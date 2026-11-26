extends SceneTree

const Config=preload("res://scripts/campus/items/equipment_configuration.gd")
const Photos=preload("res://scripts/campus/phones/photo_library.gd")
const Finish=preload("res://scripts/campus/items/equipment_finish.gd")
const Viewer=preload("res://scripts/campus/computers/file_viewer.gd")

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	create_timer(45).timeout.connect(func():push_error("Device hardware test timed out");quit(1))
	var game: Node=load("res://scenes/Main.tscn").instantiate()
	root.add_child(game)
	for frame in 5:await process_frame
	_button(game.front.body,"Singleplayer").pressed.emit()
	await process_frame
	_button(game.front.body,"Play").pressed.emit()
	for frame in 4:await process_frame
	var profile: RefCounted=game.electronics.profile
	profile.data.dollars=10000
	var config:=Config.defaults(Config.PHONE)
	profile.buy_smartphone("basic",6,"",config)
	assert(profile.operation_succeeded)
	var id: String=profile.data.dorm.smartphones.keys()[0]
	game.hotbar._sync_dorm_items()
	var slot: int=game.hotbar.slots.find_custom(func(item):return item.get("id","")==id)
	assert(slot>=0)
	game.hotbar.active=slot
	var phone: Node=game.smartphones
	phone.open()
	phone._toggle_power(id)
	var load_control: Node=phone.performance
	load_control.set_process(false)
	assert(load_control.quality==0)
	phone._switch("Calculator")
	assert(phone.status.text=="Opening Calculator…" and phone.content.get_child_count()==0)
	load_control._process(6.0)
	assert(phone.content.get_child_count()==0)
	load_control._process(.6)
	var calculator: Control=phone.content.get_child(0)
	assert(calculator!=null)
	_button(calculator,"7").pressed.emit()
	assert(calculator.display.text.is_empty())
	load_control._process(1.4)
	assert(calculator.display.text=="7")
	load_control.event_in=0.0
	load_control._process(.01)
	assert(load_control.frozen and phone.frozen_overlay.visible)
	for seed_value in 100:
		load_control.rng.seed=seed_value
		if load_control.rng.randf()<.35:
			load_control.rng.seed=seed_value
			break
	load_control.event_in=0.0
	load_control._process(.01)
	assert(not phone.is_powered(id))
	phone._toggle_power(id)
	phone.close()
	await phone.capture()
	var owner: String=profile.data.dorm.owner
	var photos:=Photos.list(owner,id)
	assert(photos.photos.size()==1)
	var captured: Image=Photos.load_photo(owner,id,photos.photos[0].id).image
	assert(captured.get_size()==Vector2i(480,360))
	var laptop_config:=Config.defaults(Config.LAPTOP)
	laptop_config.backlight=[1,3,6]
	laptop_config.hardware.performance=4
	laptop_config.hardware.audio_quality=1
	var priced:=Config.quote(Config.LAPTOP,600,laptop_config)
	assert(priced.configuration.backlight==[1,3,6] and priced.appearance_cost==36)
	var fake:=laptop_config.duplicate(true)
	fake.backlight=[1,1]
	assert(Config.quote(Config.LAPTOP,600,fake).is_empty())
	var model:=Node3D.new()
	game.add_child(model)
	game.ac_laptops._build_laptop(model,-1)
	Finish.apply_finish(model,Config.LAPTOP,laptop_config)
	var keys: MultiMeshInstance3D=model.get_meta("equipment_keyboard")
	var shader:=keys.material_override as ShaderMaterial
	assert(shader!=null and shader.get_shader_parameter("color_count")==3)
	Finish.set_backlight_power(model,false)
	assert(shader.get_shader_parameter("enabled")==false)
	Finish.set_backlight_power(model,true)
	assert(shader.get_shader_parameter("enabled")==true)
	RenderingServer.force_draw()
	var viewer:=Viewer.new()
	root.add_child(viewer)
	viewer.playback_quality=1
	var bus:=AudioServer.get_bus_index(viewer._audio_output())
	assert(bus>0 and AudioServer.get_bus_effect_count(bus)==2)
	viewer.free()
	load_control.configure("test-max",4)
	var state:={"called":false}
	load_control.submit(func():state.called=true)
	assert(state.called and not load_control.is_processing())
	print("DEVICE_HARDWARE PASS")
	game.queue_free()
	await process_frame
	quit()

func _button(parent: Node,caption: String) -> Button:
	for candidate in parent.find_children("*","Button",true,false):
		if candidate.text==caption and candidate.is_visible_in_tree():return candidate
	return null
