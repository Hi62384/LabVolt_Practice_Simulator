extends CanvasLayer
const MenuTheme = preload("res://scripts/ui/design_system/theme.gd")
const MenuTokens = preload("res://scripts/ui/design_system/tokens.gd")
const MenuWidgets = preload("res://scripts/ui/design_system/widgets.gd")
const Session = preload("res://scripts/session.gd")
const JOIN_HISTORY := "user://join_history.cfg"
var campus_adapter: Object
var campus_dashboard: Control
var campus_hud: HBoxContainer
var navigation_room := ""
var campus_navigation = preload("res://scripts/campus/world/navigation.gd").new()
var campus_tick := 0.0
var game: Node
var screen: Control
var body: VBoxContainer
var title: Label
var status: Label
var in_game := false
var leaving_game := false
var joining := false
var page := "home"
var panel: PanelContainer
var menu_page: Control
var menu_scroll: ScrollContainer
var join_address: LineEdit
var join_port: LineEdit
var join_connect: Button
var join_back: Button
var join_spinner: ProgressBar
var join_timeout: Timer
func build(owner_game: Node) -> void:
	game=owner_game
	layer=20
	screen=Control.new()
	screen.theme=MenuTheme.create()
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(screen)
	var shade := ColorRect.new()
	shade.color=Color(.025,.045,.065,.045)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	screen.add_child(shade)
	panel = PanelContainer.new()
	panel.position=Vector2(64,64)
	panel.custom_minimum_size=Vector2(440,580)
	var style := StyleBoxFlat.new()
	style.bg_color=Color(.035,.065,.085,.94)
	style.border_color=Color("41636b")
	style.set_border_width_all(1)
	style.shadow_color=Color(0,0,0,.35)
	style.shadow_size=16
	style.set_corner_radius_all(10)
	style.content_margin_left=30
	style.content_margin_right=30
	style.content_margin_top=28
	style.content_margin_bottom=28
	var menu_skin := MenuTokens.surface(Color(0.055,0.115,0.15,0.84),MenuTokens.BORDER,20)
	panel.add_theme_stylebox_override("panel",menu_skin)
	screen.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation",15)
	panel.add_child(column)
	title=Label.new()
	title.add_theme_font_size_override("font_size",38)
	column.add_child(title)
	var subtitle := Label.new()
	subtitle.text="C O L L E G E   S I M U L A T O R"
	subtitle.modulate=Color("80dfc5")
	subtitle.add_theme_font_size_override("font_size",12)
	column.add_child(subtitle)
	menu_scroll=ScrollContainer.new()
	menu_scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	menu_scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL
	column.add_child(menu_scroll)
	body=VBoxContainer.new()
	body.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation",12)
	body.size_flags_vertical=Control.SIZE_EXPAND_FILL
	menu_scroll.add_child(body)
	status=Label.new()
	status.custom_minimum_size=Vector2(0,40)
	status.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	status.add_theme_font_size_override("font_size",14)
	column.add_child(status)
	screen.resized.connect(_layout_menu)
	game.ui.menu.hide()

	game.session.message_received.connect(func(text):status.text=text)
	game.session.roster_changed.connect(func():
		if not joining:return
		if not game.session.online:
			_set_join_pending(false)
		elif game.session.roster.has(multiplayer.get_unique_id()):
			var history := ConfigFile.new()
			history.set_value("connection", "address", _join_host(join_address.text))
			history.set_value("connection", "port", int(join_port.text.strip_edges()))
			history.save(JOIN_HISTORY)
			_set_join_pending(false)
			status.text = "Connected."
			game.capture()
	)
	join_timeout = Timer.new()
	join_timeout.one_shot = true
	join_timeout.wait_time = 12.0
	add_child(join_timeout)
	join_timeout.timeout.connect(func():
		if not joining:return
		_set_join_pending(false)
		game.session.leave()
		status.text = "Connection timed out. Check the host address and port, then try again.")
	home()
	call_deferred("_refresh_initial_home")
func _refresh_initial_home() -> void:
	if page=="home" and not in_game:home()
func clear(next_page: String,heading: String) -> void:
	if is_instance_valid(menu_page):
		screen.remove_child(menu_page)
		menu_page.queue_free()
		menu_page = null
	panel.visible = next_page not in ["view_courses", "characters", "settings"]
	page=next_page
	body.add_theme_constant_override("separation", 7 if next_page=="home" else 12)
	title.text=heading
	menu_scroll.vertical_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED if next_page in ["home","characters","join","pause"] else ScrollContainer.SCROLL_MODE_AUTO
	title.add_theme_font_size_override("font_size", 30 if next_page in ["join","host","singleplayer"] else 38)
	for child in body.get_children():
		body.remove_child(child)
		child.queue_free()
	status.text=""
	status.visible = next_page != "pause"
	panel.position=Vector2(64,32)
	panel.custom_minimum_size=Vector2(440,580)
	panel.size=Vector2(440,580)
	call_deferred("_layout_menu")
func _layout_menu() -> void:
	if not is_instance_valid(panel):return
	var available := screen.size-Vector2(32,32)
	panel.position=Vector2(32,32)
	panel.custom_minimum_size=Vector2.ZERO
	var target_width := 440
	if page in ["join","host","singleplayer"]:
		panel.size = Vector2(minf(456.0, available.x - 32), minf(448.0, available.y - 16))
		panel.position.y = maxf(16, (screen.size.y - panel.size.y) * .5)
		return
	var target_height := panel.get_combined_minimum_size().y if page == "pause" else minf(620, available.y-16)
	panel.size=Vector2(maxf(1,minf(target_width,available.x-32)),maxf(1,target_height))
func _action_icon(value: String) -> String:
	if "Back" in value or "Leave" in value:return "back"
	if "Course" in value or "Class" in value or "Lecture" in value:return "course"
	if "Settings" in value:return "settings"
	if "Character" in value:return "palette"
	if "Shop" in value:return "cart"
	if "Join" in value or "Connect" in value:return "network"
	if "Quit" in value:return "close"
	if "sheet" in value:return "inventory"
	return "play"
func button(text: String,callback: Callable) -> void:
	var control := _host_button(text,body,callback)
	if page=="home":control.custom_minimum_size.y=44
	if text in ["Host Game","Connect","Resume"]:control.theme_type_variation="PrimaryButton"
	elif text in ["Quit","Leave to Main Menu"]:control.theme_type_variation="DangerButton"
func text(value: String) -> void:
	var label := Label.new()
	label.text=value
	label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	body.add_child(label)
func field(value: String,hint: String) -> LineEdit:
	_host_label(hint,body,14)
	var input := LineEdit.new()
	input.text=value
	input.placeholder_text=hint
	input.custom_minimum_size.y=38
	body.add_child(input)
	return input
func home() -> void:
	if joining:
		_set_join_pending(false)
		game.session.leave()
	if not in_game and is_instance_valid(game.menu_campus):game.menu_campus.show_menu()
	screen.show()
	clear("home","LAB/VOLT")
	text("Learn. Explore. Experiment.")
	button("Host Game",func():network_page(false))
	button("Singleplayer",singleplayer_page)
	button("Join Game",func():network_page(true))
	button("View Courses",view_courses_page)
	button("Character Customizer",characters_page)
	button("Settings",settings_page)
	button("Quit",func():game.get_tree().quit())
func network_page(join: bool) -> void:
	clear("join" if join else "host","JOIN GAME" if join else "HOST GAME")
	if join:
		_build_join()
		return
	_build_play(false)

func _build_join() -> void:
	text("Connect to a hosted college session.")
	var fields := _session_form()
	var history := ConfigFile.new()
	history.load(JOIN_HISTORY)
	join_address = _join_field(fields, "Host address", str(history.get_value("connection", "address", "")), "IP or hostname, e.g. 192.168.1.20")
	join_address.max_length = 253
	join_port = _join_field(fields, "Port", str(history.get_value("connection", "port", Session.PORT)), str(Session.PORT))
	join_port.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	join_port.custom_minimum_size.x = 110
	join_port.max_length = 5
	var actions := _session_actions("Connect", "network", _connect_to_host)
	join_back = actions.get_child(0)
	join_connect = actions.get_child(1)
	join_spinner = ProgressBar.new()
	join_spinner.indeterminate = true
	join_spinner.show_percentage = false
	join_spinner.custom_minimum_size.y = 6
	body.add_child(join_spinner)
	join_spinner.hide()
	join_address.text_submitted.connect(func(_value: String): _connect_to_host())
	join_port.text_submitted.connect(func(_value: String): _connect_to_host())
	join_address.grab_focus.call_deferred()

func _session_form() -> VBoxContainer:
	var form := PanelContainer.new()
	body.add_child(form)
	var fields := VBoxContainer.new()
	fields.add_theme_constant_override("separation", 7)
	form.add_child(fields)
	_host_label("Playing as " + game.characters.display_name(), fields, 17)
	return fields

func _session_actions(caption: String, icon: String, action: Callable) -> HBoxContainer:
	var row := HBoxContainer.new()
	body.add_child(row)
	var back := MenuWidgets.action("Back", "back", home)
	var primary := MenuWidgets.action(caption, icon, action, true)
	for control in [back, primary]:
		control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		control.custom_minimum_size.y = 46
		row.add_child(control)
	return row

func _build_play(offline: bool) -> void:
	text("Explore the campus on your own." if offline else "Host a college session for other players to join.")
	var fields := _session_form()
	var port: LineEdit
	var forwarding: CheckButton
	if not offline:
		var advanced := MenuWidgets.action("Advanced Settings", "settings", Callable())
		advanced.toggle_mode = true
		fields.add_child(advanced)
		var options := VBoxContainer.new()
		fields.add_child(options)
		options.hide()
		port = _join_field(options, "Port", str(Session.PORT), str(Session.PORT))
		port.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		port.custom_minimum_size.x = 110
		port.max_length = 5
		forwarding = CheckButton.new()
		forwarding.text = "Try automatic internet port forwarding (UPnP)"
		options.add_child(forwarding)
		_host_label("For internet play, share your public IP and UDP port. If automatic forwarding fails, forward the port on your router.", options, 14)
		advanced.toggled.connect(func(open: bool): options.visible = open)
		port.text_submitted.connect(func(_value: String): _start_play(false, port, forwarding))
	_session_actions("Play", "play", _start_play.bind(offline, port, forwarding))

func _start_play(offline: bool, port: LineEdit, forwarding: CheckButton) -> void:
	var id: String = game.characters.selected
	if not id.is_empty() and not game.characters.profiles.any(func(profile): return profile.id == id):
		status.text = "Select an available character before playing."
		return
	var port_number := Session.PORT
	if not offline:
		var value := port.text.strip_edges()
		if not value.is_valid_int() or int(value) < 1024 or int(value) > 65535:
			status.text = "Enter a port between 1024 and 65535."
			port.grab_focus()
			return
		port_number = int(value)
	var player_name: String = game.characters.display_name()
	game.menu_campus.hold(true)
	if offline:
		game.session.local_name = player_name
		game.session.leave()
	else:
		var error: Error = game.session.host_game(player_name, port_number, forwarding.button_pressed)
		if error != OK:
			game.menu_campus.hold(false)
			status.text = "Could not host on port %d. %s" % [port_number, error_string(error)]
			return
	var result: Dictionary = game.school.start_activity({"mode": "Freeplay"})
	if not result.get("ok", false):
		game.session.leave()
		game.menu_campus.hold(false)
		status.text = str(result.get("error", "Could not start Play."))
		return
	game.ui.name_input.text = player_name
	if offline:game.dc_lab.restore_carried_pcbs(1)
	game.capture()

func _join_field(parent: VBoxContainer, caption: String, value: String, placeholder: String) -> LineEdit:
	_host_label(caption, parent, 14)
	var input := LineEdit.new()
	input.accessibility_name = caption
	input.text = value
	input.placeholder_text = placeholder
	input.custom_minimum_size.y = 40
	parent.add_child(input)
	return input

func _connect_to_host() -> void:
	if joining:return
	var id: String = game.characters.selected
	if not id.is_empty() and not game.characters.profiles.any(func(profile):return profile.id == id):
		status.text = "Select an available character before connecting."
		return
	var address := _join_host(join_address.text)
	if address.is_empty():
		status.text = "Enter a valid IP address or hostname."
		join_address.grab_focus()
		return
	var port_value := join_port.text.strip_edges()
	if not port_value.is_valid_int() or int(port_value) < 1 or int(port_value) > 65535:
		status.text = "Enter a port from 1 to 65535."
		join_port.grab_focus()
		return
	var player_name: String = game.characters.display_name()
	var result: Error = game.session.join_game(address, player_name, int(port_value))
	if result != OK:
		status.text = "Could not start the connection. " + error_string(result)
		return
	game.ui.name_input.text = player_name
	_set_join_pending(true)
	status.text = "Connecting…"

func _set_join_pending(value: bool) -> void:
	joining = value
	if not is_instance_valid(join_connect):return
	join_connect.disabled = value
	join_address.editable = not value
	join_port.editable = not value
	join_back.text = "Cancel" if value else "Back"
	join_spinner.visible = value
	if value:join_timeout.start()
	else:join_timeout.stop()

static func _join_host(raw: String) -> String:
	var value := raw.strip_edges()
	if value.begins_with("[") and value.ends_with("]"):value = value.substr(1, value.length() - 2)
	if value.is_valid_ip_address():return value
	var hostname := value.trim_suffix(".")
	if hostname.is_empty() or hostname.length() > 253:return ""
	var pattern := RegEx.create_from_string("^[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?$")
	var numeric := RegEx.create_from_string("^[0-9.]+$")
	if numeric.search(hostname):return ""
	for part in hostname.split("."):
		if not pattern.search(part):return ""
	return value

func singleplayer_page() -> void:
	clear("singleplayer","SINGLEPLAYER")
	_build_play(true)

func _mount_page(control: Control, source: Node) -> void:
	menu_page = control
	screen.add_child(menu_page)
	menu_page.build(source)
	menu_page.closed.connect(pause_menu if in_game else home)

func _host_label(value: String,parent: Node,size := 16) -> Label:
	var label := MenuWidgets.text(value,"SubtitleLabel" if size>=18 else "Label");label.add_theme_font_size_override("font_size",size);parent.add_child(label);return label

func _host_button(value: String,parent: Node,callback: Callable,toggle := false) -> Button:
	var control := MenuWidgets.action(value,_action_icon(value),callback);control.custom_minimum_size.y=52;control.alignment=HORIZONTAL_ALIGNMENT_LEFT;control.toggle_mode=toggle
	control.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	control.pressed.connect(func():game.sfx.play("ui"));parent.add_child(control)
	if toggle:control.toggled.connect(func(selected):control.theme_type_variation="PrimaryButton" if selected else "Button")
	return control

func view_courses_page() -> void:
	if not is_instance_valid(game.school):return
	clear("view_courses","View Courses")
	_mount_page(preload("res://scripts/campus/ui/gradebook_page.gd").new(), game.school)

func set_campus_adapter(adapter: Object) -> void:
	campus_adapter=adapter
	if adapter.has_signal("navigation_requested") and not adapter.navigation_requested.is_connected(_campus_navigate): adapter.navigation_requested.connect(_campus_navigate)
	if not is_instance_valid(campus_hud):
		campus_hud=preload("res://scripts/campus/ui/campus_hud.gd").new(); campus_hud.position=Vector2(28,128); add_child(campus_hud)
func _campus_navigate(room_id: String) -> void:
	if room_id.is_empty():
		navigation_room=""
		campus_navigation.clear()
	elif campus_navigation.select_room(room_id,game.player.global_position):
		navigation_room=room_id
func campus_page() -> void:
	if not is_instance_valid(campus_adapter) and ResourceLoader.exists("res://scripts/campus/world/room_registry.gd") and ResourceLoader.exists("res://scripts/campus_course_provider.gd"):
		campus_adapter=preload("res://scripts/campus/ui/campus_adapter.gd").new()
		campus_adapter.configure(game.school,load("res://scripts/campus/world/room_registry.gd").new(),load("res://scripts/campus_course_provider.gd").new())
		set_campus_adapter(campus_adapter)
	if not is_instance_valid(campus_adapter):
		status.text="Campus services are not connected yet. Use the laboratory menus below."
		return
	if is_instance_valid(campus_dashboard): return
	campus_dashboard=preload("res://scripts/campus/ui/campus_dashboard.gd").new()
	screen.add_child(campus_dashboard)
	campus_dashboard.build(campus_adapter)
	campus_dashboard.activity_started.connect(func():campus_dashboard.queue_free(); game.capture())
func settings_page() -> void:
	clear("settings","Settings")
	_mount_page(preload("res://scripts/campus/ui/settings_page.gd").new(), game)
func pause_menu() -> void:
	game.release_mouse()
	screen.show()
	clear("pause","MENU")
	button("Resume",func():game.capture())
	button("View Courses",view_courses_page)
	button("Settings",settings_page)
	button("Leave to Main Menu",leave_game)
func leave_game() -> void:
	if leaving_game:return
	leaving_game=true
	joining=false
	_campus_navigate("")
	game._stand_from_chair()
	game.session.leave()
	in_game=false
	game.school._identity_changed()
	game.school.start("Freeplay",0)
	game.shop_room.active=false
	game.release_mouse()
	home()
	leaving_game=false
func entered() -> void:
	in_game=true
	screen.hide()
	if is_instance_valid(game.menu_campus):game.menu_campus.enter_game()
	game.camera.current=true
func escape() -> void:
	if screen.visible:
		if page not in ["home","pause"]:
			if in_game:pause_menu()
			else:home()
		elif in_game:game.capture()
	else:pause_menu()
func characters_page() -> void:
	clear("characters","Your Characters")
	_mount_page(preload("res://scripts/campus/ui/character_selector.gd").new(), game)

func _process(delta: float) -> void:
	campus_tick+=delta
	if is_instance_valid(campus_hud):
		campus_hud.visible=in_game and not screen.visible and game.client_preferences.values.hud
		if in_game and campus_tick>=0.25 and is_instance_valid(campus_adapter) and is_instance_valid(campus_adapter.registry):
			campus_tick=0.0
			var registry: Object=campus_adapter.registry
			var room: Dictionary=registry.call("get_room",registry.call("locate",game.player.global_position))
			var state: Dictionary=game.school.get("activity") if game.school.has_method("start_activity") else {"mode":game.school.mode}
			campus_hud.update_state(room,state,float(game.school.remaining) if game.school.phase=="assignment" else -1.0,campus_navigation.update(game.player.global_position))
			if not game.client_preferences.values.room_names:
				campus_hud.location.get_parent().get_parent().hide()

func experiment_page() -> void:
	clear("experiment","EXPERIMENT")
	text("Configure the nearest workstation.")
	var mode := OptionButton.new()
	for name in ["Free Laboratory","Guided Learning","Practical Exam","Cooperative Challenge"]:mode.add_item(name)
	body.add_child(mode)
	var task := OptionButton.new()
	for name in ["Balanced Wye","Balanced Delta","Power factor correction"]:task.add_item(name)
	body.add_child(task)
	var component := OptionButton.new()
	for name in ["Resistors","Inductors","Capacitors"]:component.add_item(name)
	body.add_child(component)
	button("Apply",func():game._request({"op":"configure","mode":mode.get_item_text(mode.selected),"task":task.selected,"element":component.selected});status.text="Requested workstation setup.")
	button("Back",pause_menu)
