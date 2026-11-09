"""Generate low-poly baked OBJ campus props without external dependencies.

Meshes deliberately use tapered, cylindrical and sloped silhouettes instead of
building every object from axis-aligned boxes. Run from the repository root.
"""
from __future__ import annotations
import math
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
OUT = ROOT / "assets" / "campus" / "decor" / "meshes"


class Obj:
    def __init__(self, name: str):
        self.name, self.v, self.f = name, [], []

    def vertex(self, p):
        self.v.append(tuple(round(float(x), 5) for x in p)); return len(self.v)

    def quad(self, a, b, c, d): self.f.extend([(a,b,c), (a,c,d)])

    def box(self, center, size, slope=0.0):
        cx,cy,cz=center; sx,sy,sz=(x/2 for x in size); y0,y1=cy-sy,cy+sy
        lo=[self.vertex((cx+x*sx,y0,cz+z*sz)) for x,z in [(-1,-1),(1,-1),(1,1),(-1,1)]]
        hi=[self.vertex((cx+x*sx+slope*z,y1,cz+z*sz)) for x,z in [(-1,-1),(1,-1),(1,1),(-1,1)]]
        self.quad(*lo[::-1]); self.quad(*hi)
        for i in range(4): self.quad(lo[i],lo[(i+1)%4],hi[(i+1)%4],hi[i])

    def cylinder(self, center, radius, height, sides=10, top_scale=1.0):
        cx,cy,cz=center; bottom=[]; top=[]
        for i in range(sides):
            a=math.tau*i/sides; bottom.append(self.vertex((cx+math.cos(a)*radius,cy-height/2,cz+math.sin(a)*radius)))
            top.append(self.vertex((cx+math.cos(a)*radius*top_scale,cy+height/2,cz+math.sin(a)*radius*top_scale)))
        cb=self.vertex((cx,cy-height/2,cz)); ct=self.vertex((cx,cy+height/2,cz))
        for i in range(sides):
            j=(i+1)%sides; self.f += [(cb,bottom[j],bottom[i]),(ct,top[i],top[j])]; self.quad(bottom[i],bottom[j],top[j],top[i])

    def write(self):
        OUT.mkdir(parents=True, exist_ok=True)
        lines=[f"# generated campus decor mesh: {self.name}",f"o {self.name}"]
        lines += ["v %.5f %.5f %.5f"%p for p in self.v]
        lines += ["f %d %d %d"%p for p in self.f]
        (OUT/f"{self.name}.obj").write_text("\n".join(lines)+"\n", encoding="ascii")


def chair():
    o=Obj("campus_chair"); o.box((0,.48,0),(.55,.12,.55),.05); o.box((0,.9,.25),(.55,.72,.09),-.10)
    for x in (-.22,.22):
        for z in (-.20,.20): o.cylinder((x,.23,z),.035,.46,8,.82)
    o.write()

def planter():
    o=Obj("leaf_planter"); o.cylinder((0,.25,0),.26,.5,12,.78); o.cylinder((0,.55,0),.055,.65,8,.7)
    for i in range(7):
        a=math.tau*i/7; x,z=math.cos(a)*.17,math.sin(a)*.17
        o.box((x,.83+(i%2)*.10,z),(.18,.55,.055),math.cos(a)*.18)
    o.write()

def pendant():
    o=Obj("pendant_fixture"); o.cylinder((0,.30,0),.035,.6,8); o.cylinder((0,.01,0),.34,.18,16,.42); o.cylinder((0,-.10,0),.22,.035,16); o.write()

def stool():
    o=Obj("lab_stool"); o.cylinder((0,.62,0),.30,.11,14,.9); o.cylinder((0,.31,0),.055,.62,10)
    for a in (0,math.tau/3,2*math.tau/3):
        o.box((math.cos(a)*.18,.17,math.sin(a)*.18),(.055,.34,.055),math.cos(a)*.12)
    o.write()

def trophy():
    o=Obj("trophy_case"); o.box((0,.06,0),(.7,.12,.42)); o.cylinder((0,.27,0),.25,.36,14,.72); o.cylinder((0,.49,0),.10,.12,12,.55)
    for s in (-1,1): o.cylinder((s*.28,.31,0),.055,.42,8,.75)
    o.write()

def bin_mesh():
    o=Obj("sort_bin"); o.cylinder((0,.42,0),.28,.78,12,.92); o.cylinder((0,.83,0),.30,.08,12,.78); o.write()

def acoustic():
    o=Obj("acoustic_fin"); o.box((0,.75,0),(.12,1.5,.62),.18); o.write()

def rack():
    o=Obj("equipment_rack");
    for x in (-.52,.52): o.cylinder((x,.85,0),.045,1.7,8)
    for y in (.2,.65,1.1,1.55): o.box((0,y,0),(1.15,.07,.48),.03)
    o.box((0,1.72,0),(1.25,.12,.56)); o.write()

def cafe_table():
    o=Obj("cafe_table"); o.cylinder((0,.72,0),.62,.10,20,.96); o.cylinder((0,.37,0),.10,.70,12); o.cylinder((0,.05,0),.38,.08,16,.8); o.write()

def locker():
    o=Obj("arched_locker"); o.box((0,.82,0),(.72,1.64,.44),.02); o.cylinder((0,1.64,0),.36,.44,14,.82); o.write()

def component_counter():
    o=Obj("component_counter")
    # Faceted service counter with recessed customer side and rounded end caps.
    o.box((0,.46,0),(2.8,.92,.72),.03); o.box((0,.96,-.04),(3.05,.14,.92),.02)
    for x in (-1.18,0,1.18): o.box((x,.55,-.38),(.72,.46,.08))
    for x in (-1.45,1.45): o.cylinder((x,.48,0),.10,.92,10)
    o.write()

def parts_display():
    o=Obj("parts_display")
    # Sloped pegboard, four spool/canister silhouettes and angled parts trays.
    o.box((0,1.1,.18),(2.5,1.5,.10),.10)
    for x in (-.85,-.28,.28,.85): o.cylinder((x,1.28,.08),.16,.16,12)
    for x in (-.75,0,.75): o.box((x,.55,-.06),(.58,.22,.44),.12)
    for x in (-1.15,1.15): o.cylinder((x,.85,.05),.035,1.65,8)
    o.write()

def trade_counter():
    o=Obj("trade_counter")
    # Open negotiation table: oval top, central pedestal and two document trays.
    o.cylinder((0,.78,0),1.18,.14,24,.92); o.cylinder((0,.4,0),.18,.76,12,.8); o.cylinder((0,.06,0),.58,.10,18,.75)
    for x in (-.58,.58): o.box((x,.91,0),(.68,.06,.42),.08 if x>0 else -.08)
    o.write()

def main():
    for fn in (chair,planter,pendant,stool,trophy,bin_mesh,acoustic,rack,cafe_table,locker,component_counter,parts_display,trade_counter): fn()
    print(f"generated 13 OBJ meshes in {OUT}")

if __name__ == "__main__": main()
