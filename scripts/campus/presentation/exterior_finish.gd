extends Node3D

const FRAME := "263f50"
const BLUE := "36596b"
const WALL := "9ba9b5"
const WOOD := "a47a51"
const LENS := "fff0d5"
const Signage = preload("res://scripts/campus/presentation/entrance_signage.gd")
const RoomSignage = preload("res://scripts/campus/presentation/signage/campus_signage.gd")

var world: Node3D
var crown := SphereMesh.new()
var trunk := CylinderMesh.new()
var paving: Dictionary = {}

func mount(campus: Node3D) -> bool:
	if not is_instance_valid(campus) or get_parent() != null: return false
	world = campus
	campus.add_child(self)
	crown.radius = .5
	crown.height = 1.0
	crown.radial_segments = 8
	crown.rings = 3
	trunk.bottom_radius = .11
	trunk.top_radius = .064
	trunk.height = 1.0
	trunk.radial_segments = 7
	_build_facade()
	_build_courtyard()
	_build_directory()
	return true

func _build_facade() -> void:
	for x in [0.0, 26.0]:
		# Window recesses sit between continuous sill and spandrel bands.
		_box(Vector3(x, 4.36, -10.58), Vector3(20, 8.72, 1.04), WALL)
		_box(Vector3(x, 4.99, -7.19), Vector3(20, 8.56, 6.78), WALL)
		_box(Vector3(x, .59, -11.23), Vector3(20, 1.18, .26), BLUE)
		_box(Vector3(x, 4.06, -11.27), Vector3(20, .23, .32), "b4bec6")
		_box(Vector3(x, 8.79, -7.43), Vector3(20.12, .25, 8.14), FRAME)
		for y in [2.42, 6.16]:
			for bay in range(6):
				_window(x - 8.33 + bay * 3.33, y, -11.18)
		for bay in range(1, 6):
			_box(Vector3(x - 10 + bay * 3.33, 4.23, -11.15), Vector3(.18, 8.46, .22), "8d9eab")
		_box(Vector3(x, .21, -11.29), Vector3(20, .23, .15), FRAME)

	# Recessed glazing closes the upper corridor end. Ground level remains a
	# wide covered passage with its original six-metre walkable opening.
	_box(Vector3(13, 6.93, -4.12), Vector3(6.16, 4.18, .24), BLUE, true)
	_box(Vector3(13, 6.84, -8.24), Vector3(6.16, 3.98, 5.95), WALL)
	_window(13, 7.02, -11.35, 5.56, 2.7)
	_box(Vector3(13, 8.94, -7.66), Vector3(6.52, .23, 7.75), "b4bec6")
	# The inner jamb face meets the corridor lining at z=-11. Keep it
	# proud of the wing wall at x=10/16 so those side faces cannot overlap.
	for x in [9.78, 16.22]:
		_box(Vector3(x, 2.13, -11.53), Vector3(.64, 4.26, 1.06), FRAME, true)
	_box(Vector3(13, .011, -11), Vector3(5.8, .02, .13), "718694")
	_box(Vector3(13, 4.16, -8.15), Vector3(6.96, .34, 7.82), "a7b3bd", true)
	# One soffit from the fascia to the first interior ceiling panel.
	_box(Vector3(13, 4.008, -8.03), Vector3(5.8, .035, 8.06), "c6c8cc")
	_box(Vector3(13, 4.30, -12.02), Vector3(7.08, .66, .30), FRAME)
	var heading := RoomSignage.create_label("LABVOLT CAMPUS", Vector3(13, 4.32, -12.18), PI, 46)
	add_child(heading)
	heading.pixel_size = .0054
	heading.outline_size = 0
	heading.visibility_range_end = 52

func _window(x: float, y: float, z: float, width := 2.94, height := 1.72) -> void:
	_box(Vector3(x, y, z), Vector3(width, height, .19), FRAME)
	for pane in [-1.0, 1.0]:
		var cx: float = x + pane * width * .245
		var tint := "537586" if pane < 0 else "5c7e91"
		_box(Vector3(cx, y, z - .105), Vector3(width * .466, height - .16, .028), tint)
		_box(Vector3(cx, y + height * .285, z - .124), Vector3(width * .45, height * .25, .018), "7092a4")
	_box(Vector3(x, y - height * .15, z - .134), Vector3(width - .1, .045, .05), FRAME)
	_box(Vector3(x, y - height * .5, z - .08), Vector3(width + .13, .10, .31), "718694")

func _build_courtyard() -> void:
	# Ground art is slightly above the existing solid slab. Grass beds and
	# paving occupy different footprints, with the walk clear of props.
	_box(Vector3(13, -.11, -32.5), Vector3(60, .16, 15), "657e48")
	for side in [-1.0, 1.0]:
		var lawn_x: float = 13 + side * 12.95
		_box(Vector3(lawn_x, -.012, -18.03), Vector3(19.9, .042, 13.84), "526c35")
		for z in [-22.1, -14.9]:
			_box(Vector3(13 + side * 4.85, .085, z), Vector3(2.8, .16, 1.20), "8f9d9d", true)
			for i in range(4):
				_foliage(Vector3(13 + side * 4.85 + (i - 1.5) * .63, .37, z),
					Vector3(.82, .47 + (i % 2) * .1, 1.0), ["4a7038", "567b41"][i % 2])
		for z in [-19.6, -15.4]:
			_bollard(Vector3(13 + side * 3.48, .02, z))
		_banner_lamp(Vector3(13 + side * 6.35, .02, -18.35), -side)
		for z in [-19.9, -13.9]:
			_tree(Vector3(13 + side * (7.9 if z < -18 else 15.7), .02, z))
		for z in [-26.5, -32.2]:
			_tree(Vector3(13 + side * (10.1 if z > -30 else 19.4), -.03, z))
		_bench(Vector3(13 + side * 4.9, .02, -19.72), side)
		_box(Vector3(13 + side * 3.02, .009, -18), Vector3(.17, .031, 14), "7d8c92")
	for row in range(10):
		var z := -24.3 + row * 1.4
		for col in range(4):
			_paver(Vector3(10.825 + col * 1.45, .002, z), Vector3(1.433, .035, 1.381), (row + col * 3) % 3)
	for side in [-1.0, 1.0]:
		for column in range(11):
			_paver(Vector3(13 + side * (3.72 + column * 1.42), .014, -19.55), Vector3(1.403, .034, 1.74), column % 3)
	for index in paving:
		var batch := MultiMesh.new()
		batch.transform_format = MultiMesh.TRANSFORM_3D
		batch.mesh = world.box_mesh
		batch.instance_count = paving[index].size()
		for i in batch.instance_count:
			batch.set_instance_transform(i, paving[index][i])
		var node := MultiMeshInstance3D.new()
		node.multimesh = batch
		node.material_override = world.material(["68716e", "626d6c", "68706f"][index])
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(node)

func _paver(point: Vector3, size: Vector3, shade: int) -> void:
	if not paving.has(shade): paving[shade] = []
	paving[shade].append(Transform3D(Basis.from_scale(size), point))

func _build_directory() -> void:
	_box(Vector3(8.08, .24, -16.73), Vector3(2.62, .48, .72), "8496a2", true)
	_box(Vector3(8.08, 1.30, -16.73), Vector3(2.52, 1.74, .23), FRAME, true)
	var title := Signage.mount(self, "CAMPUS DIRECTORY", Vector3(8.08, 1.96, -16.875), PI, Vector2(2.4, .31), 30)
	title.pixel_size = .0044
	title.outline_size = 0

func _bench(at: Vector3, side: float) -> void:
	for z in [-.16, 0.0, .16]:
		_box(at + Vector3(0, .47, z), Vector3(2.00, .07, .135), WOOD, true)
	for y in [.64, .82]:
		_box(at + Vector3(0, y, side * .24), Vector3(2.00, .135, .065), WOOD, true)
	for x in [-.77, .77]:
		_box(at + Vector3(x, .23, 0), Vector3(.085, .46, .47), FRAME, true)
		_box(at + Vector3(x, .65, side * .24), Vector3(.075, .43, .075), FRAME)

func _tree(at: Vector3) -> void:
	_branch(at, at + Vector3(.05, 2.26, .03), 1.0)
	var trunk_body := StaticBody3D.new()
	trunk_body.position = at + Vector3(.03, 1.12, .01)
	trunk_body.collision_layer = 1
	trunk_body.collision_mask = 0
	var trunk_collision := CollisionShape3D.new()
	var trunk_shape := CylinderShape3D.new()
	trunk_shape.radius = .18
	trunk_shape.height = 2.24
	trunk_collision.shape = trunk_shape
	trunk_body.add_child(trunk_collision)
	add_child(trunk_body)
	for i in range(4):
		var angle := TAU * i / 4.0 + at.x * .43
		var offset := Vector3(cos(angle), 0, sin(angle))
		var end := at + offset * .63 + Vector3(0, 2.55 + .18 * (i % 2), 0)
		_branch(at + Vector3(.03, 1.30, .01), end, .62)
		_foliage(end + offset * .21, Vector3(1.55, 1.41, 1.54), ["527740", "456838", "648747", "50743c"][i])
	_foliage(at + Vector3(.1, 3.08, .03), Vector3(1.72, 1.38, 1.75), "5c8144")

func _branch(start: Vector3, end: Vector3, width: float) -> void:
	var part := MeshInstance3D.new()
	part.mesh = trunk
	part.material_override = world.material("6c5844")
	add_child(part)
	part.position = (start + end) * .5
	part.quaternion = Quaternion(Vector3.UP, start.direction_to(end))
	part.scale = Vector3(width, start.distance_to(end), width)

func _foliage(point: Vector3, size: Vector3, tint: String) -> void:
	var part := MeshInstance3D.new()
	part.mesh = crown
	part.material_override = world.material(tint)
	part.position = point
	part.scale = size
	part.rotation.y = point.x * .4
	add_child(part)

func _bollard(at: Vector3) -> void:
	_box(at + Vector3(0, .30, 0), Vector3(.18, .6, .18), FRAME, true)
	_box(at + Vector3(0, .66, 0), Vector3(.17, .15, .17), LENS)
	_box(at + Vector3(0, .76, 0), Vector3(.21, .06, .21), FRAME)

func _banner_lamp(at: Vector3, inward: float) -> void:
	_box(at + Vector3(0, 1.81, 0), Vector3(.13, 3.62, .13), FRAME, true)
	_box(at + Vector3(inward * .29, 3.57, 0), Vector3(.68, .13, .27), FRAME)
	_box(at + Vector3(inward * .41, 3.49, 0), Vector3(.39, .045, .21), LENS)
	_box(at + Vector3(-inward * .41, 2.72, 0), Vector3(.85, .055, .075), FRAME)
	_box(at + Vector3(-inward * .43, 2.15, 0), Vector3(.74, 1.1, .045), "31566e")
	_box(at + Vector3(-inward * .43, 1.71, -.026), Vector3(.74, .09, .015), "9bb1bb")
	var emblem := Signage.Signage.create_label("LV", at + Vector3(-inward * .43, 2.21, -.038), PI, 42)
	emblem.outline_size = 0
	add_child(emblem)
	var lens: StandardMaterial3D = world.material(LENS)
	lens.emission_enabled = true
	lens.emission = Color(LENS)
	lens.emission_energy_multiplier = .74
	preload("res://scripts/campus/presentation/fixture_light.gd").down(self, at + Vector3(inward * .41, 3.45, 0), .42, 5.0)

func _box(point: Vector3, size: Vector3, tint: String, solid := false) -> MeshInstance3D:
	return world.box(self, point, size, tint, solid)

