extends RefCounted
## Nonblocking modular corridor finish. Apply after campus shell and stairs exist.
## All placements derive from the room registry; no room identity is hard-coded.

const HallwayGeometry = preload("res://scripts/campus/presentation/navigation_safety/hallway_geometry.gd")

const UPPER := "e3e9e6"
const LOWER := "859aa5"
const TRIM := "486879"
const FLOOR_A := "aeb8b9"
const FLOOR_B := "a4afb1"
const CEILING := "edf0ed"
const FRAME := "294e68"

static func apply(world: Node3D) -> void:
	# Structural walls, collisions, and shared materials retain their exact state.
	var wall_runs: Array[Dictionary] = []
	for room in world.registry.rooms.values():
		var center: Vector3 = world.registry.vector(room.center)
		var size: Vector3 = world.registry.vector(room.size)
		var x: float = 10.0 if center.x < 13.0 else 16.0
		var face_x: float = x + (0.09 if x == 10.0 else -0.09)
		var half: float = float(room.door_width) * 0.5
		var z0: float = center.z - size.z * 0.5
		var z1: float = center.z + size.z * 0.5
		var door_z: float = float(room.door[2])
		_add_wall_run(world, wall_runs, face_x, center.y, z0, door_z - half)
		_add_wall_run(world, wall_runs, face_x, center.y, door_z + half, z1)
		_add_frame(world, face_x, center.y, door_z, half)
	# Gap closures exist where rooms do not supply their own wall.
	for closure in HallwayGeometry.edge_closures():
		var x: float = float(closure.position.x)
		var face_x: float = x + (0.09 if x == 10.0 else -0.09)
		_add_wall_run(world, wall_runs, face_x, float(closure.floor) * 5.0, float(closure.z_min), float(closure.z_max))
	_add_floor_tiles(world, 0, -11.32, 68.0)
	_add_floor_tiles(world, 1, -4.0, 50.0)
	_add_floor_tiles(world, 1, 50.0, 68.0)
	_add_ceiling_panels(world, 0, -4.0, 50.0)
	_add_ceiling_panels(world, 1, -4.0, 50.0)
	_add_stair_finish(world)

static func _add_wall_run(world: Node3D, runs: Array[Dictionary], x: float, y: float, z0: float, z1: float) -> void:
	if z1 - z0 < 0.05: return
	var length: float = z1 - z0
	var z: float = (z0 + z1) * 0.5
	# Mesh only: structural wall supplies collision. Hall-facing offset prevents z fight.
	world.box(world, Vector3(x, y + 0.77, z), Vector3(0.018, 1.54, length), LOWER, false)
	world.box(world, Vector3(x, y + 2.79, z), Vector3(0.018, 2.42, length), UPPER, false)
	world.box(world, Vector3(x + (0.018 if x < 13.0 else -0.018), y + 1.55, z), Vector3(0.03, 0.045, length), TRIM, false)
	world.box(world, Vector3(x + (0.02 if x < 13.0 else -0.02), y + 0.10, z), Vector3(0.045, 0.20, length), TRIM, false)
	runs.append({"x":x,"y":y,"z_min":z0,"z_max":z1})

static func _add_frame(world: Node3D, x: float, y: float, z: float, half: float) -> void:
	var outward: float = 0.035 if x < 13.0 else -0.035
	for side in [-1.0, 1.0]:
		world.box(world, Vector3(x + outward, y + 1.55, z + side * (half + 0.055)), Vector3(0.14, 3.10, 0.11), FRAME, false)
	world.box(world, Vector3(x + outward, y + 3.08, z), Vector3(0.14, 0.12, 2.0 * half + 0.22), FRAME, false)

static func _add_floor_tiles(world: Node3D, floor: int, z0: float, z1: float) -> void:
	var transforms_a: Array[Transform3D] = []
	var transforms_b: Array[Transform3D] = []
	var rows: int = int(ceil((z1 - z0) / 1.0))
	for row in range(rows):
		var z: float = z0 + row + 0.5
		if z > z1: continue
		for column in range(6):
			var x: float = 10.5 + column
			# The ramp remains entirely free of flat floor overlays.
			if z >= 50.0 and z <= 62.0 and x < 13.0: continue
			var transform := Transform3D(Basis.IDENTITY.scaled(Vector3(0.982, 0.012, 0.982)), Vector3(x, floor * 5.0 + 0.011, z))
			if (row + column) % 2 == 0: transforms_a.append(transform)
			else: transforms_b.append(transform)
	_add_instances(world, transforms_a, FLOOR_A, 72.0)
	_add_instances(world, transforms_b, FLOOR_B, 72.0)

static func _add_ceiling_panels(world: Node3D, floor: int, z0: float, z1: float) -> void:
	var panels: Array[Transform3D] = []
	var beams: Array[Transform3D] = []
	for row in range(int((z1 - z0) / 2.0)):
		var z: float = z0 + row * 2.0 + 1.0
		for column in range(3):
			panels.append(Transform3D(Basis.IDENTITY.scaled(Vector3(1.95, 0.025, 1.95)), Vector3(11.0 + column * 2.0, floor * 5.0 + 4.025, z)))
		beams.append(Transform3D(Basis.IDENTITY.scaled(Vector3(6.0, 0.035, 0.045)), Vector3(13.0, floor * 5.0 + 3.99, z0 + row * 2.0)))
	_add_instances(world, panels, CEILING, 72.0)
	_add_instances(world, beams, TRIM, 72.0)

static func _add_stair_finish(world: Node3D) -> void:
	# Existing convex ramp collision and tread geometry are untouched.
	for i in range(30):
		var top: float = (i + 1.0) * 5.0 / 30.0
		world.box(world, Vector3(11.5, top + 0.009, 50.0 + (i + 0.5) * 0.4), Vector3(2.96, 0.015, 0.375), FLOOR_A if i % 2 == 0 else FLOOR_B, false)
	for x in [10.13, 12.87]:
		for index in range(7):
			var z: float = 50.0 + index * 2.0
			var y: float = 0.75 + index * (5.0 / 6.0)
			world.box(world, Vector3(x, y, z), Vector3(0.055, 1.45, 0.055), FRAME, false)

static func _add_instances(world: Node3D, transforms: Array[Transform3D], color: String, range_end: float) -> void:
	if transforms.is_empty(): return
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = world.box_mesh
	multimesh.instance_count = transforms.size()
	for i in range(transforms.size()): multimesh.set_instance_transform(i, transforms[i])
	var node := MultiMeshInstance3D.new()
	node.multimesh = multimesh
	node.material_override = world.material(color)
	node.visibility_range_end = range_end
	node.visibility_range_end_margin = 8.0
	world.add_child(node)





