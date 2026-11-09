extends Control
signal closed

const Prefs = preload("res://scripts/campus/ui/client_preferences.gd")
const Player = preload("res://scripts/first_person.gd")
const SkinFactory = preload("res://scripts/ui/design_system/theme.gd")
const Widgets = preload("res://scripts/ui/design_system/widgets.gd")
const T = preload("res://scripts/ui/design_system/tokens.gd")
const CATEGORIES := {
	"Graphics & Display":"meter", "Audio":"volume", "Controls":"keyboard",
	"Gameplay":"play", "Accessibility":"user", "Host Server":"network"}
const RESOLUTIONS := [Vector2i.ZERO, Vector2i(1280,720), Vector2i(1366,768), Vector2i(1600,900), Vector2i(1920,1080), Vector2i(2560,1440)]
const RESERVED := [KEY_F, KEY_Q, KEY_Z, KEY_P, KEY_C, KEY_F8, KEY_F11, KEY_ESCAPE, KEY_ENTER, KEY_BACKSPACE, KEY_R, KEY_BRACKETLEFT, KEY_BRACKETRIGHT]

var game: Node
var prefs: RefCounted
var graphics: Node
var nav: BoxContainer
var layout: BoxContainer
var body: VBoxContainer
var active := "Graphics & Display"
var apply_button: Button
var message: Label
var choices := {}
var binding := ""
var binding_buttons := {}
var save_timer: Timer
var pending_mode := 0
var pending_resolution := Vector2i.ZERO
var previewing := false
var previous_mode: Window.Mode
var previous_size: Vector2i
var previous_position: Vector2i
var confirmation: ConfirmationDialog
var countdown := 0
var preset := "Custom"

func build(owner: Node) -> void:
	game = owner
	prefs = game.client_preferences
	graphics = game.ui.graphics_controller
	pending_mode = prefs.values.display_mode
	pending_resolution = Vector2i(prefs.values.width, prefs.values.height)
	theme = SkinFactory.create()
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	var backdrop := ColorRect.new()
	backdrop.color = Color("0b212e")
	backdrop.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(backdrop)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	for edge in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + edge, 16)
	add_child(margin)
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 8)
	margin.add_child(page)
	_label(page, "Settings", 29)
	layout = BoxContainer.new()
	layout.size_flags_vertical = SIZE_EXPAND_FILL
	page.add_child(layout)
	nav = BoxContainer.new()
	nav.vertical = true
	nav.custom_minimum_size.x = 208
	nav.add_theme_constant_override("separation", 5)
	layout.add_child(nav)
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = SIZE_EXPAND_FILL
	panel.size_flags_vertical = SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", T.surface(Color("112b39"), Color("315266"), 12))
	layout.add_child(panel)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	panel.add_child(scroll)
	body = VBoxContainer.new()
	body.size_flags_horizontal = SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 6)
	scroll.add_child(body)
	message = _label(page, "", 13, T.ACCENT)
	message.hide()
	page.add_child(HSeparator.new())
	var footer := HBoxContainer.new()
	page.add_child(footer)
	_button(footer, "Back", "back", func(): closed.emit())
	var spacer := Control.new()
	spacer.size_flags_horizontal = SIZE_EXPAND_FILL
	footer.add_child(spacer)
	_button(footer, "Reset Defaults", "refresh", _reset)
	apply_button = _button(footer, "Apply Display", "check", _apply_display)
	apply_button.theme_type_variation = "PrimaryButton"
	save_timer = Timer.new()
	save_timer.one_shot = true
	save_timer.wait_time = .35
	save_timer.timeout.connect(_save)
	add_child(save_timer)
	resized.connect(_reflow)
	_reflow()
	_select(active)

func _host_server_controls() -> void:
	var code: String = game.session.room_code()
	if code.is_empty():
		_label(body, "Room code appears here while you are hosting.", 15)
	else:
		var room_code := _label(body, "Room code  " + code, 17)
		room_code.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_button(body, "Copy Room Code", "", func(): DisplayServer.clipboard_set(code))
	var account = game.front.relay_account
	if account.connected():
		_label(body, "Estimated daily requests left · %d / %d" % [account.estimated_remaining(), account.DAILY_REQUESTS], 16)
		var note := _label(body, "Counts this installation’s relay traffic. Account-wide usage and compute limits are in Cloudflare. Resets at midnight UTC.", 14)
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_button(body, "View Cloudflare Usage", "meter", func(): OS.shell_open("https://dash.cloudflare.com/" + str(account.identity.account_id) + "/workers-and-pages"))
	else:
		_label(body, "Connect a relay account from Host Game to track usage.", 15)
	_label(body, "Multiplayer optimization", 18)
	_slider("Movement updates per second", 5, 20, 1, prefs.values.relay_pose_rate,
		func(value: float): _preference(int(value), "relay_pose_rate"), "%.0f", 1)
	_toggle("Skip unchanged movement updates", prefs.values.relay_skip_idle, _preference.bind("relay_skip_idle"))

func _reflow() -> void:
	layout.vertical = size.x < 760
	nav.vertical = not layout.vertical
	nav.custom_minimum_size.x = 0 if layout.vertical else 208

func _select(category: String) -> void:
	binding = ""
	active = category
	message.hide()
	_clear(nav)
	_clear(body)
	choices.clear()
	binding_buttons.clear()
	for title in CATEGORIES:
		var pick := _button(nav, title, CATEGORIES[title], _select.bind(title))
		pick.theme_type_variation = "PrimaryButton" if title == active else "Button"
	_label(body, category, 22)
	match category:
		"Graphics & Display": _display_controls()
		"Audio":
			for spec in [["Master volume","master"],["Sound effects","effects"],["Environmental ambience","ambience"],["UI sounds","interface"]]:
				_slider(spec[0], 0, 1, .01, prefs.values[spec[1]], _preference.bind(spec[1]), "%.0f%%", 100)
		"Controls": _input_controls()
		"Host Server": _host_server_controls()
		"Gameplay":
			for spec in [["Show interaction prompts","prompts"],["Show notifications","notifications"],["Show room names","room_names"],["Show HUD","hud"],["Terminal assistance","assists"]]:
				_toggle(spec[0], prefs.values[spec[1]], _preference.bind(spec[1]))
			_label(body, "Public player card", 18)
			for key in game.ui.public_visibility.values:
				_toggle("Share " + str(key).capitalize(), game.ui.public_visibility.values[key], func(value: bool):
					game.ui.public_visibility.values[key] = value
					if game.ui.public_visibility.save_settings() != OK:
						_notice("Could not save profile visibility."))
		"Accessibility":
			_slider("Interface scale", .85, 1.25, .05, prefs.values.ui_scale, _preference.bind("ui_scale"), "%.0f%%", 100)
			_toggle("High-contrast HUD text", prefs.values.high_contrast, _preference.bind("high_contrast"))
			_toggle("Analyzer polarity symbols", prefs.values.analyzer_shapes, _preference.bind("analyzer_shapes"))
			_toggle("Reduced motion", prefs.values.reduced_motion, _preference.bind("reduced_motion"))
	_update_display_action()

func _display_controls() -> void:
	_choice("Display mode", ["Windowed","Borderless Fullscreen","Fullscreen"], pending_mode, func(index):
		pending_mode = index
		choices.resolution.disabled = index != 0
		_update_display_action())
	var titles := ["Current window size"]
	for resolution in RESOLUTIONS.slice(1):
		titles.append("%d × %d" % [resolution.x, resolution.y])
	choices.resolution = _choice("Window resolution", titles, maxi(0, RESOLUTIONS.find(pending_resolution)), func(index):
		pending_resolution = RESOLUTIONS[index]
		_update_display_action())
	choices.resolution.disabled = pending_mode != 0
	_toggle("V-Sync", prefs.values.vsync, _preference.bind("vsync"))
	var limits := [0,30,60,90,120,144,165,240]
	var limit_labels := ["Unlimited","30 FPS","60 FPS","90 FPS","120 FPS","144 FPS","165 FPS","240 FPS"]
	var saved_limit: int=prefs.values.fps
	if not limits.has(saved_limit):
		limits.append(saved_limit)
		limit_labels.append("%d FPS" % saved_limit)
	_choice("Frame rate limit", limit_labels, limits.find(saved_limit), func(index): _preference(limits[index], "fps"))
	_slider("First-person field of view", 55, 95, 1, prefs.values.fov, _preference.bind("fov"), "%.0f°")
	_label(body, "Image quality", 18)
	var levels := ["Low","Medium","High","Ultra","Custom"]
	choices.preset = _choice("Quality preset", levels, levels.find(preset), func(index):
		preset = levels[index]
		if preset != "Custom":
			graphics.preset(preset)
			_select(active))
	_quality_choice("Anti-aliasing", "aa", [0,1,2,3], ["Off","MSAA 2×","MSAA 4×","MSAA 8×"])
	_quality_choice("Texture filtering", "texture", [0,1,2], ["Nearest mipmaps","Filtered 4×","Filtered 16×"])
	_quality_choice("View distance", "view_distance", [30.0,60.0,120.0,180.0,240.0], ["30 m","60 m","120 m","180 m","240 m"])
	_quality_choice("Ambient campus crowd", "npc_density", ["Off","Low","Medium","High"], ["Off","Low","Medium","High"])
	for spec in [["Cast shadows","shadows"],["Fine-detail shadows","detail_shadows"],["Local lights","lights"],["Particle effects","effects"],["First-person interaction hands","interaction_hands"]]:
		_toggle(spec[0], graphics.options[spec[1]], _quality.bind(spec[1]))

func _quality_choice(label: String, key: String, values: Array, names: Array) -> void:
	_choice(label, names, maxi(0, values.find(graphics.options[key])), func(index): _quality(values[index], key))

func _quality(value: Variant, key: String) -> void:
	graphics.set_option(key, value)
	preset = "Custom"
	choices.preset.select(4)

func _input_controls() -> void:
	_slider("Mouse sensitivity", .0003, .008, .00005, game.player.sensitivity, _control.bind("sensitivity"), "%.2f", 1.0/.00225)
	_toggle("Invert vertical look", game.player.invert_vertical, _control.bind("invert_vertical"))
	_toggle("Invert horizontal look", game.player.invert_horizontal, _control.bind("invert_horizontal"))
	_toggle("Head bob", game.player.head_bob, _control.bind("head_bob"))
	_label(body, "Keyboard bindings", 18)
	for action in game.player.keys:
		var names := {"forward":"Move forward","back":"Move backward","left":"Strafe left","right":"Strafe right","read_sheet":"Read held worksheet","drop_lead":"Drop held item","emotes":"Open emotes"}
		var row := _row(names.get(action, str(action).replace("_"," ").capitalize()))
		binding_buttons[action] = _button(row, OS.get_keycode_string(game.player.keys[action]), "keyboard", _start_binding.bind(action))
		binding_buttons[action].custom_minimum_size.x = 120
	_button(body, "Restore Default Bindings", "refresh", func():
		game.player.keys = Player.DEFAULT_KEYS.duplicate()
		game.player.save_settings()
		_select(active))

func _start_binding(action: String) -> void:
	if not binding.is_empty():
		binding_buttons[binding].text = OS.get_keycode_string(game.player.keys[binding])
	binding = action
	binding_buttons[action].text = "Press a key…"
	_notice("Press Esc to cancel rebinding.")

func handle_binding(event: InputEvent) -> bool:
	if binding.is_empty() or not event is InputEventKey or not event.pressed or event.echo:
		return false
	var key: int = event.physical_keycode
	if key == KEY_ESCAPE:
		binding_buttons[binding].text = OS.get_keycode_string(game.player.keys[binding])
		binding = ""
		message.hide()
		return true
	if key == 0 or key in RESERVED:
		_notice("That key is reserved. Choose another key or press Esc.")
		return true
	for action in game.player.keys:
		if action != binding and game.player.keys[action] == key:
			_notice("%s is already assigned to %s." % [OS.get_keycode_string(key), str(action).replace("_"," ")])
			return true
	game.player.keys[binding] = key
	binding_buttons[binding].text = OS.get_keycode_string(key)
	binding = ""
	game.player.save_settings()
	_notice("Binding saved.")
	return true

func _control(value: Variant, key: String) -> void:
	game.player.set(key, value)
	save_timer.start()

func _preference(value: Variant, key: String) -> void:
	prefs.set_option(key, value)
	save_timer.start()

func _save() -> void:
	if prefs.save() != OK and is_inside_tree():
		_notice("Could not save settings.")
	game.player.save_settings()

func _reset() -> void:
	var keys: Array = []
	match active:
		"Graphics & Display":
			keys = ["vsync","fps","fov"]
			graphics.preset("Medium")
			preset = "Medium"
			pending_mode = 0
			pending_resolution = Vector2i.ZERO
		"Audio": keys = Prefs.BUS_NAMES.keys()
		"Controls":
			game.player.sensitivity = .00225
			game.player.invert_vertical = false
			game.player.invert_horizontal = false
			game.player.head_bob = false
			game.player.keys = Player.DEFAULT_KEYS.duplicate()
		"Gameplay": keys = ["prompts","notifications","room_names","hud","assists"]
		"Accessibility": keys = ["ui_scale","high_contrast","analyzer_shapes","reduced_motion"]
	for key in keys:
		prefs.set_option(key, Prefs.DEFAULTS[key])
	_save()
	_select(active)

func _update_display_action() -> void:
	apply_button.visible = active == "Graphics & Display"
	apply_button.disabled = pending_mode == prefs.values.display_mode and pending_resolution == Vector2i(prefs.values.width, prefs.values.height)

func _apply_display() -> void:
	var window := get_window()
	previous_mode = window.mode
	previous_size = window.size
	previous_position = window.position
	previewing = true
	prefs.apply_display(pending_mode, pending_resolution)
	confirmation = ConfirmationDialog.new()
	confirmation.title = "Keep display settings?"
	confirmation.ok_button_text = "Keep Changes"
	confirmation.cancel_button_text = "Revert"
	confirmation.confirmed.connect(_confirm_display)
	confirmation.canceled.connect(_restore_display)
	confirmation.close_requested.connect(_restore_display)
	add_child(confirmation)
	countdown = 12
	confirmation.dialog_text = "Reverting in %d seconds." % countdown
	confirmation.popup_centered()
	var clock := Timer.new()
	clock.wait_time = 1.0
	confirmation.add_child(clock)
	clock.timeout.connect(func():
		countdown -= 1
		if countdown <= 0:
			_restore_display()
		else:
			confirmation.dialog_text = "Reverting in %d seconds." % countdown)
	clock.start()

func _confirm_display() -> void:
	previewing = false
	prefs.values.display_mode = pending_mode
	prefs.values.width = pending_resolution.x
	prefs.values.height = pending_resolution.y
	confirmation.queue_free()
	_save()
	_update_display_action()

func _restore_display() -> void:
	if not previewing:
		return
	previewing = false
	var window := game.get_window()
	window.mode = previous_mode
	if previous_mode == Window.MODE_WINDOWED:
		window.size = previous_size
		window.position = previous_position
	if is_instance_valid(confirmation):
		confirmation.queue_free()
	pending_mode = prefs.values.display_mode
	pending_resolution = Vector2i(prefs.values.width, prefs.values.height)
	if is_inside_tree():
		_select(active)

func _exit_tree() -> void:
	if previewing:
		_restore_display()
	if is_instance_valid(save_timer) and not save_timer.is_stopped():
		_save()

func _notice(value: String) -> void:
	message.text = value
	message.show()

func _row(title: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	body.add_child(row)
	_label(row, title, 14)
	return row

func _slider(title: String, low: float, high: float, step: float, value: float, changed: Callable, format: String, scale := 1.0) -> void:
	var row := _row(title)
	var slider := HSlider.new()
	slider.min_value = low
	slider.max_value = high
	slider.step = step
	slider.value = value
	slider.size_flags_horizontal = SIZE_EXPAND_FILL
	slider.custom_minimum_size.y = 34
	row.add_child(slider)
	var readout := _label(row, format % (value * scale), 14, T.ACCENT)
	readout.custom_minimum_size.x = 56
	readout.size_flags_horizontal = SIZE_FILL
	readout.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	slider.value_changed.connect(func(next: float): readout.text = format % (next * scale); changed.call(next))

func _toggle(title: String, value: bool, changed: Callable) -> void:
	var control := CheckButton.new()
	control.custom_minimum_size.y = 32
	control.button_pressed = value
	control.toggled.connect(changed)
	_row(title).add_child(control)

func _choice(title: String, items: Array, index: int, changed: Callable) -> OptionButton:
	var pick := OptionButton.new()
	pick.size_flags_horizontal = SIZE_EXPAND_FILL
	pick.custom_minimum_size.y = 33
	for item in items:
		pick.add_item(item)
	pick.select(index)
	pick.item_selected.connect(changed)
	_row(title).add_child(pick)
	return pick

func _button(parent: Node, title: String, icon: String, action: Callable) -> Button:
	var item := Widgets.action(title, icon, action)
	item.custom_minimum_size.y = 36
	item.add_theme_font_size_override("font_size", 14)
	item.alignment = HORIZONTAL_ALIGNMENT_LEFT
	parent.add_child(item)
	return item

func _label(parent: Node, title: String, size_value: int, color := T.INK) -> Label:
	var item := Widgets.text(title)
	item.add_theme_font_size_override("font_size", size_value)
	item.add_theme_color_override("font_color", color)
	parent.add_child(item)
	return item

func _clear(parent: Node) -> void:
	for child in parent.get_children():
		parent.remove_child(child)
		child.queue_free()
