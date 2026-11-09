"""Bake flat Avatar Studio card art from the catalog silhouettes."""
import json
import math
import struct
import sys
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(Path(__file__).parent / "clothing"))
from build_reference_tops import thumbnail as top_icon

BACKGROUND = "#1a202b"
HAIR = {"hair": "#49323e", "hair_highlight": "#795062", "hair_tip": "#654352"}
COLORS = {
    "gold": "#cba54e", "silver": "#a5b9c3", "dark_metal": "#506575",
    "glass": "#326078", "canvas": "#478295", "knit": "#ad5864",
    "felt": "#a48164", "leather": "#986451", "fabric": "#56728b", "accent": "#e5af3d",
}
TOP_STYLES = {
    "marina_stripe_tee": "striped_tee", "harbor_rugby": "rugby_shirt",
    "summit_quarter_zip": "quarter_zip", "campus_pocket_tee": "pocket_tee",
    "alumni_cardigan": "cardigan", "track_jacket": "campus_jacket",
    "field_jacket": "denim_jacket", "lab_coat": "denim_jacket",
}


def asset(uri):
    return ROOT / uri.removeprefix("res://")


def triangles(path):
    if path.suffix == ".glb":
        raw = path.read_bytes()
        length = struct.unpack_from("<I", raw, 12)[0]
        document = json.loads(raw[20:20+length])
        buffer = raw[28+length:]
    else:
        document = json.loads(path.read_text(encoding="utf-8"))
        buffer = (path.parent / document["buffers"][0]["uri"]).read_bytes()

    def accessor(index, code):
        spec = document["accessors"][index]
        view = document["bufferViews"][spec["bufferView"]]
        fmt = struct.Struct("<"+code)
        start = view.get("byteOffset",0)+spec.get("byteOffset",0)
        stride = view.get("byteStride",fmt.size)
        return [fmt.unpack_from(buffer,start+i*stride) for i in range(spec["count"])]

    for mesh in document.get("meshes",[]):
        for primitive in mesh["primitives"]:
            points = accessor(primitive["attributes"]["POSITION"],"3f")
            if "indices" in primitive:
                index = primitive["indices"]
                code = {5121:"B",5123:"H",5125:"I"}[document["accessors"][index]["componentType"]]
                points = [points[i] for i, in accessor(index,code)]
            material = document["materials"][primitive.get("material",0)].get("name","")
            for i in range(0,len(points)-2,3):
                yield material, points[i:i+3]


def flat_projection(draw, mesh, palette, project, fixed=None):
    faces = []
    for material, points in mesh:
        projected = [project(*point) for point in points]
        faces.append((sum(p[2] for p in projected), material, projected))
    if not faces:
        return
    if fixed is None:
        x = [p[0] for _,_,face in faces for p in face]
        y = [p[1] for _,_,face in faces for p in face]
        fixed = ((min(x)+max(x))/2,(min(y)+max(y))/2,266/max(max(x)-min(x),max(y)-min(y),.001))
    x,y,scale = fixed
    for _, material, face in sorted(faces,key=lambda face:face[0]):
        draw.polygon([(192+(u-x)*scale,177+(v-y)*scale) for u,v,_ in face],
                     fill=palette.get(material,palette.get("", "#8ca4ad")))


def draw_face(draw):
    draw.ellipse((106,95,278,294), fill="#ddb095", outline="#f1c9aa", width=3)
    for x in (150,224):
        draw.ellipse((x,165,x+11,179),fill="#384957")
    draw.arc((169,193,215,228), 15, 165, fill="#875568", width=4)


def bottoms(draw, style, primary, accent):
    if "skirt" in style:
        draw.polygon([(127,64),(257,64),(303,302),(81,302)],fill=primary,outline="#e8ebed",width=3)
        for x in (113,147,192,237,271):
            draw.line((192+(x-192)*.56,84,x,292),fill=accent,width=3)
        return
    short = any(word in style for word in ("short","bermuda"))
    hem = 220 if short else 312
    draw.polygon([(94,64),(290,64),(280,hem),(208,hem),(192,137),(176,hem),(104,hem)],
                 fill=primary,outline="#e8ebed",width=3)
    draw.line((103,85,280,85),fill=accent,width=4)
    if any(word in style for word in ("cargo","tech","camo")):
        for x in (113,226):
            draw.rounded_rectangle((x,120,x+45,182),5,outline=accent,width=4)
    if any(word in style for word in ("track","jogger","athletic","scholar")):
        for x in (115,269):
            draw.line((x,92,x,hem-13),fill=accent,width=5)
    if "ripped" in style:
        for x in (125,216):
            draw.rectangle((x,187,x+43,199),fill="#dbc4aa")
    if "pajama" in style:
        for y in range(115,hem-8,26):
            for x in (114,216):
                draw.line((x,y,x+52,y),fill=accent,width=4)


def main():
    for group in ("clothing","faces_hair","footwear","accessories"):
        data=json.loads((ROOT/"assets/cosmetics"/group/"catalog.json").read_text(encoding="utf-8"))
        for item in data["items"]:
            category=item["category"]
            if category=="faces":
                continue
            destination=asset(item["thumbnail"])
            style=destination.stem.removeprefix("reference_")
            params=item.get("parameters",{})
            primary=str(params.get("primary_color",params.get("base_color",{})).get("default","67899d")).lstrip("#")
            accent=str(params.get("detail_color",params.get("secondary_color",params.get("accent_color",{}))).get("default","b5cbd0")).lstrip("#")
            if category=="tops":
                top_icon(destination.stem,TOP_STYLES.get(style,style),item["name"],primary,accent)
                continue
            image=Image.new("RGB",(384,384),BACKGROUND)
            draw=ImageDraw.Draw(image)
            if category=="bottoms":
                bottoms(draw,style,"#"+primary,"#"+accent)
            else:
                mesh=list(triangles(asset(item["scene"])))
                if category in ("hair","facial_hair"):
                    draw_face(draw)
                    if category=="hair":
                        front=[(mat,pts) for mat,pts in mesh if sum(p[2] for p in pts)>-.09 or all(abs(p[0])>.16 for p in pts)]
                        flat_projection(draw,front,{**HAIR,"":"#49323e"},lambda x,y,z:(x+.15*z,-y,z),(0,-.045,440))
                    elif not item["id"].endswith(".clean"):
                        flat_projection(draw,mesh,{**HAIR,"":"#49323e"},lambda x,y,z:(x,-y,z),(0,-.045,440))
                elif category=="shoes":
                    palette={"":"#"+primary}
                    for region, value in (("primary_regions","#"+primary),("secondary_regions","#"+accent),("sole_regions","#b9c8cb")):
                        for material in item.get("materials",{}).get(region,[]):
                            palette[material]=value
                    flat_projection(draw,mesh,palette,lambda x,y,z:(z+.35*x,-y+.12*x,x))
                else:
                    flat_projection(draw,mesh,COLORS,lambda x,y,z:(x+.32*z,-y+.26*z,z-.32*x))
            image.save(destination)


if __name__ == "__main__":
    main()
