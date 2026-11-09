class_name CampusLightingRig
extends Node3D
## Compatibility-renderer-safe campus sky and key lighting.
## One directional light supplies shadows; interiors remain readable through sky ambient fill.

@export_range(0.0, 24.0, 0.05) var time_of_day := 13.5:
	set(value):
		time_of_day = fposmod(value, 24.0)
		if is_inside_tree(): _apply_time_of_day()
@export var animate_day_cycle := false
@export_range(60.0, 7200.0, 1.0) var day_length_seconds := 1200.0
@export_range(0.0, 2.0, 0.01) var brightness_scale := 1.0:
	set(value):
		brightness_scale = maxf(value, 0.0)
		if is_inside_tree(): _apply_time_of_day()

var world_environment: WorldEnvironment
var sun: DirectionalLight3D
var interior_fill: DirectionalLight3D
var sky: Sky
var sky_material: ProceduralSkyMaterial

const DAY_SKY_TOP := Color("3c83c9")
const DAY_SKY_HORIZON := Color("b8d9ee")
const DAY_GROUND_BOTTOM := Color("263742")
const DAY_GROUND_HORIZON := Color("8aa0a6")
const NIGHT_SKY_TOP := Color("071329")
const NIGHT_SKY_HORIZON := Color("182c48")
const NIGHT_GROUND_BOTTOM := Color("070b13")
const NIGHT_GROUND_HORIZON := Color("17212d")

func _ready() -> void:
	_build_once()
	_apply_time_of_day()

func _process(delta: float) -> void:
	if animate_day_cycle and day_length_seconds > 0.0:
		set_time_of_day(time_of_day + delta * 24.0 / day_length_seconds)

func set_time_of_day(hours: float) -> void:
	time_of_day = hours

func set_lighting_enabled(enabled: bool) -> void:
	if is_instance_valid(world_environment): world_environment.visible = enabled
	if is_instance_valid(sun): sun.visible = enabled
	if is_instance_valid(interior_fill): interior_fill.visible = enabled

func _build_once() -> void:
	world_environment = get_node_or_null("WorldEnvironment") as WorldEnvironment
	if world_environment == null:
		world_environment = WorldEnvironment.new()
		world_environment.name = "WorldEnvironment"
		add_child(world_environment)

	sky_material = ProceduralSkyMaterial.new()
	sky_material.sky_curve = 0.12
	sky_material.ground_curve = 0.08
	sky_material.sun_angle_max = 18.0
	sky_material.sun_curve = 0.12
	sky_material.use_debanding = true
	sky = Sky.new()
	sky.radiance_size = Sky.RADIANCE_SIZE_128
	sky.process_mode = Sky.PROCESS_MODE_REALTIME if animate_day_cycle else Sky.PROCESS_MODE_QUALITY
	sky.sky_material = sky_material

	var environment := Environment.new()
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	environment.background_energy_multiplier = 0.9
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_sky_contribution = 0.0
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.glow_enabled = true
	environment.glow_hdr_luminance_cap = 64.0
	world_environment.environment = environment

	sun = get_node_or_null("Sun") as DirectionalLight3D
	if sun == null:
		sun = DirectionalLight3D.new()
		sun.name = "Sun"
		add_child(sun)
	sun.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_max_distance = 90.0
	sun.shadow_bias = 0.07
	sun.shadow_normal_bias = 1.4
	sun.light_angular_distance = 1.1
	# The campus has solid ceilings. Compatibility sky ambient alone does not
	# illuminate the enclosed desks and walls consistently across room views.
	# A single weak, shadowless fill keeps those surfaces legible at low cost.
	interior_fill = get_node_or_null("InteriorFill") as DirectionalLight3D
	if interior_fill == null:
		interior_fill = DirectionalLight3D.new()
		interior_fill.name = "InteriorFill"
		add_child(interior_fill)
	interior_fill.rotation_degrees = Vector3(-65.0, 145.0, 0.0)
	interior_fill.light_color = Color("edf0f7")
	interior_fill.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
	interior_fill.shadow_enabled = false

func _apply_time_of_day() -> void:
	if not is_instance_valid(world_environment) or not is_instance_valid(sun) or not is_instance_valid(interior_fill): return
	var daylight := clampf(sin((time_of_day - 6.0) * TAU / 24.0), -1.0, 1.0)
	var day_mix := smoothstep(-0.12, 0.22, daylight)
	var twilight := 1.0 - smoothstep(0.02, 0.48, absf(daylight))
	var elevation_degrees := lerpf(-12.0, 68.0, clampf((daylight + 0.15) / 1.15, 0.0, 1.0))
	var azimuth_degrees := (time_of_day / 24.0) * 360.0 - 70.0
	sun.rotation_degrees = Vector3(-elevation_degrees, azimuth_degrees, 0.0)
	sun.light_color = Color("ffb178").lerp(Color("fff7ea"), clampf(daylight * 1.8, 0.0, 1.0))
	sun.light_energy = lerpf(0.035, 0.30, day_mix) * brightness_scale
	interior_fill.light_energy = lerpf(0.015, 0.035, day_mix) * brightness_scale

	sky_material.sky_top_color = NIGHT_SKY_TOP.lerp(DAY_SKY_TOP, day_mix)
	sky_material.sky_horizon_color = NIGHT_SKY_HORIZON.lerp(DAY_SKY_HORIZON, day_mix).lerp(Color("f1a06f"), twilight * 0.38)
	sky_material.ground_bottom_color = NIGHT_GROUND_BOTTOM.lerp(DAY_GROUND_BOTTOM, day_mix)
	sky_material.ground_horizon_color = NIGHT_GROUND_HORIZON.lerp(DAY_GROUND_HORIZON, day_mix).lerp(Color("b9785f"), twilight * 0.25)
	sky_material.sun_curve = lerpf(0.04, 0.12, day_mix)
	world_environment.environment.background_energy_multiplier = lerpf(0.18, 0.92, day_mix) * brightness_scale
	world_environment.environment.ambient_light_energy = lerpf(0.075, 0.16, day_mix) * brightness_scale
	world_environment.environment.ambient_light_color = Color("8ea5c8").lerp(Color("e6e8eb"), day_mix)
