extends SceneTree
var failures: Array[String] = []
var checks := 0
func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures.append(message); push_error(message)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var world = preload("res://scripts/campus/world/campus_world.gd").new()
	root.add_child(world); await process_frame
	var geometry: Node3D = world.elevator_geometry
	check(geometry.controls.size() == 6, "two real call controls and four actual-floor controls")
	check(geometry.leaves.size() == 2 and geometry.barriers.size() == 2, "both original landings have doors and collision")
	for floor_id in [0, 1]:
		var barrier: CollisionShape3D = geometry.barriers[floor_id]
		check(barrier.shape.size == Vector3(0.22, 3, 2), "barrier matches original doorway")
		check(absf(barrier.get_parent().position.y - (floor_id * 5 + 1.5)) < 0.01, "door/cabin floor aligned")
	var state = preload("res://scripts/campus/elevator/elevator_state.gd").new()
	geometry.apply_snapshot(state.snapshot(), false); await process_frame; await physics_frame
	check(geometry.barriers[0].disabled and not geometry.barriers[1].disabled, "only current fully open landing admits entry")
	check(absf(geometry.leaves[0][0].position.z - 57.45) < 0.01 and absf(geometry.leaves[0][1].position.z - 60.55) < 0.01, "open leaves fully clear aperture")
	state.request(1, true); state.advance(1.3, false, {}, true)
	geometry.apply_snapshot(state.snapshot(), true); await process_frame; await physics_frame
	check(not geometry.barriers[0].disabled, "closing immediately guards entry")
	await create_timer(0.4).timeout
	var middle_z: float = geometry.leaves[0][0].position.z
	check(middle_z > 57.45 and middle_z < 58.5, "real tween produces intermediate door position")
	state.advance(0.1, true, {}, true); geometry.apply_snapshot(state.snapshot(), true)
	await create_timer(0.9).timeout
	check(absf(geometry.leaves[0][0].position.z - 57.45) < 0.02, "real obstruction reversal returns leaves to pocket")
	check(not geometry.barriers[0].disabled, "barrier remains until host declares full opening")
	state.advance(0.9, false, {}, true); geometry.apply_snapshot(state.snapshot(), false)
	await process_frame; await physics_frame
	check(geometry.barriers[0].disabled, "obstructed opening completion safely releases entrance")
	# Actual engine collision queries, not just named-node checks.
	var space: PhysicsDirectSpaceState3D = world.get_world_3d().direct_space_state
	var roof := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(20, 2, 59), Vector3(20, 4.5, 59), 1))
	check(not roof.is_empty(), "cabin ceiling has no sky gap")
	var rear := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(20, 2, 59), Vector3(25, 2, 59), 1))
	check(not rear.is_empty(), "rear cabin wall is enclosed")
	var aperture := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(15.5, 1, 59), Vector3(17, 1, 59), 1))
	check(aperture.is_empty(), "fully open original hallway aperture stays traversable")
	print("ELEVATOR_GEOMETRY checks=", checks, " failures=", failures.size())
	world.queue_free(); await process_frame
	quit(0 if failures.is_empty() else 1)
