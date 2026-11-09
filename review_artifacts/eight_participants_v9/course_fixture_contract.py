"""Eight-engine course inputs. File validation and public-givens answers only."""
import hashlib,json,re
from pathlib import Path
from mth255_cases import answers_for as mth255_answers

ROLES=['host']+[f'client{i}' for i in range(1,8)]
SPECS={'ELM253':(1,'lab',6),'ETY155':(1,'lab',4),'MTH147':(6,'lecture',8),'MTH255':(1,'lecture',8)}
MODES={'ELM253':{'correct','first_wrong','all_wrong'},'ETY155':{'correct','first_wrong','all_wrong'},
       'MTH147':{'correct','missing_domain','extra_hole'},'MTH255':{'correct','first_wrong','all_wrong'}}

def validate_fixture(value,course):
    if course not in SPECS:raise ValueError('unknown course')
    week,kind,count=SPECS[course]
    if value.get('schema')!='eight-course-public-givens-v2' or value.get('course')!=course:raise ValueError('nondefault course fixture required')
    if (value.get('week'),value.get('kind'),value.get('difficulty'),value.get('questions'))!=(week,kind,0,count):raise ValueError('retained course instance mismatch')
    if set(value.get('roles',{}))!=set(ROLES):raise ValueError('all eight explicit role inputs required')
    for role,row in value['roles'].items():
        mode=row.get('mode')
        if mode not in MODES[course]:raise ValueError('unknown/default answer mode')
        score=100.0 if mode=='correct' else 81.25 if mode=='missing_domain' else 43.75 if mode=='extra_hole' else 100.0*(count-1)/count if mode=='first_wrong' else 0.0
        final=score/2 if kind=='lab' else score
        if row.get('expected_written_score')!=score or row.get('expected_final_score')!=final:raise ValueError('independent expected score mismatch')
        if kind=='lab' and row.get('expected_practical_score')!=0:raise ValueError('unbuilt practical must not receive invented credit')
    modes={row['mode'] for row in value['roles'].values()}
    if modes!=MODES[course] or value['roles']['host']['mode']!='correct':raise ValueError('positive plus distinct negative cases required')
    return value

def load_fixture(plan):
    raw=plan.get('answer_fixture')
    if not isinstance(raw,str) or not raw:raise ValueError('empty/default fixture binding forbidden for course acceptance')
    path=Path(raw)
    if not path.is_file():raise ValueError('bound fixture missing')
    digest=hashlib.sha256(path.read_bytes()).hexdigest()
    if plan.get('answer_fixture_sha256')!=digest or plan.get('bound_files',{}).get(str(path))!=digest:raise ValueError('fixture not pinned to reviewed bytes')
    return validate_fixture(json.loads(path.read_text(encoding='utf-8')),plan['course'])

def public_answers(project,course):
    """Independent arithmetic over displayed data. Unknown questions fail closed."""
    qs=project['questions'];count=SPECS[course][2]
    if len(qs)!=count:raise ValueError('question count changed')
    if course=='MTH255':return mth255_answers(project)
    data=project['data'];out=[]
    if course=='ELM253':
        m=re.search(r'R1=([0-9.]+).*?R2=([0-9.]+).*?source=([0-9.]+)',data)
        if not m:raise ValueError('ELM253 displayed R1/R2/source grammar changed')
        r1,r2,v=map(float,m.groups())
        parts=project['diagram']['parts']
        if len(parts)!=2:raise ValueError('week1 physical network changed')
        resistor=next(p for p in parts if p['id']=='R0' and p['kind']=='R')
        source=next(p for p in parts if p['id']=='VA' and p['kind']=='V')
        physical_v=float(re.match(r'[0-9.]+',str(source['value'])).group())
        table={'How is an ammeter connected?':'1','Before changing the wiring:':'1',
            'Equivalent resistance of the given R1 and R2 in parallel':str(1/(1/r1+1/r2)),
            'Current through R1 alone':str(v/r1),
            'Physical experiment: RMS voltage across R0':str(physical_v),
            'Physical experiment: RMS current through R0':str(physical_v/float(resistor['value']))}
    elif course=='ETY155':
        m=re.search(r'Vs \(V\): a=p, b=g, value=([0-9.]+)',data)
        n=re.search(r'R1 \(R\): a=p, b=g, value=([0-9.]+)',data)
        if not m or not n:raise ValueError('ETY155 oriented netlist changed')
        v,r=float(m.group(1)),float(n.group(1))
        table={'Where must the ammeter be connected?':'1','Convert R1 to kilo-ohms':str(r/1000),
            'Signed current from a to b through R1':str(v/r),'Signed voltage V(a)-V(b) across R1':str(v)}
    else:raise ValueError('MTH147 uses unchanged dedicated peer public-factor oracle')
    if set(q['prompt'] for q in qs)!=set(table):raise ValueError('unreviewed course question set')
    return [table[q['prompt']] for q in qs]

def answer_commands(fixture,latest):
    course=fixture['course']
    if course=='MTH147':
        return [{role:{'op':'request','selector':'official','action':{'op':'answer','key':'@mth147','value':row['mode']}} for role,row in fixture['roles'].items()}]
    answers={role:public_answers(latest[role]['course_public'],course) for role in ROLES}
    batches=[]
    for i in range(fixture['questions']):
        batch={}
        for role,row in fixture['roles'].items():
            wrong=row['mode']=='all_wrong' or (row['mode']=='first_wrong' and i==0)
            value=({} if course=='MTH255' else 'not-a-number') if wrong else answers[role][i]
            batch[role]={'op':'request','selector':'official','action':{'op':'answer','key':str(i),'value':value}}
        batches.append(batch)
    return batches

def expected_marks(fixture,observations):
    from evidence import need,official
    for role,row in fixture['roles'].items():
        snapshot=observations[role];papers=official(snapshot)
        need(len(papers)==1,'missing identity-owned marked paper')
        paper=papers[0]
        need(paper['marked'] and abs(paper['score']-row['expected_final_score'])<1e-7,'independent expected final mark differs for '+role)
        if fixture['kind']=='lab':
            need(paper['written_score'] is not None and abs(paper['written_score']-row['expected_written_score'])<1e-7,'independent written mark differs')
            need(paper['practical'].get('score')==0,'unbuilt equipment received practical credit')
        if fixture['course']=='MTH147':need(snapshot.get('mth147_public_projection_ok') is True,'math private projection leaked')
