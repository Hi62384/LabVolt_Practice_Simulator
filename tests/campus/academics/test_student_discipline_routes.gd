extends SceneTree
## Real room geometry regression: an NPC must get out of their own chair
## without ignoring walls or other occupied chairs, then reach the exact seat.
var failures: Array[String]=[]

func check(ok: bool,message: String) -> void:
	if not ok:failures.append(message);printerr("FAIL: "+message)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	create_timer(60.).timeout.connect(func():quit(1))
	var game: Node=load("res://scenes/Main.tscn").instantiate()
	root.add_child(game)
	for index in 4:await process_frame
	game.front.entered()
	game.player.set_physics_process(false)
	game.client_preferences.values.teacher_speech=false
	var classes: Node=game.lecture_classes
	var students: Node=classes.classroom_students
	var room:="ety155_lecture"
	game.player.global_position=classes.signs[room].desk
	check(classes._start(room,{"kind":"lecture","course_id":"ETY155","week":1,"difficulty":1})=="","start lecture with actual furniture collision")
	var activity: Dictionary=classes.classes[room]
	activity.phase="lesson"
	var now: float=classes._now()
	var seat: Vector3=activity.room.seats[0]
	var person: Dictionary=students.population.profile_for("campus_student_14")
	var member:={"profile":person,"position":seat,"seat":seat,"arrived":true,"seated":true,"walking":false,"standing":false,
		"has_seat":true,"arrival":now,"next":now,"turns":0,"action":"listening"}
	activity.classmates={person.id:member}
	var moved: bool=students.apply_discipline(room,activity,person.id,{"action":"move"},now)
	check(moved,"student can stand out of authored chair for a move")
	if moved:
		check(member.walk.seat_points.size()==2,"only start and reserved destination chairs receive seating clearance")
		for point: Vector3 in member.walk.path:check(game.campus.registry.room_contains(room,point),"move path stays in the classroom")
		for step in 300:
			if not member.has("walk"):break
			students._step_walk(activity,member,now+step*.25,.25)
		check(member.seated and member.position.distance_to(member.seat)<.01,"move reaches the exact chair instead of sitting off to one side")
		check(member.seat.distance_to(seat)>1.,"the selected seat is different")
	var removed: bool=students.apply_discipline(room,activity,person.id,{"action":"remove"},now+80.)
	check(removed,"student can leave from the new seat")
	for step in 300:
		if not member.has("walk"):break
		students._step_walk(activity,member,now+80.+step*.25,.25)
	check(member.get("removed_from_class",false) and not member.walking,"removal finishes at the room entrance")
	check(students.snapshot(activity,now+160.).is_empty(),"departed NPC is no longer rendered or occupying the class")
	print("STUDENT_DISCIPLINE_ROUTES %s"%("PASS" if failures.is_empty() else "FAIL"))
	quit(0 if failures.is_empty() else 1)
