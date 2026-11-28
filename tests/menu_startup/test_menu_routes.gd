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
	var practice_store=preload("res://scripts/campus/academics/open_lab/practice/practice_sheet_store.gd")
	var identity: String=game.school.local_identity
	var stale_practice: Dictionary={"identity":identity,"project":{"title":"Old session sheet","practice_scope":"ungraded"},"answers":{"old":"work"},"strokes":{}}
	_check(practice_store.write(identity,{1:stale_practice})==OK,"Could not seed a worksheet from an old session")
	var old_practice_digest:=FileAccess.get_sha256(practice_store._path(identity))
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
		_check(front.menu_scroll.vertical_scroll_mode==ScrollContainer.SCROLL_MODE_DISABLED and not front.menu_scroll.get_v_scroll_bar().visible, label + " Play options can scroll")
		for caption in ["Back","Play"]:
			var action := _button(front.body,caption)
			_check(is_instance_valid(action) and front.menu_scroll.get_global_rect().encloses(action.get_global_rect()) and viewport_rect.encloses(action.get_global_rect()), label + " clips " + caption)
		var programming := _button(front.body,"Programming Setup")
		_usable(programming, viewport_rect, label + " Programming Setup")
		if is_instance_valid(programming):
			programming.pressed.emit()
			await process_frame
			_check(front.page=="programming" and is_instance_valid(_button(front.body,"Use public Judge0")), label+" compiler setup is missing")
			_button(front.body,"Cancel").pressed.emit()
			await process_frame
		var ai_settings := _button(front.body,"OpenAI Settings")
		_usable(ai_settings, viewport_rect, label + " OpenAI Settings")
		if is_instance_valid(ai_settings):
			ai_settings.pressed.emit()
			await process_frame
			_check(front.page=="openai", label + " did not open OpenAI Settings")
			var key_caption := "Remove connected API key" if game.host_openai.configured() else "Connect API Key"
			_check(is_instance_valid(_button(front.body,key_caption)), label + " OpenAI key control missing")
			if not game.host_openai.configured():
				_check(not is_instance_valid(_button(front.body,"Accept")), label + " showed Accept without an API key")
			_button(front.body,"Cancel").pressed.emit()
			await process_frame
			_check(front.page==("singleplayer" if offline else "host"), label + " OpenAI Cancel returned to the wrong screen")
			if OS.get_environment("LABVOLT_TEST_OPENAI_FIXTURE")=="1":
				game.host_openai.set_local_test_endpoint("http://127.0.0.1:%s/v1"%OS.get_environment("LABVOLT_OPENAI_FIXTURE_PORT") if OS.has_environment("LABVOLT_OPENAI_FIXTURE_PORT") else "http://127.0.0.1:28768/v1")
				_button(front.body,"OpenAI Settings").pressed.emit()
				await process_frame
				var controls: VBoxContainer=front.body.get_child(-1)
				if controls.remove_key.visible:
					var key_deadline:=Time.get_ticks_msec()+5000
					while controls.fetching_models and Time.get_ticks_msec()<key_deadline:await process_frame
					controls.remove_key.pressed.emit()
					_check(not game.host_openai.configured() and controls.key_row.visible,label+" did not remove the API key")
				controls.key_field.text="sk-test-12345678901234567890"
				controls.connect_button.pressed.emit()
				var deadline:=Time.get_ticks_msec()+5000
				while (controls.fetching_models or controls.model_ids.size()<11) and Time.get_ticks_msec()<deadline:await process_frame
				_check(controls.model_ids.size()==11, label + " did not load the API model list")
				_check(not controls.key_row.visible and controls.remove_key.visible,label+" connected key controls incorrect")
				controls.model.pressed.emit()
				await process_frame
				var picker_bounds:=Rect2(Vector2(controls.picker.position),Vector2(controls.picker.size))
				_check(root.get_visible_rect().encloses(picker_bounds),label+" comparison window escaped the menu viewport")
				var rows: Dictionary=controls.picker_models
				_check(rows.has("gpt-5.4-mini") and not rows.has("text-embedding-3-small") and not rows.has("gpt-image-2.6-sunburst"), label + " text picker mixed model types")
				_check(rows.get("gpt-5-nano",{}).get("benchmark")==-1.0 and rows.get("gpt-5.4-mini",{}).get("benchmark")==88.0, label + " benchmark scores were incorrect")
				_check(rows.get("gpt-5.4-mini",{}).get("price",{}).get("input")==.75 and rows["gpt-5.4-mini"].price.output==4.5, label + " published pricing was missing")
				controls.picker.hide()
				controls.model_buttons.image_generation.pressed.emit()
				_check(controls.picker_models.keys()==["gpt-image-2.6-sunburst"], label + " image generation picker mixed model types")
				controls.picker.hide()
				_check(controls.effort_row.visible and controls.model.text.begins_with("gpt-5.4-mini"), label + " text effort control missing")
				controls.model_buttons.image.pressed.emit()
				controls._choose_model("gpt-4.1")
				_check(not controls.image_effort.get_parent().visible, label + " image effort was shown for a model without reasoning")
				controls.model_buttons.image.pressed.emit()
				controls._choose_model("gpt-6.2-astra")
				_check(controls.image_effort.get_parent().visible, label + " image model effort control missing")
				controls.image_effort.select(4)
				controls.image_effort.item_selected.emit(4)
				controls.tts_enabled.button_pressed=true
				controls.stt_enabled.button_pressed=true
				controls.ai_test.pressed.emit()
				var panel: Window=controls.test_panel
				await process_frame
				if is_instance_valid(panel):
					await _check_ai_test(panel,label)
					panel.queue_free()
				else:_check(false,label+" AI Test window did not open")
				controls.output.select(3)
				var save := _button(front.body,"Accept")
				if is_instance_valid(save) and not save.disabled:save.pressed.emit()
				else:_button(front.body,"Cancel").pressed.emit()
				_check(game.host_openai.max_output_tokens==128 and game.host_openai.enabled, label + " did not accept OpenAI settings")
				_check(game.host_openai.image_reasoning_effort=="xhigh" and game.host_openai.reasoning_effort.is_empty(),label+" did not save independent reasoning settings")
				await process_frame
				_check(front.page==("singleplayer" if offline else "host"), label + " OpenAI Accept returned to the wrong screen")
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
					_check(not is_instance_valid(_button(front.screen, "Use Key")), "OpenAI key field still appears in general settings")
				front.pause_menu()
				var resume := _button(front.body, "Resume")
				if is_instance_valid(resume): resume.pressed.emit()
				await process_frame
			_check(front.in_game and not front.screen.visible and game.player.enabled,
				"%s Play failed to enter gameplay (%s)" % [label, front.status.text])
			_check(game.session.online == not offline, label + " started the wrong session type")
			_check(not game.school.papers.values().any(func(sheet):return sheet.get("project",{}).get("practice_scope","")=="ungraded"),label + " restored an old practice worksheet")
			if offline and front.in_game:
				var paper_id: int=game.school._give(1,{"title":"This session","practice_scope":"ungraded","questions":[],"difficulty":0,"topic":0,"theory":"","data":"","procedure":"","source":"Smoke test"},true,false)
				_check(paper_id>0,"Current-session practice sheet would not spawn")
				await _check_singleplayer_pause(game)
				await _check_invention_world(game)
		if front.in_game or game.session.online:
			front.leave_game()
		else:
			front.home()
		await process_frame
	_check(FileAccess.get_sha256(practice_store._path(identity))==old_practice_digest,"A fresh practice session changed the old worksheet archive")
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

func _check_ai_test(panel: Window,label: String) -> void:
	_check(panel.tabs.tab_count==5,label+" AI Test categories missing")
	await panel._run_test(true)
	_check(panel.status.text.begins_with("Connection verified"),label+" text test failed")
	panel.tabs.current_tab=1
	_check(panel.model_label.text.contains("Xhigh"),label+" image test did not use draft image effort")
	var image:=Image.create_empty(2,2,false,Image.FORMAT_RGB8)
	var image_path: String=ProjectSettings.globalize_path("user://test_image.png")
	image.save_png(image_path)
	panel._attach(image_path,true)
	await panel._run_test(false)
	_check(panel.status.text.contains("Image answer"),label+" image analysis test failed")
	panel.tabs.current_tab=2
	panel.prompt.text="Draw a blue dot"
	await panel._run_test(false)
	_check(panel.preview.visible and panel.status.text=="Image generated.",label+" image generation test failed")
	panel.tabs.current_tab=3
	_check(panel.voice_row.visible and panel.voice.item_count>1,label+" speech voice picker missing")
	panel.voice.select(2)
	await panel._run_test(false)
	_check(panel.replay.visible and panel.status.text.begins_with("Speech generated."),label+" speech output test failed")
	panel.tabs.current_tab=4
	var wav:=AudioStreamWAV.new()
	wav.format=AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate=16000
	var samples:=PackedByteArray()
	samples.resize(32000)
	wav.data=samples
	var path: String=ProjectSettings.globalize_path("user://test_voice.wav")
	wav.save_to_wav(path)
	panel._attach(path,false)
	await panel._run_test(false)
	_check(panel.status.text=="What does the board show?",label+" transcription test failed")
