extends RefCounted

const Config=preload("res://scripts/campus/items/equipment_configuration.gd")

static func apply_finish(model: Node3D, kind: String, configuration: Dictionary) -> void:
	if configuration.is_empty():return
	var surface: Vector2=Config.value(kind,configuration,"appearance","finish",Vector2(.45,0.0))
	_paint(model.get_meta("equipment_shell",[]),Color(Config.value(kind,configuration,"appearance","shell","667b84")),surface)
	_paint(model.get_meta("equipment_trim",[]),Color(Config.value(kind,configuration,"appearance","trim","b7c2ca")),surface)

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
