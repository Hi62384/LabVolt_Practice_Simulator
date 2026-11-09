extends RefCounted
## Nonblocking modular corridor finish. Apply after campus shell and stairs exist.
## All placements derive from the room registry; no room identity is hard-coded.

const HallwayGeometry = preload("res://scripts/campus/presentation/navigation_safety/hallway_geometry.gd")

const Fixtures = preload("res://scripts/campus/presentation/fixture_light.gd")
const UPPER := "bdc4cd"
const LOWER := "4e697e"
const TRIM := "314757"
const FLOOR_A := "8492a0"
const FLOOR_B := "7e8b9b"
const CEILING := "c6c8cc"
const FRAME := "253f50"

static func apply(world: Node3D) -> void:
	# Structural walls, collisions, and shared materials retain their exact state.
	for room in world.registry.rooms.values():
		var center: Vector3 = world.registry.vector(room.center)
		var size: Vector3 = world.registry.vector(room.size)
		var x: float = 10.0 if center.x < 13.0 else 16.0
		var face_x: float = x + (0.09 if x == 10.0 else -0.09)
		var half: float = float(room.door_width) * 0.5
		var z0: float = center.z - size.z * 0.5
		var z1: float = center.z + size.z * 0.5
		var door_z: float = float(room.door[2])
		_add_wall_run(world, face_x, center.y, z0, door_z - half)
		_add_wall_run(world, face_x, center.y, door_z + half, z1)
		_add_frame(world, face_x, center.y, door_z, half)
	# Gap closures exist where rooms do not supply their own wall.
	for closure in HallwayGeometry.edge_closures():
		var x: float = float(closure.position.x)
		var face_x: float = x + (0.09 if x == 10.0 else -0.09)
		_add_wall_run(world, face_x, float(closure.floor) * 5.0, float(closure.z_min), float(closure.z_max))
	for x in [10.09, 15.91]:
		_add_wall_run(world, x, 0.0, -11.0, -4.0)
	_add_floor_tiles(world, 0, -11.0, 68.0)
	_add_floor_tiles(world, 1, -4.0, 50.0)
	_add_floor_tiles(world, 1, 50.0, 68.0)
	_add_ceiling_panels(world, 0, -4.0, 50.0)
	_add_ceiling_panels(world, 1, -4.0, 50.0)
	_add_ceiling_panels(world, 1, 50.0, 68.0)
	_add_stair_finish(world)
	_add_fixtures(world)
	for floor in [0, 1]:
		for z in [10.7, 27.4, 43.4]:
			for x in [10.0, 16.0]:
				_sconce(world, x, float(floor) * 5, z)


static func _add_wall_run(world: Node3D, x: float, y: float, z0: float, z1: float) -> void:
	if z1 - z0 < 0.05: return
	var length: float = z1 - z0
	var z: float = (z0 + z1) * 0.5
	# Mesh only: structural wall supplies collision. Hall-facing offset prevents z fight.
	world.box(world, Vector3(x, y + 0.77, z), Vector3(0.018, 1.54, length), LOWER, false)
	world.box(world, Vector3(x, y + 2.79, z), Vector3(0.018, 2.42, length), UPPER, false)
	# The old continuous mid-wall strip crossed mounted corridor artwork.
	# The material break at 1.54 m already defines this edge cleanly.
	world.box(world, Vector3(x + (0.02 if x < 13.0 else -0.02), y + 0.10, z), Vector3(0.045, 0.20, length), TRIM, false)

static func _add_frame(world: Node3D, x: float, y: float, z: float, half: float) -> void:
	# Wrap the structural reveal. The inside edge sits clear of the wall
	# panel ends, and the lintel meets the jambs without overlapping faces.
	var structural_x: float = 10.0 if x < 13.0 else 16.0
	for side in [-1.0, 1.0]:
		world.box(world, Vector3(structural_x, y + 1.49, z + side * (half + 0.033)), Vector3(.285, 2.98, .112), FRAME, false)
	world.box(world, Vector3(structural_x, y + 3.052, z), Vector3(.285, .145, 2.0 * half + .178), FRAME, false)

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
			if floor == 1 and z >= 50.0 and z <= 62.0 and x < 13.0: continue
			var transform := Transform3D(Basis.IDENTITY.scaled(Vector3(0.982, 0.012, 0.982)), Vector3(x, floor * 5.0 + 0.011, z))
			if column in [0, 5]: transforms_b.append(transform)
			elif (row + column * 3) % 9 != 0: transforms_a.append(transform)
			else: transforms_b.append(transform)
	_add_instances(world, transforms_a, FLOOR_A, 72.0)
	_add_instances(world, transforms_b, FLOOR_B, 72.0)

static func _add_ceiling_panels(world: Node3D, floor: int, z0: float, z1: float) -> void:
	var panels: Array[Transform3D] = []
	var y := floor * 5.0 + 4.008
	for row in range(int((z1 - z0) / 2.0)):
		var z := z0 + row * 2.0 + 1.0
		for column in range(3):
			panels.append(Transform3D(Basis.from_scale(Vector3(1.976, .035, 1.976)), Vector3(11.0 + column * 2.0, y, z)))
	_add_instances(world, panels, CEILING, 85.0)
	for x in [10.11, 15.89]:
		world.box(world, Vector3(x, y - .047, (z0 + z1) * .5), Vector3(.22, .15, z1-z0), "8c9aa7", false)

static func _add_fixtures(world: Node3D) -> void:
	var material: StandardMaterial3D = world.material("fff0d8")
	material.emission_enabled = true
	material.emission = Color("fff1d8")
	material.emission_energy_multiplier = .75
	for floor in [0, 1]:
		var first := -10 if floor == 0 else -2
		for z in range(first, 68, 5):
			if floor == 0 and z >= 50: continue
			var fixture := Node3D.new()
			fixture.position = Vector3(13.0, floor * 5.0 + 3.947, z)
			world.add_child(fixture)
			world.box(fixture, Vector3.ZERO, Vector3(1.79, .085, .76), FRAME, false)
			world.box(fixture, Vector3(0, -.047, 0), Vector3(1.68, .027, .64), "fff0d8", false)
			Fixtures.ceiling_omni(fixture, Vector3(0, -.047, 0), 1.25, 6.0, false)

static func _sconce(world: Node3D, wall_x: float, base_y: float, z: float) -> void:
	var inward := 1.0 if wall_x < 13.0 else -1.0
	var point := Vector3(wall_x + inward * .18, base_y + 2.77, z)
	world.box(world, point, Vector3(.23, .29, .33), FRAME, true)
	world.box(world, point - Vector3(0, .15, 0), Vector3(.19, .023, .29), "fff0d8", false)
	Fixtures.down(world, point + Vector3(inward * .095, -.185, 0), .76, 2.85,
		Vector3(-inward * .32, -.94, 0).normalized(), 54.0)

static func _add_direction_sign(world: Node3D, y: float, z: float, title: String) -> void:
	for x in [11.86, 14.14]:
		world.box(world, Vector3(x, y + .43, z), Vector3(.064, .61, .064), FRAME, false)
	var signage = preload("res://scripts/campus/presentation/entrance_signage.gd")
	var label := signage.mount(world, title, Vector3(13, y, z), PI, Vector2(2.75, .40), 28)
	label.pixel_size = .0048
	label.outline_size = 0
	label.visibility_range_end = 20

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
	var sections := {}
	for tile in transforms:
		var section := floori(tile.origin.z / 5.0)
		if not sections.has(section):sections[section]=[]
		sections[section].append(tile)
	for section in sections:
		_add_instance_section(world,sections[section],color,range_end)

static func _add_instance_section(world: Node3D, transforms: Array, color: String, range_end: float) -> void:
	var center: Vector3=transforms[0].origin
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = world.box_mesh
	multimesh.instance_count = transforms.size()
	for i in range(transforms.size()):
		var tile: Transform3D=transforms[i]
		tile.origin-=center
		multimesh.set_instance_transform(i,tile)
	var node := MultiMeshInstance3D.new()
	node.position=center
	node.multimesh = multimesh
	node.material_override = world.material(color)
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.visibility_range_end = range_end
	node.visibility_range_end_margin = 8.0
	world.add_child(node)





