extends SceneTree
const Progression=preload("res://scripts/campus/academics/course_progression.gd")
const Adapter=preload("res://scripts/campus/academics/course_progression_adapter.gd")
const Attendance=preload("res://scripts/campus/academics/attendance_ledger.gd")
var failures := 0
class CourseStub:
	extends RefCounted
	func catalog() -> Array:return [{"id":"TEST","title":"Circuits","subject":"Electrical"},{"id":"MTHX","title":"Math"}]
	func weeks(course: String,kind: String) -> Array:
		var count := 2 if course=="TEST" else (2 if kind=="lecture" else 0);var rows: Array=[]
		for i in count:rows.append({"week":i+1,"title":"W%d"%(i+1),"is_exam":i==count-1,"assessment_type":"exam" if i==count-1 else "assignment","grade_weight":50.0})
		return rows
func check(value: bool,message: String) -> void:
	if not value:failures+=1;push_error(message)
func record(id: String,course: String,kind: String,week: int,score: float,time: String,extra: Dictionary={}) -> Dictionary:
	var value := {"id":id,"profile":"student","course_id":course,"kind":kind,"week":week,"score":score,"time":time,"is_exam":week==2}
	value.merge(extra,true);return value
func completed(prefix: String,base_day: int,scores: Array) -> Dictionary:
	return {prefix+"l1":record(prefix+"l1","TEST","lecture",1,scores[0],"2026-01-%02d"%base_day),prefix+"l2":record(prefix+"l2","TEST","lecture",2,scores[1],"2026-01-%02d"%(base_day+1)),prefix+"b1":record(prefix+"b1","TEST","lab",1,scores[2],"2026-01-%02d"%(base_day+2)),prefix+"b2":record(prefix+"b2","TEST","lab",2,scores[3],"2026-01-%02d"%(base_day+3))}
func _initialize() -> void:
	var requirements := {"lecture":2,"lab":2};var weights := {"lecture:1":10.0,"lecture:2":20.0,"lab:1":50.0,"lab:2":20.0}
	var mixed := completed("a",1,[100.0,50.0,20.0,100.0]);var result := Progression.summarize(mixed,"student","TEST",requirements,weights)
	check(result.completed_attempts.size()==1 and is_equal_approx(result.final_mark,50.0) and result.passed,"mixed lecture/lab completes at exact passing boundary")
	check(result.completed_attempts[0].exams.size()==2,"last lecture and lab records are retained as separate exams")
	var partial := mixed.duplicate(true);partial.erase("ab2");result=Progression.summarize(partial,"student","TEST",requirements,weights)
	check(result.final_mark==null and result.current_attempt.running_mark!=null,"incomplete course has running mark but no final")
	check(is_equal_approx(result.current_attempt.earned_to_date,30.0),"earned-to-date uses full denominator")
	var retries := completed("low",1,[40.0,40.0,40.0,40.0]);retries.merge(completed("high",10,[80.0,80.0,80.0,80.0]));retries.merge(completed("equal",20,[80.0,80.0,80.0,80.0]))
	result=Progression.summarize(retries,"student","TEST",requirements,weights)
	check(result.completed_attempts.size()==3 and result.final_mark==80.0 and result.best_attempt==2,"lower, higher and equal retakes retain first highest final")
	retries["practice"]=record("practice","TEST","lecture",1,100.0,"2026-02-01",{"lesson":true,"linked_practice":true})
	retries["other"]=record("other","OTHER","lecture",1,100.0,"2026-02-02")
	check(Progression.summarize(retries,"student","TEST",requirements,weights).completed_attempts.size()==3,"practice and other courses are isolated")
	var invalid := weights.duplicate();invalid["lab:2"]=-2
	result=Progression.summarize(mixed,"student","TEST",requirements,invalid)
	check(not result.weight_policy_valid and result.final_mark==null,"invalid weights cannot produce a final mark")
	var malformed := weights.duplicate();malformed["lab:2"]="20"
	check(not Progression.summarize(mixed,"student","TEST",requirements,malformed).weight_policy_valid,"malformed weight rejected")
	var excessive := weights.duplicate();excessive["lab:2"]=120.0
	check(not Progression.summarize(mixed,"student","TEST",requirements,excessive).weight_policy_valid,"over-total policy rejected")
	var interleaved := {}
	for item in [["a1","lecture",1,10.0,1],["b1","lecture",1,90.0,2],["a2","lecture",2,10.0,3],["b2","lecture",2,90.0,4],["a3","lab",1,10.0,5],["b3","lab",1,90.0,6],["a4","lab",2,10.0,7],["b4","lab",2,90.0,8]]:
		interleaved[item[0]]=record(item[0],"TEST",item[1],item[2],item[3],"2026-03-%02d"%item[4])
	interleaved["duplicate_delivery"]=record("duplicate_delivery","TEST","lecture",1,100.0,"2026-03-09",{"assessment_id":"a1"})
	interleaved["unknown"]=record("unknown","TEST","lab",9,100.0,"2026-03-10")
	result=Progression.summarize(interleaved,"student","TEST",requirements,weights)
	check(result.completed_attempts.size()==2 and result.completed_attempts[0].final_mark==10.0 and result.completed_attempts[1].final_mark==90.0,"interleaved attempts partition without duplicate delivery or unknown week")
	var out_of_order := {"late":record("late","TEST","lecture",1,80.0,"2026-04-02"),"early":record("early","TEST","lecture",1,20.0,"2026-04-01")}
	result=Progression.summarize(out_of_order,"student","TEST",{"lecture":2,"lab":0},{"lecture:1":50.0,"lecture:2":50.0})
	check(result.open_attempts.size()==2 and result.open_attempts[0].records["lecture:1"].score==20.0,"stored timestamps, not dictionary order, drive legacy partition")
	var bounded := {"x":record("x","MTHX","lecture",1,-20.0,"2026-05-01"),"y":record("y","MTHX","lecture",2,140.0,"2026-05-02")}
	result=Progression.summarize(bounded,"student","MTHX",{"lecture":2,"lab":0},{"lecture:1":50.0,"lecture:2":50.0})
	check(result.final_mark==50.0 and result.passed and result.completed_attempts[0].exams.size()==1,"scores clamp to 0..100 and lecture-only final week is one exam")
	var prior := completed("prior",1,[80.0,80.0,80.0,80.0]);prior["new"]=record("new","TEST","lecture",1,10.0,"2026-06-01")
	result=Progression.summarize(prior,"student","TEST",requirements,weights)
	check(result.final_mark==80.0 and result.current_attempt.running_mark==10.0,"best completed final remains separate from current retake")
	var events := {"attendance":{"profile":"student","course_id":"TEST","kind":"lecture","week":1,"attended":true,"time":"2026-07-01T10:00:00"}}
	var menu := Adapter.menu_catalog(mixed,"student",CourseStub.new(),events)
	check(menu.schema=="academic-menu.v1" and menu.groups.Electrical==["TEST"] and menu.groups.Mathematics==["MTHX"],"menu query groups exact course IDs by subject")
	check(menu.recent_attendance.size()==1 and menu.courses[0].tracks.lecture[0].attendance=="attended" and menu.courses[0].tracks.lecture[1].attendance=="unavailable","recent attendance uses explicit events and does not infer absence")
	check(menu.courses[0].tracks.lab[1].is_exam and menu.courses[1].tracks.lab.is_empty(),"menu query separates dual-track exams and lecture-only courses")
	check(menu.courses[0].tracks.lecture[0].marks.size()==1 and menu.courses[0].tracks.lecture[0].marks[0].score==100.0,"read-only course browser receives individual immutable week marks without flattening")
	var ledger := {};var attended := Attendance.record_authoritative(ledger,true,"class-7","student","TEST","lecture",1,"2026-07-01T10:00:00",["TEST"])
	var replay := Attendance.record_authoritative(ledger,true,"class-7","student","TEST","lecture",1,"2026-07-01T10:01:00",["TEST"])
	check(attended.created and not replay.created and ledger.size()==1,"same authoritative class join records attendance exactly once")
	check(not Attendance.record_authoritative(ledger,false,"class-8","student","TEST","lecture",1,"2026-07-02T10:00:00",["TEST"]).ok,"client cannot author attendance")
	check(Attendance.private_for_profile(ledger,"other").is_empty(),"attendance query preserves profile privacy")
	print("COURSE_PROGRESSION_RESULT failures=%d"%failures);quit(0 if failures==0 else 1)
