"""No-engine structural checks for the footwear quality slice."""
from __future__ import annotations

import hashlib
import json
import math
import re
import struct
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[3]
BASE = ROOT / "assets" / "cosmetics" / "footwear"
CATALOG = BASE / "catalog.json"
REQUIRED = {"id","name","category","slot","scene","thumbnail","price","starter","rig","parameters","materials"}
COLOR = re.compile(r"^[0-9A-Fa-f]{6}$")
CORE_SOURCE = ROOT / "scripts" / "avatar_cosmetics" / "core" / "avatar_core.gd"


def resource_path(value: str) -> Path:
    assert value.startswith("res://"), value
    return ROOT / value[6:]


def inspect_gltf(path: Path) -> tuple[str, int, set[str], tuple[list[float],list[float]]]:
    doc=json.loads(path.read_text(encoding="utf-8")); assert doc["asset"]["version"] == "2.0"
    blob=(path.parent/doc["buffers"][0]["uri"]).read_bytes(); assert len(blob)==doc["buffers"][0]["byteLength"]
    vertices=0; bounds_min=[float("inf")]*3; bounds_max=[float("-inf")]*3
    for primitive in doc["meshes"][0]["primitives"]:
        attrs=primitive["attributes"]; assert {"POSITION","NORMAL","TEXCOORD_0"} <= set(attrs)
        vertices += doc["accessors"][attrs["POSITION"]]["count"]
        pos=doc["accessors"][attrs["POSITION"]]
        bounds_min=[min(bounds_min[i],pos["min"][i]) for i in range(3)]
        bounds_max=[max(bounds_max[i],pos["max"][i]) for i in range(3)]
    assert vertices >= 100, (path, vertices)
    materials={m["name"] for m in doc["materials"]}; assert len(materials) >= 2
    for mat in doc["materials"]:
        pbr=mat["pbrMetallicRoughness"]; assert "baseColorTexture" in pbr and "metallicRoughnessTexture" in pbr
        assert "normalTexture" in mat
    for image in doc["images"]:
        image_path=(path.parent/image["uri"]).resolve(); assert image_path.is_file(), image_path
        with Image.open(image_path) as texture: assert texture.size == (128,128)
    return hashlib.sha256(blob).hexdigest(),vertices,materials,(bounds_min,bounds_max)


def transformed_bounds(bounds, fit, feet, leg_length, leg_x):
    lo,hi=bounds; scale=fit["scale"]; offset=fit["offset"]
    vertical=(1.0+(feet-1.0)*.32)/leg_length
    out_lo=[leg_x+lo[0]*feet*scale[0], (-.74+offset[1]+lo[1]*vertical*scale[1])*leg_length, .045+offset[2]+lo[2]*feet*scale[2]]
    out_hi=[leg_x+hi[0]*feet*scale[0], (-.74+offset[1]+hi[1]*vertical*scale[1])*leg_length, .045+offset[2]+hi[2]*feet*scale[2]]
    return out_lo,out_hi


def main() -> None:
    core=CORE_SOURCE.read_text(encoding="utf-8")
    body_min=float(re.search(r"const BODY_MIN :=\s*([.0-9]+)",core).group(1))
    body_max=float(re.search(r"const BODY_MAX :=\s*([.0-9]+)",core).group(1))
    assert body_min == .65 and body_max == 1.4
    data=json.loads(CATALOG.read_text(encoding="utf-8")); assert data["schema_version"] == 1
    items=data["items"]; assert len(items) == 6
    ids=set(); geometry=set(); totals=[]
    for item in items:
        assert REQUIRED <= set(item); assert item["id"] not in ids; ids.add(item["id"])
        assert item["category"] == "shoes" and item["slot"] == "footwear" and item["rig"] == "labvolt_toon_v1"
        assert isinstance(item["price"],int) and item["price"] >= 0
        scene=resource_path(item["scene"]); thumb=resource_path(item["thumbnail"]); assert scene.is_file() and thumb.is_file()
        with Image.open(thumb) as image: assert image.size == (384,384)
        digest,vertices,material_names,bounds=inspect_gltf(scene); assert digest not in geometry; geometry.add(digest)
        declared=set(sum(item["materials"].values(),[])); assert declared <= material_names
        fit=item.get("fit",{}); assert len(fit.get("scale",[]))==3 and len(fit.get("offset",[]))==3
        # Static transform tests use opposing legal extremes. They verify the
        # actual glTF bounds and attachment math, not rendered visual clearance.
        cases=((body_min,body_max,body_min),(body_max,body_min,body_max),(1.0,1.0,1.0))
        fit_evidence=[]
        for feet,leg_length,width in cases:
            left=transformed_bounds(bounds,fit,feet,leg_length,-.12*width)
            right=transformed_bounds(bounds,fit,feet,leg_length,.12*width)
            assert all(abs((right[n][i]-left[n][i])-.24*width)<1e-6 for n in range(2) for i in [0])
            assert all(abs(right[n][i]-left[n][i])<1e-6 for n in range(2) for i in [1,2])
            assert all(math.isfinite(v) for side in (left,right) for bound in side for v in bound)
            fit_evidence.append((feet,leg_length,round(left[0][1],3),round(left[1][1],3)))
        for schema in item["parameters"].values():
            assert schema["type"] in {"float","int","bool","color","enum"} and "default" in schema
            if schema["type"] == "color": assert COLOR.fullmatch(schema["default"])
            if schema["type"] == "enum": assert schema["default"] in schema["values"]
        totals.append((item["id"],vertices,len(material_names),fit_evidence))
    provider=(ROOT/"scripts/avatar_cosmetics/footwear/footwear_provider.gd").read_text(encoding="utf-8")
    for token in ("LegL","LegR","FOOT_CENTER","AvatarCore.BODY_MIN","AvatarCore.BODY_MAX","validate_fit", "duplicate(true)","set_surface_override_material","body.get(\"feet\"", "body.get(\"leg_length\""):
        assert token in provider, token
    assert "MIN_FIT" not in provider and "MAX_FIT" not in provider and "clampf(float(body.get(\"feet\"" not in provider
    assert provider.index("duplicate(true)") < provider.index("set_surface_override_material")
    print("PASS: 6 unique footwear assets, catalog contract, PBR references, UV streams, thumbnails, and adapter seam")
    for item_id,vertices,materials,evidence in totals: print(f"  {item_id}: {vertices} vertices, {materials} regions; extreme Y bounds {evidence[:2]}")


if __name__ == "__main__": main()
