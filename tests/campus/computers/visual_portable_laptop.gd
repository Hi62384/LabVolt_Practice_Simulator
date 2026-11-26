extends SceneTree
const Config=preload("res://scripts/campus/items/equipment_configuration.gd")
func _initialize() -> void:call_deferred("run")
func button(node: Node,title: String) -> Button:
	for b in node.find_children("*","Button",true,false):
		if b.text==title and b.is_visible_in_tree():return b
	return null
func fail(message: String) -> void:push_error(message);quit(1)
func run() -> void:
	var args:=OS.get_cmdline_user_args()
	var configured:=args==PackedStringArray(["configured"])
	var tier: String=args[0] if not args.is_empty() and not configured else "basic"
	if tier not in ["basic","standard","premium"]:fail("Invalid tier");return
	var game=load("res://scenes/Main.tscn").instantiate();root.add_child(game)
	for i in 4:await process_frame
	var single:=button(game.front.body,"Singleplayer")
	if single==null:fail("Singleplayer missing");return
	single.pressed.emit();await process_frame
	var play:=button(game.front.body,"Play")
	if play==null:fail("Play missing");return
	play.pressed.emit()
	for i in 10:await process_frame
	game.electronics.profile.data.dollars=10000
	var laptop_configuration: Dictionary={}
	var usb_configuration: Dictionary={}
	if configured:
		laptop_configuration=Config.defaults(Config.LAPTOP,1)
		laptop_configuration.hardware.processor=2
		laptop_configuration.hardware.display=1
		laptop_configuration.hardware.battery=1
		laptop_configuration.appearance.shell=2
		usb_configuration=Config.defaults(Config.USB,1)
		usb_configuration.hardware.storage=2
		usb_configuration.hardware.read=1
		usb_configuration.appearance.shell=3
	game.electronics.profile.buy_portable_laptop(tier,6,"",laptop_configuration)
	if game.electronics.profile.data.dorm.get("portable_laptops",{}).size()!=1:fail("Laptop shop purchase failed");return
	game.electronics.profile.buy_usb(64 if configured else 8,6,"",usb_configuration)
	game.hotbar._sync_dorm_items()
	var id: String=game.electronics.profile.data.dorm.portable_laptops.keys()[0]
	for i in game.hotbar.slots.size():
		if game.hotbar.slots[i].get("id","")==id:game.hotbar.active=i
	game.camera.rotation.x=-.75
	game.capture()
	await physics_frame
	var key:=InputEventKey.new();key.keycode=KEY_F;key.physical_keycode=KEY_F;key.pressed=true
	game._input(key)
	await physics_frame
	if not game.portable_laptops.placed.has(id):fail("F did not place the laptop");return
	game.hotbar._sync_dorm_items()
	if game.hotbar.slots.any(func(slot):return slot.get("id","")==id):fail("Placed laptop still in hotbar");return
	var entry: Dictionary=game.portable_laptops.placed[id]
	var model: Node3D=entry.model
	if configured and not model.get_meta("equipment_shell")[0].material_override.albedo_color.is_equal_approx(Color("27745e")):
		fail("Placed laptop did not use the selected finish");return
	game.camera.look_at(model.global_position+Vector3(0,.08,0),Vector3.UP)
	await physics_frame
	var ray:=PhysicsRayQueryParameters3D.create(game.camera.global_position,model.global_position+Vector3(0,.04,0),4)
	var hit: Dictionary=game.get_world_3d().direct_space_state.intersect_ray(ray)
	if not hit.has("collider") or hit.collider.get_meta("portable_id","")!=id:fail("Placed laptop cannot be targeted");return
	game.current_target=hit.collider
	var click:=InputEventMouseButton.new();click.button_index=MOUSE_BUTTON_RIGHT;click.pressed=true
	game._input(click)
	if not entry.open:fail("Right-click did not open laptop");return
	await process_frame;await RenderingServer.frame_post_draw
	if root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://.godot/portable-laptop-visual.png"))!=OK:fail("Screenshot failed");return
	var usb: StaticBody3D
	for target in model.find_children("*","StaticBody3D",true,false):
		if target.get_meta("role","")=="public_computer_usb":usb=target
	if usb==null:fail("USB target missing");return
	for i in game.hotbar.slots.size():
		if game.hotbar.slots[i].get("kind","")=="usb":game.hotbar.active=i
	await create_timer(.1).timeout
	if not game.computer_room_adapter.held_usb.visible:fail("Equipped USB has no visible model");return
	game.camera.look_at(usb.global_position,Vector3.UP)
	await physics_frame
	ray=PhysicsRayQueryParameters3D.create(game.camera.global_position,usb.global_position,4)
	hit=game.get_world_3d().direct_space_state.intersect_ray(ray)
	if hit.get("collider")!=usb:fail("USB port cannot be targeted");return
	game.current_target=usb
	click.button_index=MOUSE_BUTTON_LEFT;game._input(click)
	if game.computers.stations[entry.station].power.usb.is_empty():fail("USB click failed");return
	if not game.computer_room_adapter.usb_visuals[id].visible:fail("Connected USB has no visible model");return
	if configured and not game.computer_room_adapter.usb_visuals[id].get_meta("equipment_shell")[0].material_override.albedo_color.is_equal_approx(Color("b95755")):
		fail("Connected USB did not use the selected finish");return
	var power: StaticBody3D
	for target in model.find_children("*","StaticBody3D",true,false):
		if target.get_meta("role","")=="public_computer_power":power=target
	if power==null:fail("Power target missing");return
	game.camera.look_at(power.global_position,Vector3.UP)
	await physics_frame
	ray=PhysicsRayQueryParameters3D.create(game.camera.global_position,power.global_position,4)
	hit=game.get_world_3d().direct_space_state.intersect_ray(ray)
	if hit.get("collider")!=power:fail("Power button cannot be targeted");return
	game.current_target=power
	click.button_index=MOUSE_BUTTON_LEFT;game._input(click)
	if not game.computers.stations[entry.station].power.powered:fail("Power click failed");return
	if configured:
		var remaining: int=game.computers.stations[id].ready_at-Time.get_ticks_msec()
		if remaining<=0 or remaining>350:fail("Configured laptop boot time was ignored");return
		if game.device_charging.devices["laptop:"+id].runtime_seconds!=1500.0:fail("Configured laptop battery was ignored");return
		await create_timer(.45).timeout
	if power.get_meta("label")!="Turn off laptop" or model.screen.material_override.albedo_texture==null:
		fail("Powered laptop did not show a display");return
	var lid_target: StaticBody3D=model.get_node("Lid").find_children("*","StaticBody3D",true,false)[0]
	ray=PhysicsRayQueryParameters3D.create(game.camera.global_position,lid_target.global_position,4)
	hit=game.get_world_3d().direct_space_state.intersect_ray(ray)
	if hit.get("collider")!=lid_target:fail("Open laptop screen cannot be targeted");return
	game.current_target=lid_target
	game.player.facility_seat={"station":"test/seat"}
	key.keycode=KEY_E;key.physical_keycode=KEY_E;game._input(key)
	if game.computers.local_snapshot.get("tier","")!=tier:fail("Desktop did not open");return
	if configured and not await _test_configured_usb(game):return
	game.player.facility_seat.clear()
	await process_frame;await RenderingServer.frame_post_draw
	if root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://.godot/portable-desktop-%s.png"%tier))!=OK:fail("Desktop screenshot failed");return
	var exit:=InputEventKey.new();exit.keycode=KEY_ESCAPE;exit.physical_keycode=KEY_ESCAPE;exit.pressed=true
	game.computer_room_adapter.desktop._input(exit);await process_frame
	game.capture();game.current_target=power;click.button_index=MOUSE_BUTTON_LEFT;game._input(click)
	game.current_target=usb;game._input(click)
	if not game.computers.stations[entry.station].power.usb.is_empty():fail("USB removal failed");return
	if game.computer_room_adapter.usb_visuals[id].visible:fail("Removed USB remained visible");return
	game.current_target=power;game._input(click)
	if not game.computers.stations[entry.station].power.powered:fail("Power did not turn back on");return
	game.current_target=body_for(model);game._input(click);game._input(click)
	if game.portable_laptops.placed.has(id):fail("Laptop pickup failed");return
	if game.computers.stations.has(id) or game.computers.local_snapshot.has("station"):fail("Picked-up laptop remained powered");return
	if not game.hotbar.slots.any(func(slot):return slot.get("id","")==id):fail("Picked-up laptop missing from hotbar");return
	var table:=fixture_surface(game,Vector3(800,.75,800),"table")
	fixture_surface(game,Vector3(800,1.25,800),"facility_seat")
	await physics_frame
	var placement_ray:=PhysicsRayQueryParameters3D.create(Vector3(800,1.6,800),Vector3(800,.6,800),5)
	if game.portable_laptops._placement_hit(placement_ray).get("collider")!=table:
		fail("Chair hitbox blocked a tabletop placement");return
	game.player.global_position=Vector3(13,0,-18)
	await physics_frame
	game.discarded_items.discard({"location":"hotbar","item":{"kind":"laptop","id":id}})
	if game.electronics.profile.data.dorm.portable_laptops.has(id) or not game.discarded_items.drops.values().any(func(drop):return drop.get("parcel",{}).get("item",{}).get("id","")==id):
		fail("Laptop Discard did not produce a recoverable drop");return
	await create_timer(.2).timeout
	print("PORTABLE_INPUT PASS")
	game.front.leave_game();game.queue_free();await process_frame;quit()

func fixture_surface(game: Node, at: Vector3, role: String) -> StaticBody3D:
	var body:=StaticBody3D.new()
	body.position=at
	body.set_meta("role",role)
	game.add_child(body)
	var shape:=BoxShape3D.new()
	shape.size=Vector3(.6,.1,.6)
	var hit:=CollisionShape3D.new()
	hit.shape=shape
	body.add_child(hit)
	return body
func body_for(model: Node3D) -> StaticBody3D:
	for target in model.find_children("*","StaticBody3D",true,false):
		if target.get_meta("role","")=="portable_laptop":return target
	return null
func _test_configured_usb(game: Node) -> bool:
	var computers: Node=game.computers
	if not is_equal_approx(float(computers.local_snapshot.get("display_scale",0)),.78):
		fail("Laptop display quality was ignored");return false
	if int(computers.local_snapshot.get("usb_storage",{}).get("capacity",0))!=64*1048576:
		fail("USB storage capacity was ignored");return false
	var bytes: PackedByteArray="%PDF-1.7\n".to_ascii_buffer()
	bytes.resize(1048576)
	var path:="Downloads/rate-test.pdf"
	computers.last_request.erase(1)
	var lease: int=computers.local_snapshot.lease
	var started:=Time.get_ticks_msec()
	computers.request({"op":"download","lease":lease,"revision":computers.local_snapshot.revision,"name":"rate-test.pdf","bytes":bytes})
	while not computers.local_snapshot.get("binary_files",{}).has(path) and Time.get_ticks_msec()-started<3000:
		await process_frame
	var write_ms:=Time.get_ticks_msec()-started
	if not computers.local_snapshot.get("binary_files",{}).has(path) or write_ms<235:
		fail("The file did not save at the selected USB write rate");return false
	var result: Array[PackedByteArray]=[]
	var received:=func(_path: String,data: PackedByteArray):result.append(data)
	computers.file_opened.connect(received,CONNECT_ONE_SHOT)
	computers.last_request.erase(1)
	started=Time.get_ticks_msec()
	computers.request({"op":"read_file","lease":lease,"revision":computers.local_snapshot.revision,"path":path})
	while result.is_empty() and Time.get_ticks_msec()-started<3000:await process_frame
	var read_ms:=Time.get_ticks_msec()-started
	if result.is_empty() or result[0]!=bytes or read_ms<70:
		fail("The file did not open at the selected USB read rate");return false
	print("CONFIGURED_USB_IO write=",write_ms," ms read=",read_ms," ms")
	return true
