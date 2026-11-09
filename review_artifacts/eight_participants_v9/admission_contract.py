from pathlib import Path
import hashlib,json
PARSER_NAME='CLASSROOM-EIGHT-V7-PARSER1'
PARSER_ARGUMENTS=['--headless','--check-only','--script','res://tests/acceptance/classroom_network/peer.gd']
MATRIX={'ELM253': ('CLASSROOM-EIGHT-V7-ELM253-LIFECYCLE1', 27096, 1, 'lab', None), 'ETY155': ('CLASSROOM-EIGHT-V7-ETY155-LIFECYCLE1', 27097, 1, 'lab', 'CLASSROOM-EIGHT-V7-ELM253-LIFECYCLE1'), 'MTH147': ('CLASSROOM-EIGHT-V7-MTH147-LIFECYCLE1', 27098, 6, 'lecture', 'CLASSROOM-EIGHT-V7-ETY155-LIFECYCLE1'), 'MTH255': ('CLASSROOM-EIGHT-V7-MTH255-LIFECYCLE1', 27099, 1, 'lecture', 'CLASSROOM-EIGHT-V7-MTH147-LIFECYCLE1')}
def envelope(plan):
    if plan['scenario']=='parser':
        if (plan['name'],plan['scope'],plan['participants'],plan['total_engine_jobs'],plan['budget_seconds'],plan['engine_limit_seconds'],plan['arguments'],plan.get('port'))!=(PARSER_NAME,'ENGINE_ONLY_CLASSROOM_EIGHT_PARSER',1,1,30,8,PARSER_ARGUMENTS,None):raise ValueError('exact parser envelope required')
        return True
    course=plan.get('course');row=MATRIX.get(course)
    if row is None:raise ValueError('unsupported course')
    name,port,week,kind,previous=row
    if type(plan.get('difficulty')) is not int or plan['difficulty']!=0:raise ValueError('exact integer difficulty zero required')
    if (plan.get('name'),plan.get('port'),plan.get('week'),plan.get('kind'),plan.get('difficulty'),plan.get('previous_name'))!=(name,port,week,kind,0,previous):raise ValueError('exact course/name/port/week/kind/difficulty/predecessor tuple required')
    if (plan.get('scope'),plan.get('scenario'),plan.get('participants'),plan.get('total_engine_jobs'),plan.get('per_job_process_limit'),plan.get('budget_seconds'))!=('ENGINE_ONLY_CLASSROOM_EIGHT','lifecycle',8,8,1,300):raise ValueError('exact lifecycle envelope required')
    return True
def validate_parser_receipt(plan,grant,receipt,actual_sha):
    if grant.get('parser_result_sha256')!=actual_sha:raise ValueError('fresh grant must bind exact parser result')
    expected={'name':PARSER_NAME,'plan_sha256':plan['parser_plan_sha256'],'source_cache_lock_sha256':plan['source_cache_lock_sha256'],'engine_sha256':plan['engine_sha256'],'backend_binding_sha256':plan['backend_binding_sha256'],'accepted':True,'resource_hold_remains':False,'overrun':False,'total_engine_jobs':1,'per_job_process_limit':1,'parser_scope':'FIXTURE_PARSE_ONLY','main_startup_tested':False,'Godot_result':'PASS_FOR_THIS_EXACT_CASE_ONLY'}
    for key,value in expected.items():
        if type(receipt.get(key)) is not type(value) or receipt[key]!=value:raise ValueError('parser receipt mismatch: '+key)
    if receipt.get('errors') or receipt.get('source_cache_entries_verified_after')!=1224 or receipt.get('parser_copy_entries_verified_after')!=1224:raise ValueError('parser source/cache stability proof missing')
    backend=receipt.get('backend',{});clean=backend.get('cleanup',{})
    if backend.get('normal_exit')!=0 or backend.get('errors') or any(clean.get(k) is not True for k in ('stop_verified','engine_exit_verified','owned_job_empty_verified')) or clean.get('resource_hold_remains') is not False or clean.get('errors'):raise ValueError('parser normal0/owned Job0 proof failed')
    names=[e.get('event') for e in backend.get('events',[])]
    required=['job_created','engine_created_suspended','atomic_job_assignment_verified_before_resume','actual_engine_image_verified','resumed','owned_job_empty_verified']
    try:positions=[names.index(x) for x in required]
    except ValueError:raise ValueError('parser atomic launch/cleanup events missing')
    if positions!=sorted(positions):raise ValueError('parser launch/cleanup events out of order')
def require_parser(plan,grant):
    path=Path(plan['parser_result']);raw=path.read_bytes();validate_parser_receipt(plan,grant,json.loads(raw),hashlib.sha256(raw).hexdigest())
