extends SceneTree

# Run only with an isolated user-data directory after the startup import gate.
const RelayAccount = preload("res://scripts/relay_account.gd")
const Session = preload("res://scripts/session.gd")
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
	_check(not game.held_hint.visible and not game.held_item_name.visible, "Item instructions appeared over main menu")
	_check(front.layer>game.health.overlay.layer, "Pause menu must appear above the death screen")
	_check(not game.paper_ui.has_method("daq_page"), "Removed Computer I/O menu is still available")
	_check(game.control_bodies.daq.get_meta("role", "") == "ac_daq_usb", "Computer I/O cable connection missing")
	_check(game.terminal_bodies.has("DAQ_POWER_A") and game.terminal_bodies.has("DAQ_POWER_B"), "DAQ low-power sockets missing")
	_check(game.campus.registry.rooms.has("circuit_studio"), "Circuit Studio missing from campus directory")
	_check(is_instance_valid(game.circuit_studio) and game.circuit_studio.mount_succeeded, "Circuit Studio failed to mount")
	if is_instance_valid(game.circuit_studio) and game.circuit_studio.mount_succeeded:
		_check(game.circuit_studio.room.adapter.stations.size() == 5, "Circuit Studio workstations missing")
		_check(game.campus.streamer.contents.has("circuit_studio"), "Circuit Studio is not streamed into campus")
		for action in ["ic_builder", "pcb_builder", "assembly_table"]:
			var station: Node=game.circuit_studio.room.station_anchors.get(action)
			_check(is_instance_valid(station), action + " target missing")
			if is_instance_valid(station):
				_check(game.circuit_studio.interact(station), action + " did not open")
				var window: Window=game.circuit_studio.room.adapter.builder_window
				_check(is_instance_valid(window) and (window.title == "Invention Assembly Studio" if action == "assembly_table" else window.kind == ("IC" if action == "ic_builder" else "PCB")), action + " opened wrong editor")
				if action=="assembly_table" and is_instance_valid(window):
					window.draft=preload("res://scripts/campus/facilities/circuit_studio/assembly_model.gd").empty()
					window._editor()
					_check(window.find_children("*","Control",true,false).any(func(node):return node.get_script()==preload("res://scripts/campus/facilities/circuit_studio/assembly_preview.gd")),"Assembly editor preview missing")
				if is_instance_valid(window):
					window._close()
					if action=="assembly_table":
						var discard_prompts: Array=window.get_children().filter(func(node):return node is ConfirmationDialog)
						_check(discard_prompts.size()==1,
							"Closing an unsaved assembly draft must request confirmation")
						if not discard_prompts.is_empty():discard_prompts[0].confirmed.emit()
				await process_frame
	if game.terminal_bodies.has("DAQ_POWER_A"):
		var indicator := game.terminal_bodies.DAQ_POWER_A.get_parent().get_node_or_null("DaqPowerIndicator") as MeshInstance3D
		_check(is_instance_valid(indicator) and not indicator.material_override.emission_enabled, "DAQ indicator must start off")
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
		if not offline and Session.relay_endpoint().is_empty():
			_usable(_button(front.body, "Relay account · Not connected"), viewport_rect, "Relay account setup")
			_check(is_instance_valid(play) and play.disabled, "Hosting must require a relay account")
			front.home()
			continue
		_usable(play, viewport_rect, label + " Play")
		if is_instance_valid(play):
			play.pressed.emit()
			await process_frame
			if not offline and not Session.relay_endpoint().is_empty():
				var deadline := Time.get_ticks_msec() + 12000
				while not front.in_game and front.pending_host != null and Time.get_ticks_msec() < deadline:
					await process_frame
				_check(game.session.room_code().length() == 10, "Relay host did not receive a room code")
				_check(front.notice_time > 0, "Host room code notice missing")
				front.pause_menu()
				_check(not paused, "Host menu paused the multiplayer session")
				front.settings_page()
				await process_frame
				var host_server := _button(front.screen, "Host Server")
				_usable(host_server, viewport_rect, "Host Server settings")
				if is_instance_valid(host_server):
					host_server.pressed.emit()
					await process_frame
					_usable(_button(front.screen, "Copy Room Code"), viewport_rect, "Copy Room Code")
					_check(is_instance_valid(_button(front.screen, "Use Key")), "Host OpenAI key control missing")
					_check(is_instance_valid(_button(front.screen, "Test Connection")), "Host OpenAI connection control missing")
				front.pause_menu()
				var resume := _button(front.body, "Resume")
				if is_instance_valid(resume): resume.pressed.emit()
				await process_frame
			_check(front.in_game and not front.screen.visible and game.player.enabled,
				"%s Play failed to enter gameplay (%s)" % [label, front.status.text])
			_check(game.session.online == not offline, label + " started the wrong session type")
			if offline and front.in_game:
				await _check_singleplayer_pause(game)
				await _check_invention_world(game)
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
	var personal_code := RelayAccount.invite("labvolt-relay.example-team.workers.dev", "ABCDEFGHJK")
	var invite := RelayAccount.parse_invite(personal_code, "")
	_check(invite == {"code": "ABCDEFGHJK", "endpoint": "wss://labvolt-relay.example-team.workers.dev"}, "Personal room code did not route to its relay")
	_check(RelayAccount.parse_invite("ABCDEFGHJK@example.com/path", "").is_empty(), "Invalid room relay address accepted")
	_check_food_icons()
	_finish()

func _check_singleplayer_pause(game: Node) -> void:
	var front: Node = game.front
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.physical_keycode = KEY_ESCAPE
	escape.pressed = true
	root.push_input(escape)
	await process_frame
	_check(paused and front.page == "pause" and front.screen.visible, "Esc did not pause singleplayer")
	_check(front.can_process() and not game.player.can_process(), "Pause did not freeze gameplay with the menu responsive")
	var settings := _button(front.body, "Settings")
	if is_instance_valid(settings):
		settings.pressed.emit()
		await process_frame
		_check(paused and front.page == "settings", "Opening Settings resumed singleplayer")
		var labels: Array[String] = []
		for label in front.menu_page.find_children("*", "Label", true, false):
			labels.append(label.text)
		for spec in game.ui.graphics_controller.ENVIRONMENT_CONTROLS.values():
			_check(labels.has(spec[0]), "Graphics & Display is missing " + spec[0])
		root.push_input(escape)
		await process_frame
		_check(paused and front.page == "pause", "Esc from Settings did not return to the paused menu")
	root.push_input(escape)
	await process_frame
	_check(not paused and game.player.enabled and not front.screen.visible, "Esc did not resume singleplayer")
	front.pause_menu()
	var resume := _button(front.body, "Resume")
	if is_instance_valid(resume): resume.pressed.emit()
	_check(not paused and game.player.enabled, "Resume button did not resume singleplayer")
	if paused: game.capture()

func _check_invention_world(game: Node) -> void:
	var model=preload("res://scripts/campus/facilities/circuit_studio/assembly_model.gd")
	var saved_profile: Dictionary=game.electronics.profile.data.duplicate(true)
	var saved_pose: Vector3=game.player.global_position
	var invention:=model.empty("Test cart")
	invention.parts.append({"type":"battery","x":1,"y":0,"z":0,"control":"","ref":""})
	invention.parts.append({"type":"dc_motor","x":0,"y":1,"z":0,"control":"A","ref":""})
	invention.parts.append({"type":"wheel","x":1,"y":1,"z":0,"control":"","ref":""})
	invention.parts.append({"type":"switch","x":2,"y":0,"z":0,"control":"A","ref":""})
	game.electronics.profile.data.inventions={"inv:test":invention}
	game.electronics.profile.data.invention_copies={"inv:test":1}
	game.player.global_position=Vector3(20,5,50)
	await physics_frame
	game.invention_world.request_place("inv:test")
	_check(game.invention_world.placed.size()==1,"Fabricated invention did not appear in the world")
	if game.invention_world.placed.size()==1:
		var key: String=str(game.invention_world.placed.keys()[0])
		var before: Vector3=game.invention_world.placed[key].position
		var view: StaticBody3D=game.invention_world.visuals[key]
		var solid: StaticBody3D=view.get_node("Solid") as StaticBody3D
		_check(game._resolve_invention_hit(solid)==view,"A physical invention collider did not resolve to its retrieve action")
		var actuator: StaticBody3D=view.find_child("ControlA",true,false) as StaticBody3D
		_check(is_instance_valid(actuator) and actuator.get_parent().get_meta("assembly_kind","")=="switch",
			"Invention control A is not attached to the placed physical switch")
		game.invention_world._apply(1,{"op":"control","key":key,"control":"A","pressed":true})
		game.invention_world._physics_process(.25)
		_check(game.invention_world.placed[key].position.distance_to(before)>.01,"Powered wheels did not move")
		game.invention_world._apply(1,{"op":"pickup","key":key})
		_check(game.invention_world.placed.is_empty(),"Invention copy could not be retrieved")
	var board_model=preload("res://scripts/breadboard_model.gd")
	var source: Dictionary=board_model.empty()
	source.parts=[{"id":"gate","type":"toggle","a":"A1","b":"A2"},{"id":"pull","type":"r1000","a":"A2","b":"F1"}]
	var pcb: Dictionary=board_model.blueprint(source,"Drive PCB")
	pcb.package="PCB";pcb.footprint={"width":8,"height":8,"color":"24775b"}
	pcb.layout={"rows":30,"parts":source.parts.duplicate(true),"wires":[]}
	pcb.pins=[{"name":"VCC","node":"L1"},{"name":"GND","node":"R1"},{"name":"OUT_A","node":"L2"}]
	var powered:=model.empty("PCB cart")
	powered.drive.A="pcb"
	powered.parts.append({"type":"battery","x":1,"y":0,"z":0,"control":"","ref":""})
	powered.parts.append({"type":"dc_motor","x":0,"y":1,"z":0,"control":"A","ref":""})
	powered.parts.append({"type":"wheel","x":1,"y":1,"z":0,"control":"","ref":""})
	powered.parts.append({"type":"pcb","x":2,"y":0,"z":0,"control":"","ref":"ic:drive_test","pin_map":{"power":0,"ground":1,"A":2,"B":-1}})
	game.electronics.profile.data.blueprints={"ic:drive_test":pcb}
	game.electronics.profile.data.inventions={"inv:pcb_test":powered}
	game.electronics.profile.data.invention_copies={"inv:pcb_test":1}
	_check(model.validate("inv:pcb_test",game.electronics.profile.data.inventions,game.electronics.profile.data.blueprints)=="","Mapped PCB assembly is invalid")
	game.circuit_studio.interact(game.circuit_studio.room.station_anchors.assembly_table)
	var editor: Window=game.circuit_studio.room.adapter.builder_window
	editor.draft=model.empty("Editor mapping")
	editor._editor()
	for option in editor.part_kind.item_count:
		if editor.part_kind.get_item_metadata(option)=="pcb":editor.part_kind.select(option);break
	editor._reference_options()
	editor.part_x.value=2
	editor._add_part()
	_check(editor.draft.parts.back().get("pin_map",{}).get("A",-1)==2,"Assembly editor did not map PCB output A")
	editor._close()
	var draft_prompts: Array=editor.get_children().filter(func(node):return node is ConfirmationDialog)
	_check(draft_prompts.size()==1,"Unsaved PCB assembly draft must offer discard confirmation")
	if not draft_prompts.is_empty():draft_prompts[0].confirmed.emit()
	await process_frame
	game.invention_world.request_place("inv:pcb_test")
	_check(game.invention_world.placed.size()==1,"PCB invention did not appear")
	if game.invention_world.placed.size()==1:
		var pcb_key: String=str(game.invention_world.placed.keys()[0])
		game.invention_world._physics_process(.06)
		_check(not game.invention_world.placed[pcb_key].effective.A,"Open PCB switch unexpectedly drives motor")
		game.invention_world.request_pcb_input(pcb_key,"board/pcb/gate",true)
		var pcb_before: Vector3=game.invention_world.placed[pcb_key].position
		game.invention_world._physics_process(.06)
		_check(float(game.invention_world.placed[pcb_key].pcb_voltage.A)>2.5 and game.invention_world.placed[pcb_key].effective.A,"Live PCB output did not drive motor")
		_check(game.invention_world.placed[pcb_key].position.distance_to(pcb_before)>.01,"PCB-powered wheels did not move")
		game.invention_world._process(.01)
		var pcb_target: Node
		for node in game.invention_world.visuals[pcb_key].find_children("*","StaticBody3D",true,false):
			if node.get_meta("role","")=="invention_pcb":pcb_target=node;break
		_check(is_instance_valid(pcb_target) and game.invention_world.interact(pcb_target),"Mounted PCB panel did not open")
		if is_instance_valid(game.invention_world.pcb_panel):game.invention_world.pcb_panel._close()
		game.invention_world._apply(1,{"op":"pickup","key":pcb_key})
	game.electronics.profile.data=saved_profile
	game.player.global_position=saved_pose

func _check_food_icons() -> void:
	var rules = preload("res://scripts/campus/facilities/facility_host.gd").new()
	var portraits = preload("res://scripts/ui/personal_inventory/item_portraits.gd").new()
	for item: String in rules.menu:
		_check(portraits.texture({"kind":"food","type":item}, null) != null, item + " inventory icon missing")
	for venue: String in ["tim_hortons", "subway"]:
		var categories := {}
		for entry in rules.menu.values():
			if entry.venue == venue:categories[entry.category]=int(categories.get(entry.category,0))+1
		for category in categories:
			var panel = preload("res://scripts/campus/facilities/facility_panel.gd").new()
			root.add_child(panel)
			panel.state = {"menu":rules.menu}
			if venue=="tim_hortons":panel.cafe_category=category
			else:panel.subway_category=category
			panel._restaurant_menu(venue, Color.WHITE, Color.BLACK)
			var icons: Array[Node] = panel.find_children("*", "TextureRect", true, false)
			_check(icons.size() == int(categories[category]), venue + " category must display every food icon")
			for icon: TextureRect in icons:
				_check(icon.texture != null, venue + " menu food icon missing")
			panel.queue_free()

func _finish() -> void:
	for failure in failures:push_error(failure)
	print("MENU_ROUTES ", "PASS" if failures.is_empty() else "FAIL (%d)" % failures.size())
	quit(0 if failures.is_empty() else 1)
