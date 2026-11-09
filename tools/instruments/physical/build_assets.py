"""Original authored instrument meshes. Offline only; no Blender/Godot required.

Metres, +Y up, front +Z, casing front at Z=0. No manufacturer geometry.
OBJ triangles have explicit normals and UVs. Godot reverses OBJ face convention
at import; source uses the standard outward counter-clockwise OBJ convention.
"""
from pathlib import Path
import json, math, hashlib

ROOT = Path(__file__).resolve().parents[3]
OUT = ROOT / 'assets/instruments/physical'
PALETTE = {'shell':'bfc8ca','face':'e0e4de','rubber':'29383d','bezel':'35464c',
           'screen':'102828','metal':'9ba7aa','dark':'102027','accent':'3e8c88'}

class Mesh:
    def __init__(self): self.v=[]; self.uv=[]; self.n=[]; self.faces=[]
    def quad(self, pts, material):
        a,b,c=pts[:3]; u=[b[i]-a[i] for i in range(3)]; v=[c[i]-a[i] for i in range(3)]
        n=[u[1]*v[2]-u[2]*v[1],u[2]*v[0]-u[0]*v[2],u[0]*v[1]-u[1]*v[0]]
        length=math.sqrt(sum(x*x for x in n)); assert length>1e-10
        n=[x/length for x in n]; ids=[]
        for point,uv in zip(pts,[(0,0),(1,0),(1,1),(0,1)]):
            self.v.append(point);self.uv.append(uv);self.n.append(n);ids.append(len(self.v))
        self.faces.extend([(material,(ids[0],ids[1],ids[2])),(material,(ids[0],ids[2],ids[3]))])
    def rounded(self,x,y,z,w,h,d,r,material,steps=4):
        # CCW rounded rectangle, viewed from +Z.
        p=[]
        for cx,cy,start in [(w/2-r,h/2-r,0),(-w/2+r,h/2-r,90),(-w/2+r,-h/2+r,180),(w/2-r,-h/2+r,270)]:
            for j in range(steps+1):
                t=math.radians(start+j*90/steps);p.append((x+cx+r*math.cos(t),y+cy+r*math.sin(t)))
        # Fan with separate explicit normals and UVs; no degenerate corner triangles.
        for i,a in enumerate(p):
            b=p[(i+1)%len(p)]
            for zz,rev in [(z,False),(z-d,True)]:
                tri=[(x,y,zz),(*a,zz),(*b,zz)]
                if rev:tri.reverse()
                ids=[]
                for point in tri:
                    self.v.append(point);self.uv.append(((point[0]-x)/w+.5,(point[1]-y)/h+.5));self.n.append((0,0,-1 if rev else 1));ids.append(len(self.v))
                self.faces.append((material,ids))
            self.quad([(*a,z),(*a,z-d),(*b,z-d),(*b,z)],material)
    def cylinder(self,x,y,z,r,d,material,segments=24):
        # +Z-facing, tactile scalloped edge for knob grip when segments=48.
        p=[]
        for j in range(segments):
            t=math.tau*j/segments;rr=r*(.95 if segments==48 and j%2 else 1)
            p.append((x+rr*math.cos(t),y+rr*math.sin(t)))
        for i,a in enumerate(p):
            b=p[(i+1)%len(p)]
            self.quad([(*a,z),(*a,z-d),(*b,z-d),(*b,z)],material)
            for zz,reverse in [(z,False),(z-d,True)]:
                tri=[(x,y,zz),(*a,zz),(*b,zz)]
                if reverse:tri.reverse()
                ids=[]
                for point in tri:
                    self.v.append(point);self.uv.append(((point[0]-x)/r*.5+.5,(point[1]-y)/r*.5+.5));self.n.append((0,0,-1 if reverse else 1));ids.append(len(self.v))
                self.faces.append((material,ids))
    def write(self,name):
        lines=['# Original LabVolt simulator asset; authored 2026-11-06','mtllib physical.mtl']
        lines += ['v '+' '.join(f'{x:.7f}' for x in v) for v in self.v]
        lines += ['vt '+' '.join(f'{x:.7f}' for x in v) for v in self.uv]
        lines += ['vn '+' '.join(f'{x:.7f}' for x in v) for v in self.n]
        for material in PALETTE:
            if not any(mat==material for mat,_ in self.faces):continue
            lines.append('usemtl '+material)
            for mat,face in self.faces:
                if mat==material:lines.append('f '+' '.join(f'{i}/{i}/{i}' for i in face))
        (OUT/(name+'.obj')).write_text('\n'.join(lines)+'\n',encoding='utf-8')
        return {'vertices':len(self.v),'triangles':len(self.faces),'surfaces':len({m for m,_ in self.faces}),
                'bounds_min':[min(p[i] for p in self.v) for i in range(3)],'bounds_max':[max(p[i] for p in self.v) for i in range(3)]}

def housing(name,w,h,d,screens):
    m=Mesh()
    m.rounded(0,0,-.018,w,h,d-.018,.04,'shell')
    m.rounded(0,0,-.005,w+.006,h+.006,.035,.035,'rubber')
    m.rounded(0,0,0,w-.018,h-.018,.012,.028,'face')
    for x,y,sw,sh in screens:
        m.rounded(x,y,.004,sw+.025,sh+.025,.010,.012,'bezel')
        m.rounded(x,y,.005,sw,sh,.003,.008,'screen')
    # Side bumpers are shaped extrusions; feet do not penetrate tabletop.
    for x in [-w/2+.027,w/2-.027]:
        m.rounded(x,0,.004,.035,h-.02,.07,.015,'rubber')
    for x in [-w*.36,w*.36]:m.rounded(x,-h/2-.014,-d*.36,.09,.028,d*.35,.009,'rubber')
    # Rear ventilation louvres stay on the housing, behind the control face.
    for i in range(12):
        x=-w*.30+i*w*.60/11
        m.quad([(x-.005,h/2,-d*.7),(x-.005,h/2,-d*.28),(x+.005,h/2,-d*.28),(x+.005,h/2,-d*.7)],'dark')
    for x in [-w/2+.065,w/2-.065]:
        for y in [-h/2+.04,h/2-.04]:
            m.cylinder(x,y,.006,.008,.005,'metal',12)
            m.rounded(x,y,.0065,.010,.0018,.001,.0007,'dark',2)
    return m

def main():
    OUT.mkdir(parents=True,exist_ok=True)
    mtl=[]
    for name,h in PALETTE.items():
        c=[int(h[i:i+2],16)/255 for i in (0,2,4)]
        mtl += [f'newmtl {name}','Kd '+' '.join(f'{v:.5f}' for v in c),'Ks 0.08 0.08 0.08','Ns 24','']
    (OUT/'physical.mtl').write_text('\n'.join(mtl),encoding='utf-8')
    # These fit the audited worktop, not unverified manufacturer dimensions.
    specs={'supply':(1.46,.70,.53,[(-.45,.16,.36,.18),(0,.16,.36,.18),(.45,.16,.36,.18)]),
           'meter':(1.05,.34,.40,[(-.19,.025,.56,.145)]),
           'generator':(1.05,.34,.44,[(-.18,.045,.52,.12)]),
           'scope':(1.45,.75,.55,[(-.20,.08,.84,.44)]),
           'patchdeck':(4.30,.15,.32,[])}
    stats={name:housing(name,*spec).write(name) for name,spec in specs.items()}
    m=Mesh();m.cylinder(0,0,.028,.032,.031,'rubber',48);m.cylinder(0,0,.03,.022,.003,'metal',24)
    m.rounded(0,.012,.032,.003,.016,.001,.001,'dark',2);stats['knob']=m.write('knob')
    m=Mesh();m.rounded(0,0,.012,.065,.028,.016,.008,'rubber');stats['button']=m.write('button')
    m=Mesh();m.cylinder(0,0,.008,.029,.01,'metal',12);m.cylinder(0,0,.020,.023,.022,'rubber',12);m.cylinder(0,0,.023,.012,.003,'dark',12);stats['socket']=m.write('socket')
    (OUT/'mesh_manifest.json').write_text(json.dumps({'coordinate_system':'+Y up, +Z front, casing face Z=0; metres','reference_status':'Pending actual reference pixels. Generic original housings; not a manufacturer reproduction.','license':'Original project-authored geometry; no external assets','meshes':stats},indent=2)+'\n')

if __name__=='__main__':main()
