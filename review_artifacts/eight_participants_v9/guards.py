"""Private additive checks over actual fixture evidence; no launcher/backend."""
import re
import evidence as staged_base
import proposed_v3 as proposed
from evidence import need,registered,privacy,practice_excluded,saved_assessment,official,exactly_once

def bound_group(host,clients,course,assessment):
    need(len(clients)==7,'seven eligible remote observers required')
    registered(host,clients,8)
    need(host['assessment_id']==assessment and bool(assessment),'host assessment binding')
    peers={host['peer'],*[s['peer'] for s in clients]}
    need(len(peers)==8,'duplicate peer identity')
    bindings={p['id']:p for p in host['paper_bindings'] if p['official']}
    need(len(bindings)==8,'eight actual host-issued bindings required')
    for s in [host,*clients]:
        need(s['activity']['course_id']==course and s['assessment_id']==assessment,'per-peer course/assessment mismatch')
        papers=official(s);need(len(papers)==1,'one identity-owned official paper required')
        p=papers[0];b=bindings.get(p['id'],{})
        need(b.get('owner')==s['peer'] and b.get('course')==course and b.get('assessment_id')==assessment,'actual issued paper binding differs')
        need(b.get('profile_observable') is True and b.get('profile_sha256')==s['local_identity_sha256'],'host-issued profile binding missing')
        observed=[row for row in s['paper_bindings'] if row['id']==p['id']]
        need(len(observed)==1 and observed[0]['course']==course and observed[0]['assessment_id']==assessment,'client actual paper identity missing')
    return bindings

def projection_group(host,clients,course,assessment,*,pre_submit):
    bindings=bound_group(host,clients,course,assessment)
    for s in clients:
        privacy(s)
        if pre_submit:proposed.privacy(staged_base,s,s.get('hardened_projection_coverage',{}))
        c=s.get('projection_coverage',{})
        need(c.get('observer')=='remote_client' and c.get('peer')==s['peer'],'teacher/host cannot substitute for client scan')
        need(c.get('course')==course and c.get('assessment_id')==assessment,'scan belongs to another attempt')
        need(type(c.get('eligible_owned_unmarked')) is int and type(c.get('eligible_foreign')) is int,'measured eligible-paper counts required')
        need(c['eligible_foreign']==7 and (c['eligible_owned_unmarked']==1 if pre_submit else c['eligible_owned_unmarked']==0),'eligible-paper counts differ from intended coverage')
        rows={p['id']:p for p in s['papers']}
        categories=['foreign']+(['owned_unmarked'] if pre_submit else [])
        for category in categories:
            scanned=c.get(category,[])
            expected={k for k,b in bindings.items() if (b['owner']==s['peer'] if category=='owned_unmarked' else b['owner']!=s['peer'])}
            need(len(scanned)==len(expected) and {r['id'] for r in scanned}==expected and bool(expected),'positive eligible '+category+' coverage required')
            for r in scanned:
                p=rows.get(r['id'],{});b=bindings[r['id']]
                need(r.get('clean') is True and r.get('raw_dictionary_scanned') is True,'actual dictionary scan must be clean')
                need(type(r.get('project_dicts')) is int and r['project_dicts']>0 and type(r.get('project_keys')) is int and r['project_keys']>0,'positive measured per-paper dictionary/key scan counts required')
                need(r.get('owner')==b['owner'] and r.get('course')==course and r.get('assessment_id')==assessment,'unrelated scanned paper')
                need(p.get('owner')==b['owner'] and not p.get('lesson',True) and not p.get('guide',True),'unrelated or lesson paper coverage')
                if category=='owned_unmarked':need(not p['marked'],'owned-unmarked coverage captured after mark')
    return True

def journal_binding(snapshot):
    proposed.saved(staged_base,snapshot,snapshot.get('journal_binding',{}))
    saved_assessment(snapshot)
    paper=official(snapshot);need(len(paper)==1,'owned journal paper')
    b=snapshot.get('journal_binding',{});p=paper[0]
    for digest in (p.get('project_sha256'),b.get('project_sha256'),snapshot.get('local_identity_sha256'),b.get('profile_sha256'),b.get('journal_sha256')):
        need(isinstance(digest,str) and re.fullmatch('[0-9a-f]{64}',digest) is not None,'present valid journal/project/profile digest required')
    need(re.fullmatch('[0-9a-f]{64}',snapshot['save_evidence']['journal_sha256']) is not None,'journal hash syntax')
    need(b==dict(journal_sha256=snapshot['save_evidence']['journal_sha256'],profile_sha256=snapshot['local_identity_sha256'],assessment_id=snapshot['assessment_id'],paper_id=p['id'],project_sha256=p['project_sha256']),'actual journal profile/paper/project binding missing')

def practice_link(before,issued,after,course):
    link=issued.get('practice_request_link',{})
    need(before['peer']==issued['peer']==after['peer'] and before['peer']!=1,'actual same remote requester required')
    need(before['local_identity_sha256']==issued['local_identity_sha256']==after['local_identity_sha256'],'practice identity changed')
    need(before['assessment_id']==issued['assessment_id']==after['assessment_id'],'formal attempt changed during practice')
    old={p['id'] for p in before['papers']}
    new=[p for p in issued['papers'] if p['id'] not in old and p['owner']==issued['peer'] and not p['official'] and not p['lesson'] and not p['guide']]
    need(len(new)==1,'singleton newly owned practice delta required')
    p=new[0]
    need(link.get('paper_id')==p['id'] and link.get('request_peer')==issued['peer'] and link.get('profile_sha256')==issued['local_identity_sha256'],'new request/owned paper linkage differs')
    need(link.get('course')==course and link.get('formal_assessment_id')==issued['assessment_id'] and link.get('op')=='new' and type(link.get('command_sequence')) is int,'practice request course/sequence binding missing')
    need(set(link.get('before_ids',[]))==old and link.get('basis')=='single_inflight_request_and_actual_owned_delta','unmeasured request linkage')
    bound=[b for b in issued['paper_bindings'] if b['id']==p['id']]
    need(len(bound)==1 and bound[0]['course']==course and bound[0]['assessment_id']=='','actual nonofficial practice binding missing')
    done=[row for row in after['papers'] if row['id']==p['id']]
    need(len(done)==1 and done[0]['owner']==after['peer'] and done[0]['marked'] and not done[0]['official'] and not done[0]['lesson'] and not done[0]['guide'],'exact newly requested practice must be marked')
    practice_excluded(before,after)
    proposed.practice(staged_base,before,after,p['id'])
    for field in ('reward_ids','dollars'):need(before[field]==after[field],'practice changed '+field)
    return p['id']

def duplicate_processed(before,after,course,receipt,request_context=None):
    exactly_once(before,after,course)
    p=official(after)[0]
    need(isinstance(request_context,dict) and isinstance(receipt,dict),'BLOCKED: actual contextual host duplicate-processing receipt is not observable')
    binding={key:receipt.get(key) for key in ('paper_id','assessment_id','profile_sha256','course')}
    need(binding==dict(paper_id=p['id'],assessment_id=after['assessment_id'],profile_sha256=after['local_identity_sha256'],course=course),'passive host callback binding missing')
    proposed.once(staged_base,before,after,course,receipt,binding,request_context)
    need(request_context.get('peer')==after['peer'] and receipt.get('peer')==after['peer'],'duplicate peer context differs')
