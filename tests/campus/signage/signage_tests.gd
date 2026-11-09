extends SceneTree
const Signage = preload("res://scripts/campus/presentation/signage/campus_signage.gd")
var failures := 0

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		printerr("FAIL SIGNAGE: " + message)

func _init() -> void:
	check(Signage.room_number({"number":"M103", "title":"DC Lab"}) == "M103", "physical identity is number-only")
	check(Signage.room_hud_identity({"number":"M103", "title":"DC Lab"}) == "M103 · DC Lab", "HUD carries room function")
	check(Signage.room_hud_identity({"room_number":"M201", "name":"ELM253"}) == "M201 · ELM253", "HUD accepts room-slip keys")
	var root := Node3D.new()
	var west := Signage.add_room_number_faces(root, {"number":"M103", "title":"DC Lab"}, Vector3.ZERO, true)
	check(west.size() == 2, "door has deliberate corridor and interior faces")
	check(west[0].text == "M103" and west[1].text == "M103", "neither physical face contains descriptive title")
	check(not west[0].double_sided and not west[1].double_sided, "back faces cannot render mirrored")
	check(is_equal_approx(west[0].rotation.y, PI / 2.0), "west corridor face yaw")
	check(is_equal_approx(west[1].rotation.y, -PI / 2.0), "west interior face yaw")
	root.free()
	var east_root := Node3D.new()
	var east := Signage.add_room_number_faces(east_root, {"number":"M104"}, Vector3.ZERO, false)
	check(is_equal_approx(east[0].rotation.y, -PI / 2.0), "east corridor face yaw")
	check(is_equal_approx(east[1].rotation.y, PI / 2.0), "east interior face yaw")
	check(east[0].position.x < 0.0 and east[1].position.x > 0.0, "faces sit outside their wall surfaces")
	east_root.free()
	print("SIGNAGE TESTS: %d failures" % failures)
	quit(failures)
