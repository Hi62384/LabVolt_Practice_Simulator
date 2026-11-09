class_name DormHall
extends Node3D
## Connected, capacity-driven dorm presentation. This node publishes targets and
## anchors only; the host-authoritative dorm service owns assignment and door use.

const Layout = preload("res://scripts/campus/dorms/world/dorm_layout.gd")

var _unit_box := BoxMesh.new()
var _unit_cylinder := CylinderMesh.new()
var _materials: Dictionary = {}
var _built := false
var _capacity := 0
var room_contracts: Array[Dictionary] = []
var door_targets: Dictionary = {}

func build(authoritative_player_capacity: int) -> void:
	if _built:
		return
	_capacity = maxi(authoritative_player_capacity, 1)
	_built = true
	name = "DormHall"
	_unit_box.size = Vector3.ONE
	_unit_cylinder.top_radius = 0.5
	_unit_cylinder.bottom_radius = 0.5
	_unit_cylinder.height = 1.0
	_build_corridor()
	room_contracts = Layout.all_rooms(_capacity)
	for contract in room_contracts:
		_build_room(contract)

func _material(color: String, metallic := 0.0) -> StandardMaterial3D:
	var key := color + ":" + str(metallic)
	if not _materials.has(key):
		var value := StandardMaterial3D.new()
		value.albedo_color = Color(color)
		value.roughness = 0.72 if metallic == 0.0 else 0.38
		value.metallic = metallic
		_materials[key] = value
	return _materials[key]

func _mesh(parent: Node3D, node_name: String, position: Vector3, size: Vector3, color: String, cylinder := false) -> MeshInstance3D:
	var result := MeshInstance3D.new()
	result.name = node_name
	result.mesh = _unit_cylinder if cylinder else _unit_box
	result.position = position
	result.scale = size
	result.material_override = _material(color, 0.65 if color in ["6f7778", "b8a36a"] else 0.0)
	result.visibility_range_end = 72.0
	result.visibility_range_end_margin = 7.0
	parent.add_child(result)
	return result

func _solid(parent: Node3D, node_name: String, position: Vector3, size: Vector3, color: String) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = node_name
	body.position = position
	body.collision_layer = 1
	body.collision_mask = 0
	var shape_node := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	shape_node.shape = shape
	body.add_child(shape_node)
	parent.add_child(body)
	_mesh(body, "Surface", Vector3.ZERO, size, color)
	return body

func _marker(parent: Node3D, node_name: String, position: Vector3) -> Marker3D:
	var marker := Marker3D.new()
	marker.name = node_name
	marker.position = position
	parent.add_child(marker)
	return marker

func _build_corridor() -> void:
	var end_z := Layout.hall_end_z(_capacity)
	var length := end_z - Layout.ENTRY_Z
	var center_z := Layout.ENTRY_Z + length / 2.0
	_solid(self, "HallFloor", Vector3(13.0, -0.12, center_z), Vector3(6.0, 0.24, length), "756f64")
	_mesh(self, "HallCeiling", Vector3(13.0, 4.08, center_z), Vector3(6.0, 0.16, length), "e7dfcf")
	_solid(self, "NorthEndWall", Vector3(13.0, 2.0, end_z), Vector3(6.0, 4.0, 0.16), "bcae99")
	# Warm, instanced ceiling panels; emissive-looking surfaces without per-room lights.
	var count := maxi(1, ceili(length / 5.5))
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = _unit_box
	mm.instance_count = count
	for index in range(count):
		var z := Layout.ENTRY_Z + 2.75 + float(index) * 5.5
		mm.set_instance_transform(index, Transform3D(Basis.IDENTITY.scaled(Vector3(1.55, 0.035, 0.28)), Vector3(13.0, 3.94, minf(z, end_z - 1.0))))
	var lights := MultiMeshInstance3D.new()
	lights.name = "CeilingPanels"
	lights.multimesh = mm
	lights.material_override = _material("f4dca4")
	add_child(lights)

func _build_room(contract: Dictionary) -> void:
	var root := Node3D.new()
	root.name = contract.dorm_id
	root.set_meta("dorm_id", contract.dorm_id)
	root.set_meta("dorm_index", contract.index)
	add_child(root)
	var center: Vector3 = contract.center
	var west: bool=str(contract.side)=="west"
	var outer_x := center.x - Layout.ROOM_WIDTH / 2.0 if west else center.x + Layout.ROOM_WIDTH / 2.0
	var wall_x := Layout.CORRIDOR_X_MIN if west else Layout.CORRIDOR_X_MAX
	var z_min := center.z - Layout.ROOM_DEPTH / 2.0
	var z_max := center.z + Layout.ROOM_DEPTH / 2.0
	_solid(root, "Floor", center + Vector3(0, -0.12, 0), Vector3(Layout.ROOM_WIDTH, 0.24, Layout.ROOM_DEPTH), "897c6c")
	_mesh(root, "Ceiling", center + Vector3(0, 4.08, 0), Vector3(Layout.ROOM_WIDTH, 0.16, Layout.ROOM_DEPTH), "e8dfd0")
	_solid(root, "OuterWall", Vector3(outer_x, 2.0, center.z), Vector3(0.16, 4.0, Layout.ROOM_DEPTH), "bcae99")
	for z in [z_min, z_max]:
		_solid(root, "Partition", Vector3(center.x, 2.0, z), Vector3(Layout.ROOM_WIDTH, 4.0, 0.16), "bcae99")
	var side_span := (Layout.ROOM_DEPTH - Layout.DOOR_WIDTH) / 2.0
	for direction in [-1.0, 1.0]:
		_solid(root, "EntryWall", Vector3(wall_x, 2.0, center.z + direction * (Layout.DOOR_WIDTH / 2.0 + side_span / 2.0)), Vector3(0.16, 4.0, side_span), "bcae99")
		_mesh(root, "WoodSlat", Vector3(outer_x + (0.09 if west else -0.09), 2.0, center.z + direction * 3.6), Vector3(0.07, 2.6, 1.65), "6c4f3c")
	_mesh(root, "DoorLintel", Vector3(wall_x, 3.55, center.z), Vector3(0.16, 0.9, Layout.DOOR_WIDTH), "57483e")
	_build_door(root, contract)
	_marker(root, "EntryAnchor", contract.entry_anchor)
	_marker(root, "RoomAnchor", contract.room_anchor)
	_marker(root, "WorkshopAnchor", contract.workshop_anchor)
	_marker(root, "LoadoutNotesAnchor", contract.loadout_notes_anchor)
	_build_bed_storage(root, center, west)
	_build_workshop(root, contract.workshop_anchor, west)
	_build_loadout_notes(root, contract.loadout_notes_anchor, west)

func _build_door(root: Node3D, contract: Dictionary) -> void:
	var west: bool=str(contract.side)=="west"
	var pivot := Node3D.new()
	pivot.name = "DoorPivot"
	pivot.position = contract.door + Vector3(0.0, 0.0, -Layout.DOOR_WIDTH / 2.0)
	pivot.set_meta("dorm_id", contract.dorm_id)
	pivot.set_meta("role", "dorm_door_pivot")
	root.add_child(pivot)
	var door := AnimatableBody3D.new()
	door.name = "Door"
	door.position = Vector3(0.0, 1.1, Layout.DOOR_WIDTH / 2.0)
	door.collision_layer = 1 | 4
	door.collision_mask = 0
	door.set_meta("dorm_id", contract.dorm_id)
	door.set_meta("dorm_index", contract.index)
	door.set_meta("role", "dorm_door")
	door.set_meta("label", "Open/close %s" % contract.dorm_id)
	var collision := CollisionShape3D.new()
	collision.name = "CollisionShape3D"
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.12, 2.2, Layout.DOOR_WIDTH)
	collision.shape = shape
	door.add_child(collision)
	pivot.add_child(door)
	_mesh(door, "DoorLeaf", Vector3.ZERO, shape.size, "77513c")
	_mesh(door, "Handle", Vector3(-0.09 if west else 0.09, 0.0, Layout.DOOR_WIDTH * 0.34), Vector3(0.045, 0.045, 0.045), "b8a36a", true)
	door_targets[contract.dorm_id] = door

func _build_bed_storage(root: Node3D, center: Vector3, west: bool) -> void:
	var outward := -1.0 if west else 1.0
	var bed_x := center.x + outward * 1.85
	_solid(root, "BedFrame", Vector3(bed_x, 0.3, center.z - 1.0), Vector3(1.15, 0.35, 2.25), "493d35")
	_mesh(root, "Mattress", Vector3(bed_x, 0.57, center.z - 1.0), Vector3(1.05, 0.22, 2.05), "d7cfbd")
	_mesh(root, "Blanket", Vector3(bed_x, 0.71, center.z - 1.35), Vector3(1.07, 0.08, 1.1), "557269")
	_mesh(root, "Pillow", Vector3(bed_x, 0.72, center.z - 0.15), Vector3(0.72, 0.16, 0.42), "efe6d5")
	_solid(root, "Wardrobe", Vector3(center.x + outward * 2.45, 1.05, center.z + 3.7), Vector3(1.25, 2.1, 1.0), "5d493b")
	_mesh(root, "LampShade", Vector3(center.x + outward * 2.0, 1.5, center.z + 1.0), Vector3(0.33, 0.45, 0.33), "e3b66e", true)
	_mesh(root, "LampStem", Vector3(center.x + outward * 2.0, 0.82, center.z + 1.0), Vector3(0.06, 0.75, 0.06), "6f7778", true)

func _build_workshop(root: Node3D, anchor: Vector3, west: bool) -> void:
	var inward := 1.0 if west else -1.0
	_solid(root, "WorkshopTable", anchor + Vector3(0, 0.72, 0), Vector3(2.25, 0.12, 1.15), "674a36")
	for x in [-0.9, 0.9]:
		for z in [-0.42, 0.42]:
			_mesh(root, "TableLeg", anchor + Vector3(x, 0.35, z), Vector3(0.09, 0.7, 0.09), "49362b")
	# Open hard kit: base, upright lid, inset breadboard and shaped components.
	_mesh(root, "OpenKitBase", anchor + Vector3(inward * 0.35, 0.85, 0), Vector3(0.85, 0.09, 0.62), "29383b")
	var lid := _mesh(root, "OpenKitLid", anchor + Vector3(inward * 0.77, 1.18, 0), Vector3(0.06, 0.62, 0.62), "34494c")
	lid.rotation.z = 0.12 * inward
	_mesh(root, "Breadboard", anchor + Vector3(inward * 0.32, 0.93, 0), Vector3(0.55, 0.035, 0.38), "e8e1cf")
	for index in range(7):
		var component := anchor + Vector3(-inward * (0.15 + float(index % 3) * 0.19), 0.91, -0.34 + float(index / 3) * 0.22)
		_mesh(root, "Component", component, Vector3(0.055, 0.055 + 0.025 * (index % 2), 0.12), ["bd604b", "d7b558", "4d7182"][index % 3], index % 2 == 0)

func _build_loadout_notes(root: Node3D, anchor: Vector3, west: bool) -> void:
	var inward := 1.0 if west else -1.0
	_solid(root, "LoadoutNotesTable", anchor + Vector3(0, 0.72, 0), Vector3(2.25, 0.12, 1.15), "674a36")
	for x in [-0.9, 0.9]:
		for z in [-0.42, 0.42]:
			_mesh(root, "TableLeg", anchor + Vector3(x, 0.35, z), Vector3(0.09, 0.7, 0.09), "49362b")
	# Backpack reads as a soft body with front pocket, flap, straps and top handle.
	_mesh(root, "BackpackBody", anchor + Vector3(inward * 0.42, 1.12, 0.04), Vector3(0.58, 0.72, 0.46), "425b4d")
	_mesh(root, "BackpackPocket", anchor + Vector3(inward * 0.18, 1.02, 0.04), Vector3(0.18, 0.34, 0.34), "31483d")
	_mesh(root, "BackpackFlap", anchor + Vector3(inward * 0.1, 1.34, 0.04), Vector3(0.15, 0.16, 0.42), "587363")
	_mesh(root, "BackpackHandle", anchor + Vector3(inward * 0.43, 1.55, 0.04), Vector3(0.22, 0.05, 0.05), "273a31", true)
	for index in range(5):
		var paper := _mesh(root, "Paper", anchor + Vector3(-inward * (0.18 + 0.14 * index), 0.84 + 0.006 * index, -0.3 + 0.13 * (index % 3)), Vector3(0.42, 0.012, 0.3), "eee6d3")
		paper.rotation.y = -0.18 + 0.09 * index

func metrics() -> Dictionary:
	return {"capacity": _capacity, "rooms": room_contracts.size(), "doors": door_targets.size(), "shared_materials": _materials.size(), "realtime_lights": 0}
