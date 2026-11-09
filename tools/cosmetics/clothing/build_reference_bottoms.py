"""Build the Avatar Studio reference bottoms while keeping existing catalog IDs."""
import copy
import json
from PIL import Image, ImageDraw
from build_clothing_assets import BASE, THUMBS, leg, write_model

STYLES = [
    ("classic_jeans", "Classic Jeans", "2F5680"),
    ("black_pants", "Black Pants", "272C34"),
    ("khaki_pants", "Khaki Pants", "AE9B75"),
    ("sweatpants", "Sweatpants", "A5ABB1"),
    ("track_pants", "Track Pants", "293E59"),
    ("cargo_pants", "Cargo Pants", "A48758"),
    ("cargo_olive", "Cargo (Olive)", "55583B"),
    ("pajama_pants", "Pajama Pants", "324967"),
    ("denim_shorts", "Denim Shorts", "38658E"),
    ("athletic_shorts", "Athletic Shorts", "252C35"),
    ("dress_pants", "Dress Pants", "33373F"),
    ("ripped_jeans", "Ripped Jeans", "83A4B4"),
    ("camo_pants", "Camo Pants", "5A6237"),
    ("tech_pants", "Tech Pants", "252F40"),
    ("scholar_pants", "Scholar Pants", "34333D"),
]

def build(style):
    length = .33 if style.endswith("shorts") else .72
    pieces = {}
    for name, side in [("LegL",-1),("LegR",1)]:
        part = leg("twill",length,.12 if style in ("sweatpants","cargo_pants","cargo_olive","camo_pants") else .109)
        if style in ("track_pants","athletic_shorts","scholar_pants"):
            for offset in [.059,.079]:
                part.welt("stitch",[(offset*side,-.06,.096),(offset*side,-length*.5,.087),(offset*side,-length+.06,.07)],.004)
        if style in ("cargo_pants","cargo_olive","tech_pants","camo_pants"):
            part.box("rib",(.072*side,-.23,.067),(.09,.15,.12))
            part.box("stitch",(.074*side,-.16,.073),(.095,.026,.118))
        if style=="ripped_jeans":
            for y in [-.36,-.38,-.40]:
                part.box("stitch",(0,y,.106),(.112,.009,.006))
        if style=="pajama_pants":
            for y in [-.12,-.24,-.36,-.48,-.60]:
                part.welt("stitch",[(-.064,y,.083),(0,y,.109),(.064,y,.083)],.003)
            for x in [-.042,.042]:
                part.welt("stitch",[(x,-.05,.11),(x,-.32,.105),(x,-.68,.088)],.003)
        if style=="camo_pants":
            for x,y,w in [(-.046,-.11,.08),(.038,-.28,.10),(-.025,-.43,.12),(.025,-.58,.085)]:
                part.box("rib",(x,y,.103),(w,.044,.007))
        pieces[name]=part
    return pieces

def main():
    path = BASE/"catalog.json"
    catalog = json.loads(path.read_text(encoding="utf-8"))
    template = next(item for item in catalog["items"] if item["id"]=="bottoms.indigo_straight_jeans")
    existing = {item["id"] for item in catalog["items"]}
    for index,(style,title,color) in enumerate(STYLES):
        key = "reference_"+style
        mats = write_model(key,title,build(style))
        image = Image.new("RGB",(384,384),"#132B39")
        draw = ImageDraw.Draw(image)
        hem = 190 if style.endswith("shorts") else 316
        draw.polygon([(93,60),(291,60),(275,hem),(205,hem),(192,132),(179,hem),(109,hem)],fill="#"+color)
        if style in ("cargo_pants","cargo_olive","camo_pants","tech_pants"):
            for x in [108,229]:
                draw.rounded_rectangle((x,134,x+48,195),6,outline="#CBD1BF",width=3)
        if style in ("track_pants","athletic_shorts","scholar_pants"):
            for x in [119,264]:
                draw.line((x,75,x,hem-12),fill="#E2C76E" if index==14 else "#F3F3ED",width=6)
        if style=="pajama_pants":
            for y in range(82,hem,24):
                draw.line((118,y,168,y),fill="#87A9C5",width=4)
                draw.line((217,y,266,y),fill="#87A9C5",width=4)
        if style=="ripped_jeans":
            for x in [122,220]:
                draw.rounded_rectangle((x,181,x+43,198),6,fill="#DAC4A8")
        draw.text((20,343),title,fill="white")
        image.save(THUMBS/(key+".png"))
        item=copy.deepcopy(template)
        item.update(id="bottoms."+key,name=title,rarity="Common" if index<11 else "Uncommon" if index<14 else "Rare",
                    scene=f"res://assets/cosmetics/clothing/models/{key}.gltf",
                    thumbnail=f"res://assets/cosmetics/clothing/thumbnails/{key}.png")
        item["materials"]={"primary_regions":[mats[0]],"secondary_regions":mats[1:],"detail_regions":[]}
        item["parameters"]["primary_color"]["default"]=color
        if item["id"] not in existing:catalog["items"].append(item)
    path.write_text(json.dumps(catalog,indent=2),encoding="utf-8")

if __name__=="__main__":
    main()
