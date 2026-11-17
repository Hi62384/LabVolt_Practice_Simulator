extends SceneTree
const Pending=preload("res://scripts/campus/academics/pending_assessment.gd")

var disk: Dictionary={}
var fail_next:=false
var writes:=0

func _initialize() -> void:call_deferred("run")

func persist(value: Dictionary) -> Error:
	if fail_next:
		fail_next=false
		return ERR_CANT_CREATE
	disk=value.duplicate(true)
	writes+=1
	return OK

func check(condition: bool,message: String) -> bool:
	if condition:return true
	push_error(message)
	quit(1)
	return false

func run() -> void:
	var archive: Dictionary={}
	var enrollment: Dictionary={"id":"class-1-student","assessment_id":"class-1","profile":"student","course_id":"ETY155","kind":"lecture","week":1,"class_authority_role":"host","gradebook_assessment_id":"lecture:1","course_attempt":1}
	fail_next=true
	if not check(Pending.enroll(archive,[enrollment],persist)==ERR_CANT_CREATE and archive.is_empty() and disk.is_empty(),"Failed enrollment mutated official archive"):return
	if not check(Pending.enroll(archive,[enrollment],persist)==OK and archive==disk and archive.student[enrollment.id].has("pending_assessment_version"),"Enrollment retry failed"):return
	var result: Dictionary=enrollment.duplicate(true)
	result.score=84.0
	fail_next=true
	if not check(Pending.settle(archive,result,persist)==ERR_CANT_CREATE and archive==disk and not archive.student[enrollment.id].has("score"),"Failed settlement changed pending credit"):return
	if not check(Pending.settle(archive,result,persist)==OK and archive==disk and float(archive.student[enrollment.id].score)==84.0,"Settlement retry lost official credit"):return
	var before: int=writes
	if not check(Pending.settle(archive,result,persist)==OK and writes==before and archive.student.size()==1,"Duplicate settlement wrote or added credit"):return
	var interrupted: Dictionary=enrollment.duplicate(true)
	interrupted.id="class-2-student";interrupted.assessment_id="class-2"
	if not check(Pending.enroll(archive,[interrupted],persist)==OK,"Interrupted class enrollment failed"):return
	fail_next=true
	if not check(Pending.end_host_session(archive,persist,"class-2")==ERR_CANT_CREATE and archive==disk and not archive.student[interrupted.id].has("score"),"Failed host reconciliation changed pending credit"):return
	if not check(Pending.end_host_session(archive,persist,"class-2")==OK and archive==disk and float(archive.student[interrupted.id].score)==0.0 and archive.student.size()==2,"Host reconciliation retry lost or duplicated credit"):return
	print("PENDING_ASSESSMENT_RETRY PASS")
	quit(0)
