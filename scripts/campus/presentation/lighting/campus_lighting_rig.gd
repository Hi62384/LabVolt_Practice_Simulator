class_name CampusLightingRig
extends Node3D
## Campus sky, exterior key light and interior fill.
## Ambient stays readable throughout the day; practical fixtures light enclosed rooms.

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
var ceiling_fill: DirectionalLight3D
var sky: Sky
var sky_material: ProceduralSkyMaterial
var scene_environment := false

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
	if is_instance_valid(ceiling_fill): ceiling_fill.visible = enabled

func _build_once() -> void:
	if world_environment == null:
		world_environment = get_node_or_null("WorldEnvironment") as WorldEnvironment
	if world_environment == null:
		world_environment = WorldEnvironment.new()
		world_environment.name = "WorldEnvironment"
		add_child(world_environment)

	scene_environment = world_environment.environment != null
	if not scene_environment:
		_build_default_environment()

	sun = get_node_or_null("Sun") as DirectionalLight3D
	if sun == null:
		sun = DirectionalLight3D.new()
		sun.name = "Sun"
		add_child(sun)
	sun.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = 65.0
	sun.shadow_bias = 0.07
	sun.shadow_normal_bias = 1.4
	interior_fill = get_node_or_null("InteriorFill") as DirectionalLight3D
	if interior_fill == null:
		interior_fill = DirectionalLight3D.new()
		interior_fill.name = "InteriorFill"
		add_child(interior_fill)
	interior_fill.rotation_degrees = Vector3(-65.0, 145.0, 0.0)
	interior_fill.light_color = Color("edf0f7")
	interior_fill.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
	interior_fill.shadow_enabled = false
	# A low upward bounce keeps ceilings readable in rooms lit by downward
	# fixtures, including when the GI volume is still settling after streaming.
	ceiling_fill = DirectionalLight3D.new()
	ceiling_fill.name = "CeilingBounce"
	ceiling_fill.rotation_degrees = Vector3(76.0,145.0,0.0)
	ceiling_fill.light_color = Color("e5ebf5")
	ceiling_fill.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
	ceiling_fill.light_specular = 0.0
	ceiling_fill.light_bake_mode = Light3D.BAKE_DISABLED
	ceiling_fill.light_energy = .10
	add_child(ceiling_fill)

func _build_default_environment() -> void:
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
	environment.glow_bloom = 0.0
	environment.glow_hdr_threshold = 1.0
	environment.glow_hdr_scale = 1.65
	environment.glow_intensity = 0.75
	environment.glow_hdr_luminance_cap = 64.0
	world_environment.environment = environment

func _apply_time_of_day() -> void:
	if not is_instance_valid(world_environment) or not is_instance_valid(sun) or not is_instance_valid(interior_fill): return
	var daylight := clampf(sin((time_of_day - 6.0) * TAU / 24.0), -1.0, 1.0)
	var day_mix := smoothstep(-0.12, 0.22, daylight)
	var twilight := 1.0 - smoothstep(0.02, 0.48, absf(daylight))
	var elevation_degrees := lerpf(-12.0, 68.0, clampf((daylight + 0.15) / 1.15, 0.0, 1.0))
	var azimuth_degrees := (time_of_day / 24.0) * 360.0 - 70.0
	sun.rotation_degrees = Vector3(-elevation_degrees, azimuth_degrees, 0.0)
	sun.light_color = Color("ffb178").lerp(Color("fff7ea"), clampf(daylight * 1.8, 0.0, 1.0))
	sun.light_energy = lerpf(0.025, 0.55, day_mix) * brightness_scale
	interior_fill.light_energy = lerpf(0.009, 0.020, day_mix) * brightness_scale
	var visuals := get_parent().get_node_or_null("CampusVisualSettings")
	if visuals != null:
		sun.light_color *= visuals.sun_tint
		sun.light_energy *= visuals.sun_energy

	if scene_environment:return
	sky_material.sky_top_color = NIGHT_SKY_TOP.lerp(DAY_SKY_TOP, day_mix)
	sky_material.sky_horizon_color = NIGHT_SKY_HORIZON.lerp(DAY_SKY_HORIZON, day_mix).lerp(Color("f1a06f"), twilight * 0.38)
	sky_material.ground_bottom_color = NIGHT_GROUND_BOTTOM.lerp(DAY_GROUND_BOTTOM, day_mix)
	sky_material.ground_horizon_color = NIGHT_GROUND_HORIZON.lerp(DAY_GROUND_HORIZON, day_mix).lerp(Color("b9785f"), twilight * 0.25)
	sky_material.sun_curve = lerpf(0.04, 0.12, day_mix)
	world_environment.environment.background_energy_multiplier = lerpf(0.18, 0.92, day_mix) * brightness_scale
	world_environment.environment.ambient_light_energy = lerpf(0.22, 0.285, day_mix) * brightness_scale
	world_environment.environment.ambient_light_color = Color("c0ccdf").lerp(Color("dce3eb"), day_mix)
