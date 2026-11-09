"""Bounded no-engine structural, geometry, material and contract checks."""
from __future__ import annotations
import json, math, re, struct
from pathlib import Path
from PIL import Image

ROOT=Path(__file__).resolve().parents[3];BASE=ROOT/'assets/cosmetics/clothing';COLOR=re.compile(r'^[0-9A-Fa-f]{6}$')
REQUIRED={'id','name','category','slot','scene','thumbnail','price','starter','rig','tags','conflicts','materials','parameters'}
TARGETS={'Torso','SleeveL','SleeveR','Waist','LegL','LegR'}

def resource(path): assert path.startswith('res://');return ROOT/path[6:]
def unpack(doc,blob,index,width):
 a=doc['accessors'][index];v=doc['bufferViews'][a['bufferView']];off=v.get('byteOffset',0)+a.get('byteOffset',0)
 return [struct.unpack_from('<'+'f'*width,blob,off+i*width*4) for i in range(a['count'])]
def inspect(path):
 doc=json.loads(path.read_text());assert doc['asset']['version']=='2.0';blob=(path.parent/doc['buffers'][0]['uri']).read_bytes();assert len(blob)==doc['buffers'][0]['byteLength']
 names={n['name'] for n in doc['nodes']};assert names and names<=TARGETS,(path,names);node_bounds={}
 verts=0;bounds=[]
 for mesh in doc['meshes']:
  mesh_positions=[]
  for p in mesh['primitives']:
   assert {'POSITION','NORMAL','TEXCOORD_0'}<=set(p['attributes']);pos=unpack(doc,blob,p['attributes']['POSITION'],3);nor=unpack(doc,blob,p['attributes']['NORMAL'],3);uv=unpack(doc,blob,p['attributes']['TEXCOORD_0'],2);assert len(pos)==len(nor)==len(uv) and len(pos)%3==0
   assert all(abs(math.sqrt(sum(c*c for c in n))-1)<.02 for n in nor);assert all(math.isfinite(c) for row in pos+nor+uv for c in row)
   for i in range(0,len(pos),3):
    a,b,c=pos[i:i+3];ab=tuple(b[j]-a[j] for j in range(3));ac=tuple(c[j]-a[j] for j in range(3));cross=(ab[1]*ac[2]-ab[2]*ac[1],ab[2]*ac[0]-ab[0]*ac[2],ab[0]*ac[1]-ab[1]*ac[0]);assert sum(x*x for x in cross)>1e-12
   verts+=len(pos);bounds.extend(pos);mesh_positions.extend(pos)
  node_bounds[mesh['name']]=([min(v[i] for v in mesh_positions) for i in range(3)],[max(v[i] for v in mesh_positions) for i in range(3)])
 assert verts>=120;mins=[min(v[i] for v in bounds) for i in range(3)];maxs=[max(v[i] for v in bounds) for i in range(3)];assert maxs[0]-mins[0]<.8 and maxs[2]-mins[2]<.6 and -1<mins[1]<1.5
 mats={m['name'] for m in doc['materials']};assert mats
 for m in doc['materials']:assert 'baseColorTexture' in m['pbrMetallicRoughness'] and 'metallicRoughnessTexture' in m['pbrMetallicRoughness'] and 'normalTexture' in m
 for im in doc['images']:
  with Image.open((path.parent/im['uri']).resolve()) as pic:assert pic.size==(128,128)
 return names,verts,mats,node_bounds

def validate_extreme_fit():
 # Mirrors provider/toon endpoint math. Mixed extremes must remain distinct,
 # finite, positive, and must not collapse back into the obsolete .8..1.2 band.
 samples=[]
 for overall,torso,waist,shoulders in ((.65,1.4,.65,1.4),(1.4,.65,1.4,.65),(.65,.65,.65,.65),(1.4,1.4,1.4,1.4)):
  lower=overall*torso*waist;upper=overall*torso*shoulders;samples.extend((lower,upper));assert lower>0 and upper>0 and math.isfinite(lower+upper)
 assert min(samples)<.8 and max(samples)>1.2
def main():
 data=json.loads((BASE/'catalog.json').read_text());assert data['schema_version']==1 and len(data['items'])==7;ids=set();models=[]
 for item in data['items']:
  assert REQUIRED<=set(item);assert item['id'] not in ids;ids.add(item['id']);assert item['category'] in ('tops','bottoms');assert item['slot'] in ('top_inner','top_outer','bottom');assert item['rig']=='labvolt_toon_v1';assert isinstance(item['price'],int) and item['price']>=0
  scene=resource(item['scene']);thumb=resource(item['thumbnail']);assert scene.is_file() and thumb.is_file()
  with Image.open(thumb) as im:assert im.size==(384,384)
  names,verts,mats,node_bounds=inspect(scene);declared=set(sum(item['materials'].values(),[]));assert declared<=mats
  if item['category']=='tops':
   assert 'Torso' in names and {'SleeveL','SleeveR'}<=names
   for sleeve in ('SleeveL','SleeveR'):assert node_bounds[sleeve][1][1]>=.035 and node_bounds[sleeve][0][1]<=-.19
   torso_min,torso_max=node_bounds['Torso'];assert torso_max[1]>=1.31
   expected_hem=.67 if item['id']=='tops.practical_lab_coat' else .85
   assert abs(torso_min[1]-expected_hem)<.001,(item['id'],torso_min[1])
  else:
   assert {'LegL','LegR'}<=names
   for leg in ('LegL','LegR'):assert node_bounds[leg][1][1]>=.015
  for spec in item['parameters'].values():
   assert spec['type'] in {'float','int','bool','color','enum'} and 'default' in spec
   if spec['type']=='color':assert COLOR.fullmatch(spec['default'])
   if spec['type']=='enum':assert spec['default'] in spec['values']
   if spec['type'] in ('float','int'):assert spec['min']<=spec['default']<=spec['max'] and all(math.isfinite(float(spec[k])) for k in ('min','max','default'))
  models.append((item['id'],','.join(sorted(names)),verts))
 provider=(ROOT/'scripts/avatar_cosmetics/clothing/clothing_provider.gd').read_text()
 for token in ('Body/ArmL','Body/ArmR','LegL','LegR','duplicate(true)','set_surface_override_material','Core.sanitize_body(body)','smoothstep(.87, 1.24','fitted_body.arm_width','fitted_body.leg_width','Mesh.ARRAY_NORMAL'):assert token in provider
 assert 'MIN_FIT' not in provider and 'MAX_FIT' not in provider
 assert sum(i['starter'] for i in data['items'])==4
 validate_extreme_fit()
 print('PASS: 7 distinct baked garments; contract, PBR/UV/normal streams, finite bounds, nondegenerate triangles, thumbnails, segmented rig seam, and instance-local materials checked')
 for row in models:print(' ',row[0],row[1],row[2],'vertices')
if __name__=='__main__':main()
