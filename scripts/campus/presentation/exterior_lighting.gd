extends Node3D
## Review candidate. Parent under the persistent campus root, at identity transform.
## Two frame-mounted accent sources at the published entrance portal.

@export_range(0.0, 24.0, 0.05) var time_of_day := 13.5:
	set(value):
		time_of_day = fposmod(value, 24.0)
		_update_lights()
@export_range(0.0, 2.0, 0.01) var brightness_scale := 1.0:
	set(value):
		brightness_scale = maxf(value, 0.0)
		_update_lights()

var lamps: Array[OmniLight3D] = []
var campus_clock: Node3D
var clock_refresh := 0.0
const POSITIONS := [Vector3(9.72, 4.2, -11.32), Vector3(16.28, 4.2, -11.32)]

func _ready() -> void:
	for index in POSITIONS.size():
		var lamp := OmniLight3D.new()
		lamp.name = "EntranceLamp%d" % index
		lamp.position = POSITIONS[index]
		lamp.light_color = Color("ffe7c4")
		lamp.omni_range = 5.0
		lamp.shadow_enabled = false
		add_child(lamp)
		lamps.append(lamp)
	_update_lights()

func _process(delta: float) -> void:
	clock_refresh-=delta
	if clock_refresh>0.0:return
	clock_refresh=.25
	if not is_instance_valid(campus_clock):
		campus_clock=get_tree().root.find_child("CampusLightingRig",true,false) as Node3D
	if is_instance_valid(campus_clock):
		set_time_of_day(float(campus_clock.get("time_of_day")))
		brightness_scale=float(campus_clock.get("brightness_scale"))

func set_time_of_day(hours: float) -> void:
	time_of_day = hours

func _update_lights() -> void:
	var daylight := sin((time_of_day - 6.0) * TAU / 24.0)
	var night_mix := 1.0 - smoothstep(-0.05, 0.3, daylight)
	for index in lamps.size():
		lamps[index].light_energy = lerpf(0.08, 0.36, night_mix) * brightness_scale
