extends Node
## Reusable finish and interaction controller for the two registered washrooms.
const Rules = preload("res://review_artifacts/washrooms_20261107/stall_state.gd")
const IDS := ["washroom_1", "washroom_2"]
const CENTERS := [-6.8, -2.6, 1.6, 5.8]
const ORIGINS := {"washroom_1": Vector3(0, 0, 47), "washroom_2": Vector3(26, 5, 33)}
var rules = Rules.new()
var game: Node
var roots := {}
var doors := {}
var taps := {}
var materials := {}

func install(owner_game: Node, campus: Node3D) -> bool:
	if not is_instance_valid(owner_game) or not is_instance_valid(campus): return false
	game = owner_game
	for id in IDS:
		var root := _build(id)
		campus.add_child(root)
		if not campus.register_content(id, root):
			root.queue_free()
			return false
		roots[id] = root
	multiplayer.peer_disconnected.connect(_peer_left)
	if not multiplayer.is_server(): _refresh.rpc_id(1)
	return true

func interact(target: Node) -> bool:
	if not is_instance_valid(target) or target.get_meta("role", "") != "washroom_fixture": return false
	var room := str(target.get_meta("room_id", ""))
	var index := int(target.get_meta("stall", -1))
	var action := str(target.get_meta("action", ""))
	if room not in IDS: return true
	if action == "tap":
		_toggle_tap(room, index)
		return true
	if multiplayer.is_server(): _host_act(room, index, action, 1)
	else: _request.rpc_id(1, room, index, action)
	return true

@rpc("any_peer", "call_remote", "reliable")
func _request(room: String, index: int, action: String) -> void:
	if multiplayer.is_server(): _host_act(room, index, action, multiplayer.get_remote_sender_id())

@rpc("any_peer", "call_remote", "reliable")
func _refresh() -> void:
	if not multiplayer.is_server(): return
	var peer := multiplayer.get_remote_sender_id()
	for room in IDS:
		for index in CENTERS.size(): _sync.rpc_id(peer, room, index, rules.state(room, index))

func _host_act(room: String, index: int, action: String, peer: int) -> void:
	var actor: Node3D = game.player if peer == 1 else game.avatars.get(peer)
	if not is_instance_valid(actor) or room not in IDS: return
	var result: Dictionary = rules.act(room, index, action, peer, actor.global_position - ORIGINS[room])
	if not result.get("ok", false): return
	if action != "flush":
		_apply(room, index, result.state)
		_sync.rpc(room, index, result.state)

@rpc("authority", "call_remote", "reliable")
func _sync(room: String, index: int, value: Dictionary) -> void:
	if room in IDS and index >= 0 and index < CENTERS.size(): _apply(room, index, value)

func _peer_left(peer: int) -> void:
	if not multiplayer.is_server(): return
	for key in rules.release_peer(peer):
		var bits := key.split(":")
		var room: String = bits[0]
		var index := int(bits[1])
		var value := rules.state(room, index)
		_apply(room, index, value)
		_sync.rpc(room, index, value)

func _apply(room: String, index: int, value: Dictionary) -> void:
	var key := room + ":" + str(index)
	if not doors.has(key): return
	var hinge: Node3D = doors[key]
	# Open inward into the stall, leaving the common aisle clear.
	hinge.rotation.y = -1.42 if value.open else 0.0
	var target: StaticBody3D = hinge.get_node("Door")
	target.set_meta("label", "Close stall door" if value.open else ("Unlock stall door" if int(value.owner) != 0 else "Open stall door"))

func _toggle_tap(room: String, index: int) -> void:
	var key := room + ":" + str(index)
	if taps.has(key): taps[key].visible = not taps[key].visible

func _mat(name: String, color: Color, roughness := 0.85, metallic := 0.0) -> Material:
	if materials.has(name): return materials[name]
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	material.metallic = metallic
	materials[name] = material
	return material

func _box(parent: Node3D, name: String, position: Vector3, size: Vector3, material: Material, solid := false) -> Node3D:
	var body: Node3D = StaticBody3D.new() if solid else Node3D.new()
	body.name = name
	body.position = position
	parent.add_child(body)
	var mesh := MeshInstance3D.new()
	var shape := BoxMesh.new()
	shape.size = size
	mesh.mesh = shape
	mesh.material_override = material
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	body.add_child(mesh)
	if solid:
		var collision := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = size
		collision.shape = box
		body.add_child(collision)
	return body

func _cylinder(parent: Node3D, name: String, position: Vector3, radius: float, height: float, material: Material) -> void:
	var mesh := MeshInstance3D.new()
	mesh.name = name
	mesh.position = position
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = radius
	cylinder.bottom_radius = radius
	cylinder.height = height
	cylinder.radial_segments = 12
	mesh.mesh = cylinder
	mesh.material_override = material
	parent.add_child(mesh)

func _target(body: Node3D, room: String, stall: int, action: String, label: String) -> void:
	body.set_meta("role", "washroom_fixture")
	body.set_meta("room_id", room)
	body.set_meta("stall", stall)
	body.set_meta("action", action)
	body.set_meta("label", label)

func _build(id: String) -> Node3D:
	var root := Node3D.new()
	root.name = "WashroomFinish_" + id
	root.position = ORIGINS[id]
	var wall := _mat("wall", Color("e8e9e4"))
	var blue := _mat("blue", Color("8b9fa9"))
	var tile := _mat("tile", Color("b9bec0"), 0.96)
	var grout := _mat("grout", Color("929a9e"))
	var teal := _mat("teal", Color("34777a"))
	var ceramic := _mat("ceramic", Color("e9ebe6"), 0.45)
	var steel := _mat("steel", Color("a1aaab"), 0.35, 0.55)
	var ink := _mat("ink", Color("26363d"))
	var oak := _mat("oak", Color("9b7959"))
	var mirror := _mat("mirror", Color("a4b8b8"), 0.17, 0.45)
	_box(root, "Matte tile floor", Vector3(0, 0.006, 0), Vector3(19.6, 0.012, 11.6), tile)
	for x in range(-9, 10): _box(root, "Fine grout", Vector3(x, 0.013, 0), Vector3(0.008, 0.002, 11.6), grout)
	for z in range(-5, 6): _box(root, "Fine grout", Vector3(0, 0.013, z), Vector3(19.6, 0.002, 0.008), grout)
	for z in [-5.78, 5.78]:
		_box(root, "Blue wall dado", Vector3(0, 0.66, z), Vector3(19.6, 1.32, 0.025), blue)
		_box(root, "Wall trim", Vector3(0, 1.33, z), Vector3(19.6, 0.035, 0.04), wall)
	for x in [-9.78, 9.78]:
		_box(root, "Side wall dado", Vector3(x, 0.66, 0), Vector3(0.025, 1.32, 11.5), blue)
	for x in range(-8, 9, 4):
		for z in range(-4, 5, 4):
			_box(root, "Ceiling tile", Vector3(x, 3.88, z), Vector3(3.96, 0.035, 3.96), wall)
	for x in [-6, -2, 2, 6]:
		_box(root, "Ceiling light", Vector3(x, 3.84, 0), Vector3(1.7, 0.045, 0.58), ceramic)
	for i in CENTERS.size(): _stall(root, id, i, CENTERS[i], teal, steel, ceramic, ink)
	for i in 4: _sink(root, id, i, -6.0 + 4.0 * i, oak, ceramic, steel, ink, mirror)
	_box(root, "Privacy return", Vector3(8.2 if id == "washroom_1" else -8.2, 1.2, 3.65), Vector3(0.09, 2.1, 2), teal, true)
	_box(root, "Paper towel dispenser", Vector3(-9.65, 1.45, -3.9), Vector3(0.2, 0.4, 0.33), steel)
	_box(root, "Waste bin", Vector3(-8.9, 0.38, -3.9), Vector3(0.45, 0.72, 0.4), ink, true)
	_box(root, "Washroom sign", Vector3(8.8, 2.55, -5.72), Vector3(1.05, 0.35, 0.04), ink)
	return root

func _stall(root: Node3D, room: String, i: int, x: float, teal: Material, steel: Material, ceramic: Material, ink: Material) -> void:
	for dx in [-1.8, 1.8]:
		_box(root, "Stall partition", Vector3(x + dx, 1.32, 4.1), Vector3(0.075, 2.25, 3.2), teal, true)
		for z in [2.6, 5.45]: _box(root, "Partition foot", Vector3(x + dx, 0.11, z), Vector3(0.09, 0.22, 0.09), steel)
		_box(root, "Wall bracket", Vector3(x + dx, 2.35, 5.55), Vector3(0.16, 0.09, 0.12), steel)
	for dx in [-1.24, 1.24]: _box(root, "Stall front", Vector3(x + dx, 1.32, 2.5), Vector3(1.13, 2.25, 0.075), teal, true)
	var hinge := Node3D.new()
	hinge.name = "Hinge_%s_%d" % [room, i]
	hinge.position = Vector3(x - 0.68, 0, 2.5)
	root.add_child(hinge)
	var door := _box(hinge, "Door", Vector3(0.67, 1.31, 0), Vector3(1.34, 2.16, 0.065), teal, true)
	_target(door, room, i, "toggle", "Close stall door")
	for y in [0.48, 2.05]: _cylinder(hinge, "Visible hinge", Vector3(0, y, 0), 0.035, 0.15, steel)
	_box(hinge, "Outside handle", Vector3(1.19, 1.14, -0.1), Vector3(0.18, 0.05, 0.08), steel)
	var lock := _box(root, "Inside lock", Vector3(x + 0.52, 1.12, 2.64), Vector3(0.19, 0.09, 0.07), steel, true)
	_target(lock, room, i, "lock", "Lock stall from inside")
	var unlock := _box(root, "Inside unlock", Vector3(x + 0.52, 0.92, 2.64), Vector3(0.19, 0.09, 0.07), ink, true)
	_target(unlock, room, i, "unlock", "Unlock stall")
	doors[room + ":" + str(i)] = hinge
	_apply(room, i, rules.state(room, i))
	_cylinder(root, "Toilet pedestal", Vector3(x, 0.26, 4.6), 0.27, 0.5, ceramic)
	_cylinder(root, "Toilet bowl", Vector3(x, 0.51, 4.6), 0.38, 0.13, ceramic)
	_box(root, "Toilet cistern", Vector3(x, 0.79, 5.27), Vector3(0.66, 0.62, 0.26), ceramic)
	var flush := _box(root, "Flush button", Vector3(x + 0.13, 1.13, 5.27), Vector3(0.1, 0.025, 0.07), steel, true)
	_target(flush, room, i, "flush", "Flush toilet")
	_box(root, "Toilet paper holder", Vector3(x + 1.63, 0.85, 4.48), Vector3(0.09, 0.13, 0.25), steel)

func _sink(root: Node3D, room: String, i: int, x: float, oak: Material, ceramic: Material, steel: Material, ink: Material, mirror: Material) -> void:
	_box(root, "Vanity cabinet", Vector3(x, 0.43, -5.24), Vector3(2.58, 0.8, 0.92), oak, true)
	_box(root, "Vanity counter", Vector3(x, 0.87, -5.2), Vector3(2.72, 0.09, 1.0), ceramic, true)
	_cylinder(root, "Ceramic basin", Vector3(x, 0.94, -5.16), 0.44, 0.13, ceramic)
	_cylinder(root, "Visible drain", Vector3(x, 1.015, -5.16), 0.045, 0.008, ink)
	_cylinder(root, "Faucet stem", Vector3(x, 1.12, -5.56), 0.035, 0.38, steel)
	_box(root, "Faucet spout", Vector3(x, 1.30, -5.39), Vector3(0.08, 0.05, 0.35), steel)
	var tap := _box(root, "Tap handle", Vector3(x + 0.14, 1.09, -5.52), Vector3(0.14, 0.06, 0.09), steel, true)
	_target(tap, room, i, "tap", "Turn faucet on or off")
	var water := _box(root, "Running water", Vector3(x, 1.17, -5.21), Vector3(0.018, 0.24, 0.018), mirror)
	water.visible = false
	taps[room + ":" + str(i)] = water
	_box(root, "Mirror frame", Vector3(x, 2.03, -5.76), Vector3(2.33, 1.27, 0.05), ink)
	_box(root, "Mirror surface", Vector3(x, 2.03, -5.725), Vector3(2.22, 1.16, 0.012), mirror)
	_box(root, "Soap dispenser", Vector3(x + 1.08, 1.27, -5.7), Vector3(0.16, 0.28, 0.13), ceramic)
