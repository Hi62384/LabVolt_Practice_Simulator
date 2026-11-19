extends SceneTree
const Plan=preload("res://scripts/campus/academics/adaptive_lesson.gd")

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var duration:=420.0
	var steps:=["introduction","concept","check","example","practice","review"]
	var progress:=0.0
	for step in steps:
		var window:=Plan.window(progress+.01,duration)
		assert(window.key==step)
		progress=float(window.end)
	assert(is_equal_approx(progress,duration))
	var feedback:={}
	var present: Array[String]=["one","two","three"]
	assert(Plan.pacing_signal(feedback,"unknown","ready",150.0,duration,present)==0.0)
	assert(Plan.pacing_signal(feedback,"one","ready",150.0,duration,present)==0.0)
	assert(Plan.pacing_signal(feedback,"two","clarify",150.0,duration,present)==0.0)
	assert(Plan.pacing_signal(feedback,"three","ready",150.0,duration,present)==0.0)
	assert(Plan.pacing_signal(feedback,"two","ready",150.0,duration,present)>0.0)
	print("ADAPTIVE_LESSON_PACING PASS")
	var game: Node=load("res://scenes/Main.tscn").instantiate()
	root.add_child(game)
	for i in 4:await process_frame
	game.front.entered()
	game.school.start("Freeplay",0)
	var classes: Node=game.lecture_classes
	for room in ["ac_lab","dc_lab"]:
		var course: String="ELM253" if room=="ac_lab" else "ETY155"
		var mount: Node3D=game.school_world.teacher if room=="ac_lab" else game.school_world.dc_instructor
		game.player.global_position=classes.signs[room].desk
		await physics_frame
		assert(classes._start(room,{"kind":"lab","course_id":course,"week":1,"difficulty":0})=="")
		classes.classes[room].ai_teaching=true
		game.faculty._sync_lab_teachers()
		var teacher:=mount.get_node("InstructorModel") as Node3D
		assert(game.faculty.lab_routes.has(room),"No arrival route for "+room)
		var entrance:=teacher.global_position
		for i in 110:game.faculty._step_lab_routes(.1)
		assert(entrance.distance_to(teacher.global_position)>1.0,"No arrival motion for "+room)
		classes.classes.erase(room)
		game.faculty._sync_lab_teachers()
		assert(game.faculty.lab_routes.get(room,{}).get("departing",false),"No departure route for "+room)
		assert(teacher.get_node("ClassInstructorTarget").collision_layer==0)
		for i in 110:game.faculty._step_lab_routes(.1)
		assert(mount.get_node_or_null("InstructorModel")==null)
		print("LAB_INSTRUCTOR_TRAVEL ",room," PASS")
	game.queue_free()
	await process_frame
	print("ADAPTIVE_CLASSROOM PASS")
	quit(0)
