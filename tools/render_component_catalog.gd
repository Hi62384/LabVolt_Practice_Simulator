extends SceneTree
## Regenerate the store's thumbnails from the same procedural geometry used on deployed breadboards.
const ROOT := "res://assets/electronics/component_shop_ui/"
const PARTS := {
	"resistor":"r1000", "capacitor":"c1.0", "inductor":"l10", "diode":"diode",
	"led":"led", "led_green":"led_green", "led_blue":"led_blue", "led_yellow":"led_yellow",
	"transistor":"npn", "button":"button", "switch":"toggle", "potentiometer":"pot10k",
	"battery":"battery", "speaker":"speaker", "chip":"hc00", "opamp":"opamp", "board":"lv_mcu",
}

func _initialize() -> void:
	call_deferred("render")

func render() -> void:
	var stage := SubViewport.new()
	stage.size = Vector2i(256, 256)
	stage.own_world_3d = true
	stage.transparent_bg = true
	stage.msaa_3d = Viewport.MSAA_4X
	root.add_child(stage)
	var builder := preload("res://scripts/equipment_builder.gd").new()
	stage.add_child(builder)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color("e4efff")
	environment.environment.ambient_light_energy = .68
	stage.add_child(environment)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-52, -37, 0)
	key.light_energy = 1.25
	stage.add_child(key)
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-38, 141, 0)
	rim.light_energy = .36
	stage.add_child(rim)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.position = Vector3(.19,.18,.27)
	camera.size = .15
	stage.add_child(camera)
	camera.look_at(Vector3(0, .027, 0))
	var catalog := preload("res://scripts/electronics_catalog.gd").all()
	for family in PARTS:
		var type: String = PARTS[family]
		if not catalog.has(type):continue
		var model: Dictionary = catalog[type]
		var parts := preload("res://scripts/board_components_3d.gd").new()
		stage.add_child(parts)
		var pins: Array[Vector2] = []
		var count: int = model.get("pins", []).size()
		var side := ceili(count / 2.0)
		for index in count:
			var y := 220.0 if count == 2 else 182.0 if index < side else 258.0
			var spacing := 31.0 if count == 2 else 12.0
			var x := 500.0 + ((index % side) - (side - 1) * .5) * spacing if count != 2 else 500.0 + (index - .5) * spacing * 2.0
			pins.append(Vector2(x, y))
		parts.build_device(builder, {"id":"sample", "type":type, "center":Vector2(500,220), "pins":pins}, model)
		for child in parts.get_children():
			if child is Label3D:child.hide()
		if parts.lights.has("sample"):
			var entry: Dictionary = parts.lights.sample
			entry.mesh.material_override.albedo_color = entry.color
		stage.render_target_update_mode = SubViewport.UPDATE_ONCE
		await process_frame
		await RenderingServer.frame_post_draw
		var picture := stage.get_texture().get_image()
		var error := picture.save_png(ROOT + family + ".png")
		if error != OK:
			push_error(error_string(error))
			quit(1)
			return
		stage.remove_child(parts)
		parts.queue_free()
	print("Rendered circuit component catalog thumbnails")
	quit()

