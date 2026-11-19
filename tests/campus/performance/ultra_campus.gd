extends SceneTree
## Render every registered room, plus outdoor and circulation areas, on Ultra.
const Probe = preload("res://scripts/campus/performance/frame_probe.gd")

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	if DisplayServer.get_name()=="headless" or RenderingServer.get_current_rendering_method()!="forward_plus":
		push_error("The campus tour requires Forward+.");quit(1);return
	var game: Node=load("res://scenes/Main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.front.entered()
	game.ui.graphics_controller.preset("Ultra")
	for frame in 12:await process_frame
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps=0
	game.player.set_physics_process(false)
	var registry: RefCounted=game.campus.registry
	var views: Dictionary={
		"exterior":[Vector3(13,0,-20),Vector3.BACK],
		"ground_hall_north":[Vector3(14.5,0,51),Vector3.BACK],
		"ground_hall_south":[Vector3(14.5,0,5),Vector3.BACK],
		"upper_hall":[Vector3(14.5,5,49),Vector3.FORWARD],
		"north_stairs":[Vector3(11.5,2.5,56),Vector3.BACK],
		"dorm_hall_south":[Vector3(13,0,70),Vector3.BACK],
		"dorm_hall_north":[Vector3(13,0,105),Vector3.FORWARD],
	}
	for dorm in game.dorm_interactions.hall.room_contracts:
		views[dorm.dorm_id]=[dorm.entry_anchor,(dorm.center-dorm.entry_anchor).normalized()]
	for id in registry.rooms:
		var room: Dictionary=registry.rooms[id]
		var center: Vector3=registry.vector(room.center)
		var approach: Vector3=registry.vector(room.door)
		var direction: Vector3=center-approach
		direction.y=0.0
		if direction.length_squared()<.1:direction=Vector3.FORWARD
		views[id]=[registry.vector(room.anchor),direction.normalized()]
	var results := {}
	for id in views:
		if registry.rooms.has(id):game.campus.request_room(id)
		var view: Array=views[id]
		game.player.global_position=view[0]
		game.campus.set_viewer_position(view[0])
		game.camera.look_at(game.camera.global_position+view[1])
		for frame in 12:await process_frame
		var probe:=Probe.new()
		for frame in 90:
			var before:=Time.get_ticks_usec()
			await process_frame
			probe.record_frame((Time.get_ticks_usec()-before)/1000000.0)
		var report:=probe.report()
		probe.free()
		results[id]={"avg_fps":report.average_fps,"p95_ms":report.p95_ms,"slowest_ms":report.peak_frame_ms}
		print("ULTRA ",id," ",JSON.stringify(results[id]))
	var output:=FileAccess.open(OS.get_environment("LABVOLT_ULTRA_REPORT"),FileAccess.WRITE)
	if output!=null:output.store_string(JSON.stringify({"size":[root.size.x,root.size.y],"adapter":RenderingServer.get_video_adapter_name(),"vsync":DisplayServer.window_get_vsync_mode(),"max_fps":Engine.max_fps,"locations":results},"\t"))
	print("ULTRA_TOUR PASS ",results.size())
	game.front.leave_game()
	game.queue_free()
	await process_frame
	quit()
