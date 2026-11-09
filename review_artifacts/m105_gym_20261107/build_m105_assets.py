"""Original service-room geometry. Standard library only; never starts Godot.

OBJ uses right-handed CCW faces (Godot's OBJ importer converts winding).
Every triangle has explicit unit normals and nondegenerate metre-space UVs.
"""
from pathlib import Path
from collections import defaultdict
import math, json, hashlib

ROOT = Path(__file__).resolve().parents[2]
OUT = Path(__file__).resolve().parent/'generated'
PALETTE = {
 'oak': ['b99160', .78, 0], 'oak_light':['cda977',.8,0],
 'ink':['253a44',.7,.12], 'steel':['9baaad',.32,.7],
 'porcelain':['ecede5',.24,0], 'teal':['317a7d',.76,0],
 'rubber':['30383b',.95,0], 'line':['ece6d3',.8,0],
 'mirror':['b3d4d5',.16,.8], 'leaf':['4e7161',.9,0],
 'terracotta':['b16d51',.82,0], 'paper':['e1d5b8',.9,0]}

def add(a,b): return tuple(x+y for x,y in zip(a,b))
def sub(a,b): return tuple(x-y for x,y in zip(a,b))
def cross(a,b): return (a[1]*b[2]-a[2]*b[1],a[2]*b[0]-a[0]*b[2],a[0]*b[1]-a[1]*b[0])
def norm(v):
    d=math.sqrt(sum(x*x for x in v)); return tuple(x/d for x in v)

class Author:
    def __init__(self): self.parts=defaultdict(list); self.objects=[]; self.current=[]
    def tri(self,m,a,b,c):
        n=norm(cross(sub(b,a),sub(c,a)))
        # Project along the dominant normal; robust even for upright triangles.
        axis=max(range(3),key=lambda i:abs(n[i])); axes=[i for i in range(3) if i!=axis]
        self.parts[m].append([(p,n,(p[axes[0]],p[axes[1]])) for p in (a,b,c)])
        self.current.extend((a,b,c))
    def quad(self,m,a,b,c,d): self.tri(m,a,b,c);self.tri(m,a,c,d)
    def box(self,m,p,s):
        x,y,z=p; a,b,c=[v/2 for v in s]
        v=[(x+i*a,y+j*b,z+k*c) for i,j,k in [(-1,-1,-1),(1,-1,-1),(1,1,-1),(-1,1,-1),(-1,-1,1),(1,-1,1),(1,1,1),(-1,1,1)]]
        for q in [(0,3,2,1),(4,5,6,7),(0,4,7,3),(1,2,6,5),(0,1,5,4),(3,7,6,2)]:self.quad(m,*(v[i] for i in q))
    def tube(self,m,a,b,r,segments=12):
        w=norm(sub(b,a)); u=norm(cross(w,(0,1,0) if abs(w[1])<.9 else (1,0,0))); v=cross(w,u)
        ring=lambda p,t:add(p,tuple(r*(math.cos(t)*u[i]+math.sin(t)*v[i]) for i in range(3)))
        for i in range(segments):
            t=i*math.tau/segments; t2=(i+1)*math.tau/segments
            p,q,rr,s=ring(a,t),ring(a,t2),ring(b,t2),ring(b,t)
            self.quad(m,p,q,rr,s);self.tri(m,a,q,p);self.tri(m,b,s,rr)
    def lathe(self,m,p,profile,segments=24,aspect=(1,1)):
        # profile runs from base to top; may turn inward to form actual bowls.
        for (r,y),(r2,y2) in zip(profile,profile[1:]):
            for j in range(segments):
                t=j*math.tau/segments; q=(j+1)*math.tau/segments
                point=lambda rad,h,a:add(p,(rad*math.cos(a)*aspect[0],h,rad*math.sin(a)*aspect[1]))
                self.quad(m,point(r,y,t),point(r2,y2,t),point(r2,y2,q),point(r,y,q))
    def ring(self,m,p,rx,rz,width=.035):
        x,y,z=p
        for j in range(80):
            t=j*math.tau/80;q=(j+1)*math.tau/80
            self.quad(m,(x+rx*math.cos(t),y,z+rz*math.sin(t)),(x+rx*math.cos(q),y,z+rz*math.sin(q)),(x+(rx-width)*math.cos(q),y,z+(rz-width)*math.sin(q)),(x+(rx-width)*math.cos(t),y,z+(rz-width)*math.sin(t)))
    def ball(self, material, center, radii):
        segments, rings = 32, 16
        def point(i, j):
            pitch = -math.pi / 2 + math.pi * i / rings
            yaw = math.tau * j / segments
            direction = (math.cos(pitch)*math.cos(yaw), math.sin(pitch), math.cos(pitch)*math.sin(yaw))
            position = add(center, tuple(direction[k]*radii[k] for k in range(3)))
            normal = norm(tuple(direction[k]/radii[k] for k in range(3)))
            return (position, normal, (j/segments, i/rings))
        for i in range(rings):
            for j in range(segments):
                a,b,c,d = point(i,j),point(i+1,j),point(i+1,j+1),point(i,j+1)
                if i < rings-1:
                    self.parts[material].append([a,b,c])
                    self.current.extend((a[0],b[0],c[0]))
                if i > 0:
                    self.parts[material].append([a,c,d])
                    self.current.extend((a[0],c[0],d[0]))
    def object(self,name,fn,role='furniture'):
        self.current=[];fn()
        if self.current:self.objects.append({'name':name,'role':role,'min':[min(v[i] for v in self.current) for i in range(3)],'max':[max(v[i] for v in self.current) for i in range(3)]})

def bench(a,x,z):
    for zz in [-.18,0,.18]:a.box('oak',(x,.47,z+zz),(2.2,.075,.145))
    for xx in [-.8,.8]:
        a.tube('ink',(x+xx,.08,z-.21),(x+xx,.44,z-.21),.04)
        a.tube('ink',(x+xx,.08,z+.21),(x+xx,.44,z+.21),.04)
        a.tube('ink',(x+xx,.12,z-.25),(x+xx,.12,z+.25),.045)
    a.box('oak',(x,.89,z+.25),(2.2,.3,.06))

def plant(a,x,z):
    a.lathe('terracotta',(x,0,z),[(.2,.03),(.29,.08),(.35,.52),(.36,.56),(.3,.56),(.27,.48)])
    for i in range(9):
        t=i*2.4;end=(x+.36*math.cos(t),.9+(i%3)*.18,z+.36*math.sin(t))
        a.tube('leaf',(x,.5,z),end,.014,6)
        d=(.17*math.sin(t),.05,-.17*math.cos(t));tip=add(end,(.18*math.cos(t),.24,.18*math.sin(t)))
        a.quad('leaf',add(end,d),tip,sub(end,d),sub(end,(.12*math.cos(t),.14,.12*math.sin(t))))
        # Physical leaves are two-sided geometry, no global double-sided material.
        a.quad('leaf',sub(end,d),tip,add(end,d),sub(end,(.12*math.cos(t),.14,.12*math.sin(t))))

def gym():
    a=Author()
    # Metre-sized plank courses: baked and grouped, rather than hundreds of nodes.
    for row in range(23):
        z=-5.7+row*.5
        a.object('maple_course_%02d'%row,lambda z=z,row=row:a.box('oak_light' if row%3 else 'oak',(0,.009,z),(19.65,.012,.494)),'surface')
    def markings():
        for z in [-4.7,4.7]:a.box('line',(0,.018,z),(16,.004,.045))
        for x in [-8,8]:a.box('line',(x,.018,0),(.045,.004,9.44))
        a.box('line',(0,.019,0),(.04,.004,9.4));a.ring('line',(0,.022,0),1.25,1.25)
        for x in [-6.7,6.7]:a.ring('line',(x,.021,0),.8,1.4)
    a.object('training_court_linework',markings,'surface')
    for z in [-4.9,4.9]:
        for x in [-6,-3,0,3,6]:
            a.object('perimeter_acoustic_%s_%s'%(x,z),lambda x=x,z=z:a.box('teal',(x,2.6,z*1.19),(2.2,.95,.09)),'wall')
    # West-wall locker run, facing east; seams, inset vents, handles, feet, folded caps.
    for z in [-4,-3,-2,2,3,4]:
        def locker(z=z):
            a.box('ink',(-9.35,1.02,z),(.7,1.96,.88))
            a.box('teal',(-8.987,1.06,z),(.035,1.8,.79))
            for dy in [1.54,1.63,1.72]:a.box('ink',(-8.963,dy,z),(.012,.025,.43))
            a.tube('steel',(-8.94,.89,z+.25),(-8.94,1.1,z+.25),.018,8)
            a.box('paper',(-8.96,1.36,z),(.012,.09,.16))
            for zz in [-.29,.29]:a.tube('steel',(-9.35,.02,z+zz),(-9.35,.08,z+zz),.04,8)
        a.object('ventilated_locker_%s'%z,locker)
    for x in [-5.6,4.8]:a.object('slatted_team_bench_%s'%x,lambda x=x:bench(a,x,5.1))
    # Animated barbells/dumbbell are assembled once by GymEquipmentMotion.
    def rack():
        for x in [6.3,8.3]:
            a.tube('ink',(x,.07,4.45),(x,1.65,4.45),.035)
            a.tube('ink',(x,.07,5.1),(x,1.65,5.1),.035)
        for y in [.2,.85,1.5]:
            for z in [4.45,5.1]:a.tube('steel',(6.3,y,z),(8.3,y,z),.025)
        for x in [6.65,7.3,7.95]:
            a.ball('terracotta',(x,.91,4.78),(.25,.27,.25))
    a.object('open_ball_storage',rack)
    # College wall treatment: no new room shell, doors or collision.
    for z in [-5.84,5.84]:
        a.object('blue_gray_dado_%s'%z,lambda z=z:a.box('teal',(0,0.71,z),(19.65,1.42,.035)),'wall')
        a.object('wall_base_%s'%z,lambda z=z:a.box('ink',(0,.12,z-(.025 if z>0 else -.025)),(19.65,.22,.045)),'wall')
        a.object('upper_wall_%s'%z,lambda z=z:a.box('porcelain',(0,2.55,z),(19.65,2.05,.025)),'wall')
    a.object('west_dado',lambda:a.box('teal',(-9.82,.7,0),(.03,1.4,11.6)),'wall')
    # Door wall trim stays outside the M105 doorway at x=10, z=0.
    for z in [-3.7,3.7]:a.object('east_dado_%s'%z,lambda z=z:a.box('teal',(9.82,.7,z),(.03,1.4,3.8)),'wall')
    for z in [-4,0,4]:
        for x in [-6,0,6]:
            def ceiling(x=x,z=z):
                a.box('paper',(x,3.98,z),(5.7,.03,3.7))
                a.box('ink',(x,3.955,z),(1.8,.025,.42))
                a.box('porcelain',(x,3.94,z),(1.68,.016,.32))
            a.object('ceiling_bay_%s_%s'%(x,z),ceiling,'ceiling')
    for x in [-6.3,6.3]:
        def poster(x=x):
            a.box('ink',(x,2.31,-5.79),(1.2,1.35,.045))
            a.box('paper',(x,2.31,-5.755),(1.08,1.23,.012))
            for j in range(4):a.box('teal',(x,2.7-j*.2,-5.745),(.75-j*.1,.04,.005))
        a.object('framed_training_poster_%s'%x,poster,'wall')
    # Low impact stretching edge; graphics sit on the existing floor.
    for x in [-6.4,-3.7,-1]:
        a.object('rolled_stretch_mat_%s'%x,lambda x=x:(a.box('rubber',(x,.025,-4.37),(1.35,.035,1.92)),a.tube('teal',(x-.55,.085,-5.3),(x+.55,.085,-5.3),.05,12)),'surface')
    for x in [1,2.2,3.4]:
        def medicine(x=x):
            a.ball('rubber',(x,.36,5.15),(.37,.34,.37))
            a.ring('teal',(x,.68,5.15),.116,.116,.02)
        a.object('medicine_ball_%s'%x,medicine)
    return a

def washroom():
    a=Author()
    def floor():
        a.box('porcelain',(0,.008,0),(19.65,.012,11.65))
        for x in range(-9,10):a.box('ink',(x,.016,0),(.012,.002,11.6))
        for z in range(-5,6):a.box('ink',(0,.017,z),(19.6,.002,.012))
    a.object('gridded_terrazzo_floor',floor,'surface')
    # Deep north bank of private cubicles; center and NPC southwest work paths stay open.
    for i,x in enumerate([-6.8,-2.6,1.6,5.8]):
        def stall(x=x):
            for xx in [x-1.8,x+1.8]:
                a.box('teal',(xx,1.3,4.1),(.07,2.25,3.2))
                for zz in [2.7,5.4]:a.tube('steel',(xx,.03,zz),(xx,.22,zz),.025,8)
            a.box('teal',(x-1.13,1.3,2.5),(1.25,2.25,.07))
            a.box('teal',(x+1.13,1.3,2.5),(1.25,2.25,.07))
            a.box('teal',(x,1.3,2.51),(.98,2.19,.055))
            a.tube('steel',(x+.34,1.14,2.46),(x+.34,1.32,2.46),.022,8)
            a.box('porcelain',(x+.34,1.4,2.47),(.1,.035,.015))
            # Ceramic pedestal and open oval bowl, seat annulus, cistern, flush button.
            a.lathe('porcelain',(x,0,4.65),[(.24,.03),(.28,.08),(.18,.3),(.29,.39)],24,(1,1.25))
            a.lathe('porcelain',(x,0,4.56),[(.22,.28),(.38,.38),(.4,.47),(.33,.49),(.28,.43),(.17,.34)],32,(1,1.35))
            a.lathe('ink',(x,0,4.56),[(.4,.49),(.405,.52),(.32,.53),(.315,.49)],32,(1,1.35))
            a.box('porcelain',(x,.73,5.2),(.68,.65,.27))
            a.tube('steel',(x+.14,1.055,5.2),(x+.14,1.068,5.2),.04,12)
            a.tube('steel',(x-1.55,.8,4.3),(x-1.55,.8,5.2),.025)
            a.tube('steel',(x-1.55,.8,4.3),(x-1.4,.8,4.3),.025)
            a.tube('paper',(x+1.53,.77,4.45),(x+1.53,.77,4.66),.1,16)
        a.object('private_cubicle_%d'%i,stall)
    for x in [-6,-2,2,6]:
        def sink(x=x):
            a.box('oak',(x,.81,-5.22),(2.7,.12,.94))
            a.lathe('porcelain',(x,.86,-5.15),[(.36,0),(.48,.11),(.49,.17),(.43,.18),(.35,.08),(.06,.035)],32,(1,.73))
            a.tube('steel',(x,.9,-5.54),(x,1.31,-5.54),.025)
            a.tube('steel',(x,1.31,-5.54),(x,1.31,-5.25),.025)
            a.box('ink',(x,1.91,-5.77),(2.35,1.25,.04))
            a.box('mirror',(x,1.91,-5.74),(2.25,1.15,.014))
            for xx in [-1.1,1.1]:a.tube('steel',(x+xx,.7,-5.66),(x+xx,.78,-4.94),.023)
            a.box('porcelain',(x+1,1.08,-5.47),(.16,.29,.12))
            a.tube('steel',(x+1,1.24,-5.47),(x+1,1.24,-5.32),.015,8)
        a.object('floating_basin_mirror_%s'%x,sink)
    # Side wall privacy return outside both entry and diagonal NPC paths.
    a.object('entry_privacy_return',lambda:a.box('teal',(8.2,1.2,3.65),(.09,2.1,2.0)))
    for x in [-9,9]:
        a.object('towel_dispenser_%s'%x,lambda x=x:(a.box('steel',(x,1.35,-3.9),(.22,.45,.35)),a.box('paper',(x,.99,-3.9),(.12,.26,.22))))
    return a

def circulation(floor):
    a=Author(); y=floor*5
    # Only real wall spans, never invented corridor closures or shell surfaces.
    spans=[(10,13),(25,27),(39,41)] if floor==0 else [(9,13),(25,27),(41,49)]
    for lo,hi in spans:
        for x in [10.09,15.91]:
            def display(lo=lo,hi=hi,x=x):
                z=(lo+hi)/2
                a.box('oak',(x,y+1.95,z),(.035,1.35,min(hi-lo-.25,2.5)))
                a.box('ink',(x+(.023 if x<13 else -.023),y+1.95,z),(.012,1.23,min(hi-lo-.38,2.38)))
                # Authored abstract engineering print, ruled paper and enamel discs.
                for j in range(3):
                    xx=x+(.033 if x<13 else -.033)
                    a.box('paper',(xx,y+1.95,z-.6+j*.6),(.009,.78,.44))
                    a.tube('teal',(xx-.006,y+2.05,z-.6+j*.6),(xx+.006,y+2.05,z-.6+j*.6),.12,20)
                    for k in range(3):a.box('teal',(xx+(.01 if x<13 else -.01),y+1.75+k*.06,z-.6+j*.6),(.005,.012,.3))
            a.object('framed_campus_print_%s_%s'%(x,lo),display,'wall')
    # No stair furniture. Slender wall-mounted route strips above the ramp's head zone.
    a.object('stair_wall_inlay',lambda:a.box('teal',(10.09,y+3.35,48),(.025,.12,2)),'wall')
    # Seats and foliage in the back of the EXISTING lift alcove, not the z56..60 path.
    a.object('lift_alcove_bench',lambda:bench_at_height(a,20,y,61.35))
    a.object('lift_alcove_plant',lambda:plant_at_height(a,23,y,61.25))
    # Brushed metal lift portal surrounds the existing open entrance, no fake doors.
    for z in [58.03,59.97]:
        a.object('lift_jamb_%s'%z,lambda z=z:a.box('steel',(16.1,y+1.45,z),(.12,2.9,.06)),'wall')
    a.object('lift_header',lambda:a.box('steel',(16.1,y+2.94,59),(.12,.08,2)),'wall')
    return a

def translate_author(a,offset,start):
    # Helper functions capture generated vertices then shift only their newly added geometry.
    for m,triangles in a.parts.items():
        for i in range(start.get(m,0),len(triangles)):
            triangles[i]=[(add(p,offset),n,uv) for p,n,uv in triangles[i]]
    a.current=[add(p,offset) for p in a.current]
def bench_at_height(a,x,y,z):
    start={m:len(v) for m,v in a.parts.items()};bench(a,x,z);translate_author(a,(0,y,0),start)
def plant_at_height(a,x,y,z):
    start={m:len(v) for m,v in a.parts.items()};plant(a,x,z);translate_author(a,(0,y,0),start)

def save(profile,a,origin,output=None,only_material=None):
    output = OUT if output is None else output
    groups=[]
    for material,triangles in sorted(a.parts.items()):
        if only_material is not None and material != only_material:
            continue
        path=output/'meshes'/f'{profile}_{material}.obj';lines=['# Original authored geometry; CCW OBJ; metres; explicit normals and UVs']
        for tri in triangles:
            for p,n,uv in tri:
                lines += ['v '+' '.join(f'{v:.7f}' for v in p),'vt '+' '.join(f'{v:.7f}' for v in uv),'vn '+' '.join(f'{v:.7f}' for v in n)]
        for i in range(len(triangles)):
            k=i*3+1;lines.append('f '+' '.join(f'{v}/{v}/{v}' for v in range(k,k+3)))
        path.write_text('\n'.join(lines)+'\n',encoding='ascii')
        groups.append({'mesh':'res://assets/campus/decor/m105/meshes/'+path.name,'material':material,'triangles':len(triangles)})
    return {'origin':origin,'groups':groups,'objects':a.objects,'triangles':sum(len(t) for t in a.parts.values())}

def main():
    (OUT/'meshes').mkdir(parents=True,exist_ok=True)
    registry=json.loads((ROOT/'assets/campus/world/room_registry.json').read_text())
    rooms={r['id']:r for r in registry['rooms']}
    profiles={'gym':save('gym',gym(),rooms['gym']['center'])}
    payload={'schema':1,'authorship':'Original mathematical geometry authored for this project; no external assets','materials':PALETTE,'profiles':profiles}
    (OUT/'profiles.json').write_text(json.dumps(payload,indent=2)+'\n')
    print('Generated',len(profiles),'profiles;',len(list((OUT/'meshes').glob('*.obj'))),'mesh batches')

if __name__=='__main__':
    import sys
    if '--production-teal-only' in sys.argv:
        output = ROOT/'assets/campus/decor/m105'
        path = output/'profiles.json'
        payload = json.loads(path.read_text(encoding='utf-8'))
        profile = payload['profiles']['gym']
        updated = save('gym',gym(),profile['origin'],output,'teal')
        profile['groups'] = [updated['groups'][0] if group['material']=='teal' else group for group in profile['groups']]
        profile['objects'] = updated['objects']
        profile['triangles'] = sum(group['triangles'] for group in profile['groups'])
        path.write_text(json.dumps(payload,indent=2)+'\n',encoding='utf-8')
    else:
        main()
