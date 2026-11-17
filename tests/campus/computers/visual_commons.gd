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
	for i in 90:await process_frame
	if game.campus.registry.locate(game.player.global_position)!="computer_commons":push_error("Commons is not registered");quit(1);return
	var count:=0
	for id in game.computers.stations:
		if str(id).begins_with("commons_"):count+=1
	if count!=8:push_error("Commons workstations missing");quit(1);return
	var door: Node=game.campus.room_roots.computer_commons.get_node("Door_computer_commons")
	door._set_open(true)
	await create_timer(.8).timeout;await physics_frame
	var ray:=PhysicsRayQueryParameters3D.create(Vector3(14.2,6,65),Vector3(18,6,65),1)
	ray.exclude=[game.player.get_rid()]
	var hit: Dictionary=game.get_world_3d().direct_space_state.intersect_ray(ray)
	if not hit.is_empty():push_error("Commons entrance blocked by "+str(hit.collider.get_path())+": "+str(hit));quit(1);return
	var camera:=Camera3D.new();game.add_child(camera);camera.current=true;camera.fov=72
	camera.global_position=Vector3(17.3,6.7,66.5);camera.look_at(Vector3(31,6,63))
	await process_frame;await RenderingServer.frame_post_draw
	var error:=root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://.godot/computer-commons.png"))
	print("COMPUTER_COMMONS ","PASS" if error==OK else "FAIL")
	game.front.leave_game();game.queue_free();await process_frame;quit(0 if error==OK else 1)
