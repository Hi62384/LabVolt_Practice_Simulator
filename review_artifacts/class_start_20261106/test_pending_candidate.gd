extends SceneTree
const Pending = preload("res://review_artifacts/class_start_20261106/pending_assessment_candidate.gd")
var disk := {}
var fail_write := false
var failures := 0
func persist(value: Dictionary) -> Error:
	if fail_write:return ERR_CANT_CREATE
	disk=value.duplicate(true)
	return OK
func check(ok: bool) -> void:
	if not ok:failures+=1;printerr("FAIL CLASS_PENDING")
func _initialize() -> void:
	var archive := {}
	var record := {"id":"assessment:A:P","assessment_id":"A","profile":"P","course_id":"ELM253","kind":"lecture","week":1,"lesson":false,"title":"Synthetic","time":"2026-11-06T12:00:00"}
	var before_issue: Array[Dictionary]=[record]
	fail_write=true
	check(Pending.enroll(archive,before_issue,persist)==ERR_CANT_CREATE and archive.is_empty() and disk.is_empty())
	fail_write=false
	check(Pending.enroll(archive,before_issue,persist)==OK)
	var pre_issue_restart: Dictionary=disk.duplicate(true)
	check(Pending.abandoned(pre_issue_restart,"P").size()==1)
	check(Pending.settle(pre_issue_restart,Pending.abandoned(pre_issue_restart,"P")[0],persist)==OK)
	check(Pending.enroll(pre_issue_restart,before_issue,persist)==OK and pre_issue_restart.P[record.id].score==0.0)
	archive.clear();disk.clear()
	fail_write=true
	check(Pending.prepare(archive,record,persist)==ERR_CANT_CREATE and archive.is_empty() and disk.is_empty())
	fail_write=false
	check(Pending.prepare(archive,record,persist)==OK and not archive.P[record.id].has("score"))
	var restarted: Dictionary=disk.duplicate(true)
	var abandoned: Array[Dictionary]=Pending.abandoned(restarted,"P")
	check(abandoned.size()==1 and abandoned[0].score==0.0)
	fail_write=true
	check(Pending.settle(restarted,abandoned[0],persist)==ERR_CANT_CREATE and restarted.P[record.id].has("pending_assessment_version"))
	fail_write=false
	check(Pending.settle(restarted,abandoned[0],persist)==OK)
	check(Pending.abandoned(disk,"P").is_empty())
	var successful := record.duplicate(true);successful.score=90.0
	check(Pending.settle(restarted,successful,persist)==OK and restarted.P[record.id].score==0.0)
	var completed := record.duplicate(true);completed.id="assessment:B:P";completed.assessment_id="B";completed.score=80.0
	check(Pending.settle(restarted,completed,persist)==OK)
	var replay := record.duplicate(true);replay.score=0.0
	check(Pending.settle(restarted,replay,persist)==OK and restarted.P[completed.id].score==80.0)
	print("CLASS_PENDING failures=%d"%failures)
	quit(0 if failures==0 else 1)
