extends SceneTree
func _initialize() -> void: call_deferred("run")
func button(node: Node, text: String) -> Button:
	for item in node.find_children("*", "Button", true, false):
		if item.text==text and item.is_visible_in_tree(): return item
	return null
func capture(name: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	var directory := OS.get_environment("LABVOLT_UI_ARTIFACTS")
	if directory.is_empty():
		directory = ProjectSettings.globalize_path("res://.godot")
	DirAccess.make_dir_recursive_absolute(directory)
	if root.get_texture().get_image().save_png(directory.path_join(name + ".png")) != OK:
		push_error("Capture failed for " + name)
		quit(1)

func run() -> void:
	var game=load("res://scenes/Main.tscn").instantiate(); root.add_child(game)
	for i in 4: await process_frame
	var single:=button(game.front.body,"Singleplayer")
	if single==null: push_error("Singleplayer missing"); quit(1); return
	single.pressed.emit(); await process_frame
	var play:=button(game.front.body,"Play")
	if play==null: push_error("Play missing"); quit(1); return
	play.pressed.emit(); await process_frame
	game.ui.graphics_controller.preset("Medium")
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
	var rack:=PhysicsRayQueryParameters3D.create(Vector3(-4.1,1.1,30),Vector3(-4.1,1.1,32),1)
	rack.exclude=[game.player.get_rid()]
	if space.intersect_ray(rack).is_empty():
		push_error("Gym pull-up rack lacks physical collision");quit(1);return
	var camera:=Camera3D.new(); game.add_child(camera); camera.current=true; camera.fov=72
	var shots:=[{"at":Vector3(-8,1.7,28.2),"look":Vector3(4,1.1,36)}, {"at":Vector3(8,1.7,37.8),"look":Vector3(-4,1.1,29)}, {"at":Vector3(-8,1.7,37.8),"look":Vector3(6,1.1,29)}]
	for index in shots.size():
		camera.global_position=shots[index].at; camera.look_at(shots[index].look)
		await capture("campus-gym-%d" % index)
	var details := {
		"medicine-ball-storage": [Vector3(7.3, 1.27, 35.9), Vector3(7.3, .81, 37.78)],
		"cable-weight": [Vector3(6.9, 1.65, 31.05), Vector3(7, 1.22, 29.6)],
		"dumbbell-rack": [Vector3(2.65, 1.67, 31.6), Vector3(2.65, .96, 27.58)],
		"belt-rack": [Vector3(-6.15, 1.57, 33), Vector3(-9.2, 1.1, 33)],
		"plate-rack": [Vector3(-7.3, 1.6, 35.7), Vector3(-7.65, .94, 38.72)],
		"ac-lab": [Vector3(2.5, 1.67, 6.9), Vector3(0, .78, 9.36)],
		"dc-lab": [Vector3(2.3, 1.67, 16), Vector3(0, .78, 13.64)],
		"cafeteria": [Vector3(17.3, 1.7, 19), Vector3(28, .68, 21)],
		"hallway-junction": [Vector3(13.4, 1.65, -6.1), Vector3(9.9, 1.6, -3.8)],
	}
	for name in details:
		var shot: Array = details[name]
		game.player.global_position = shot[0]
		game.campus.set_viewer_position(shot[0])
		camera.global_position = shot[0]
		camera.look_at(shot[1])
		for frame in 16:
			await process_frame
		await capture(name)

	camera.global_position = Vector3(5.6, 1.75, 33)
	camera.look_at(Vector3(7, 1.30, 29.6))
	var panel: PanelContainer = game.campus_services.facility_panel
	game.release_mouse()
	panel.open_for("gym/cable_0", "cable")
	for frame in 4:
		await process_frame
	await capture("exercise-selector")
	panel.open_for("gym/progress", "gym_progress")
	for frame in 4:
		await process_frame
	await capture("gym-progress")
	panel.hide()
	game.player.global_position = Vector3(5.6, 0.1, 33)
	game.campus.set_viewer_position(game.player.global_position)
	var plate: MeshInstance3D = game.gym_barbells._plate_model(45)
	game.add_child(plate)
	plate.global_position = Vector3(5.0, 1.29, 33.0)
	plate.rotation.x = PI * .5
	for side in [-1.0, 1.0]:
		camera.global_position = plate.global_position + Vector3(.13, .07, side * .74)
		camera.look_at(plate.global_position)
		camera.make_current()
		for frame in 4:
			await process_frame
		await capture("plate-%s" % ("front" if side > 0 else "rear"))
	plate.queue_free()
	game.ui.graphics_controller.preset("Low")
	for name in ["ac-lab", "cafeteria", "medicine-ball-storage"]:
		var shot: Array = details[name]
		game.player.global_position = shot[0]
		game.campus.set_viewer_position(shot[0])
		camera.global_position = shot[0]
		camera.look_at(shot[1])
		for frame in 16:
			await process_frame
		await capture(name + "-low")
	print("CAMPUS_GYM_CAPTURES PASS")
	game.front.leave_game(); game.queue_free(); await process_frame; quit()
