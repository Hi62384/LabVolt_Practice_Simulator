extends SceneTree

const Config = preload("res://scripts/campus/items/equipment_configuration.gd")
const Surface = preload("res://scripts/campus/items/decoration_surface.gd")
const Document = preload("res://scripts/campus/items/decoration_document.gd")
const Dialog = preload("res://scripts/ui/store_bundles_equipment/equipment_configurator.gd")

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	create_timer(55).timeout.connect(func():quit(1))
	var game: Node=load("res://scenes/Main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	var image:=Image.create_empty(64,32,false,Image.FORMAT_RGBA8)
	image.fill(Color("4488aa"))
	var data:=Document.encode(image)
	assert(Document.valid_image(data))
	assert(Document.import_image(image.save_png_to_buffer(),"png").get_size()==Vector2i(64,32))
	assert(Document.import_image(image.save_jpg_to_buffer(),"jpg").get_size()==Vector2i(64,32))
	assert(Document.import_image(image.save_webp_to_buffer(),"webp").get_size()==Vector2i(64,32))
	var layer:=Document.layer("image")
	layer.data=data
	layer.crop_left=.2
	layer.glow=.5
	layer.glow_color="66ffbb"
	layer.opacity=.8
	for kind in Config.DEFINITIONS:
		var dialog := Dialog.new()
		game.add_child(dialog)
		dialog.build(game.electronics.profile,func(_message:String):pass,{"kind":kind,"price":20,"name":kind},game.electronics._equipment_preview)
		dialog._show_stage(1)
		dialog.decoration_editor._add("image",data)
		dialog.decoration_editor._set_layer("crop_left",.2,false)
		dialog.decoration_editor._set_layer("glow",.5,false)
		dialog.decoration_editor._set_layer("glow_color","66ffbb",false)
		dialog.decoration_editor._set_layer("opacity",.8,false)
		assert(dialog.price.text=="$23")
		var surface := dialog.phone.find_child("DecorationSurface",true,false)
		assert(surface!=null and surface.get_child_count()==1,"Missing preview surface for "+kind)
		assert(is_equal_approx(surface.get_child(0).material_override.uv1_offset.x,.2))
		assert(surface.get_child(0).material_override.emission_enabled)
		var saved:=Config.quote(kind,20,JSON.parse_string(JSON.stringify(dialog.configuration)))
		assert(not saved.is_empty() and Config.same_configuration(kind,saved.configuration,dialog.configuration))
		var tampered: Dictionary=dialog.configuration.duplicate(true)
		tampered.decoration[0].size=8.0
		assert(Config.quote(kind,20,tampered).is_empty())
		dialog.decoration_editor._add("shape","")
		dialog.decoration_editor._set_layer("data","Stud",false)
		dialog.decoration_editor._undo()
		dialog.decoration_editor._undo()
		assert(dialog.configuration.decoration.size()==1)
		dialog.decoration_editor._save()
		dialog.decoration_editor._reset()
		assert(not dialog.configuration.has("decoration"))
		dialog.decoration_editor._load()
		assert(dialog.configuration.decoration[0].data==data)
		dialog.queue_free()
		await process_frame
	var incomplete:=Config.defaults(Config.PHONE)
	incomplete.decoration=[layer]
	var player=game.electronics.profile
	player.data.dollars=10000
	player.buy_smartphone("basic",6,"",incomplete)
	assert(player.operation_succeeded)
	var purchased: Dictionary=player.data.dorm.smartphones.values().back()
	var model:=Node3D.new()
	game.add_child(model)
	const Handset=preload("res://scripts/campus/phones/phone_handset.gd")
	Handset.build(model)
	Handset.apply_appearance(model,Config.phone_appearance(purchased))
	assert(model.has_node("DecorationSurface"))
	assert(model.get_node("DecorationSurface").rotation.y>3.0)
	var id: String=player.data.dorm.smartphones.keys().back()
	var updated:=incomplete.duplicate(true)
	updated.decoration[0].angle=25.0
	player.decorate_equipment(Config.PHONE,id,updated,incomplete)
	assert(player.operation_succeeded)
	assert(player.data.dorm.smartphones[id].configuration.decoration[0].angle==25.0)
	var wrong:=updated.duplicate(true)
	wrong.hardware.battery=2
	player.decorate_equipment(Config.PHONE,id,wrong,updated)
	assert(not player.operation_succeeded)
	if DisplayServer.get_name()!="headless":
		const Portraits=preload("res://scripts/ui/personal_inventory/equipment_portraits.gd")
		var empty:=Image.create_empty(128,96,false,Image.FORMAT_RGBA8)
		var fallback:=ImageTexture.create_from_image(empty)
		for kind in Config.DEFINITIONS:
			var options:=Config.defaults(kind)
			options.decoration=[layer]
			var picture:=Portraits.texture(kind,options,game.electronics._equipment_preview,fallback)
			while Portraits.rendering:await process_frame
			assert(not picture.get_image().is_invisible(),"Missing rendered inventory icon for "+kind)
	print("EQUIPMENT_DECORATION PASS")
	game.queue_free()
	await process_frame
	quit()
