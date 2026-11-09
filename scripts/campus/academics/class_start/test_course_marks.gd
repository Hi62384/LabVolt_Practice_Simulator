extends SceneTree
const Progression = preload("res://scripts/campus/academics/course_progression.gd")
const Attendance = preload("res://scripts/campus/academics/attendance_ledger.gd")
const Adapter = preload("res://scripts/campus/academics/course_progression_adapter.gd")

var checks := 0
var failures := 0
func check(ok: bool, message: String) -> void:
	checks+=1
	if not ok:
		failures+=1
		printerr("FAIL CLASS_MARKS: "+message)
func _initialize() -> void:call_deferred("run")

func row(id: String, kind: String, week: int, score: float, attempt: int, late: bool=false) -> Dictionary:
	return {"id":id,"assessment_id":id,"profile":"synthetic-profile","course_id":"SYNTH","kind":kind,"week":week,"score":score,"course_attempt":attempt,"lesson":false,"late":late,"time":"2026-11-06T12:00:00"}

func run() -> void:
	var requirements := {"lecture":2,"lab":2}
	var weights := {"lecture:1":20.0,"lecture:2":30.0,"lab:1":20.0,"lab:2":30.0}
	var records := {}
	records["a1"]=row("a1","lecture",1,50.0,1)
	records["a2"]=row("a2","lecture",2,50.0,1)
	records["a3"]=row("a3","lab",1,50.0,1,true)
	var running: Dictionary=Progression.summarize(records,"synthetic-profile","SYNTH",requirements,weights)
	check(running.current_attempt.running_mark==50.0,"running mark uses completed slot weights")
	check(is_equal_approx(float(running.current_attempt.earned_to_date),35.0),"earned-to-date includes missing exam weight")
	check(running.final_mark==null and not running.passed,"no final or pass before final lab exam")
	records["a4"]=row("a4","lab",2,50.0,1)
	var complete: Dictionary=Progression.summarize(records,"synthetic-profile","SYNTH",requirements,weights)
	check(complete.final_mark==50.0 and complete.passed and complete.pass_mark==50.0,"exactly 50 percent passes")
	check(complete.completed_attempts[0].exams.has("lecture") and complete.completed_attempts[0].exams.has("lab"),"final lecture and lab slots are exams")
	var baseline: float=complete.final_mark
	records["a3"].late=false
	var without_late: Dictionary=Progression.summarize(records,"synthetic-profile","SYNTH",requirements,weights)
	check(without_late.final_mark==baseline,"late flag does not invent a grade penalty")
	for spec in [["b1","lecture",1],["b2","lecture",2],["b3","lab",1],["b4","lab",2]]:
		records[str(spec[0])]=row(str(spec[0]),str(spec[1]),int(spec[2]),70.0,2)
	var retake: Dictionary=Progression.summarize(records,"synthetic-profile","SYNTH",requirements,weights)
	check(retake.final_mark==70.0 and retake.best_attempt==2,"highest completed retake determines final mark")
	records["repeat"] = row("a4","lab",2,0.0,1)
	var repeated: Dictionary=Progression.summarize(records,"synthetic-profile","SYNTH",requirements,weights)
	check(repeated.final_mark==70.0 and repeated.completed_attempts.size()==2,"replayed assessment ID cannot change result")
	records["practice"]=row("practice","lecture",1,0.0,3)
	records["practice"].lesson=true
	var practice: Dictionary=Progression.summarize(records,"synthetic-profile","SYNTH",requirements,weights)
	check(practice.final_mark==70.0 and practice.completed_attempts.size()==2,"practice excluded from official mark")
	var events := {}
	var unknown: Dictionary=Adapter._attendance(events,"synthetic-profile","ELM253","lecture",1)
	check(unknown.status=="unavailable","empty historical attendance stays unknown")
	var event: Dictionary=Attendance.record_authoritative(events,true,"synthetic-session","synthetic-profile","ELM253","lecture",1,"2026-11-06T12:00:00",["ELM253"])
	check(event.ok and events.size()==1,"attendance event is separate from grade records")
	print("CLASS_MARKS checks=%d failures=%d"%[checks,failures])
	quit(0 if failures==0 else 1)
