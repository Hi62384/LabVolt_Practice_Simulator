extends SceneTree
const Crowd = preload("res://scripts/campus/npcs/local_crowd.gd")
var failures := 0
func check(value: bool, label: String) -> void:
	if not value:
		failures += 1
		printerr("FAIL: " + label)
func _initialize() -> void:
	var crowd := Crowd.new()
	crowd.allow_headless = true
	root.add_child(crowd)
	crowd.set_process(false)
	crowd._meshes = [ArrayMesh.new(), ArrayMesh.new()]
	crowd.set_context("hall_f0", Vector3(13, 0, 10))
	crowd.set_density("Low")
	for frame in 20:
		crowd.advance(0.1)
	check(crowd._pool.size() == 4, "low density pool")
	var identity := crowd._behavior.students[0].id
	var continuity_position: Vector3 = crowd._behavior.students[0].position
	crowd.set_context("ac_lab", Vector3(9, 0, 3))
	crowd.advance(0.1)
	check(crowd._behavior.students[0].id == identity, "zone crossing preserves student identity")
	check(crowd._behavior.students[0].position.distance_to(continuity_position) < 1.0, "zone crossing preserves motion continuity")
	var item: Dictionary = crowd._pool[0]
	item.node.position = Vector3(37, 0, 0)
	crowd._viewer = Vector3.ZERO
	crowd._update_visual_visibility(item, 0, 37.0, 0.1)
	check(bool(crowd._visibility[0].inside), "enters inside near threshold")
	crowd._update_visual_visibility(item, 0, 41.0, 0.1)
	check(bool(crowd._visibility[0].inside), "hysteresis retains visibility in boundary band")
	crowd._update_visual_visibility(item, 0, 45.0, 0.1)
	check(not bool(crowd._visibility[0].inside), "exits beyond outer threshold")
	check(float(crowd._visibility[0].alpha) > 0.0, "exit fades instead of binary hiding")
	check(crowd.get_stats().network_messages == 0, "local ambience sends no network traffic")
	crowd.free()
	print("STUDENT_VISIBILITY failures=%d" % failures)
	quit(1 if failures else 0)

