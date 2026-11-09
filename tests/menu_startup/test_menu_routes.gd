extends SceneTree

# Run only with an isolated user-data directory after the startup import gate.
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _check(ok: bool, message: String) -> void:
	if not ok:failures.append(message)

func _button(root: Node, label: String) -> Button:
	for node in root.find_children("*", "Button", true, false):
		if node.text == label and node.is_visible_in_tree():return node
	return null

func _usable(button: Button, viewport_rect: Rect2, label: String) -> void:
	_check(is_instance_valid(button), label + " missing")
	if not is_instance_valid(button):return
	_check(button.is_visible_in_tree() and not button.disabled, label + " hidden or disabled")
	_check(button.focus_mode != Control.FOCUS_NONE and button.mouse_filter != Control.MOUSE_FILTER_IGNORE, label + " cannot receive input")
	var bounds := button.get_global_rect()
	_check(bounds.size.x > 0 and bounds.size.y > 0 and viewport_rect.intersects(bounds), label + " outside viewport")

func _run() -> void:
	var scene := load("res://scenes/Main.tscn") as PackedScene
	_check(scene != null, "Main scene failed to load")
	if scene == null:_finish();return
	var game := scene.instantiate()
	root.add_child(game)
	for i in 4:await process_frame
	var front: Variant = game.get("front")
	_check(is_instance_valid(front) and is_instance_valid(front.body), "Main menu failed to construct")
	if not is_instance_valid(front) or not is_instance_valid(front.body):_finish();return
	var viewport_rect := root.get_viewport().get_visible_rect()
	for label in ["Host Game", "Singleplayer", "View Courses", "Join Game", "Character Customizer", "Settings"]:
		_usable(_button(front.body, label), viewport_rect, label)
	for offline: bool in [true, false]:
		var label := "Singleplayer" if offline else "Host Game"
		var route_button := _button(front.body, label)
		if not is_instance_valid(route_button):continue
		route_button.pressed.emit()
		await process_frame
		_check(front.page == ("singleplayer" if offline else "host"), label + " did not open Play options")
		var play := _button(front.body, "Play")
		_usable(play, viewport_rect, label + " Play")
		if is_instance_valid(play):
			play.pressed.emit()
			await process_frame
			_check(front.in_game and not front.screen.visible and game.player.enabled,
				"%s Play failed to enter gameplay (%s)" % [label, front.status.text])
			_check(game.session.online == not offline, label + " started the wrong session type")
		if front.in_game or game.session.online:
			front.leave_game()
		else:
			front.home()
		await process_frame
	for route in [{"label":"View Courses","page":"view_courses"},{"label":"Character Customizer","page":"characters"},{"label":"Settings","page":"settings"}]:
		var action := _button(front.body, route.label)
		if not is_instance_valid(action):continue
		action.pressed.emit();await process_frame
		_check(front.page == route.page, route.label + " did not open")
		var back := _button(front.screen, "Back")
		_usable(back, viewport_rect, route.label + " Back")
		if is_instance_valid(back):back.pressed.emit();await process_frame
		_check(front.page == "home", route.label + " Back did not return home")
		_usable(_button(front.body, "Host Game"), viewport_rect, "Host Game after Back")
	_finish()

func _finish() -> void:
	for failure in failures:push_error(failure)
	print("MENU_ROUTES ", "PASS" if failures.is_empty() else "FAIL (%d)" % failures.size())
	quit(0 if failures.is_empty() else 1)
