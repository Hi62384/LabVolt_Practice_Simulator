extends SceneTree
func _initialize() -> void:call_deferred("run")
func button(node: Node,title: String) -> Button:
	for b in node.find_children("*","Button",true,false):
		if b.text==title and b.is_visible_in_tree():return b
	return null
func fail(message: String) -> void:push_error(message);quit(1)
func run() -> void:
	var args:=OS.get_cmdline_user_args()
	var tier: String=args[0] if not args.is_empty() else "basic"
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
	game.electronics.shop_section=2;game.electronics.open("shop");await process_frame
	var tier_data: Dictionary=preload("res://scripts/campus/computers/laptop_inventory.gd").TIERS[tier]
	var card: Node
	for label in game.electronics.screen.find_children("*","Label",true,false):
		if label.text==tier_data.name:card=label.get_parent();break
	if card==null:fail("Laptop shop card missing");return
	var details:=button(card,"Details")
	if details==null:fail("Laptop details missing");return
	details.pressed.emit();await process_frame
	var buy:=button(game.electronics.screen,"Buy for $%d"%int(tier_data.price))
	if buy==null:fail("Laptop buy button missing");return
	buy.pressed.emit();await process_frame
	if game.electronics.profile.data.dorm.get("portable_laptops",{}).size()!=1:fail("Laptop shop purchase failed");return
	game.electronics.close();await process_frame
	game.electronics.profile.buy_usb(8)
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
	var entry: Dictionary=game.portable_laptops.placed[id]
	var model: Node3D=entry.model
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
	game.camera.look_at(usb.global_position,Vector3.UP)
	await physics_frame
	ray=PhysicsRayQueryParameters3D.create(game.camera.global_position,usb.global_position,4)
	hit=game.get_world_3d().direct_space_state.intersect_ray(ray)
	if hit.get("collider")!=usb:fail("USB port cannot be targeted");return
	game.current_target=usb
	click.button_index=MOUSE_BUTTON_LEFT;game._input(click)
	if game.computers.stations[entry.station].power.usb.is_empty():fail("USB click failed");return
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
	game.current_target=body_for(model)
	click.button_index=MOUSE_BUTTON_RIGHT;game._input(click)
	if game.computers.local_snapshot.get("tier","")!=tier:fail("Desktop did not open");return
	await process_frame;await RenderingServer.frame_post_draw
	if root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://.godot/portable-desktop-%s.png"%tier))!=OK:fail("Desktop screenshot failed");return
	var exit:=InputEventKey.new();exit.keycode=KEY_ESCAPE;exit.physical_keycode=KEY_ESCAPE;exit.pressed=true
	game.computer_room_adapter.desktop._input(exit);await process_frame
	game.capture();game.current_target=power;click.button_index=MOUSE_BUTTON_LEFT;game._input(click)
	game.current_target=usb;game._input(click)
	if not game.computers.stations[entry.station].power.usb.is_empty():fail("USB removal failed");return
	game.current_target=body_for(model);game._input(click);game._input(click)
	if game.portable_laptops.placed.has(id):fail("Laptop pickup failed");return
	print("PORTABLE_INPUT PASS")
	game.front.leave_game();game.queue_free();await process_frame;quit()
func body_for(model: Node3D) -> StaticBody3D:
	for target in model.find_children("*","StaticBody3D",true,false):
		if target.get_meta("role","")=="portable_laptop":return target
	return null
