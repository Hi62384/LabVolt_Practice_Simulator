"""Build original baked clothing assets for the LabVolt segmented toon rig."""
from __future__ import annotations
import json, math, struct
from pathlib import Path
from PIL import Image, ImageDraw

ROOT=Path(__file__).resolve().parents[3]
BASE=ROOT/'assets/cosmetics/clothing'; MODELS=BASE/'models'; MATS=BASE/'materials'; THUMBS=BASE/'thumbnails'
MATERIALS={
 'jersey':((56,126,134),0,.84),'fleece':((122,82,142),0,.92),'rib':((39,67,74),0,.78),
 'canvas':((177,112,70),0,.72),'lining':((235,188,91),0,.86),'coat':((222,231,229),0,.82),
 'denim':((43,66,94),0,.76),'twill':((48,56,67),0,.68),'metal':((126,137,148),.78,.24),
 'skirt':((116,63,83),0,.80),'stitch':((224,214,184),0,.75)
}

class Mesh:
 def __init__(self): self.groups={}
 def tri(self,m,a,b,c,n,uv=((0,0),(1,0),(1,1))):
  u = tuple(b[i] - a[i] for i in range(3))
  v = tuple(c[i] - a[i] for i in range(3))
  cross = (u[1]*v[2] - u[2]*v[1], u[2]*v[0] - u[0]*v[2], u[0]*v[1] - u[1]*v[0])
  if sum(cross[i] * n[i] for i in range(3)) < 0:
      b, c = c, b
      uv = (uv[0], uv[2], uv[1])
  self.groups.setdefault(m,[]).extend(((a,n,uv[0]),(b,n,uv[1]),(c,n,uv[2])))
 def quad(self,m,a,b,c,d,n): self.tri(m,a,b,c,n); self.tri(m,a,c,d,n,((0,0),(1,1),(0,1)))
 def surface(self,mat,rows,x=0,z=0,segments=40,fold=.0,bands=()):
  if bands:
   expanded=[]
   for low,high in zip(rows,rows[1:]):
    expanded.append(low)
    for y in sorted({edge for a,b,_ in bands for edge in (a,b) if low[0]<edge<high[0]}):
     t=(y-low[0])/(high[0]-low[0])
     expanded.append((y,low[1]+t*(high[1]-low[1]),low[2]+t*(high[2]-low[2])))
   rows=expanded+[rows[-1]]
  def vertex(row,index):
   y,rx,rz=rows[row]
   a=math.tau*index/segments
   ripple=1+fold*math.sin(a*7+4*y)*math.sin(math.pi*row/(len(rows)-1))
   return (x+rx*math.cos(a)*ripple,y,z+rz*math.sin(a)*ripple)
  def normal(row,i):
   prev,nxt=vertex(max(0,row-1),i),vertex(min(len(rows)-1,row+1),i)
   left,right=vertex(row,i-1),vertex(row,i+1)
   u=tuple(nxt[j]-prev[j] for j in range(3))
   v=tuple(right[j]-left[j] for j in range(3))
   c=(u[1]*v[2]-u[2]*v[1],u[2]*v[0]-u[0]*v[2],u[0]*v[1]-u[1]*v[0])
   length=math.sqrt(sum(q*q for q in c))
   return tuple(q/length for q in c)
  for row in range(len(rows)-1):
   mid=(rows[row][0]+rows[row+1][0])*.5
   material=next((name for lo,hi,name in bands if lo<=mid<hi),mat)
   for i in range(segments):
    ids=[(row,i),(row,i+1),(row+1,i+1),(row+1,i)]
    ps=[vertex(r,c) for r,c in ids]
    ns=[normal(r,c) for r,c in ids]
    us=[(c/segments,r/(len(rows)-1)) for r,c in ids]
    self.groups.setdefault(material,[]).extend((ps[j],ns[j],us[j]) for j in [0,2,1,0,3,2])
 def frustum(self,m,y0,y1,rx0,rz0,rx1,rz1,x=0,z=0,segments=36):
  self.surface(m,[(y0,rx0,rz0),(y1,rx1,rz1)],x,z,segments)
 def cap(self,mat,y,rx,rz,segments=40):
  rim=[(rx*math.cos(math.tau*i/segments),y,rz*math.sin(math.tau*i/segments)) for i in range(segments)]
  for i in range(segments):
   self.tri(mat,(0,y,0),rim[i],rim[(i+1)%segments],(0,1,0))
 def welt(self,mat,points,width):
  for (x,y,z),(a,b,c) in zip(points,points[1:]):
   self.quad(mat,(x-width,y,z),(a-width,b,c),(a+width,b,c),(x+width,y,z),(0,0,1))
 def box(self,m,c,s):
  x,y,z=c;X,Y,Z=(v/2 for v in s); p=[(x-X,y-Y,z-Z),(x+X,y-Y,z-Z),(x+X,y-Y,z+Z),(x-X,y-Y,z+Z),(x-X,y+Y,z-Z),(x+X,y+Y,z-Z),(x+X,y+Y,z+Z),(x-X,y+Y,z+Z)]
  for q,n in [((0,3,2,1),(0,-1,0)),((4,5,6,7),(0,1,0)),((0,1,5,4),(0,0,-1)),((3,7,6,2),(0,0,1)),((0,4,7,3),(-1,0,0)),((1,2,6,5),(1,0,0))]: self.quad(m,*[p[i] for i in q],n)

def torso(mat='jersey',long=False,open_front=False,coat=False,bands=()):
 m=Mesh()
 hem=.69 if coat else .858
 rows=[(hem-.010,.210,.123),(hem,.239,.142),(hem+.020,.242,.147),(.96,.232,.153),(1.10,.239,.154),
       (1.20,.258,.153),(1.25,.263,.148),(1.28,.249,.136),(1.304,.211,.119),
       (1.318,.152,.100),(1.322,.108,.086),(1.323,.084,.074),
       (1.320,.078,.067),(1.318,.078,.067)]
 m.surface(mat,rows,fold=.024,bands=bands)
 if open_front:
  m.box('lining',(-.055,1.08,.153),(.018,.39,.012));m.box('lining',(.055,1.08,.153),(.018,.39,.012))
 if coat:
  m.box('coat',(-.145,.82,.145),(.1,.13,.018));m.box('coat',(.145,.82,.145),(.1,.13,.018))
 return m
def sleeve(mat,length=.22,wide=1):
 m=Mesh()
 m.surface(mat,[(-length-.011,.063*wide,.070*wide),(-length,.078*wide,.087*wide),(-length+.019,.081*wide,.089*wide),
                (-length*.46,.084*wide,.089*wide),(-.021,.087*wide,.089*wide),(.025,.079,.084),
                (.046,.064,.069),(.059,.043,.047),(.065,.021,.023),(.067,.001,.001)],fold=.022)
 m.cap(mat,.067,.001,.001)
 return m
def tee(): return {'Torso':torso(),'SleeveL':sleeve('jersey',.20),'SleeveR':sleeve('jersey',.20)}
def hoodie():
 d={'Torso':torso('fleece'),'SleeveL':sleeve('fleece',.40,1.08),'SleeveR':sleeve('fleece',.40,1.08)};d['Torso'].box('rib',(0,.875,0),(.48,.045,.29));d['Torso'].box('lining',(0,1.02,.155),(.25,.12,.025));d['Torso'].frustum('fleece',1.23,1.42,.20,.12,.13,.10);return d
def jacket():
 d={'Torso':torso('canvas',open_front=True),'SleeveL':sleeve('canvas',.40),'SleeveR':sleeve('canvas',.40)};d['Torso'].box('metal',(0,1.08,.168),(.012,.37,.012));d['Torso'].box('lining',(-.145,1.08,.157),(.09,.065,.018));return d
def labcoat():
 d={'Torso':torso('coat',open_front=True,coat=True),'SleeveL':sleeve('coat',.40,1.04),'SleeveR':sleeve('coat',.40,1.04)};d['Torso'].box('lining',(-.08,1.255,.16),(.1,.08,.018));d['Torso'].box('lining',(.08,1.255,.16),(.1,.08,.018));return d
def leg(mat='denim',length=.72,rad=.108):
 m=Mesh()
 m.surface(mat,[(-length-.004,rad*.70,.080),(-length,rad*.78,.094),(-length+.021,rad*.80,.095),(-length*.66,rad*.85,.104),(-length*.33,rad*.91,.112),(-.04,rad,.119),(.025,rad*.99,.119)],fold=.029)
 return m
def jeans():
 l=leg();r=leg();l.welt('stitch',[(-.057,-.03,.105),(-.055,-.20,.098),(-.051,-.38,.092),(-.046,-.58,.083)],.0017);r.welt('stitch',[(.057,-.03,.105),(.055,-.20,.098),(.051,-.38,.092),(.046,-.58,.083)],.0017)
 return {'LegL':l,'LegR':r}
def shorts(): return {'LegL':leg('twill',.33,.115),'LegR':leg('twill',.33,.115)}
def skirt():
 waist=Mesh();waist.frustum('skirt',.82,.91,.25,.15,.235,.145)
 left=Mesh();right=Mesh();left.frustum('skirt',-.37,.02,.18,.13,.125,.12,x=.035);right.frustum('skirt',-.37,.02,.18,.13,.125,.12,x=-.035)
 for x in (-.11,0,.11): waist.box('stitch',(x,.855,.153),(.012,.055,.01))
 return {'Waist':waist,'LegL':left,'LegR':right}

ITEMS={'fitted_tee':('Harbor Fitted Tee',tee()),'layered_hoodie':('Cedar Layered Hoodie',hoodie()),'field_jacket':('Workshop Field Jacket',jacket()),'lab_coat':('Practical Lab Coat',labcoat()),'straight_jeans':('Indigo Straight Jeans',jeans()),'work_shorts':('Campus Work Shorts',shorts()),'pleated_skirt':('Harbour Pleated Skirt',skirt())}

def jersey_style(material, length, cut, accents):
    bands={"stripes":[(y,y+.035,"rib") for y in (.99,1.105,1.216)],
           "rugby":[(1.045,1.15,"lining")],
           "training":[(.865,.91,"rib")]}
    pieces={"Torso":torso(material,bands=bands.get(cut,())),"SleeveL":sleeve(material,length),"SleeveR":sleeve(material,length)}
    front=pieces["Torso"]
    if cut=="quarter_zip":
        front.frustum("rib",1.27,1.34,.165,.109,.134,.090)
        front.box("metal",(0,1.177,.155),(.012,.22,.014))
        front.box("lining",(-.123,1.16,.147),(.071,.034,.012))
    elif cut=="campus":
        front.box("lining",(-.105,1.174,.146),(.091,.073,.014))
        for x in (-.085,-.108,-.13): front.box("stitch",(x,1.174,.157),(.006,.048,.006))
    elif cut=="cardigan":
        for side in (-1,1): front.box("lining",(side*.027,1.071,.151),(.031,.376,.012))
        for y in (.94,1.005,1.071,1.137): front.box("metal",(0,y,.165),(.018,.017,.012),)
    elif cut=="rugby":
        front.frustum("rib",1.279,1.331,.163,.109,.132,.087)
    elif cut=="training":
        for x in (-.137,.137): front.box("lining",(x,1.10,.139),(.033,.32,.015))
    if accents:
        for sleeve_mesh in (pieces["SleeveL"],pieces["SleeveR"]):
            sleeve_mesh.frustum("rib",-length,-length+.035,.084,.092,.083,.092)
    return pieces

def utility_bottoms(style):
    pieces={}
    for side in (-1,1):
        part=leg("canvas" if style=="cargo" else "fleece",.72 if style!="bermuda" else .31,.109)
        if style=="cargo":
            part.box("lining",(side*.075,-.215,.047),(.073,.148,.098))
            part.box("rib",(side*.076,-.152,.056),(.082,.035,.098))
        elif style=="joggers":
            part.frustum("rib",-.722,-.65,.084,.098,.090,.106)
            part.box("stitch",(side*.076,-.24,.055),(.012,.40,.008))
        else:
            part.frustum("rib",-.315,-.274,.094,.100,.096,.103)
        pieces["LegL" if side<0 else "LegR"]=part
    return pieces

ITEMS.update({
 "campus_pocket_tee": ("Campus Pocket Tee",jersey_style("jersey",.20,"campus",False)),
 "marina_stripe_tee": ("Marina Stripe Tee",jersey_style("jersey",.22,"stripes",False)),
 "summit_quarter_zip": ("Summit Quarter-Zip",jersey_style("fleece",.40,"quarter_zip",True)),
 "alumni_cardigan": ("Alumni Cardigan",jersey_style("fleece",.39,"cardigan",True)),
 "harbor_rugby": ("Harbor Rugby Shirt",jersey_style("jersey",.40,"rugby",True)),
 "track_jacket": ("Campus Track Jacket",jersey_style("canvas",.40,"training",True)),
 "workshop_cargos": ("Workshop Cargo Trousers",utility_bottoms("cargo")),
 "campus_joggers": ("Campus Joggers",utility_bottoms("joggers")),
 "bayside_bermudas": ("Bayside Bermuda Shorts",utility_bottoms("bermuda")),
})

def textures():
 MATS.mkdir(parents=True,exist_ok=True)
 for name,(rgb,metal,rough) in MATERIALS.items():
  a=Image.new('RGB',(128,128),rgb);d=ImageDraw.Draw(a)
  for i in range(0,128,4 if name not in ('denim','twill') else 3): d.line((i,0,i,127),fill=tuple(max(0,c-8) for c in rgb))
  a.save(MATS/f'{name}_albedo.png'); n=Image.new('RGB',(128,128),(128,128,255));nd=ImageDraw.Draw(n)
  for i in range(0,128,8): nd.line((0,i,127,i),fill=(128,136,254))
  n.save(MATS/f'{name}_normal.png');Image.new('RGB',(128,128),(255,int(rough*255),int(metal*255))).save(MATS/f'{name}_orm.png')

def write_model(key,title,parts):
 blob=bytearray();views=[];acc=[];meshes=[];nodes=[];used=[]
 for part,mesh in parts.items():
  prim=[]
  for mat,verts in mesh.groups.items():
   if mat not in used:used.append(mat)
   def add(raw,kind,stride,mins=None,maxs=None,component_type=5126):
    while len(blob)%4:blob.append(0)
    off=len(blob);blob.extend(raw);views.append({'buffer':0,'byteOffset':off,'byteLength':len(raw)});a={'bufferView':len(views)-1,'componentType':component_type,'count':len(raw)//stride,'type':kind}
    if mins is not None:a.update(min=mins,max=maxs)
    acc.append(a);return len(acc)-1
   xyz=[v[0] for v in verts];pa=add(b''.join(struct.pack('<3f',*v[0]) for v in verts),'VEC3',12,[min(v[i] for v in xyz) for i in range(3)],[max(v[i] for v in xyz) for i in range(3)]);na=add(b''.join(struct.pack('<3f',*v[1]) for v in verts),'VEC3',12);ua=add(b''.join(struct.pack('<2f',*v[2]) for v in verts),'VEC2',8)
   # Explicit CCW glTF indices are converted to clockwise by Godot on import.
   indices=add(struct.pack(f'<{len(verts)}H', *range(len(verts))), 'SCALAR', 2, [0], [len(verts)-1], 5123)
   prim.append({'attributes':{'POSITION':pa,'NORMAL':na,'TEXCOORD_0':ua},'indices':indices,'material':used.index(mat),'mode':4})
  meshes.append({'name':part,'primitives':prim});nodes.append({'name':part,'mesh':len(meshes)-1})
 images=[];tex=[];mdefs=[]
 for mat in used:
  def t(uri):images.append({'uri':uri});tex.append({'source':len(images)-1});return len(tex)-1
  rgb,metal,rough=MATERIALS[mat];mdefs.append({'name':mat,'pbrMetallicRoughness':{'baseColorTexture':{'index':t(f'../materials/{mat}_albedo.png')},'metallicRoughnessTexture':{'index':t(f'../materials/{mat}_orm.png')},'metallicFactor':metal,'roughnessFactor':rough},'normalTexture':{'index':t(f'../materials/{mat}_normal.png'),'scale':.5}})
 doc={'asset':{'version':'2.0','generator':'LabVolt clothing authoring tool'},'scene':0,'scenes':[{'nodes':list(range(len(nodes)))}],'nodes':nodes,'meshes':meshes,'materials':mdefs,'images':images,'textures':tex,'samplers':[{}],'buffers':[{'uri':key+'.bin','byteLength':len(blob)}],'bufferViews':views,'accessors':acc}
 MODELS.mkdir(parents=True,exist_ok=True);(MODELS/f'{key}.bin').write_bytes(blob);(MODELS/f'{key}.gltf').write_text(json.dumps(doc,indent=2),encoding='utf8')
 return used
def thumb(key,title,mats):
 THUMBS.mkdir(parents=True,exist_ok=True);im=Image.new('RGBA',(384,384),(26,32,43,255));d=ImageDraw.Draw(im);c=MATERIALS[mats[0]][0];edge=(240,242,244,255)
 if key=='straight_jeans':
  d.polygon([(105,88),(279,88),(270,170),(246,336),(170,336),(192,181),(170,336),(94,336),(114,170)],fill=c+(255,),outline=edge)
  for x in (114,270):d.line((x,118,192,150),fill=MATERIALS['stitch'][0]+(255,),width=4)
 elif key=='work_shorts':
  d.polygon([(102,92),(282,92),(272,260),(211,260),(192,179),(173,260),(112,260)],fill=c+(255,),outline=edge)
  d.rectangle((122,128,174,180),outline=(220,220,220,255),width=4);d.rectangle((210,128,262,180),outline=(220,220,220,255),width=4)
 elif key=='pleated_skirt':
  d.polygon([(126,91),(258,91),(309,307),(75,307)],fill=c+(255,),outline=edge)
  for x in range(103,292,31):d.line((192,110,x,295),fill=MATERIALS['stitch'][0]+(255,),width=3)
 else:
  hem=330 if key=='lab_coat' else 300;d.rounded_rectangle((92,82,292,hem),30,fill=c+(255,),outline=edge,width=4);d.polygon([(92,103),(42,188),(78,211),(112,152)],fill=c+(255,));d.polygon([(292,103),(342,188),(306,211),(272,152)],fill=c+(255,))
  if key=='layered_hoodie':d.ellipse((126,52,258,150),fill=c+(255,),outline=edge,width=4);d.rectangle((132,220,252,270),outline=MATERIALS['lining'][0]+(255,),width=6)
  elif key=='field_jacket':d.line((192,90,192,300),fill=MATERIALS['metal'][0]+(255,),width=7);d.rectangle((108,178,166,225),outline=MATERIALS['lining'][0]+(255,),width=5)
  elif key=='lab_coat':d.line((192,110,192,330),fill=MATERIALS['lining'][0]+(255,),width=6);d.rectangle((105,243,165,291),outline=MATERIALS['lining'][0]+(255,),width=5);d.rectangle((219,243,279,291),outline=MATERIALS['lining'][0]+(255,),width=5)
  else:d.ellipse((153,72,231,126),fill=(26,32,43,255))
 d.text((24,25),title,fill='white');im.save(THUMBS/f'{key}.png')
def main():
 textures()
 for key,(title,parts) in ITEMS.items(): mats=write_model(key,title,parts);thumb(key,title,mats)
 print('Built',len(ITEMS),'clothing assets')
if __name__=='__main__':main()
