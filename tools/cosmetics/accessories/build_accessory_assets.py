"""Bake the original LabVolt accessory starter collection to glTF + PNG assets."""
from __future__ import annotations

import json, math, struct
from pathlib import Path
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[3]
BASE = ROOT / "assets" / "cosmetics" / "accessories"
MODELS, MATERIALS, THUMBS = BASE / "models", BASE / "materials", BASE / "thumbnails"

MATS = {
    "canvas": ((55, 102, 118), 0.0, .82), "knit": ((174, 81, 87), 0.0, .9),
    "felt": ((92, 67, 49), 0.0, .86), "dark_metal": ((41, 48, 59), .75, .24),
    "gold": ((190, 143, 52), .92, .18), "glass": ((31, 111, 132), .18, .12),
    "leather": ((91, 55, 34), 0.0, .42), "fabric": ((49, 65, 83), 0.0, .88),
    "accent": ((229, 175, 61), .15, .4), "silver": ((174, 184, 191), .95, .16),
}

class Mesh:
    def __init__(self): self.groups = {}
    def tri(self, m, a, b, c, n, uv=((0,0),(1,0),(1,1))):
        u = tuple(b[i] - a[i] for i in range(3))
        v = tuple(c[i] - a[i] for i in range(3))
        cross = (u[1]*v[2] - u[2]*v[1], u[2]*v[0] - u[0]*v[2], u[0]*v[1] - u[1]*v[0])
        if sum(cross[i] * n[i] for i in range(3)) < 0:
            b, c = c, b
            uv = (uv[0], uv[2], uv[1])
        self.groups.setdefault(m, []).extend(((a,n,uv[0]),(b,n,uv[1]),(c,n,uv[2])))
    def quad(self,m,a,b,c,d,n):
        self.tri(m,a,b,c,n); self.tri(m,a,c,d,n,((0,0),(1,1),(0,1)))
    def box(self,m,c,s):
        x,y,z=c; X,Y,Z=(v/2 for v in s); p=[(x-X,y-Y,z-Z),(x+X,y-Y,z-Z),(x+X,y+Y,z-Z),(x-X,y+Y,z-Z),(x-X,y-Y,z+Z),(x+X,y-Y,z+Z),(x+X,y+Y,z+Z),(x-X,y+Y,z+Z)]
        for q,n in [((0,3,2,1),(0,0,-1)),((4,5,6,7),(0,0,1)),((0,4,7,3),(-1,0,0)),((1,2,6,5),(1,0,0)),((0,1,5,4),(0,-1,0)),((3,7,6,2),(0,1,0))]: self.quad(m,*[p[i] for i in q],n)
    def cylinder(self,m,c,r,h,axis="y",segments=16):
        x,y,z=c
        for i in range(segments):
            a,b=2*math.pi*i/segments,2*math.pi*(i+1)/segments
            if axis=="y": p=[(x+r*math.cos(a),y-h/2,z+r*math.sin(a)),(x+r*math.cos(b),y-h/2,z+r*math.sin(b)),(x+r*math.cos(b),y+h/2,z+r*math.sin(b)),(x+r*math.cos(a),y+h/2,z+r*math.sin(a))]; n=(math.cos((a+b)/2),0,math.sin((a+b)/2))
            elif axis=="x": p=[(x-h/2,y+r*math.cos(a),z+r*math.sin(a)),(x-h/2,y+r*math.cos(b),z+r*math.sin(b)),(x+h/2,y+r*math.cos(b),z+r*math.sin(b)),(x+h/2,y+r*math.cos(a),z+r*math.sin(a))]; n=(0,math.cos((a+b)/2),math.sin((a+b)/2))
            else: p=[(x+r*math.cos(a),y+r*math.sin(a),z-h/2),(x+r*math.cos(b),y+r*math.sin(b),z-h/2),(x+r*math.cos(b),y+r*math.sin(b),z+h/2),(x+r*math.cos(a),y+r*math.sin(a),z+h/2)]; n=(math.cos((a+b)/2),math.sin((a+b)/2),0)
            self.quad(m,*p,n)
            axes = {"x":0,"y":1,"z":2}
            index = axes[axis]
            normal = tuple(1 if i==index else 0 for i in range(3))
            base = tuple(c[i] - normal[i]*h/2 for i in range(3))
            top = tuple(c[i] + normal[i]*h/2 for i in range(3))
            self.tri(m, base, p[0], p[1], tuple(-v for v in normal))
            self.tri(m, top, p[2], p[3], normal)
    def smooth_quad(self, material, points, normals):
        self.quad(material, *points, normals[0])
        by_point = dict(zip(points, normals))
        vertices = self.groups[material]
        vertices[-6:] = [(point, by_point[point], uv) for point, _, uv in vertices[-6:]]

    def dome(self,m,rows,segments=32):
        for index, ((y0,rx0,rz0),(y1,rx1,rz1)) in enumerate(zip(rows,rows[1:])):
            for i in range(segments):
                a,b=math.tau*i/segments,math.tau*(i+1)/segments
                def point(y,rx,rz,angle):
                    return (rx*math.cos(angle),y,rz*math.sin(angle))
                def normal(row, angle):
                    lo, hi = rows[max(0,row-1)], rows[min(len(rows)-1,row+1)]
                    c, s = math.cos(angle), math.sin(angle)
                    dy = hi[0]-lo[0]
                    n = (c*dy, (lo[1]-hi[1])*c*c+(lo[2]-hi[2])*s*s, s*dy)
                    length = math.sqrt(sum(v*v for v in n))
                    return tuple(v/length for v in n)
                self.smooth_quad(m,[point(y0,rx0,rz0,a),point(y0,rx0,rz0,b),
                                    point(y1,rx1,rz1,b),point(y1,rx1,rz1,a)],
                                 [normal(index,a),normal(index,b),normal(index+1,b),normal(index+1,a)])

    def chain(self,m,points,width):
        for start,end in zip(points,points[1:]):
            axis = tuple(b-a for a,b in zip(start,end))
            length = math.sqrt(sum(v*v for v in axis))
            if length == 0:
                continue
            axis = tuple(v/length for v in axis)
            up = (0,1,0) if abs(axis[1]) < .9 else (0,0,1)
            x = (axis[1]*up[2]-axis[2]*up[1],-axis[0]*up[2],axis[0]*up[1])
            x = tuple(v/math.sqrt(sum(w*w for w in x)) for v in x)
            y = (axis[1]*x[2]-axis[2]*x[1],axis[2]*x[0]-axis[0]*x[2],axis[0]*x[1]-axis[1]*x[0])
            def point(center, normal):
                return tuple(c+n*width*.5 for c,n in zip(center,normal))
            for i in range(8):
                a,b = (math.tau*k/8 for k in (i,i+1))
                na,nb = (tuple(u*math.cos(t)+v*math.sin(t) for u,v in zip(x,y)) for t in (a,b))
                pa,pb,qa,qb = point(start,na),point(start,nb),point(end,na),point(end,nb)
                self.smooth_quad(m,[pa,pb,qb,qa],[na,nb,nb,na])
                self.tri(m,start,pa,pb,tuple(-v for v in axis))
                self.tri(m,end,qa,qb,axis)
    def ring(self,m,c,outer,inner,axis="z",segments=20):
        x,y,z=c
        def point(rad,a,depth):
            if axis=="z": return (x+rad*math.cos(a),y+rad*math.sin(a),z+depth)
            if axis=="x": return (x+depth,y+rad*math.cos(a),z+rad*math.sin(a))
            return (x+rad*math.cos(a),y+depth,z+rad*math.sin(a))
        normal = (1,0,0) if axis=="x" else ((0,1,0) if axis=="y" else (0,0,1))
        for i in range(segments):
            a,b=2*math.pi*i/segments,2*math.pi*(i+1)/segments
            for depth,sign in [(-.003,-1),(.003,1)]:
                self.quad(m,point(outer,a,depth),point(outer,b,depth),point(inner,b,depth),point(inner,a,depth),tuple(sign*v for v in normal))

def cap():
    mesh = Mesh()
    mesh.dome("canvas",[(.124,.232,.184),(.162,.233,.185),(.20,.224,.177),
                        (.235,.199,.157),(.266,.155,.123),(.287,.095,.076),(.296,.001,.001)],48)
    # The bill begins under the crown and tapers toward its rounded front edge.
    for index in range(24):
        a,b = (math.pi*k/24 for k in (index,index+1))
        def point(t, front, bottom):
            x = .174*math.cos(t)
            z = .115+(.185 if front else .045)*math.sin(t)
            y = .157-.018*math.cos(t)**2-(.013 if bottom else 0)
            return x,y,z
        for bottom,sign in [(False,1),(True,-1)]:
            mesh.quad("canvas",point(a,False,bottom),point(a,True,bottom),
                      point(b,True,bottom),point(b,False,bottom),(0,sign,0))
        mesh.quad("canvas",point(a,True,False),point(a,True,True),
                  point(b,True,True),point(b,True,False),(math.cos((a+b)*.5),0,math.sin((a+b)*.5)))
    return mesh
def beanie():
    m=Mesh(); m.dome("knit",[(.106,.235,.185),(.151,.238,.193),(.167,.229,.185),(.232,.207,.169),(.29,.163,.14),(.319,.095,.088),(.329,.002,.002)]); return m
def brim_hat():
    m=Mesh(); m.cylinder("felt",(0,.255,0),.19,.23,"y",20); m.cylinder("felt",(0,.145,0),.31,.025,"y",24); m.ring("gold",(0,.19,0),.198,.184,"y",20); return m
def round_glasses():
    m=Mesh()
    for side in (-1,1):
        m.ring("dark_metal",(side*.085,.016,.183),.063,.053,"z",28)
        m.chain("dark_metal",[(side*.142,.038,.182),(side*.164,.038,.154),(side*.187,.031,.106),(side*.210,.020,.042),(side*.215,.003,.015)],.009)
    m.box("dark_metal",(0,.031,.184),(.053,.009,.010)); return m
def visor():
    m=Mesh(); m.box("glass",(0,.015,.215),(.31,.115,.018)); m.box("dark_metal",(0,.079,.205),(.34,.018,.025)); m.box("accent",(0,-.055,.207),(.20,.012,.025)); return m
def hoops():
    m=Mesh()
    for x in (-.246,.246): m.ring("gold",(x,-.075,.022),.045,.034,"z",18)
    return m
def pendant():
    m=Mesh()
    for side in (-1,1):
        points=[(0,1.363,-.081),(side*.077,1.35,-.05),(side*.093,1.323,.039),(side*.072,1.271,.121),(side*.04,1.217,.149),(0,1.188,.156)]
        for a,b in zip(points,points[1:]):
            m.chain("gold",[tuple(a[k]+(b[k]-a[k])*t/12 for k in range(3)) for t in range(13)],.004)
    m.ring("gold",(0,1.164,.163),.028,.019,"z",18); m.cylinder("glass",(0,1.164,.165),.018,.009,"z",16); return m
def watch():
    m=Mesh(); m.ring("leather",(0,-.405,0),.085,.067,"y",20); m.box("silver",(0,-.405,.078),(.085,.068,.025)); m.box("glass",(0,-.405,.094),(.065,.048,.01)); return m
def backpack():
    m=Mesh(); m.box("fabric",(0,1.05,-.225),(.36,.48,.16)); m.box("canvas",(0,.91,-.14),(.30,.15,.08)); m.box("accent",(0,1.13,-.14),(.16,.03,.02));
    for x in (-.15,.15): m.box("leather",(x,1.12,-.105),(.035,.45,.035))
    return m

ITEMS={"campus_cap":("Campus Five-Panel Cap",cap,["canvas","accent"]),"harbor_beanie":("Harbor Knit Beanie",beanie,["knit"]),"field_brim":("Field Brim Hat",brim_hat,["felt","gold"]),"round_glasses":("Round Study Glasses",round_glasses,["dark_metal"]),"aurora_visor":("Aurora Visor",visor,["glass","dark_metal","accent"]),"gold_hoops":("Orbit Hoop Earrings",hoops,["gold"]),"prism_pendant":("Prism Pendant",pendant,["gold","glass"]),"bench_watch":("Bench Timer Watch",watch,["leather","silver","glass"]),"utility_pack":("Campus Utility Pack",backpack,["fabric","canvas","accent","leather"])}

def studio_earstuds():
    m=Mesh()
    for side in (-1,1):
        m.cylinder("silver",(side*.242,-.048,.023),.015,.014,"z",16)
        m.cylinder("glass",(side*.242,-.048,.033),.009,.009,"z",8)
    return m

def enamel_pin():
    m=Mesh()
    m.cylinder("gold",(0,1.165,.159),.034,.014,"z",20)
    m.cylinder("accent",(0,1.165,.169),.028,.010,"z",16)
    m.box("dark_metal",(0,1.165,.176),(.020,.009,.005))
    return m

ITEMS.update({
 "studio_studs": ("Studio Stud Earrings",studio_earstuds,["silver","glass"]),
 "campus_medallion": ("Campus Medallion",enamel_pin,["gold","accent","dark_metal"]),
})

def textures():
    MATERIALS.mkdir(parents=True,exist_ok=True)
    for name,(rgb,metal,rough) in MATS.items():
        al=Image.new("RGB",(128,128),rgb); px=al.load()
        for y in range(128):
            for x in range(128):
                grain=((x*13+y*23+(x^y)*5)%15)-7; px[x,y]=tuple(max(0,min(255,int(v*(1+grain*.008)))) for v in rgb)
        al.save(MATERIALS/f"{name}_albedo.png")
        normal=Image.new("RGB",(128,128),(128,128,255)); d=ImageDraw.Draw(normal)
        if name in ("canvas","knit","fabric"): 
            for i in range(0,128,5): d.line((i,0,i,127),fill=(136,128,254)); d.line((0,i,127,i),fill=(128,136,254))
        normal.save(MATERIALS/f"{name}_normal.png"); Image.new("RGB",(128,128),(255,int(rough*255),int(metal*255))).save(MATERIALS/f"{name}_orm.png")

def write(key,title,mesh,mats):
    MODELS.mkdir(parents=True,exist_ok=True); blob=bytearray(); views=[]; acc=[]; prim=[]
    def add(data,kind,stride,mins=None,maxs=None):
        while len(blob)%4: blob.append(0)
        off=len(blob); blob.extend(data); views.append({"buffer":0,"byteOffset":off,"byteLength":len(data)}); a={"bufferView":len(views)-1,"componentType":5126,"count":len(data)//stride,"type":kind}
        if mins is not None: a.update(min=mins,max=maxs)
        acc.append(a); return len(acc)-1
    for mat in mats:
        verts=mesh.groups.get(mat,[])
        if not verts: continue
        xyz=[v[0] for v in verts]; pa=add(b''.join(struct.pack('<3f',*v[0]) for v in verts),'VEC3',12,[min(v[i] for v in xyz) for i in range(3)],[max(v[i] for v in xyz) for i in range(3)])
        na=add(b''.join(struct.pack('<3f',*v[1]) for v in verts),'VEC3',12); ua=add(b''.join(struct.pack('<2f',*v[2]) for v in verts),'VEC2',8); prim.append({"attributes":{"POSITION":pa,"NORMAL":na,"TEXCOORD_0":ua},"material":mats.index(mat)})
    images=[]; tex=[]; md=[]
    def texture(uri): images.append({"uri":uri}); tex.append({"source":len(images)-1}); return len(tex)-1
    for mat in mats:
        rgb,metal,rough=MATS[mat]; md.append({"name":mat,"pbrMetallicRoughness":{"baseColorTexture":{"index":texture(f'../materials/{mat}_albedo.png')},"metallicRoughnessTexture":{"index":texture(f'../materials/{mat}_orm.png')},"metallicFactor":metal,"roughnessFactor":rough},"normalTexture":{"index":texture(f'../materials/{mat}_normal.png'),"scale":.55}})
    doc={"asset":{"version":"2.0","generator":"LabVolt original accessory authoring"},"scene":0,"scenes":[{"nodes":[0]}],"nodes":[{"name":title,"mesh":0}],"meshes":[{"name":title,"primitives":prim}],"materials":md,"images":images,"textures":tex,"buffers":[{"uri":key+'.bin',"byteLength":len(blob)}],"bufferViews":views,"accessors":acc}
    (MODELS/f'{key}.bin').write_bytes(blob); (MODELS/f'{key}.gltf').write_text(json.dumps(doc,indent=2),encoding='utf-8')

def thumbnail(key,title,index,mats):
    THUMBS.mkdir(parents=True,exist_ok=True); im=Image.new('RGBA',(384,384),(24,30,41,255)); d=ImageDraw.Draw(im); rgb=MATS[mats[0]][0]; accent=MATS[mats[-1]][0]
    d.ellipse((54,275,330,328),fill=(6,10,16,150)); shape=index%5
    if shape==0: d.ellipse((95,105,289,269),fill=rgb+(255,),outline=(240,243,247,255),width=5)
    elif shape==1: d.rounded_rectangle((92,105,292,270),28,fill=rgb+(255,),outline=(240,243,247,255),width=5)
    elif shape==2: d.polygon([(192,78),(305,245),(78,245)],fill=rgb+(255,),outline=(240,243,247,255))
    elif shape==3: d.ellipse((88,108,188,208),outline=rgb+(255,),width=18); d.ellipse((196,108,296,208),outline=rgb+(255,),width=18)
    else: d.rounded_rectangle((105,82,279,286),35,fill=rgb+(255,),outline=(240,243,247,255),width=5)
    d.line((112,235,272,145),fill=accent+(255,),width=15); d.text((25,28),title,fill=(246,247,250,255),stroke_width=1,stroke_fill=(4,6,9,255)); im.save(THUMBS/f'{key}.png')

def main():
    textures()
    for i,(key,(title,factory,mats)) in enumerate(ITEMS.items()): write(key,title,factory(),mats); thumbnail(key,title,i,mats)
    print(f'Built {len(ITEMS)} distinct accessory models')
if __name__=='__main__': main()
