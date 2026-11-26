extends Node3D
## Each floor has an identical cabin and a shared hallway aperture at X16.
const HEIGHT := 5.0
const DOOR_X := 16.18
const DOOR_Z := 59.0
const WIDTH := 2.0
const DOOR_HEIGHT := 2.28
const CABIN_BACK := 19.5
const CABIN_HALF_WIDTH := 1.6
const CABIN_HEIGHT := 2.65
const CABIN_FRONT := 16.35
var world: Node3D
var leaves: Dictionary = {}
var barriers: Dictionary = {}
var indicators: Array[Node3D] = []
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
	return Vector3(15.82, y + 1.25, 60.35) if button < 0 else Vector3(16.70, y + 1.20 + button * 0.28, 60.45)

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
	# Retain the structural divider backing the second-floor Commons wall.
	for z in [56.0,62.0]:
		_box(Vector3(20,y+2.04,z),Vector3(8,4.08,.16),"c6cbd6")
	_box(Vector3(24,y+2.04,59),Vector3(.16,4.08,6),"c6cbd6")
	var depth := CABIN_BACK - 16.0
	var center := 16.0 + depth * .5
	_box(Vector3(center,y-.12,DOOR_Z),Vector3(depth,.24,CABIN_HALF_WIDTH*2.0),"7c898e")
	for z in [DOOR_Z-CABIN_HALF_WIDTH,DOOR_Z+CABIN_HALF_WIDTH]:
		_box(Vector3(center,y+1.0,z),Vector3(depth,2,.12),"859aa5")
		_box(Vector3(center,y+(2.0+CABIN_HEIGHT)*.5,z),Vector3(depth,CABIN_HEIGHT-2.0,.12),"e3e9e6")
	_box(Vector3(CABIN_BACK,y+CABIN_HEIGHT*.5,DOOR_Z),Vector3(.12,CABIN_HEIGHT,CABIN_HALF_WIDTH*2.0),"859aa5")
	_box(Vector3(center,y+CABIN_HEIGHT+.07,DOOR_Z),Vector3(depth,.14,CABIN_HALF_WIDTH*2.0),"edf0ed")
	# The corridor front also closes the space on either side of the cabin.
	for side in [-1.0,1.0]:
		var z: float = DOOR_Z+side*2.0
		if side > 0 and floor_id==1:
			_box(Vector3(16.0,y+2.04,z),Vector3(.10,4.08,2),"859aa5")
		_box(Vector3(CABIN_FRONT,y+CABIN_HEIGHT*.5,z),Vector3(.08,CABIN_HEIGHT,2),"859aa5")
	# Each piece owns its volume: the wall begins above the header and the
	# sliding leaves run behind the hallway-facing jambs.
	var header_top := DOOR_HEIGHT+.124
	_box(Vector3(16.05,y+(4.08+header_top)*.5,DOOR_Z),Vector3(.22,4.08-header_top,WIDTH),"e3e9e6")
	# The visible surround is a face-mounted plate. Its back clears the
	# corridor skin, and the separate reveal stays behind the moving leaves.
	var surround_x := 15.80
	var jamb_inset := .025
	for side in [-1.0,1.0]:
		_box(Vector3(surround_x,y+DOOR_HEIGHT*.5,DOOR_Z+side*(WIDTH*.5+.047-jamb_inset*.5)),Vector3(.065,DOOR_HEIGHT,.094+jamb_inset),"29404f",false).cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# Separate liners on either side of the sliding-leaf track conceal
		# the structural wall ends without intersecting the moving doors.
		var jamb_z: float=DOOR_Z+side*(WIDTH*.5+.018)
		_box(Vector3(15.968,y+DOOR_HEIGHT*.5,jamb_z),Vector3(.266,DOOR_HEIGHT,.086),"29404f",false).cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_box(Vector3(16.31,y+DOOR_HEIGHT*.5,jamb_z),Vector3(.16,DOOR_HEIGHT,.086),"486879",false).cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_box(Vector3(surround_x,y+DOOR_HEIGHT+.062,DOOR_Z),Vector3(.065,.124,WIDTH+.188),"29404f",false).cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_box(Vector3(DOOR_X,y+DOOR_HEIGHT+.035,DOOR_Z),Vector3(.12,.045,WIDTH),"486879",false)
	var cabin_header_bottom := DOOR_HEIGHT+.06
	_box(Vector3(CABIN_FRONT,y+(cabin_header_bottom+CABIN_HEIGHT)*.5,DOOR_Z),Vector3(.08,CABIN_HEIGHT-cabin_header_bottom,WIDTH),"859aa5",false)
	_box(Vector3(16.078,y+.015,DOOR_Z),Vector3(.38,.016,WIDTH-.018),"b4bec0",false)
	var pair: Array[MeshInstance3D] = []
	for side in [-1, 1]:
		pair.append(_box(Vector3(DOOR_X, y + DOOR_HEIGHT * .5, DOOR_Z + side * .5), Vector3(.09, DOOR_HEIGHT, .995), "9daeb6", false))
	leaves[floor_id] = pair
	var body := StaticBody3D.new(); body.position = Vector3(DOOR_X, y + DOOR_HEIGHT * .5, DOOR_Z)
	var collision := CollisionShape3D.new(); var box := BoxShape3D.new(); box.size = Vector3(.22, DOOR_HEIGHT, WIDTH)
	collision.shape = box; body.add_child(collision); add_child(body); barriers[floor_id] = collision
	_floor_display(15.785,y+2.48,-1.0)
	_floor_display(16.421,y+2.48,1.0)
	_box(Vector3(15.87, y + 1.3, 60.35), Vector3(0.08, 0.40, 0.30), "294e68", false)
	_box(Vector3(16.35, y + 1.35, 60.45), Vector3(0.06, 0.66, 0.34), "294e68", false)
	_button(floor_id, -1)
	for stop in [0, 1]: _button(floor_id, stop)
	_box(Vector3(CABIN_BACK-.16,y+1,DOOR_Z),Vector3(.07,.07,2.62),"486879")
	for z in [DOOR_Z-CABIN_HALF_WIDTH+.15,DOOR_Z+CABIN_HALF_WIDTH-.15]:
		_box(Vector3(center+.16,y+1,z),Vector3(depth-.58,.07,.07),"486879")
	for z in [58.0,59.0,60.0]:
		_box(Vector3(center,y+.005,z),Vector3(depth-.28,.008,.018),"66777f",false)
	var light_mesh := _box(Vector3(center,y+CABIN_HEIGHT-.035,DOOR_Z),Vector3(1.62,.045,.82),"edf0ed",false)
	light_mesh.material_override = _material("edf0ed", true)
	var light := OmniLight3D.new()
	light.position = Vector3(center,y+CABIN_HEIGHT-.35,DOOR_Z)
	light.omni_range = 4.0
	light.light_energy = .74
	light.shadow_enabled = false
	add_child(light)
	# Keep waiting furniture clear of the elevator and the M110 entrance.
	var bench_x := 15.45 if floor_id==0 else 10.55
	var back_x := 15.78 if floor_id==0 else 10.22
	var bench_z := 66.85 if floor_id==0 else 64.4
	_box(Vector3(bench_x, y + 0.46, bench_z), Vector3(0.55, 0.12, 1.8), "486879")
	_box(Vector3(back_x, y + 0.85, bench_z), Vector3(0.09, 0.65, 1.8), "859aa5")
	for offset in [-.65,.65]: _box(Vector3(bench_x, y + 0.2, bench_z+offset), Vector3(0.4, 0.4, 0.09), "294e68")
	_box(Vector3(10.55, y + 0.25, 66), Vector3(0.45, 0.5, 0.45), "7c898e")
	_box(Vector3(10.55, y + 0.8, 66), Vector3(0.5, 0.7, 0.5), "6f8b79", false)

func _floor_display(x: float,y: float,facing: float) -> void:
	_box(Vector3(x,y,DOOR_Z),Vector3(.06,.18,.48),"263946",false)
	_box(Vector3(x+facing*.035,y,DOOR_Z),Vector3(.012,.132,.41),"101c24",false)
	for floor_id in 2:
		var digit := Node3D.new()
		digit.name="FloorDigit%d"%(floor_id+1)
		add_child(digit)
		indicators.append(digit)
		var segments := [[Vector2(0,0),false],[Vector2(-.013,.04),true],[Vector2(0,-.047),true]] if floor_id==0 else [
			[Vector2(0,.047),true],[Vector2(.028,.023),false],[Vector2(0,0),true],
			[Vector2(-.028,-.023),false],[Vector2(0,-.047),true]]
		for segment in segments:
			var point: Vector2=segment[0]
			var horizontal: bool=segment[1]
			var mesh := _box(Vector3(x+facing*.045,y+point.y,DOOR_Z-point.x*facing),Vector3(.003,.010 if horizontal else (.079 if floor_id==0 else .035),.046 if horizontal else .010),"83deda",false)
			mesh.material_override=_material("83deda",true)
			mesh.reparent(digit)
		digit.visible=floor_id==0

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
	for index in indicators.size():
		indicators[index].visible=index%2==floor_id
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
