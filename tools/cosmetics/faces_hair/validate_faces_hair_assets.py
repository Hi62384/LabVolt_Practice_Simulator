"""Bounded, engine-free structural validation for face/hair collectibles."""
from __future__ import annotations

import hashlib
import json
import math
import re
import struct
from pathlib import Path

from PIL import Image

ROOT=Path(__file__).resolve().parents[3]
BASE=ROOT/"assets"/"cosmetics"/"faces_hair"
COLOR=re.compile(r"^[0-9A-Fa-f]{6}$")
REQUIRED={"id","name","category","slot","scene","thumbnail","price","starter","rig","parameters","materials","tags","conflicts"}

def resource(value):
    assert value.startswith("res://") and ".." not in value, value
    return ROOT/value[6:]

def values(doc,blob,accessor):
    acc=doc["accessors"][accessor]; view=doc["bufferViews"][acc["bufferView"]]; size={"VEC2":2,"VEC3":3}[acc["type"]]
    off=view.get("byteOffset",0)+acc.get("byteOffset",0); stride=view.get("byteStride",size*4)
    return [struct.unpack_from("<"+"f"*size,blob,off+i*stride) for i in range(acc["count"])]

def inspect(path,category):
    doc=json.loads(path.read_text(encoding="utf-8")); assert doc["asset"]["version"]=="2.0"
    # All models are authored at Body/Head local origin; the provider must not
    # need an unexplained corrective attachment transform.
    assert "translation" not in doc["nodes"][0] and "matrix" not in doc["nodes"][0]
    blob=(path.parent/doc["buffers"][0]["uri"]).read_bytes(); assert len(blob)==doc["buffers"][0]["byteLength"]
    vertices=0; positive=0; triangles=0; xyz=[]
    for primitive in doc["meshes"][0]["primitives"]:
        attrs=primitive["attributes"]; assert {"POSITION","NORMAL","TEXCOORD_0"}<=set(attrs); assert primitive.get("mode",4)==4
        pos=values(doc,blob,attrs["POSITION"]); nor=values(doc,blob,attrs["NORMAL"]); uv=values(doc,blob,attrs["TEXCOORD_0"])
        assert len(pos)==len(nor)==len(uv) and len(pos)%3==0; vertices+=len(pos); xyz+=pos
        assert all(all(math.isfinite(v) for v in p) for p in pos+nor+uv)
        assert all(.85 <= math.sqrt(sum(v*v for v in n)) <= 1.15 for n in nor)
        assert all(-.001<=u<=1.001 and -.001<=v<=1.001 for u,v in uv)
        for i in range(0,len(pos),3):
            a,b,c=pos[i:i+3]; ab=tuple(b[j]-a[j] for j in range(3)); ac=tuple(c[j]-a[j] for j in range(3)); cross=(ab[1]*ac[2]-ab[2]*ac[1],ab[2]*ac[0]-ab[0]*ac[2],ab[0]*ac[1]-ab[1]*ac[0]); area=math.sqrt(sum(v*v for v in cross)); assert area>1e-10
            avg=tuple(sum(n[j] for n in nor[i:i+3])/3 for j in range(3)); positive += sum(cross[j]*avg[j] for j in range(3))>0; triangles+=1
    assert vertices>=100 and positive/triangles>.98,(path,positive,triangles)
    mins=[min(p[i] for p in xyz) for i in range(3)]; maxs=[max(p[i] for p in xyz) for i in range(3)]
    assert mins[0]>=-.36 and maxs[0]<=.36 and mins[1]>=-.55 and maxs[1]<=.45 and mins[2]>=-.32 and maxs[2]<=.25,(path,mins,maxs)
    if category=="faces": assert mins[2]>=.14 and maxs[2]<=.225,(path,mins,maxs)
    mats={m["name"] for m in doc["materials"]}; assert mats
    for mat in doc["materials"]:
        pbr=mat["pbrMetallicRoughness"]; assert "baseColorTexture" in pbr and "metallicRoughnessTexture" in pbr and "normalTexture" in mat
    for image in doc["images"]:
        target=(path.parent/image["uri"]).resolve(); assert target.is_file()
        with Image.open(target) as texture: assert texture.size==(128,128)
    return hashlib.sha256(blob).hexdigest(),vertices,mins,maxs,mats

def main():
    catalog=json.loads((BASE/"catalog.json").read_text(encoding="utf-8")); assert catalog["schema_version"]==1
    items=catalog["items"]; assert len(items)==19
    counts={"faces":0,"hair":0,"facial_hair":0}; ids=set(); scenes=set(); geometry=set(); total_vertices=0
    for item in items:
        assert REQUIRED<=set(item); assert item["id"] not in ids; ids.add(item["id"])
        category=item["category"]; assert category in counts; counts[category]+=1
        assert item["slot"]=={"faces":"face","hair":"hair","facial_hair":"facial_hair"}[category]
        assert item["rig"]=="labvolt_toon_v1" and isinstance(item["price"],int) and item["price"]>=0 and isinstance(item["starter"],bool)
        scene=resource(item["scene"]); thumb=resource(item["thumbnail"]); assert scene.is_file() and thumb.is_file(); scenes.add(scene)
        with Image.open(thumb) as image: assert image.size==(384,384)
        all_scenes={"default":item["scene"]}|item.get("variants",{})
        checked_paths=set()
        for variant,path_value in all_scenes.items():
            if path_value in checked_paths: continue
            checked_paths.add(path_value)
            path=resource(path_value); assert path.is_file(); scenes.add(path)
            digest,vertices,mins,maxs,mats=inspect(path,category); total_vertices+=vertices
            # Distinct variants and items must have distinct baked buffers.
            assert digest not in geometry,(item["id"],variant); geometry.add(digest)
        for name,spec in item["parameters"].items():
            assert spec["type"] in {"float","int","bool","color","enum"} and "default" in spec
            if spec["type"]=="color": assert COLOR.fullmatch(spec["default"])
            if spec["type"] in ("float","int"): assert math.isfinite(spec["min"]) and math.isfinite(spec["max"]) and spec["min"]<=spec["default"]<=spec["max"]
            if spec["type"]=="enum": assert spec["default"] in spec["values"] and set(spec["values"])==set(item.get("variants",{}))
    assert counts=={"faces":6,"hair":7,"facial_hair":6} and len(scenes)==24
    provider=(ROOT/"scripts/avatar_cosmetics/faces_hair/faces_hair_provider.gd").read_text(encoding="utf-8")
    for token in ('Body/Head','duplicate(true)','set_surface_override_material','"length"','_hide_legacy','detach_from_avatar','_restore_legacy','LEGACY_STATE_META'):
        assert token in provider,token
    for stale in ('MIN_FIT','MAX_FIT','1.0 / head_width','1.0 / head_height'):
        assert stale not in provider,stale
    # The real head node supplies both overall head size and non-uniform shape.
    # A local point therefore remains in the same proportional location across
    # all mixed core extremes when no inverse child scaling is introduced.
    local=(.18,.10,.16)
    ratios=[]
    for head in (.65,1.0,1.4):
        for width in (.65,1.4):
            for height in (.65,1.4):
                world=(local[0]*head*width,local[1]*head*height,local[2]*head)
                envelope=(.24*head*width,.225*head*height,.20*head)
                ratios.append(tuple(world[i]/envelope[i] for i in range(3)))
    assert all(all(abs(ratios[0][i]-r[i])<1e-9 for i in range(3)) for r in ratios)
    accessories=json.loads((ROOT/"assets/cosmetics/accessories/catalog.json").read_text(encoding="utf-8"))["items"]
    headwear=[i for i in accessories if i.get("slot")=="head"]
    assert headwear and all("hair_volume_high" in i.get("conflicts",[]) for i in headwear)
    bulky={i["id"] for i in items if "hair_volume_high" in i.get("tags",[])}
    assert bulky=={"hair.curly","hair.bun"},bulky
    print(f"PASS: {len(items)} definitions, {len(scenes)} unique baked models, {total_vertices} referenced vertices")
    print("  6 faces, 7 hair silhouettes, 6 facial-hair choices; UV/PBR/normals/winding/bounds/provider seam checked")

if __name__=="__main__": main()
