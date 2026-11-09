extends SceneTree
## Run later: godot --headless --path . --script res://review_artifacts/campus_entrance_20261107/navigation/entrance_clearance.gd
var failures: Array[String] = []
func check(ok: bool, label: String) -> void:
	if not ok: failures.append(label)

func _initialize() -> void: call_deferred("run")

func clear_path(space: PhysicsDirectSpaceState3D, capsule: CapsuleShape3D, start: Vector3, finish: Vector3) -> bool:
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape=capsule
	query.transform=Transform3D(Basis.IDENTITY,start+Vector3(0,.85,0))
	query.motion=finish-start
	query.collision_mask=1
	return space.cast_motion(query)[0]>.99

func floor_below(space: PhysicsDirectSpaceState3D, point: Vector3) -> bool:
	var ray := PhysicsRayQueryParameters3D.create(point+Vector3(0,.4,0),point-Vector3(0,.6,0),1)
	return not space.intersect_ray(ray).is_empty()

func run() -> void:
	var registry=preload("res://scripts/campus/world/room_registry.gd").new()
	var campus=preload("res://scenes/campus/Campus.tscn").instantiate()
	root.add_child(campus)
	var exterior=preload("res://review_artifacts/campus_entrance_20261107/geometry/exterior_finish.gd").new()
	check(exterior.mount(campus),"exterior candidate failed to mount")
	await physics_frame
	await physics_frame
	var space: PhysicsDirectSpaceState3D=campus.get_world_3d().direct_space_state
	var capsule := CapsuleShape3D.new()
	capsule.radius=.25
	capsule.height=1.7
	var spawn: Vector3=registry.entrance()
	check(spawn.is_equal_approx(Vector3(13,0,-18)),"production spawn and registry entrance differ")
	# The shared facade portal is z=-11.32; edging ends at z=-11.4.
	# Three lanes leave two players ample side-by-side space at the threshold.
	for x in [11.5,13.0,14.5]:
		var start := Vector3(x,spawn.y+.05,spawn.z)
		var inside := Vector3(x,spawn.y+.05,-4)
		check(clear_path(space,capsule,start,inside),"entrance lane blocked at x="+str(x))
		check(clear_path(space,capsule,Vector3(x,.05,-11.5),Vector3(x,.05,-11.1)),"portal threshold blocked at x="+str(x))
		for z in range(int(spawn.z),-3):
			check(floor_below(space,Vector3(x,spawn.y,float(z))),"entrance floor absent at "+str(Vector2(x,z)))
	for room in registry.rooms.values():
		var door: Vector3=registry.vector(room.door)
		var approach: Vector3=registry.vector(room.approach)
		var inside := door+Vector3(-1 if door.x<13 else 1,0,0)
		check(clear_path(space,capsule,approach,inside),"door blocked: "+str(room.id))
		check(floor_below(space,door),"door threshold unsupported: "+str(room.id))
		var route: PackedVector3Array=registry.route("exterior",str(room.id))
		check(route.size()>=5 and route[route.size()-1].is_equal_approx(registry.vector(room.anchor)),"route invalid: "+str(room.id))
	print("ENTRANCE_CLEARANCE failures=",failures)
	campus.queue_free()
	quit(0 if failures.is_empty() else 1)
