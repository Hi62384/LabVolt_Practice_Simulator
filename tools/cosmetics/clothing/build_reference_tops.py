"""Bake the fifteen tops from the Avatar Studio reference sheet.

Run as asset production only; older catalog definitions and save IDs are kept.
"""
import copy
import json
from PIL import Image, ImageDraw

from build_clothing_assets import (BASE, THUMBS, hoodie, sleeve, tee, torso, write_model)


STYLES = [
    ("fitted_tee", "Fitted Tee", "top_inner", "387E86", ""),
    ("pocket_tee", "Pocket Tee", "top_inner", "314969", "D6A24B"),
    ("striped_tee", "Striped Tee", "top_inner", "E9E2D0", "314969"),
    ("long_sleeve_shirt", "Long-Sleeve Shirt", "top_inner", "8D4356", ""),
    ("rugby_shirt", "Rugby Shirt", "top_inner", "244E52", "E9E2D0"),
    ("hoodie", "Hoodie", "top_outer", "77508D", "E9E2D0"),
    ("layered_hoodie", "Layered Hoodie", "top_outer", "334153", "E9E2D0"),
    ("cardigan", "Cardigan", "top_outer", "9A4558", "D7BE87"),
    ("sweater", "Sweater", "top_inner", "E9E2D0", "D7BE87"),
    ("quarter_zip", "Quarter-Zip", "top_inner", "304767", "D6A24B"),
    ("polo_shirt", "Polo Shirt", "top_inner", "234A41", "E9E2D0"),
    ("flannel_shirt", "Flannel Shirt", "top_outer", "A96F32", "314969"),
    ("denim_jacket", "Denim Jacket", "top_outer", "4F7395", "E9E2D0"),
    ("varsity_jacket", "Varsity Jacket", "top_outer", "243453", "E9E2D0"),
    ("campus_jacket", "Campus Jacket", "top_outer", "D9DDC7", "396957"),
]


def build(style):
    if style == "fitted_tee": return tee()
    if style == "hoodie": return hoodie()
    if style == "layered_hoodie":
        parts = hoodie()
        parts["Torso"].box("coat", (0, 1.05, .157), (.33, .42, .012))
        return parts
    long = style not in ("pocket_tee", "striped_tee", "polo_shirt")
    mat = "denim" if style == "denim_jacket" else "canvas" if style in ("flannel_shirt", "varsity_jacket", "campus_jacket") else "fleece" if style in ("cardigan", "sweater", "quarter_zip") else "jersey"
    bands = {"striped_tee": [(y,y+.026,"rib") for y in (.94,1.02,1.10,1.18,1.25)],
             "rugby_shirt": [(1.05,1.15,"lining")],
             "flannel_shirt": [(y,y+.012,"rib") for y in (.93,1.025,1.12,1.215)],
             "sweater": [(.858,.895,"rib")], "denim_jacket": [(.855,.89,"lining")],
             "varsity_jacket": [(.855,.89,"rib")]}
    parts = {"Torso": torso(mat,bands=bands.get(style,())), "SleeveL": sleeve(mat, .40 if long else .20), "SleeveR": sleeve(mat, .40 if long else .20)}
    front = parts["Torso"]
    if style == "pocket_tee": front.box("lining", (-.115, 1.164, .154), (.073, .077, .012))
    elif style == "rugby_shirt":
        front.frustum("coat", 1.278, 1.33, .165, .108, .13, .087)
    elif style == "cardigan":
        for x in (-.033, .033): front.box("lining", (x, 1.075, .157), (.025, .4, .012))
        for y in (.93, 1.005, 1.08, 1.155): front.box("metal", (0, y, .171), (.015, .015, .01))
        for x in (-.17, .17): front.box("rib", (x, .95, .155), (.085, .105, .014))
    elif style == "sweater":
        for x in (-.13, -.065, 0, .065, .13):
            front.welt("stitch", [(x-.012, .89, .152), (x+.013, 1.02, .158), (x-.012, 1.15, .157), (x+.013, 1.26, .148)], .004)
    elif style == "quarter_zip":
        front.frustum("rib", 1.27, 1.34, .162, .105, .13, .086)
        front.box("metal", (0, 1.236, .155), (.012, .145, .012))
        front.box("lining", (-.14, 1.17, .151), (.045, .026, .012))
    elif style == "polo_shirt":
        front.frustum("coat", 1.277, 1.332, .164, .109, .133, .086)
        front.box("lining", (0, 1.245, .151), (.019, .13, .01))
        for y in (1.21, 1.25, 1.29): front.box("metal", (0, y, .162), (.009, .009, .008))
    elif style == "flannel_shirt":
        for x in (-.175, -.08, .08, .175): front.box("rib", (x, 1.08, .159), (.018, .38, .01))
        front.box("coat", (0, 1.08, .169), (.015, .40, .012))
    elif style == "denim_jacket":
        front.box("lining", (0, 1.075, .166), (.018, .4, .012))
        for x in (-.157, .157):
            front.box("lining", (x, 1.17, .153), (.09, .085, .014))
            front.box("metal", (x, 1.17, .164), (.013, .013, .009))
    elif style == "varsity_jacket":
        front.frustum("rib", 1.277, 1.32, .164, .108, .137, .09)
        front.box("lining", (.135, 1.16, .154), (.075, .091, .014))
        for part in (parts["SleeveL"], parts["SleeveR"]): part.frustum("coat", -.40, -.025, .081, .087, .081, .087)
    elif style == "campus_jacket":
        front.box("rib", (0, 1.075, .169), (.013, .41, .012))
        for side in (-1, 1):
            front.welt("rib", [(side*.02, 1.21, .16), (side*.18, 1.1, .153), (side*.24, 1.05, .149)], .017)
        front.frustum("rib", 1.27, 1.34, .165, .108, .13, .09)
    return parts


def thumbnail(key, style, title, primary, secondary):
    im = Image.new("RGBA", (384,384), (26,32,43,255))
    d = ImageDraw.Draw(im)
    base = "#" + primary
    accent = "#" + (secondary or "E9E2D0")
    d.rounded_rectangle((90,96,294,316),28,fill=base,outline="#E8EBED",width=3)
    d.polygon([(94,107),(52,178),(79,217),(112,151)],fill=base)
    d.polygon([(290,107),(332,178),(305,217),(272,151)],fill=base)
    if style in ("long_sleeve_shirt","rugby_shirt","hoodie","layered_hoodie","cardigan","sweater","quarter_zip","flannel_shirt","denim_jacket","varsity_jacket","campus_jacket"):
        for x in (65,305): d.rounded_rectangle((x,173,x+15,271),7,fill=base)
    d.ellipse((153,81,231,126),fill=(26,32,43,255))
    if style in ("hoodie","layered_hoodie"):
        d.arc((125,57,259,161),177,363,fill=base,width=25)
        d.rounded_rectangle((137,223,247,267),12,outline=accent,width=5)
        for x in (175,209): d.line((x,111,x,193),fill=accent,width=4)
        if style=="layered_hoodie": d.rectangle((112,132,272,217),outline=accent,width=7)
    elif style=="pocket_tee": d.rounded_rectangle((116,154,166,196),5,fill=accent)
    elif style=="striped_tee":
        for y in range(132,288,28): d.line((96,y,287,y),fill=accent,width=12)
    elif style=="rugby_shirt":
        d.rectangle((93,157,291,208),fill=accent)
        d.polygon([(165,101),(192,142),(219,101)],fill=accent)
    elif style=="cardigan":
        d.line((191,116,191,308),fill=accent,width=10)
        for y in (164,199,234,269): d.ellipse((187,y,196,y+9),fill="#D6C286")
        for x in (118,229): d.rectangle((x,239,x+38,271),outline=accent,width=4)
    elif style=="sweater":
        for x in (133,164,195,226,257):
            for y in range(134,276,34): d.line((x-9,y,x+9,y+15,x-9,y+30),fill=accent,width=3,joint="curve")
    elif style=="quarter_zip":
        d.line((192,98,192,180),fill=accent,width=6)
        d.rectangle((116,145,152,166),fill=accent)
    elif style=="polo_shirt":
        d.polygon([(157,98),(192,131),(227,98),(216,140),(168,140)],fill=accent)
        for y in (153,174,195): d.ellipse((189,y,196,y+7),fill=accent)
    elif style=="flannel_shirt":
        for x in range(112,288,37): d.line((x,106,x,310),fill=accent,width=8)
        for y in range(139,310,39): d.line((94,y,290,y),fill=accent,width=8)
        d.line((192,104,192,309),fill="#EFE8D7",width=6)
    elif style=="denim_jacket":
        d.line((192,108,192,306),fill=accent,width=7)
        for x in (111,220): d.rectangle((x,158,x+53,203),outline=accent,width=5)
        for y in (219,245,271): d.ellipse((188,y,196,y+8),fill=accent)
    elif style=="varsity_jacket":
        d.rectangle((93,290,291,307),fill=accent)
        d.line((192,108,192,304),fill=accent,width=5)
        d.text((231,153),"C",fill=accent,stroke_width=1)
        for x in (65,305): d.rectangle((x,178,x+15,261),fill=accent)
    elif style=="campus_jacket":
        d.line((192,108,192,305),fill=accent,width=5)
        d.polygon([(101,143),(190,208),(284,143),(284,168),(192,240),(101,168)],fill=accent)
    im.save(THUMBS / f"{key}.png")


def main():
    catalog_path = BASE / "catalog.json"
    catalog = json.loads(catalog_path.read_text(encoding="utf-8"))
    existing = {item["id"] for item in catalog["items"]}
    inner = next(item for item in catalog["items"] if item["id"] == "tops.harbor_fitted_tee")
    outer = next(item for item in catalog["items"] if item["id"] == "tops.cedar_layered_hoodie")
    for style, title, slot, primary, secondary in STYLES:
        key = "reference_" + style
        parts = build(style)
        mats = write_model(key, title, parts)
        thumbnail(key, style, title, primary, secondary)
        item = copy.deepcopy(inner if slot == "top_inner" else outer)
        item.update(id="tops."+key, name=title, slot=slot,
                    scene=f"res://assets/cosmetics/clothing/models/{key}.gltf",
                    thumbnail=f"res://assets/cosmetics/clothing/thumbnails/{key}.png")
        item["materials"] = {"primary_regions": [mats[0]], "secondary_regions": [m for m in mats[1:] if m not in ("metal", "stitch")], "detail_regions": []}
        item["parameters"]["primary_color"]["default"] = primary
        if secondary:
            item["parameters"].setdefault("secondary_color", {"type":"color", "default":secondary})["default"] = secondary
        item["tags"] = [slot, "long_sleeve" if style not in ("fitted_tee", "pocket_tee", "striped_tee", "polo_shirt") else "short_sleeve"]
        if item["id"] not in existing: catalog["items"].append(item)
    catalog_path.write_text(json.dumps(catalog, indent=2), encoding="utf-8")


if __name__ == "__main__": main()
