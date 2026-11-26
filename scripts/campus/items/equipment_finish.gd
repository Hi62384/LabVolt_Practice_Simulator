extends RefCounted

const Config=preload("res://scripts/campus/items/equipment_configuration.gd")
const Decoration=preload("res://scripts/campus/items/decoration_surface.gd")

static func apply_finish(model: Node3D, kind: String, configuration: Dictionary) -> void:
	if configuration.is_empty():return
	var surface: Vector2=Config.value(kind,configuration,"appearance","finish",Vector2(.45,0.0))
	_paint(model.get_meta("equipment_shell",[]),Color(Config.value(kind,configuration,"appearance","shell","667b84")),surface)
	_paint(model.get_meta("equipment_trim",[]),Color(Config.value(kind,configuration,"appearance","trim","b7c2ca")),surface)
	for part in model.get_meta("equipment_shell",[]):
		if not part.has_meta("material_segment"):part.set_meta("material_segment","case")
	for part in model.get_meta("equipment_trim",[]):
		if not part.has_meta("material_segment"):part.set_meta("material_segment","trim")
	Config.Materials.apply(model,configuration)
	if kind==Config.LAPTOP:_backlight(model,configuration.get("backlight",[]))
	var anchor: Dictionary=model.get_meta("decoration_anchor",{})
	if not anchor.is_empty():Decoration.attach(anchor.part,configuration.get("decoration",[]),anchor.position,anchor.rotation,anchor.area,1,model)

static func _paint(parts: Array, tint: Color, surface: Vector2) -> void:
	for part in parts:
		var material: StandardMaterial3D=part.material_override
		# Laptop geometry shares materials across the lab. Customize only this instance.
		if not part.has_meta("custom_material"):
			material=material.duplicate()
			part.material_override=material
			part.set_meta("custom_material",true)
		material.albedo_color=tint
		material.roughness=surface.x
		material.metallic=surface.y

static func _backlight(model: Node3D, choices: Array) -> void:
	var keys: MultiMeshInstance3D=model.get_meta("equipment_keyboard") if model.has_meta("equipment_keyboard") else null
	if not is_instance_valid(keys):return
	if choices.is_empty():
		if keys.material_override is ShaderMaterial:keys.material_override=keys.get_meta("unlit_material")
		return
	var material:=keys.material_override as ShaderMaterial
	if material==null:
		material=ShaderMaterial.new()
		material.shader=preload("res://scripts/campus/items/keyboard_backlight.gdshader")
		keys.material_override=material
	var colors:=PackedColorArray()
	for offset in Config.BACKLIGHT_COLORS.size():
		colors.append(Color(Config.BACKLIGHT_COLORS[int(choices[offset%choices.size()])]))
	material.set_shader_parameter("colors",colors)
	material.set_shader_parameter("color_count",choices.size())

static func set_backlight_power(model: Node3D, powered: bool) -> void:
	var keys: MultiMeshInstance3D=model.get_meta("equipment_keyboard") if model.has_meta("equipment_keyboard") else null
	if is_instance_valid(keys) and keys.material_override is ShaderMaterial:
		var material: ShaderMaterial=keys.material_override
		if material.get_shader_parameter("enabled")!=powered:material.set_shader_parameter("enabled",powered)
