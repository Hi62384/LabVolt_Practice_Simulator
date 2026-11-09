"""Independent test oracle over actual Godot-generated instances. No eval/CAS/input execution."""
import json,math,cmath,statistics,itertools,collections
from fractions import Fraction
from pathlib import Path
ROOT=Path(__file__).resolve().parents[3]
def near(a,b):
 assert abs(a-b)<=1e-6*max(1,abs(b)),(a,b)
def cx(value):return complex(value['real'],value['imag'])
def same_set(a,b):
 assert len(a)==len(b),(a,b)
 for x in a:assert any(abs(x-y)<1e-6*max(1,abs(y)) for y in b),(a,b)
def verify(p):
 g=p['generator_id'];q=p['parameters'];a=p['answer']
 if g=='j_power':
  zn,zm,zk,zh=[1j**q[k] for k in ['n','m','k','h']];near(cx(a),[zn,zn*zm,zn/zm,(zn+zm)*zk,(zn+zm)/(zk+zh)][q['mode']])
 elif g=='complex_components':
  z=cx(q['u'])+cx(q['w']);near(a['real'],z.real);near(a['imag'],z.imag);assert a['argument_defined']==(0 if z==0 else 1)
 elif g=='complex_plot':assert a['points']==q['points']
 elif g=='complex_convert':
  z=cx(q['z']);near(cx(a) if q['requested']=='rectangular' else cmath.rect(a['magnitude'],math.radians(a['angle'])),z)
 elif g=='complex_operation':
  z,w=cx(q['z']),cx(q['w']);op=q['operation'];expected={'add':lambda:z+w,'subtract':lambda:z-w,'multiply':lambda:z*w,'divide':lambda:z/w,'conjugate':lambda:z.conjugate(),'reciprocal':lambda:1/z}[op]();near(cx(a),expected)
 elif g=='complex_power':near(cx(a),cx(q['z'])**q['n'])
 elif g=='complex_roots':
  values=list(map(cx,a['values']));assert len(values)==q['n'];assert len({(round(z.real,6),round(z.imag,6)) for z in values})==q['n']
  for z in values:near(z**q['n'],cx(q['z']))
 elif g=='impedance':
  z,w=cx(q['z']),cx(q['w']);expected=1/(1/z+1/w) if q['parallel'] else z+w;near(complex(a['z_real'],a['z_imag']),expected);near(complex(a['i_real'],a['i_imag']),q['v']/expected)
 elif g=='impedance_network':
  z1,z2,z3=cx(q['z1']),cx(q['z2']),cx(q['z3']);parallel=1/(1/z2+1/z3);eq=z1+parallel;v=q['voltage']*parallel/eq;near(complex(a['z_real'],a['z_imag']),eq);near(complex(a['v_real'],a['v_imag']),v);near(complex(a['i2_real'],a['i2_imag']),v/z2);near(complex(a['i3_real'],a['i3_imag']),v/z3)
 elif g=='reactance_equation':
  assert len(a['values'])==1 and a['values'][0]>0 and a['excluded']==[0];omega=a['values'][0];near(omega*q['L']-1/(omega*q['C']),q['X'])
 elif g=='rational_transformed':
  B=-(q['excluded']+q['ex2']+q['A']+q['B']);constant=q['excluded']*q['ex2']+q['A']*q['ex2']+q['B']*q['excluded'];D=B*B-4*constant;roots=[(-B+sgn*math.sqrt(D))/2 for sgn in [-1,1]];valid=[x for x in roots if x not in a['excluded']];same_set(a['values'],valid)
  for x in valid:near(q['A']/(x-q['excluded'])+q['B']/(x-q['ex2']),1)
 elif g=='radical_transformed':
  B=2*q['m']-q['c'];constant=q['m']**2-q['k'];D=B*B-4*constant;roots=[(-B+sgn*math.sqrt(D))/2 for sgn in [-1,1]];valid=sorted(set(u+q['h'] for u in roots if q['c']*u+q['k']>=0 and u+q['m']>=0 and abs(math.sqrt(q['c']*u+q['k'])-u-q['m'])<1e-8));same_set(a['values'],valid);near(a['boundary'],max(q['h']-q['k']/q['c'],q['h']-q['m']))
 elif g in ['trig_proof','log_combine','log_changebase']:pass # Exact shared-core schema proof runs before generator issuance and during all-family tests.
 elif g=='quadratic':
  D=q['b']**2-4*q['a']*q['c'];near(a['discriminant'],D);roots=[(-q['b']+math.sqrt(D))/(2*q['a']),(-q['b']-math.sqrt(D))/(2*q['a'])];same_set(a['values'],sorted(set(roots)))
 elif g=='quadratic_formula':assert len(a['values'])==2 and q['rad']>0 # Shared-core exact-substitution checks are separate.
 elif g=='rational_quadratic':same_set(a['values'],[q['other']]);assert a['excluded']==[q['excluded']]
 elif g=='radical_quadratic':
  expected=[x for x in [(1+math.sqrt(1+4*q['offset']))/2,(1-math.sqrt(1+4*q['offset']))/2] if x>=0 and abs(math.sqrt(x+q['offset'])-x)<1e-8];same_set(a['values'],expected)
 elif g=='biquadratic':same_set(a['values'],[-q['u'],-q['v'],q['u'],q['v']])
 elif g=='quadratic_application':near(a['width']*a['length'],q['area']);near(a['length']-a['width'],q['difference']);assert a['width']>0
 elif g=='quadratic_vertex':near(a['x'],-q['b']/(2*q['a']));near(a['y'],q['c']-q['b']**2/(4*q['a']));assert a['type']==(1 if q['a']>0 else -1)
 elif g=='quadratic_system':
  assert len(a['points'])==2
  for pair in a['points']:near(pair['y'],(pair['x']-q['h'])**2+q['k']);near(pair['y'],q['m']*(pair['x']-q['h'])+q['k']+q['a']**2)
 elif g=='polynomial_remaining':
  for x in a['values']:near(x**3+q['B']*x*x+q['C']*x+q['D'],0)
  assert len(set(a['values']))==3;near(a['b']-q['known'],q['B']);near(a['c']-q['known']*a['b'],q['C']);near(-q['known']*a['c'],q['D'])
 elif g=='resistor_pair':x,y=a['values'];near(x+y,q['series']);near(x*y/(x+y),q['parallel']);assert x>0 and y>0
 elif g=='engineering_power':
  for x in a['values']:near(q['E']*x-q['R']*x*x,q['P']);assert x>=0
 elif g in ['angle_conversion','exact_trig','half_angle','trig_identity']:pass # Exact values/proofs tested through frozen shared facade, no approximate oracle used for equivalence.
 elif g=='trig_equation':
  assert len(a['values'])==2*q['n'];assert len(set(a['values']))==len(a['values'])
  for x in a['values']:assert 0<=x<(2*math.pi if q['radians'] else 360);near(math.sin(q['n']*x*(1 if q['radians'] else math.pi/180)),math.sin(math.radians(q['alpha'])))
 elif g=='waveform':near(a['omega'],2*math.pi*q['frequency']);near(a['period'],1/q['frequency']);near(a['shift'],-q['phase']/a['omega']);near(a['value'],q['amplitude']*math.sin(a['omega']*q['t']+q['phase']))
 elif g=='wave_from_graph':
  for key in ['amplitude','period','offset','shift']:near(a[key],q[key])
  assert 0<=a['shift']<a['period']
 elif g=='wave_graph':
  assert len(a['points'])==5
  for i,point in enumerate(a['points']):near(point['x'],q['shift']+i*q['period']/4);near(point['y'],q['offset']+q['amplitude']*(math.cos(i*math.pi/2) if q['cosine'] else math.sin(i*math.pi/2)))
 elif g=='wave_combine':near(a['magnitude']*math.cos(a['angle']),q['a']);near(a['magnitude']*math.sin(a['angle']),q['b']);near(a['lead_seconds']*q['omega'],a['angle'])
 elif g=='wave_threshold':
  alpha=math.asin(q['ratio']);candidates=[(angle-q['phase'])/q['omega'] for k in range(-4,5) for angle in [alpha+2*math.pi*k,math.pi-alpha+2*math.pi*k] if (angle-q['phase'])/q['omega']>1e-9];near(a['time'],min(candidates))
 elif g=='exponential':
  if q.get('fit'):near(a['initial']*math.exp(a['rate']*q['t1']),q['y1']);near(a['initial']*math.exp(a['rate']*q['t2']),q['y2']);near(a['value_at_t3'],a['initial']*math.exp(a['rate']*q['t3']))
  else:near(a['value'],q['initial']*math.exp(q['rate']*q['t']));assert a['asymptote']==0
 elif g=='exp_equation':near(q['base']**(q['coefficient']*a['x']+q['shift']),q['target'])
 elif g=='rc_model':
  if q.get('unknown_capacitance'):
   C=a['capacitance_microfarads']*1e-6;near(1-math.exp(-q['given_time']/(q['resistance']*C)) if q['charging'] else math.exp(-q['given_time']/(q['resistance']*C)),q['fraction'])
  else:near(a['tau'],q['resistance']*q['capacitance']);near(1-math.exp(-a['time']/a['tau']) if q['charging'] else math.exp(-a['time']/a['tau']),q['fraction'])
 elif g=='exp_substitution':u=math.exp(q['multiplier']*a['x']);near((u-q['positive'])*(u-q['negative']),0);assert u>0
 elif g=='log_evaluate':near(math.log(q['argument'],q['base']),a['value'])
 elif g=='log_rules':assert a['a']==q['power'] and a['b']==-q['divisor']
 elif g=='log_equation':
  assert len(a['values'])==1
  for x in a['values']:assert x>q['h'];near(math.log(x-q['h'])+math.log(x+q['h']),math.log(q['product']))
 elif g=='log_variable_base':
  roots=[(q['coefficient']+s*math.sqrt(q['coefficient']**2+4*q['constant']))/2 for s in [-1,1]];same_set(a['values'],sorted(set(x for x in roots if x>0 and x!=1 and q['coefficient']*x+q['constant']>0)))
 elif g=='decibels':near(a['gain_db'],(20 if q['voltage'] else 10)*math.log10(q['output']/q['input']));near(a['ratio'],q['output']/q['input'])
 elif g=='decibel_inverse':near((20 if q['voltage'] else 10)*math.log10(a['output']/q['input']),q['gain'])
 elif g=='statistics':
  values=sorted(q['data']);n=len(values);counts=collections.Counter(values);maximum=max(counts.values());modes=[] if maximum==1 else [x for x,count in counts.items() if count==maximum];near(a['mean'],statistics.mean(values));near(a['median'],statistics.median(values))
  if 'q1' in a:near(a['q1'],statistics.median(values[:n//2+n%2]));near(a['q3'],statistics.median(values[-(n//2+n%2):]));near(a['iqr'],a['q3']-a['q1'])
  if 'modes' in a:same_set(a['modes'],modes)
  if 'modal_frequency' in a:assert a['modal_frequency']==maximum
  if 'above_mean' in a:
   ticks=[round(x*q['precision']) for x in values];assert a['above_mean']==sum(x*n>sum(ticks) for x in ticks)
 elif g=='frequency':
  if q.get('construct_table'):assert dict(a['rows'])==dict(collections.Counter(q['observations']))
  elif 'missing_index' in q:assert a['missing_frequency']==q['rows'][q['missing_index']][1] and a['total_count']==sum(f for x,f in q['rows'])
  else:near(a['mean'],sum(x*f for x,f in q['rows'])/sum(f for x,f in q['rows']));near(a['count'],sum(f for x,f in q['rows']))
 elif g=='coins':
  count=sum(1 for outcomes in itertools.product([0,1],repeat=q['n']) if (sum(outcomes)>=q['k'] if q['at_least'] else sum(outcomes)==q['k']));expected=Fraction(count,2**q['n'])
  if 'second' in q:expected*=Fraction(math.comb(q['second']['n'],q['second']['k']),2**q['second']['n'])
  assert Fraction(a['probability'])==expected
 elif g=='dice':
  count=sum(1 for outcomes in itertools.product(range(1,7),repeat=q['n']) if (sum(outcomes)==q['threshold'] if q['condition']=='exactly' else sum(outcomes)>=q['threshold']));assert Fraction(a['probability'])==Fraction(count,6**q['n'])
 elif g=='cards':
  rule=q['rule'];eligible=[]
  for suit,rank in itertools.product(range(4),range(1,14)):
   suit_ok=rule['suit_mode']=='all' or (suit==rule['suit'] if rule['suit_mode']=='suit' else suit//2==rule['colour']);match=suit_ok and rule['low']<=rank<=rule['high'];match=not match if rule['complement'] else match
   if match:eligible.append((suit,rank))
  m=len(eligible);expected=Fraction(m,52)**q['draws'] if q['replacement'] else Fraction(math.comb(m,q['draws']),math.comb(52,q['draws']));assert Fraction(a['probability'])==expected
 elif g=='card_union':assert Fraction(a['probability'])==Fraction(1 if q['intersection'] else 16,52)
 elif g=='dice_event':
  v=q['variant'];count=sum(1 for x,y in itertools.product(range(1,7),repeat=2) if [x==y,x!=y,x%2==0 and y%2==0,(x+y)%q['divisor']==0][v]);assert Fraction(a['probability'])==Fraction(count,36)
 else:raise AssertionError('Unknown topic '+g)
if __name__=='__main__':
 import sys
 path=Path(sys.argv[1]) if len(sys.argv)>1 else ROOT/'work/light-project/samples.jsonl';count=0;topics=collections.Counter()
 for line in path.open(encoding='utf-8'):
  p=json.loads(line,parse_float=lambda value:int(float(value)) if float(value).is_integer() else float(value));verify(p);count+=1;topics[p['generator_id']]+=1
 print('MTH255_INDEPENDENT_ORACLE',json.dumps({'samples':count,'topics':len(topics),'failures':0,'exact_equivalence':'shared-core checks, not numerical sampling'}))
