"""Additive proposal. Caller supplies reviewed base evidence module explicitly.
Unmeasured receipts are mandatory prerequisites, never inferred from booleans.
"""
import hashlib
import re

def need(ok, why):
    if not ok: raise ValueError(why)

def identity(s):
    need(bool(re.fullmatch('[0-9a-f]{64}', s['local_identity_sha256'])), 'identity digest required')
    need(isinstance(s['assessment_id'], str) and bool(s['assessment_id']), 'nonempty assessment required')

def practice(base, before, after, paper_id):
    base.practice_excluded(before, after)
    need(paper_id not in {p['id'] for p in before['papers']}, 'paper predates new request')
    rows = [p for p in after['papers'] if p['id'] == paper_id]
    need(len(rows) == 1, 'exact requested paper missing')
    p = rows[0]
    need(p['owner'] == after['peer'] and p['marked'] and not p['official']
         and not p['guide'] and not p['lesson'], 'owned marked practice required')

def privacy(base, s, coverage):
    base.privacy(s)
    # coverage must be emitted while scanning actual received dictionaries.
    need(coverage.get('peer') == s['peer'] and s['peer'] != 1, 'client coverage required')
    for category in ('owned_unmarked', 'foreign'):
        rows = coverage.get(category, [])
        need(bool(rows), 'missing '+category+' projection coverage')
        ids = {p['id']:p for p in s['papers']}
        for row in rows:
            need(row['id'] in ids and row.get('clean') is True, 'unobserved or dirty projection')
            p = ids[row['id']]
            need((p['owner'] == s['peer'] and not p['marked'] and not p['lesson'])
                 if category == 'owned_unmarked' else p['owner'] != s['peer'], 'coverage category mismatch')

def saved(base, s, binding):
    base.saved_assessment(s); identity(s)
    need(bool(re.fullmatch('[0-9a-f]{64}', s['save_evidence']['journal_sha256'])), 'hex journal digest required')
    papers = base.official(s)
    need(len(papers) == 1, 'owned saved paper required')
    need(binding.get('journal_sha256') == s['save_evidence']['journal_sha256']
         and binding.get('profile_sha256') == s['local_identity_sha256']
         and binding.get('assessment_id') == s['assessment_id']
         and binding.get('paper_id') == papers[0]['id']
         and binding.get('project_sha256') == papers[0]['project_sha256'], 'journal owned-paper binding missing')

def once(base, before, after, course, receipt, paper_binding):
    base.exactly_once(before, after, course); identity(after)
    p = base.official(after)[0]
    expected = 'assessment:'+after['assessment_id']+':'
    records = [r for r in after['gradebook'].values() if r.get('course_id') == course
               and r.get('assessment_id') == after['assessment_id'] and not r.get('lesson', True)]
    r = records[0]
    need(r['id'] == expected+str(r['profile']), 'attempt record ID mismatch')
    need(paper_binding == dict(paper_id=p['id'], assessment_id=after['assessment_id'],
         profile_sha256=after['local_identity_sha256'], course=course), 'paper record binding missing')
    need(receipt.get('paper_id') == p['id'] and receipt.get('op') == 'submit'
         and receipt.get('host_processed') is True and receipt.get('duplicate') is True,
         'host duplicate-submit processing receipt prerequisite')
    need(len([k for k in after['reward_ids'] if k.startswith(expected)]) == 1, 'ambiguous attempt rewards')

def rejoin(base, before, host, client, clients):
    base.stable_paper(before, client)
    base.registered(host, clients, len(clients)+1)
    connected = host['transport']['connected_peers']
    need(before['peer'] not in connected and client['peer'] in connected,
         'old/new peer transport membership mismatch')
