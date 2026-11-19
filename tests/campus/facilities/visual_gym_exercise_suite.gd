extends SceneTree
## Capture the real gym and camera at matched rep positions in both perspectives.
const Rules = preload("res://scripts/campus/facilities/facility_host.gd")
const Avatar = preload("res://scripts/toon_character.gd")
const Pose = preload("res://scripts/campus/facilities/avatar_activity.gd")

func _initialize() -> void:
	call_deferred("run")

func _button(node: Node, text: String) -> Button:
	for button in node.find_children("*", "Button", true, false):
		if button.text == text and button.is_visible_in_tree():return button
	return null

func _capture(path: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	assert(root.get_texture().get_image().save_png(path)==OK, path)

func run() -> void:
	var folder := OS.get_environment("LABVOLT_UI_ARTIFACTS")
	if folder.is_empty() or DisplayServer.get_name()=="headless":
		push_error("Run the rendered test with LABVOLT_UI_ARTIFACTS set.");quit(1);return
	DirAccess.make_dir_recursive_absolute(folder)
	var game: Node = load("res://scenes/Main.tscn").instantiate()
	root.add_child(game)
	for i in 4:await process_frame
	_button(game.front.body,"Singleplayer").pressed.emit()
	await process_frame
	_button(game.front.body,"Play").pressed.emit()
	await process_frame
	game.ui.graphics_controller.preset("Medium")
	game.campus.set_viewer_position(Vector3(0,0,33))
	game.campus.request_room("gym")
	for i in 12:game.campus.streamer.advance(16000)
	game.player.set_physics_process(false)
	game.player.reduced_motion=true
	var fixtures: Node = game.campus_services.facilities
	var rules: RefCounted = fixtures.controller.host
	var avatar := Avatar.build(Avatar.defaults())
	game.add_child(avatar)
	var pose := Pose.new()
	game.add_child(pose)
	pose.bind_visual(avatar)
	var camera := Camera3D.new()
	game.add_child(camera)
	camera.fov=61
	var bridge: Node = game.interaction_presentation
	var cases: Array[Dictionary] = []
	_add_cases(cases,"gym/pushup",Rules.STATION_EXERCISES.pushup)
	_add_cases(cases,"gym/pullup",Rules.STATION_EXERCISES.pullup)
	_add_cases(cases,"gym/benchpress",Rules.BENCH_BARBELL_EXERCISES)
	_add_cases(cases,"gym/benchpress",Rules.BENCH_DUMBBELL_EXERCISES,"dumbbell")
	_add_cases(cases,"gym/seated_bench_1",Rules.SEATED_DUMBBELL_EXERCISES,"dumbbell")
	_add_cases(cases,"gym/seated_bench_2",Rules.SEATED_BARBELL_EXERCISES,"barbell")
	_add_cases(cases,"gym/dumbbell/1",Rules.DUMBBELL_EXERCISES,"dumbbell")
	_add_cases(cases,"gym/barbell/1",Rules.BARBELL_EXERCISES,"barbell")
	_add_cases(cases,"gym/squat",Rules.STATION_EXERCISES.squat)
	for id in rules.anchors:
		if rules.anchors[id].kind=="cable":
			_add_cases(cases,id,Rules.CABLE_EXERCISES)
			break
	var first_camera: Camera3D=game.camera
	var weight_view: Node3D=game.gym_weights._pair_model(20.0)
	first_camera.add_child(weight_view)
	game.gym_weights.held_visual=weight_view
	var bar_view: Node3D=game.gym_barbells._bar_model("gym/barbell_rack_2")
	first_camera.add_child(bar_view)
	game.gym_barbells.bar_hand=bar_view
	bar_view.scale=Vector3.ONE*.55
	game.gym_weights.set_process(false)
	game.gym_barbells.set_process(false)
	for movement in cases:
		var anchor: Dictionary=rules.anchors.get(movement.station,{"position":Vector3(0,0,33)})
		var event := {"activity":"exercise","exercise":movement.exercise,"station":movement.station,"phase":.30,"half_ms":750,"weight":20.0}
		for field in ["mat_position","bench_position"]:
			if anchor.has(field):event[field]=anchor[field]
		if movement.station=="gym/pullup":
			event.grip_anchor=anchor["dip_grip" if movement.exercise=="dip" else "pullup_grip"]
		if not movement.equipment.is_empty():event.equipment=movement.equipment
		var position: Vector3=anchor.position
		bridge.facility_event(1,{"activity":"idle"})
		game.player.global_position=position
		avatar.global_position=position
		pose.original=avatar.transform
		pose.apply_event(event,false)
		fixtures.controller.room_event.emit(1,event)
		weight_view.visible=movement.equipment=="dumbbell"
		bar_view.visible=movement.equipment=="barbell"
		var bench: Node3D=fixtures.rooms.gym.adjustable_benches.get(movement.station)
		for i in 20:
			pose._process(.05)
			if is_instance_valid(bench):bench._process(.05)
			game.campus_services.gym_motion._process(.05)
			bridge._update_workout(.05)
		var name: String=movement.station.trim_prefix("gym/").replace("/","-")+"-"+movement.exercise+"-"+movement.equipment
		avatar.hide()
		first_camera.make_current()
		if movement.equipment=="dumbbell":
			for weight in weight_view.get_children():
				assert(first_camera.is_position_in_frustum(weight.global_position),name+" dumbbell is outside the view")
		if movement.equipment=="barbell" and movement.exercise not in ["squat","good_morning"]:
			assert(first_camera.is_position_in_frustum(bar_view.global_position),name+" barbell is outside the view")
		if movement.exercise in ["pushup","pike_pushup","pullup","dip","benchpress","incline_press"]:
			# Hands should remain on the same screen side as their shoulder.
			for arm in bridge.workout_arms:
				var hand := arm.find_child("Hand*",true,false) as Node3D
				var side := -1.0 if arm.get_meta("workout_left",false) else 1.0
				assert(is_instance_valid(hand) and first_camera.to_local(hand.global_position).x*side>=-.002,name)
		await _capture(folder.path_join(name+"-first.png"))
		avatar.show()
		weight_view.hide()
		bar_view.hide()
		var focus: Vector3=event.get("mat_position",event.get("bench_position",position))+Vector3.UP*.7
		await physics_frame
		camera.global_position=_camera_position(game,focus)
		camera.look_at(focus)
		camera.make_current()
		await _capture(folder.path_join(name+"-third.png"))
		pose.apply_event({"activity":"idle"},false)
		print("GYM_RENDER ",name)
	bridge.facility_event(1,{"activity":"idle"})
	assert(not game.player.workout_camera_override)
	print("GYM_EXERCISE_RENDER PASS ",cases.size()," exercises and equipment combinations")
	game.front.leave_game()
	game.queue_free()
	await process_frame
	quit(0)

func _add_cases(cases: Array[Dictionary],station: String,exercises: Array,equipment: String="") -> void:
	for exercise in exercises:cases.append({"station":station,"exercise":exercise,"equipment":equipment})

func _camera_position(game: Node3D,focus: Vector3) -> Vector3:
	var space:=game.get_world_3d().direct_space_state
	for offset in [Vector3(-2.7,1.0,1.8),Vector3(2.7,1.0,1.8),Vector3(-2.7,1.0,-1.8),Vector3(2.7,1.0,-1.8)]:
		var candidate: Vector3=focus+offset
		if not game.campus.registry.room_contains("gym",candidate):continue
		var ray:=PhysicsRayQueryParameters3D.create(focus,candidate,1,[game.player.get_rid()])
		if space.intersect_ray(ray).is_empty():return candidate
	return focus+Vector3(0,1.9,0)
