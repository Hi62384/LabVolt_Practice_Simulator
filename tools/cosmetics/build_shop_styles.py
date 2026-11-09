"""Bake premium Harbor Outfitters models and matching flat thumbnails."""
from copy import deepcopy
import json

from PIL import Image, ImageDraw

from accessories import build_accessory_assets as accessories
from clothing import build_clothing_assets as clothing
from faces_hair import build_faces_hair_assets as heads
from footwear import build_footwear_assets as footwear
from build_flat_icons import (
    BACKGROUND, COLORS, HAIR, ROOT, asset, bottoms, draw_face, flat_projection,
    top_icon, triangles,
)


def add(group, template, item_id, key, name, price, rarity):
    path = ROOT / "assets/cosmetics" / group / "catalog.json"
    data = json.loads(path.read_text(encoding="utf-8"))
    item = deepcopy(next(entry for entry in data["items"] if entry["id"] == template))
    base = f"res://assets/cosmetics/{group}"
    item.update(id=item_id, name=name, price=price, rarity=rarity, starter=False,
                scene=f"{base}/models/{key}.gltf", thumbnail=f"{base}/thumbnails/{key}.png")
    item.pop("variants", None)
    item.get("parameters", {}).pop("length", None)
    data["items"] = [entry for entry in data["items"] if entry["id"] != item_id] + [item]
    path.write_text(json.dumps(data, indent=2), encoding="utf-8")
    return item


def icon(item, project, palette, face=False):
    image = Image.new("RGB", (384, 384), BACKGROUND)
    draw = ImageDraw.Draw(image)
    if face:
        draw_face(draw)
    flat_projection(draw, list(triangles(asset(item["scene"]))), palette,
                    project, (0, -.045, 440) if face else None)
    image.save(asset(item["thumbnail"]))


def head_styles():
    for key, name, rarity, price in [
        ("comet_crest", "Comet Crest", "epic", 540),
        ("crown_braids", "Crown Braids", "legendary", 980),
    ]:
        mesh = heads.Mesh()
        heads.scalp(mesh, "hair", .020, .017, .071, "crop")
        if key == "comet_crest":
            for i in range(7):
                heads.swept_lock(mesh, "hair_highlight" if i in (2, 5) else "hair",
                                 (-.12+i*.031,.22,.121),(.06+i*.015,.35,.10),
                                 (.18+i*.014,.31,-.12),.036)
        else:
            for side in (-1, 1):
                for i in range(10):
                    heads.swept_lock(mesh, "hair_highlight" if i % 3 == 0 else "hair",
                                     (side*.11,.26,.12-i*.025),(side*.23,.24,.115-i*.024),
                                     (side*.205,.17,.10-i*.025),.039,.021)
        model = "hair_" + key
        heads.write_gltf(model, name, mesh)
        item = add("faces_hair", "hair.crop", "hair."+key, model, name, price, rarity)
        icon(item, lambda x,y,z: (x+.15*z,-y,z), HAIR, True)

    for key, name, rarity, price in [
        ("duelist_whiskers", "Duelist Whiskers", "epic", 510),
        ("twin_braid_beard", "Twin Braid Beard", "legendary", 990),
    ]:
        mesh = heads.Mesh()
        for side in (-1, 1):
            if key == "duelist_whiskers":
                mesh.tube("hair", [(0,-.081,.007),(side*.052,-.087,.015),
                                   (side*.099,-.064,.019),(side*.127,-.037,.025)],
                          [.010,.015,.010,.002])
                mesh.tube("hair", [(side*.040,-.163,.013),(side*.024,-.181,.022),
                                   (side*.005,-.198,.028)], [.012,.013,.003])
            else:
                for i in range(8):
                    x = side*(.025+i*.0035)
                    y = -.150-i*.020
                    mesh.ellipsoid("hair_highlight" if i % 2 else "hair",
                                   (x,y,.026+i*.009),(.034-i*.002,.024,.023),8,14)
        model = "facial_" + key
        heads.write_gltf(model, name, heads.seat_on_face(mesh))
        item = add("faces_hair", "facial_hair.toothbrush", "facial_hair."+key, model, name, price, rarity)
        icon(item, lambda x,y,z: (x,-y,z), HAIR, True)


def clothing_styles():
    name = "Signal Racing Jacket"
    parts = clothing.jersey_style("canvas", .41, "training", True)
    for x in (-.085,.085):
        parts["Torso"].box("lining",(x,1.22,.154),(.08,.037,.014))
    for side in ("SleeveL","SleeveR"):
        parts[side].frustum("lining",-.29,-.23,.090,.099,.093,.104)
    clothing.write_model("signal_racing_jacket",name,parts)
    item = add("clothing","tops.campus_track_jacket","tops.signal_racing_jacket",
               "signal_racing_jacket",name,560,"epic")
    top_icon(asset(item["thumbnail"]).stem,"campus_jacket",name,"204453","ffb94f")

    name = "Foundry Armored Cargos"
    parts = clothing.utility_bottoms("cargo")
    for leg in parts.values():
        leg.box("rib",(0,-.34,.102),(.174,.125,.027))
        leg.box("stitch",(0,-.39,.119),(.146,.013,.008))
    clothing.write_model("foundry_armored_cargos",name,parts)
    item = add("clothing","bottoms.workshop_cargos","bottoms.foundry_armored_cargos",
               "foundry_armored_cargos",name,850,"legendary")
    image = Image.new("RGB",(384,384),BACKGROUND)
    draw = ImageDraw.Draw(image)
    bottoms(draw,"cargo","#323843","#dfa65d")
    for x in (119,218):
        draw.rounded_rectangle((x,198,x+49,232),6,fill="#52636f",outline="#dfa65d",width=3)
    image.save(asset(item["thumbnail"]))


def finishing_styles():
    name = "Meteor Platform Boots"
    mesh = footwear.work_boot()
    mesh.box("rubber",(0,-.078,.01),(.232,.044,.38),.014)
    for x in (-.108,.108):
        for z in (-.09,.01,.11):
            mesh.box("metal",(x,-.067,z),(.021,.024,.055))
    footwear.write_gltf("meteor_platform",name,mesh,["leather","leather_dark","rubber","metal","canvas"])
    item = add("footwear","shoes.foundry_boot","shoes.meteor_platform","meteor_platform",name,920,"legendary")
    icon(item,lambda x,y,z: (z+.35*x,-y+.12*x,x),
         {"leather":"#81504b","leather_dark":"#513a3d","rubber":"#263647","metal":"#df9c65","canvas":"#d5c2a8"})

    name = "Sunburst Frames"
    mesh = accessories.round_glasses()
    for side in (-1,1):
        mesh.ring("gold",(side*.085,.016,.187),.071,.062,"z",32)
        for i in range(3):
            mesh.box("gold",(side*(.142+i*.010),.066-i*.013,.185),(.026,.009,.009))
    accessories.write("sunburst_frames",name,mesh,["dark_metal","gold"])
    item = add("accessories","accessory.face.round_study","accessory.face.sunburst_frames",
               "sunburst_frames",name,530,"epic")
    icon(item,lambda x,y,z: (x+.32*z,-y+.26*z,z-.32*x),COLORS)


if __name__ == "__main__":
    head_styles()
    clothing_styles()
    finishing_styles()
