"""Preserved v2 proposal; all extra receipts require measured observations."""
import re
import proposed_guards as v1

def digest(value):
    return isinstance(value,str) and re.fullmatch('[0-9a-f]{64}',value) is not None

def privacy(base,s,coverage):
    v1.privacy(base,s,coverage)
    for category in ('owned_unmarked','foreign'):
        if category=='owned_unmarked':
            eligible=[p for p in s['papers'] if p['owner']==s['peer'] and not p['marked'] and not p['lesson']]
        else:
            eligible=[p for p in s['papers'] if p['owner']!=s['peer']]
        expected={p['id'] for p in eligible}
        rows=coverage[category]
        v1.need(len(rows)==len(expected) and {r['id'] for r in rows}==expected,
                'exact eligible projection coverage required')
        for row in rows:
            v1.need(type(row.get('projection_checks')) is int and row['projection_checks']>0
                    and type(row.get('private_fields_found')) is int
                    and row['private_fields_found']==0, 'measured per-paper projection counts required')

def saved(base,s,binding):
    papers=base.official(s)
    v1.need(len(papers)==1,'one owned paper required')
    v1.need(digest(papers[0].get('project_sha256')) and digest(binding.get('project_sha256')),
            'observed and bound project digests required')
    v1.saved(base,s,binding)

def once(base,before,after,course,receipt,paper_binding,request):
    v1.once(base,before,after,course,receipt,paper_binding)
    expected=dict(assessment_id=after['assessment_id'],profile_sha256=after['local_identity_sha256'],
                  course=course,paper_id=base.official(after)[0]['id'],op='submit')
    for field,value in expected.items():
        v1.need(request.get(field)==value and receipt.get(field)==value,'request/ack '+field+' mismatch')
    v1.need(isinstance(request.get('request_id'),str) and bool(request['request_id'])
            and receipt.get('request_id')==request['request_id'],'duplicate request ID mismatch')
    v1.need(digest(request.get('request_sha256'))
            and receipt.get('request_sha256')==request['request_sha256'],'duplicate request digest mismatch')
    v1.need(type(request.get('sequence')) is int and request['sequence']>0
            and receipt.get('sequence')==request['sequence'],'duplicate request sequence mismatch')

practice=v1.practice
rejoin=v1.rejoin
