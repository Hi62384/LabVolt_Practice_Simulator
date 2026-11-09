"""Bounded, no-engine structural validation for accessory source assets."""
from __future__ import annotations
import hashlib, json, math, re, struct
from pathlib import Path
from PIL import Image

ROOT=Path(__file__).resolve().parents[3]; BASE=ROOT/'assets'/'cosmetics'/'accessories'; COLOR=re.compile(r'^[0-9A-Fa-f]{6}$')
EXPECTED={'head':3,'eyewear':2,'ears':1,'neck':1,'wrist_left':1,'back':1}
BODY_EXTREMES=(.65,1.4)

def resource(value): assert value.startswith('res://') and '..' not in value; return ROOT/value[6:]
def inspect(path):
    doc=json.loads(path.read_text(encoding='utf-8')); assert doc['asset']['version']=='2.0'; blob=(path.parent/doc['buffers'][0]['uri']).read_bytes(); assert len(blob)==doc['buffers'][0]['byteLength']
    for node in doc.get('nodes',[]): assert all(v>0 for v in node.get('scale',[1,1,1])), (path,'negative/mirrored node scale')
    vertices=0; bounds=[[math.inf]*3,[-math.inf]*3]
    for primitive in doc['meshes'][0]['primitives']:
        attrs=primitive['attributes']; assert {'POSITION','NORMAL','TEXCOORD_0'} <= set(attrs); pos=doc['accessors'][attrs['POSITION']]; vertices+=pos['count']
        for i in range(3): bounds[0][i]=min(bounds[0][i],pos['min'][i]); bounds[1][i]=max(bounds[1][i],pos['max'][i])
        pview=doc['bufferViews'][pos['bufferView']]; praw=blob[pview['byteOffset']:pview['byteOffset']+pview['byteLength']]; points=list(struct.iter_unpack('<3f',praw))
        view=doc['bufferViews'][doc['accessors'][attrs['NORMAL']]['bufferView']]; raw=blob[view['byteOffset']:view['byteOffset']+view['byteLength']]; normals=list(struct.iter_unpack('<3f',raw))
        for v in normals: assert .85 < math.sqrt(sum(x*x for x in v)) < 1.15, (path,v)
        for i in range(0,len(points),3):
            a,b,c=points[i:i+3]; ab=[b[j]-a[j] for j in range(3)]; ac=[c[j]-a[j] for j in range(3)]; cross=(ab[1]*ac[2]-ab[2]*ac[1],ab[2]*ac[0]-ab[0]*ac[2],ab[0]*ac[1]-ab[1]*ac[0]); area=math.sqrt(sum(v*v for v in cross)); assert area>1e-8,(path,i)
            # The authored normal may face either side for intentionally planar rings,
            # but it must agree with the triangle plane rather than be orthogonal.
            assert abs(sum(cross[j]*normals[i][j] for j in range(3))) > area*.7, (path,i,cross,normals[i])
    assert vertices>=72 and all(math.isfinite(v) for row in bounds for v in row)
    mats={m['name'] for m in doc['materials']}; assert mats
    for mat in doc['materials']: assert 'baseColorTexture' in mat['pbrMetallicRoughness'] and 'metallicRoughnessTexture' in mat['pbrMetallicRoughness'] and 'normalTexture' in mat
    for image in doc['images']:
        p=(path.parent/image['uri']).resolve(); assert p.is_file() and BASE.resolve() in p.parents
        with Image.open(p) as im: assert im.size==(128,128)
    return hashlib.sha256(blob).hexdigest(),vertices,mats,bounds

def validate_fit_extremes(item,bounds):
    """Mirror provider math at mixed valid extremes; no engine/visual claim."""
    slot=item['slot']; user_values=(item['parameters'].get('scale',{}).get('min',1.0),item['parameters'].get('scale',{}).get('max',1.0))
    for low in BODY_EXTREMES:
        high=BODY_EXTREMES[1] if low==BODY_EXTREMES[0] else BODY_EXTREMES[0]
        for user in user_values:
            position=[0.0,0.0,0.0]
            if slot in {'head','eyewear','ears'}: scale=[user,user,user]
            elif slot=='neck': scale=[low*high*user,user,high*user]; position[1]=(low-1.0)*.30
            elif slot=='back':
                back_width=low*(1+.65*(high-1))*(1+.70*(low-1)); scale=[back_width*user,user,low*user]; position[1]=(high-1.0)*.30
            elif slot.startswith('wrist_'): scale=[high*user,user/low,high*user]; position[1]=-.405*(low-1)/low
            else: scale=[user,user,user]
            assert all(math.isfinite(v) and v>0 for v in scale),(item['id'],scale)
            transformed=[[position[i]+bounds[row][i]*scale[i] for i in range(3)] for row in range(2)]
            assert all(math.isfinite(v) for row in transformed for v in row)
            assert all(transformed[0][i] <= transformed[1][i] for i in range(3))
            # Accessories stay bounded around the toon instead of using scale as a
            # clipping workaround, even with deliberately mixed min/max sliders.
            assert max(transformed[1][i]-transformed[0][i] for i in range(3)) < 1.25,(item['id'],transformed)

def main():
    data=json.loads((BASE/'catalog.json').read_text(encoding='utf-8')); assert data['schema_version']==1 and len(data['items'])==9
    ids=set(); geometry=set(); slots={}; results=[]
    for item in data['items']:
        assert {'id','name','category','slot','scene','thumbnail','price','starter','rig','tags','conflicts','materials','parameters'} <= set(item)
        assert item['id'] not in ids and item['id'].startswith('accessory.'); ids.add(item['id']); assert item['category']=='accessories' and item['rig']=='labvolt_toon_v1'; slots[item['slot']]=slots.get(item['slot'],0)+1
        assert isinstance(item['price'],int) and item['price']>=0 and isinstance(item['starter'],bool); assert isinstance(item['tags'],list) and isinstance(item['conflicts'],list)
        scene,thumb=resource(item['scene']),resource(item['thumbnail']); assert scene.is_file() and thumb.is_file()
        with Image.open(thumb) as im: assert im.size==(384,384) and im.mode=='RGBA'
        digest,verts,mats,bounds=inspect(scene); assert digest not in geometry; geometry.add(digest); assert set(sum(item['materials'].values(),[])) <= mats
        validate_fit_extremes(item,bounds)
        for spec in item['parameters'].values():
            assert spec['type'] in {'float','int','bool','color','enum'} and 'default' in spec
            if spec['type']=='color': assert COLOR.fullmatch(spec['default'])
            if spec['type'] in {'float','int'}: assert all(math.isfinite(float(spec[k])) for k in ('default','min','max')) and spec['min']<=spec['default']<=spec['max']
            if spec['type']=='enum': assert spec['default'] in spec['values']
        results.append((item['id'],verts,bounds))
    assert slots==EXPECTED, slots
    for item in data['items']:
        if item['slot']=='head': assert 'hair_covering' in item['tags'] and 'hair_volume_high' in item['conflicts']
        if item['slot']=='back': assert 'physical_backpack_visible' in item['conflicts']
    provider=(ROOT/'scripts/avatar_cosmetics/accessories/accessory_provider.gd').read_text(encoding='utf-8')
    for token in ('FIT_MIN := 0.65','FIT_MAX := 1.4','Body/Head','Body/ArmL','Body/ArmR','sync_legacy_hair','legacy_hair.visible','duplicate(true)','set_surface_override_material','body.get("arm_length"','body.get("arm_width"','body.get("torso_width"','body.get("neck_width"','body.get("shoulders"'): assert token in provider
    assert 'Vector3(-' not in provider and 'scale = -' not in provider
    print('PASS: 9 unique accessory meshes; UV/normal/PBR streams, .65-1.4 mixed-extreme transforms, positive scales, fit seams, conflicts, thumbnails and material isolation validated')
    for item,verts,bounds in results: print(f'  {item}: {verts} vertices, bounds {bounds}')
if __name__=='__main__': main()
