import copy,json,unittest
from pathlib import Path
from admission_contract import envelope
from path_contract import validate_paths

BASE=Path(__file__).resolve().parent
COURSES=('ELM253','ETY155','MTH147','MTH255')

def plan(course):
    return json.loads(next((BASE/'plans').glob('*-'+course+'-LIFECYCLE1.json')).read_text())

class DifficultyBinding(unittest.TestCase):
    def test_all_four_exact_difficulty_zero_positive_controls(self):
        for course in COURSES:
            value=plan(course)
            self.assertEqual(value['difficulty'],0)
            self.assertTrue(envelope(value))

    def test_each_course_rejects_nonzero_integer_difficulty(self):
        for course in COURSES:
            for replacement in (1,4):
                value=plan(course);value['difficulty']=replacement
                with self.subTest(course=course,difficulty=replacement),self.assertRaisesRegex(ValueError,'difficulty'):
                    envelope(value)

    def test_each_course_rejects_bool_and_float_difficulty(self):
        for course in COURSES:
            for replacement in (False,0.0):
                value=plan(course);value['difficulty']=replacement
                with self.subTest(course=course,difficulty=replacement),self.assertRaises(ValueError):
                    envelope(value)

class ParserPathBinding(unittest.TestCase):
    def parser(self):
        return json.loads((BASE/'plans/CLASSROOM-EIGHT-V7-PARSER1.json').read_text())

    def test_exact_parser_positive_control(self):
        value=self.parser()
        self.assertTrue(validate_paths(value,BASE))
        self.assertTrue(envelope(value))

    def test_parser_rejects_outside_parser_result(self):
        value=self.parser();value['parser_result']=r'C:\outside\forbidden.json'
        with self.assertRaisesRegex(ValueError,'parser result'):
            validate_paths(value,BASE)

    def test_parser_rejects_all_forbidden_course_chain_fields(self):
        mutations={'parser_result':str(BASE/'run-data/other/RESULT.json'),'previous_result':str(BASE/'run-data/other/RESULT.json'),'previous_name':'other','answer_fixture':str(BASE/'fixtures/ELM253.json')}
        for field,replacement in mutations.items():
            value=self.parser();value[field]=replacement
            with self.subTest(field=field),self.assertRaisesRegex(ValueError,'parser result'):
                validate_paths(value,BASE)

if __name__=='__main__':unittest.main(verbosity=2)
