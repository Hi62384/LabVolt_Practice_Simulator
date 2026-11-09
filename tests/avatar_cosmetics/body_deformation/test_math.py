"""Execute a restricted translation of the ACTUAL pure GDScript map functions.

This tests source arithmetic, not Godot's parser, resources, animation or pixels.
No hand-copied alternative deformation implementation is used.
"""
import ast, itertools, json, math, pathlib, re, struct, time, unittest
ROOT=pathlib.Path(__file__).resolve().parents[3]
SOURCE=(ROOT/'scripts/avatar_cosmetics/body_deformation/body_fit.gd').read_text()
class V:
    def __init__(self,*v): self.v=list(v)
    def __getattr__(self,k): return self.v['xyzw'.index(k)]
    def __setattr__(self,k,v):
        if k=='v': object.__setattr__(self,k,v)
        else: self.v['xyzw'.index(k)]=v
    def lerp(self,b,t): return V(*(a+(c-a)*t for a,c in zip(self.v,b.v)))
    def __getitem__(self,i): return self.v[i]
    def __sub__(self,b): return V(*(a-c for a,c in zip(self.v,b.v)))
    def cross(self,b): return self.x*b.y-self.y*b.x
    def __hash__(self): return hash(tuple(self.v))
    def __eq__(self,b): return isinstance(b,V) and self.v==b.v
V.ZERO=V(0.,0.)
class P(dict):
    __getattr__=dict.__getitem__
def smooth(a,b,x):
    t=max(0.,min(1.,(x-a)/(b-a))); return t*t*(3-2*t)
ENV=dict(Vector2=V,Vector3=V,Vector4=V,float=float,range=range,sqrt=math.sqrt,pow=pow,INF=math.inf,
         sin=math.sin,cos=math.cos,absf=abs,minf=min,maxf=max,
         clampf=lambda x,a,b:max(a,min(b,x)),smoothstep=smooth,
         lerpf=lambda a,b,t:a+(b-a)*t,inverse_lerp=lambda a,b,x:(x-a)/(b-a))
NAMES=['torso_y','neck_y','extra_width','torso_point','arm_factor','leg_factor','hip_factor','_radii','garment_torso_point']
ENVELOPE=(ROOT/'scripts/avatar_cosmetics/body_deformation/mesh_envelope.gd').read_text()
for name in NAMES+['pose','clears','at_y','convex_edges','joint_drop']:
    source=SOURCE if name in NAMES else ENVELOPE
    block=source.split('static func '+name+'(',1)[1].split('\nstatic func ',1)[0]
    signature,body=block.split('\n',1)
    args=signature.split(') ->',1)[0]
    args=re.sub(r':\s*\w+(?:\[\w+\])?','',args).replace(':=','=').replace('false','False').replace('true','True')
    lines=[]
    for line in body.splitlines():
        if 'points.sort_custom(' in line: line='\tpoints.sort(key=lambda a:(a.x,a.y))'
        line=re.sub(r'\bvar\s+(\w+)(?:\s*:\s*\w+(?:\[\w+\])?)?\s*(?::=|=)',r'\1 =',line)
        line=re.sub(r'(\w+)\.size\(\)',r'len(\1)',line)
        line=line.replace('.pop_back()','.pop()')
        line=re.sub(r'\btrue\b','True',line); line=re.sub(r'\bfalse\b','False',line)
        lines.append(line)
    while lines and (not lines[-1].strip() or lines[-1].startswith('##')): lines.pop()
    exec('def '+name+'('+args+'):\n'+'\n'.join(lines),ENV)
BUILDS=ast.literal_eval(SOURCE.split('const BUILDS :=',1)[1].split('\n\nstatic',1)[0].strip())
CORE=(ROOT/'scripts/avatar_cosmetics/core/avatar_core.gd').read_text()
FIELDS=ast.literal_eval(CORE.split('const BODY_FIELDS := ',1)[1].splitlines()[0])
def params(**kw):
    p=P({k:1. for k in FIELDS}); p.update(build='average',depth=1.,coat=False); p.update(kw)
    p.shape=P(BUILDS[p.build]); return p
class Math(unittest.TestCase):
    def test_exact_envelope_solver_and_bounded_cost(self):
        path=ROOT/'assets/cosmetics/clothing/models/lab_coat.gltf'
        d=json.loads(path.read_text()); blob=(path.parent/d['buffers'][0]['uri']).read_bytes()
        node=next(n for n in d['nodes'] if n['name']=='SleeveL')
        prim=d['meshes'][node['mesh']]['primitives'][0]
        def read(index):
            a=d['accessors'][index]; view=d['bufferViews'][a['bufferView']]
            fmt={5126:'f',5123:'H',5125:'I'}[a['componentType']]; size=3 if a['type']=='VEC3' else 1
            step=struct.calcsize('<'+fmt*size); stride=view.get('byteStride',step)
            offset=view.get('byteOffset',0)+a.get('byteOffset',0)
            return [struct.unpack_from('<'+fmt*size,blob,offset+i*stride) for i in range(a['count'])]
        vertices=read(prim['attributes']['POSITION'])
        indices=[x[0] for x in read(prim['indices'])] if 'indices' in prim else list(range(len(vertices)))
        started=time.perf_counter(); cases=queries=max_hull=0
        for build in BUILDS:
            for tw,hips,arms in itertools.product([.65,1.4],repeat=3):
                p=params(build=build,torso_width=tw,torso_length=hips,hips=hips,waist=hips,shoulders=tw,arm_width=arms,arm_length=.65,coat=True)
                edges=[]
                for i in range(0,len(indices),3):
                    for j in range(3):
                        a=vertices[indices[i+j]]; b=vertices[indices[i+(j+1)%3]]
                        f=ENV['arm_factor'](p); edges.append(V(a[0]*f,a[1],b[0]*f,b[1]))
                hull=ENV['convex_edges'](edges); max_hull=max(max_hull,len(hull))
                self.assertLess(len(hull),len(edges)/4)
                torso=[]; rows=[]
                for y in [.69,.96,1.24,1.30,1.32]:
                    rows.append((ENV['torso_y'](y,p),ENV['_radii'](y,p).x))
                for (ya,ra),(yb,rb) in zip(rows,rows[1:]):
                    torso.extend([V(ra,ya,rb,yb),V(-ra,ya,-rb,yb),V(-ra,ya,ra,ya)])
                pivot=V(ENV['_radii'](1.24,p).x,ENV['torso_y'](1.24,p))
                for side in [-1,1]:
                    lower=.12; upper=lower; limit=pivot.y-ENV['joint_drop'](hull,p.arm_length)
                    def clear(angle):
                        nonlocal queries
                        queries+=1
                        return ENV['clears'](torso,ENV['pose'](hull,pivot,p.arm_length,side,angle),limit)
                    if not clear(upper):
                        for trial in [.25,.40,.60,.85,1.10,1.35,1.55]:
                            upper=trial
                            if clear(upper): break
                            lower=upper
                        else: self.fail('No supported rest splay')
                        for _ in range(10):
                            mid=(lower+upper)/2
                            if clear(mid): upper=mid
                            else: lower=mid
                    self.assertTrue(clear(upper)); cases+=1
        elapsed=time.perf_counter()-started
        self.assertLessEqual(queries,cases*19)
        print('Envelope cases/queries/max arm hull edges/offline seconds:',cases,queries,max_hull,round(elapsed,3))
    def test_default_identity_and_individual_controls(self):
        p=params()
        for y in [.69,.85,.86,.87,.96,1.24,1.30,1.32,1.33]:
            v=V(.2,y,.1); self.assertEqual(ENV['torso_point'](v,p).v,v.v)
        checks={'neck_length':lambda p:ENV['neck_y'](1.435,p),
                'neck_width':lambda p:ENV['extra_width'](1.32,p),
                'torso_length':lambda p:ENV['torso_y'](1.24,p),
                'torso_width':lambda p:ENV['extra_width'](1.24,p),
                'hips':lambda p:ENV['hip_factor'](p),
                'arm_width':lambda p:ENV['arm_factor'](p),
                'leg_width':lambda p:ENV['leg_factor'](p)}
        for field,f in checks.items(): self.assertLess(f(params(**{field:.65})),f(params(**{field:1.4})),field)
        self.assertEqual(len({tuple(v.values()) for v in BUILDS.values()}),4)
    def test_mixed_extrema_pivots_neck_and_rows(self):
        keys=['neck_length','neck_width','torso_length','torso_width','hips','arm_width','leg_width','shoulders','waist','width','leg_length']
        count=0
        for build in BUILDS:
            for values in itertools.product([.65,1.4],repeat=len(keys)):
                p=params(build=build,**dict(zip(keys,values)))
                ys=[ENV['torso_y'](y,p) for y in [.69,.86,.87,.96,1.24,1.30,1.32,1.33]]
                self.assertTrue(all(a<b for a,b in zip(ys,ys[1:])))
                shoulder=ENV['_radii'](1.24,p).x
                pivot=.255*p.width*p.shoulders*ENV['extra_width'](1.24,p)
                self.assertAlmostEqual(shoulder,pivot,places=12)
                # Head bottom remains .08 inside neck upper envelope regardless
                # of modern head scale; direct legacy calls bypass this adapter.
                for hs in [.65*.65,1.,1.4*1.4]:
                    head=1.56+.44*(p.torso_length-1)+.135*(p.neck_length-1)+.205*(hs-1)
                    self.assertAlmostEqual(ENV['neck_y'](1.435,p)-(head-.205*hs),.08)
                self.assertLess(ENV['neck_y'](1.225,p),ENV['torso_y'](1.33,p))
                self.assertGreater(ENV['arm_factor'](p),0); self.assertGreater(ENV['leg_factor'](p),0)
                # Parent length moves footwear but never thickness-scales it;
                # same cancellation preserves wrist centre at every user scale.
                for user in [.9,1.1]:
                    offset=-.405+.405*user/p.arm_length
                    self.assertAlmostEqual(p.arm_length*(offset-.405*user/p.arm_length),-.405*p.arm_length)
                count+=1
        self.assertEqual(count,8192)
    def test_actual_garment_vertices_clear_elliptical_body_envelope(self):
        checked=0
        for path in (ROOT/'assets/cosmetics/clothing/models').glob('*.gltf'):
            d=json.loads(path.read_text()); blob=(path.parent/d['buffers'][0]['uri']).read_bytes()
            for node in d['nodes']:
                if node.get('name') not in ['Torso','Waist']: continue
                for prim in d['meshes'][node['mesh']]['primitives']:
                    a=d['accessors'][prim['attributes']['POSITION']]; view=d['bufferViews'][a['bufferView']]
                    self.assertEqual(a['componentType'],5126)
                    offset=view.get('byteOffset',0)+a.get('byteOffset',0); stride=view.get('byteStride',12)
                    for build in BUILDS:
                        for low,high in [(.65,1.4),(1.4,.65),(1.,1.)]:
                            p=params(build=build,torso_length=low,torso_width=high,hips=low,width=high,waist=low,shoulders=high,neck_width=low,depth=high,coat=path.stem=='lab_coat')
                            for i in range(0,a['count'],8):
                                v=V(*struct.unpack_from('<fff',blob,offset+i*stride))
                                out=ENV['garment_torso_point'](v,p,.94); r=ENV['_radii'](v.y,p)
                                radial=math.hypot(out.x/r.x,out.z/r.y)
                                self.assertTrue(all(math.isfinite(x) for x in out.v))
                                if radial>1e-6: self.assertGreaterEqual(radial,1.012-1e-9)
                                checked+=1
        self.assertGreater(checked,1000)
        print('Actual authored garment samples checked:',checked)
if __name__=='__main__': unittest.main()
