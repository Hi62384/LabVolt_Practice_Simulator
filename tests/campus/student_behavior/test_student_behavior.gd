extends SceneTree
const Behavior = preload("res://scripts/campus/npcs/student_behavior.gd")
const Registry = preload("res://scripts/campus/world/room_registry.gd")
var failures := 0

func check(value: bool, label: String) -> void:
	if not value:
		failures += 1
		printerr("FAIL: " + label)

func _initialize() -> void:
	var registry := Registry.new()
	var behavior := Behavior.new()
	check(behavior.configure(registry), "accepts canonical registry")
	behavior.set_population(10)
	check(behavior.students.size() == 10, "bounded requested population")
	var initial: Array[Vector3] = []
	for student in behavior.students:
		initial.append(student.position)
	for step in 6000:
		behavior.advance(Behavior.TICK_SECONDS)
		for student in behavior.students:
			check(student.position.is_finite(), "finite position")
			check(str(student.state) in ["wander", "to_room", "working", "to_hall"], "known state")
			check(student.path.size() <= 20, "bounded path")
			if str(student.state) == "working":
				check(registry.locate(student.position) == str(student.room_id), "work point inside chosen room")
			if str(student.state) in ["to_room", "to_hall"] and not str(student.room_id).is_empty():
				var room := registry.get_room(str(student.room_id))
				var door := Registry.vector(room.door)
				var has_door := false
				for point in student.path:
					has_door = has_door or point.distance_to(door) < 0.01
				check(has_door, "room route includes authored door")
	var changed := 0
	var states := {}
	for index in behavior.students.size():
		if behavior.students[index].position != initial[index]:
			changed += 1
		states[str(behavior.students[index].state)] = true
	check(changed == behavior.students.size(), "students do not share a frozen timer")
	check(states.size() >= 2, "deterministic students desynchronize across lifecycle states")
	behavior.set_population(100)
	check(behavior.students.size() == 24, "population hard cap")
	var before := behavior.students[0].duplicate(true)
	for invalid in [0.0, -1.0, NAN, INF]:
		behavior.advance(invalid)
	check(behavior.students[0] == before, "invalid time is a no-op")
	print("STUDENT_BEHAVIOR failures=%d" % failures)
	quit(1 if failures else 0)

