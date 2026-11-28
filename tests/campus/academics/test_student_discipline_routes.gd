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
	preload("res://tests/campus/academics/dossier/legacy_population_fixture.gd").seed(students.population,24)
	var room:="ety155_lecture"
	game.player.global_position=classes.signs[room].desk
	check(classes._start(room,{"kind":"lecture","course_id":"ETY155","week":1,"difficulty":1})=="","start lecture with actual furniture collision")
	var activity: Dictionary=classes.classes[room]
	classes.set_process(false);game.faculty.set_process(false)
	activity.phase="lesson"
	var now: float=classes._now()
	# Replace the random class through the same actual-chair authority used by
	# gameplay, instead of inventing a seated member without a seat claim.
	activity.classmates={};students.seating._process(1.)
	var chair: Node3D=students.seating.chair_at(activity.room.seats[0])
	check(chair!=null,"authored seat has an actual chair")
	if chair==null:quit(1);return
	var seat: Vector3=chair.global_position
	var person: Dictionary=students.population.profile_for("campus_student_14")
	var member:={"profile":person,"position":seat,"seat":seat,"arrived":true,"seated":true,"walking":false,"standing":false,
		"has_seat":true,"arrival":now,"next":now,"turns":0,"action":"listening"}
	activity.classmates={person.id:member}
	check(students.seating.assign(member,str(activity.id)),"student owns the starting chair")
	var moved: bool=students.apply_discipline(room,activity,person.id,{"action":"move"},now)
	check(moved,"student can stand out of authored chair for a move")
	if moved:
		check(member.has("seat_relocation") and member.seat_relocation.origin!=member.seat_relocation.destination,"move reserves a distinct destination through the shared seat authority")
		for point: Vector3 in member.seat_relocation.path:check(game.campus.registry.room_contains(room,point),"move path stays in the classroom")
		member.seat_relocation.starts=0
		for step in 300:
			if not member.has("seat_relocation"):break
			students.seating.step(member,.25)
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
