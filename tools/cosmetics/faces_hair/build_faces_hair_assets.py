"""Author original baked face, hair, and facial-hair collectible assets.

The generated glTF files contain UVs, normals, and named PBR material regions.
Geometry is baked offline; the runtime provider only selects variants and applies
instance-local material properties.
"""
from __future__ import annotations

import json
import math
import random
import struct
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[3]
BASE = ROOT / "assets" / "cosmetics" / "faces_hair"
MODEL = BASE / "models"
MATERIAL = BASE / "materials"
THUMB = BASE / "thumbnails"

MATS = {
    "skin_detail": ((222, 176, 140), 0.0, .67),
    "eye_white": ((247, 244, 232), 0.0, .42),
    "iris": ((57, 122, 131), 0.0, .34),
    "pupil": ((28, 31, 38), 0.0, .40),
    "brow": ((53, 43, 49), 0.0, .78),
    "lip": ((118, 59, 68), 0.0, .55),
    "mouth": ((39, 23, 32), 0.0, .82),
    "tongue": ((222, 118, 129), 0.0, .62),
    "freckle": ((155, 91, 71), 0.0, .76),
    "hair": ((53, 43, 49), 0.0, .70),
    "hair_highlight": ((104, 76, 67), 0.0, .62),
}

FACE_META = [("friendly","Openhearted",True,0,"common"),("serious","Steady Focus",True,0,"common"),("sleepy","Soft Morning",True,0,"common"),("bright","Bright Grin",False,160,"uncommon"),("determined","Determined",False,220,"uncommon"),("goofy","Mischief",False,310,"rare"), ("curious","Curious Glance",True,0,"common"), ("confident","Quiet Confidence",True,0,"common"), ("kindly","Kind Eyes",True,0,"common"), ("surprised","Wide Awake",True,0,"common"), ("relaxed","Easygoing",False,120,"common"), ("cheerful","Sunny Smile",True,0,"common"), ("stoic","Stone Calm",False,160,"uncommon"), ("scholar","Deep in Thought",False,150,"uncommon")]
HAIR_META = [("buzz","Clean Buzz",["default"],True,0,"common"),("crop","Textured Crop",["default"],True,0,"common"),("bob","Sculpted Bob",["short","medium","long"],True,0,"common"),("long_waves","Long Waves",["medium","long"],False,260,"rare"),("ponytail","High Ponytail",["short","long"],True,0,"uncommon"),("curly","Cloud Curls",["default"],False,320,"rare"),("bun","Braided Bun",["default"],False,390,"rare"), ("side_part","Side Part",["default"],True,0,"common"), ("crew","Campus Crew Cut",["default"],True,0,"common"), ("windswept","Windswept Fringe",["default"],False,175,"uncommon"), ("short_curls","Short Curls",["default"],True,0,"common")]
HAIR_META += [
    ("braids", "Twin Braids", ["default"], True, 0, "common"),
    ("quiff", "High Quiff", ["default"], True, 0, "common"),
    ("mohawk", "Razor Crest", ["default"], True, 0, "uncommon"),
    ("twin_puffs", "Twin Puffs", ["default"], True, 0, "uncommon"),
]
FACIAL_META = [("clean","Clean Shaven",["default"],True,0,"common"),("stubble","Fine Stubble",["default"],True,0,"common"),("short_beard","Short Beard",["default"],True,0,"common"),("full_beard","Full Beard",["short","long"],False,230,"uncommon"),("goatee","Trim Goatee",["default"],False,170,"uncommon"),("handlebar","Handlebar",["default"],False,285,"rare"), ("pencil","Pencil Moustache",["default"],True,0,"common"), ("chevron","Chevron Moustache",["default"],True,0,"common"), ("jawline","Jawline Beard",["default"],True,0,"common"), ("boxed","Boxed Beard",["default"],False,180,"uncommon"), ("pointed","Pointed Beard",["default"],False,220,"uncommon"), ("anchor","Anchor Beard",["default"],True,0,"common")]

FACIAL_META += [
    ("mutton_chops", "Mutton Chops", ["default"], True, 0, "uncommon"),
    ("soul_patch", "Soul Patch", ["default"], True, 0, "common"),
    ("imperial", "Imperial Moustache", ["default"], True, 0, "uncommon"),
    ("forked", "Forked Beard", ["default"], True, 0, "rare"),
]

# Reference-sheet collection. Keep the earlier IDs above so saved outfits and
# purchases continue to resolve to their original assets.
FACIAL_META += [
    (key, name, ["default"], True, 0, "common") for key, name in [
        ("thin_moustache", "Thin Moustache"),
        ("thick_moustache", "Thick Moustache"),
        ("curled_moustache", "Curled Moustache"),
        ("pencil_moustache", "Pencil Moustache"),
        ("sheet_stubble", "Stubble"),
        ("chin_strap", "Chin Strap"),
        ("sheet_soul_patch", "Soul Patch"),
        ("sheet_goatee", "Goatee"),
        ("extended_goatee", "Extended Goatee"),
        ("short_boxed_beard", "Short Boxed Beard"),
        ("sheet_full_beard", "Full Beard"),
        ("rounded_beard", "Rounded Beard"),
        ("van_dyke", "Van Dyke"),
        ("friendly_trimmed_beard", "Friendly Trimmed Beard"),
        ("rugged_medium_beard", "Rugged Medium Beard"),
    ]
]


class Mesh:
    def __init__(self): self.groups = {}
    def tri(self, mat, a, b, c, na, nb=None, nc=None, uv=((0,0),(1,0),(1,1))):
        normals = (na, nb or na, nc or na)
        cross = cross_product(subtract(b,a), subtract(c,a))
        if sum(cross[i]*sum(n[i] for n in normals) for i in range(3)) < 0:
            b,c = c,b
            normals = (normals[0],normals[2],normals[1])
            uv = (uv[0],uv[2],uv[1])
        self.groups.setdefault(mat, []).extend(zip((a,b,c),normals,uv))
    def ellipsoid(self, mat, center, scale, rings=8, segments=14, front_only=False):
        cx,cy,cz=center; sx,sy,sz=scale
        start = 0 if not front_only else 1
        for r in range(start, rings):
            # Keep latitude rings infinitesimally off the poles so every baked
            # triangle has measurable area (the tiny caps remain visually closed).
            v0=r/rings; v1=(r+1)/rings; eps=.018
            p0=-math.pi/2+eps+(math.pi-2*eps)*v0; p1=-math.pi/2+eps+(math.pi-2*eps)*v1
            for s in range(segments):
                u0=s/segments; u1=(s+1)/segments; a0=2*math.pi*u0; a1=2*math.pi*u1
                def pt(p,a): return (cx+sx*math.cos(p)*math.cos(a),cy+sy*math.sin(p),cz+sz*math.cos(p)*math.sin(a))
                def no(p,a):
                    x=math.cos(p)*math.cos(a)/sx; y=math.sin(p)/sy; z=math.cos(p)*math.sin(a)/sz; q=math.sqrt(x*x+y*y+z*z)
                    return (x/q,y/q,z/q)
                q0,q1,q2,q3=pt(p0,a0),pt(p0,a1),pt(p1,a1),pt(p1,a0); n0,n1,n2,n3=no(p0,a0),no(p0,a1),no(p1,a1),no(p1,a0)
                self.tri(mat,q0,q1,q2,n0,n1,n2,((u0,v0),(u1,v0),(u1,v1))); self.tri(mat,q0,q2,q3,n0,n2,n3,((u0,v0),(u1,v1),(u0,v1)))
    def tube(self, mat, points, radius=.006, segments=10):
        rings = []
        for i, p in enumerate(points):
            tangent = unit(subtract(points[min(i+1,len(points)-1)],points[max(i-1,0)]))
            ref = (0,1,0) if abs(tangent[1])<.85 else (1,0,0)
            if i:
                # Transport the previous cross-section through the bend.
                ref = previous_up
            side = unit(cross_product(tangent,ref))
            previous_up = unit(cross_product(side,tangent))
            size = radius[i] if isinstance(radius,list) else radius
            ring=[]
            for j in range(segments):
                angle = math.tau*j/segments
                n = tuple(side[k]*math.cos(angle)+previous_up[k]*math.sin(angle) for k in range(3))
                ring.append((tuple(p[k]+size*n[k] for k in range(3)),n))
            rings.append(ring)
        for i in range(len(rings)-1):
            for j in range(segments):
                k=(j+1)%segments
                a,na=rings[i][j]; b,nb=rings[i][k]; c,nc=rings[i+1][k]; d,nd=rings[i+1][j]
                self.tri(mat,a,b,c,na,nb,nc); self.tri(mat,a,c,d,na,nc,nd)
        for index, direction in [(0,-1),(-1,1)]:
            n=unit(subtract(points[-1],points[-2]) if direction>0 else subtract(points[0],points[1]))
            for j in range(segments):
                self.tri(mat,points[index],rings[index][j][0],rings[index][(j+1)%segments][0],n)

def subtract(a,b):
    return tuple(a[i]-b[i] for i in range(3))

def cross_product(a,b):
    return (a[1]*b[2]-a[2]*b[1], a[2]*b[0]-a[0]*b[2], a[0]*b[1]-a[1]*b[0])

def unit(v):
    size=math.sqrt(sum(x*x for x in v))
    return tuple(x/max(size,1e-10) for x in v)

# Head-local cross sections from Toon.build(). All cosmetics inherit the head scale.
HEAD = [(-.205,0,0),(-.19,.10,.10),(-.12,.195,.148),(.015,.225,.17),(.14,.205,.155),(.22,.135,.105),(.24,0,0)]

def head_radii(y):
    for a,b in zip(HEAD,HEAD[1:]):
        if y<=b[0]:
            t=max(0,(y-a[0])/(b[0]-a[0]))
            return (a[1]+(b[1]-a[1])*t,a[2]+(b[2]-a[2])*t)
    return 0,0

def skin_front(x,y):
    rx,rz=head_radii(y)
    if rx < .0001:
        return 0
    return rz*math.sqrt(max(0,1-(x/rx)**2))

def seat_on_face(mesh):
    for material, vertices in mesh.groups.items():
        result=[]
        for (x,y,z),(nx,ny,nz),uv in vertices:
            step=.0001
            dx=(skin_front(x+step,y)-skin_front(x-step,y))/(2*step)
            dy=(skin_front(x,y+step)-skin_front(x,y-step))/(2*step)
            result.append(((x,y,skin_front(x,y)+z),unit((nx-dx*nz,ny-dy*nz,nz)),uv))
        mesh.groups[material]=result
    return mesh

# The combing ridges and dyed sections belong to the same continuous scalp mesh.
COMBED = {
    "crew": (.024, 5, .24, .40), "crop": (.034, 7, -.35, .70),
    "side_part": (.048, 4, 1.38, .52), "windswept": (.063, 4, -1.1, .85),
    "quiff": (.106, 5, .50, 1.05),
}


def scalp(mesh, mat, height, thickness, line, style):
    sectors, bands = 80, 32
    comb = COMBED.get(style)

    def profile(angle, t):
        c,d=math.cos(angle),math.sin(angle)
        hairline=line + .074*d - .016*max(0,d)**3
        y=hairline+(.24-hairline)*t
        rx,rz=head_radii(y)
        extra=thickness*(1-t*t)
        return c*(rx+extra),y+height*t*t,d*(rz+extra)

    # Round off the transitions between the original head sections.
    def point(angle, t):
        blend = .04
        low = profile(angle, max(0,t-blend))
        mid = profile(angle, t)
        high = profile(angle, min(1,t+blend))
        x,y,z = tuple((low[i]+2*mid[i]+high[i])*.25 for i in range(3))
        if comb:
            lift, ridges, drift, front = comb
            az = angle + drift*t
            crest = .74 + .26*math.cos(az*ridges)
            fade = math.sin(math.pi*t)**1.5
            swell = lift * fade * crest * (.72 + front*.36*max(0,math.sin(angle)))
            x += .28*swell*math.cos(angle)
            y += swell
            z += .28*swell*math.sin(angle)
        return x,y,z

    def normal(angle,t):
        da = subtract(point(angle+.003,t),point(angle-.003,t))
        dt = subtract(point(angle,min(1,t+.003)),point(angle,max(0,t-.003)))
        return unit(cross_product(dt,da))

    def angle_at(index, t):
        u=index/sectors
        if comb:
            # Move both edges of each pigment strip together with the flow.
            # Taper by easing the strip edges toward their center at either end.
            for start,end in ((13,16),(28,31)):
                if start <= index <= end:
                    center=(start+end)*.5/sectors
                    taper=.18+.82*math.sin(math.pi*t)**.65
                    u=center+(u-center)*taper
            u-=comb[2]*t/math.tau
        return u*math.tau

    rows=[]
    for band in range(bands+1):
        t=band/bands
        angles=[angle_at(i,t) for i in range(sectors)]
        rows.append([(point(a,t),normal(a,t)) for a in angles])
    for band in range(bands):
        t0,t1=band/bands,(band+1)/bands
        for i in range(sectors):
            u,v=i/sectors,(i+1)/sectors
            j=(i+1)%sectors
            a,na=rows[band][i]; b,nb=rows[band][j]
            c,nc=rows[band+1][j]; d,nd=rows[band+1][i]
            region = "hair_highlight" if comb and (13<=i<16 or 28<=i<31) else mat
            mesh.tri(region,a,b,c,na,nb,nc,uv=((u,t0),(v,t0),(v,t1)))
            mesh.tri(region,a,c,d,na,nc,nd,uv=((u,t0),(v,t1),(u,t1)))
    for i in range(sectors):
        a,na=rows[-1][i]; b,nb=rows[-1][(i+1)%sectors]
        mesh.tri(mat,a,b,(0,.24+height,0),na,nb,(0,1,0))

# Shared by the 3D face and its flat catalog illustration.
FACE_SHAPES = {
    "friendly": ("round", "arched", "smile"),
    "serious": ("narrow", "stern", "frown"),
    "sleepy": ("sleepy", "flat", "tiny"),
    "bright": ("happy", "arched", "teeth"),
    "determined": ("narrow", "stern", "clench"),
    "goofy": ("wink", "raised", "tongue"),
    "curious": ("round", "raised", "purse"),
    "confident": ("almond", "raised", "smirk"),
    "kindly": ("dots", "arched", "smile"),
    "surprised": ("wide", "high", "gasp"),
    "relaxed": ("closed", "flat", "tiny"),
    "cheerful": ("happy", "high", "laugh"),
    "stoic": ("dots", "flat", "flat"),
    "scholar": ("side_eye", "raised", "worry"),
}


def face(kind, icon=None):
    mesh = Mesh()
    eyes, brows, mouth = FACE_SHAPES[kind]
    inks = {"pupil": "#18212d", "brow": "#312335", "mouth": "#302033", "lip": "#73394d",
            "skin_detail": "#dc9c78", "iris": "#428f95", "freckle": "#ad635d"}
    def ink(mat):
        return inks.get(mat, MATS[mat][0])

    def pixel(point):
        return (192 + point[0] * 880, 194 - point[1] * 880)

    def ellipse(mat, x, y, z, rx, ry, depth):
        mesh.ellipsoid(mat, (x,y,z), (rx,ry,depth), 8, 18)
        if icon is not None:
            icon.ellipse([pixel((x-rx,y+ry)),pixel((x+rx,y-ry))],fill=ink(mat))

    def curve(mat, points, radius, depth=.002):
        mesh.tube(mat, [(x,y,depth) for x,y in points], radius, 8)
        if icon is not None:
            line = [pixel(point) for point in points]
            icon.line(line, fill=ink(mat), width=max(2,round(radius*1760)), joint="curve")
            r = radius*880
            for x,y in (line[0],line[-1]):
                icon.ellipse((x-r,y-r,x+r,y+r),fill=ink(mat))

    def face_strip(mat, upper, lower, depth):
        # A tall triangle spans the curve of the jaw and can cut through the skin.
        # Sample across the opening before seat_on_face projects it onto the head.
        rows = max(1, math.ceil(max(a[1]-b[1] for a,b in zip(upper,lower)) / .005))
        normal = (0,0,1)
        for i in range(len(upper)-1):
            def point(column, row):
                x, top = upper[column]
                return (x, top + (lower[column][1]-top)*row/rows, depth)
            for row in range(rows):
                a, b = point(i,row), point(i,row+1)
                d, c = point(i+1,row), point(i+1,row+1)
                if a != b: mesh.tri(mat,a,b,c,normal)
                if c != d: mesh.tri(mat,a,c,d,normal)
        if icon is not None:
            icon.polygon([pixel(p) for p in upper + lower[::-1]],fill=ink(mat))

    for side in (-1, 1):
        x = side*.091
        if eyes in ("canted", "classic", "imp"):
            # Rotate the eye outline as a solid, shallow relief on the head.
            angle = side*(.76 if eyes=="canted" else .08)
            if eyes=="canted":
                for ring in range(12):
                    a,b=math.tau*ring/12,math.tau*(ring+1)/12
                    def tilted(theta):
                        u,v=.023*math.cos(theta),.013*math.sin(theta)
                        return x+u*math.cos(angle)-v*math.sin(angle), .028+u*math.sin(angle)+v*math.cos(angle)
                    a,b=tilted(a),tilted(b)
                    mesh.tri("pupil",(x,.028,.012),(*a,-.002),(*b,-.002),(0,0,1))
                if icon is not None:
                    icon.polygon([pixel(tilted(math.tau*i/24)) for i in range(24)],fill=ink("pupil"))
            else:
                ellipse("pupil",x,.031,.002,.016,.027,.009)
                if eyes=="imp":
                    ellipse("iris",x,.024,.010,.014,.016,.004)
                    ellipse("eye_white",x-.006,.046,.012,.004,.005,.003)
        elif eyes=="hooded":
            lid=[(x+u,.035+side*u*.09) for u in [(i/16*2-1)*.047 for i in range(17)]]
            lower=[(u,y-.017*math.sin(math.pi*i/16)) if 0<i<16 else (u,y) for i,(u,y) in enumerate(lid)]
            face_strip("eye_white",lid,lower,.005)
            ellipse("pupil",x,.028,.008,.014,.009,.004)
            ellipse("eye_white",x-.005,.031,.012,.0025,.0025,.0015)
            curve("brow",lid,.003,.012)
        elif eyes=="human":
            xs=[x+(i/20-.5)*.098 for i in range(21)]
            arch=[math.sin(math.pi*i/20) if 0<i<20 else 0 for i in range(21)]
            upper=[(u,.026+.031*a) for u,a in zip(xs,arch)]
            lower=[(u,.026-.023*a) for u,a in zip(xs,arch)]
            face_strip("eye_white",upper,lower,.005)
            ellipse("pupil",x,.027,.007,.019,.021,.006)
            curve("brow",upper,.004,.006)
            curve("brow",lower,.003,.006)
        elif eyes=="half_lid":
            ellipse("eye_white",x,.026,-.002,.042,.017,.009)
            ellipse("pupil",x,.025,.007,.020,.0148,.006)
            curve("brow",[(x-.042,.039),(x,.042),(x+.042,.039)],.005)
        elif eyes in ("happy", "closed") or (eyes=="wink" and side==1):
            height = .024 if eyes in ("happy", "wink") else .004
            points = [(x+(i/12-.5)*.082,.024+height*math.sin(math.pi*i/12)) for i in range(13)]
            curve("brow",points,.005)
        elif eyes == "dots":
            ellipse("pupil",x,.028,.003,.015,.026,.009)
        else:
            ex,ey={"round":(.043,.055),"wide":(.045,.066),"sleepy":(.047,.019),
                "narrow":(.041,.025),"almond":(.047,.031),"wink":(.033,.050),"side_eye":(.040,.032)}[eyes]
            eye_y=.028
            pupil_x=x+.014 if eyes=="side_eye" else x
            ellipse("eye_white",x,eye_y,-.002,ex,ey,.012)
            ellipse("iris",pupil_x,eye_y,.008,ex*.51,ey*.70,.006)
            ellipse("pupil",pupil_x,eye_y,.012,ex*.28,ey*.45,.004)
            ellipse("eye_white",pupil_x-.005,eye_y+ey*.20,.017,.004,.005,.002)
            if eyes in ("narrow","sleepy","almond","side_eye"):
                slope=.017 if eyes=="narrow" else -.010 if eyes=="almond" else 0
                curve("brow",[(x+(i/12-.5)*ex*2,eye_y+ey*.72+.010*math.sin(math.pi*i/12)+side*slope*(i/12-.5)) for i in range(13)],.004)

        brow_y=.112 if eyes=="wide" else .101
        if brows=="none": continue
        arch,tilt={"arched":(.021,0),"flat":(.003,0),"stern":(.008,.053),
            "raised":(.030 if side==1 else .011,.012),"high":(.027,0),"asym":(.036 if side==1 else .016,.018)}[brows]
        if brows=="high": brow_y+=.009
        curve("brow",[(x+(i/12-.5)*.073,brow_y+arch*math.sin(math.pi*i/12)+side*tilt*(i/12-.5)) for i in range(13)],.004)

    ellipse("skin_detail",0,-.038,.003,.022 if kind=="sleepy" else .028,.025,.021)
    if mouth in ("crescent", "crooked", "dimpled", "toothy_smirk"):
        width = .105 if mouth=="dimpled" else .080
        xs=[(i/24*2-1)*width for i in range(25)]
        slant = .30 if mouth in ("crooked", "toothy_smirk") else 0
        lift = .036 if mouth=="dimpled" else .027
        top=[(x,-.107+lift*(x/width)**2+x*slant) for x in xs]
        opening = {"crescent":.030,"dimpled":.038}.get(mouth,.023)
        bottom=[(x,y-opening*math.sin(math.pi*i/24)) if 0<i<24 else (x,y) for i,(x,y) in enumerate(top)]
        face_strip("mouth",top,bottom,.0035)
        curve("lip",bottom,.003,.004)
        if mouth in ("dimpled","toothy_smirk"):
            teeth_top=[(x,y-.003) for x,y in top[3:-3]]
            teeth_floor=[(x,y-(.023*math.sin(math.pi*(i+3)/24) if mouth=="dimpled" else .007)) for i,(x,y) in enumerate(teeth_top)]
            face_strip("eye_white",teeth_top,teeth_floor,.006)
        if mouth=="dimpled":
            for side in (-1,1):
                ellipse("mouth",side*.012,-.051,.018,.005,.0028,.003)
    elif mouth in ("gasp","purse"):
        w,h=(.034,.032) if mouth=="gasp" else (.018,.012)
        ellipse("lip",0,-.110,-.001,w+.005,h+.004,.006)
        ellipse("mouth",0,-.110,.004,w,h,.004)
    elif mouth in ("teeth","clench","tongue","laugh","double_grin"):
        width, height, lift={"teeth":(.081,.028,.026),"clench":(.066,.018,-.014),
            "tongue":(.071,.027,.020),"laugh":(.084,.046,.026),"double_grin":(.106,.042,.034)}[mouth]
        xs=[(i/20*2-1)*width for i in range(21)]
        base=[-.112+lift*(x/width)**2+(.18*x if mouth=="tongue" else 0) for x in xs]
        radius=[max(.001,height*math.sin(math.pi*i/20)) for i in range(21)]
        upper=[(x,y+r*.37) for x,y,r in zip(xs,base,radius)]
        lower=[(x,y-r*.65) for x,y,r in zip(xs,base,radius)]
        face_strip("mouth",upper,lower,.0035)
        if mouth in ("teeth","clench","laugh","double_grin"):
            teeth_floor=[(x,y-r*(.12 if mouth!="clench" else .36)) for x,y,r in zip(xs,base,radius)]
            face_strip("eye_white",upper[2:-2],teeth_floor[2:-2],.006)
        if mouth=="double_grin":
            lower_teeth=[(x,y+r*.24) for (x,y),r in zip(lower,radius)]
            face_strip("eye_white",lower_teeth[3:-3],lower[3:-3],.006)
        if mouth=="tongue":
            ellipse("tongue",.025,-.132,.005,.025,.014,.005)
        curve("lip",upper,.003)
        curve("lip",lower,.003)
    else:
        width,lift,slant={"smile":(.066,.028,0),"closed_smile":(.065,.015,.04),"tiny":(.028,.004,0),"flat":(.058,0,0),
            "frown":(.060,-.026,0),"smirk":(.063,.013,.29),"worry":(.059,-.021,-.13),"classic_smile":(.079,.049,0)}[mouth]
        curve("lip",[(x,-.121+lift*(x/width)**2+x*slant) for x in [(i/20*2-1)*width for i in range(21)]],.0045,.0035)
    if kind in ("friendly","goofy","kindly","cheerful"):
        for side in (-1,1):
            for j in range(3):
                ellipse("freckle",side*(.104+j*.012),-.040-(j%2)*.010,.001,.0025,.0023,.0015)
    if kind == "storm_chaser":
        curve("lip", [(.118,-.020),(.110,-.039),(.119,-.051),(.105,-.073)],.0035,.003)
    if kind == "starstruck":
        for x,y in ((-.120,-.052),(.120,-.044)):
            curve("iris",[(x-.013,y),(x+.013,y)],.003,.003)
            curve("iris",[(x,y-.014),(x,y+.014)],.003,.003)
    return seat_on_face(mesh)

FACE_META += [
    ("big_laugh", "Belly Laugh", True, 0, "common"),
    ("deadpan", "Deadpan", True, 0, "common"),
    ("side_smirk", "Side-Eye Smirk", True, 0, "uncommon"),
    ("stage_fright", "Stage Fright", True, 0, "uncommon"),
    ("arched_crook", "Sly Smile", True, 0, "uncommon"),
    ("hooded_grin", "Midnight Grin", True, 0, "rare"),
    ("classic_smile", "Classic Smile", True, 0, "common"),
    ("dimpled_grin", "Double Take", True, 0, "rare"),
    ("imp_grin", "Impish Grin", True, 0, "rare"),
    ("half_lid", "Unbothered", True, 0, "uncommon"),
    ("quick_wink", "Quick Wink", True, 0, "common"),
    ("shocked", "Speechless", True, 0, "common"),
    ("fed_up", "Fed Up", True, 0, "common"),
    ("storm_chaser", "Storm Chaser", False, 480, "epic"),
    ("starstruck", "Starstruck", False, 940, "legendary"),
]
FACE_SHAPES.update({
    "big_laugh": ("happy", "flat", "laugh"),
    "deadpan": ("sleepy", "stern", "flat"),
    "side_smirk": ("side_eye", "raised", "smirk"),
    "stage_fright": ("wide", "raised", "worry"),
    "arched_crook": ("canted", "asym", "crooked"),
    "hooded_grin": ("hooded", "none", "double_grin"),
    "classic_smile": ("classic", "none", "classic_smile"),
    "dimpled_grin": ("human", "arched", "dimpled"),
    "imp_grin": ("imp", "stern", "toothy_smirk"),
    "half_lid": ("half_lid", "none", "closed_smile"),
    "quick_wink": ("wink", "asym", "tongue"),
    "shocked": ("classic", "high", "gasp"),
    "fed_up": ("closed", "stern", "frown"),
    "storm_chaser": ("canted", "stern", "crooked"),
    "starstruck": ("wide", "asym", "double_grin"),
})


def write_face(key, title):
    image = Image.new("RGBA", (384, 384))
    draw = ImageDraw.Draw(image)
    draw.rounded_rectangle((28,28,356,356), radius=50, fill="#ecd6be")
    write_gltf(f"face_{key}", title, face(key, draw))
    image.save(THUMB/f"face_{key}.png")


def swept_lock(mesh, material, start, middle, end, bulk, tip=.003):
    points=[]
    radii=[]
    for i in range(17):
        t=i/16
        points.append(tuple((1-t)**2*a+2*t*(1-t)*b+t*t*c for a,b,c in zip(start,middle,end)))
        radii.append(tip + bulk*(1-.70*t)*(.67+.33*math.sin(math.pi*t)))
    mesh.tube(material, points, radii, 12)


def hair(kind, length="default"):
    mesh=Mesh()
    h,a="hair","hair_highlight"
    profiles={
        "buzz":(.008,.008,.065), "crew":(.015,.012,.073), "crop":(.025,.019,.070),
        "bob":(.039,.030,.056), "long_waves":(.041,.027,.062), "ponytail":(.022,.017,.063),
        "curly":(.045,.024,.071), "bun":(.024,.019,.064), "side_part":(.034,.022,.071),
        "windswept":(.042,.024,.073), "short_curls":(.023,.017,.072),
        "braids":(.020,.017,.064), "quiff":(.032,.023,.074), "mohawk":(.009,.012,.079),
        "twin_puffs":(.031,.020,.071),
    }
    scalp(mesh,h,*profiles[kind],kind)
    if kind=="buzz" or kind in COMBED:
        return mesh
    elif kind in ("bob","long_waves"):
        drop={"short":.14,"medium":.23,"long":.32}[length] if kind=="bob" else {"medium":.34,"long":.48}[length]
        for side in (-1,1):
            for i in range(7):
                z=.10-i*.041
                tips=[]
                for j in range(13):
                    t=j/12
                    wave=.034*math.sin(t*math.tau*1.3+i*.57)*t if kind=="long_waves" else .024*math.sin(math.pi*t)
                    tips.append((side*(.132+.095*math.sin(t*math.pi*.72)+wave), .202-(.22+drop*.67+i*.004)*t, z-.036*t))
                mesh.tube(a if i in (2,6) else h,tips,[.029+.024*math.sin(math.pi*j/12)**.65 for j in range(13)],12)
            swept_lock(mesh,h,(side*.031,.243,.101),(side*.104,.204,.195),(side*.178,.125,.129),.048)
    elif kind=="ponytail":
        for i in range(8):
            x=(i-3.5)*.042
            swept_lock(mesh,a if i==2 else h,(x,.163,.119),(x,.300,.015),(0,.231,-.179),.029)
        mesh.ellipsoid(a,(0,.238,-.184),(.071,.046,.047),9,16)
        drop={"short":.26,"long":.43}[length]
        for i in range(5):
            x=(i-2)*.026
            swept_lock(mesh,a if i==3 else h,(x,.223,-.191),(x+.028,.21-drop*.35,-.323),(x+.070,.184-drop,-.239),.052)
        for side in (-1,1):
            swept_lock(mesh,h,(side*.110,.218,.099),(side*.194,.143,.154),(side*.201,.018,.096),.026)
    elif kind in ("short_curls","curly","twin_puffs"):
        if kind=="twin_puffs":
            for side in (-1,1):
                swept_lock(mesh,h,(side*.045,.20,.129),(side*.139,.308,.030),(side*.202,.243,-.025),.050)
            centers=[(side*.228,.261,-.022) for side in (-1,1)]
        else:
            centers=[(0,.197,0)]
        for cx,cy,cz in centers:
            for i in range(18 if kind=="short_curls" else 22):
                angle=i*2.39996
                t=i/(17 if kind=="short_curls" else 21)
                spread=.125 if kind=="twin_puffs" else .205
                scale=.035 if kind=="short_curls" else .057
                x=cx+spread*math.cos(angle)*math.sqrt(t)
                y=cy+(1-t)*(.087 if kind=="short_curls" else .130)
                z=cz+.82*spread*math.sin(angle)*math.sqrt(t)
                points=[]
                for j in range(14):
                    u=j/13
                    spin=u*math.tau*1.05+angle
                    points.append((x+math.cos(spin)*scale*u,y+math.sin(spin)*scale*u,z+(.032 if kind=="short_curls" else .057)*u))
                mesh.tube(a if i%7==2 else h,points,[.025-.012*j/13 for j in range(14)],10)
    elif kind in ("bun","braids"):
        for side in (-1,1):
            for i in range(4):
                swept_lock(mesh,h,(side*(.03+i*.042),.147,.128),(side*(.15+i*.014),.30,.017),(side*.17,.171,-.146),.029)
        for side in (-1,1):
            for i in range(3):
                points=[]
                for j in range(32):
                    t=j/31; angle=t*math.tau*(2.4 if kind=="braids" else 1.5)+i*math.tau/3
                    if kind=="braids":
                        points.append((side*(.176+.068*t)+.025*math.cos(angle),.144-.430*t,-.109+.033*math.sin(angle)+.121*t))
                    else:
                        points.append((side*.062+(.066-.024*t)*math.cos(angle),.230+.102*t,-.114+(.074-.025*t)*math.sin(angle)))
                mesh.tube(a if i==1 else h,points,[.028-.011*j/31 for j in range(32)],10)
    elif kind=="mohawk":
        for i in range(10):
            z=.141-i*.031
            swept_lock(mesh,a if i in (1,6) else h,(0,.194,z-.035),(.018,.376,z),(.014,.344-.005*i,z-.036),.040)
        for side in (-1,1):
            swept_lock(mesh,a,(side*.176,.126,.094),(side*.223,.104,.043),(side*.205,.110,-.069),.007)
    return mesh


EXTRA_FACIAL = [
    ("french_curl","French Curl Moustache",["default"],True,0,"common"),
    ("western_droop","Western Droop Moustache",["default"],True,0,"common"),
    ("toothbrush","Toothbrush Moustache",["default"],False,1250,"legendary"),
    ("long_sage","Long Sage Beard",["default"],True,0,"common"),
]
REFERENCE_FACIAL_KEYS = {key for key, *_ in FACIAL_META[-15:]}
FACIAL_META.extend(EXTRA_FACIAL)


def distinctive_facial(kind):
    mesh = Mesh()
    if kind == "toothbrush":
        for x in (-.016,-.008,0,.008,.016):
            mesh.tube("hair",[(x,-.067,.006),(x,-.079,.011),(x,-.091,.006)],.006)
    elif kind == "french_curl":
        for side in (-1,1):
            points = [(side*x,y,.007) for x,y in
                      [(0,-.078),(.025,-.084),(.062,-.097),(.092,-.096),(.114,-.078)]]
            for i in range(1,22):
                t=math.tau*i/26
                points.append((side*(.100+.014*math.cos(t)),-.078+.018*math.sin(t),.009))
            mesh.tube("hair",points,[.010*(1-i/len(points))+.0015 for i in range(len(points))])
    elif kind == "western_droop":
        for side in (-1,1):
            points=[(side*x,y,.009) for x,y in
                    [(0,-.079),(.033,-.077),(.063,-.087),(.086,-.108),(.090,-.142),(.080,-.168)]]
            mesh.tube("hair",points,[.011,.017,.017,.015,.011,.003])
    else:
        for side in (-1,1):
            mesh.tube("hair",[(0,-.081,.009),(side*.051,-.086,.012),(side*.080,-.109,.013),
                              (side*.091,-.159,.025),(side*.105,-.187,.060)],[.009,.012,.010,.006,.0015])
        for strand in range(-2,3):
            x=strand*.013
            mesh.tube("hair",[(x,-.150,.009),(x*1.2,-.198,.029),(x*.8,-.245,.086),
                             (x*.25,-.302,.120)],[.013,.015,.009,.002])
    return seat_on_face(mesh)


def facial(kind, length="default"):
    m=Mesh(); H="hair"; A="hair_highlight"
    if kind in {entry[0] for entry in EXTRA_FACIAL}:return distinctive_facial(kind)
    sheet_styles=REFERENCE_FACIAL_KEYS
    if kind in sheet_styles:
        moustaches={"thin_moustache":(.005,.079,0), "thick_moustache":(.015,.093,0),
                    "curled_moustache":(.011,.120,1), "pencil_moustache":(.0028,.073,0)}
        if kind in moustaches or kind in ("short_boxed_beard", "sheet_full_beard", "rounded_beard", "van_dyke", "friendly_trimmed_beard", "rugged_medium_beard", "extended_goatee"):
            bulk, reach, curl=moustaches.get(kind, (.008,.083,0))
            for side in (-1,1):
                points=[(side*(.009+reach*i/12),-.083-.012*math.sin(math.pi*i/12)+curl*.044*(i/12)**5,.003) for i in range(13)]
                m.tube(H,points,[bulk*(.45+.55*math.sin(math.pi*(i+.5)/13)) for i in range(13)])
        if kind in ("sheet_stubble", "chin_strap", "short_boxed_beard", "sheet_full_beard", "rounded_beard", "friendly_trimmed_beard", "rugged_medium_beard"):
            if kind=="sheet_stubble":
                rng=random.Random(615)
                for side in (-1,1):
                    for _ in range(155):
                        x=rng.uniform(.015,.174); y=rng.uniform(-.18,-.057)
                        if x>head_radii(y)[0]*.92: continue
                        r=rng.uniform(.0015,.0035)
                        m.ellipsoid(H,(side*x,y,.002),(r,r*1.5,.0014),4,6)
            else:
                profiles={
                    "chin_strap":(.009,.181,-.189), "short_boxed_beard":(.032,.178,-.205),
                    "sheet_full_beard":(.067,.181,-.278), "rounded_beard":(.053,.176,-.235),
                    "friendly_trimmed_beard":(.027,.168,-.207), "rugged_medium_beard":(.053,.181,-.255),
                }
                bulk, width, bottom=profiles[kind]
                for side in (-1,1):
                    for i in range(7):
                        x=width*(1-i/7)
                        top=-.047-.104*math.sin(math.pi*i/14)
                        base=bottom+(.055 if kind=="chin_strap" else .037)*(1-i/7)**2
                        if kind=="rugged_medium_beard": base-=.012*(i%3==1)
                        m.ellipsoid(H,(side*x,(top+base)/2,.004+bulk*.18),(.018,(top-base)/2,bulk),7,10)
        if kind in ("sheet_soul_patch", "sheet_goatee", "extended_goatee", "van_dyke"):
            if kind=="sheet_soul_patch":
                m.ellipsoid(H,(0,-.153,.006),(.018,.020,.006),7,12)
            else:
                bottom={"sheet_goatee":-.208,"extended_goatee":-.245,"van_dyke":-.236}[kind]
                for side in (-1,1):
                    swept_lock(m,H,(side*.025,-.139,.003),(side*.046,-.176,.009),(side*(.013 if kind=="van_dyke" else .027),bottom,.012),.023)
                if kind=="extended_goatee":
                    for side in (-1,1):
                        swept_lock(m,H,(side*.071,-.091,.003),(side*.082,-.153,.006),(side*.034,-.214,.009),.013)
        return seat_on_face(m)
    if kind=="stubble":
        rng=random.Random(155)
        for side in (-1,1):
            for _ in range(154):
                x=rng.uniform(.021,.173)
                y=rng.uniform(-.174,-.061)
                if y>-.149 and x<.066 or x>head_radii(y)[0]*.90:
                    continue
                size=rng.uniform(.0014,.0026)
                m.ellipsoid(H,(side*x,y,.0007),(size,size*.82,.0014),4,7)
        return seat_on_face(m)
    if kind in ("short_beard","full_beard","jawline","boxed","pointed"):
        depth={"short_beard":.021,"full_beard":.042 if length=="short" else .067,"jawline":.012,"boxed":.035,"pointed":.046}[kind]
        bands=[]
        for j in range(9):
            t=j/8; row=[]
            for i in range(33):
                a=math.pi*i/32; angle=math.cos(a)
                x=angle*(.189 if kind=="boxed" else .174)*(1-(.44 if kind=="pointed" else .19)*t)
                upper=-.056-.099*math.sin(a) if kind!="jawline" else -.084-.071*math.sin(a)
                drop={"short_beard":.035,"full_beard":.078 if length=="short" else .135,"jawline":.022,"boxed":.046,"pointed":.105}[kind]
                y=upper-drop*t*(.44+.56*math.sin(a)**(2.0 if kind=="pointed" else .65))
                z=skin_front(x,max(-.187,y)) + depth*math.sin(math.pi*t)*math.sin(a)**.28
                if j==0 or j==8:
                    z-=.001
                row.append((x,y,z))
            bands.append(row)
        for row,nxt in zip(bands,bands[1:]):
            for i in range(32):
                a,b,c,d=row[i],row[i+1],nxt[i+1],nxt[i]
                n=unit(cross_product(subtract(b,a),subtract(c,a)))
                if n[2]<0:n=tuple(-v for v in n)
                material=A if (i in range(5,7) or i in range(24,26)) and kind!="jawline" else H
                m.tri(material,a,b,c,n);m.tri(material,a,c,d,n)
        return m
    if kind in ("goatee","anchor"):
        for side in (-1,1):
            swept_lock(m,H,(side*.029,-.142,.003),(side*.053,-.166,.006),(0,-.204,.009),.022 if kind=="goatee" else .019)
        m.ellipsoid(H,(0,-.150,.005),(.017,.014,.008),8,14)
    if kind=="soul_patch":
        swept_lock(m,H,(-.022,-.143,.004),(0,-.152,.010),(0,-.179,.010),.014)
        swept_lock(m,H,(.022,-.143,.004),(0,-.152,.010),(0,-.179,.010),.014)
    if kind in ("mutton_chops","forked"):
        for side in (-1,1):
            for i in range(4):
                if kind=="mutton_chops":
                    swept_lock(m,H if i!=2 else A,(side*(.171+i*.009),.016,-.002),(side*(.176-i*.005),-.099,.010),(side*(.103+i*.011),-.139,.008),.018)
                else:
                    swept_lock(m,H if i!=2 else A,(side*(.023+i*.014),-.150,.006),(side*(.040+i*.008),-.224,.103),(side*(.032+i*.009),-.271,.092),.016)
    if kind in ("handlebar","pencil","chevron","anchor","imperial"):
        radius={"handlebar":.008,"pencil":.0035,"chevron":.015,"anchor":.007,"imperial":.012}[kind]
        for side in (-1,1):
            points=[]
            for i in range(13):
                t=i/12
                y=-.077-.020*t
                if kind=="handlebar": y+=.045*t**5
                if kind=="imperial": y+=.072*t**4
                reach=.117 if kind in ("handlebar","imperial") else .071 if kind=="pencil" else .087
                points.append((side*(.007+reach*t),y,.001))
            m.tube(H,points,[radius*(.35+.65*math.sin(math.pi*(i+.6)/13.5)) for i in range(13)])
    return seat_on_face(m)


def textures():
    MATERIAL.mkdir(parents=True,exist_ok=True)
    for name,(rgb,metal,rough) in MATS.items():
        al=Image.new("RGB",(128,128),rgb); px=al.load()
        for y in range(128):
            for x in range(128):
                grain=((x*19+y*31+(x^y)*5)%17)-8; strength=.010 if "hair" in name or name=="brow" else .004
                px[x,y]=tuple(max(0,min(255,int(c*(1+grain*strength)))) for c in rgb)
        al.save(MATERIAL/f"{name}_albedo.png")
        normal=Image.new("RGB",(128,128),(128,128,255)); d=ImageDraw.Draw(normal)
        if name in ("hair","hair_highlight","brow"):
            for i in range(0,128,5): d.line((i,0,(i+23)%128,127),fill=(136,124,253),width=1)
        normal.save(MATERIAL/f"{name}_normal.png")
        Image.new("RGB",(128,128),(255,int(rough*255),int(metal*255))).save(MATERIAL/f"{name}_orm.png")


def write_gltf(key, title, mesh):
    MODEL.mkdir(parents=True,exist_ok=True); blob=bytearray(); views=[]; accessors=[]; primitives=[]; used=list(mesh.groups)
    def add(data,kind,stride,mins=None,maxs=None):
        while len(blob)%4: blob.append(0)
        off=len(blob); blob.extend(data); views.append({"buffer":0,"byteOffset":off,"byteLength":len(data)})
        a={"bufferView":len(views)-1,"componentType":5126,"count":len(data)//stride,"type":kind}
        if mins is not None:a.update(min=mins,max=maxs)
        accessors.append(a); return len(accessors)-1
    for mat,verts in mesh.groups.items():
        pos=b"".join(struct.pack("<3f",*v[0]) for v in verts); nor=b"".join(struct.pack("<3f",*v[1]) for v in verts); uv=b"".join(struct.pack("<2f",*v[2]) for v in verts); xyz=[v[0] for v in verts]
        pa=add(pos,"VEC3",12,[min(v[i] for v in xyz) for i in range(3)],[max(v[i] for v in xyz) for i in range(3)])
        primitives.append({"attributes":{"POSITION":pa,"NORMAL":add(nor,"VEC3",12),"TEXCOORD_0":add(uv,"VEC2",8)},"material":used.index(mat),"mode":4})
    images=[]; tex=[]; materials=[]
    def texture(uri): images.append({"uri":uri}); tex.append({"source":len(images)-1}); return len(tex)-1
    for mat in used:
        rgb,metal,rough=MATS[mat]; materials.append({"name":mat,"pbrMetallicRoughness":{"baseColorTexture":{"index":texture(f"../materials/{mat}_albedo.png")},"metallicRoughnessTexture":{"index":texture(f"../materials/{mat}_orm.png")},"metallicFactor":metal,"roughnessFactor":rough},"normalTexture":{"index":texture(f"../materials/{mat}_normal.png"),"scale":.45}})
    if key.startswith("hair_"):
        for material in materials:
            material.pop("normalTexture",None)
    doc={"asset":{"version":"2.0","generator":"LabVolt original faces/hair authoring tool"},"scene":0,"scenes":[{"nodes":[0]}],"nodes":[{"name":title,"mesh":0}],"meshes":[{"name":title,"primitives":primitives}],"materials":materials,"images":images,"textures":tex,"samplers":[{}],"buffers":[{"uri":f"{key}.bin","byteLength":len(blob)}],"bufferViews":views,"accessors":accessors}
    (MODEL/f"{key}.bin").write_bytes(blob); (MODEL/f"{key}.gltf").write_text(json.dumps(doc,indent=2),encoding="utf-8")


def hair_icon(key, mesh):
    im=Image.new("RGBA",(384,384))
    draw=ImageDraw.Draw(im)
    draw.ellipse((110,99,274,322),fill="#e7bea3")
    draw.ellipse((155,205,166,224),fill="#322b36")
    draw.ellipse((218,205,229,224),fill="#322b36")
    draw.arc((170,230,215,269),12,168,fill="#825260",width=4)
    triangles=[]
    angle=.58
    co,si=math.cos(angle),math.sin(angle)
    for mat,verts in mesh.groups.items():
        base=MATS[mat][0]
        for i in range(0,len(verts),3):
            points=[]
            depth=light=0
            for (x,y,z),n,_ in verts[i:i+3]:
                points.append((192+370*(x*co+z*si), 205-435*y))
                depth += z*co-x*si
                light += max(0,sum(a*b for a,b in zip(n,(-.25,.70,.65))))
            # The head covers the back of the scalp. Keep its protruding silhouette.
            if depth<-.14 and all(112<x<272 and 114<y<319 for x,y in points):
                continue
            shade=.73+.19*light
            ink=tuple(min(255,round(c*shade+25)) for c in base)
            triangles.append((depth,points,ink))
    for _,points,ink in sorted(triangles,key=lambda tri:tri[0]):
        draw.polygon(points,fill=ink)
    im.save(THUMB/f"hair_{key}.png")


def thumb(key,title,category,accent):
    THUMB.mkdir(parents=True,exist_ok=True); im=Image.new("RGBA",(384,384),(27,34,47,255)); d=ImageDraw.Draw(im)
    d.ellipse((82,62,302,302),fill=(222,176,140,255),outline=(244,239,228,255),width=4)
    if category=="faces":
        d.ellipse((132,150,173,196),fill=(247,244,232),outline=(30,33,40),width=3); d.ellipse((211,150,252,196),fill=(247,244,232),outline=(30,33,40),width=3)
        d.ellipse((148,163,162,184),fill=accent); d.ellipse((227,163,241,184),fill=accent); d.arc((145,195,239,260),10,170,fill=(118,59,68),width=7)
    elif category=="hair":
        d.pieslice((70,40,314,276),180,360,fill=accent); d.ellipse((90,40,294,170),fill=accent)
    else:
        if key.startswith("facial_") and key[7:] in REFERENCE_FACIAL_KEYS:
            style=key[7:]
            if style in ("thin_moustache","thick_moustache","curled_moustache","pencil_moustache"):
                width={"thin_moustache":5,"thick_moustache":15,"curled_moustache":11,"pencil_moustache":3}[style]
                d.arc((135,197,249,246),5,175,fill=accent,width=width)
                if style=="curled_moustache":
                    d.arc((107,174,153,226),180,345,fill=accent,width=10); d.arc((231,174,277,226),195,360,fill=accent,width=10)
            elif style=="sheet_stubble":
                rng=random.Random(615)
                for _ in range(160):
                    x=rng.randrange(107,278); y=rng.randrange(214,294)
                    if ((x-192)/90)**2+((y-242)/83)**2<1:
                        d.ellipse((x,y,x+2,y+3),fill=accent)
            elif style=="sheet_soul_patch": d.rounded_rectangle((177,243,207,266),7,fill=accent)
            else:
                low={"chin_strap":288,"sheet_goatee":296,"extended_goatee":315,"short_boxed_beard":292,"sheet_full_beard":325,"rounded_beard":310,"van_dyke":311,"friendly_trimmed_beard":292,"rugged_medium_beard":321}[style]
                d.pieslice((105,178,279,low),0,180,fill=accent)
                if style not in ("chin_strap","sheet_goatee","extended_goatee"):
                    d.rounded_rectangle((138,210,246,249),15,fill=accent)
                if style in ("sheet_goatee","extended_goatee","van_dyke"):
                    d.polygon([(167,239),(217,239),(192,low)],fill=accent)
                if style=="chin_strap": d.ellipse((118,193,266,275),fill=(222,176,140,255))
                if style=="van_dyke": d.ellipse((168,218,216,251),fill=(222,176,140,255))
        else:
            d.pieslice((105,178,279,326),0,180,fill=accent); d.rounded_rectangle((125,205,259,255),18,fill=accent)
    d.rounded_rectangle((18,315,366,369),10,fill=(12,16,23,220)); d.text((30,329),title,fill=(245,247,250,255),stroke_width=1,stroke_fill=(0,0,0,255)); im.save(THUMB/f"{key}.png")


def write_catalog():
    items=[]
    scalar=lambda default, low, high: {"type":"float","default":default,"min":low,"max":high}
    face_params={"eye_color":{"type":"color","default":"397A83"},"eyebrow_color":{"type":"color","default":"352B31"},"lip_color":{"type":"color","default":"763B44"},
        "eye_size":scalar(1,.85,1.12),"brow_height":scalar(0,-.013,.013),"mouth_width":scalar(1,.8,1.14)}
    hair_params={"color":{"type":"color","default":"352B31"},"highlight":{"type":"color","default":"68504A"},"volume":{"type":"float","default":1.0,"min":.9,"max":1.12},"shine":{"type":"float","default":.35,"min":0.0,"max":1.0},
        "crown_lift":scalar(1,.80,1.25),"side_volume":scalar(1,.95,1.10)}
    facial_params={"color":{"type":"color","default":"352B31"},"density":{"type":"float","default":1.0,"min":.6,"max":1.0},"shine":{"type":"float","default":.2,"min":0.0,"max":1.0},
        "width":scalar(1,.84,1.10),"depth":scalar(1,.8,1.25),"highlight":{"type":"color","default":"4d3b38"}}
    def base(item_id,name,category,slot,scene,thumbnail,starter,price,rarity,params,tags):
        return {"id":item_id,"name":name,"category":category,"slot":slot,"scene":f"res://assets/cosmetics/faces_hair/models/{scene}.gltf","thumbnail":f"res://assets/cosmetics/faces_hair/thumbnails/{thumbnail}.png","price":price,"starter":starter,"rarity":rarity,"rig":"labvolt_toon_v1","tags":tags,"conflicts":[],"parameters":params,"materials":{"color_regions":["hair","hair_highlight","brow","iris","lip","skin_detail"]}}
    for key,name,starter,price,rarity in FACE_META:
        params=dict(face_params)
        if key=="imp_grin":
            params["eye_color"]={"type":"color","default":"a6bc43"}
        items.append(base(f"faces.{key}",name,"faces","face",f"face_{key}",f"face_{key}",starter,price,rarity,params,["face_preset"]))
    for key,name,variants,starter,price,rarity in HAIR_META:
        params=dict(hair_params); default=variants[0]
        if len(variants)>1: params["length"]={"type":"enum","default":default,"values":variants}
        tags=["head_hair", "long_hair" if "long" in variants else "short_hair"]
        if key in ("curly","bun"): tags.append("hair_volume_high")
        item=base(f"hair.{key}",name,"hair","hair",f"hair_{key}_{default}",f"hair_{key}",starter,price,rarity,params,tags)
        if len(variants)>1:item["variants"]={v:f"res://assets/cosmetics/faces_hair/models/hair_{key}_{v}.gltf" for v in variants}
        items.append(item)
    for key,name,variants,starter,price,rarity in FACIAL_META:
        params=dict(facial_params); default=variants[0]
        if len(variants)>1:params["length"]={"type":"enum","default":default,"values":variants}
        item=base(f"facial_hair.{key}",name,"facial_hair","facial_hair",f"facial_{key}_{default}",f"facial_{key}",starter,price,rarity,params,["facial_hair"])
        if len(variants)>1:item["variants"]={v:f"res://assets/cosmetics/faces_hair/models/facial_{key}_{v}.gltf" for v in variants}
        items.append(item)
    path=BASE/"catalog.json"
    if path.is_file():
        saved=json.loads(path.read_text(encoding="utf-8"))
        existing={item["id"]:item for item in saved["items"]}
        items=[existing.get(item["id"],item) for item in items]
        for item in items:
            if item["id"]=="facial_hair.toothbrush":
                item.update(starter=False,price=1250,rarity="legendary")
        items.extend(item for item in saved["items"] if item["id"] not in {entry["id"] for entry in items})
    path.write_text(json.dumps({"schema_version":1,"items":items},indent=2),encoding="utf-8")


def main():
    textures(); entries=[]
    for key,title,*_ in FACE_META:
        write_face(key,title); entries.append(("faces",key))
    for key,title,variants,*_ in HAIR_META:
        for variant in variants: write_gltf(f"hair_{key}_{variant}",f"{title} {variant}",hair(key,variant))
        hair_icon(key,hair(key,variants[0])); entries.append(("hair",key))
    for key,title,variants,*_ in FACIAL_META:
        if key=="clean":
            empty=Mesh(); empty.ellipsoid("skin_detail",(0,0,0),(.001,.001,.001),4,6); write_gltf("facial_clean_default",title,empty)
        else:
            for variant in variants: write_gltf(f"facial_{key}_{variant}",f"{title} {variant}",facial(key,variant))
        thumb(f"facial_{key}",title,"facial_hair",(53,43,49,255)); entries.append(("facial_hair",key))
    write_catalog()
    print(f"Built {len(entries)} collectible definitions and {len(list(MODEL.glob('*.gltf')))} baked models")


if __name__ == "__main__":
    import sys
    if "--shop-faces-only" in sys.argv:
        for key,title,*_ in FACE_META:
            if key in ("storm_chaser","starstruck"):write_face(key,title)
        write_catalog()
    elif "--reference-facial-only" in sys.argv:
        for key,title,variants,*_ in FACIAL_META:
            if key not in REFERENCE_FACIAL_KEYS:continue
            for variant in variants: write_gltf(f"facial_{key}_{variant}",title,facial(key,variant))
            thumb(f"facial_{key}",title,"facial_hair",(53,43,49,255))
        write_catalog()
    else: main()
