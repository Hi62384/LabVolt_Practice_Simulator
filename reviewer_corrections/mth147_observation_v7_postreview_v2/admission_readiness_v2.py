"""Reviewer correction proposal for frozen MTH147 v7 admission evidence."""
from pathlib import Path
import hashlib
import json
import re

V7 = Path(r"C:\Users\User1\Documents\Codex\2026-11-05\task-4\mth147_observation_v7")
BUNDLE = V7 / "review_bundle"
PROJECT = BUNDLE / "project"
MAIN = Path(r"C:\Users\User1\Documents\GodotProjects\LabVolt_Practice_Simulator\scripts\school_session.gd")
LABEL = "TEST-INSTRUMENTED HOST"
STAGES = ("parser", "solo", "two_peer")
PLAN_FILES = {
    "parser": "MTH147-TEST-INSTRUMENTED-HOST-PARSER.json",
    "solo": "MTH147-TEST-INSTRUMENTED-HOST-SOLO.json",
    "two_peer": "MTH147-TEST-INSTRUMENTED-HOST-TWOPEER.json",
}
PLAN_SHA256 = {
    "parser": "9cbeaf2785eeab5fefb4355d1989bb742d9110a2885d75c8234bf9272e18262a",
    "solo": "f16e5a1d640aa0aeafa45ac559c09873d7914ab63097da9b250bce08b6edd4f6",
    "two_peer": "c684ca156b63b4e5854c4d21af765b2c8ab5a428e5858352e9faef3dfec593c8",
}
MAIN_SHA256 = "143d5d04435e60b21cfc433d5cb471bfbdfbacb94947af9ff7c0c65854fa0843"
LOCK_SHA256 = "d6d512d1496890679c1c918222f2a86067ac2bc0d3391cc797493f0d36a33a13"
FIXTURE_SHA256 = "078323eeaaefb65692208e304b0ba8737c8eeb2ed5cf486277b45aa6ddd996ac"
CALLER_SHA256 = "f418e50897d44083702e0e151c0b53bfa45f96999a777cffc4daf132dade7699"
HEX64 = re.compile(r"^[0-9a-f]{64}$")

def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()

def load(path):
    return json.loads(Path(path).read_text(encoding="utf-8-sig"))

def require(ok, message):
    if not ok:
        raise ValueError(message)

def exact_int(value):
    return type(value) is int

def exact_bool(value):
    return type(value) is bool

def nonempty_text(value, maximum=256):
    return type(value) is str and 0 < len(value) <= maximum

def digest(value):
    return type(value) is str and HEX64.fullmatch(value) is not None

def inside(path, root):
    path, root = Path(path).resolve(), Path(root).resolve()
    return path == root or path.is_relative_to(root)

def verify_frozen_package(stage):
    require(stage in STAGES, "unknown stage")
    plan_path = BUNDLE / "plans" / PLAN_FILES[stage]
    require(sha(plan_path) == PLAN_SHA256[stage], "plan drift")
    require(sha(BUNDLE / "SOURCE-CACHE-LOCK.json") == LOCK_SHA256, "lock drift")
    require(sha(V7 / "mth147_fixture.gd") == FIXTURE_SHA256, "fixture drift")
    require(sha(V7 / "mth147_case.py") == CALLER_SHA256, "caller drift")
    require(sha(MAIN) == MAIN_SHA256, "Main preimage drift")
    plan = load(plan_path)
    require(Path(plan["project"]).resolve() == PROJECT.resolve(), "project path escaped")
    require(inside(plan["output"], BUNDLE / "run-data"), "output path escaped")
    require(inside(plan["required_root_grant"], BUNDLE / "UNISSUED-GRANTS"), "grant path escaped")
    require(Path(plan["source_cache_lock"]).resolve() == (BUNDLE / "SOURCE-CACHE-LOCK.json").resolve(), "wrong lock path")
    require(Path(plan["runner"]).resolve() == (BUNDLE / "run_j.py").resolve(), "wrong runner path")
    require(sha(plan["runner"]) == plan["runner_sha256"], "runner drift")
    require(sha(plan["engine"]) == plan["engine_sha256"], "engine drift")
    require(Path(plan["engine"]).stat().st_size == plan["engine_bytes"], "engine size drift")
    require(sha(plan["python"]) == plan["python_sha256"], "Python drift")
    for path, expected in plan["bound_files"].items():
        require(inside(path, BUNDLE), "bound helper escaped package")
        require(sha(path) == expected, "bound helper drift: " + path)
    lock = load(BUNDLE / "SOURCE-CACHE-LOCK.json")
    actual = {p.relative_to(PROJECT).as_posix() for p in PROJECT.rglob("*") if p.is_file()}
    require(actual == set(lock["files"]), "project inventory drift")
    for relative, row in lock["files"].items():
        target = PROJECT / relative
        require(inside(target, PROJECT), "locked path escaped project")
        require(sha(target) == row["sha256"], "locked file drift: " + relative)
    output = Path(plan["output"])
    require(not output.exists(), "output reuse rejected")
    require(not (output / "RESULT.json").exists(), "result reuse rejected")
    require(not Path(plan["required_root_grant"]).exists(), "proposal must remain ungranted")
    return plan

def validate_predecessor(stage, receipt):
    predecessor = {"parser": None, "solo": "parser", "two_peer": "solo"}[stage]
    if predecessor is None:
        require(receipt is None, "parser must not consume a predecessor")
        return
    require(type(receipt) is dict, "exact predecessor receipt required")
    required_plan = PLAN_SHA256[predecessor]
    require(receipt.get("name") == load(BUNDLE / "plans" / PLAN_FILES[predecessor])["name"], "wrong predecessor name")
    require(receipt.get("plan_sha256") == required_plan, "wrong predecessor plan")
    require(receipt.get("source_cache_lock_sha256") == LOCK_SHA256, "wrong predecessor lock")
    require(receipt.get("evidence_label") == LABEL, "wrong predecessor evidence label")
    require(receipt.get("accepted") is True, "predecessor not accepted")
    require(receipt.get("Godot_result") == "PASS_FOR_THIS_EXACT_CASE_ONLY", "predecessor case did not pass")
    require(receipt.get("source_cache_verified_after") is True, "predecessor source/cache after-proof missing")
    require(receipt.get("overrun") is False, "predecessor overran")
    publication = receipt.get("receipt")
    require(type(publication) is dict and publication.get("durable") is True, "predecessor receipt not durable")
    require(digest(publication.get("sha256")), "predecessor receipt hash missing")
    cleanup = receipt.get("cleanup")
    require(type(cleanup) is dict, "predecessor cleanup missing")
    require(cleanup.get("normal_zero_all") is True, "predecessor normal-zero missing")
    require(cleanup.get("owned_job_zero_verified") is True, "predecessor Job0 missing")
    require(cleanup.get("resource_hold_remains") is False, "predecessor resource hold remains")

def validate_request_and_privacy(stage, readiness):
    if stage == "parser":
        require(readiness.get("request_context") is None, "parser request context forbidden")
        require(readiness.get("privacy") is None, "parser privacy evidence forbidden")
        return
    context = readiness.get("request_context")
    require(type(context) is dict, "request context required")
    require(nonempty_text(context.get("request_id")), "request ID required")
    require(digest(context.get("request_sha256")), "request digest malformed")
    require(exact_int(context.get("paper_id")) and context["paper_id"] > 0, "typed positive paper ID required")
    require(nonempty_text(context.get("assessment_id")), "assessment ID required")
    require(digest(context.get("profile_sha256")), "profile digest malformed")
    require(context.get("course") == "MTH147" and context.get("op") == "submit", "wrong request context")
    require(exact_int(context.get("owner_peer")) and context["owner_peer"] > 0, "typed positive owner peer required")
    privacy = readiness.get("privacy")
    require(type(privacy) is dict and privacy.get("complete_scan") is True, "complete privacy scan required")
    for key in ("eligible", "covered", "private_fields_found"):
        require(exact_int(privacy.get(key)) and privacy[key] >= 0, "typed privacy count required: " + key)
    require(privacy["eligible"] > 0 and privacy["covered"] == privacy["eligible"], "incomplete privacy coverage")
    require(privacy["private_fields_found"] == 0, "private data observed")

def validate_result(stage, result):
    require(type(result) is dict, "result evidence required")
    require(result.get("evidence_label") == LABEL, "result evidence label missing")
    require(result.get("plan_sha256") == PLAN_SHA256[stage], "result plan mismatch")
    require(result.get("source_cache_lock_sha256") == LOCK_SHA256, "result lock mismatch")
    require(result.get("accepted") is True and result.get("Godot_result") == "PASS_FOR_THIS_EXACT_CASE_ONLY", "result not accepted")
    require(result.get("source_cache_verified_after") is True and result.get("overrun") is False, "result final checks failed")
    if stage == "parser":
        backend = result.get("backend")
        require(type(backend) is dict and backend.get("normal_exit") == 0, "parser normal-zero missing")
        cleanup = backend.get("cleanup")
        require(type(cleanup) is dict, "parser backend cleanup missing")
        require(cleanup.get("stop_verified") is True, "parser stop proof missing")
        require(cleanup.get("engine_exit_verified") is True, "parser exit proof missing")
        require(cleanup.get("owned_job_empty_verified") is True, "parser Job0 proof missing")
        require(cleanup.get("resource_hold_remains") is False, "parser resource hold remains")
    else:
        cleanup = result.get("cleanup")
        require(type(cleanup) is dict, "behavioral cleanup missing")
        require(cleanup.get("normal_zero_all") is True, "normal-zero missing")
        require(cleanup.get("owned_job_zero_verified") is True, "Job0 missing")
        require(cleanup.get("resource_hold_remains") is False, "resource hold remains")
    return True

def validate(stage, readiness):
    plan = verify_frozen_package(stage)
    require(readiness.get("label") == LABEL, "wrong admission label")
    require(readiness.get("plan_sha256") == PLAN_SHA256[stage], "wrong exact plan")
    require(readiness.get("source_cache_lock_sha256") == LOCK_SHA256, "wrong exact lock")
    require(readiness.get("fresh_grant") is True, "fresh exact grant required")
    require(readiness.get("previous_owned_cleanup_verified") is True, "prior cleanup gate required")
    require(readiness.get("total_engine_jobs") == plan["total_engine_jobs"], "wrong Job envelope")
    require(readiness.get("per_job_process_limit") == 1, "one process per Job required")
    validate_predecessor(stage, readiness.get("predecessor"))
    validate_request_and_privacy(stage, readiness)
    return True

