"""Nonlaunch evidence verifier. Frozen v7 remains the execution package."""
import importlib.util
import json
from pathlib import Path
import sys
BASE=Path(__file__).resolve().parent
spec=importlib.util.spec_from_file_location('correction',BASE.parent/'mth147_observation_v7_postreview_v2/admission_readiness_v2.py')
v2=importlib.util.module_from_spec(spec);spec.loader.exec_module(v2)

def receipt(stage, publication):
    v2.require(type(publication) is dict,'publication required')
    plan=v2.load(v2.BUNDLE/'plans'/v2.PLAN_FILES[stage])
    target=Path(plan['output'])/'RESULT.json'
    v2.require(publication.get('path')==str(target),'wrong durable receipt identity')
    v2.require(publication.get('durable') is True,'publication incomplete')
    v2.require(v2.digest(publication.get('sha256')),'receipt digest malformed')
    v2.require(v2.inside(target,v2.BUNDLE/'run-data'),'receipt escaped output root')
    v2.require(v2.sha(target)==publication['sha256'],'receipt bytes mismatch')
    result=v2.load(target)
    v2.validate_result(stage,result)
    v2.require(result.get('snapshot')=='L','historical snapshot field changed')
    v2.require(result.get('name')==plan['name'],'result name mismatch')
    v2.require(result.get('resource_hold_remains') is False,'result resource hold')
    v2.require(result.get('errors')==[],'result errors present')
    count=result.get('source_cache_entries_verified_after')
    expected=len(v2.load(v2.BUNDLE/'SOURCE-CACHE-LOCK.json')['files'])
    v2.require(type(count) is int and count==expected,'post-run complete inventory proof missing')
    if stage=='parser':
        v2.require(type(result['backend'].get('normal_exit')) is int,'boolean exit code forbidden')
        v2.require(result['backend'].get('errors')==[],'parser backend errors')
        v2.require(not result['backend']['cleanup'].get('errors'),'parser cleanup errors')
    return result

def validate(stage,row):
    plan=v2.verify_frozen_package(stage)
    for field,value in [('total_engine_jobs',plan['total_engine_jobs']),('per_job_process_limit',1)]:
        v2.require(type(row.get(field)) is int and row[field]==value,'typed Job envelope required')
    v2.require(row.get('label')==v2.LABEL,'explicit instrumentation label required')
    v2.require(row.get('plan_sha256')==v2.PLAN_SHA256[stage],'wrong exact plan')
    v2.require(row.get('source_cache_lock_sha256')==v2.LOCK_SHA256,'wrong lock')
    prior={'parser':None,'solo':'parser','two_peer':'solo'}[stage]
    if prior is None:v2.require(row.get('predecessor') is None,'parser predecessor forbidden')
    else:receipt(prior,row.get('predecessor'))
    v2.validate_request_and_privacy(stage,row)
    # This verifier neither issues nor authenticates grants. The unchanged runner
    # must validate the real exact grant immediately before any launch.
    return True

if __name__=='__main__':
    validate(sys.argv[1],v2.load(sys.argv[2]))
    print('PASS_NONLAUNCH_EVIDENCE_REVIEW_ONLY')
