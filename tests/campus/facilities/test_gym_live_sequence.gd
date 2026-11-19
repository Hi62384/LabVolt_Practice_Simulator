extends SceneTree
func _initialize() -> void:call_deferred("run")
func button(node: Node, text: String) -> Button:
	for item in node.find_children("*","Button",true,false):
		if item.text==text and item.is_visible_in_tree(): return item
	return null
func run() -> void:
	var game=load("res://scenes/Main.tscn").instantiate();root.add_child(game)
	for i in 4:await process_frame
	button(game.front.body,"Singleplayer").pressed.emit();await process_frame
	button(game.front.body,"Play").pressed.emit();await process_frame
	game.campus.request_room("gym")
	var rack: StaticBody3D=game.gym_barbells.belt_return_target
	game.player.global_position=Vector3(rack.global_position.x+1.40,.01,rack.global_position.z)
	game.campus.set_viewer_position(game.player.global_position)
	await physics_frame
	var belts=game.gym_barbells
	var rack_approach: Vector3=game.player.global_position
	game.player.global_position=belts.PLATE_RACK-Vector3.UP*.6
	belts.request_plate("pickup",0)
	assert(belts.held_plate(1)==0)
	game.player.global_position=rack_approach
	belts.request_plate("belt_attach",0,"belt/0")
	assert(belts.plates[0].station=="belt/0")
	for iteration in 2:
		for operation in ["pickup","wear","unwear"]:
			belts.request_belt(operation,0)
		assert(belts.held_belt(1)==0 and rack.collision_layer==4)
		await physics_frame
		await physics_frame
		var upright:=rack.global_position+Vector3(0,-.45,1.02)
		var ray:=PhysicsRayQueryParameters3D.create(upright+Vector3.RIGHT*1.4,upright,4)
		var hit:=rack.get_world_3d().direct_space_state.intersect_ray(ray)
		assert(hit.get("collider")==rack)
		game.current_target=hit.collider;game.activate(true)
		assert(belts.belts[0].where=="rack" and belts.held_belt(1)<0 and belts.worn_belt(1)<0 and rack.collision_layer==0)
		assert(belts.plates[0].station=="belt/0")
	var panel: PanelContainer=game.campus_services.facility_panel
	panel.open_for("gym/pushup","pushup")
	for i in 4:await process_frame
	assert(panel.exercise_scroll.visible and not panel.exercise_scroll.get_v_scroll_bar().visible)
	assert(panel.size.y<400.0)
	assert(panel.exercise_scroll.get_global_rect().encloses(button(panel,"Start set").get_global_rect()))
	assert(not panel.body.get_node("ExerciseLoad").visible)
	var output_path:=OS.get_environment("LABVOLT_GYM_SELECTOR_CAPTURE")
	if not output_path.is_empty() and DisplayServer.get_name()!="headless":
		await RenderingServer.frame_post_draw
		assert(root.get_texture().get_image().save_png(output_path)==OK)
	panel.hide()
	for bench in ["gym/seated_bench_1","gym/seated_bench_2"]:
		assert(game.campus_services.facilities.controller.host.anchors[bench].kind=="seated_bench")
	var host=game.campus_services.facilities.controller.host
	var weights=game.gym_weights
	game.player.global_position=weights._slot_position(weights.items[0].rack_slot)+Vector3(0,-.60,1.0)
	weights.request("pickup",0)
	assert(weights.held_id(1)==0)
	for id in ["gym/seated_bench_1","gym/seated_bench_2"]:
		game.player.global_position=host.anchors[id].bench_position+Vector3(0,0,1.0)
		await create_timer(.25).timeout
		var sequence: int=host.private_state(1).profile.last_sequence+1
		var seated: Dictionary=host.act(1,{"op":"sit","station":id,"sequence":sequence})
		assert(seated.ok and host.active[1].type=="seat",str(seated))
		await create_timer(.12).timeout
		var response: Dictionary=host.act(1,{"op":"start","station":id,"exercise":"curl","equipment":"dumbbell","sequence":sequence+1})
		assert(response.ok,str(response))
		assert(host.active[1].bench_position==host.anchors[id].bench_position)
		var cancel: Dictionary=host.act(1,{"op":"cancel","sequence":sequence+2})
		assert(cancel.ok,str(cancel))
		await create_timer(1.55).timeout
		assert(not host.active.has(1))
	var bar_station := "gym/barbell_rack_2"
	game.player.global_position=belts.POSITIONS[bar_station]-Vector3.UP
	belts.request("pickup_bar",bar_station,0.0,0)
	assert(belts.held_bar(1)==bar_station)
	for id in ["gym/seated_bench_1","gym/seated_bench_2"]:
		game.player.global_position=host.anchors[id].bench_position+Vector3(0,0,1.0)
		await create_timer(.25).timeout
		var sequence: int=host.private_state(1).profile.last_sequence+1
		var seated: Dictionary=host.act(1,{"op":"sit","station":id,"sequence":sequence})
		assert(seated.ok,str(seated))
		await create_timer(.12).timeout
		var response: Dictionary=host.act(1,{"op":"start","station":id,"exercise":"overhead_press","equipment":"barbell","sequence":sequence+1})
		assert(response.ok,str(response))
		assert(host.active[1].equipment=="barbell" and host.active[1].bench_position==host.anchors[id].bench_position)
		var cancel: Dictionary=host.act(1,{"op":"cancel","sequence":sequence+2})
		assert(cancel.ok,str(cancel))
		await create_timer(1.55).timeout
		assert(not host.movement_locked(1) and not game.player.workout_camera_override)
	print("GYM_LIVE_SEQUENCE PASS")
	game.queue_free();await process_frame;quit()
