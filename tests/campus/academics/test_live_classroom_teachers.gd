extends SceneTree
## Check real faculty movement and local Piper playback in every lecture room.
const Route = preload("res://scripts/campus/academics/classroom_teacher_route.gd")
const ROOM_COURSES := {
	"elm253_lecture":"ELM253", "ety155_lecture":"ETY155",
	"lecture_north_west":"MTH147", "lecture_north_east":"DGS266",
	"lecture_north_annex":"ELM253",
}

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var game: Node = load("res://scenes/Main.tscn").instantiate()
	root.add_child(game)
	for frame in range(4):
		await process_frame
	game.front.entered()
	var classes: Node = game.lecture_classes
	var faculty: Node = game.faculty
	var exercise := await check_rooms(game,classes,faculty)
	game.queue_free()
	await process_frame
	if exercise:
		print("LIVE_CLASSROOM_TEACHERS PASS")
	quit(0 if exercise else 1)

func check_rooms(game: Node, classes: Node, faculty: Node) -> bool:
	for room in ROOM_COURSES:
		game.campus.request_room(room)
		var center: Vector3 = game.campus.registry.vector(game.campus.registry.get_room(room).center)
		game.player.global_position = center
		game.player.enabled = false
		game.campus.set_viewer_position(center)
		await physics_frame
		await physics_frame
		var failure: String = classes._start(room,{"kind":"lecture","course_id":ROOM_COURSES[room],"week":1,"difficulty":0})
		if not failure.is_empty():
			push_error("%s failed to start: %s" % [room,failure])
			return false
		var activity: Dictionary = classes.classes[room]
		activity.phase = "lesson"
		activity.deadline = classes._now() + classes.LessonSeconds
		classes._publish()
		faculty._sync_lectures()
		var teacher: Node3D = faculty.lecture_models.get(room)
		if not is_instance_valid(teacher) or not Route.clear_step(game,teacher.global_position,teacher.global_position):
			push_error("%s has no teacher on a clear classroom floor" % room)
			return false
		var start: Vector3 = teacher.global_position
		faculty._direct_lectures()
		var saw_playback := false
		var moved := false
		var end := Time.get_ticks_msec()+14000
		while Time.get_ticks_msec() < end and not(saw_playback and moved):
			await process_frame
			var current: Vector3 = teacher.global_position
			if not game.campus.registry.room_contains(room,current) or absf(current.y-start.y)>.02:
				push_error("%s teacher left the classroom floor" % room)
				return false
			moved = moved or current.distance_to(start)>.25
			var voice: Dictionary = faculty.speech_player.active.get(room,{})
			var player := voice.get("player") as AudioStreamPlayer3D
			if is_instance_valid(player) and player.stream is AudioStreamWAV and player.stream.data.size()>20000:
				saw_playback = player.get_parent()==teacher
		if not saw_playback or not moved:
			push_error("%s did not move and play a real voice (motion %s, audio %s)" % [room,moved,saw_playback])
			return false
		classes.classes.erase(room)
		classes._publish()
		faculty._sync_lectures()
		if faculty.speech_player.active.has(room) or faculty.lecture_models.has(room):
			push_error("%s retained teacher or speech after class teardown" % room)
			return false
		print("LIVE_CLASSROOM_TEACHER ",room," PASS")
	return true
