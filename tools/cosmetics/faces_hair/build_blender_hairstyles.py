"""Bake the Avatar Studio concept hairstyles with Blender.

Run: blender --background --factory-startup --python build_blender_hairstyles.py
"""
import json
import math
from pathlib import Path

import bpy
from mathutils import Vector

BASE = Path(__file__).resolve().parents[3] / "assets/cosmetics/faces_hair"
# Catalog IDs used by existing characters are retained for equivalent styles.
STYLES = [
    ("crop", "Classic Crop", "342730", "886457"),
    ("messy_spiky", "Messy Spiky", "5b3c36", "815649"),
    ("short_curls", "Short Fade", "32242b", "62434a"),
    ("undercut_sweep", "Undercut Sweep", "483239", "e2ad76"),
    ("side_part", "Side Part", "44313a", "74565d"),
    ("center_part", "Center Part", "3f2f38", "674e53"),
    ("quiff", "Textured Quiff", "50373b", "edba83"),
    ("buzz", "Buzz Cut", "40313b", "58434d"),
    ("pixie", "Pixie Cut", "743a4d", "99546a"),
    ("bald", "Bald", None, None),
    ("bob", "Short Bob", "503848", "da648e"),
    ("wavy_bob", "Wavy Bob", "db9d59", "f1c282"),
    ("lob", "Lob (Long Bob)", "503842", "e3ad75"),
    ("straight_long", "Straight Long", "412e40", "9261ac"),
    ("long_waves", "Wavy Long", "6f4439", "ae735a"),
    ("curly_long", "Curly Long", "503343", "8b586d"),
    ("layered", "Layered Medium", "343143", "77a7d3"),
    ("wolf", "Shag / Wolf Cut", "a95244", "f1b985"),
    ("half_bun", "Half-Up Bun", "533740", "a76c56"),
    ("ponytail", "High Ponytail", "dfab6e", "66abd3"),
    ("low_ponytail", "Low Ponytail", "503740", "d3a071"),
    ("twin_pigtails", "Twin Pigtails", "b34d77", "efc385"),
    ("braids", "Braided Pigtails", "634139", "e0a75f"),
    ("single_braid", "Single Braid", "593b3a", "c2925e"),
    ("crown_braid", "Crown Braid", "daa465", "f6cb89"),
    ("bun", "Top Bun", "5d403e", "e0ab69"),
    ("double_buns", "Double Buns", "4c324e", "ac69d5"),
    ("dreadlocks", "Dreadlocks", "382a30", "d8a36d"),
    ("cornrows", "Cornrows", "392930", "735049"),
    ("multicolor_spiky", "Multicolor Spiky", "332a41", "65c7e5"),
]
LONG = {"bob", "wavy_bob", "lob", "straight_long", "long_waves", "curly_long", "layered",
        "wolf", "half_bun", "ponytail", "low_ponytail", "twin_pigtails", "braids", "single_braid", "dreadlocks"}
LENGTHS = {key: ("short", "medium", "long") for key in LONG}
# Head-local sections, in the same coordinate system as the game.
HEAD = [(-.205,0,0),(-.19,.10,.10),(-.12,.195,.148),(.015,.225,.17),
        (.14,.205,.155),(.22,.135,.105),(.24,0,0)]

def xyz(v):
    return Vector((v[0], -v[2], v[1]))

def lerp(a, b, t):
    return a + (b - a) * t

def head_at(y):
    for a, b in zip(HEAD, HEAD[1:]):
        if y <= b[0]:
            t = max(0, (y-a[0])/(b[0]-a[0]))
            return lerp(a[1],b[1],t), lerp(a[2],b[2],t)
    return 0, 0

def material(name, hex_color, roughness):
    color = []
    for n in range(0, 6, 2):
        c = int(hex_color[n:n+2], 16) / 255
        color.append(c / 12.92 if c <= .04045 else ((c + .055) / 1.055) ** 2.4)
    mat = bpy.data.materials.new(name)
    mat.diffuse_color = (*color, 1)
    mat.use_nodes = True
    shader = next(node for node in mat.node_tree.nodes if node.type == "BSDF_PRINCIPLED")
    shader.inputs["Base Color"].default_value = (*color, 1)
    shader.inputs["Roughness"].default_value = roughness
    return mat

def mesh(name, verts, faces, mat, reverse=False):
    data = bpy.data.meshes.new(name)
    data.from_pydata([xyz(v) for v in verts], [], [tuple(reversed(f)) for f in faces] if reverse else faces)
    data.update()
    obj = bpy.data.objects.new(name, data)
    bpy.context.collection.objects.link(obj)
    data.materials.append(mat)
    for face in data.polygons:
        face.use_smooth = True
    return obj

def spline(points, t):
    n = len(points)-1
    i = min(int(t*n), n-1)
    u = t*n-i
    a,b,c,d = [points[max(0,min(n,j))] for j in (i-1,i,i+1,i+2)]
    return .5*((2*b) + (-a+c)*u + (2*a-5*b+4*c-d)*u*u + (-a+3*b-3*c+d)*u*u*u)

class Hair:
    def __init__(self, base, accent, key, length):
        self.key = key
        self.length = length
        self.main = material("hair", base or "342730", .65)
        self.accent = material("hair_highlight", accent or "725448", .60)
        self.third = material("hair_tip", "df5c96", .64) if key=="multicolor_spiky" else self.accent
        self.objects = []

    def scalp(self, height=.022, thickness=.014, front=.126, back=.003, ribs=0, crop=False):
        sides, bands = 64, 24
        verts, faces, highlights = [], [], []
        for j in range(bands):
            t=j/bands
            for i in range(sides):
                angle=math.tau*i/sides
                if crop and 11<=i<=14:
                    center=12.5*math.tau/sides
                    angle=center+(angle-center)*(.24+.76*math.sin(math.pi*t)**.5)
                depth=math.sin(angle)
                line=lerp(back,front,(depth+1)*.5) - .036*(1-depth*depth)
                line += .007*math.cos(3*angle+.25)
                y=lerp(line,.24,t)
                # Smooth the profiles around the avatar's low-poly head corners.
                radii = [head_at(max(line,min(.24,y+dy))) for dy in (-.005,0,.005)]
                rx,rz = [(radii[0][k]+2*radii[1][k]+radii[2][k])*.25 for k in (0,1)]
                detail=(.0025*math.cos(angle*ribs+t*5)*math.sin(math.pi*t)) if ribs else 0
                padding=(thickness+detail)*(1-t*t)
                x=math.cos(angle)*(rx+padding)
                crest=0
                if crop:
                    band=math.sin(math.pi*t)**1.6
                    groove=.77+.23*math.cos(113*x+depth*.82)
                    crest=.045*band*groove*(.61+.39*max(depth,0))
                verts.append((x,y+height*t*t+crest,depth*(rz+padding)))
        for j in range(bands-1):
            for i in range(sides):
                k=(i+1)%sides
                if crop and 11<=i<14:
                    highlights.append(len(faces))
                faces.append((j*sides+i,(j+1)*sides+i,(j+1)*sides+k,j*sides+k))
        verts.append((0,.24+height,0))
        start=(bands-1)*sides
        for i in range(sides):
            faces.append((start+i,len(verts)-1,start+(i+1)%sides))
        scalp=mesh("Scalp",verts,faces,self.main)
        if highlights:
            scalp.data.materials.append(self.accent)
            for index in highlights:
                scalp.data.polygons[index].material_index=1
        self.objects.append(scalp)

    def lock(self, coords, width, depth=.7, mat=None, steps=20, tip=.002, root=.18, taper=.44):
        """Build a closed, tapered spline with a transported elliptical section."""
        pts = [Vector(v) for v in coords]
        sides = 12
        verts, faces = [], []
        first = None
        for i in range(steps+1):
            t=i/steps
            center=spline(pts,t)
            tangent=(spline(pts,min(1,t+.004))-spline(pts,max(0,t-.004))).normalized()
            if first is None:
                # Start with the wide axis facing along the scalp, then transport
                # it down the curve without flipping when the tangent turns.
                first=tangent.cross(Vector((0,0,1)))
                if first.length < .05:
                    first=tangent.cross(Vector((0,1,0)))
            else:
                first=first-tangent*first.dot(tangent)
            first.normalize()
            second=tangent.cross(first)
            gain = lerp(root,1,math.sin(math.pi*t)**.38)*(1-taper*t)
            if i==steps:
                gain=0
            radius=tip+width*gain
            for j in range(sides):
                theta=math.tau*j/sides
                v=center+radius*(first*math.cos(theta)+second*math.sin(theta)*depth)
                verts.append(tuple(v))
        for i in range(steps):
            for j in range(sides):
                k=(j+1)%sides
                faces.append((i*sides+j,i*sides+k,(i+1)*sides+k,(i+1)*sides+j))
        faces += [tuple(reversed(range(sides))), tuple(steps*sides+j for j in range(sides))]
        self.objects.append(mesh("Sculpted lock",verts,faces,mat or self.main))

    def puff(self, center, scale, mat=None):
        bpy.ops.mesh.primitive_uv_sphere_add(segments=16, ring_count=10, location=xyz(center))
        obj=bpy.context.object
        obj.scale=(scale[0],scale[2],scale[1])
        obj.data.materials.append(mat or self.main)
        for face in obj.data.polygons:
            face.use_smooth=True
        self.objects.append(obj)

    def buzz(self, curls=False):
        self.scalp(.012,.009, .106 if curls else .137, .012 if curls else -.005, 32)
        if curls:
            for row in range(4):
                t=row/3
                for i in range(7-row):
                    theta=.04+math.pi*i/(6-row) if row<3 else .3+math.pi*i/3
                    x=math.cos(theta)*(.184-.04*t)
                    z=math.sin(theta)*(.119-.043*t)-.039*row
                    self.puff((x,.16+.031*row,z),(.043,.042,.048),self.accent if (i+row)%8==0 else None)

    def cropped(self):
        key=self.key
        if key=="crop":
            self.scalp(.030,.015,.129,.008,6,crop=True)
            return
        self.scalp(.055 if key=="quiff" else .035,.016,.123,.014)
        if key in {"undercut_sweep","quiff"}:
            tall=key=="quiff"
            for i in range(7):
                k=i-3
                self.lock([(k*.041,.188,-.101),(k*.041-.034,.232+.032*tall,.012),
                           (k*.041+.012,.265+.077*tall,.093),(k*.030+.108,.155+.145*tall+.013*k,.168)],
                          .049 if tall else .045,.70,self.accent if i in (4,5) else None)
        else:
            pixie=key=="pixie"
            vivid=key=="multicolor_spiky"
            for row in range(2):
                for i in range(7):
                    a=math.tau*(i+row*.40)/7
                    c,d=math.cos(a),math.sin(a)
                    direction=-1 if i%3==0 else 1
                    y=.214+.022*row
                    end_y=(.153 if pixie else .168) + .05*row + .04*math.sin(i*2.6)
                    mat=self.accent if vivid and (i in (0,1,6) or row==0 and i==5) else self.third if vivid and i in (2,3) else None
                    self.lock([(.074*c,y,.056*d),(.133*c,y+.048,.107*d),
                               (.198*c+.026*direction,y-.026,.158*d),(.246*c+.044*direction,end_y,.181*d)],
                              .054 if pixie else .064,.65,mat)

    def parted(self, center=False, strands=False, bangs=False):
        if bangs:
            for i in range(7):
                x=(i-3)*.043
                self.lock([(x*.62,.248,-.002),(x,.253,.10),(x,.199,.165),(x,.108+abs(x)*.17,.171)],.034,.66)
            return
        sides=(-1,1)
        split=0 if center else .090
        for side in sides:
            for i in range(4):
                root_x=split+.016*side
                start_z=-.054+i*.039
                wide_side = not center and side < 0
                width=.059+.011*wide_side
                end_x=side*(.199+.008*i)
                self.lock([(root_x,.231+.006*i,start_z),(lerp(root_x,end_x,.36),.266+.009*i,.029+i*.028),
                           (lerp(root_x,end_x,.84),.201-.015*i,.110+i*.011),(end_x,.112-.017*i,.078+i*.006)],
                          width,.68,self.accent if strands and i==3 else None)

    def curtain(self, drop, wave, fringe, tip_colors=False, ringlets=False):
        length = drop + self.length
        self.scalp(.036,.024,.137,-.045,6)
        for i in range(13):
            a=math.pi+math.pi*i/12
            c,d=math.cos(a),math.sin(a)
            coords=[(.095*c,.255,.08*d),(.205*c,.148,.176*d)]
            for j in range(1,9):
                t=j/8
                s=math.sin(t*math.tau*(2.2 if ringlets else 1.25)+i*.64)*wave
                y=lerp(.136,-length,t)+.02*math.sin(i*1.7)*t
                coords.append((c*(.204+s+.02*t),y,d*(.182+s)-.024*t))
            mat=self.accent if tip_colors and i in (0,1,11,12) else None
            self.lock(coords,.069 if ringlets else .072,.85,mat,steps=34,taper=.14)
        if fringe=="bangs":
            self.parted(bangs=True)
        else:
            self.parted(center=fringe=="center")
        for side in (-1,1):
            self.lock([(side*.07,.243,.111),(side*.153,.175,.164),(side*.20,.027,.11),
                       (side*(.214+wave),-.6*length,.143),(side*.157,-length,.096)],
                      .042 if tip_colors else .055,.72,self.accent if tip_colors else None, steps=26)

    def layered(self):
        wolf=self.key=="wolf"
        self.scalp(.025,.019,.134,-.036,8)
        for row in range(3):
            for i in range(8):
                a=math.pi+math.pi*i/7
                c,d=math.cos(a),math.sin(a)
                y=.201-.062*row
                end=.037-.095*row-self.length
                self.lock([(.15*c,y,.112*d),(.211*c,y-.033,.171*d),(.239*c,end-.040,.181*d),(.284*c,end+.018,.198*d)],
                          .058-.006*row,.69,self.accent if row==2 else None)
        self.parted(center=wolf,strands=False)

    def ties(self, center, radius, color=None):
        pts=[(center[0]+radius*math.cos(i*math.tau/16),center[1],center[2]+radius*math.sin(i*math.tau/16)) for i in range(17)]
        self.lock(pts,.010,1.0,color or self.accent,steps=32,tip=.006,root=1.0)

    def tail(self, center, lean, drop, accent=True):
        x,y,z=center
        self.puff((x,y-.023,z),(.069,.073,.060))
        for i in range(6):
            d=(i-2.5)*.021
            self.lock([(x+d*.45,y,z),(x+d+lean*.57,y-.049,z-.047),
                       (x+d+lean,y-drop*.61,z-.064),(x+d+lean*.92,y-drop-self.length,z-.039+.012*i)],
                      .049,.89,self.accent if accent and i==1 else None,steps=26,taper=.23)
        self.ties(center,.044)

    def braid(self, coords, size, ties=True):
        spine = [Vector(p) for p in coords]
        for j in range(3):
            pts=[]
            for i in range(45):
                t=i/44
                center=spline(spine,t)
                tangent=(spline(spine,min(1,t+.006))-spline(spine,max(0,t-.006))).normalized()
                side=tangent.cross(Vector((0,0,1))).normalized()
                normal=tangent.cross(side)
                theta=math.tau*(3.6*t+j/3)
                v=center+(side*math.cos(theta)+normal*math.sin(theta))*size*(1-.27*t)
                pts.append(tuple(v))
            self.lock(pts,size*.74,.82,self.accent if j==1 and not ties else None, steps=55,tip=.006)
        if ties:
            self.ties(coords[-1],size*.91)

    def bun(self, center, size):
        x,y,z=center
        self.puff(center,(size,.75*size,.88*size))
        for i in range(5):
            angle=math.tau*i/5
            c,d=math.cos(angle),math.sin(angle)
            self.lock([(x+size*c*.65,y-.04,z+size*d*.60),(x+size*c,y+.018,z+size*d*.88),
                       (x+size*c*.48,y+size*.72,z+size*d*.54),(x,y+size*.74,z)],size*.30,.76)
        self.ties((x,y-.046,z),size*.72)

    def rows(self, dangling=False):
        if not dangling:
            # Project each braid onto the head so the parts stay visible from
            # the front through the crown. No opaque scalp cap between rows.
            for row in range(8):
                latitude = (row-3.5)*.237
                coords = []
                for step in range(13):
                    angle = lerp(.43-.11*abs(latitude), 3.49, step/12)
                    direction = Vector((math.sin(latitude), math.cos(latitude)*math.sin(angle),
                                        math.cos(latitude)*math.cos(angle)))
                    low, high = 0, .26
                    for _ in range(15):
                        distance = (low+high)*.5
                        x, y, z = direction*distance
                        rx, rz = head_at(y)
                        if rx > 0 and (x/rx)**2+(z/rz)**2 < 1:
                            low = distance
                        else:
                            high = distance
                    coords.append(tuple(direction*(high+.012)))
                self.braid(coords,.014,ties=False)
            return
        self.scalp(.008,.010,.098,.01,28)
        for row in range(8):
            x=(row-3.5)*.051
            offset=(row%2)*.028
            self.lock([(x,.13,.158),(x*.92,.244+offset,.089),(x*.94,.267,-.055),(x*1.22,.16,-.163),
                       (x*1.34,-.10-self.length-.03*(row%3),-.20)],.033,.91,steps=27,tip=.012)
            self.puff((x*1.34,-.093-self.length-.03*(row%3),-.20),(.018,.025,.018),self.accent)

    def build(self):
        key=self.key
        if key=="bald":
            return
        if key in {"buzz","short_curls"}:
            self.buzz(key=="short_curls")
        elif key in {"crop","messy_spiky","undercut_sweep","quiff","pixie","multicolor_spiky"}:
            self.cropped()
        elif key in {"side_part","center_part"}:
            self.scalp(.027,.018,.124,-.012,7)
            self.parted(center=key=="center_part")
        elif key in {"layered","wolf"}:
            self.layered()
        elif key in {"bob","wavy_bob","lob","straight_long","long_waves","curly_long","half_bun"}:
            drop,wave,fringe,accent,curls={
                "bob":(.17,.005,"bangs",True,False), "wavy_bob":(.17,.040,"side",False,False),
                "lob":(.23,.014,"center",True,False), "straight_long":(.33,.0,"bangs",True,False),
                "long_waves":(.35,.044,"center",False,False), "curly_long":(.36,.069,"side",False,True),
                "half_bun":(.23,.018,"center",False,False)}[key]
            self.curtain(drop,wave,fringe,accent,curls)
            if key=="half_bun":
                self.bun((0,.281,-.105),.074)
        elif key in {"ponytail","low_ponytail","twin_pigtails"}:
            self.scalp(.035,.025,.136,-.038,13)
            self.parted(center=key=="twin_pigtails", strands=key!="ponytail")
            if key=="ponytail":
                self.tail((-.060,.253,-.125),-.154,.39)
            elif key=="low_ponytail":
                self.tail((-.081,-.012,-.145),-.146,.25,False)
            else:
                for side in (-1,1):
                    self.tail((side*.189,.156,-.063),side*.087,.31,False)
        elif key in {"braids","single_braid","crown_braid"}:
            self.scalp(.028,.020,.129,-.039,9)
            self.parted()
            if key=="crown_braid":
                for side in (-1,1):
                    self.braid([(side*.151,.08,.09),(side*.176,.19,.085),(side*.085,.274,.081),(0,.285,.022)],
                               .034,False)
                    self.lock([(side*.141,.174,.135),(side*.196,.048,.099),(side*.192,-.075,.127),(side*.166,-.182,.133)],.025)
            else:
                for side in ((-1,) if key=="single_braid" else (-1,1)):
                    self.braid([(side*.167,.087,-.101),(side*.225,-.032,-.065),(side*.217,-.163,.014),
                                (side*.223,-.280-self.length,.042)],.042)
        elif key in {"bun","double_buns"}:
            self.scalp(.029,.023,.130,-.042,8)
            self.parted(center=True,strands=key=="double_buns")
            if key=="bun":
                self.bun((0,.294,-.093),.096)
            else:
                for side in (-1,1):
                    self.bun((side*.187,.240,-.044),.097)
            for side in (-1,1):
                self.lock([(side*.144,.203,.13),(side*.204,.085,.107),(side*.193,-.066,.134),
                           (side*.146,-.176,.116)],.030,.71,self.accent if key=="double_buns" else None)
        else:
            self.rows(key=="dreadlocks")

    def export(self,path):
        bpy.ops.object.select_all(action="DESELECT")
        if self.objects:
            for obj in self.objects:
                obj.select_set(True)
            bpy.context.view_layer.objects.active=self.objects[0]
            bpy.ops.object.join()
            obj=bpy.context.object
            bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
        else:
            obj=bpy.data.objects.new("Bald", None)
            bpy.context.collection.objects.link(obj)
            obj.select_set(True)
            bpy.context.view_layer.objects.active=obj
        obj.name=self.key
        bpy.ops.export_scene.gltf(filepath=str(path), export_format="GLB", use_selection=True)
        return obj

def thumb_setup():
    skin=material("Thumbnail skin","e6b693",.74)
    dark=material("Thumbnail eyes","1d2630",.56)
    teal=material("Thumbnail clothing","468c9e",.74)
    proxy=Hair(None,None,"proxy",0)
    verts=[]
    sides=48
    for y,rx,rz in HEAD:
        for i in range(sides):
            a=math.tau*i/sides
            verts.append((math.cos(a)*max(.0002,rx), y, math.sin(a)*max(.0002,rz)))
    faces=[]
    for row in range(len(HEAD)-1):
        for i in range(sides):
            j=(i+1)%sides
            faces.append((row*sides+i,(row+1)*sides+i,(row+1)*sides+j,row*sides+j))
    mesh("Thumbnail head",verts,faces,skin)
    for side in (-1,1):
        proxy.puff((side*.22,-.009,.009),(.036,.054,.028),skin)
        proxy.puff((side*.087,.026,.151),(.014,.022,.010),dark)
    proxy.puff((0,-.045,.164),(.025,.026,.025),skin)
    proxy.puff((0,-.327,-.019),(.248,.11,.117),teal)
    proxy.puff((0,-.219,0),(.076,.071,.072),skin)
    bpy.ops.object.camera_add(location=xyz((.70,.21,1.55)))
    camera=bpy.context.object
    camera.rotation_euler=(xyz((0,-.026,0))-camera.location).to_track_quat("-Z","Y").to_euler()
    camera.data.type="ORTHO"
    camera.data.ortho_scale=.96
    scene=bpy.context.scene
    scene.camera=camera
    scene.render.engine="BLENDER_WORKBENCH"
    scene.render.resolution_x=384
    scene.render.resolution_y=384
    scene.render.resolution_percentage=100
    scene.render.film_transparent=True
    scene.display.shading.light="STUDIO"
    scene.display.shading.color_type="MATERIAL"
    scene.display.shading.show_shadows=False
    scene.display.shading.show_cavity=True
    scene.display.shading.cavity_type="WORLD"
    scene.view_settings.view_transform="Standard"
    scene.view_settings.exposure=.5
    return camera

def update_catalog():
    path=BASE/"catalog.json"
    document=json.loads(path.read_text(encoding="utf-8"))
    original={i["id"].split(".",1)[1]:i for i in document["items"] if i["category"]=="hair"}
    entries=[]
    params={
        "color":{"type":"color","default":"352b31"},
        "highlight":{"type":"color","default":"68504a"},
        "volume":{"type":"float","default":1,"min":.9,"max":1.12},
        "shine":{"type":"float","default":.25,"min":0,"max":1},
        "crown_lift":{"type":"float","default":1,"min":.8,"max":1.25},
        "side_volume":{"type":"float","default":1,"min":.95,"max":1.10},
    }
    model="res://assets/cosmetics/faces_hair/models/"
    thumbs="res://assets/cosmetics/faces_hair/thumbnails/"
    for index,(key,name,color,accent) in enumerate(STYLES):
        variants=LENGTHS.get(key,("default",))
        default="medium" if len(variants)>1 else "default"
        values={k:dict(v) for k,v in params.items()} if color else {}
        if color:
            values["color"]["default"]=color
            values["highlight"]["default"]=accent
        if key in {"side_part","center_part","buzz","wavy_bob","long_waves","curly_long","pixie","messy_spiky"}:
            values.pop("highlight",None)
        if key=="multicolor_spiky":
            values["tip_color"]={"type":"color","default":"df5c96"}
        definition={
            "id":"hair."+key,"name":name,"category":"hair","slot":"hair","rig":"labvolt_toon_v1",
            "scene":model+f"studio_{key}_{default}.glb","thumbnail":thumbs+f"studio_{key}.png",
            "price":0,"starter":True,"rarity":"common" if index<14 else "uncommon" if index<24 else "rare",
            "catalog_order":index+1,"tags":["head_hair"],"conflicts":[],"parameters":values,
        }
        if key in {"quiff","half_bun","bun","double_buns","twin_pigtails"}:
            definition["tags"].append("hair_volume_high")
        if len(variants)>1:
            values["length"]={"type":"enum","default":default,"values":list(variants)}
            definition["variants"]={v:model+f"studio_{key}_{v}.glb" for v in variants}
        entries.append(definition)
    document["items"]=[i for i in document["items"] if i["category"]!="hair"]+entries
    active={key for key,*_ in STYLES}
    for key,item in original.items():
        if key not in active:
            document["items"].append({**item,"legacy":True})
    path.write_text(json.dumps(document,indent=2),encoding="utf-8")

def remove_unused_assets():
    for pool in (bpy.data.meshes,bpy.data.materials):
        for data in list(pool):
            if not data.users:
                pool.remove(data)

def main():
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    camera=thumb_setup()
    remove_unused_assets()
    for key,_,base,accent in STYLES:
        for variant in LENGTHS.get(key,("default",)):
            hair=Hair(base,accent,key,{"short":-.05,"long":.07}.get(variant,0))
            hair.build()
            obj=hair.export(BASE/"models"/f"studio_{key}_{variant}.glb")
            if variant in {"default","medium"}:
                side_view=key in {"ponytail","low_ponytail","single_braid","dreadlocks"}
                camera.location=xyz((-.99 if side_view else -.40,.27,1.32))
                camera.rotation_euler=(xyz((0,-.024,0))-camera.location).to_track_quat("-Z","Y").to_euler()
                bpy.context.scene.render.filepath=str(BASE/"thumbnails"/f"studio_{key}.png")
                bpy.ops.render.render(write_still=True)
            bpy.data.objects.remove(obj,do_unlink=True)
            # Exported material names are the game's color-region keys.
            remove_unused_assets()
    update_catalog()

if __name__=="__main__":
    main()

