extends Node
const UI = preload("res://scripts/ui/design_system/widgets.gd")
const HudTheme = preload("res://scripts/ui/design_system/theme.gd")
const InteriorShadows = preload("res://scripts/campus/presentation/lighting/interior_shadows.gd")
const Layout = preload("res://scripts/ui/hud_settings/layout.gd")
signal changed(options: Dictionary)
const SAVE := "user://campus_graphics.cfg"
const DEFAULTS := {"render_scale":1.0,"texture":1,"shadows":true,"detail_shadows":false,"lights":true,"reflections":true,"sdfgi":false,"aa":1,"npc_density":"Off","view_distance":120.0,"effects":true,"bloom":true,"lighting_quality":1,"shadow_quality":2,"bloom_quality":1,"brightness":1.0,"indoor_intensity":1.0,"lighting_tone":"Neutral","interaction_hands":true}
const PRESETS := ["Low", "Medium", "High", "Ultra", "Custom"]
const MAX_FOG_DENSITY := 0.00299
const INDOOR_SUN_SHADOW_DISTANCE := 22.0
const BAKED_OUTDOOR_SUN_SHADOW_DISTANCE := 12.0
const INDOOR_FIXTURE_SHADOW_DISTANCE := 9.0
const FIXTURE_SHADOW_BLEND_DISTANCE := 3.0
const ENVIRONMENT_CONTROLS := {
	"ssr_fade_out": ["Reflection Fade-Out", 0.0, 8.0, 0.01],
	"ssao_intensity": ["Contact Shadow Intensity", 0.0, 8.0, 0.05],
	"ssil_radius": ["Indirect Light Radius", 0.0, 16.0, 0.05],
	"sdfgi_cascades": ["Global Illumination Cascades", 1, 8, 1],
	"glow_bloom": ["Bloom Strength", 0.0, 1.0, 0.01],
	"glow_intensity": ["Glow Intensity", 0.0, 8.0, 0.01],
	"glow_blend_mode": ["Glow Blend Mode"],
	"volumetric_fog_density": ["Indoor Fog Density", 0.0, MAX_FOG_DENSITY, 0.00001],
	"adjustment_saturation": ["Color Saturation", 0.0, 2.0, 0.01],
	"adjustment_contrast": ["Color Contrast", 0.0, 2.0, 0.01],
}
var quality_preset := "Medium"
var save_error := OK
var options := DEFAULTS.duplicate()
var viewport: Viewport
var world: Node
var crowd: Object
var originals := {}
var texture_materials := {}
var shared_material_copies := {}
var node_refs := {}
var density_controls: Array[OptionButton]=[]
var _fog_environment: Environment
var _fog_density := 0.0
var _fog_clock := 0.0
var _sun: DirectionalLight3D
var _sun_shadow_distance := 0.0
var _fixture_shadow_opacity := {}
var _preview_scene_effects := false
func attach(target: Viewport, root: Node, crowd_adapter: Object=null) -> void:
	viewport=target; world=root; crowd=crowd_adapter
	load_settings()
	apply()
func load_settings(path := SAVE) -> void:
	var cfg := ConfigFile.new()
	if cfg.load(path)!=OK: return
	var saved := str(cfg.get_value("graphics", "preset", ""))
	for key in DEFAULTS:
		_validate(key,cfg.get_value("graphics",key,true if key=="sdfgi" and saved=="Ultra" else DEFAULTS[key]))
	for key in ENVIRONMENT_CONTROLS:
		options.erase(key)
		if cfg.has_section_key("graphics", key):
			_validate(key, cfg.get_value("graphics", key))
	if not options.shadows:options.shadow_quality=0
	if not options.bloom:options.bloom_quality=0
	options.shadows=options.shadow_quality>0
	options.bloom=options.bloom_quality>0
	quality_preset = "Custom"
	if saved == "Ultra" and options.aa == 3:
		var previous_ultra := _preset_options("Ultra")
		previous_ultra.aa = 3
		if options == previous_ultra:
			options = _preset_options("Ultra")
	if saved == "Custom":
		return
	for level in PRESETS.slice(0, 4):
		if options == _preset_options(level) and (saved.is_empty() or saved == level):
			quality_preset = level
			break
func save_settings(path := SAVE) -> Error:
	var cfg := ConfigFile.new()
	for key in options: cfg.set_value("graphics",key,options[key])
	cfg.set_value("graphics", "preset", quality_preset)
	return cfg.save(path)
func _validate(key: String, value: Variant) -> bool:
	if ENVIRONMENT_CONTROLS.has(key):
		if not (value is float or value is int) or not is_finite(float(value)):
			return false
		if key == "glow_blend_mode":
			if value not in [Environment.GLOW_BLEND_MODE_SCREEN, Environment.GLOW_BLEND_MODE_SOFTLIGHT]:
				return false
			options[key] = int(value)
		else:
			var spec: Array = ENVIRONMENT_CONTROLS[key]
			var amount := clampf(float(value), float(spec[1]), float(spec[2]))
			options[key] = roundi(amount) if key == "sdfgi_cascades" else amount
		return true
	if not DEFAULTS.has(key): return false
	if key in ["render_scale","view_distance","texture","aa","lighting_quality","shadow_quality","bloom_quality","brightness","indoor_intensity"]:
		if not (value is float or value is int) or not is_finite(float(value)):return false
	match key:
		"brightness":options[key]=clampf(float(value),.70,1.30)
		"indoor_intensity":options[key]=clampf(float(value),.60,1.40)
		"lighting_tone":
			if value not in ["Cool","Neutral","Warm"]:return false
			options[key]=value
		"render_scale": options[key]=clampf(float(value),0.5,1.0)
		"view_distance": options[key]=clampf(float(value),30.0,1000.0)
		"texture": options[key]=clampi(int(value),0,2)
		"aa","lighting_quality","shadow_quality","bloom_quality": options[key]=clampi(int(value),0,3)
		"npc_density":
			if str(value) not in ["Off","Low","Medium","High"]: return false
			options[key]=str(value)
		_: options[key]=bool(value)
	return true
func set_option(key: String, value: Variant) -> bool:
	if not _validate(key,value): return false
	if key == "sdfgi":
		_preview_scene_effects = false
	if key=="shadow_quality": options.shadows=options.shadow_quality>0
	elif key=="bloom_quality": options.bloom=options.bloom_quality>0
	elif key=="shadows":options.shadow_quality=maxi(int(options.shadow_quality),2) if options.shadows else 0
	elif key=="bloom":options.bloom_quality=maxi(int(options.bloom_quality),1) if options.bloom else 0
	quality_preset = "Custom"
	_apply_and_save(key)
	return true
func preset(level: String) -> void:
	if level not in PRESETS:
		return
	quality_preset = level
	_preview_scene_effects = false
	if level != "Custom":
		options = _preset_options(level)
	_apply_and_save()

func _apply_and_save(key := "") -> void:
	apply(key)
	save_error = save_settings()
	changed.emit(options.duplicate())

func _preset_options(level: String) -> Dictionary:
	var values := DEFAULTS.duplicate()
	var low := level=="Low"
	values.merge({"lighting_quality":0 if low else 2,"shadow_quality":0 if low else 2,"bloom_quality":0 if low else 1,"render_scale":0.65 if low else 1.0,"texture":0 if low else 2,"shadows":not low,"detail_shadows":level=="High","reflections":not low,"aa":0 if low else 2,"npc_density":"Off","view_distance":100.0 if low else 180.0,"effects":not low,"bloom":not low,"lights":not low},true)
	if level=="Medium": return DEFAULTS.duplicate()
	if level=="Ultra":
		values.merge({"detail_shadows":true, "aa":1, "view_distance":240.0,"lighting_quality":3, "bloom_quality":2,"shadow_quality":3,"sdfgi":true}, true)
	return values
func set_crowd_adapter(adapter: Object) -> void:
	crowd=adapter; apply()
func apply(key := "") -> void:
	for control in density_controls:
		if is_instance_valid(control): control.disabled=not (is_instance_valid(crowd) and crowd.has_method("set_density"))
	if not is_instance_valid(viewport): return
	viewport.scaling_3d_scale=float(options.render_scale)
	viewport.msaa_3d=int(options.aa)
	# Texture filtering changes real sampler behavior. Import resolution is deliberately not promised.
	viewport.anisotropic_filtering_level=0 if options.texture==0 else (2 if options.texture==1 else 4)
	if is_instance_valid(crowd) and crowd.has_method("set_density"): crowd.call("set_density",options.npc_density)
	for id in node_refs.keys():
		if node_refs[id].get_ref()==null:
			node_refs.erase(id); originals.erase(id); texture_materials.erase(id)
			_fixture_shadow_opacity.erase(id)
	if is_instance_valid(world):
		var first_pass := not get_tree().node_added.is_connected(_node_added)
		if first_pass:get_tree().node_added.connect(_node_added)
		var hands=world.get("interaction_presentation")
		if is_instance_valid(hands):hands.set_enabled(bool(options.interaction_hands))
		if first_pass:register_node(world)
		else:
			for reference in node_refs.values():
				var node: Node=reference.get_ref()
				if is_instance_valid(node) and _affects(node,key):register_node(node,false)
func _affects(node: Node, key: String) -> bool:
	if ENVIRONMENT_CONTROLS.has(key):
		return node is WorldEnvironment
	match key:
		"brightness","bloom","bloom_quality","sdfgi":return node is WorldEnvironment
		"lighting_tone","indoor_intensity","lighting_quality":return node is Light3D or node is ReflectionProbe or node is WorldEnvironment or node.has_meta("satin_floor")
		"lights":return node is Light3D
		"shadow_quality","shadows":return node is Light3D or node.has_meta("floor_contact_shadows")
		"reflections":return node is Light3D or node is ReflectionProbe or node is GeometryInstance3D or node is WorldEnvironment
		"view_distance":return node is Camera3D or node is GeometryInstance3D
		"texture","detail_shadows":return node is GeometryInstance3D
		"effects":return node is GPUParticles3D or node is CPUParticles3D or node is WorldEnvironment
		_:return key.is_empty()

func _node_added(node: Node) -> void:
	if not is_instance_valid(world) or not world.is_ancestor_of(node):
		return
	if node is GeometryInstance3D or node is Light3D or node is Camera3D or node is WorldEnvironment or node is ReflectionProbe or node is GPUParticles3D or node is CPUParticles3D:
		call_deferred("_register_added", weakref(node))

func _register_added(reference: WeakRef) -> void:
	var node: Node = reference.get_ref()
	if is_instance_valid(node) and node.is_inside_tree():
		register_node(node, false)

func _material_copy(source: BaseMaterial3D) -> BaseMaterial3D:
	var id := source.get_instance_id()
	if not shared_material_copies.has(id): shared_material_copies[id]=source.duplicate()
	return shared_material_copies[id]
func register_node(node: Node, recursive := true) -> void:
	if not (node is GeometryInstance3D or node is Light3D or node is Camera3D or node is WorldEnvironment or node is ReflectionProbe or node is GPUParticles3D or node is CPUParticles3D):
		if recursive:
			for child in node.get_children():register_node(child)
		return
	var id := node.get_instance_id()
	node_refs[id]=weakref(node)
	if not originals.has(id):
		var original := {}
		if node is Light3D: original={"shadow":node.shadow_enabled,"fade":node.distance_fade_enabled,"fade_shadow":node.distance_fade_shadow,"visible":node.visible,"range":node.spot_range if node is SpotLight3D else 0.0,"energy":node.light_energy,"color":node.light_color,"specular":node.light_specular,"blur":node.shadow_blur}
		elif node is ReflectionProbe or node is GPUParticles3D or node is CPUParticles3D: original={"visible":node.visible}
		elif node is Camera3D: original={"far":node.far}
		elif node is WorldEnvironment and node.environment!=null:
			var env: Environment = node.environment
			original={"reflected":env.reflected_light_source,"ssr":env.ssr_enabled,"glow":env.glow_enabled,"ssao":env.ssao_enabled,"ssil":env.ssil_enabled,"fog":env.volumetric_fog_enabled,"exposure":env.tonemap_exposure,"sdfgi":env.sdfgi_enabled,"glow_threshold":env.glow_hdr_threshold}
			for key in ENVIRONMENT_CONTROLS:
				original[key] = env.get(key)
		elif node is GeometryInstance3D: original={"end":node.visibility_range_end,"cast":node.cast_shadow,"fine":_fine_detail(node)}
		originals[id]=original
	var saved: Dictionary=originals[id]
	var visuals := world.get_node_or_null("CampusVisualSettings") if is_instance_valid(world) else null
	if node is Light3D:
		var quality := int(options.shadow_quality) if options.shadows else 0
		node.shadow_enabled=InteriorShadows.enabled(node,bool(saved.shadow),quality)
		node.shadow_blur=float(saved.blur)*[1.0,.65,.85,1.0][quality]
		if node is DirectionalLight3D and node.shadow_enabled:
			node.directional_shadow_mode=DirectionalLight3D.SHADOW_ORTHOGONAL if quality==1 else DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
			node.directional_shadow_blend_splits = true
			node.directional_shadow_fade_start = 0.65
			if node.name == "Sun" and node != _sun:
				_sun = node
				_sun_shadow_distance = node.directional_shadow_max_distance
		elif node.get_meta("room_fixture",false):
			var lighting := int(options.lighting_quality)
			node.light_energy=float(saved.energy)*[.84,1.0,1.04,1.65][lighting]*float(options.indoor_intensity)
			if node is SpotLight3D:node.spot_range=float(saved.range)
			var tint: Color=saved.color
			match options.lighting_tone:
				"Cool":tint=tint.lerp(Color("e5edff"),.45)
				"Warm":tint=tint.lerp(Color("ffdab5"),.42)
			node.light_color=tint
			if visuals != null:
				node.light_energy *= visuals.fixture_energy
				node.light_color *= visuals.fixture_tint
			node.light_specular=float(saved.specular)*([.7,1.0,1.12,1.18][lighting] if options.reflections else 0.0)
		if not node is DirectionalLight3D:
			# Keep fixture lighting visible at its authored distance, while
			# avoiding shadow-map work for fixtures farther down the corridor.
			node.distance_fade_enabled=bool(saved.fade) or node.get_meta("ultra_distance_fade",false) or node.shadow_enabled
			var reach: float=node.spot_range if node is SpotLight3D else node.omni_range
			node.distance_fade_shadow=minf(float(saved.fade_shadow),clampf(reach+6.0,11.0,21.0))
			if node is SpotLight3D and node.get_meta("room_fixture", false):
				# The light still illuminates its full range. Only distant dynamic shadows fade.
				node.distance_fade_shadow = minf(node.distance_fade_shadow, INDOOR_FIXTURE_SHADOW_DISTANCE)
		# Room fixtures provide basic illumination even with accent lights disabled.
		if not node is DirectionalLight3D:
			node.visible = bool(saved.visible) and int(options.lighting_quality)>=int(node.get_meta("fixture_quality_min",0)) and (bool(options.lights) or bool(node.get_meta("room_fixture", false)))
		if node.name == "Sun" or node.get_meta("room_fixture", false):
			if not saved.has("opacity"):
				saved["opacity"] = node.shadow_opacity
			node.shadow_opacity = float(saved.opacity)
			if visuals != null:
				node.shadow_opacity *= visuals.shadow_opacity
				node.shadow_blur *= visuals.shadow_softness
		if node is SpotLight3D and node.get_meta("room_fixture", false) and node.shadow_enabled:
			_fixture_shadow_opacity[id] = node.shadow_opacity
		else:
			_fixture_shadow_opacity.erase(id)
	elif node is ReflectionProbe: node.visible=bool(saved.visible) and options.reflections and (not node.has_meta("room_probe") or int(options.lighting_quality)>=3)
	elif node is GPUParticles3D or node is CPUParticles3D: node.visible=bool(saved.visible) and options.effects
	elif node is Camera3D: node.far=minf(float(saved.far),float(options.view_distance))
	elif node is WorldEnvironment and node.environment!=null:
		_apply_environment(node, saved, visuals != null and bool(visuals.use_scene_environment_effects))
	elif node is GeometryInstance3D:
		if node.get_meta("floor_contact_shadows",false):node.visible=bool(options.shadows)
		if node.get_meta("satin_floor",false) and node.material_override is ShaderMaterial:
			var material: ShaderMaterial=node.material_override
			material.set_shader_parameter("satin_reflections",bool(options.reflections))
			material.set_shader_parameter("area_reflections",int(options.lighting_quality)>=3)
			material.set_shader_parameter("fixture_intensity",float(options.indoor_intensity))
			var tint: Color={"Cool":Color("fff0d8"),"Neutral":Color("ffca91"),"Warm":Color("ffb66f")}[options.lighting_tone]
			material.set_shader_parameter("reflection_tint",tint)
		node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if bool(saved.get("fine",false)) and not options.detail_shadows else int(saved.get("cast",node.cast_shadow))
		node.visibility_range_end=minf(float(saved.end),float(options.view_distance)) if float(saved.end)>0 else float(options.view_distance)
		if node is MeshInstance3D and node.mesh!=null:
			if not texture_materials.has(id):
				var copies: Array=[]
				if node.material_override is BaseMaterial3D:
					var copy: BaseMaterial3D=_material_copy(node.material_override)
					node.material_override=copy; copies.append(copy)
				else:
					for surface in node.mesh.get_surface_count():
						var material: Material=node.get_active_material(surface)
						if material is BaseMaterial3D:
							var copy: BaseMaterial3D=_material_copy(material)
							node.set_surface_override_material(surface,copy); copies.append(copy)
				texture_materials[id]=copies
			for material in texture_materials[id]: material.texture_filter=BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS if options.texture==0 else BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	if recursive:
		for child in node.get_children(): register_node(child)
func apply_scene_preview() -> void:
	_preview_scene_effects = true
	apply()

func _apply_environment(node: WorldEnvironment, saved: Dictionary, scene_effects: bool) -> void:
	var env := node.environment
	var author_preview := scene_effects and _preview_scene_effects
	var authored := quality_preset == "Ultra" or (quality_preset == "Custom" and int(options.lighting_quality) == 3) or author_preview
	var forward := RenderingServer.get_current_rendering_method() == "forward_plus"
	var bloom_level := int(options.bloom_quality) if options.bloom else 0
	var authored_gi := quality_preset == "Ultra" or author_preview
	env.sdfgi_enabled = forward and (bool(saved.sdfgi) if authored_gi else bool(options.sdfgi))
	env.tonemap_exposure = float(saved.exposure) * (1.0 if authored else float(options.brightness))
	env.ssr_enabled = forward and (bool(saved.ssr) if authored else bool(saved.ssr) and int(options.lighting_quality) >= 2 and bool(options.reflections))
	env.reflected_light_source = int(saved.reflected) if authored or options.reflections else Environment.REFLECTION_SOURCE_DISABLED
	env.glow_enabled = bool(saved.glow) and (authored or bloom_level > 0)
	env.glow_hdr_threshold = float(saved.glow_threshold) if authored else [1.0, 0.93, 0.85, 0.78][bloom_level]
	env.ssao_enabled = forward and (bool(saved.ssao) if authored else (bool(saved.ssao) or int(options.lighting_quality) >= 3) and bool(options.effects))
	env.ssil_enabled = forward and bool(saved.ssil) and (authored or (bool(options.effects) and int(options.lighting_quality) >= 2))
	env.volumetric_fog_enabled = forward and bool(saved.fog) and (authored or (bool(options.effects) and int(options.lighting_quality) >= 2))
	for key in ENVIRONMENT_CONTROLS:
		if key == "volumetric_fog_density":
			continue
		var value: Variant = options.get(key, saved[key])
		if not authored and not options.has(key):
			if key == "glow_intensity":
				value = [0.0, 0.65, 0.98, 1.35][bloom_level]
			elif key == "glow_bloom":
				value = 0.0
		if env.get(key) != value:
			env.set(key, value)
	if node.get_parent() == world:
		_fog_environment = env
		_fog_density = clampf(float(options.get("volumetric_fog_density", saved.volumetric_fog_density)), 0.0, MAX_FOG_DENSITY)
		_update_fog()

func _process(delta: float) -> void:
	_fog_clock += delta
	if _fog_clock >= 0.1:
		_fog_clock = 0.0
		_update_fog()
		_update_sun_shadow_distance()
		_update_fixture_shadow_opacity()

func _update_fixture_shadow_opacity() -> void:
	if not is_instance_valid(viewport):
		return
	var camera := viewport.get_camera_3d()
	if camera == null:
		return
	var eye := camera.global_position
	for id in _fixture_shadow_opacity:
		var light := node_refs[id].get_ref() as SpotLight3D
		if not is_instance_valid(light) or not light.is_visible_in_tree():
			continue
		# Forward+ stops drawing the shadow at its cutoff. Reach zero opacity first.
		var cutoff := light.distance_fade_shadow
		var distance := eye.distance_to(light.global_position)
		var opacity: float = _fixture_shadow_opacity[id] * (1.0 - smoothstep(maxf(0.0, cutoff - FIXTURE_SHADOW_BLEND_DISTANCE), cutoff, distance))
		if not is_equal_approx(light.shadow_opacity, opacity):
			light.shadow_opacity = opacity

func _update_sun_shadow_distance() -> void:
	if not is_instance_valid(_sun) or not _sun.shadow_enabled or not is_instance_valid(viewport):
		return
	var camera := viewport.get_camera_3d()
	if camera == null:
		return
	# The facade blocks the interior from the exterior directional light.
	# Blend to the outdoor range in the lobby so the distance does not jump at the door.
	var interior := smoothstep(-11.0, -3.0, camera.global_position.z)
	var outdoors := _sun_shadow_distance
	var bake := world.get_node_or_null("CampusBakedLighting") if is_instance_valid(world) else null
	if bake != null and bake.has_active_sun_mask():
		outdoors = minf(outdoors, BAKED_OUTDOOR_SUN_SHADOW_DISTANCE)
	var distance := lerpf(outdoors, minf(_sun_shadow_distance, INDOOR_SUN_SHADOW_DISTANCE), interior)
	if not is_equal_approx(_sun.directional_shadow_max_distance, distance):
		_sun.directional_shadow_max_distance = distance

func _update_fog() -> void:
	if _fog_environment == null or not is_instance_valid(viewport):
		return
	var camera := viewport.get_camera_3d()
	var factor := 1.0
	if camera != null:
		# The campus front threshold spans the corridor at z = -11.
		factor = smoothstep(-11.0, -3.0, camera.global_position.z)
	var density := _fog_density * factor
	if not is_equal_approx(_fog_environment.volumetric_fog_density, density):
		_fog_environment.volumetric_fog_density = density

func build_controls(parent: VBoxContainer) -> void:
	var body := Layout.section(parent, "Graphics", "Applies immediately • choose a preset or tune each setting", "palette")
	var presets := Layout.flow(body)
	for level in PRESETS.slice(0,4):
		var b := UI.action(level, "palette", func():preset(level)); presets.add_child(b)
	var quality := Layout.section(body, "Image quality", "Render scale, filtering and anti-aliasing", "settings")
	var environment := Layout.section(body, "World detail", "Lighting, effects and local presentation", "home")
	for key in DEFAULTS:
		if key in ["shadows","bloom","brightness","indoor_intensity"]: continue
		var row := VBoxContainer.new(); (quality if key in ["render_scale","texture","aa"] else environment).add_child(row)
		var label := Label.new(); label.text={"bloom_quality":"Bloom","lighting_quality":"Lighting quality","shadow_quality":"Shadow quality","reflections":"Reflections and highlights","detail_shadows":"Fine-detail shadows","texture":"Texture filtering","aa":"Anti-aliasing","npc_density":"NPC density"}.get(key,key.replace("_"," ").capitalize()); label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; row.add_child(label)
		var select := OptionButton.new(); select.size_flags_horizontal=Control.SIZE_EXPAND_FILL; select.custom_minimum_size.y=44; select.tooltip_text=label.text; row.add_child(select)
		var values: Array=[]; var names: Array=[]
		match key:
			"render_scale": values=[0.5,0.65,0.75,0.85,1.0]; names=["50%","65%","75%","85%","100%"]
			"texture": values=[0,1,2]; names=["Nearest mipmaps","Filtered · 4×","Filtered · 16×"]
			"aa": values=[0,1,2,3]; names=["Off","MSAA 2×","MSAA 4×","MSAA 8×"]
			"lighting_tone": values=["Cool","Neutral","Warm"]; names=values
			"lighting_quality": values=[0,1,2,3]; names=["Low","Medium","High","Ultra"]
			"shadow_quality","bloom_quality": values=[0,1,2,3]; names=["Off","Low","Medium","High"]
			"npc_density": values=["Off","Low","Medium","High"]; names=values
			"view_distance": values=[30.0,60.0,100.0,120.0,180.0,240.0]; names=["30 m","60 m","100 m","120 m","180 m","240 m"]
			_: values=[false,true]; names=["Off","On"]
		if key=="npc_density":
			density_controls.append(select); select.disabled=not (is_instance_valid(crowd) and crowd.has_method("set_density")); select.tooltip_text="Requires the campus local crowd module. Saved density applies when it is connected."
		for name in names: select.add_item(str(name))
		select.select(maxi(values.find(options[key]),0))
		select.item_selected.connect(func(index):set_option(key,values[index]))
		changed.connect(func(_o):select.select(maxi(values.find(options[key]),0)))
	var advanced := Layout.section(body, "Advanced lighting and color", "Fine-tune individual effects", "palette")
	for key in ENVIRONMENT_CONTROLS:
		_add_environment_control(advanced, key)

func _add_environment_control(parent: VBoxContainer, key: String) -> void:
	var spec: Array = ENVIRONMENT_CONTROLS[key]
	var row := VBoxContainer.new()
	parent.add_child(row)
	var label := Label.new()
	label.text = spec[0]
	row.add_child(label)
	if key == "glow_blend_mode":
		var select := OptionButton.new()
		select.add_item("Screen", Environment.GLOW_BLEND_MODE_SCREEN)
		select.add_item("Soft Light", Environment.GLOW_BLEND_MODE_SOFTLIGHT)
		row.add_child(select)
		var refresh := func(_options): select.select(select.get_item_index(int(environment_value(key))))
		refresh.call(options)
		changed.connect(refresh)
		select.item_selected.connect(func(index): set_option(key, select.get_item_id(index)))
		return
	var number := SpinBox.new()
	number.min_value = spec[1]
	number.max_value = spec[2]
	number.step = spec[3]
	row.add_child(number)
	number.set_value_no_signal(float(environment_value(key)))
	changed.connect(func(_options): number.set_value_no_signal(float(environment_value(key))))
	number.value_changed.connect(func(value): set_option(key, value))

func environment_value(key: String) -> Variant:
	var node := world.get_node_or_null("WorldEnvironment") as WorldEnvironment
	if node == null or node.environment == null:
		return ENVIRONMENT_CONTROLS[key][1] if key != "glow_blend_mode" else Environment.GLOW_BLEND_MODE_SCREEN
	var value: Variant = node.environment.get(key)
	if key == "volumetric_fog_density":
		var authored: Dictionary = originals.get(node.get_instance_id(), {})
		value = minf(float(options.get(key, authored.get(key, value))), MAX_FOG_DENSITY)
	return value

func _fine_detail(node: GeometryInstance3D) -> bool:
	if node.has_meta("batch_fine_detail"):
		return bool(node.get_meta("batch_fine_detail"))
	# Printed text/schematic strokes and tiny fixtures retain their lit appearance;
	# only their contribution to the shadow map is optional. Large equipment,
	# furniture, people and the room keep ordinary shadows enabled.
	if node is Label3D:return true
	if not node is MeshInstance3D or node.mesh==null:return false
	var size: Vector3=node.mesh.get_aabb().size*node.scale.abs()
	return maxf(size.x,maxf(size.y,size.z))<=0.25 or minf(size.x,minf(size.y,size.z))<=0.012
