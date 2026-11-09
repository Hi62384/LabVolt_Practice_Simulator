"""Author the reference accessories on the existing avatar attachment slots."""
import json
import math
from PIL import Image, ImageDraw
from build_accessory_assets import BASE, THUMBS, MATS, Mesh, cap, beanie, brim_hat, round_glasses, visor, hoops, pendant, watch, studio_earstuds, enamel_pin, write

GROUPS = {
    "head":"Baseball Cap|Beanie|Bucket Hat|Headband|Bandana|Visor|Earmuffs|Headphones|Gaming Headset|Flower Crown|Crown|Halo Headband|Hair Clips",
    "eyewear":"Round Glasses|Square Glasses|Aviators|Heart Sunglasses|Sports Sunglasses|Monocle|Eye Patch|Face Mask|Bandana Mask|Nose Ring|Eyebrow Piercing|Lip Piercing",
    "neck":"Simple Necklace|Chain Necklace|Pendant Necklace|Choker|Scarf|Bow Tie|Tie|Decorative Pins",
    "ears":"Hoop Earrings|Stud Earrings|Dangling Earrings",
    "wrist_left":"Smartwatch|Bracelet|Bangle|Wrist Sweatband",
}

def aviators():
    mesh = Mesh()
    for side in (-1,1):
        def contour(angle, scale, depth):
            h = math.sin(angle)
            x = side*(.088+scale*(.066*math.cos(angle)*(1+.22*h)-.018*min(h,0)))
            return (x,.020+scale*.068*h,.223-.14*abs(x)+depth)
        for index in range(40):
            a,b = (math.tau*i/40 for i in (index,index+1))
            for depth, sign in [(0,1),(-.006,-1)]:
                mesh.quad("gold",contour(a,1,depth),contour(b,1,depth),
                          contour(b,.92,depth),contour(a,.92,depth),(0,0,sign))
            mesh.tri("glass",(side*.088,.020,.210),contour(a,.94,-.003),
                     contour(b,.94,-.003),(side*.14,0,1))
        mesh.chain("gold",[(side*.148,.049,.202),(side*.182,.046,.159),
                           (side*.215,.030,.070),(side*.222,.017,.006)],.008)
        mesh.chain("dark_metal",[(side*.222,.017,.006),(side*.218,-.009,-.043)],.012)
    mesh.chain("gold",[(-.041,.066,.217),(0,.071,.225),(.041,.066,.217)],.007)
    mesh.chain("gold",[(-.028,.034,.219),(0,.045,.227),(.028,.034,.219)],.007)
    return mesh

def bandana(mask):
    mesh = Mesh()
    material = "knit" if mask else "canvas"
    def point(angle, height):
        front = max(0,math.cos(angle))
        back = max(0,-math.cos(angle))
        wave = .003*math.sin(angle*7)
        if mask:
            top = -.019+.017*front+.005*back
            bottom = top-.035-.162*front**2.5
            width = .211-.030*front*height
            depth = (.226 if math.cos(angle)>=0 else .153)-.034*front*height
        else:
            top = .174-.038*back+.014*front
            bottom = top-.054-.019*front
            width,depth = .221,.175
        return ((width+wave)*math.sin(angle),top+(bottom-top)*height+wave,
                (depth+wave)*math.cos(angle))
    for index in range(56):
        a,b = (math.tau*i/56 for i in (index,index+1))
        for low,high in [(0,.12),(.12,.53),(.53,.87),(.87,1)]:
            points = [point(a,low),point(b,low),point(b,high),point(a,high)]
            normals = [(math.sin(t),0,math.cos(t)) for t in (a,b,b,a)]
            mesh.smooth_quad(material,points,normals)
            mesh.smooth_quad(material,points,[tuple(-v for v in n) for n in normals])
    _, y, z = point(math.pi,.5)
    mesh.cylinder(material,(0,y,z-.008),.025,.021,"z",16)
    for side in (-1,1):
        tail = [(-.013,y+.010,z-.021),(.013,y+.010,z-.021),
                (side*.075,y-.071,z-.035),(side*.044,y-.105,z-.026)]
        for sign in (-1,1):
            mesh.quad(material,*tail,(0,0,sign))
    return mesh

def bangle():
    mesh = Mesh()
    for index in range(48):
        a,b = (math.tau*i/48 for i in (index,index+1))
        for section in range(12):
            c,d = (math.tau*i/12 for i in (section,section+1))
            def normal(t,u):
                return (math.cos(t)*math.cos(u),math.sin(u),math.sin(t)*math.cos(u))
            def point(t,u):
                radius = .074+.008*math.cos(u)
                return (radius*math.cos(t),-.404+.012*math.sin(u),radius*math.sin(t))
            angles = [(a,c),(b,c),(b,d),(a,d)]
            mesh.smooth_quad("gold",[point(*pair) for pair in angles],[normal(*pair) for pair in angles])
    return mesh

def build(name):
    reused = {"Baseball Cap":cap,"Beanie":beanie,"Bucket Hat":brim_hat,"Round Glasses":round_glasses,
              "Sports Sunglasses":visor,"Hoop Earrings":hoops,"Pendant Necklace":pendant,
              "Smartwatch":watch,"Stud Earrings":studio_earstuds}
    if name=="Aviators":return aviators()
    if name in ("Bandana","Bandana Mask"):return bandana(name=="Bandana Mask")
    if name=="Bangle":return bangle()
    if name in reused:return reused[name]()
    m=Mesh()
    if name in ("Headband","Visor","Flower Crown","Crown","Halo Headband"):
        metal = "gold" if name in ("Crown","Halo Headband") else "canvas"
        y=.36 if name=="Halo Headband" else .151
        m.ring(metal,(0,y,0),.239,.218,"y",32)
        if name=="Headband":m.box("canvas",(0,.153,.216),(.29,.066,.035))
        elif name=="Visor":m.box("canvas",(0,.14,.238),(.33,.027,.18))
        elif name=="Halo Headband":
            for x in [-.14,.14]:m.box("gold",(x,.255,0),(.012,.20,.014))
        elif name in ("Crown","Flower Crown"):
            for i in range(10):
                t=math.tau*i/10
                x,z=.225*math.cos(t),.225*math.sin(t)
                if name=="Crown":
                    m.cylinder("gold",(x,.20,z),.032,.091,"y",5)
                    m.cylinder("accent",(x,.253,z),.019,.024,"y",8)
                else:
                    m.cylinder("knit",(x,.167,z),.039,.028,"y",7)
                    m.cylinder("gold",(x,.185,z),.016,.012,"y",10)
    elif name in ("Headphones","Gaming Headset","Earmuffs"):
        pad="knit" if name=="Earmuffs" else "dark_metal"
        for side in [-1,1]:
            m.cylinder(pad,(side*.244,-.019,0),.083,.069,"x",20)
            m.cylinder("accent",(side*.282,-.019,0),.061,.018,"x",20)
        m.chain("canvas",[(.25*math.cos(t*math.pi/20),.294*math.sin(t*math.pi/20),0) for t in range(21)],.025)
        if name=="Gaming Headset":
            m.chain("dark_metal",[(.257,-.05,.01),(.229,-.095,.14),(.133,-.106,.218)],.014)
    elif name=="Hair Clips":
        for x,y in [(-.142,.142),(-.113,.178)]:
            m.box("gold",(x,y,.177),(.089,.023,.018))
            m.box("accent",(x,y,.190),(.071,.011,.010))
    elif name in ("Square Glasses","Heart Sunglasses","Monocle","Eye Patch"):
        for side in ([1] if name=="Monocle" else [-1] if name=="Eye Patch" else [-1,1]):
            x=side*.086
            if name=="Square Glasses":
                for y in [-.035,.065]:m.box("dark_metal",(x,y,.196),(.115,.014,.013))
                for edge in [-.053,.053]:m.box("dark_metal",(x+edge,.015,.196),(.014,.10,.013))
            elif name=="Heart Sunglasses":
                pts=[(x+.052*math.sin(t)**3,.029+.0034*(13*math.cos(t)-5*math.cos(2*t)-2*math.cos(3*t)-math.cos(4*t)),.211) for t in [i*math.tau/28 for i in range(29)]]
                m.chain("accent",pts,.012)
                for a,b in zip(pts,pts[1:]):m.tri("dark_metal",(x,.029,.206),a,b,(0,0,1))
            else:
                metal="dark_metal" if name=="Eye Patch" else "gold"
                m.ring(metal,(x,.015,.200),.063,.052,"z",24)
                if name!="Monocle":m.cylinder("dark_metal",(x,.016,.198),.054,.012,"z",24)
        if name=="Monocle":m.chain("gold",[(.14,-.02,.196),(.161,-.14,.13),(.201,-.17,.084),(.22,-.06,.06)],.007)
        else:m.chain("dark_metal",[(-.22,.034,.012),(-.17,.034,.184),(0,.035,.208),(.17,.034,.184),(.22,.034,.012)],.009)
    elif name in ("Face Mask",):
        m.quad("knit",(-.168,-.051,.146),(.168,-.051,.146),(.14,-.171,.164),(-.14,-.171,.164),(0,0,1))
        for side in [-1,1]:m.chain("canvas",[(side*.155,-.07,.155),(side*.223,-.017,.035),(side*.20,-.118,.05),(side*.103,-.16,.155)],.009)
        for y in [-.085,-.112,-.142]:m.box("canvas",(0,y,.169),(.23,.007,.009))
    elif name in ("Nose Ring","Eyebrow Piercing","Lip Piercing","Dangling Earrings"):
        points={"Nose Ring":[(.034,-.065,.206)],"Eyebrow Piercing":[(-.113,.083,.186)],"Lip Piercing":[(.041,-.125,.196)],"Dangling Earrings":[(-.243,-.115,.032),(.243,-.115,.032)]}[name]
        for x,y,z in points:
            m.ring("silver",(x,y,z),.016,.009,"z",16)
            if name=="Dangling Earrings":
                m.box("gold",(x,y-.033,z),(.011,.051,.013))
                m.cylinder("gold",(x,y-.064,z),.027,.013,"z",5)
    elif name in ("Simple Necklace","Chain Necklace","Choker","Scarf","Bow Tie","Tie","Decorative Pins"):
        if name=="Decorative Pins":
            for i,(x,r) in enumerate([(-.05,.025),(.015,.022),(.072,.019)]):
                m.cylinder("gold",(x,1.15+i*.015,.169),r,.014,"z",5+i*3)
                m.cylinder("accent",(x,1.15+i*.015,.180),r*.77,.009,"z",5+i*3)
        elif name in ("Bow Tie","Tie"):
            m.box("canvas",(0,1.27,.139),(.06,.053,.038))
            if name=="Bow Tie":
                for side in [-1,1]:m.tri("canvas",(0,1.265,.168),(side*.10,1.32,.166),(side*.10,1.21,.166),(0,0,1))
            else:m.quad("canvas",(-.035,1.243,.164),(.035,1.243,.164),(.06,1.02,.171),(-.06,1.02,.171),(0,0,1))
        else:
            y=1.301 if name in ("Choker","Scarf") else 1.265
            mat="knit" if name=="Scarf" else "dark_metal" if name=="Choker" else "silver"
            for i in range(3 if name=="Scarf" else 1):m.ring(mat,(0,y+i*.02,0),.129,.109,"y",30)
            if name=="Scarf":m.box("knit",(.076,1.13,.143),(.115,.28,.035))
            elif name=="Chain Necklace":
                for i in range(7):m.ring("silver",((i-3)*.031,y-.02-.008*(3-abs(i-3)),.119),.021,.013,"z",12)
            else:m.cylinder("gold",(0,y-.041,.133),.021,.012,"z",12)
    else:
        mat="gold" if name=="Bangle" else "knit" if name=="Wrist Sweatband" else "canvas"
        for i in range(3 if name=="Wrist Sweatband" else 1):
            m.ring(mat,(0,-.404+i*.021,0),.085,.067,"y",24)
        if name=="Bracelet":
            for i in range(10):
                t=i*math.tau/10
                m.cylinder("accent",(.079*math.cos(t),-.404,.079*math.sin(t)),.016,.022,"y",12)
    return m

def preview(key, title, mesh):
    triangles = [(mat,vertices[i:i+3]) for mat,vertices in mesh.groups.items() for i in range(0,len(vertices),3)]
    points = [v[0] for _,tri in triangles for v in tri]
    def project(p):return p[0]+.38*p[2],-p[1]+.18*p[2]
    xy = [project(p) for p in points]
    lo = [min(p[i] for p in xy) for i in (0,1)]
    hi = [max(p[i] for p in xy) for i in (0,1)]
    scale=262/max(hi[0]-lo[0],hi[1]-lo[1],.001)
    image=Image.new("RGB",(384,384),"#152B3B")
    draw=ImageDraw.Draw(image)
    for mat,tri in sorted(triangles,key=lambda pair:sum(v[0][2]-.38*v[0][0] for v in pair[1])):
        polygon=[((x-(hi[0]+lo[0])/2)*scale+192,(y-(hi[1]+lo[1])/2)*scale+171) for x,y in (project(v[0]) for v in tri)]
        shade=.68+.32*max(0,tri[0][1][2])
        draw.polygon(polygon,fill=tuple(int(v*shade) for v in MATS[mat][0]))
    draw.text((22,337),title,fill="white")
    image.save(THUMBS/(key+".png"))

def main():
    path=BASE/"catalog.json"
    catalog=json.loads(path.read_text(encoding="utf-8"))
    ids={i["id"] for i in catalog["items"]}
    for slot,names in GROUPS.items():
        for title in names.split("|"):
            key="reference_"+title.lower().replace(" ","_")
            item_id=f"accessory.{slot}.{key}"
            mesh=build(title)
            mats=list(mesh.groups)
            write(key,title,mesh,mats)
            preview(key,title,mesh)
            tags=["hair_covering"] if title in ("Baseball Cap","Beanie","Bucket Hat") else []
            item={"id":item_id,"name":title,"category":"accessories","slot":slot,"scene":f"res://assets/cosmetics/accessories/models/{key}.gltf",
                  "thumbnail":f"res://assets/cosmetics/accessories/thumbnails/{key}.png","price":0,"starter":True,"rarity":"common",
                  "rig":"labvolt_toon_v1","tags":tags,"conflicts":["hair_volume_high","headwear_locked"] if tags else [],
                  "materials":{"primary_regions":[mats[0]],"accent_regions":mats[1:]},
                  "parameters":{"primary_color":{"type":"color","default":"".join(f"{v:02X}" for v in MATS[mats[0]][0])}}}
            if item_id not in ids:catalog["items"].append(item)
    path.write_text(json.dumps(catalog,indent=2),encoding="utf-8")

if __name__=="__main__":
    main()
