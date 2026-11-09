extends Node3D
## Optional visual layer. No collision or gameplay state; parent under DormHall.
const Layout = preload("res://scripts/campus/dorms/world/dorm_layout.gd")
var mats: Dictionary = {}
var cube := BoxMesh.new()
var tube := CylinderMesh.new()
var plaques := {}

func set_door_title(bay: String, title: String) -> void:
	var plaque: Label3D = plaques.get(bay)
	if not is_instance_valid(plaque):return
	plaque.text = title
	plaque.pixel_size = minf(.003, .036/maxi(1,title.length()))

func install(hall: Node3D, contracts: Array[Dictionary]) -> void:
	name = "DormHallFinish"
	hall.add_child(self)
	cube.size = Vector3.ONE
	tube.top_radius = 0.5
	tube.bottom_radius = 0.5
	tube.height = 1.0
	var end_z: float = Layout.hall_end_z(contracts.size())
	for z in range(int(Layout.ENTRY_Z) + 2, int(end_z), 2):
		part(self, "FloorJoint", Vector3(13, .003, z), Vector3(5.8, .004, .012), "687887")
		part(self, "CeilingJoint", Vector3(13, 3.997, z), Vector3(5.8, .009, .018), "c5c7cc")
	for x in [11.5, 13.0, 14.5]:
		part(self, "FloorJoint", Vector3(x, .003, (Layout.ENTRY_Z + end_z) * .5), Vector3(.012, .004, end_z - Layout.ENTRY_Z), "687887")
		part(self, "CeilingJoint", Vector3(x, 3.997, (Layout.ENTRY_Z + end_z) * .5), Vector3(.018, .009, end_z - Layout.ENTRY_Z), "c5c7cc")
	for x in [10.12, 15.88]:
		part(self, "CeilingTrim", Vector3(x, 3.96, (Layout.ENTRY_Z + end_z) * .5), Vector3(.08, .075, end_z - Layout.ENTRY_Z), "ba9169")
	for room in contracts:
		entrance(room, hall)
	part(self, "EndLowerWall", Vector3(13, .78, end_z - .092), Vector3(5.8, 1.55, .022), "788d9a")
	part(self, "EndChairRail", Vector3(13, 1.58, end_z - .11), Vector3(5.8, .065, .04), "9b7659")
	part(self, "EndBaseboard", Vector3(13, .10, end_z - .112), Vector3(5.8, .20, .045), "3d5264")
	part(self, "EndCeilingTrim", Vector3(13, 3.96, end_z - .12), Vector3(5.8, .075, .08), "ba9169")
	part(self, "NoticeFrame", Vector3(13, 2.48, end_z - .14), Vector3(2.22, .89, .07), "725b47")
	part(self, "NoticeFace", Vector3(13, 2.48, end_z - .19), Vector3(2.08, .75, .035), "dfd4bf")
	var notice := Label3D.new()
	notice.text = "STUDENT RESIDENCE\nCommunity noticeboard"
	notice.position = Vector3(13, 2.48, end_z - .22)
	notice.rotation.y = PI
	notice.font_size = 46
	notice.pixel_size = .003
	notice.modulate = Color("39434b")
	add_child(notice)
	part(self, "EndBench", Vector3(13, 0.48, end_z - 0.58), Vector3(1.9, 0.12, 0.44), "80634c")
	_solid("BenchCollision",Vector3(13,.27,end_z-.58),Vector3(1.9,.54,.44))
	for x in [12.12, 13.88]:
		part(self, "BenchFoot", Vector3(x, 0.24, end_z - 0.58), Vector3(0.1, 0.42, 0.38), "485055")
	for x in [10.65, 15.35]:
		part(self, "Planter", Vector3(x,.22,end_z-.55), Vector3(.37,.44,.37), "80634c", true)
		_solid("PlanterCollision",Vector3(x,.22,end_z-.55),Vector3(.37,.44,.37))
		part(self, "PlantStem", Vector3(x,.59,end_z-.55), Vector3(.04,.5,.04), "54694c")
		for branch in [-1.0, 1.0]:
			var leaf := part(self, "PlantLeaf", Vector3(x+branch*.11,.71,end_z-.55), Vector3(.27,.07,.17), "687d59")
			leaf.rotation.z = branch * .43

func _solid(label: String, at: Vector3, size: Vector3) -> void:
	var body := StaticBody3D.new()
	body.name=label
	body.position=at
	body.collision_mask=0
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size=size
	collision.shape=box
	body.add_child(collision)
	add_child(body)

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
		part(self, "Baseboard", Vector3(wall_x + face * .112, .10, z + direction * (Layout.DOOR_WIDTH * .5 + span * .5)), Vector3(.045, .20, span - .12), "3d5264")
		part(self, "DoorJamb", Vector3(wall_x + face * 0.14, 1.14, z + direction * (Layout.DOOR_WIDTH * 0.5 + 0.055)), Vector3(0.2, 2.28, 0.09), "393f43")
	part(self, "DoorFrameTop", Vector3(wall_x + face * 0.14, 2.31, z), Vector3(0.2, 0.1, Layout.DOOR_WIDTH + 0.2), "393f43")
	var plaque := Label3D.new()
	plaque.name = "RoomNumber"
	plaque.text = "Dorm"
	plaque.font_size = 32
	plaque.pixel_size = 0.003
	plaque.modulate = Color("f0e8d8")
	plaque.outline_modulate = Color("252d31")
	plaque.position = Vector3(wall_x + face * 0.16, 1.85, z + 1.06)
	plaque.rotation.y = PI * 0.5 if west else -PI * 0.5
	add_child(plaque)
	plaques[str(room.dorm_id)] = plaque
	part(self, "NumberBacking", plaque.position - Vector3(face * 0.025, 0, 0), Vector3(0.03, 0.24, 0.72), "343d41")
	var sconce := Vector3(wall_x + face * .13, 2.38, z + 1.06)
	part(self, "SconceHousing", sconce, Vector3(.10, .44, .19), "334755")
	var lens := part(self, "SconceLens", sconce + Vector3(face * .06, 0, 0), Vector3(.035, .35, .13), "fff2de")
	var diffuse := lens.material_override as StandardMaterial3D
	diffuse.emission_enabled = true
	diffuse.emission = Color("ffeac6")
	diffuse.emission_energy_multiplier = .3
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
