from copy import deepcopy
import unittest
import admission_readiness_v2 as a

def base(stage):
    predecessor = None
    if stage != "parser":
        prior = "parser" if stage == "solo" else "solo"
        prior_plan = a.load(a.BUNDLE / "plans" / a.PLAN_FILES[prior])
        predecessor = {
            "name": prior_plan["name"], "plan_sha256": a.PLAN_SHA256[prior],
            "source_cache_lock_sha256": a.LOCK_SHA256, "evidence_label": a.LABEL,
            "accepted": True, "Godot_result": "PASS_FOR_THIS_EXACT_CASE_ONLY",
            "source_cache_verified_after": True, "overrun": False,
            "receipt": {"durable": True, "sha256": "a" * 64},
            "cleanup": {"normal_zero_all": True, "owned_job_zero_verified": True,
                        "resource_hold_remains": False},
        }
    return {
        "label": a.LABEL, "plan_sha256": a.PLAN_SHA256[stage],
        "source_cache_lock_sha256": a.LOCK_SHA256, "fresh_grant": True,
        "previous_owned_cleanup_verified": True,
        "total_engine_jobs": 2 if stage == "two_peer" else 1,
        "per_job_process_limit": 1, "predecessor": predecessor,
        "request_context": None if stage == "parser" else {
            "request_id": "request-1", "request_sha256": "b" * 64, "paper_id": 7,
            "assessment_id": "assessment-1", "profile_sha256": "c" * 64,
            "course": "MTH147", "owner_peer": 2, "op": "submit"},
        "privacy": None if stage == "parser" else {
            "complete_scan": True, "eligible": 2, "covered": 2, "private_fields_found": 0},
    }

class CorrectionRegressions(unittest.TestCase):
    def rejects(self, stage, row):
        with self.assertRaises(ValueError):
            a.validate(stage, row)

    def test_exact_frozen_package_and_positive_envelopes(self):
        for stage in a.STAGES:
            self.assertTrue(a.validate(stage, base(stage)))

    def test_fabricated_minimal_predecessor_rejected(self):
        row = base("two_peer")
        row["predecessor"] = {"stage": "solo", "accepted": True,
            "resource_hold_remains": False, "source_cache_lock_sha256": a.LOCK_SHA256,
            "label": a.LABEL}
        self.rejects("two_peer", row)

    def test_malformed_request_fields_and_bool_counts_rejected(self):
        mutations = [
            ("request_context", "request_id", ""),
            ("request_context", "request_sha256", "x"),
            ("request_context", "paper_id", True),
            ("request_context", "assessment_id", False),
            ("request_context", "profile_sha256", "x"),
            ("request_context", "owner_peer", 0),
            ("privacy", "private_fields_found", False),
            ("privacy", "eligible", True),
        ]
        for section, key, value in mutations:
            row = base("solo"); row[section][key] = value
            self.rejects("solo", row)

    def test_parser_and_behavioral_cleanup_schemas_are_distinct(self):
        common = {"evidence_label": a.LABEL, "source_cache_lock_sha256": a.LOCK_SHA256,
            "accepted": True, "Godot_result": "PASS_FOR_THIS_EXACT_CASE_ONLY",
            "source_cache_verified_after": True, "overrun": False}
        parser = dict(common, plan_sha256=a.PLAN_SHA256["parser"], backend={
            "normal_exit": 0, "cleanup": {"stop_verified": True,
                "engine_exit_verified": True, "owned_job_empty_verified": True,
                "resource_hold_remains": False}})
        self.assertTrue(a.validate_result("parser", parser))
        wrong = deepcopy(parser); wrong["backend"].pop("cleanup")
        with self.assertRaises(ValueError): a.validate_result("parser", wrong)
        solo = dict(common, plan_sha256=a.PLAN_SHA256["solo"], cleanup={
            "normal_zero_all": True, "owned_job_zero_verified": True,
            "resource_hold_remains": False})
        self.assertTrue(a.validate_result("solo", solo))

    def test_result_requires_explicit_test_instrumented_label(self):
        result = {"plan_sha256": a.PLAN_SHA256["solo"],
            "source_cache_lock_sha256": a.LOCK_SHA256, "accepted": True,
            "Godot_result": "PASS_FOR_THIS_EXACT_CASE_ONLY",
            "source_cache_verified_after": True, "overrun": False,
            "cleanup": {"normal_zero_all": True, "owned_job_zero_verified": True,
                        "resource_hold_remains": False}}
        with self.assertRaises(ValueError): a.validate_result("solo", result)

if __name__ == "__main__":
    unittest.main(verbosity=2)
