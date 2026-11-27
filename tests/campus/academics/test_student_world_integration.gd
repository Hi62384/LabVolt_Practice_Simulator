extends SceneTree
const Students=preload("res://scripts/campus/academics/classroom_students.gd")
const Population=preload("res://scripts/campus/academics/student_population.gd")
var failures: Array[String]=[]

func check(ok: bool,message: String) -> void:
	if not ok:failures.append(message);printerr("FAIL: "+message)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	create_timer(45.).timeout.connect(func():quit(1))
	var game: Node=load("res://scenes/Main.tscn").instantiate()
	root.add_child(game)
	for index in 4:await process_frame
	game.front.entered()
	game.player.set_physics_process(false)
	var classes: Node=game.lecture_classes
	var students: Node=classes.classroom_students
	var faculty: Node=game.faculty
	var room:="ac_lab"
	game.player.global_position=classes.signs[room].desk
	check(classes._start(room,{"kind":"lab","course_id":"ELM253","week":1,"difficulty":1})=="","start actual lab class")
	var activity: Dictionary=classes.classes[room]
	var now: float=classes._now()
	check(activity.classmates.size()>=1 and activity.classmates.size()<=6,"class capacity remains bounded")
	var other:={"id":"overlap-probe","phase":"arrival","kind":"lab","classmates":{}}
	var no_players: Array[Vector3]=[]
	students.start(other,activity.room,no_players,now)
	check(other.classmates.keys().all(func(id):return not activity.classmates.has(id)),"simultaneous classes use different persistent identities")
	var member: Dictionary=activity.classmates.values()[0]
	var old_id:=str(member.profile.id)
	member.profile=students.population.profile_for("campus_student_14")
	activity.classmates.erase(old_id)
	activity.classmates[member.profile.id]=member
	member.arrival=now-1.
	member.arrived=true
	member.position=member.seat
	member.action="using phone"
	member.next=now+120.
	game.player.global_position=member.position+Vector3(.7,0,0)
	classes._publish()
	students.render(room,classes.public_classes,.2)
	var model: Node3D=students.models.get(activity.id+":"+member.profile.id)
	check(is_instance_valid(model),"new persistent population member renders")
	check(model.get_node("Body/ArmR/StudentPhone").visible,"phone behavior presents an actual held item")
	member.action="taking notes"
	classes._publish()
	students.render(room,classes.public_classes,.2)
	check(not model.get_node("Body/ArmR/StudentPhone").visible and model.get_node("StudentNotebook").visible,"writing swaps visible held/work items")
	var public_member: Dictionary=students.visible_member(room,activity.id,member.profile.id)
	check(public_member.public_profile.id==member.profile.id and not public_member.public_profile.has("biography"),"public voice identity excludes private memory")
	check(public_member.appearance.name==member.profile.appearance.name,"persistent appearance travels in host snapshot")
	activity.phase="lesson"
	member.action="using phone"
	check(students.apply_discipline(room,activity,member.profile.id,{"action":"put_away"},now),"host can execute put-away consequence")
	check(member.action=="listening" and member.items_away_until>now,"discipline changes supported behavior")
	check(students.apply_discipline(room,activity,member.profile.id,{"action":"confiscate"},now),"host can hold the NPC's virtual phone")
	check(member.phone_in_custody and member.item_custody.get("return","")=="class_end","NPC phone custody has a defined return boundary")
	activity.phase="assignment"
	students.begin_assessment(activity,now)
	var due:=float(member.academic_due)
	check(not students.act(room,activity,member,"stand",Vector3.INF,now),"assessment disallows requested movement")
	check(students.act(room,activity,member,"nod",Vector3.INF,now),"assessment preserves harmless expressive behavior")
	check(not students.apply_discipline(room,activity,member.profile.id,{"action":"remove"},now),"assessment work cannot be lost through NPC removal")
	game.school.identities[1]="student-world-probe"
	faculty.open_conversation(room,member.profile.id,activity.id)
	var assessment_before:=JSON.stringify(activity.get("classmate_assessment",{}))
	await faculty._answer_classmate({"peer":1,"room":room,"class":activity.id,"student":member.profile.id,"content":"Can you give me the answer to question one?"})
	check(float(member.academic_due)==due,"speaking does not reset academic deadline")
	check(JSON.stringify(activity.get("classmate_assessment",{}))==assessment_before,"conversation cannot edit the assessment")
	check(faculty.brain.recall(member.profile.id,"student-world-probe").size()==1,"assessment interaction reaches persistent character pipeline")
	member.next=now+300.
	students.step(activity,now+40.,.1,room)
	check(member.get("submitted",false),"pending conversation/presentation does not prevent own assessment submission")
	check(students.records.has_section_key(member.profile.id,"ELM253.last_score"),"NPC learning result persisted")
	print("STUDENT_WORLD_INTEGRATION %s"%("PASS" if failures.is_empty() else "FAIL"))
	quit(0 if failures.is_empty() else 1)
