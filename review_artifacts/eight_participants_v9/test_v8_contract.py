import ast,copy,hashlib,json,tempfile,unittest
from pathlib import Path
from admission_contract import envelope
from course_fixture_contract import load_fixture
from path_contract import MATRIX,PARSER,validate_paths
from run_j import inventory
BASE=Path(__file__).resolve().parent
PROJECT=Path(r'C:\Users\User1\Documents\Codex\2026-11-05\task-6\eight_participants_v7\project')
COURSES=('ELM253','ETY155','MTH147','MTH255')
def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def plan_path(course):return BASE/'plans'/(MATRIX[course][0]+'.json')
def plan(course):return json.loads(plan_path(course).read_text())

class CompletePreflight(unittest.TestCase):
    def test_all_five_complete_plan_command_preflights(self):
        commands=json.loads((BASE/'COMMANDS.json').read_text());self.assertEqual(len(commands),5)
        lock=json.loads((BASE/'SOURCE-CACHE-LOCK.json').read_text());self.assertEqual(inventory(PROJECT,lock),1224)
        for command in commands:
            path=Path(command['argv'][4]);p=json.loads(path.read_text());self.assertEqual(command['plan_sha256'],sha(path))
            self.assertTrue(validate_paths(p,BASE));self.assertTrue(envelope(p))
            self.assertEqual(p['runner_sha256'],sha(BASE/'run_j.py'));self.assertEqual(p['source_cache_lock_sha256'],sha(BASE/'SOURCE-CACHE-LOCK.json'));self.assertEqual(p['backend_binding_sha256'],sha(BASE/'BACKEND-BINDING.json'))
            for item,digest in p['bound_files'].items():self.assertTrue(Path(item).is_file());self.assertEqual(sha(item),digest)
            for rel,digest in p['source_sha256'].items():self.assertEqual(sha(PROJECT/rel),digest)
            for rel,digest in p['cache_sha256'].items():self.assertEqual(sha(PROJECT/'.godot'/rel),digest)
            if p['scenario']!='parser':self.assertEqual(load_fixture(p)['course'],p['course'])
    def test_actual_run_j_calls_both_guards_before_grant_read(self):
        text=(BASE/'run_j.py').read_text();a=text.index('validate_paths(plan,BASE)');b=text.index('envelope(plan)');c=text.index("grant=strict_json")
        self.assertLess(a,b);self.assertLess(b,c)
        self.assertIn("if plan['scenario']=='lifecycle':\n        from course_fixture_contract import load_fixture\n        load_fixture(plan)",text)
    def test_python_syntax_and_v7_project_is_not_copied(self):
        for p in BASE.rglob('*.py'):ast.parse(p.read_text(encoding='utf-8-sig'))
        self.assertFalse((BASE/'project').exists());self.assertTrue(PROJECT.is_dir())

class PathRejections(unittest.TestCase):
    def reject(self,p,pattern=None):
        with self.assertRaisesRegex(ValueError,pattern or '.+'):validate_paths(p,BASE)
    def test_outside_output_predecessor_parser_and_grant_rejected(self):
        cases=[]
        p=plan('ELM253');p['output']=str(BASE.parent/'outside/run');cases.append((p,'output'))
        p=plan('ETY155');p['previous_result']=str(BASE.parent/'outside/RESULT.json');cases.append((p,'predecessor'))
        p=plan('MTH147');p['parser_result']=str(BASE.parent/'outside/parser.json');cases.append((p,'parser'))
        p=plan('MTH255');p['required_root_grant']=str(BASE.parent/'outside/grant.json');cases.append((p,'root grant'))
        for p,label in cases:self.reject(p,label)
    def test_repeated_suffix_paths_rejected(self):
        p=plan('ELM253');p['project']=str(BASE.parent/'eight_participants_v7_v7/project');self.reject(p,'project')
        p=plan('ELM253');p['output']=str(BASE/'run-data/eight_participants_v8_v8'/p['name']);self.reject(p,'output')
        p=plan('ETY155');p['previous_result']=str(BASE/'run-data/eight_participants_v8_v8'/p['previous_name']/'RESULT.json');self.reject(p,'predecessor')
    def test_missing_and_directory_bound_files_rejected(self):
        for target in (BASE/'missing-bound.py',BASE):
            p=plan('ELM253');p['bound_files']={str(target):'0'*64};self.reject(p,'bound file')
    def test_wrong_fixture_runner_lock_and_binding_rejected(self):
        fields={'answer_fixture':BASE/'fixtures/MTH255.json','runner':BASE/'evidence.py','source_cache_lock':BASE/'COMMANDS.json','backend_binding':BASE/'COMMANDS.json'}
        for field,value in fields.items():
            p=plan('ELM253');p[field]=str(value);self.reject(p)

class CourseTupleRejections(unittest.TestCase):
    def test_exact_supported_matrix(self):
        expected={'ELM253':(27096,1,'lab',None),'ETY155':(27097,1,'lab',MATRIX['ELM253'][0]),'MTH147':(27098,6,'lecture',MATRIX['ETY155'][0]),'MTH255':(27099,1,'lecture',MATRIX['MTH147'][0])}
        for course,row in expected.items():
            p=plan(course);self.assertTrue(envelope(p));self.assertEqual((p['port'],p['week'],p['kind'],p['previous_name']),row)
    def test_elm_relabelled_mth255_is_rejected(self):
        p=plan('ELM253');p.update(course='MTH255',port=27099,week=1,kind='lecture',previous_name=MATRIX['MTH147'][0])
        with self.assertRaisesRegex(ValueError,'tuple'):envelope(p)
        with self.assertRaisesRegex(ValueError,'course/name'):validate_paths(p,BASE)
    def test_every_tuple_field_mutation_is_rejected(self):
        mutations={'name':'CLASSROOM-EIGHT-V7-MTH255-LIFECYCLE1','course':'MTH255','port':27099,'week':99,'kind':'lecture','previous_name':'wrong'}
        for field,value in mutations.items():
            p=plan('ELM253');p[field]=value
            with self.assertRaises(ValueError):envelope(p)
    def test_wrong_predecessor_result_even_with_matching_name_rejected(self):
        p=plan('MTH255');p['previous_name']=MATRIX['MTH147'][0];p['previous_result']=str(BASE/'run-data'/MATRIX['ETY155'][0]/'RESULT.json')
        with self.assertRaisesRegex(ValueError,'predecessor'):validate_paths(p,BASE)

if __name__=='__main__':unittest.main(verbosity=2)
