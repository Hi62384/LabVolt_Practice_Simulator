extends Node3D
## Optional visual layer. No collision or gameplay state; parent under DormHall.
const Layout = preload("res://scripts/campus/dorms/world/dorm_layout.gd")
var mats: Dictionary = {}
var cube := BoxMesh.new()
var tube := CylinderMesh.new()

func install(hall: Node3D, contracts: Array[Dictionary]) -> void:
	name = "DormHallFinish"
	hall.add_child(self)
	cube.size = Vector3.ONE
	tube.top_radius = 0.5
	tube.bottom_radius = 0.5
	tube.height = 1.0
	var end_z: float = Layout.hall_end_z(contracts.size())
	for z in range(int(Layout.ENTRY_Z) + 2, int(end_z), 2):
		part(self, "FloorJoint", Vector3(13, 0.014, z), Vector3(5.8, 0.006, 0.018), "aab0ac")
		part(self, "CeilingJoint", Vector3(13, 3.974, z), Vector3(5.8, 0.008, 0.018), "cbcdd0")
	for x in [10.12, 15.88]:
		part(self, "FloorTrim", Vector3(x, 0.13, (Layout.ENTRY_Z + end_z) * 0.5), Vector3(0.07, 0.24, end_z - Layout.ENTRY_Z), "90745b")
		part(self, "CeilingTrim", Vector3(x, 3.91, (Layout.ENTRY_Z + end_z) * 0.5), Vector3(0.08, 0.09, end_z - Layout.ENTRY_Z), "90745b")
	for room in contracts:
		entrance(room, hall)
	# End-wall feature is indoors; no fabricated window or schedule.
	part(self, "EndPanel", Vector3(13, 2.1, end_z - 0.09), Vector3(2.7, 2.3, 0.035), "587080")
	part(self, "EndPanelBorder", Vector3(13, 3.3, end_z - 0.12), Vector3(2.9, 0.08, 0.09), "725b47")
	part(self, "EndBench", Vector3(13, 0.48, end_z - 0.58), Vector3(1.9, 0.12, 0.44), "80634c")
	for x in [12.12, 13.88]:
		part(self, "BenchFoot", Vector3(x, 0.24, end_z - 0.58), Vector3(0.1, 0.42, 0.38), "485055")

func material(hex: String) -> StandardMaterial3D:
	if not mats.has(hex):
		var value := StandardMaterial3D.new()
		value.albedo_color = Color(hex)
		value.roughness = 0.78
		mats[hex] = value
	return mats[hex]

func part(parent: Node3D, label: String, at: Vector3, dimensions: Vector3, color: String, round_shape := false) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	mesh.name = label
	mesh.mesh = tube if round_shape else cube
	mesh.position = at
	mesh.scale = dimensions
	mesh.material_override = material(color)
	mesh.visibility_range_end = 72.0
	mesh.visibility_range_end_margin = 7.0
	parent.add_child(mesh)
	return mesh

func entrance(room: Dictionary, hall: Node3D) -> void:
	var root := hall.get_node_or_null(str(room.dorm_id)) as Node3D
	if root == null:
		return
	var wall_x: float = float(room.door.x)
	var west: bool = str(room.side) == "west"
	var face := 1.0 if west else -1.0
	var z: float = float(room.door.z)
	var span: float = (Layout.ROOM_DEPTH - Layout.DOOR_WIDTH) * 0.5
	for direction in [-1.0, 1.0]:
		part(self, "LowerWall", Vector3(wall_x + face * 0.092, 0.78, z + direction * (Layout.DOOR_WIDTH * 0.5 + span * 0.5)), Vector3(0.022, 1.55, span - 0.15), "788d9a")
		part(self, "WallChairRail", Vector3(wall_x + face * 0.11, 1.58, z + direction * (Layout.DOOR_WIDTH * 0.5 + span * 0.5)), Vector3(0.04, 0.065, span - 0.15), "9b7659")
		part(self, "DoorJamb", Vector3(wall_x + face * 0.14, 1.14, z + direction * (Layout.DOOR_WIDTH * 0.5 + 0.055)), Vector3(0.2, 2.28, 0.09), "393f43")
	part(self, "DoorFrameTop", Vector3(wall_x + face * 0.14, 2.31, z), Vector3(0.2, 0.1, Layout.DOOR_WIDTH + 0.2), "393f43")
	var plaque := Label3D.new()
	plaque.name = "RoomNumber"
	plaque.text = str(room.dorm_id).to_upper()
	plaque.font_size = 32
	plaque.pixel_size = 0.003
	plaque.modulate = Color("f0e8d8")
	plaque.outline_modulate = Color("252d31")
	plaque.position = Vector3(wall_x + face * 0.16, 2.75, z + 1.06)
	plaque.rotation.y = PI * 0.5 if west else -PI * 0.5
	add_child(plaque)
	part(self, "NumberBacking", plaque.position - Vector3(face * 0.025, 0, 0), Vector3(0.03, 0.24, 0.72), "343d41")
	var door := hall.door_targets.get(str(room.dorm_id)) as Node3D
	if door == null:
		return
	# All leaf details are parented to the animated body, so collision and visuals swing together.
	for xface in [-1.0, 1.0]:
		part(door, "PanelInset", Vector3(xface * 0.064, 0.28, 0), Vector3(0.018, 0.75, 0.95), "614735")
		part(door, "PanelInset", Vector3(xface * 0.064, -0.52, 0), Vector3(0.018, 0.44, 0.95), "614735")
		part(door, "LockPlate", Vector3(xface * 0.09, 0.02, Layout.DOOR_WIDTH * 0.32), Vector3(0.025, 0.22, 0.09), "a9946b")
		part(door, "Lever", Vector3(xface * 0.13, 0.075, Layout.DOOR_WIDTH * 0.32), Vector3(0.1, 0.04, 0.18), "b8aa84")
		part(door, "Keyhole", Vector3(xface * 0.105, -0.055, Layout.DOOR_WIDTH * 0.32), Vector3(0.015, 0.035, 0.018), "343d41")
	for y in [-0.75, 0.65]:
		part(door, "Hinge", Vector3(0, y, -Layout.DOOR_WIDTH * 0.5), Vector3(0.1, 0.18, 0.1), "798184", true)
