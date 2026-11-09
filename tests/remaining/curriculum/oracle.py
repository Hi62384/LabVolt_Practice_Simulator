"""Independent test-only SI/complex MNA and closed-form generator oracle.
No Godot solver code is imported or ported; inputs are exported explicit givens.
Run: python oracle.py cases.json report.json
"""
import cmath, copy, json, math, re, sys
from collections import defaultdict

def close(a,b): return abs(a-b)<=max(1e-8,abs(b)*3e-6)
def solve(parts,reference='g'):
    nodes=sorted({p[k] for p in parts for k in ('a','b')}-{reference})
    ids={n:i for i,n in enumerate(nodes)}
    sources=[p for p in parts if p['kind']=='V']
    branches={p['id']:len(ids)+i for i,p in enumerate(sources)}
    n=len(ids)+len(sources); a=[[0j]*n for _ in range(n)]; b=[0j]*n
    def add(row,col,value):
        if row>=0 and col>=0:a[row][col]+=value
    for p in parts:
        x=ids.get(p['a'],-1);y=ids.get(p['b'],-1);value=p['value']
        if p['kind'] in ('R','Z'):
            g=1/value
            add(x,x,g);add(y,y,g);add(x,y,-g);add(y,x,-g)
        elif p['kind']=='I':
            if x>=0:b[x]-=value
            if y>=0:b[y]+=value
        elif p['kind']=='V':
            k=branches[p['id']]
            add(x,k,1);add(y,k,-1);add(k,x,1);add(k,y,-1);b[k]=value
        else:raise AssertionError('Unknown test model '+p['kind'])
    # Independent dense Gauss-Jordan with partial pivoting, used only in tests.
    for col in range(n):
        pivot=max(range(col,n),key=lambda row:abs(a[row][col]))
        assert abs(a[pivot][col])>1e-14,'Singular generated topology'
        a[col],a[pivot]=a[pivot],a[col];b[col],b[pivot]=b[pivot],b[col]
        divisor=a[col][col]
        a[col]=[v/divisor for v in a[col]];b[col]/=divisor
        for row in range(n):
            if row==col:continue
            factor=a[row][col]
            a[row]=[v-factor*w for v,w in zip(a[row],a[col])];b[row]-=factor*b[col]
    volts={reference:0j}|{node:b[index] for node,index in ids.items()}
    drops={p['id']:volts[p['a']]-volts[p['b']] for p in parts}
    amps={p['id']:(drops[p['id']]/p['value'] if p['kind'] in ('R','Z') else p['value'] if p['kind']=='I' else b[branches[p['id']]]) for p in parts}
    # KCL and energy conservation are topology-independent oracle invariants.
    residual=defaultdict(complex)
    for p in parts:residual[p['a']]+=amps[p['id']];residual[p['b']]-=amps[p['id']]
    assert all(abs(i)<1e-7 for i in residual.values()),'KCL invariant'
    assert abs(sum(drops[p['id']]*amps[p['id']].conjugate() for p in parts))<1e-6,'Power conservation'
    return volts,drops,amps

def three(inputs):
    v=inputs['voltage_rms'];f=inputs['frequency_hz'];arms=inputs['arms']
    nodes={'A':v+0j,'B':cmath.rect(v,-2*math.pi/3),'C':cmath.rect(v,2*math.pi/3),'0':0j}
    lines=defaultdict(complex);power=0j
    for arm in arms:
        drop=nodes[arm['a']]-nodes[arm['b']]
        y=1/arm['resistance_ohms']
        if arm['inductance_henry']:y+=1/(1j*2*math.pi*f*arm['inductance_henry'])
        if arm['capacitance_farad']:y+=1j*2*math.pi*f*arm['capacitance_farad']
        i=drop*y;lines[arm['a']]+=i;lines[arm['b']]-=i;power+=drop*i.conjugate()
    return {'Line-to-line RMS source voltage':v*math.sqrt(3),'Line A RMS current':abs(lines['A']),'Total three-phase real power':power.real,'Total three-phase reactive power':power.imag,'Line B RMS current':abs(lines['B']),'Neutral current RMS magnitude':abs(lines['A']+lines['B']+lines['C'])}

def physical(inputs,template):
    v=inputs['voltage_rms'];f=inputs['frequency_hz'];parts=[]
    for node in inputs['source_nodes']:
        if node=='0':continue
        angle=0 if node=='A' else -2*math.pi/3 if node=='B' else 2*math.pi/3
        parts.append(dict(id='V'+node,kind='V',a=node,b='0',value=cmath.rect(v,angle)))
    for bank in inputs['banks']:
        value=bank['value'];kind=bank['kind']
        z=value if kind=='R' else 1j*2*math.pi*f*value if kind=='L' else 1/(1j*2*math.pi*f*value)
        parts.append(dict(id=kind+str(bank['index']),kind='Z',a=bank['a'],b=bank['b'],value=z))
    _,drops,amps=solve(parts,'0')
    assert max(abs(x) for x in drops.values())<135,'Bank voltage boundary'
    return abs(drops['R0']) if template.endswith('voltage') else abs(amps['R0'])

def elm(inputs,template,prompt=''):
    if inputs.get('generator')=='difference.v3':
        return elm(inputs['extension'],inputs['extension_template'])-elm(inputs['base'],inputs['base_template'],inputs['base_prompt'])
    if inputs.get('generator')=='three_phase.v3':return three(inputs)[prompt]
    if inputs.get('generator')=='ac_physical.v3':return physical(inputs,template)
    _,topic,index=template.split('.');topic=int(topic);index=int(index)
    v=inputs['voltage_rms'];f=inputs['frequency_hz'];r=inputs['resistance_ohms'];xl=2*math.pi*f*inputs['inductance_henry']
    if topic==0:
        return {2:1/(1/r+1/inputs['other_resistance_ohms']),3:v/r}[index]
    if topic==1:
        second=inputs['second_phasor_imag']
        return [v*math.sqrt(2),1000/f,abs(complex(v,second)),math.degrees(cmath.phase(complex(v,second)))][index]
    if topic==2:
        z=complex(r+inputs['extra_resistance_ohms'],xl-inputs['xc_ohms']);i=v/abs(z)
        return [abs(z),i,i*i*z.real,z.real/abs(z),i*xl][index]
    if topic==3:
        xc=inputs['xc_ohms'];i=complex(v/r,-v/xl+(v/xc if xc else 0))
        return [v/r,v/xl,abs(i),v*v/r,-v*i.imag][index]
    if topic==4:
        parallel=1/(1/r+1/complex(0,-inputs['xc_ohms']));z=parallel+complex(inputs['second_resistance_ohms'],xl);i=v/abs(z)
        return [z.real,z.imag,i,i*abs(parallel),i*i*z.real][index]
    if topic in (5,6):
        p=3*v*v/r;q=3*v*v/xl
        values=[v*math.sqrt(3),abs(complex(v/r,v/xl)),p,q]
        values.append((q-inputs['target_q_var'])/(3*2*math.pi*f*v*v)*1e6 if topic==6 else (p-q/math.sqrt(3))/2)
        return values[index]
    if topic==7:
        sync=120*f/inputs['poles'];speed=inputs['rotor_rpm'];slip=(sync-speed)/sync
        return [sync,slip*100,slip*f,inputs['shaft_watts']/(speed*2*math.pi/60)][index]
    if topic==8:
        a=inputs['turns_ratio'];v=inputs['primary_voltage']
        return [v/a,v/a/r,v/a/r/a,r*a*a][index]
    if topic==9:
        hz=inputs['switching_hz'];return [1e6/hz,0.5e6/hz,v,v*v/r][index]
    if topic==10:return [inputs['turns']*inputs['flux_change_wb']/inputs['interval_seconds'],inputs['flux_change_wb']/inputs['area_m2'],inputs['turns']*inputs['coil_current']][index]
    raise AssertionError('Unknown ELM template')

COLOURS={'black':0,'brown':1,'red':2,'orange':3,'yellow':4,'green':5,'blue':6,'violet':7,'grey':8,'white':9}
def decode(bands):
    value=0
    for band in bands[:-2]:value=value*10+COLOURS[band]
    exponent={'gold':-1,'silver':-2}.get(bands[-2],COLOURS.get(bands[-2]))
    return value*10**exponent
def dc(case,question):
    p=question['prompt'];parts=case['parts'];s=case['scenario'];v,drops,amps=solve(parts)
    def port():
        open_parts=[x for x in parts if x['id']!='RL'];vo,_,_=solve(open_parts)
        dead=copy.deepcopy(open_parts)
        for x in dead:
            if x['kind']=='V':x['value']=0
        dead.append(dict(id='test',kind='I',a='g',b='n',value=.001))
        vd,_,_=solve(dead)
        return vo['n'].real,(vd['n']-vd['g']).real/.001
    if p.startswith('Four-band'):return decode(s['four_band']['bands'])
    if p.startswith('Five-band'):return decode(s['five_band']['bands'])
    if p.startswith('Minimum resistance of that'):return decode(s['five_band']['bands'])*(1-s['five_band']['tolerance'])
    if p.startswith('Convert R1'):return s['nominal_resistance']/1000
    if p.startswith('Minimum resistance for R1'):return s['nominal_resistance']*(1-s['tolerance'])
    if p.startswith('Maximum resistance for R1'):return s['nominal_resistance']*(1+s['tolerance'])
    if p.startswith('Maximum voltage for R1'):return min(30,math.sqrt(s['rating_watts']*s['nominal_resistance']))
    if p.startswith('Current delivered to both'):return -amps['Vs'].real
    if p.startswith('Energy dissipated'):return (drops['R1']*amps['R1']).real*s['elapsed_seconds']
    if p.startswith('Unloaded wiper'):
        vu,_,_=solve([x for x in parts if x['id']!='RL']);return (vu['w']-vu['g']).real
    if p.startswith('Loaded wiper'):return (v['w']-v['g']).real
    if p.startswith('Resistance from p'):return next(x['value'] for x in parts if x['id']=='R1')
    if p.startswith('Wiper current'):return amps['RL'].real
    if p.startswith('Signed V(g)'):return (v['g']-v['p']).real
    if p.startswith('Signed load voltage from '):
        source=p.removeprefix('Signed load voltage from ').removesuffix(' alone');single=copy.deepcopy(parts)
        for x in single:
            if x['kind']=='V' and x['id']!=source:x['value']=0
        _,drop,_=solve(single);return drop['RL'].real
    if p.startswith('Open-circuit port'):return port()[0]
    if p.startswith('Thévenin resistance'):return port()[1]
    if p.startswith('Load resistance for maximum'):return port()[1]
    if p.startswith('Maximum load power'):
        vt,rt=port();return vt*vt/(4*rt)
    if p.startswith('Equivalent Thévenin voltage'):
        vo,_,_=solve([x for x in parts if x['id']!='RL']);return (vo['p']-vo['g']).real
    if p.startswith('Equivalent Thévenin series'):return 1/sum(1/x['value'] for x in parts if x['kind']=='R' and x['id']!='RL')
    if p.startswith('Signed current from'):return amps[p.split()[-1]].real
    if p.startswith('Signed voltage V(a)'):return drops[p.split()[-1]].real
    if p.startswith('Total current delivered'):return -amps['Vs'].real
    if p.startswith('Equivalent resistance seen'):return s['voltage']/-amps['Vs'].real
    if p.startswith('Power dissipated in '):
        id=p.split()[-1];return (drops[id]*amps[id]).real
    if p.startswith('Dissipation in '):
        id=p.split()[2].rstrip(';');return (drops[id]*amps[id]).real
    raise AssertionError('Unknown DC numeric template '+p)

def expected_unit(case,question):
    p=question['prompt'];inputs=question.get('inputs',{});template=question['template_id']
    if inputs.get('generator')=='difference.v3':
        return expected_unit(case,{'prompt':'','inputs':inputs['extension'],'template_id':inputs['extension_template']})
    if inputs.get('generator')=='ac_physical.v3':return 'V' if template.endswith('voltage') else 'A'
    if inputs.get('generator')=='three_phase.v3':return 'V' if 'voltage' in p else 'var' if 'reactive' in p else 'W' if 'power' in p else 'A'
    if case['course']=='ETY155':
        lower=p.lower()
        if lower.startswith('convert r1'):return 'kΩ'
        if 'energy dissipated' in lower:return 'J'
        if 'power' in lower or lower.startswith('dissipation'):return 'Ω' if lower.startswith('load resistance') else 'W'
        if 'voltage' in lower or lower.startswith('signed v('):return 'V'
        if 'current' in lower:return 'A'
        return 'Ω'
    _,topic,index=template.split('.')
    units={0:{2:'Ω',3:'A'},1:['V','ms','V','degrees'],2:['Ω','A','W','','V'],3:['A','A','A','W','var'],4:['Ω','Ω','A','V','W'],5:['V','A','W','var','W'],6:['V','A','W','var','µF'],7:['rpm','%','Hz','N·m'],8:['V','A','A','Ω'],9:['µs','µs','V','W'],10:['V','T','A·turns']}
    return units[int(topic)][int(index)]

def main():
    cases=json.load(open(sys.argv[1],encoding='utf-8'));errors=[];checks=0;diversity=defaultdict(set);templates=defaultdict(int)
    for case in cases:
        for question in case['questions']:
            if question.get('options'):
                if question.get('calculation_kind')=='rating_selection':
                    power=case['scenario']['voltage']**2/case['scenario']['nominal_resistance']
                    expected=next(i for i,rating in enumerate([.125,.25,.5]) if rating>=power)
                    if question['answer']!=expected:errors.append({'error':'Randomized power rating option key','case':case['seed']})
                    checks+=1
                continue
            try:
                inputs=question.get('inputs',{})
                if case['course']=='ETY155':expected=dc(case,question)
                else:expected=elm(inputs,question['template_id'],question['prompt'])
                assert math.isfinite(expected)
                assert question['unit']==expected_unit(case,question),f"unit {question['unit']} expected {expected_unit(case,question)}"
                assert close(float(question['answer']),expected),f"key {question['answer']} oracle {expected}"
                checks+=1;templates[question['template_id']]+=1
                diversity[(case['course'],case['kind'],case['week'],case['difficulty'])].add(round(float(question['answer']),10))
            except Exception as exc:errors.append({'course':case['course'],'week':case['week'],'difficulty':case['difficulty'],'seed':case['seed'],'prompt':question['prompt'],'error':str(exc)})
        if case.get('physical_plan'):
            plan=case['physical_plan']
            for bank in plan.get('banks',[]):
                assert bank['value'] in {'R':[1200,600,300],'L':[3.2,1.6,.8],'C':[2.2e-6,4.4e-6,8.8e-6]}[bank['kind']]
            assert 0<float(plan['variable_level'])<=1 and 45<=plan['frequency_hz']<=65
    report={'cases':len(cases),'independent_numeric_keys_checked':checks,'numeric_template_ids':len(templates),'template_counts':dict(templates),'errors':errors,'independent_method':'Test-only complex Gauss-Jordan MNA with KCL/power invariants, SI closed forms and colour-band decoding. No source PDF answers or Godot solver imports.'}
    with open(sys.argv[2],'w',encoding='utf-8') as f:json.dump(report,f,indent=2,ensure_ascii=False)
    print(json.dumps({k:report[k] for k in ['cases','independent_numeric_keys_checked','numeric_template_ids']}),'errors=',len(errors))
    for error in errors[:12]:print(error)
    return 1 if errors else 0
if __name__=='__main__':sys.exit(main())
