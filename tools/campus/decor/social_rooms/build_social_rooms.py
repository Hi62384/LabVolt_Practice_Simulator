"""Original authored furnishing meshes and room profiles. Offline; no Godot invocation."""
from pathlib import Path
from collections import defaultdict
import math, json, hashlib, sys

ROOT = Path(__file__).resolve().parents[4]
OUT = ROOT / 'assets/campus/decor/social_rooms'
TAU = math.tau
PALETTE = {
 'oak': {'color':'b88b5a','roughness':.66},
 'walnut': {'color':'644437','roughness':.7},
 'metal': {'color':'303e46','roughness':.4,'metallic':.65},
 'sage': {'color':'55806b','roughness':.85},
 'red': {'color':'a83e42','roughness':.8},
 'cream': {'color':'eee2c7','roughness':.65},
 'leaf': {'color':'367657','roughness':.9},
 'brass': {'color':'bd9956','roughness':.38,'metallic':.7},
 'blue': {'color':'607c99','roughness':.8},
 'bread': {'color':'d8a15e','roughness':.93},
 'window': {'color':'b3d3d4','roughness':.3},
 'glow': {'color':'f5dda9','roughness':.65,'emission':.35},
}

def sub(a,b):return tuple(x-y for x,y in zip(a,b))
def cross(a,b):return (a[1]*b[2]-a[2]*b[1],a[2]*b[0]-a[0]*b[2],a[0]*b[1]-a[1]*b[0])
def unit(v):
 d=math.sqrt(sum(x*x for x in v));return tuple(x/d for x in v) if d else (0,1,0)

class Model:
 def __init__(self,name):self.name=name;self.parts=defaultdict(list)
 def tri(self,mat,a,b,c,uv=((0,0),(1,0),(1,1))):
  if sum(x*x for x in cross(sub(b,a),sub(c,a)))>1e-15:self.parts[mat].append((a,b,c,uv))
 def quad(self,mat,a,b,c,d):
  self.tri(mat,a,b,c);self.tri(mat,a,c,d,((0,0),(1,1),(0,1)))
 def lathe(self,mat,profile,at=(0,0,0),n=24):
  # Profile runs bottom to top; each radius is positive (closed caps via fans).
  for (r,y),(s,z) in zip(profile,profile[1:]):
   for i in range(n):
    a,b=TAU*i/n,TAU*(i+1)/n
    p=lambda radius,height,t:(at[0]+radius*math.cos(t),at[1]+height,at[2]+radius*math.sin(t))
    self.quad(mat,p(r,y,a),p(s,z,a),p(s,z,b),p(r,y,b))
  for r,y,reverse in [(profile[0][0],profile[0][1],False),(profile[-1][0],profile[-1][1],True)]:
   for i in range(n):
    a,b=TAU*i/n,TAU*(i+1)/n;c=(at[0],at[1]+y,at[2]);p=(at[0]+r*math.cos(a),at[1]+y,at[2]+r*math.sin(a));q=(at[0]+r*math.cos(b),at[1]+y,at[2]+r*math.sin(b))
    self.tri(mat,c,q,p) if reverse else self.tri(mat,c,p,q)
 def rail(self,mat,a,b,r=.025,n=10):
  axis=unit(sub(b,a));u=unit(cross(axis,(0,0,1) if abs(axis[2])<.9 else (0,1,0)));v=cross(axis,u)
  rings=[]
  for center in (a,b):rings.append([tuple(center[k]+r*(u[k]*math.cos(TAU*i/n)+v[k]*math.sin(TAU*i/n)) for k in range(3)) for i in range(n)])
  for i in range(n):
   j=(i+1)%n;self.quad(mat,rings[0][i],rings[0][j],rings[1][j],rings[1][i]);self.tri(mat,a,rings[0][j],rings[0][i]);self.tri(mat,b,rings[1][i],rings[1][j])
 def rounded(self,mat,w,d,y0,y1,r=.08,at=(0,0,0),n=5):
  ring=[]
  for x,z,start in [(w/2-r,d/2-r,0),(-w/2+r,d/2-r,90),(-w/2+r,-d/2+r,180),(w/2-r,-d/2+r,270)]:
   for i in range(n+1):
    t=math.radians(start+i*90/n);ring.append((x+r*math.cos(t),z+r*math.sin(t)))
  # Top/bottom use planar metre UVs, side uses per-face 0..1 UVs.
  for i in range(len(ring)):
   j=(i+1)%len(ring);p=lambda k,y:(at[0]+ring[k][0],at[1]+y,at[2]+ring[k][1])
   self.quad(mat,p(i,y0),p(i,y1),p(j,y1),p(j,y0))
   for y,rev in [(y0,False),(y1,True)]:
    a=(at[0],at[1]+y,at[2]);b=p(i,y);c=p(j,y)
    self.tri(mat,a,c,b) if rev else self.tri(mat,a,b,c)
 def save(self):
  result=[]
  for mat,tris in self.parts.items():
   key=f'{self.name}__{mat}';lines=['# Original LabVolt social-room mesh; Godot clockwise front faces','o '+key]
   # All construction above is right-handed outward CCW. OBJ is kept CCW;
   # Godot OBJ importer performs its own winding conversion.
   adjacent=defaultdict(list)
   for a,b,c,_ in tris:
    face=unit(cross(sub(b,a),sub(c,a)))
    for point in (a,b,c):adjacent[tuple(round(v,6) for v in point)].append(face)
   for a,b,c,uv in tris:
    normal=unit(cross(sub(b,a),sub(c,a)))
    for p in (a,b,c):lines.append('v '+' '.join(f'{v:.6f}' for v in p))
    for p in uv:lines.append('vt '+' '.join(f'{v:.6f}' for v in p))
    for p in (a,b,c):
     neighbors=[n for n in adjacent[tuple(round(v,6) for v in p)] if sum(n[k]*normal[k] for k in range(3))>.34]
     smooth=unit(tuple(sum(n[k] for n in neighbors) for k in range(3)))
     lines.append('vn '+' '.join(f'{v:.6f}' for v in smooth))
   for i in range(len(tris)):
    ids=[3*i+j+1 for j in range(3)];lines.append('f '+' '.join(f'{k}/{k}/{k}' for k in ids))
   path=OUT/'meshes'/f'{key}.obj';path.write_text('\n'.join(lines)+'\n',encoding='ascii')
   points=[p for a,b,c,_ in tris for p in (a,b,c)]
   result.append({'mesh':key,'material':mat,'triangles':len(tris),'bounds_min':[min(p[k] for p in points) for k in range(3)],'bounds_max':[max(p[k] for p in points) for k in range(3)],'sha256':hashlib.sha256(path.read_bytes()).hexdigest()})
  return result

def models():
 all_models=[]
 def model(name):m=Model(name);all_models.append(m);return m
 m=model('dining_table');m.rounded('oak',1.5,1,.70,.8,.23)
 m.lathe('metal',[(.4,.02),(.43,.045),(.35,.08),(.065,.13),(.055,.70)])
 m=model('chair')
 m.rounded('sage',.61,.58,.39,.47,.16)
 # Continuous curved bucket back, open under seat, splayed tubular legs.
 for i in range(16):
  a,b=math.radians(20+i*140/16),math.radians(20+(i+1)*140/16)
  p=lambda t,y,r:(r*math.cos(t),y,.08+r*math.sin(t))
  m.quad('sage',p(a,.46,.29),p(b,.46,.29),p(b,.96,.32),p(a,.96,.32))
  m.quad('sage',p(b,.46,.32),p(a,.46,.32),p(a,.96,.35),p(b,.96,.35))
  m.quad('sage',p(a,.96,.32),p(b,.96,.32),p(b,.96,.35),p(a,.96,.35))
  m.quad('sage',p(a,.46,.32),p(b,.46,.32),p(b,.46,.29),p(a,.46,.29))
 for end,t in enumerate((math.radians(20),math.radians(160))):
  p=lambda y,r:(r*math.cos(t),y,.08+r*math.sin(t))
  cap=(p(.46,.29),p(.96,.32),p(.96,.35),p(.46,.32))
  m.quad('sage',*(cap[::-1] if end else cap))
 for x in [-1,1]:
  for z in [-1,1]:m.rail('metal',(x*.28,.02,z*.26),(x*.20,.41,z*.19),.022)
 m=model('counter')
 m.rounded('sage',6,.76,.06,1.08,.28)
 m.rounded('cream',6.2,1,1.08,1.18,.24)
 m.rounded('metal',5.6,.04,.14,.2,.015,at=(0,0,.39))
 for x in [i*.24-2.64 for i in range(23)]:m.rail('oak',(x,.25,.392),(x,.98,.392),.025,8)
 m=model('tray_setting')
 m.rounded('metal',.43,.30,0,.025,.065)
 m.lathe('cream',[(.09,.028),(.115,.035),(.105,.048)],at=(-.055,0,0))
 m.lathe('cream',[(.036,.025),(.045,.15),(.05,.16),(.05,.17)],at=(.14,0,-.055),n=16)
 m.lathe('bread',[(.065,.05),(.077,.07),(.06,.10),(.015,.12)],at=(-.055,0,0),n=16)
 m=model('tray_stack')
 for y in range(7):m.rounded('metal',.46,.33,y*.018,(y+1)*.018,.06)
 m=model('recycling')
 m.rounded('metal',.62,.58,.02,.78,.1);m.rounded('sage',.66,.62,.78,.84,.12)
 m.rounded('metal',.36,.2,.841,.848,.08,at=(0,0,-.04))
 m=model('planter')
 m.lathe('cream',[(.22,.02),(.29,.08),(.34,.46),(.36,.48),(.36,.52),(.31,.52)])
 for i in range(11):
  a=i*2.399;h=.85+(i%4)*.16;end=(.4*math.cos(a),h,.4*math.sin(a));m.rail('leaf',(0,.45,0),end,.012,6)
  # Closed tapered lance leaves, angled toward the light.
  base=(end[0]*.6,h-.3,end[2]*.6);tip=(end[0]*1.2,h+.27,end[2]*1.2);left=(end[0]-.12*math.sin(a),h,end[2]+.12*math.cos(a));right=(end[0]+.12*math.sin(a),h,end[2]-.12*math.cos(a));ridge=(end[0],h+.045,end[2])
  for a1,b1 in [(base,left),(left,tip),(tip,right),(right,base)]:m.tri('leaf',a1,b1,ridge);m.tri('leaf',b1,a1,(end[0],h-.035,end[2]))
 m=model('pendant')
 m.lathe('brass',[(.32,0),(.34,.04),(.29,.17),(.12,.29),(.06,.32)])
 m.lathe('glow',[(.29,.004),(.29,.018)])
 m.rail('metal',(0,.32,0),(0,.72,0),.012)
 m=model('window_inset')
 m.rounded('window',3.4,.035,.8,2.85,.04)
 for x in [-1.78,0,1.78]:m.rail('oak',(x,.72,0),(x,2.95,0),.055)
 for y in [.72,2.95]:m.rail('oak',(-1.78,y,0),(1.78,y,0),.055)
 m.rounded('oak',3.8,.32,.69,.75,.05)
 m=model('bookcase')
 for x in [-.86,.86]:m.rounded('oak',.1,.4,0,2.25,.035,at=(x,0,0))
 for y in [.12,.61,1.10,1.59,2.14]:m.rounded('oak',1.8,.42,y,y+.065,.035)
 for row in range(4):
  x=-.73
  for j in range(12):
   w=.065+(j%3)*.025;h=.25+((j*7+row*3)%5)*.035
   m.rounded(['red','sage','blue','cream'][(j+row)%4],w,.24,.19+row*.49,.19+row*.49+h,.012,at=(x,0,.015));x+=w+.025
 m=model('study_desk')
 m.rounded('oak',1.5,.85,.72,.79,.10)
 for x in [-.61,.61]:
  for z in [-.3,.3]:m.rail('metal',(x,.02,z),(x,.72,z),.026)
 m.rounded('sage',1.5,.055,.79,1.18,.025,at=(0,0,-.40))
 m.rounded('cream',.3,.38,.794,.817,.015,at=(-.3,0,-.08))
 m.rail('brass',(.48,.79,-.24),(.48,1.18,-.24),.016)
 m.lathe('brass',[(.14,0),(.13,.05),(.045,.12)],at=(.48,1.10,-.24),n=16)
 m=model('lounge_chair')
 m.rounded('blue',.88,.86,.25,.5,.23)
 m.rounded('blue',.88,.22,.45,1.02,.1,at=(0,0,.34))
 for x in [-.37,.37]:m.rounded('blue',.14,.72,.43,.7,.065,at=(x,0,.03))
 for x in [-.30,.30]:
  for z in [-.28,.28]:m.rail('oak',(x,.02,z),(x,.3,z),.035)
 m=model('coffee_machine')
 m.rounded('metal',.75,.48,0,.46,.08)
 m.lathe('metal',[(.15,0),(.15,.22),(.12,.25)],at=(-.20,.46,0),n=16)
 m.rounded('cream',.5,.2,.08,.13,.025,at=(0,0,.28))
 for x in [-.20,.20]:
  m.rail('brass',(x,.33,.24),(x,.26,.30),.02)
  m.lathe('cream',[(.035,.13),(.048,.24)],at=(x,0,.29),n=16)
 m=model('food_display')
 m.rounded('metal',1.8,.52,0,.065,.12)
 for x in [-.68,-.23,.23,.68]:
  m.rounded('cream',.37,.38,.065,.09,.035,at=(x,0,0))
  m.lathe('bread',[(.12,.09),(.13,.14),(.10,.20),(.02,.23)],at=(x,0,0),n=16)
 for x in [-.86,.86]:m.rail('metal',(x,.04,-.2),(x,.48,-.2),.017)
 m.rail('metal',(-.86,.48,-.2),(.86,.48,-.2),.017)
 m=model('acoustic_panel')
 m.rounded('sage',2.6,.06,0,1,.1)
 for x in [i*.14-1.19 for i in range(18)]:m.rail('oak',(x,.08,.04),(x,.92,.04),.022,8)
 return all_models

def generate():
 (OUT/'meshes').mkdir(parents=True,exist_ok=True)
 inventory={m.name:m.save() for m in models()}
 registry=json.loads((ROOT/'assets/campus/world/room_registry.json').read_text())
 registry={r['id']:r for r in registry['rooms']}
 profiles={}
 for rid in ['cafeteria','tim_hortons','subway','library','study']:
  p={'center':registry[rid]['center'],'number':registry[rid]['number'],'groups':[], 'signs':[], 'seat_visuals':[], 'protected':[], 'coverage':[]}
  profiles[rid]=p;instances=defaultdict(list)
  def put(name,x,y,z,yaw=0,scale=1):instances[name].append([x,y,z,yaw,scale,scale,scale])
  def sign(text,x,y,z,yaw=0,color='cream'):p['signs'].append({'text':text,'position':[x,y,z],'yaw':yaw,'color':color})
  def table(x,z,setting=True):
   put('dining_table',x,0,z)
   for zz,yaw in [(z+.95,0),(z-.95,180)]:
    put('chair',x,0,zz,yaw);p['seat_visuals'].append([x,0,zz,yaw])
   if setting:put('tray_setting',x-.2,.805,z,20)
  if rid=='cafeteria':
   p['theme']='sunlit social commons / oak, celadon and warm linen'
   for x in [-5.2,-1.2,3.0,7.0]:
    for z in [-3.3,3.3]:table(x,z)
   put('counter',4.0,0,-.05,90,.85)
   put('food_display',4,1.01,-1.4,90);put('tray_stack',4,1.01,1.4)
   put('coffee_machine',5.5,0,4.4)
   for x in [-1,0,1]:put('recycling',x,0,5.2)
   sign('CAMPUS COMMONS',0,2.9,5.83,180)
   sign('FRESH TODAY  /  SERVING',4,2.65,-.05,90)
   sign('RETURN  /  RECYCLE  /  COMPOST',0,1.5,5.72,180,'sage')
   p['protected']=[[-9.9,-1.25,2.2,2.5],[-7.7,-1.15,10.5,2.3]]
   p['coverage']=['16 dining chair places','8 pedestal dining tables','ribbed serving island','meal trays / bread / cups','tray return and three sorting bins','window insets','leaf planters','pendant rhythm']
  elif rid in ['tim_hortons','subway']:
   p['theme']='warm red coffeehouse' if rid=='tim_hortons' else 'green fresh sandwich market'
   for i in range(4):
    x=-4.5+(i%2)*4.2;z=1+(i//2)*2.7
    put('dining_table',x,0,z);put('chair',x,0,z+.95)
    p['seat_visuals'].append([x,0,z+.9,0]);put('tray_setting',x,.805,z)
   put('counter',0,0,-2.5)
   put('coffee_machine' if rid=='tim_hortons' else 'food_display',1.5,1.18,-2.5)
   put('food_display',-1.5,1.18,-2.5);put('tray_stack',0,1.18,-2.5)
   for x in [4,7.2]:put('pendant',x,3.05,3.3)
   put('recycling',8.8,0,-4.9)
   # Existing live counter menu and labels remain, so authored identity is on rear wall.
   sign('TIM HORTONS  /  COFFEE & BAKED FRESH' if rid=='tim_hortons' else 'SUBWAY  /  FRESHLY MADE',0,3.15,-5.82,0,'red' if rid=='tim_hortons' else 'sage')
   p['protected']=[[-9.9,-1.25,2.2,2.5],[-7.7,-.9,10.5,1.8],[-3.2,-1.4,6.4,.9]]
   p['coverage']=['four exact existing functional seat/table positions','matching 6m counter silhouette','barista equipment' if rid=='tim_hortons' else 'sandwich ingredient display','window insets','sorting','food and cups']
  else:
   p['theme']='calm oak reading room' if rid=='library' else 'quiet celadon individual study'
   for x in [-6.6,-3.6,-.6,2.4]:
    for z in [-3.2,3.0]:
     put('study_desk',x,0,z);put('chair',x,0,z+.95);p['seat_visuals'].append([x,0,z+.95,0])
   for x in [-6,-3.8,-1.6,.6,2.8,5.0,7.2]:put('bookcase',x,0,-5.5)
   for x in [5.4,7.3]:put('lounge_chair',x,0,3.7,180)
   put('dining_table',6.35,0,2.2,0,.65)
   for x in [-5.4,-1,3.4]:put('acoustic_panel',x,1.65,5.78,180)
   sign('LIBRARY  /  DISCOVER · READ · REFLECT' if rid=='library' else 'QUIET STUDY  /  PLEASE SILENCE DEVICES',0,3.15,-5.81,0)
   p['protected']=[[-9.9,-1.25,2.2,2.5],[-7.7,-.25,15.4,1.0],[7.7,-1.25,2.2,2.5]]
   p['coverage']=['eight screened desks / task lamps / notebooks','eight curved reading chairs','seven populated open bookcases','paired reading armchairs','acoustic slat panels','window insets','leaf planters']
  # Decorative simulated glazing only: no shell edits, daylight holes or false exterior claims.
  for z in [-3.4,3.4]:put('window_inset',9.78,0,z,90)
  for x,z in [(-8.8,-4.9),(8.7,4.9)]:put('planter',x,0,z)
  if rid=='cafeteria':
   for x in [-5.2,-1.2,3,7]:
    for z in [-3.3,3.3]:put('pendant',x,3.05,z)
  if rid in ['library','study']:
   for x in [-5,-1,3]:put('pendant',x,3.05,0)
  for name,items in instances.items():
   for part in inventory[name]:
    mat=part['material']
    if rid=='tim_hortons' and mat=='sage':mat='red'
    if rid=='subway' and mat=='oak':mat='cream'
    p['groups'].append({'mesh':part['mesh'],'material':mat,'items':items})
 catalog={'schema':1,'coordinates':'room-local metres, centered on registry center; yaw degrees; no parent anchor offset','palette':PALETTE,'meshes':{s['mesh']:s for parts in inventory.values() for s in parts},'rooms':profiles,'license':'Original authored procedural geometry. No downloaded assets, logos, textures or third-party reference imagery.'}
 (OUT/'profiles.json').write_text(json.dumps(catalog,indent=2)+'\n')
 print(f'Wrote {len(catalog["meshes"])} mesh surfaces and {len(profiles)} replacement profiles')

def update_meshes_only():
 (OUT/'meshes').mkdir(parents=True,exist_ok=True)
 inventory={m.name:m.save() for m in models()}
 path=OUT/'profiles.json'
 catalog=json.loads(path.read_text(encoding='utf-8'))
 catalog['meshes']={s['mesh']:s for parts in inventory.values() for s in parts}
 path.write_text(json.dumps(catalog,indent=2)+'\n',encoding='utf-8')
 print(f'Updated {len(catalog["meshes"])} mesh surfaces without changing room profiles')

if __name__=='__main__':
 update_meshes_only() if '--meshes-only' in sys.argv else generate()
