extends SceneTree

const View = preload("res://scripts/campus/academics/gradebook_view.gd")
const Attempt = preload("res://scripts/campus/academics/attempt_selector.gd")
const Tracks := {"lecture": [{"week": 1, "title": "First lecture"}, {"week": 2, "title": "Second lecture"}],
	"lab": [{"week": 1, "title": "First laboratory"}]}
const Config := {"lecture": [2.0, 38.0], "lab": [30.0], "assessments": [
	{"id": "quiz", "kind": "lecture", "week": 1, "title": "Weekly quiz", "weight": 10.0},
	{"id": "midterm", "kind": "lecture", "title": "Midterm", "weight": 20.0}]}
var failures := 0
var checks := 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var records := {"first": _record("lecture:1", 90.0)}
	var result := View.build(records, "alice", "ELM253", Tracks, Config)
	_check(result.policy_valid and result.rows.size() == 5, "all weekly and additional assessments configured")
	_check(is_equal_approx(result.earned_final_points, 1.8), "90% on 2% earns 1.80 points")
	_check(is_equal_approx(result.current_average, 90.0) and result.completed_weight == 2.0, "running average normalizes graded weight")
	_check(result.final_mark == null and result.rows[1].score == null and result.rows[1].status == "not_started", "pending work leaves final grade undetermined")
	records.other_student = _record("lecture:2", 100.0, "bob")
	records.other_course = _record("lecture:2", 100.0, "alice", "ETY155")
	records.practice = _record("lecture:2", 100.0)
	records.practice.practice = true
	records.open_lab = _record("lecture:2", 100.0)
	records.open_lab.lesson = true
	records.zero = _record("lab:1", 0.0)
	var submitted := _record("quiz", null)
	submitted.pending_assessment_version = 1
	submitted.submitted_at = "2026-01-01T12:00:00"
	var running := _record("midterm", null)
	running.pending_assessment_version = 1
	result = View.build(records, "alice", "ELM253", Tracks, Config, {"quiz": submitted, "midterm": running})
	_check(result.rows[2].status == "zero" and result.completed_weight == 32.0, "official zero counts and other profiles/courses and practice are excluded")
	_check(result.rows[3].status == "submitted" and result.rows[4].status == "in_progress", "distinguishes both pending states")
	_check(is_equal_approx(result.current_average, 5.625), "official zero reduces weighted average")
	records.second = _record("lecture:2", 75.0)
	records.quiz = _record("quiz", 80.0)
	records.midterm = _record("midterm", 95.0)
	result = View.build(records, "alice", "ELM253", Tracks, Config)
	_check(result.complete and is_equal_approx(result.final_mark, 57.3), "weekly quiz and non-weekly midterm contribute to definitive grade")
	_check(result.rows[3].week == 1 and result.rows[4].week == null and result.rows[3].score == 80, "weekly and non-weekly rows retain independent identity")
	var relative := Config.duplicate(true)
	relative.weight_basis = "category"
	relative.category_weights = {"lecture": 70.0, "lab": 30.0}
	relative.lecture = [2.0 / 0.7, 38.0 / 0.7]
	relative.lab = [100.0]
	relative.assessments[0].weight = 10.0 / 0.7
	relative.assessments[1].weight = 20.0 / 0.7
	var converted := View.build(records, "alice", "ELM253", Tracks, relative)
	_check(converted.policy_valid and is_equal_approx(converted.final_mark, result.final_mark), "category shares apply once to weekly work and extras")
	relative.category_weights = {"lecture": 70.0, "lab": 20.0}
	_check(not View.build(records, "alice", "ELM253", Tracks, relative).policy_valid, "invalid category shares detected")
	var missing := View.build(records, "alice", "ELM253", Tracks, {})
	_check(not missing.policy_valid and missing.current_average == null and missing.rows[0].score == 90.0 and missing.rows[0].weight == null, "missing weights preserve available marks")
	var legacy := _record("", 90)
	var historical := View.build({"legacy": legacy, "second_attempt": _record("lecture:1", 100)}, "alice", "ELM253", Tracks, Config)
	_check(historical.rows[0].score == 90 and historical.historical_records.size() == 1, "legacy weekly original is preserved when newer attempts or extras exist")
	var selected := Attempt.select(records, "alice", "ELM253", Tracks, Config)
	_check(selected.attempt_number == 1 and is_equal_approx(selected.final_mark, 57.3), "explicit saved attempt keeps independent marks")
	var unavailable := View.build({"broken": _record("lecture:1", null)}, "alice", "ELM253", Tracks, Config)
	_check(unavailable.rows[0].status == "not_available" and unavailable.current_average == null, "unavailable result is distinct from an official zero")
	print("GRADEBOOK: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _record(id: String, score: Variant, profile := "alice", course_id := "ELM253") -> Dictionary:
	return {"id": "%s/%s/%s" % [profile, course_id, id], "profile": profile, "course_id": course_id,
		"kind": "lab" if id.begins_with("lab:") else "lecture", "week": 1, "score": score,
		"gradebook_assessment_id": id, "course_attempt": 1, "time": "2026-01-01T12:00:00"}

func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)
