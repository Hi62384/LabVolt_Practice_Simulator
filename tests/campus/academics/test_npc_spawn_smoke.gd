extends SceneTree
## Exercise the real campus scene and its shared NPC dependency chain with no
## provider request, using saved identities from the existing deterministic fixture.
const Legacy = preload("res://tests/campus/academics/dossier/legacy_population_fixture.gd")
const Dossier = preload("res://scripts/campus/academics/character_dossier.gd")
const Profiles = preload("res://scripts/campus/academics/class_character_profile.gd")
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		printerr("FAIL: " + message)

func run() -> void:
	create_timer(45.0).timeout.connect(func(): quit(1))
	# Verify the constraint projection compiles and retains its intended behavior.
	var seed: Dictionary = Profiles.teacher("chad")
	var dossier: Dictionary = Dossier.migrate(seed)
	seed.trait_constraints = {"arrogance": [0.8, 1.0]}
	dossier.traits.arrogance = 0.1
	var projected: Dictionary = Dossier.project(seed, dossier)
	check(is_equal_approx(float(projected.traits.arrogance), 0.8), "faculty trait constraints remain authoritative")
	check(is_equal_approx(float(dossier.traits.arrogance), 0.1), "projection does not mutate saved dossier")

	var packed: PackedScene = load("res://scenes/Main.tscn")
	if packed == null:
		check(false, "main scene loads")
		quit(1)
		return
	var game: Node = packed.instantiate()
	root.add_child(game)
	for index in 4: await process_frame
	if not is_instance_valid(game.get("faculty")) or not is_instance_valid(game.get("lecture_classes")):
		check(false, "faculty and classroom systems initialized")
		quit(1)
		return
	game.client_preferences.values.teacher_speech = false
	game.front.entered()
	game.player.set_physics_process(false)
	var faculty: Node = game.faculty
	var classes: Node = game.lecture_classes
	var students: Node = classes.classroom_students
	check(is_instance_valid(faculty.lunch) and faculty.lunch.is_inside_tree(), "cafeteria NPC exists in freeplay")
	for room in ["ac_lab", "dc_lab"]:
		var teacher_root: Node3D = game.school_world.teacher if room == "ac_lab" else game.school_world.dc_instructor
		var instructor: Node3D = teacher_root.get_node_or_null("InstructorModel")
		check(is_instance_valid(instructor) and instructor.is_inside_tree(), "freeplay instructor exists: " + room)

	Legacy.seed(students.population, 24)
	# A real lab start must select persisted students and render them in the scene.
	var room := "ac_lab"
	game.player.global_position = classes.signs[room].desk
	var result: String = classes._start(room, {"kind":"lab","course_id":"ELM253","week":1,"difficulty":1})
	check(result.is_empty(), "start actual lab class: " + result)
	if result.is_empty():
		var activity: Dictionary = classes.classes[room]
		check(not activity.classmates.is_empty(), "class selected persisted NPCs")
		if not activity.classmates.is_empty():
			var member: Dictionary = activity.classmates.values()[0]
			member.arrival = classes._now() - 1.0
			member.arrived = true
			member.position = member.seat
			classes._publish()
			students.render(room, classes.public_classes, 0.2)
			var model: Node3D = students.models.get(str(activity.id) + ":" + str(member.profile.id))
			check(is_instance_valid(model) and model.is_inside_tree(), "class student has a physical scene model")
	game.queue_free()
	await process_frame
	print("NPC_SPAWN_SMOKE " + ("PASS" if failures.is_empty() else "FAIL"))
	quit(0 if failures.is_empty() else 1)
