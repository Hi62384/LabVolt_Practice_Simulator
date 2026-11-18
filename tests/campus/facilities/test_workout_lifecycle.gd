extends SceneTree

const Host = preload("res://scripts/campus/facilities/facility_host.gd")
var saved := Host.empty_profile()
var load_kg := 20.0

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var game: Node = load("res://scenes/Main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	_button(game.front.body,"Singleplayer").pressed.emit()
	await process_frame
	_button(game.front.body,"Play").pressed.emit()
	await process_frame
	var panel: Control = game.campus_services.facility_panel
	var controller: Node = game.campus_services.facilities.controller
	var rules: RefCounted = controller.host
	var bench: Vector3 = rules.anchors["gym/benchpress"].position
	game.player.global_position = bench
	game.player.yaw_target = 0.0
	game.player.pitch_target = -.16
	rules.context = func(_peer):return {"identity":"student", "position":bench, "room_id":"gym", "allowed":true, "grounded":true}
	rules.load_profile = func(_identity):return saved.duplicate(true)
	rules.commit_profile = func(_identity,_dollars,value):saved=value.duplicate(true);return true
	rules.barbell_mass = func(_station):return load_kg
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	var effort := InputEventKey.new()
	effort.keycode = KEY_E
	effort.pressed = true
	var lower := InputEventMouseButton.new()
	lower.button_index = MOUSE_BUTTON_LEFT
	lower.pressed = true

	panel.open_for("gym/benchpress","benchpress")
	_button(panel,"Start set").pressed.emit()
	await _wait_real(.11)
	assert(panel.visible and panel.rep_control.live and not panel.menu_layout.visible)
	var original: Control = panel.rep_control
	assert(panel.handle_workout_input(effort))
	await _wait_real(.115)
	assert(panel.rep_control == original and rules.active[1].lift_progress > 0.0 and rules.active[1].lift_progress < 1.0, "Active=%s, same HUD=%s, error=%s, waiting=%s" % [rules.active[1], panel.rep_control == original, panel.last_error, panel.direct_in_flight])
	for i in 28:
		if rules.active[1].phase == 0:break
		panel.handle_workout_input(effort)
		await _wait_real(.105)
	assert(rules.active[1].phase == 0)
	await _wait_real(.25)
	var bar: Node3D = game.campus_services.gym_motion.bars["gym/benchpress"]
	var bar_view: Vector3 = game.camera.to_local(bar.global_position)
	assert(bar_view.z < 0.0 and absf(bar_view.y) < .19, "First-person camera lost the moving bar: %s" % str(bar_view))
	await _capture("workout-top")
	panel.handle_workout_input(lower)
	assert(rules.active[1].phase == 2)
	await _wait_real(float(rules.active[1].half_ms)/1000.0+.25)
	assert(rules.active[1].reps == 1 and rules.active[1].lift_progress == 0.0)
	assert(panel.handle_workout_input(escape))
	await process_frame
	assert(not panel.visible and not rules.movement_locked(1))
	assert(saved.gym.history.back().outcome == "voluntary")

	await _wait_real(.11)
	load_kg = 200.0
	panel.open_for("gym/benchpress","benchpress")
	_button(panel,"Start set").pressed.emit()
	await _wait_real(.11)
	for i in 28:
		if rules.active[1].type == "trapped":break
		panel.handle_workout_input(effort)
		await _wait_real(.105)
	assert(rules.active[1].type == "trapped" and not panel.menu_layout.visible)
	assert(panel.handle_workout_input(escape) and panel.visible)
	await process_frame
	await process_frame
	assert(panel.size.y < 210 and panel.trap_instruction.is_visible_in_tree())
	await _capture("workout-pinned")
	await _wait_real(.32)
	assert(float(game.health.people[1].health) < 100.0 and not game.health.people[1].dead)
	game.health.people[1].health = .1
	await _wait_real(.32)
	assert(game.health.people[1].dead and not rules.movement_locked(1) and not panel.visible)
	assert(saved.gym.history.size() == 2 and saved.gym.history.back().outcome == "failure")
	game.health.people[1].remaining = .05
	await _wait_real(.32)
	assert(not game.health.people[1].dead and not game.player.shock_locked and not rules.movement_locked(1))
	assert(game.player.global_position.distance_to(game.health.RESPAWN)<1.0)
	print("WORKOUT_LIFECYCLE PASS")
	quit()

func _capture(name: String) -> void:
	var directory := OS.get_environment("LABVOLT_UI_ARTIFACTS")
	if directory.is_empty() or DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(directory)
	assert(root.get_texture().get_image().save_png(directory.path_join(name+".png")) == OK)

func _button(container: Node, label: String) -> Button:
	for node in container.find_children("*","Button",true,false):
		if node.text == label and node.is_visible_in_tree():
			return node
	return null


func _wait_real(seconds: float) -> void:
	var end := Time.get_ticks_msec() + ceili(1000.0*seconds)
	while Time.get_ticks_msec() < end:
		await process_frame
