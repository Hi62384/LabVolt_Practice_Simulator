"""Fail-closed checks over observations from actual Main peers. No engine/fixture synthesis."""
import hashlib
import json

COURSES = ('ELM253', 'ETY155', 'MTH147', 'MTH255')

class EvidenceError(ValueError):
    pass

def need(value, message):
    if not value:
        raise EvidenceError(message)

def official(snapshot):
    return [p for p in snapshot['papers'] if p['official'] and p['owner'] == snapshot['peer']]

def stable_paper(before, after, require_new_peer=True):
    a, b = official(before), official(after)
    need(len(a) == len(b) == 1, 'exactly one owned official paper required')
    for key in ('id', 'project_sha256', 'answers_sha256', 'answer_count', 'strokes', 'page'):
        need(a[0][key] == b[0][key], 'rejoin changed ' + key)
    need(before['local_identity_sha256'] == after['local_identity_sha256'], 'identity changed')
    if require_new_peer:
        need(before['peer'] != after['peer'], 'rejoin needs a different real ENet peer ID')
    else:
        need(before['peer'] == after['peer'] == 1, 'solo reload must remain offline peer one')
    need(before['assessment_id'] == after['assessment_id'], 'assessment changed')
    need(before['deadline'] > 0 and before['deadline'] == after['deadline'], 'original deadline changed')
    need(after['remaining'] < before['remaining'], 'remaining time did not decrease')
    need(b[0]['answer_count'] > 0 and b[0]['strokes'] > 0, 'no written work or ink exercised')

def saved_assessment(snapshot):
    saved=snapshot['save_evidence']
    need(saved['ok'] and saved['wrong_profile_rejected'], 'profile-bound journal verification missing')
    need(saved['assessment_id']==snapshot['assessment_id'], 'saved assessment ID differs')
    need(saved['deadline']==snapshot['deadline'] and saved['deadline']>0, 'saved deadline differs')
    need(saved['paper_count']>=1 and len(saved['journal_sha256'])==64, 'saved journal evidence missing')


def registered(host, clients, participants):
    need(participants in (2, 8), 'unsupported stage size')
    need(len(clients) == participants - 1, 'missing OS-client observation')
    need(len(host['roster']) == len(host['identities']) == participants, 'host registration mismatch')
    ids = [host['peer']] + [s['peer'] for s in clients]
    need(len(set(ids)) == participants and host['peer'] == 1, 'duplicate/missing ENet IDs')
    identities = [host['local_identity_sha256']] + [s['local_identity_sha256'] for s in clients]
    need(len(set(identities)) == participants, 'duplicate student identities')
    dirs = [host['user_data_dir']] + [s['user_data_dir'] for s in clients]
    need(len(set(dirs)) == participants, 'peer save directories are shared')
    for s in clients:
        need(s['online'] and len(s['roster']) == participants, 'client roster not converged')
        need(str(s['peer']) in host['identities'], 'client not host-registered')
        need(host['identities'][str(s['peer'])] == s['local_identity_sha256'], 'host identity mismatch')

def privacy(snapshot):
    need(snapshot['peer'] != 1, 'privacy requires a remote observation')
    need(snapshot['peer_work_redacted'], 'foreign work leaked')
    need(snapshot['solution_keys_redacted'], 'private solution key leaked')
    for record in snapshot.get('gradebook',{}).values():
        need(hashlib.sha256(str(record.get('profile','')).encode('utf-8')).hexdigest()==snapshot['local_identity_sha256'],
             'foreign student grade record leaked')
    need(any(p['owner'] != snapshot['peer'] and p['answer_count'] == 0 for p in snapshot['papers']),
         'no foreign paper tested')

def exactly_once(before, after, course):
    need(course in COURSES, 'unknown course')
    need(before['gradebook'] == after['gradebook'], 'duplicate submission changed immutable gradebook')
    need(before['reward_ids'] == after['reward_ids'] and before['dollars'] == after['dollars'],
         'duplicate submission changed rewards')
    records = [r for r in after['gradebook'].values() if not r.get('lesson', True)
               and r.get('course_id') == course and r.get('assessment_id') == after['assessment_id']]
    need(len(records) == 1, 'one delivered official grade required')
    record = records[0]
    need(hashlib.sha256(str(record.get('profile','')).encode('utf-8')).hexdigest()==after['local_identity_sha256'],
         'official grade belongs to another profile')
    need(record['id'] in after['reward_ids'], 'host reward acknowledgement missing')
    papers = official(after)
    need(len(papers) == 1 and papers[0]['marked'] and papers[0]['score'] == record['score'], 'paper/grade mismatch')

def practice_excluded(before, after):
    need(before['summary'] == after['summary'], 'practice changed official summary')
    prior = {k: v for k, v in before['gradebook'].items() if not v.get('lesson', True)}
    final = {k: v for k, v in after['gradebook'].items() if not v.get('lesson', True)}
    need(prior == final, 'practice created or changed official grades')
    need(any(p['marked'] and not p['official'] and not p['guide'] for p in after['papers']),
         'practice was never actually marked')

def late_join(snapshot):
    need(snapshot['phase'] == 'assignment', 'late observation outside assignment')
    need(not official(snapshot), 'late join received an official paper')
    need(any(p['owner'] == snapshot['peer'] and not p['official'] and not p['lesson'] for p in snapshot['papers']),
         'late practice paper missing')

def randomized(host):
    rows = [p for p in host['papers'] if p['official']]
    need(len(rows) >= 2, 'randomization requires two official papers')
    need(len({p['project_sha256'] for p in rows}) == len(rows), 'per-student projects are identical')

def fingerprint(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()
