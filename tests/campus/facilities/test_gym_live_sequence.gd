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
		var response: Dictionary=host.act(1,{"op":"start","station":id,"exercise":"incline_press","equipment":"dumbbell","sequence":sequence+1})
		assert(response.ok,str(response))
		assert(host.active[1].bench_position==host.anchors[id].bench_position)
		var model: Node3D=game.campus_services.facilities.rooms.gym.adjustable_benches[id]
		assert(is_equal_approx(model.target_angle,model.backrest_angle("incline")))
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
		var early_cancel: Dictionary=host.act(1,{"op":"cancel","sequence":sequence+2})
		assert(not early_cancel.ok and "Raise the bar" in early_cancel.error)
		for press in 65:
			if host.active[1].phase==0:break
			while host.now()-int(host.last_request.get(1,-1000))<90:await process_frame
			var next_sequence: int=host.private_state(1).profile.last_sequence+1
			var effort: Dictionary=host.act(1,{"op":"effort","sequence":next_sequence})
			assert(effort.ok,str(effort))
		assert(host.active[1].phase==0,"The bar did not reach lockout")
		var cancel: Dictionary=host.act(1,{"op":"cancel","sequence":host.private_state(1).profile.last_sequence+1})
		assert(cancel.ok,str(cancel))
		await create_timer(1.55).timeout
		assert(not host.movement_locked(1) and not game.player.workout_camera_override)
	var bridge: Node=game.interaction_presentation
	game.player.reduced_motion=true
	var bar:=Node3D.new()
	game.add_child(bar)
	var bench: Vector3=host.anchors["gym/benchpress"].bench_position
	bridge.workout_state={"station":"gym/benchpress","bench_position":bench,"equipment":"barbell"}
	for offset in [-.6,0.0,.6,-.6]:
		bar.global_position=bench+Vector3(0,1.7,offset)
		bridge._workout_camera(game.camera,"incline_press",bar,null,.5,1.0)
		var forward: Vector3=-game.camera.global_basis.z
		assert(forward.is_finite() and forward.z>.70 and absf(forward.y)<.70,"Incline camera flipped or aimed vertically")
	bridge._workout_camera(game.camera,"chest_supported_row",bar,null,.5,1.0)
	assert(-game.camera.global_basis.z.y<-.55 and game.camera.global_position.y>bench.y+1.15,"Row camera should clear the bench and look down")
	bridge._restore_workout_camera()
	bridge.workout_state.clear()
	assert(not game.player.workout_camera_override)
	bridge.workout_state={"equipment":"dumbbell","workout_facing":game.player.yaw_target}
	bridge._workout_camera(game.camera,"calf_raise",null,null,0.0,1.0)
	var bottom: float=game.camera.global_position.y
	bridge._workout_camera(game.camera,"calf_raise",null,null,1.0,1.0)
	assert(is_equal_approx(game.camera.global_position.y-bottom,.12))
	bridge._workout_camera(game.camera,"calf_raise",null,null,0.0,1.0)
	assert(is_equal_approx(game.camera.global_position.y,bottom))
	var low_grip: Vector3=bridge._frame_workout_weight(game.camera,Vector3(.3,-.9,-.22))
	assert(low_grip.y>=-.9 and low_grip.y<0.0 and low_grip.z<-.9)
	assert(game.camera.is_position_in_frustum(game.camera.to_global(low_grip)))
	for exercise in ["deadlift","romanian_deadlift","squat","good_morning"]:
		bridge._workout_camera(game.camera,exercise,null,null,0.0,1.0)
		var crouched: float=game.camera.global_position.y
		bridge._workout_camera(game.camera,exercise,null,null,1.0,1.0)
		assert(game.camera.global_position.y>crouched+.15,"Camera should rise during "+exercise)
	bridge._restore_workout_camera()
	bridge.workout_state.clear()
	var motion: Node3D=game.campus_services.gym_motion
	for exercise in host.BENCH_BARBELL_EXERCISES:
		motion.on_room_event(1,{"activity":"exercise","station":"gym/benchpress","exercise":exercise,"phase":1})
		var lowered: float=motion.target_height["gym/benchpress"]
		motion.on_room_event(1,{"activity":"exercise","station":"gym/benchpress","exercise":exercise,"phase":0})
		assert(motion.target_height["gym/benchpress"]>lowered,"Bar moves down during the lift: "+exercise)
	print("GYM_LIVE_SEQUENCE PASS")
	game.queue_free();await process_frame;quit()
