"""Additional assertions over real peer observations; imports no engine backend."""
from evidence import need, registered, privacy, official

def complete_eight(observations,course):
    roles=['host']+[f'client{i}' for i in range(1,8)]
    need(set(observations)==set(roles),'eight role observations required')
    host=observations['host']; clients=[observations[r] for r in roles[1:]]
    registered(host,clients,8)
    need(all(s['phase']=='complete' for s in observations.values()),'all eight must complete before transport closure')
    need(len({s['assessment_id'] for s in observations.values()})==1 and bool(host['assessment_id']),'assessment divergence')
    need(len({s['deadline'] for s in observations.values()})==1 and host['deadline']>0,'shared original deadline divergence')
    rows=[p for p in host['papers'] if p['official']]
    need(len(rows)==8 and len({p['owner'] for p in rows})==8,'eight distinct actual official owners required')
    need(all(p['marked'] for p in rows),'every official paper must be marked')
    for role,snapshot in observations.items():
        need(snapshot['activity']['course_id']==course,'wrong formal course')
        need(len(official(snapshot))==1,'one owned official paper per real engine')
        if role!='host':
            privacy(snapshot)
            foreign=[p for p in snapshot['papers'] if p['official'] and p['owner']!=snapshot['peer']]
            need(len(foreign)==7,'all seven foreign official papers must be observed')
            need(all(p['answer_count']==0 and p['strokes']==0 and not p['marked'] and p['score'] is None for p in foreign),'foreign official work/marks leaked')
