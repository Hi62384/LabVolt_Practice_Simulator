import copy
import importlib.util
import json
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
OWNER = Path(r"C:\Users\User1\Documents\Codex\2026-11-05\task-6\eight_participants_v7")


def load(name):
    spec = importlib.util.spec_from_file_location(name, HERE / (name + ".py"))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


PATHS = load("path_contract")
ADMISSION = load("admission_contract")


def plan(name):
    return json.loads((OWNER / "plans" / name).read_text(encoding="utf-8"))


class PathContractTests(unittest.TestCase):
    def test_all_five_owner_plans_are_positive_controls(self):
        for path in sorted((OWNER / "plans").glob("*.json")):
            self.assertTrue(PATHS.validate_paths(json.loads(path.read_text(encoding="utf-8")), OWNER))

    def test_original_outside_output_and_predecessor_failure_is_rejected(self):
        value = plan("CLASSROOM-EIGHT-V7-ETY155-LIFECYCLE1.json")
        value["output"] = r"C:\outside\result"
        value["previous_result"] = r"C:\outside\prior.json"
        with self.assertRaisesRegex(ValueError, "noncanonical V7 path"):
            PATHS.validate_paths(value, OWNER)

    def test_missing_bound_file_is_rejected(self):
        value = plan("CLASSROOM-EIGHT-V7-ELM253-LIFECYCLE1.json")
        value["bound_files"][str(OWNER / "missing-bound.py")] = "0" * 64
        with self.assertRaisesRegex(ValueError, "outside/missing bound file"):
            PATHS.validate_paths(value, OWNER)

    def test_repeated_suffix_output_is_rejected(self):
        value = plan("CLASSROOM-EIGHT-V7-MTH255-LIFECYCLE1.json")
        value["output"] = str(OWNER / "eight_participants_v7" / "run-data" / value["name"])
        with self.assertRaisesRegex(ValueError, "noncanonical V7 path"):
            PATHS.validate_paths(value, OWNER)

    def test_outside_parser_result_and_grant_are_rejected(self):
        value = plan("CLASSROOM-EIGHT-V7-MTH147-LIFECYCLE1.json")
        for field in ("parser_result", "required_root_grant"):
            changed = copy.deepcopy(value)
            changed[field] = str(Path(r"C:\outside") / Path(value[field]).name)
            with self.assertRaisesRegex(ValueError, "noncanonical V7 path"):
                PATHS.validate_paths(changed, OWNER)


class AdmissionTests(unittest.TestCase):
    def test_all_five_owner_plans_are_positive_controls(self):
        for path in sorted((OWNER / "plans").glob("*.json")):
            ADMISSION.envelope(json.loads(path.read_text(encoding="utf-8")))

    def test_original_mismatched_course_port_name_failure_is_rejected(self):
        value = plan("CLASSROOM-EIGHT-V7-ELM253-LIFECYCLE1.json")
        value["course"] = "MTH255"
        value["port"] = 27099
        with self.assertRaisesRegex(ValueError, "exact course/name/port/week/kind/predecessor tuple"):
            ADMISSION.envelope(value)

    def test_each_course_tuple_field_is_bound(self):
        value = plan("CLASSROOM-EIGHT-V7-MTH147-LIFECYCLE1.json")
        mutations = {"name": "wrong", "port": 27099, "week": 1, "kind": "lab", "difficulty": 1,
                     "previous_name": "CLASSROOM-EIGHT-V7-ELM253-LIFECYCLE1"}
        for field, replacement in mutations.items():
            changed = copy.deepcopy(value)
            changed[field] = replacement
            with self.subTest(field=field), self.assertRaises(ValueError):
                ADMISSION.envelope(changed)


if __name__ == "__main__":
    unittest.main(verbosity=2)
