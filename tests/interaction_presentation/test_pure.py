"""Bounded Python execution of the production scalar GDScript subset.
This is NOT a Godot parser/engine/rig test. Fails on unsupported syntax.
No child processes/network. Run python project/tests/interaction_presentation/test_pure.py.
"""
import copy, io, json, math, pathlib, re, sys, time, tokenize, unittest
ROOT=pathlib.Path(__file__).resolve().parents[2]
class Dict(dict):
    def is_empty(self): return not self
    def has(self,key): return key in self
    def size(self): return len(self)
    def duplicate(self,deep=False): return wrap(copy.deepcopy(self))
class Array(list):
    def size(self): return len(self)
def wrap(value):
    if isinstance(value,dict): return Dict({k:wrap(v) for k,v in value.items()})
    if isinstance(value,list): return Array(wrap(v) for v in value)
    return value
class Vector3:
    def __init__(self,x=0,y=0,z=0): self.x,self.y,self.z=x,y,z
    def is_finite(self): return all(math.isfinite(v) for v in (self.x,self.y,self.z))
    def __eq__(self,other): return isinstance(other,Vector3) and vars(self)==vars(other)
Vector3.ZERO=Vector3()
def load(name):
    source=(ROOT/'scripts/interaction_presentation'/name).read_text()
    fields=re.findall(r'^var (\w+) = ',source,re.M)
    out=['class Production:']
    init=[]
    for raw in source.splitlines():
        if raw.startswith('extends ') or raw.startswith('##') or not raw.strip(): continue
        if raw.startswith('var '):
            init.append('        self.'+raw[4:].replace('true','True').replace('false','False'));continue
        line=raw.replace('\t','    ')
        line=re.sub(r'^( *)const ',r'\1',line)
        static=line.startswith('static func ')
        if static: line=line.replace('static func ','func ',1)
        if line.startswith('func '):
            line=re.sub(r' -> \w+', '',line)
            line=re.sub(r': (Dictionary|int|bool|float|String)(?=[,)])','',line)
            line=line.replace('func ','def ',1)
            if static: out.append('    @staticmethod')
            else: line=line.replace('(', '(self,',1).replace('(self,)', '(self)')
        line=line.replace('not target is Vector3','not isinstance(target,Vector3)')
        line=line.replace('% [kind,index]','% (kind,index)')
        line=re.sub(r'\bvar (\w+) = ',r'\1 = ',line)
        indent=len(line)-len(line.lstrip())
        line=line.lstrip()
        tokens=[]
        previous=''
        for tok in tokenize.generate_tokens(io.StringIO(line).readline):
            kind,string,*_=tok
            if kind==tokenize.NAME:
                if string in fields and previous!='.': string='self.'+string
                elif string in ('true','false'): string=string.capitalize()
                elif string=='null': string='None'
                elif string in ('cancel','active') and previous!='.' and not line.startswith('def '): string='self.'+string
            tokens.append((kind,string))
            if kind not in (tokenize.INDENT,tokenize.DEDENT,tokenize.NEWLINE,tokenize.ENDMARKER): previous=tok.string
        # Untokenize preserves indentation; literal containers gain only Godot helpers.
        line=tokenize.untokenize(tokens).rstrip()
        out.append('    '+' '*indent+line)
    if fields:
        out.append('    def __init__(self):')
        out.extend(init)
    code='\n'.join(out)
    # Wrap literal dictionaries/arrays through AST, keeping their production values.
    import ast
    tree=ast.parse(code)
    class Containers(ast.NodeTransformer):
        def visit_Dict(self,node):
            self.generic_visit(node);return ast.copy_location(ast.Call(ast.Name('Dict',ast.Load()),[node],[]),node)
        def visit_List(self,node):
            self.generic_visit(node);return ast.copy_location(ast.Call(ast.Name('Array',ast.Load()),[node],[]),node)
    tree=ast.fix_missing_locations(Containers().visit(tree))
    env=dict(Dict=Dict,Array=Array,Vector3=Vector3,clampf=lambda v,a,b:max(a,min(b,v)),minf=min,maxf=max,is_finite=math.isfinite,sin=math.sin,PI=math.pi,sign=lambda v:(v>0)-(v<0))
    exec(compile(tree,name,'exec'),env)
    cls=env['Production']
    if hasattr(cls,'DURATIONS'): env['DURATIONS']=cls.DURATIONS
    if hasattr(cls,'cable'): env['cable']=cls.cable
    return cls
Timeline=load('timeline.gd');Projector=load('accepted_event.gd')
def event(kind='insert',sequence=1):return wrap(dict(kind=kind,sequence=sequence,turn=.45,target=Vector3(1,1,1)))
def cable(a='',b='',owner=2):return dict(id=7,a=a,b=b,owner=owner,color=0)
def snapshot(c=None,**values):return wrap(dict(cables=[c] if c is not None else [],revision=3,**values))
class PureChecks(unittest.TestCase):
    def test_idle_and_hold(self):
        t=Timeline();self.assertFalse(t.active());t.reconcile_hold(wrap(dict(cable=7,end=0,station=0)))
        self.assertTrue(t.active());self.assertEqual(t.sample()['grip'],.75)
        t.reconcile_hold(Dict());self.assertFalse(t.active())
    def test_all_operations_finish(self):
        for kind in Timeline.DURATIONS:
            t=Timeline();self.assertTrue(t.accept(event(kind)));t.advance(1);self.assertFalse(t.active())
    def test_replay_stale_and_bounded_supersession(self):
        t=Timeline();self.assertTrue(t.accept(event(sequence=8)));self.assertFalse(t.accept(event(sequence=8)))
        self.assertFalse(t.accept(event(sequence=2)));self.assertTrue(t.accept(event('knob',9)))
        for i in range(10,1010): self.assertTrue(t.accept(event('knob',i)))
        self.assertEqual(t.event['sequence'],1009);self.assertEqual(t.elapsed,0)
    def test_continuous_knob_reaches_contact_under_fast_updates(self):
        t=Timeline()
        for seq in range(1,21):
            t.accept(event('knob',seq));t.advance(.035)
        self.assertGreater(t.sample()['reach'],.9);self.assertGreater(t.sample()['twist'],.05)
        t.advance(1);self.assertFalse(t.active())
    def test_cancel_preserves_authoritative_hold(self):
        t=Timeline();h=wrap(dict(cable=7,end=1,station=0));t.reconcile_hold(h);t.accept(event());t.cancel()
        self.assertEqual(t.hold,h);self.assertEqual(t.sample()['reach'],0);self.assertTrue(t.active())
        self.assertFalse(t.accept(event()))
    def test_setting_and_facility_priority(self):
        for method in ['set_enabled','set_suspended']:
            t=Timeline();t.reconcile_hold(wrap(dict(cable=7)));t.accept(event())
            getattr(t,method)(False if method=='set_enabled' else True)
            self.assertFalse(t.active());self.assertFalse(t.accept(event(sequence=2)))
            getattr(t,method)(True if method=='set_enabled' else False)
            self.assertTrue(t.active());self.assertTrue(t.event.is_empty())
    def test_reconnect_rebaseline(self):
        t=Timeline();t.accept(event(sequence=800));t.reconcile_hold(wrap(dict(cable=7)));t.reset()
        self.assertFalse(t.active());self.assertTrue(t.accept(event(sequence=1)))
        t.set_suspended(True);t.reset();t.reconcile_hold(wrap(dict(cable=9)));self.assertTrue(t.active());self.assertTrue(t.event.is_empty())
    def test_samples_finite_and_bounded(self):
        for kind,duration in Timeline.DURATIONS.items():
            t=Timeline();t.accept(event(kind))
            for i in range(100):
                t.advance(duration/100);s=t.sample()
                for key in ('reach','grip'):self.assertTrue(0<=s[key]<=1)
                self.assertTrue(abs(s['twist'])<=.45);self.assertTrue(0<=s['connector']<=.065)
                self.assertTrue(all(math.isfinite(s[k]) for k in ('reach','grip','twist','connector')))
    def test_removal_transfers_from_socket_to_carried_anchor(self):
        t=Timeline();t.accept(event('remove'))
        self.assertEqual(t.sample()['transfer'],0)
        t.advance(.20);self.assertGreater(t.sample()['transfer'],.7)
        t.advance(.02);self.assertGreater(t.sample()['transfer'],.9)
    def test_invalid_delta_and_kind(self):
        t=Timeline();self.assertFalse(t.accept(event('unsupported')));t.accept(event())
        for dt in (0,-1,float('nan'),float('inf')):t.advance(dt)
        self.assertEqual(t.elapsed,0)
    def test_hold_is_copied(self):
        t=Timeline();h=wrap(dict(cable=7));t.reconcile_hold(h);h['cable']=999;self.assertEqual(t.hold['cable'],7)
    def test_insert_and_remove_real_endpoint_diff(self):
        positions=wrap(dict(P=Vector3(1,1,1)))
        for op,old,new,kind,end in [('plug',cable(),cable('P'),'insert',0),('plug',cable('P'),cable('P','P',0),'insert',1),('unplug',cable('P','P',0),cable('P'),'remove',1),('undo',cable('P','P',0),cable('P'),'remove',1)]:
            a=snapshot(old);b=snapshot(new);saved=copy.deepcopy((a,b))
            e=Projector.project(2,0,wrap(dict(op=op)),a,b,positions,4)
            self.assertEqual((e['kind'],e['cable'],e['end']),(kind,7,end));self.assertEqual((a,b),saved)
    def test_noop_rejection_missing_target_wrong_owner(self):
        a=snapshot(cable());b=snapshot(cable('P'))
        for old,new,positions in [(a,a,wrap(dict(P=Vector3()))),(a,b,Dict()),(snapshot(cable(owner=3)),b,wrap(dict(P=Vector3()))),(a,b,wrap(dict(P=Vector3(float('nan')))))]:
            self.assertEqual(Projector.project(2,0,wrap(dict(op='plug')),old,new,positions,1),{})
    def test_grasp_requires_owner_change_or_new_item(self):
        action=wrap(dict(op='grab'))
        e=Projector.project(2,0,action,snapshot(cable('P',owner=0)),snapshot(cable('P')),Dict(),1)
        self.assertEqual((e['kind'],e['end']),('grasp',1))
        self.assertEqual(Projector.project(2,0,action,snapshot(cable()),snapshot(cable()),Dict(),2),{})
    def test_knob_switch_and_saturated_noop(self):
        p=wrap(dict(variable=Vector3(),R_0=Vector3(),power=Vector3()))
        a=snapshot(level=.5,switches=dict(R=[False]),powered=False);b=snapshot(level=.55,switches=dict(R=[True]),powered=True)
        for action,kind in [(dict(op='voltage'),'knob'),(dict(op='switch',kind='R',index=0),'switch'),(dict(op='power'),'switch')]:
            self.assertEqual(Projector.project(2,0,wrap(action),a,b,p,1)['kind'],kind)
            self.assertEqual(Projector.project(2,0,wrap(action),b,b,p,2),{})
    def test_modules_do_not_write_domain_or_create_equipment(self):
        forbidden=('session.request(','.act(','.recalculate(','.rpc(','.rpc_id(','StaticBody3D.new','CollisionShape3D.new','LabState','FileAccess.open','OS.execute')
        for p in (ROOT/'scripts/interaction_presentation').glob('*.gd'):
            s=p.read_text()
            for phrase in forbidden:self.assertNotIn(phrase,s,str(p))
if __name__=='__main__':
    start=time.perf_counter();suite=unittest.defaultTestLoader.loadTestsFromTestCase(PureChecks)
    result=unittest.TextTestRunner(verbosity=2).run(suite)
    print(json.dumps(dict(checks=result.testsRun,failures=len(result.failures),errors=len(result.errors),seconds=round(time.perf_counter()-start,4),scope='Production scalar source translated to Python; not Godot validation')))
    sys.exit(not result.wasSuccessful())
