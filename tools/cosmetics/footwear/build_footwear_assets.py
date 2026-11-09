"""Build the original LabVolt footwear quality-slice assets.

This is an offline authoring tool.  It writes baked glTF meshes with UVs and
material regions; no geometry is assembled at game runtime.
"""
from __future__ import annotations

import json
import math
import struct
from pathlib import Path

from PIL import Image, ImageDraw


ROOT = Path(__file__).resolve().parents[3]
OUT = ROOT / "assets" / "cosmetics" / "footwear"
MODEL_DIR = OUT / "models"
MAT_DIR = OUT / "materials"
THUMB_DIR = OUT / "thumbnails"

MATERIALS = {
    "fabric": ((62, 86, 115), 0.0, 0.82, False),
    "canvas": ((211, 202, 178), 0.0, 0.88, False),
    "rubber": ((35, 40, 46), 0.0, 0.72, False),
    "rubber_light": ((220, 218, 207), 0.0, 0.78, False),
    "leather": ((84, 43, 27), 0.0, 0.36, False),
    "leather_dark": ((35, 24, 22), 0.0, 0.28, False),
    "metal": ((105, 116, 128), 0.78, 0.22, False),
    "neon": ((38, 224, 217), 0.15, 0.24, True),
    "cork": ((164, 118, 68), 0.0, 0.92, False),
}


def texture_set() -> None:
    MAT_DIR.mkdir(parents=True, exist_ok=True)
    for name, (rgb, metallic, roughness, emissive) in MATERIALS.items():
        albedo = Image.new("RGB", (128, 128), rgb)
        px = albedo.load()
        for y in range(128):
            for x in range(128):
                grain = ((x * 17 + y * 29 + (x ^ y) * 3) % 13) - 6
                scale = 0.018 if name in ("fabric", "canvas", "cork") else 0.006
                px[x, y] = tuple(max(0, min(255, int(c * (1 + grain * scale)))) for c in rgb)
        albedo.save(MAT_DIR / f"{name}_albedo.png")
        normal = Image.new("RGB", (128, 128), (128, 128, 255))
        nd = ImageDraw.Draw(normal)
        if name in ("fabric", "canvas"):
            for i in range(0, 128, 4):
                nd.line((i, 0, i, 127), fill=(136, 128, 254))
                nd.line((0, i, 127, i), fill=(128, 136, 254))
        elif name == "leather" or name == "leather_dark":
            for i in range(12, 128, 24):
                nd.arc((i - 11, i - 8, i + 17, i + 12), 15, 170, fill=(135, 122, 254))
        normal.save(MAT_DIR / f"{name}_normal.png")
        # glTF metallic-roughness: G=roughness, B=metallic.
        orm = Image.new("RGB", (128, 128), (255, int(roughness * 255), int(metallic * 255)))
        orm.save(MAT_DIR / f"{name}_orm.png")
        if emissive:
            Image.new("RGB", (128, 128), rgb).save(MAT_DIR / f"{name}_emission.png")


class Mesh:
    def __init__(self):
        self.groups: dict[str, list[tuple[tuple[float, float, float], tuple[float, float, float], tuple[float, float]]]] = {}

    def tri(self, mat, a, b, c, normal, uvs=((0, 0), (1, 0), (1, 1))):
        u = tuple(b[i] - a[i] for i in range(3))
        v = tuple(c[i] - a[i] for i in range(3))
        cross = (u[1]*v[2] - u[2]*v[1], u[2]*v[0] - u[0]*v[2], u[0]*v[1] - u[1]*v[0])
        length = math.sqrt(sum(component * component for component in cross))
        if length == 0:
            return
        if sum(cross[i] * normal[i] for i in range(3)) < 0:
            b, c = c, b
            uvs = (uvs[0], uvs[2], uvs[1])
            cross = tuple(-component for component in cross)
        normal = tuple(component / length for component in cross)
        self.groups.setdefault(mat, []).extend(((a, normal, uvs[0]), (b, normal, uvs[1]), (c, normal, uvs[2])))

    def quad(self, mat, a, b, c, d, normal):
        self.tri(mat, a, b, c, normal, ((0, 0), (1, 0), (1, 1)))
        self.tri(mat, a, c, d, normal, ((0, 0), (1, 1), (0, 1)))

    def box(self, mat, center, size, bevel=0.0):
        x, y, z = center; sx, sy, sz = (v / 2 for v in size)
        # A small bevel is represented by tapered top/bottom rings.
        bx = min(bevel, sx * .45); bz = min(bevel, sz * .45)
        lo = [(-sx+bx, -sy, -sz), (sx-bx, -sy, -sz), (sx-bx, -sy, sz), (-sx+bx, -sy, sz)]
        hi = [(-sx, sy, -sz+bz), (sx, sy, -sz+bz), (sx, sy, sz-bz), (-sx, sy, sz-bz)]
        lo = [(x+a, y+b, z+c) for a,b,c in lo]; hi = [(x+a, y+b, z+c) for a,b,c in hi]
        self.quad(mat, lo[0], lo[3], lo[2], lo[1], (0,-1,0)); self.quad(mat, hi[0], hi[1], hi[2], hi[3], (0,1,0))
        for i, n in enumerate(((0,0,-1),(1,0,0),(0,0,1),(-1,0,0))):
            j=(i+1)%4; self.quad(mat, lo[i], lo[j], hi[j], hi[i], n)

    def wedge(self, mat, center, width, height_back, height_front, length):
        x,y,z=center; x0=x-width/2; x1=x+width/2; z0=z-length/2; z1=z+length/2
        p=[(x0,y,z0),(x1,y,z0),(x1,y,z1),(x0,y,z1),(x0,y+height_back,z0),(x1,y+height_back,z0),(x1,y+height_front,z1),(x0,y+height_front,z1)]
        self.quad(mat,p[0],p[3],p[2],p[1],(0,-1,0)); self.quad(mat,p[4],p[5],p[6],p[7],(0,1,0))
        self.quad(mat,p[0],p[1],p[5],p[4],(0,0,-1)); self.quad(mat,p[3],p[7],p[6],p[2],(0,0,1))
        self.quad(mat,p[0],p[4],p[7],p[3],(-1,0,0)); self.quad(mat,p[1],p[2],p[6],p[5],(1,0,0))

    def cylinder(self, mat, center, radius, height, axis="y", segments=12):
        x,y,z=center
        for i in range(segments):
            a=2*math.pi*i/segments; b=2*math.pi*(i+1)/segments
            if axis=="y":
                p0=(x+radius*math.cos(a),y-height/2,z+radius*math.sin(a)); p1=(x+radius*math.cos(b),y-height/2,z+radius*math.sin(b)); p2=(p1[0],y+height/2,p1[2]); p3=(p0[0],y+height/2,p0[2]); n=(math.cos((a+b)/2),0,math.sin((a+b)/2))
            else:
                p0=(x+radius*math.cos(a),y+radius*math.sin(a),z-height/2); p1=(x+radius*math.cos(b),y+radius*math.sin(b),z-height/2); p2=(p1[0],p1[1],z+height/2); p3=(p0[0],p0[1],z+height/2); n=(math.cos((a+b)/2),math.sin((a+b)/2),0)
            self.quad(mat,p0,p1,p2,p3,n)

    def strap(self, mat, a, b, width, thickness=.008):
        ax,ay,az=a; bx,by,bz=b; dx=bx-ax; dz=bz-az; length=math.sqrt(dx*dx+dz*dz); angle=math.atan2(dx,dz)
        # axis-aligned approximation remains baked and reads as a lace/strap at this scale.
        self.box(mat,((ax+bx)/2,(ay+by)/2,(az+bz)/2),(length,thickness,width) if abs(dx)>abs(dz) else (width,thickness,length))


def running() -> Mesh:
    m=Mesh(); m.wedge("rubber_light",(0,-.045,.01),.205,.045,.035,.36); m.wedge("fabric",(0,-.005,.015),.185,.115,.075,.315)
    m.box("rubber",(0,-.025,.145),(.185,.035,.07),.012); m.box("fabric",(0,.055,-.09),(.17,.10,.12),.015)
    for z in (-.005,.035,.075): m.strap("canvas",(-.058,.082,z),(.058,.082,z),.012)
    m.box("rubber",(-.098,.005,.02),(.012,.045,.22)); m.box("rubber",(.098,.005,.02),(.012,.045,.22)); return m

def hightop() -> Mesh:
    m=Mesh(); m.box("rubber_light",(0,-.05,.0),(.21,.055,.36),.018); m.wedge("canvas",(0,-.015,.02),.185,.11,.07,.30)
    m.box("canvas",(0,.105,-.095),(.18,.24,.13),.018); m.box("rubber",(0,.17,-.16),(.18,.035,.035))
    for z in (-.09,-.055,-.02,.015,.05): m.strap("leather_dark",(-.06,.11,z),(.06,.11,z),.01)
    m.cylinder("metal",(-.075,.11,-.085),.009,.008,"z",10); m.cylinder("metal",(.075,.11,-.085),.009,.008,"z",10); return m

def work_boot() -> Mesh:
    m=Mesh(); m.box("rubber",(0,-.055,0),(.225,.07,.37),.012); m.wedge("leather",(0,-.015,.015),.205,.13,.10,.325)
    m.box("leather",(0,.13,-.09),(.195,.26,.16),.012); m.box("leather_dark",(0,.22,-.13),(.20,.055,.10),.01)
    m.box("metal",(0,.04,.145),(.185,.045,.07),.02)
    for z in (-.075,-.03,.015,.06): m.strap("canvas",(-.065,.145,z),(.065,.145,z),.012)
    for x in (-.075,0,.075): m.box("rubber",(x,-.098,.015),(.045,.022,.29)); return m

def dress() -> Mesh:
    m=Mesh(); m.wedge("leather_dark",(0,-.055,.0),.20,.035,.025,.36); m.wedge("leather",(0,-.025,.015),.19,.105,.06,.32)
    m.wedge("leather",(0,.015,-.075),.185,.09,.115,.16); m.box("leather_dark",(0,-.075,-.135),(.15,.07,.08),.006)
    m.box("leather_dark",(0,.075,-.01),(.16,.018,.035),.004); m.box("leather_dark",(0,.083,.09),(.13,.012,.012)); return m

def sandal() -> Mesh:
    mesh = Mesh()
    outline = [(-.069, -.166), (.069, -.166), (.10, -.125), (.105, .126),
               (.076, .188), (-.076, .188), (-.105, .126), (-.10, -.125)]
    for i, (x, z) in enumerate(outline):
        nx, nz = outline[(i + 1) % len(outline)]
        length = math.hypot(nx - x, nz - z)
        normal = ((nz - z) / length, 0, (x - nx) / length)
        for material, bottom, top in [("rubber", -.093, -.067), ("cork", -.067, -.017)]:
            mesh.quad(material, (x, bottom, z), (nx, bottom, nz),
                      (nx, top, nz), (x, top, z), normal)
        mesh.tri("rubber", (0, -.093, 0), (x, -.093, z), (nx, -.093, nz), (0, -1, 0))
        mesh.tri("cork", (0, -.017, 0), (x, -.017, z), (nx, -.017, nz), (0, 1, 0))

    for z, width, height in [(.101, .052, .070), (-.018, .047, .093), (-.112, .037, .116)]:
        # A continuous leather strip follows the foot from one sole edge to the other.
        profile = [(-.091, -.025), (-.086, height * .58), (-.062, height * .90),
                   (0, height), (.062, height * .90), (.086, height * .58), (.091, -.025)]
        inner = [(x * .88, y - .011) for x, y in profile]
        back, front = z - width / 2, z + width / 2
        for (x, y), (nx, ny), (ix, iy), (inx, iny) in zip(profile, profile[1:], inner, inner[1:]):
            length = math.hypot(nx - x, ny - y)
            normal = ((y - ny) / length, (nx - x) / length, 0)
            inner_length = math.hypot(inx - ix, iny - iy)
            mesh.quad("leather", (x, y, back), (nx, ny, back), (nx, ny, front), (x, y, front), normal)
            mesh.quad("leather", (ix, iy, back), (inx, iny, back), (inx, iny, front), (ix, iy, front),
                      ((iny - iy) / inner_length, (ix - inx) / inner_length, 0))
            for edge, direction in [(back, -1), (front, 1)]:
                mesh.quad("leather", (x, y, edge), (nx, ny, edge),
                          (inx, iny, edge), (ix, iy, edge), (0, 0, direction))
        for end in [0, -1]:
            x, y = profile[end]
            ix, iy = inner[end]
            mesh.quad("leather", (x, y, back), (x, y, front),
                      (ix, iy, front), (ix, iy, back), (0, -1, 0))
    mesh.box("metal", (.064, .103, -.112), (.025, .008, .027))
    return mesh


def future() -> Mesh:
    m=Mesh(); m.wedge("rubber",(0,-.05,.01),.215,.055,.035,.37); m.wedge("metal",(0,-.01,.01),.195,.125,.07,.31)
    m.box("metal",(0,.12,-.09),(.19,.22,.14),.025); m.wedge("rubber",(0,.03,.12),.18,.04,.085,.10)
    m.box("neon",(-.101,.035,.015),(.012,.025,.24)); m.box("neon",(.101,.035,.015),(.012,.025,.24)); m.box("neon",(0,.11,.11),(.15,.015,.025))
    m.box("rubber",(0,.20,-.145),(.17,.04,.045),.01); return m


ITEMS = {
    "running_sneaker": ("Velocity Runner", running, ["fabric","rubber_light","rubber","canvas"]),
    "high_top": ("Beacon High-Top", hightop, ["canvas","rubber_light","rubber","leather_dark","metal"]),
    "work_boot": ("Foundry Work Boot", work_boot, ["leather","leather_dark","rubber","metal","canvas"]),
    "dress_shoe": ("Oxford Dress Shoe", dress, ["leather","leather_dark"]),
    "sandal": ("Trail Sandal", sandal, ["cork","rubber","leather","metal"]),
    "future_shoe": ("Ionstep Future Shoe", future, ["metal","rubber","neon"]),
}


def loafer() -> Mesh:
    m=dress()
    m.box("metal",(0,.074,.015),(.105,.012,.027),.005)
    return m

def canvas_low() -> Mesh:
    m=running()
    m.box("canvas",(0,.041,.141),(.163,.034,.068),.026)
    m.box("leather_dark",(0,.072,-.145),(.095,.032,.013),.004)
    return m

ITEMS.update({
    "campus_loafer": ("Campus Penny Loafer",loafer,["leather","leather_dark","metal"]),
    "marina_canvas": ("Marina Canvas Low",canvas_low,["fabric","rubber_light","rubber","canvas","leather_dark"]),
})

def write_gltf(key: str, title: str, mesh: Mesh, mats: list[str]) -> None:
    MODEL_DIR.mkdir(parents=True, exist_ok=True)
    blob=bytearray(); views=[]; accessors=[]; primitives=[]
    def add(data, component, kind, mins=None, maxs=None):
        while len(blob)%4: blob.append(0)
        offset=len(blob); blob.extend(data); views.append({"buffer":0,"byteOffset":offset,"byteLength":len(data)})
        acc={"bufferView":len(views)-1,"componentType":component,"count":len(data)//(12 if kind=="VEC3" else 8),"type":kind}
        if mins is not None: acc["min"]=mins; acc["max"]=maxs
        accessors.append(acc); return len(accessors)-1
    for mat in mats:
        verts=mesh.groups.get(mat,[])
        if not verts: continue
        pos=b"".join(struct.pack("<3f",*v[0]) for v in verts); nor=b"".join(struct.pack("<3f",*v[1]) for v in verts); uv=b"".join(struct.pack("<2f",*v[2]) for v in verts)
        xyz=[v[0] for v in verts]; pa=add(pos,5126,"VEC3",[min(v[i] for v in xyz) for i in range(3)],[max(v[i] for v in xyz) for i in range(3)])
        na=add(nor,5126,"VEC3"); ua=add(uv,5126,"VEC2")
        primitives.append({"attributes":{"POSITION":pa,"NORMAL":na,"TEXCOORD_0":ua},"material":mats.index(mat),"mode":4})
    images=[]; textures=[]; material_defs=[]
    def tex(uri): images.append({"uri":uri}); textures.append({"source":len(images)-1}); return len(textures)-1
    for mat in mats:
        rgb,metallic,roughness,emissive=MATERIALS[mat]
        base=tex(f"../materials/{mat}_albedo.png"); normal=tex(f"../materials/{mat}_normal.png"); orm=tex(f"../materials/{mat}_orm.png")
        md={"name":mat,"pbrMetallicRoughness":{"baseColorTexture":{"index":base},"metallicRoughnessTexture":{"index":orm},"metallicFactor":metallic,"roughnessFactor":roughness},"normalTexture":{"index":normal,"scale":.55}}
        if emissive: md["emissiveTexture"]={"index":tex(f"../materials/{mat}_emission.png")}; md["emissiveFactor"]=[1,1,1]
        material_defs.append(md)
    gltf={"asset":{"version":"2.0","generator":"LabVolt original footwear authoring tool"},"scene":0,"scenes":[{"nodes":[0]}],"nodes":[{"name":title,"mesh":0}],"meshes":[{"name":title,"primitives":primitives}],"materials":material_defs,"images":images,"textures":textures,"samplers":[{}],"buffers":[{"uri":f"{key}.bin","byteLength":len(blob)}],"bufferViews":views,"accessors":accessors}
    (MODEL_DIR/f"{key}.bin").write_bytes(blob); (MODEL_DIR/f"{key}.gltf").write_text(json.dumps(gltf,indent=2),encoding="utf-8")


def thumbnail(key, title, mats):
    THUMB_DIR.mkdir(parents=True,exist_ok=True); im=Image.new("RGBA",(384,384),(26,32,43,255)); d=ImageDraw.Draw(im)
    d.ellipse((54,270,330,330),fill=(8,12,18,140)); main=MATERIALS[mats[0]][0]; accent=MATERIALS[mats[-1]][0]
    # Purposeful product-card silhouette, generated independently from gameplay.
    d.polygon([(65,235),(84,165),(183,138),(245,176),(324,207),(315,271),(88,278)],fill=main+(255,),outline=(235,239,244,255),width=4)
    d.polygon([(82,244),(315,238),(315,276),(89,282)],fill=MATERIALS.get("rubber",MATERIALS[mats[0]])[0]+(255,))
    d.line((125,188,238,208),fill=accent+(255,),width=12); d.text((32,28),title,fill=(244,246,249,255),stroke_width=1,stroke_fill=(10,12,16,255))
    im.save(THUMB_DIR/f"{key}.png")


def main():
    texture_set()
    for key,(title,factory,mats) in ITEMS.items():
        write_gltf(key,title,factory(),mats); thumbnail(key,title,mats)
    print(f"Built {len(ITEMS)} footwear models in {OUT}")


if __name__ == "__main__": main()
