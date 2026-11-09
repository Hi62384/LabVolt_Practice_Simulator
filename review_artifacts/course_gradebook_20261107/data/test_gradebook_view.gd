extends SceneTree
const View = preload("res://review_artifacts/course_gradebook_20261107/data/gradebook_view.gd")
const Selector = preload("res://review_artifacts/course_gradebook_20261107/data/attempt_selector.gd")
var failures := 0

func _initialize() -> void:
	var tracks := {"lecture": [{"week": 1, "title": "Quiz"}, {"week": 2, "title": "Exam"}], "lab": []}
	var weights := {"lecture": [2.0, 98.0], "lab": []}
	var first := _record("a", "p", "C", "lecture", 1, 90.0)
	var partial := View.build({"a": first}, "p", "C", tracks, weights)
	_check(partial.policy_valid and not partial.complete and partial.final_mark == null, "partial has no final")
	_check(is_equal_approx(partial.earned_final_points, 1.8) and is_equal_approx(partial.current_average, 90.0), "90 at 2 percent")
	_check(partial.rows[0].status == "graded" and partial.rows[1].status == "in_progress", "graded and in progress")
	var zero := _record("b", "p", "C", "lecture", 2, 0.0)
	var full := View.build({"a": first, "b": zero}, "p", "C", tracks, weights)
	_check(full.complete and is_equal_approx(full.final_mark, 1.8) and not full.passed, "official zero and full final")
	var other := _record("x", "other", "C", "lecture", 2, 100.0)
	var isolation := View.build({"a": first, "x": other}, "p", "C", tracks, weights)
	_check(not isolation.complete and isolation.rows[1].score == null, "profile isolation")
	var wrong_course := _record("y", "p", "D", "lecture", 2, 100.0)
	var duplicate := _record("a2", "p", "C", "lecture", 1, 10.0)
	var isolated := View.build({"a": first, "y": wrong_course, "a2": duplicate}, "p", "C", tracks, weights)
	_check(not isolated.complete and isolated.unmatched_records.size() == 1, "course isolation and duplicate slot")
	var pending := {"id": "pending", "profile": "p", "course_id": "C", "kind": "lecture", "week": 2, "pending_assessment_version": 1}
	var awaiting := View.build({}, "p", "C", tracks, weights, {"pending": pending})
	_check(awaiting.rows[1].status == "submitted" and awaiting.rows[0].status == "not_available", "submitted and unavailable")
	var invalid := View.build({"a": first}, "p", "C", tracks, {"lecture": [2.0], "lab": []})
	_check(not invalid.policy_valid and invalid.final_mark == null and invalid.current_average == null, "missing weight invalid")
	var multi_weights := {"lecture": [2.0, 88.0], "lab": [], "assessments": [{"id": "project", "kind": "lecture", "title": "Project", "weight": 10.0}]}
	var project := _record("project", "p", "C", "lecture", 0, 50.0)
	project["gradebook_assessment_id"] = "project"
	var multi := View.build({"a": first, "project": project}, "p", "C", tracks, multi_weights)
	_check(multi.rows.size() == 3 and is_equal_approx(multi.earned_final_points, 6.8), "additional nonweekly assessment")
	var categories := {"lecture": [{"week": 1, "title": "L"}], "lab": [{"week": 1, "title": "B"}]}
	var category_weights := {"lecture": [40.0], "lab": [60.0]}
	var lab := _record("lab", "p", "C", "lab", 1, 50.0)
	var category_result := View.build({"a": first, "lab": lab}, "p", "C", categories, category_weights)
	_check(category_result.complete and is_equal_approx(category_result.final_mark, 66.0), "lecture lab course weights applied once")
	var nan_config := {"lecture": [NAN, 98.0], "lab": []}
	_check(not View.build({}, "p", "C", tracks, nan_config).policy_valid, "nonfinite weight invalid")
	var future := first.duplicate(true)
	future["future_metadata"] = {"version": 3}
	_check(View.build({"a": future}, "p", "C", tracks, weights).rows[0].completed, "future record metadata tolerated")
	var same_week := {"lecture": [{"week": 1, "title": "Main"}], "lab": []}
	var same_config := {"lecture": [60.0], "lab": [], "assessments": [{"id": "quiz", "kind": "lecture", "week": 1, "weight": 40.0}]}
	var main := _record("main", "p", "C", "lecture", 1, 100.0)
	main["gradebook_assessment_id"] = "lecture:1"
	main["course_attempt"] = 1
	var quiz := _record("quiz", "p", "C", "lecture", 1, 50.0)
	quiz["gradebook_assessment_id"] = "quiz"
	quiz["course_attempt"] = 1
	var selected := Selector.select({"main": main, "quiz": quiz}, "p", "C", same_week, same_config)
	_check(selected.complete and is_equal_approx(selected.final_mark, 80.0) and selected.attempt_number == 1, "two same week explicit assessments")
	var retake := main.duplicate(true)
	retake.id = "retake"
	retake.course_attempt = 2
	retake.score = 10.0
	var mixed := Selector.select({"main": main, "quiz": quiz, "retake": retake, "old": first}, "p", "C", same_week, same_config)
	_check(mixed.attempt_number == 2 and mixed.final_mark == null and is_equal_approx(mixed.best_completed_mark, 80.0), "current retake separate from best")
	_check(mixed.ambiguous_legacy_records.size() == 1 and mixed.identity_status == "ambiguous_legacy", "old ambiguous history preserved")
	print("gradebook_view: %d failure(s)" % failures)
	quit(0 if failures == 0 else 1)

func _record(id: String, profile: String, course: String, kind: String, week: int, score: float) -> Dictionary:
	return {"id": id, "assessment_id": id, "profile": profile, "course_id": course, "kind": kind, "week": week, "score": score, "lesson": false}

func _check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
		printerr("FAIL: " + label)
