extends Node3D
## Geometry contract: existing two 8x6 bays; hallway aperture X16/Z58..60.
const HEIGHT := 5.0
const DOOR_X := 16.18
const DOOR_Z := 59.0
const WIDTH := 2.0
var world: Node3D
var leaves: Dictionary = {}
var barriers: Dictionary = {}
var indicators: Array[Label3D] = []
var controls: Dictionary = {}
var tweens: Dictionary = {}
var sound: AudioStreamPlayer3D
var last_phase := ""
var materials: Dictionary = {}

func mount(shell: Node3D) -> void:
	world = shell
	for floor_id in [0, 1]: _landing(floor_id)
	sound = AudioStreamPlayer3D.new()
	sound.bus = "Effects"
	sound.position = Vector3(16, 2, 59); sound.max_distance = 15.0; sound.volume_db = -20.0
	add_child(sound)

func _material(color: String, lit: bool = false) -> StandardMaterial3D:
	var key := color + str(lit)
	if not materials.has(key):
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(color); mat.roughness = 0.82
		if lit: mat.emission_enabled = true; mat.emission = Color(color); mat.emission_energy_multiplier = 0.7
		materials[key] = mat
	return materials[key]

func _box(point: Vector3, size: Vector3, color: String, solid: bool = true) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var shape := BoxMesh.new(); shape.size = size
	mesh.mesh = shape; mesh.position = point; mesh.material_override = _material(color)
	add_child(mesh)
	if solid:
		var body := StaticBody3D.new(); body.position = point
		var collision := CollisionShape3D.new(); var box := BoxShape3D.new(); box.size = size
		collision.shape = box; body.add_child(collision); add_child(body)
	return mesh

func _text(value: String, point: Vector3, yaw: float, size: int = 28) -> Label3D:
	var label := Label3D.new(); label.text = value; label.position = point; label.rotation.y = yaw
	label.font_size = size; label.pixel_size = 0.006; label.outline_size = 4
	add_child(label); return label

static func control_position(floor_id: int, button: int) -> Vector3:
	var y := floor_id * HEIGHT
	return Vector3(15.82, y + 1.25, 60.35) if button < 0 else Vector3(16.43, y + 1.20 + button * 0.28, 60.45)

func _button(floor_id: int, button: int) -> void:
	var point := control_position(floor_id, button)
	var target := StaticBody3D.new(); target.position = point; target.collision_layer = 4; target.collision_mask = 0
	target.set_meta("role", "elevator_control"); target.set_meta("floor", floor_id); target.set_meta("button", button)
	target.set_meta("label", ("Call elevator " + ("↑" if floor_id == 0 else "↓")) if button < 0 else "Elevator · Floor " + str(button + 1))
	var collision := CollisionShape3D.new(); var box := BoxShape3D.new(); box.size = Vector3(0.16, 0.22, 0.22)
	collision.shape = box; target.add_child(collision); add_child(target)
	var mesh := _box(point, Vector3(0.10, 0.16, 0.16), "b4bec0", false)
	controls[str(floor_id) + ":" + str(button)] = mesh
	_text(("↑" if floor_id == 0 else "↓") if button < 0 else str(button + 1), point + Vector3(-0.065 if button < 0 else 0.065, 0, 0), -PI / 2 if button < 0 else PI / 2, 22)

func _landing(floor_id: int) -> void:
	var y := floor_id * HEIGHT
	# Retain the original landing extent, floor altitude and east corridor connection.
	_box(Vector3(20, y - 0.12, 59), Vector3(8, 0.24, 6), "7c898e")
	for z in [56.0, 62.0]:
		_box(Vector3(20, y + 1.0, z), Vector3(8, 2, 0.16), "859aa5")
		_box(Vector3(20, y + 3.0, z), Vector3(8, 2, 0.16), "e3e9e6")
	_box(Vector3(24, y + 2, 59), Vector3(0.16, 4, 6), "859aa5")
	_box(Vector3(20, y + 4.06, 59), Vector3(8, 0.18, 6), "edf0ed")
	# Enclosed front wall with door pockets, no solid spans across the aperture.
	for z in [57.0, 61.0]:
		_box(Vector3(16.0, y + 2, z), Vector3(0.08, 4, 2), "859aa5")
		_box(Vector3(16.35, y + 2, z), Vector3(0.08, 4, 2), "859aa5")
	_box(Vector3(16.12, y + 3.5, 59), Vector3(0.22, 1, 2), "e3e9e6")
	for z in [57.955, 60.045]: _box(Vector3(16.03, y + 1.48, z), Vector3(0.46, 2.96, 0.12), "294e68")
	_box(Vector3(16.03, y + 3.04, 59), Vector3(0.46, 0.16, 2.22), "294e68")
	_box(Vector3(16.0, y + 0.015, 59), Vector3(0.45, 0.03, 2), "b4bec0", false)
	var pair: Array[MeshInstance3D] = []
	for side in [-1, 1]:
		pair.append(_box(Vector3(DOOR_X, y + 1.48, 59 + side * 0.5), Vector3(0.09, 2.96, 0.995), "9daeb6", false))
	leaves[floor_id] = pair
	var body := StaticBody3D.new(); body.position = Vector3(DOOR_X, y + 1.5, 59)
	var collision := CollisionShape3D.new(); var box := BoxShape3D.new(); box.size = Vector3(0.22, 3, 2)
	collision.shape = box; body.add_child(collision); add_child(body); barriers[floor_id] = collision
	for x in [15.75, 16.46]:
		_box(Vector3(x, y + 3.43, 59), Vector3(0.08, 0.4, 1.15), "294e68", false)
		indicators.append(_text("1", Vector3(x + (-0.06 if x < 16 else 0.06), y + 3.43, 59), -PI / 2 if x < 16 else PI / 2, 32))
	_text("ELEVATOR", Vector3(15.73, y + 3.85, 59), -PI / 2, 29)
	_box(Vector3(15.87, y + 1.3, 60.35), Vector3(0.12, 0.65, 0.4), "294e68", false)
	_box(Vector3(16.35, y + 1.35, 60.45), Vector3(0.12, 0.9, 0.42), "294e68", false)
	_button(floor_id, -1)
	for stop in [0, 1]: _button(floor_id, stop)
	# Handrails never cross the doorway; no cabin furniture.
	_box(Vector3(23.72, y + 1, 59), Vector3(0.07, 0.07, 4.8), "486879")
	for z in [56.28, 61.72]: _box(Vector3(20, y + 1, z), Vector3(6.5, 0.07, 0.07), "486879")
	for z in range(57, 62): _box(Vector3(20, y + 0.005, z), Vector3(7.7, 0.008, 0.018), "66777f", false)
	var light_mesh := _box(Vector3(20, y + 3.93, 59), Vector3(3, 0.04, 1), "edf0ed", false)
	light_mesh.material_override = _material("edf0ed", true)
	var light := OmniLight3D.new(); light.position = Vector3(20, y + 3.4, 59)
	light.omni_range = 5.0; light.light_energy = 0.65; light.shadow_enabled = false; add_child(light)
	# Waiting furniture against the west wall, beyond the stair landing.
	# Cabin and Z58..60 aperture stay clear. The X13..16 upper route stays entirely clear.
	_box(Vector3(10.55, y + 0.46, 64.4), Vector3(0.55, 0.12, 1.8), "486879")
	_box(Vector3(10.22, y + 0.85, 64.4), Vector3(0.09, 0.65, 1.8), "859aa5")
	for z in [63.75, 65.05]: _box(Vector3(10.55, y + 0.2, z), Vector3(0.4, 0.4, 0.09), "294e68")
	_box(Vector3(10.55, y + 0.25, 66), Vector3(0.45, 0.5, 0.45), "7c898e")
	_box(Vector3(10.55, y + 0.8, 66), Vector3(0.5, 0.7, 0.5), "6f8b79", false)

func apply_snapshot(state: Dictionary, animate: bool = true) -> void:
	var phase: String = state.phase
	var floor_id: int = state.floor
	for landing in [0, 1]:
		var active: bool = landing == floor_id
		var open: bool = active and phase in ["open", "opening"]
		barriers[landing].set_deferred("disabled", active and phase == "open")
		if tweens.has(landing) and tweens[landing].is_valid(): tweens[landing].kill()
		var tween := create_tween().set_parallel(true).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		tweens[landing] = tween
		for index in range(2):
			var side: float = -1.0 if index == 0 else 1.0
			var z: float = 59.0 + side * (1.55 if open else 0.5)
			var duration := maxf(0.05, 0.8 - float(state.elapsed)) if animate and phase in ["opening", "closing"] else 0.0
			tween.tween_property(leaves[landing][index], "position:z", z, duration)
	for indicator in indicators:
		indicator.text = str(floor_id + 1) + (" → " + str(int(state.destination) + 1) if phase == "moving" else "")
	for key in controls:
		var parts: PackedStringArray = key.split(":")
		var stop: int = int(parts[1]); var landing: int = int(parts[0])
		var lit: bool = state.queue.has(landing if stop < 0 else stop) or (phase == "moving" and int(state.destination) == (landing if stop < 0 else stop))
		controls[key].material_override = _material("f0cc78" if lit else "b4bec0", lit)
	if animate and phase != last_phase and phase in ["opening", "closing", "moving"]:
		play_tone(880.0 if phase == "opening" else 180.0, 0.13)
	last_phase = phase

func play_tone(frequency: float = 650.0, seconds: float = 0.06) -> void:
	# Tiny generated PCM cue, allocated only on an interaction/state edge.
	var bytes := PackedByteArray(); var count := int(22050 * seconds)
	bytes.resize(count * 2)
	for i in range(count):
		var envelope: float = sin(PI * float(i) / count)
		bytes.encode_s16(i * 2, int(sin(TAU * frequency * i / 22050.0) * envelope * 2600))
	var wav := AudioStreamWAV.new(); wav.format = AudioStreamWAV.FORMAT_16_BITS; wav.mix_rate = 22050; wav.data = bytes
	sound.stream = wav; sound.play()
