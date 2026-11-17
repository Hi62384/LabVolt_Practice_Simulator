extends SceneTree
func _initialize() -> void:call_deferred("run")
func button(node: Node,title: String) -> Button:
	for item in node.find_children("*","Button",true,false):
		if item.text==title and item.is_visible_in_tree():return item
	return null
func run() -> void:
	var game=load("res://scenes/Main.tscn").instantiate();root.add_child(game)
	for i in 4:await process_frame
	var single:=button(game.front.body,"Singleplayer")
	if single==null:push_error("Singleplayer missing");quit(1);return
	single.pressed.emit();await process_frame
	var play:=button(game.front.body,"Play")
	if play==null:push_error("Play missing");quit(1);return
	play.pressed.emit();await process_frame
	game.player.global_position=Vector3(26,5.1,65)
	game.campus.set_viewer_position(game.player.global_position);game.campus.request_room("computer_commons")
	for i in 60:await process_frame
	var target: Node3D
	for node in game.campus.find_children("*","StaticBody3D",true,false):
		if node.get_meta("role","")=="public_computer_usb" and str(node.get_meta("station","")).begins_with("commons_"):target=node;break
	if target==null:push_error("USB port target missing");quit(1);return
	var shape: CollisionShape3D=target.get_child(0)
	var point: Vector3=shape.global_position
	var camera:=Camera3D.new();game.add_child(camera);camera.current=true;camera.fov=60
	camera.global_position=point+target.global_basis.z*.8+Vector3(0,.05,0);camera.look_at(point)
	await physics_frame
	var ray:=PhysicsRayQueryParameters3D.create(camera.global_position,point,4)
	var hit: Dictionary=game.get_world_3d().direct_space_state.intersect_ray(ray)
	if hit.is_empty() or hit.collider!=target:push_error("USB port is not reachable by the interaction ray");quit(1);return
	await process_frame;camera.make_current();await RenderingServer.frame_post_draw
	var error:=root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://.godot/usb-port-visual.png"))
	print("USB_PORT_VISUAL ","PASS" if error==OK else "FAIL")
	game.front.leave_game();game.queue_free();await process_frame;quit(0 if error==OK else 1)
