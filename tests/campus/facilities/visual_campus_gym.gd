extends SceneTree
func _initialize() -> void: call_deferred("run")
func button(node: Node, text: String) -> Button:
	for item in node.find_children("*", "Button", true, false):
		if item.text==text and item.is_visible_in_tree(): return item
	return null
func run() -> void:
	var game=load("res://scenes/Main.tscn").instantiate(); root.add_child(game)
	for i in 4: await process_frame
	var single:=button(game.front.body,"Singleplayer")
	if single==null: push_error("Singleplayer missing"); quit(1); return
	single.pressed.emit(); await process_frame
	var play:=button(game.front.body,"Play")
	if play==null: push_error("Play missing"); quit(1); return
	play.pressed.emit(); await process_frame
	game.player.global_position=Vector3(0,.1,33)
	game.campus.set_viewer_position(game.player.global_position)
	game.campus.request_room("gym")
	for i in 90: await process_frame
	await physics_frame
	var space: PhysicsDirectSpaceState3D=game.get_world_3d().direct_space_state
	var aisle:=PhysicsRayQueryParameters3D.create(Vector3(-8,.9,33),Vector3(6,.9,33),1)
	aisle.exclude=[game.player.get_rid()]
	var obstruction:=space.intersect_ray(aisle)
	if not obstruction.is_empty():
		push_error("Gym central aisle blocked: "+str(obstruction));quit(1);return
	var rack:=PhysicsRayQueryParameters3D.create(Vector3(-1.4,1.1,30),Vector3(-1.4,1.1,32),1)
	rack.exclude=[game.player.get_rid()]
	if space.intersect_ray(rack).is_empty():
		push_error("Gym pull-up rack lacks physical collision");quit(1);return
	var camera:=Camera3D.new(); game.add_child(camera); camera.current=true; camera.fov=72
	var shots:=[{"at":Vector3(-8,1.7,28.2),"look":Vector3(4,1.1,36)}, {"at":Vector3(8,1.7,37.8),"look":Vector3(-4,1.1,29)}, {"at":Vector3(-8,1.7,37.8),"look":Vector3(6,1.1,29)}]
	for index in shots.size():
		camera.global_position=shots[index].at; camera.look_at(shots[index].look)
		await process_frame; await RenderingServer.frame_post_draw
		var error:=root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://.godot/campus-gym-%d.png"%index))
		if error!=OK: push_error("Gym capture failed");quit(1);return
	print("CAMPUS_GYM_CAPTURES PASS")
	game.front.leave_game(); game.queue_free(); await process_frame; quit()
