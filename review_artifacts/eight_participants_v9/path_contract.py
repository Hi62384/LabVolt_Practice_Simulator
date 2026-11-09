from pathlib import Path
PARSER='CLASSROOM-EIGHT-V7-PARSER1'
MATRIX={'ELM253': ('CLASSROOM-EIGHT-V7-ELM253-LIFECYCLE1', 27096, 1, 'lab', None), 'ETY155': ('CLASSROOM-EIGHT-V7-ETY155-LIFECYCLE1', 27097, 1, 'lab', 'CLASSROOM-EIGHT-V7-ELM253-LIFECYCLE1'), 'MTH147': ('CLASSROOM-EIGHT-V7-MTH147-LIFECYCLE1', 27098, 6, 'lecture', 'CLASSROOM-EIGHT-V7-ETY155-LIFECYCLE1'), 'MTH255': ('CLASSROOM-EIGHT-V7-MTH255-LIFECYCLE1', 27099, 1, 'lecture', 'CLASSROOM-EIGHT-V7-MTH147-LIFECYCLE1')}
COURSE_BY_NAME={row[0]:course for course,row in MATRIX.items()}
def exact(path,expected,label,must_exist=False):
    actual=Path(path).resolve();want=Path(expected).resolve()
    if actual!=want:raise ValueError('noncanonical '+label)
    if must_exist and not actual.is_file():raise ValueError('missing '+label)
    return actual
def validate_paths(plan,base):
    base=Path(base).resolve();project=Path('C:\\Users\\User1\\Documents\\Codex\\2026-11-05\\task-6\\eight_participants_v7\\project').resolve();name=plan.get('name')
    exact(plan.get('project',''),project,'project')
    if not project.is_dir():raise ValueError('missing project')
    exact(plan.get('runner',''),base/'run_j.py','runner',True)
    exact(plan.get('source_cache_lock',''),base/'SOURCE-CACHE-LOCK.json','source/cache lock',True)
    exact(plan.get('backend_binding',''),base/'BACKEND-BINDING.json','backend binding',True)
    exact(plan.get('output',''),base/'run-data'/str(name),'output')
    exact(plan.get('required_root_grant',''),base/'root-grants'/(str(name)+'.json'),'root grant')
    if plan.get('scenario')=='parser':
        if name!=PARSER:raise ValueError('unsupported parser name')
        if any(plan.get(field) is not None for field in ('parser_result','previous_result','previous_name','answer_fixture')):raise ValueError('parser result/predecessor/fixture forbidden')
    else:
        course=COURSE_BY_NAME.get(name)
        if course is None or plan.get('course')!=course:raise ValueError('unsupported course/name binding')
        expected_previous=MATRIX[course][4]
        expected_result=None if expected_previous is None else base/'run-data'/expected_previous/'RESULT.json'
        if expected_result is None:
            if plan.get('previous_result') is not None:raise ValueError('unexpected predecessor result')
        else:exact(plan.get('previous_result',''),expected_result,'predecessor result')
        if plan.get('previous_name')!=expected_previous:raise ValueError('predecessor name mismatch')
        exact(plan.get('parser_result',''),base/'run-data'/PARSER/'RESULT.json','parser result')
        exact(plan.get('answer_fixture',''),base/'fixtures'/(course+'.json'),'answer fixture',True)
    for field in ('source_sha256','cache_sha256'):
        root=project if field=='source_sha256' else project/'.godot'
        for rel in plan.get(field,{}):
            target=(root/rel).resolve()
            if not target.is_relative_to(root) or not target.is_file():raise ValueError('missing/outside '+field+': '+rel)
    for item in plan.get('bound_files',{}):
        target=Path(item).resolve()
        if not target.is_relative_to(base) or not target.is_file():raise ValueError('outside/missing bound file')
    return True
