extends "res://scripts/campus/performance/equipment_builder_adapter.gd"
## Photo-inspired equipment builder is retained in equipment_builder.gd. Gameplay uses
## LabState through Session; the legacy example shortcuts are never invoked.
const Session = preload("res://scripts/session.gd")
const FirstPerson = preload("res://scripts/first_person.gd")
const Interface = preload("res://scripts/lab_ui.gd")
const CableMesh = preload("res://scripts/cable_mesh.gd")
var supply_flashlight: SpotLight3D
var open_lab_tutorial

var cable_obstacles:Array[AABB]=[]
var inspect_camera: Camera3D
var inspect_rotation := Vector3.ZERO
var inspection_views := {}
var inspection_view_key := ""
var inspection_views_loaded := false
var hotbar: CanvasLayer
var electronics_trade: Node
var kit_world: Node3D
var discarded_items: Node3D
var lecture_classes: Node3D
var campus_services: Node
var campus: Node3D
var shop_room: Node3D
var circuit_studio: Node
var washroom_finish: Node
var dorm_rest: Node
var dorm_interactions: Node
var electronics: CanvasLayer
var dc_lab: Node3D
var school: Node
var computers: Node
var computer_room_adapter: Node
var campus_performance: Node
var school_world: Node3D
var paper_ui: CanvasLayer
var characters: Node
var front: CanvasLayer
var menu_campus: Node
var client_preferences = preload("res://scripts/campus/ui/client_preferences.gd").new()
var interaction_presentation: Node
var avatar_data := {}
var cosmetic_appearances := {}
var standing_pending := false
var standing_chair_index := -1
var chair_packet_sequence := 0
var chair_packet_revisions := {}
var displayed_station := -1
var chair_clock := 0.0
var chair_input_times := {}
var stations: Array = []
var station_snapshots: Array = []
var chairs: Array = []
var carry_visuals := {}
var sfx: Node
var held_hint: Label
var held_item_name: Label
var drawer: Node3D
var lab_challenges: Node
var session: Node
var ui: CanvasLayer
var snapshot := {}
var avatars := {}
var avatar_targets := {}
var avatar_last_movement := {}
var physical_readouts := {}
var meter_targets := {}
var telemetry := false
var network_clock := 0.0
var cable_clock := 0.0
var carried_root: Node3D
var drag_knob := ""
var drag_amount := 0.0
var drag_station := 0
var measuring_station := -1
var highlighted: StaticBody3D
var highlighted_scale := Vector3.ONE
var tone: AudioStreamPlayer
var steps_clock := 0.0
var history: Array = []
var last_result := ""
var rotor: Node3D
var rotor_speed := 0.0
var motor_label: Label3D
var motor_audio: AudioStreamPlayer3D

func open_lab_equipment_tutorial() -> void:
	if not is_instance_valid(open_lab_tutorial):
		open_lab_tutorial=preload("res://scripts/campus/academics/open_lab/tutorials/controller.gd").new()
		add_child(open_lab_tutorial)
	if not open_lab_tutorial.open(self):
		ui.log_message("Equipment tutorial is available in the M101 or M103 Open Lab.")

func _ready() -> void:
	sfx = preload("res://scripts/lab_audio.gd").new()
	add_child(sfx)
	_reset_switches()
	_build_environment()
	for child in get_children():
		if child is DirectionalLight3D:
			child.light_energy = .6
			child.shadow_enabled = true
			child.directional_shadow_max_distance = 20
		elif child is OmniLight3D:
			child.light_energy = .35
		elif child is WorldEnvironment:
			child.environment.ambient_light_energy = .38
	_build_player()
	_build_station()
	_build_room()
	carried_root = Node3D.new()
	add_child(carried_root)
	session = Session.new()
	session.name = "Session"
	session.restarted.connect(func():chair_packet_revisions.clear();standing_pending=false;standing_chair_index=-1)
	session.campus_enabled=true
	add_child(session)
	characters=preload("res://scripts/character_library.gd").new()
	add_child(characters)
	ui = Interface.new()
	add_child(ui)
	ui.build(self)
	front=preload("res://scripts/front_menu.gd").new()
	add_child(front)
	front.build(self)
	characters.changed.connect(_character_selected)
	session.appearance_received.connect(_appearance_received)
	interaction_presentation=preload("res://scripts/interaction_presentation/bridge.gd").new()
	add_child(interaction_presentation)
	interaction_presentation.attach(self)
	session.interaction_accepted.connect(interaction_presentation.accepted)
	session.leaving.connect(interaction_presentation.session_transition)
	_character_selected()
	held_hint=Label.new()
	held_hint.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	held_hint.position=Vector2(-220,-126)
	held_hint.size=Vector2(440,24)
	held_hint.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	held_hint.add_theme_font_size_override("font_size",14)
	ui.add_child(held_hint)
	held_item_name=Label.new()
	held_item_name.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	held_item_name.position=Vector2(-250,-150)
	held_item_name.size=Vector2(500,24)
	held_item_name.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	ui.add_child(held_item_name)
	session.changed.connect(_receive_state)
	session.ac_readings_changed.connect(_receive_ac_readings)
	session.message_received.connect(func(text):
		ui.log_message(text)
		if text.contains("failed") or text.contains("Host disconnected"):
			ui.connection_label.text=text
	)
	session.roster_changed.connect(_roster_changed)
	session.pose_received.connect(_receive_pose)
	var locations := {"storage":Vector3(0,.4,-1.7)}
	for id in terminal_bodies:
		locations[id] = terminal_bodies[id].global_position
	for key in switch_meshes:
		locations[key] = switch_meshes[key].handle.get_parent().global_position
	for id in control_bodies:
		locations[id] = control_bodies[id].global_position
	for station in stations:
		var equipment: Node3D=station.equipment
		var positions := {"storage":Vector3(equipment.position.x,.4,-1.7)}
		for id in equipment.terminal_bodies:
			positions[id]=equipment.terminal_bodies[id].global_position
		for id in equipment.control_bodies:
			positions[id]=equipment.control_bodies[id].global_position
		for id in equipment.switch_meshes:
			positions[id]=equipment.switch_meshes[id].handle.get_parent().global_position
		session.add_station(equipment.terminal_ids,positions)
		for id in equipment.terminal_bodies:
			terminal_bodies[str(stations.find(station)+1)+":"+id]=equipment.terminal_bodies[id]
	session.initialize(terminal_ids,locations)
	tone = AudioStreamPlayer.new()
	tone.bus = "Effects"
	tone.volume_db = -25
	add_child(tone)
	motor_audio = AudioStreamPlayer3D.new()
	motor_audio.bus = "Effects"
	motor_audio.position = rotor.position
	motor_audio.max_distance = 9
	motor_audio.unit_size = 2
	motor_audio.volume_db = -30
	var hum := AudioStreamWAV.new()
	hum.format = AudioStreamWAV.FORMAT_16_BITS
	hum.mix_rate = 22050
	hum.loop_mode = AudioStreamWAV.LOOP_FORWARD
	hum.loop_end = 22050
	var samples := PackedByteArray()
	samples.resize(44100)
	for i in range(22050):
		samples.encode_s16(i*2,int((sin(TAU*120*i/22050)+.2*sin(TAU*240*i/22050))*8000))
	hum.data = samples
	motor_audio.stream = hum
	add_child(motor_audio)
	var file := FileAccess.open("user://history.json",FileAccess.READ)
	if file:
		var parsed = JSON.parse_string(file.get_as_text())
		if parsed is Array:
			history = parsed
	ui.update_records(history)
	school=preload("res://scripts/school_session.gd").new()
	school.name="School"
	add_child(school)
	school.build(self)
	school.updated.connect(_sync_supply_accessories)
	computers=preload("res://scripts/campus/computers/computer_sessions.gd").new()
	computers.name="ComputerSessions"
	add_child(computers)
	computers.build(self)
	paper_ui=preload("res://scripts/paper_ui.gd").new()
	add_child(paper_ui)
	paper_ui.build(self)
	school_world=preload("res://scripts/school_world.gd").new()
	add_child(school_world)
	school_world.build(self)
	dc_lab=preload("res://scripts/dc_lab.gd").new()
	dc_lab.name="DCLaboratory"
	add_child(dc_lab)
	dc_lab.campus_offset=Vector3(0,0,15.15)
	dc_lab.build(self)
	electronics=preload("res://scripts/electronics_ui.gd").new();add_child(electronics);electronics.build(self)
	hotbar=preload("res://scripts/carry_hotbar.gd").new();add_child(hotbar);hotbar.build(self)
	shop_room=preload("res://scripts/shop_room.gd").new();add_child(shop_room);shop_room.build_campus(self,campus)
	kit_world=preload("res://scripts/kit_world.gd").new();add_child(kit_world);kit_world.build(self)
	electronics_trade=preload("res://scripts/electronics_trade.gd").new();add_child(electronics_trade);electronics_trade.build(self)
	dorm_interactions=preload("res://scripts/campus/dorms/integration/coordinator.gd").new()
	dorm_interactions.name="Dorms";add_child(dorm_interactions);dorm_interactions.build(self)
	discarded_items=preload("res://scripts/ui/personal_inventory/discard_world.gd").new()
	discarded_items.name="DiscardedItems";add_child(discarded_items);discarded_items.build(self)
	lecture_classes=preload("res://scripts/campus/academics/class_start/room_classes.gd").new()
	lecture_classes.name="LectureClasses";add_child(lecture_classes);lecture_classes.build(self)
	preload("res://scripts/room_finish.gd").build(self)
	campus_services=preload("res://scripts/campus_integration.gd").new()
	campus_services.name="CampusServices";add_child(campus_services);campus_services.build(self)
	# Bridge uses School.formal_active(); challenge setup requires EMPTY PE demo profile and no external links.
	# Only trusted host controls may end a PE demonstration while de-energized; no arbitrary profile RPC.
	lab_challenges=preload("res://scripts/lab_challenges/bridge.gd").new()
	lab_challenges.name="LabChallenges"
	add_child(lab_challenges);lab_challenges.build(self)
	menu_campus = preload("res://scripts/campus/presentation/menu_flythrough/campus_presentation.gd").new()
	menu_campus.name = "MenuCampusPresentation"
	add_child(menu_campus)
	menu_campus.install(self)
	client_preferences.load_settings(self)
	client_preferences.apply_all()
	menu_campus.show_menu()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

## Call once after campus registry/world composition; graphics_settings.attach accepts this adapter.
func install_campus_performance(registry: Object, routes_by_zone: Dictionary = {}) -> Node:
	if not is_instance_valid(campus_performance):
		campus_performance = preload("res://scripts/campus/performance/runtime.gd").new()
		add_child(campus_performance)
	campus_performance.attach(camera, registry, routes_by_zone)
	return campus_performance

func _build_player() -> void:
	player = CharacterBody3D.new()
	player.set_script(FirstPerson)
	player.name = "FirstPersonPlayer"
	add_child(player)
	player.position = Vector3(13,0,-18)
	camera = player.eyes
	cables_root = Node3D.new()
	add_child(cables_root)

func _solid(pos: Vector3,size: Vector3,color: Color) -> void:
	if pos.y<1.8 and size.y<1.5:cable_obstacles.append(AABB(pos-size*.5,size))
	_box(self,pos,size,color)
	var body := StaticBody3D.new()
	body.position = pos
	if size.x>2 and size.y<.2 and pos.y>.5:
		body.set_meta("role","table")
		body.set_meta("label","Tabletop")
	var shape := BoxShape3D.new()
	shape.size = size
	var coll := CollisionShape3D.new()
	coll.shape = shape
	body.add_child(coll)
	add_child(body)

func _build_station() -> void:
	var existing := get_children()
	super._build_station()
	var station := Node3D.new()
	station.name = "TrainingStation"
	add_child(station)
	for child in get_children():
		if child != station and not existing.has(child):
			child.reparent(station)
	station.scale = Vector3.ONE*.68
	station.position = Vector3(0,.75,-1)

func _build_room() -> void:
	campus=preload("res://scenes/campus/Campus.tscn").instantiate()
	add_child(campus)
	campus.set_viewer(player)
	_solid(Vector3(0,2.35,-3.3),Vector3(4.55,3.2,.2),Color("273136"))
	_solid(Vector3(0,.7,-2.9),Vector3(5.0,.14,1.2),Color("ad9779"))
	for x in [-2.25,2.25]:
		_solid(Vector3(x,.33,-2.9),Vector3(.09,.66,1.05),Color("34474b"))
	for x in range(-9,10):
		_box(self,Vector3(x,.003,3),Vector3(.012,.003,14),Color("626c6d"))
	for z in range(-3,11):
		_box(self,Vector3(0,.003,z),Vector3(20,.003,.012),Color("626c6d"))
	for x in [-6.5,6.5]:
		for z in [1.5,6.0]:
			_solid(Vector3(x,.82,z),Vector3(3.0,.12,1.2),Color("ad9779"))
			for dx in [-1.3,1.3]:
				_solid(Vector3(x+dx,.4,z),Vector3(.09,.8,.9),Color("34474b"))
			# Storage accessories and instrument cases.
			_solid(Vector3(x+.7,.99,z),Vector3(.5,.22,.4),Color("34474b"))
			_add_chair(Vector3(x,0,z+1.25))
	for x in [-6.0,0.0,6.0]:
		_add_chair(Vector3(x,0,-.6))
		if x!=0:
			_solid(Vector3(x,.7,-2.9),Vector3(5,.14,1.2),Color("ad9779"))
			for dx in [-2.25,2.25]:
				_solid(Vector3(x+dx,.33,-2.9),Vector3(.09,.66,1.05),Color("34474b"))
			var equipment := preload("res://scripts/campus/performance/equipment_builder_adapter.gd").new()
			add_child(equipment)
			equipment._reset_switches()
			equipment._build_station()
			equipment.scale=Vector3.ONE*.68
			equipment.position=Vector3(x,.75,-1)
			_solid(Vector3(x,2.35,-3.3),Vector3(4.55,3.2,.2),Color("273136"))
			var storage := preload("res://scripts/cable_drawer.gd").new()
			add_child(storage)
			storage.build(self)
			storage.position.x=x
			var number := stations.size()+1
			_tag_station(equipment,number)
			_tag_station(storage,number)
			stations.append({"equipment":equipment,"drawer":storage})
	drawer=Node3D.new()
	drawer.set_script(preload("res://scripts/cable_drawer.gd"))
	add_child(drawer)
	drawer.build(self)
	for i in range(3):
		var label := _text3(self,"0.000 A",terminal_bodies["AM%d_IN"%i].global_position+Vector3(.1,.12,.02),.027,TEXT_DARK)
		physical_readouts["A%d"%i] = label
		label = _text3(self,"0.00 V",terminal_bodies["V%d_150"%i].global_position+Vector3(0,.12,.02),.027,TEXT_DARK)
		physical_readouts["V%d"%i] = label
	for i in range(2):
		physical_readouts["W%d"%i] = _text3(self,"0.00 W",terminal_bodies["W%d_OUT"%i].global_position+Vector3(.1,.13,.02),.03,TEXT_LIGHT)
	rotor = Node3D.new()
	rotor.position = terminal_bodies.M1.get_parent().to_global(Vector3(-.15,.37,.49))
	add_child(rotor)
	_line(rotor,Vector3(-.1,0,0),Vector3(.1,0,0),.012,Color("e6cf8c"),.8)

	motor_label = _text3(self,"APPROX. MOTOR MODEL",terminal_bodies.M1.get_parent().to_global(Vector3(0,.32,.2)),.021,TEXT_LIGHT)

func capture() -> void:
	if is_instance_valid(front) and front.leaving_game:return
	if is_instance_valid(menu_campus):menu_campus.enter_game()
	if is_instance_valid(front):front.entered()
	ui.menu.hide()
	ui.sheet.hide()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	player.enabled = true

func release_mouse() -> void:
	_set_highlighted_target(null)
	if is_instance_valid(dc_lab):dc_lab.release_physical_io()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	player.enabled = false

func install_dorm_rest(authority: Object) -> void:
	if is_instance_valid(dorm_rest):return
	dorm_rest=preload("res://scripts/campus/dorms/rest/rest_controller.gd").new()
	dorm_rest.name="DormRest";add_child(dorm_rest);dorm_rest.configure(self,authority)
	session.rest_pose_guard=dorm_rest.canonical_pose

func open_carried_calculator(model := "") -> void:
	if model.is_empty():model=hotbar.calculator_type()
	if model.is_empty():return
	var window := Window.new()
	window.title = preload("res://scripts/campus/dorms/authority/persistent_dorm.gd").TOOLS.get(model,"Scientific calculator")
	window.borderless = true
	window.transient = true
	window.exclusive = true
	window.transparent_bg = true
	ui.add_child(window)
	var calculator := preload("res://scripts/scientific_calculator.gd").new()
	calculator.model=model
	calculator.show_close=true
	window.add_child(calculator)
	calculator.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var dismiss := func():
		window.hide()
		window.queue_free()
		if front.in_game:capture()
	window.close_requested.connect(dismiss)
	calculator.close_requested.connect(dismiss)
	window.window_input.connect(func(event: InputEvent):
		if event is InputEventKey and event.pressed and not event.echo and event.keycode==KEY_ESCAPE:
			window.set_input_as_handled()
			dismiss.call())
	release_mouse()
	var minimum := calculator.get_combined_minimum_size()
	var calculator_size := Vector2i(ceili(minimum.x) if model=="calculator_basic" else 420, ceili(minimum.y))
	window.popup_centered(calculator_size)

func _input(event: InputEvent) -> void:
	if is_instance_valid(front) and front.page == "settings" and is_instance_valid(front.menu_page) and front.menu_page.handle_binding(event):
		get_viewport().set_input_as_handled()
		return
	if is_instance_valid(dorm_rest) and player.resting and event is InputEventKey and event.pressed and not event.echo and event.physical_keycode in [KEY_ESCAPE,player.keys.jump,player.keys.interact]:
		dorm_rest.request("",true);get_viewport().set_input_as_handled();return
	if is_instance_valid(computer_room_adapter) and computer_room_adapter.route_event(event):return
	if is_instance_valid(school) and player.enabled and Input.mouse_mode==Input.MOUSE_MODE_CAPTURED and event is InputEventKey and event.pressed and not event.echo and event.physical_keycode==KEY_B:
		var paper_id: int = school.held(multiplayer.get_unique_id())
		if school.papers.get(paper_id,{}).get("notebook",false):
			paper_ui.open_sheet(paper_id)
			get_viewport().set_input_as_handled()
			return
		if school.papers.get(paper_id,{}).get("calculator",false):
			open_carried_calculator()
			get_viewport().set_input_as_handled()
			return
	if is_instance_valid(campus_services) and campus_services.route_event(event):get_viewport().set_input_as_handled();return
	if is_instance_valid(dc_lab) and dc_lab.route_io_event(event):
		get_viewport().set_input_as_handled();return
	if is_instance_valid(dc_lab) and ((event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT and not event.pressed) or (event is InputEventKey and event.physical_keycode==player.keys.interact and not event.pressed)):dc_lab.release_input()
	if measuring_station>=0 and ((event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT and not event.pressed) or (event is InputEventKey and event.physical_keycode==player.keys.interact and not event.pressed)):
		session.request({"op":"dyn_measure","pressed":false,"station":measuring_station});measuring_station=-1
	if is_instance_valid(characters) and characters.is_editing():return
	if event is InputEventKey and event.pressed and not event.echo and (event.keycode == KEY_F11 or (event.keycode == KEY_ENTER and event.alt_pressed)):
		toggle_fullscreen()
		get_viewport().set_input_as_handled()
		return
	if not is_instance_valid(ui):
		return
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode==KEY_TAB and electronics.active and electronics.current_page=="inventory":
		electronics.close()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode==KEY_F and Input.mouse_mode==Input.MOUSE_MODE_CAPTURED:
		if school.papers.get(school.held(multiplayer.get_unique_id()),{}).get("supply_id","")=="flashlight":
			_toggle_supply_flashlight()
			return
		toggle_inspection();return
	if event is InputEventKey and event.pressed and not event.echo and (event.keycode == KEY_ESCAPE or event.physical_keycode == KEY_ESCAPE):
		get_viewport().set_input_as_handled()
		if is_instance_valid(lecture_classes) and lecture_classes.close_picker():return
		if player.inspecting:end_inspection();return
		if is_instance_valid(dorm_interactions) and dorm_interactions.close_storage():
			return
		if is_instance_valid(electronics) and electronics.active:
			if not electronics.cancel_workspace_action():electronics.close()
			return
		if is_instance_valid(dc_lab) and is_instance_valid(dc_lab.ui) and dc_lab.ui.active:
			dc_lab.ui.close();return
		if is_instance_valid(paper_ui) and paper_ui.screen.visible:
			if not paper_ui.cancel_inline_text():paper_ui.close()
			return
		if is_instance_valid(shop_room) and shop_room.active:
			front.pause_menu()
			return
		front.escape()
		return
	if event is InputEventKey and event.pressed and not event.echo and Input.mouse_mode==Input.MOUSE_MODE_CAPTURED:
		if is_instance_valid(player.seated) and event.physical_keycode == player.keys.jump:
			_stand_from_chair()
			return
		for index in 6:
			if event.physical_keycode == player.keys["slot_%d" % (index + 1)]:
				hotbar.select_slot(index)
				return
		if event.physical_keycode in [KEY_TAB,player.keys.inventory]:electronics.open("inventory");return
		if event.physical_keycode == player.keys.kits:electronics.open("kits");return
		if event.physical_keycode == player.keys.drop_lead:
			_drop_held_item()
			return

	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	if event is InputEventMouseMotion:
		if drag_knob != "":
			drag_amount += (event.relative.x-event.relative.y)*0.0015
			if absf(drag_amount) >= 0.008:
				session.request({"op":drag_knob,"delta":drag_amount,"station":drag_station})
				drag_amount = 0
		else:
			if player.inspecting:
				camera.rotation.x=clampf(camera.rotation.x-event.relative.y*.0015,inspect_rotation.x-.5,inspect_rotation.x+.5)
				camera.rotation.y=clampf(camera.rotation.y-event.relative.x*.0015,inspect_rotation.y-.7,inspect_rotation.y+.7)
			else:player.look(event.relative)
		if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):school_world.use_supply(MOUSE_BUTTON_LEFT,true)
		elif Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):school_world.use_supply(MOUSE_BUTTON_RIGHT,true)
	elif event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
			drag_knob = ""
			interaction_presentation.cancel_actor(multiplayer.get_unique_id())
		elif event.pressed:
			if event.button_index==MOUSE_BUTTON_RIGHT and is_instance_valid(current_target) and current_target.get_meta("role","")=="trash":
				school_world.interact(current_target,true)
				return
			if event.button_index in [MOUSE_BUTTON_LEFT,MOUSE_BUTTON_RIGHT] and school_world.use_supply(event.button_index):return
			if event.button_index == MOUSE_BUTTON_LEFT:
				if _aims_at_control("variable") or _aims_at_control("dyn_load"):
					drag_knob = "voltage" if _aims_at_control("variable") else "dyn_load"
					drag_station=_active_station();drag_amount=0
				else:
					activate(false)
			elif event.button_index == MOUSE_BUTTON_RIGHT:
				if dc_lab.attach_held_lead_to_board(current_target):pass
				elif school_world.interact_held():pass
				elif kit_world.interact(current_target,true):pass
				elif dc_lab.interact(current_target,true):pass
				elif not school_world.interact(current_target,true):unplug()
			elif event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:
				var amount := 1.0 if event.button_index==MOUSE_BUTTON_WHEEL_UP else -1.0
				if _aims_at_control("variable") or _aims_at_control("dyn_load"):
					_request({"op":"voltage" if _aims_at_control("variable") else "dyn_load","delta":amount*.025})
				elif _aims_at_control("supply_meter"):
					_request({"op":"supply_meter","delta":amount})
				elif dc_lab.scroll_instrument(current_target,amount<0,event.shift_pressed):pass
				else:
					camera.fov = clampf(camera.fov-amount*4,28,78)
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == player.keys.interact:
			activate()
		else:
			match event.keycode:
				KEY_1,KEY_2,KEY_3,KEY_4:
					chosen_color = event.keycode-KEY_1
					if is_instance_valid(current_target) and current_target.has_meta("dc_station") and current_target.get_meta("role") in ["drawer","rack"]:
						dc_lab.pick_lead(int(current_target.get_meta("dc_station")),chosen_color)
					elif player.global_position.distance_to(Vector3(_station_x(_active_station()),.4,-1.7))<=3.25:
						_request({"op":"pickup","color":chosen_color})
					else:
						ui.log_message("Open the drawer under the bench to pick up a "+JACKET_NAMES[chosen_color]+" lead.")
				KEY_Q:
					if not dc_lab.interact(current_target,true):unplug()
				KEY_BACKSPACE:
					if not dc_lab.return_lead():_request({"op":"discard"})
				KEY_Z:
					_request({"op":"undo"})
				KEY_P:
					_request({"op":"power"})
				KEY_C:
					_request({"op":"check"})
				KEY_F8:
					telemetry = not telemetry
					for label in physical_readouts.values():
						label.visible=telemetry
					motor_label.visible=telemetry
					ui.refresh(_target_state())
				KEY_R:
					if dc_lab.held_board()>=0:dc_lab.request(dc_lab.held_board(),{"op":"rotate_board"})
					else:_request({"op":"reset"})
				KEY_BRACKETLEFT,KEY_BRACKETRIGHT:
					_request({"op":"frequency","delta":1 if event.keycode==KEY_BRACKETRIGHT else -1})

func _drop_held_item() -> void:
	var peer := multiplayer.get_unique_id()
	var paper_id: int=school.held(peer)
	var board: int=dc_lab.held_board()
	var holding_kit: bool=kit_world.held()
	var holding_food: bool=not hotbar.selected_food().is_empty()
	var holding_lead: bool=school._holding_cable(peer)
	if paper_id==0 and board<0 and not holding_kit and not holding_food and not holding_lead:return
	var forward: Vector3=-player.global_basis.z
	var ground: Variant=school.ground_drop_position(player.global_position+forward*1.0,peer)
	if ground==null:
		ui.log_message("Face a clear spot on the floor to drop the item.")
	elif paper_id!=0:
		school.request({"op":"drop","id":paper_id,"position":ground})
	elif board>=0:
		dc_lab.request(board,{"op":"place_board","position":ground,"ground":true})
	elif holding_kit:
		kit_world.request({"op":"drop","position":ground})
	elif holding_food:
		campus_services.facility_panel.request_direct({"op":"place","order_id":hotbar.selected_food().id,"position":ground,"ground":true})
	else:
		school.request({"op":"drop_floor_lead","position":ground})

func activate(from_interact_key := true) -> void:
	if from_interact_key and is_instance_valid(current_target) and current_target.get_meta("role","")=="table":return
	if is_instance_valid(dorm_rest) and player.resting:return
	if not from_interact_key and is_instance_valid(current_target) and current_target.get_meta("role","") in ["dorm_room_prop","dorm_personal_station","dorm_decorate","dorm_door","shop_station"]:
		return
	if is_instance_valid(campus_services):
		for resource in campus_services.study_resources.values():
			if is_instance_valid(resource) and resource.interact(current_target):return
	if is_instance_valid(computer_room_adapter) and computer_room_adapter.interact(current_target):return
	if is_instance_valid(dorm_interactions) and dorm_interactions.interact(current_target):return
	if is_instance_valid(discarded_items) and discarded_items.interact(current_target):return
	if is_instance_valid(lecture_classes) and lecture_classes.interact(current_target):return
	if is_instance_valid(circuit_studio) and circuit_studio.interact(current_target):return
	if is_instance_valid(washroom_finish) and washroom_finish.interact(current_target):return
	if is_instance_valid(kit_world) and kit_world.interact(current_target,false):return
	if is_instance_valid(campus) and campus.interact(current_target,player):return
	if is_instance_valid(shop_room) and shop_room.interact(current_target):return
	if is_instance_valid(dc_lab) and dc_lab.interact(current_target,from_interact_key and is_instance_valid(current_target) and current_target.get_meta("role","")=="dc_board"):return
	if is_instance_valid(school_world) and school_world.interact(current_target,false):return
	if not is_instance_valid(current_target):
		return
	var role := str(current_target.get_meta("role",""))
	match role:
		"chair":
			_request_chair(chairs.find(current_target.get_parent()))
			sfx.play("pickup")
		"display":
			ui.log_message("Use the centre station for circuit experiments.")
		"drawer":
			_request({"op":"drawer"})
		"rack":
			_request({"op":"pickup","color":int(current_target.get_meta("color",chosen_color))})
		"socket":
			_request({"op":"plug","port":str(current_target.get_meta("id"))})
		"loose_end":
			_request({"op":"grab","id":int(current_target.get_meta("id"))})
		"floor_lead":
			if not hotbar.slots.has({}):ui.log_message("Free a hotbar slot first.")
			else:school.request({"op":"pickup_floor_lead","id":int(current_target.get_meta("lead_id"))})
		"switch":
			var kind: String = current_target.get_meta("kind")
			var i: int = current_target.get_meta("index")
			_request({"op":"switch","kind":kind,"index":i,"expected":_target_state().get("switches",toggles)[kind][i]})
		"control":
			if _aims_at_control("power"):
				_request({"op":"power"})
			elif _aims_at_control("variable"):
				_request({"op":"voltage","delta":.025})
			elif _aims_at_control("dyn_load"):
				_request({"op":"dyn_load"})
			elif _aims_at_control("daq"):
				paper_ui.daq_page()
			elif _aims_at_control("supply_meter") or _aims_at_control("igbt_damping"):
				_request({"op":str(current_target.get_meta("id"))})
			elif _aims_at_control("dyn_measure"):
				measuring_station=_active_station();_request({"op":"dyn_measure","pressed":true})
			elif str(current_target.get_meta("id","")).begins_with("reset_"):
				_request({"op":"breaker"})
			else:
				ui.log_message("This fitting is a passive connector; attach a lead to its socket.")
		"worksheet":
			release_mouse()
			ui.sheet.show()

func unplug() -> void:
	if is_instance_valid(current_target) and str(current_target.get_meta("role",""))=="socket":
		_request({"op":"unplug","port":str(current_target.get_meta("id"))})

func _aims_at_control(id: String) -> bool:
	return is_instance_valid(current_target) and str(current_target.get_meta("role",""))=="control" and str(current_target.get_meta("id",""))==id

func _get_target() -> StaticBody3D:
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return null
	var query := PhysicsRayQueryParameters3D.create(camera.global_position,camera.global_position-camera.global_basis.z*3.0,5)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	return hit.get("collider") as StaticBody3D

func _set_highlighted_target(target: StaticBody3D) -> void:
	if is_instance_valid(target) and str(target.get_meta("role", "")) not in ["socket", "switch"]:
		target = null
	if target == highlighted:
		return
	if is_instance_valid(highlighted):
		highlighted.scale = highlighted_scale
	highlighted = target
	if is_instance_valid(highlighted):
		highlighted_scale = highlighted.scale
		highlighted.scale *= 1.08

func _physics_process(delta: float) -> void:
	if not is_instance_valid(ui):
		return
	if player.enabled:_constrain_carried_lead()
	ui.hud.visible = front.in_game and client_preferences.values.hud and telemetry and snapshot.get("mode","") != "Practical Exam" and not ui.menu.visible and not ui.sheet.visible
	ui.objective.visible = ui.hud.visible
	ui.log_label.visible = player.enabled and client_preferences.values.notifications
	ui.crosshair.visible=player.enabled
	ui.fps_label.visible=front.in_game and not ui.menu.visible and not ui.sheet.visible
	ui.prompt.visible=player.enabled and client_preferences.values.prompts
	current_target = _get_target()
	var lead_hole: String=dc_lab.preview_lead_hole(current_target) if is_instance_valid(dc_lab) else ""
	if displayed_station!=_active_station() and not station_snapshots.is_empty():
		displayed_station=_active_station()
		ui.refresh(_target_state())
	var assistance: bool = ui.assists.button_pressed and snapshot.get("mode","")!="Practical Exam"
	_set_highlighted_target(current_target if assistance else null)
	held_hint.text = ""
	if is_instance_valid(hotbar) and not hotbar.selected_food().is_empty():
		var item: Dictionary=hotbar.selected_food()
		var drink: bool=item.type in ["coffee","tea","water"]
		held_hint.text = "Right click: %s  •  Left click tabletop: place" % ("sip" if drink else "take a bite")
	if is_instance_valid(player.seated):
		var stand_key := OS.get_keycode_string(player.keys.jump)
		held_hint.text = "%s: stand" % stand_key if player.seated.fixed_seat else "WASD: roll  •  Mouse: look ±90°  •  Ctrl + mouse: swivel  •  %s: stand" % stand_key
	for cable in leads:
		if cable.owner==multiplayer.get_unique_id():
			held_hint.text="Click terminals to attach lead  •  %s: drop lead  •  Backspace: return cable" % OS.get_keycode_string(player.keys.drop_lead)
	if is_instance_valid(dc_lab) and dc_lab.lead_color >= 0:
		held_hint.text = "Click terminals to attach lead  •  %s: drop lead  •  Backspace: return cable" % OS.get_keycode_string(player.keys.drop_lead)
	if is_instance_valid(school) and school.held(multiplayer.get_unique_id())!=0:
		var held_paper: Dictionary = school.papers.get(school.held(multiplayer.get_unique_id()),{})
		if held_paper.get("notebook",false):
			held_hint.text="Right click: open notebook • Left click tabletop: place"
		elif held_paper.get("calculator",false):
			held_hint.text="Right click: use calculator • Left click tabletop: place"
		elif held_paper.get("supply_id","")=="lab_goggles":
			held_hint.text="Right click: equip goggles • Left click tabletop: place"
		elif held_paper.get("supply_id","")=="pencil_case":
			held_hint.text="Left click tabletop: place"
		elif held_paper.get("supply_id","")=="flashlight":
			held_hint.text="F: toggle flashlight"
		elif held_paper.get("supply_id","")=="marker":
			held_hint.text="Left click: draw  ·  Right click: erase"
		elif held_paper.get("supply_id","")=="whiteboard":
			held_hint.text="Right click a wall: mount whiteboard"
		elif str(held_paper.get("supply_id","")).begins_with("bag:"):
			held_hint.text="Right click: equip backpack • Left click ground: place"
		else:
			held_hint.text="Right click: read sheet • Left click tabletop: place"
	if player.resting:
		held_hint.text="%s: get up" % OS.get_keycode_string(player.keys.jump)
	elif school.held(multiplayer.get_unique_id())!=0 or kit_world.held() or dc_lab.held_board()>=0 or not hotbar.selected_food().is_empty():
		var drop_hint := "%s: drop on floor" % OS.get_keycode_string(player.keys.drop_lead)
		held_hint.text=drop_hint if held_hint.text.is_empty() else held_hint.text+"  •  "+drop_hint
	held_item_name.text=hotbar.held_title()
	held_item_name.visible=front.in_game and player.enabled and not player.resting and not held_item_name.text.is_empty()
	held_hint.visible=player.enabled and client_preferences.values.prompts
	ui.prompt.text = ""
	if current_target:
		var role: String = current_target.get_meta("role","")
		var key_name := OS.get_keycode_string(player.keys.interact)
		var hint := "%s - %s" % [key_name,str(current_target.get_meta("label",""))]
		if role=="socket":
			var port: String = current_target.get_meta("id")
			var station_id: int = current_target.get_meta("station",0)
			if station_id>0:
				port=str(station_id)+":"+port
			var held: Dictionary = {}
			var occupied := false
			for cable in leads:
				if cable.owner == multiplayer.get_unique_id():
					held = cable
				occupied = occupied or cable.a == port or cable.b == port
			if _target_state().get("powered",false) and _target_state().get("mode","")!="Free Laboratory":
				hint = "Turn power off to change cables"
			elif not held.is_empty() and (held.a == port or held.b == port):
				hint = "Right click: unplug this end | G: put cable down"
			elif not held.is_empty() or dc_lab.lead_color>=0:
				hint = "Click: " + ("stack plug here" if occupied else "attach cable here")
			else:
				hint = "Right click: unplug cable" if occupied else "Open the cable drawer first"
		elif role=="kit":
			hint="Click: return breadboard and close kit" if kit_world.can_return_held_board(current_target) else "Left click: pick up kit · Right click: open kit"
		elif role=="lecture_desk":
			var room := str(current_target.get_meta("room",""))
			hint="Class in progress" if lecture_classes.public_classes.has(room) else "Click: set up class"
		elif role=="lecture_attendance":
			hint="Click: sign attendance"
		elif role=="discarded_item":
			hint="Click: "+str(current_target.get_meta("label","Pick up item"))
		elif role=="table" and kit_world.held():
			hint="Left click: place kit"
		elif role=="shop_station":
			hint="%s - %s" % [key_name,str(current_target.get_meta("label","Shop counter"))]
		elif role=="dc_board":
			hint=str(current_target.get_meta("label","Circuit board"))
			if dc_lab._lead_board_slot(current_target)>=0:
				var pcb: bool = dc_lab.states[int(current_target.get_meta("dc_station"))].get("board",{}).get("standalone",false)
				hint="Click: attach lead to "+lead_hole if not lead_hole.is_empty() else ("Aim at a PCB terminal" if pcb else "Aim at a breadboard hole")
			elif not dc_lab.aimed_breadboard_lead(current_target,int(current_target.get_meta("dc_station"))).is_empty():
				hint="Right click: disconnect lead"
		elif role in ["dorm_room_prop","dorm_decorate"]:
			var prop := str(current_target.get_meta("kind",""))
			var name := str({"storage":"Drawer","study_chair":"Study chair","computer":"Study computer","bed":"Bed","wardrobe":"Wardrobe","bedside_lamp":"Bedside lamp","desk_lamp":"Desk lamp"}.get(prop,current_target.get_meta("label","")))
			hint="%s - %s" % [key_name,name]
		elif role=="clothing_shop":
			hint="%s - %s" % [key_name,str(current_target.get_meta("label","Clothing rack"))]
		elif role=="elevator_control":
			hint="%s - %s" % [key_name, str(current_target.get_meta("label","Elevator"))]
		elif role=="dc_panel":
			hint="%s - DC instruments" % key_name
		elif role in ["dc_input","dc_io","dc_code"]:
			hint=str(current_target.get_meta("label",""))
		elif role=="dc_instrument_control":
			hint=("Scroll: " if current_target.get_meta("dc_knob",false) else "Click: ")+str(current_target.get_meta("label","Instrument control"))
		elif role=="dc_port":
			hint=str(current_target.get_meta("label",current_target.get_meta("dc_port")))+" · Click: connect lead · Right click: disconnect"
		elif role=="computer":
			hint="%s - Classroom computer" % key_name
		elif role=="teacher":
			hint="Right click: talk to instructor"
		elif role=="paper":
			hint=school_world.placed_item_hint(int(current_target.get_meta("paper_id",0)))
		elif role=="trash":
			hint="Right click: recycle held sheet" if school_world.can_recycle_held_sheet() else "Paper recycling"
		elif role=="table" and school.held(multiplayer.get_unique_id())!=0:
			hint="Left click on tabletop: place held item"
		elif role=="table":
			hint="Left click on tabletop: place board" if dc_lab.held_board()>=0 else ""
		elif role=="chair":
			hint="%s - Sit" % key_name
		elif role=="display":
			hint="Centre station: circuit experiments"
		elif role=="drawer":
			hint = "Click: close drawer" if _target_state().get("drawer_open",false) else "Click: open cable drawer"
		elif role=="rack":
			hint = "Click: take " + str(current_target.get_meta("label","cable")).to_lower()
		elif _aims_at_control("variable"):
			hint = "Drag / wheel: voltage • [ ] frequency"
		if not str(current_target.get_meta("label","")).is_empty():
			ui.prompt.text = hint
		if assistance and telemetry and role=="socket":
			var id: String = current_target.get_meta("id")
			var connected: Array[String] = []
			for c in snapshot.get("cables",[]):
				if c.a == id or c.b == id:
					connected.append(str(c.id)+": "+str(c.b if c.a==id else c.a))
			ui.prompt.text += "\n"+id+" → "+", ".join(connected)
	if is_instance_valid(campus_services):
		var facility_hint: String = campus_services.aimed_prompt()
		if not facility_hint.is_empty() or (is_instance_valid(current_target) and current_target.get_meta("role", "") in ["facility_seat", "restaurant_cashier", "gym_equipment"]):
			ui.prompt.text = facility_hint
	_update_chair_network(delta)
	network_clock += delta
	var relay_active: bool = session.uses_relay()
	session.relay_pose_interval = 1.0 / float(client_preferences.values.relay_pose_rate)
	session.relay_skip_idle = client_preferences.values.relay_skip_idle
	if network_clock >= (session.relay_pose_interval if relay_active else .05):
		network_clock = 0
		session.send_pose({"position":player.position,"yaw":player.rotation.y,"pitch":camera.rotation.x,"crouch":player.crouched,"seated":player.seated!=null})
	for id in avatars:
		if avatar_targets.has(id):
			var target: Dictionary = avatar_targets[id]
			avatars[id].position = avatars[id].position.lerp(target.position,1-exp(-12*delta))
			avatars[id].rotation.y = lerp_angle(avatars[id].rotation.y,target.yaw,1-exp(-12*delta))
			var model=avatars[id].get_node_or_null("CharacterModel")
			if model!=null:
				var walking: bool = avatar_last_movement.has(id) and Time.get_ticks_msec() - int(avatar_last_movement[id]) < 350
				preload("res://scripts/avatar_model.gd").animate(model,walking,target.get("seated",false),target.get("resting",false))
			avatars[id].scale.y=lerpf(avatars[id].scale.y,.65 if target.crouch and not target.get("seated",false) else 1.0,1-exp(-12*delta))
	for key in meter_targets:
		needle_bodies[key].rotation.z = lerpf(needle_bodies[key].rotation.z,meter_targets[key],1-exp(-8*delta))
	rotor_speed = lerpf(rotor_speed,float(readings.get("motor_rpm",0)),1-exp(-2*delta))
	rotor.rotation.z += rotor_speed*TAU/60*delta
	if player.seated==null and player.enabled and player.velocity.length()>.5 and player.is_on_floor():
		steps_clock += delta
		if steps_clock > .5:
			steps_clock = 0
			sfx.play("step")

func _receive_state(data: Dictionary) -> void:
	interaction_presentation.set_local_peer(multiplayer.get_unique_id())
	var previous_stations: Array=station_snapshots
	var previous: Dictionary = snapshot
	snapshot = data
	drawer.sync(bool(data.get("drawer_open",false)))
	station_snapshots=[data]+data.get("stations",[])
	leads.assign(data.cables)
	toggles = data.switches
	powered = data.powered
	variable_level = data.level
	readings = data.readings
	for kind in ["R","L","C"]:
		for i in range(9):
			var k := "%s_%d"%[kind,i]
			var on: bool = toggles[kind][i]
			create_tween().tween_property(switch_meshes[k].handle,"rotation:z",-.38 if on else .38,.12)
			switch_meshes[k].indicator.material_override = _mat(Color("58ef88") if on else Color("56616e"),.2,on)
	for i in range(3):
		_set_meter("AMP%d"%i,readings.ammeters[i],readings.ammeter_ranges[i])
		_set_meter("VOLT%d"%i,readings.voltmeters[i],readings.voltmeter_ranges[i])
		physical_readouts["A%d"%i].text = "%.4f A"%readings.ammeters[i]
		physical_readouts["V%d"%i].text = "%.2f V"%readings.voltmeters[i]
	for i in range(2):
		_set_meter("WATT%d"%i,readings.wattmeters[i],250)
		physical_readouts["W%d"%i].text = "%+.3f W"%readings.wattmeters[i]
	_sync_supply_controls(self,data)
	motor_label.text = "%.0f RPM • %.2f Nm LOAD\nAPPROXIMATE EQUIVALENT" % [readings.motor_rpm,readings.get("dynamo_torque",0.)]
	if is_instance_valid(motor_audio):
		var motor_power: float = readings.get("motor",{}).get("input_power",0)
		motor_audio.pitch_scale = data.frequency/60.0
		motor_audio.volume_db = -32+clampf(motor_power/40.0,0,8)
		if powered and motor_power>1:
			if not motor_audio.playing:
				motor_audio.play()
		else:
			motor_audio.stop()
	for label in physical_readouts.values():
		label.visible = telemetry
	motor_label.visible = telemetry
	ui.refresh(_target_state())
	for i in range(1,station_snapshots.size()):
		if i<previous_stations.size() and station_snapshots[i].revision!=previous_stations[i].revision and player.position.distance_to(Vector3(_station_x(i),0,-2))<5:
			sfx.play(str(station_snapshots[i].get("last_action","ui")))
	_render_stations()
	_render_wires()
	_render_carried()
	interaction_presentation.reconcile(data)
	if readings.fault != "":
		ui.log_message(str(readings.fault))
		sfx.play("trip")
	elif not previous.is_empty() and previous.revision != data.revision:
		sfx.play(str(data.get("last_action","ui")))
	if data.checked and not previous.get("checked",false):
		ui.log_message("Preflight passed for modeled faults. Use your instructor's real safety checklist.")
	if data.result != "" and data.result != last_result:
		last_result = data.result
		history.append({"seed":data.seed,"task":data.task,"mode":data.mode,"result":data.result,"time":Time.get_datetime_string_from_system()})
		var file := FileAccess.open("user://history.json",FileAccess.WRITE)
		if file:
			file.store_string(JSON.stringify(history))
		ui.log_message(data.result)
		ui.update_records(history)
	if data.result=="":
		last_result=""

func _set_meter(key: String,value: float,maximum: float) -> void:
	meter_targets[key] = deg_to_rad(60-clampf(value/maximum,-.1 if key.begins_with("WATT") else 0.0,1)*120)

func _render_wires() -> void:
	if is_instance_valid(current_target) and cables_root.is_ancestor_of(current_target):
		current_target = null
	for child in cables_root.get_children():
		child.free()
	for c in leads:
		if c.a != "" and c.b != "":
			_draw_cable(cables_root,c,_stack_position(c.a,c.id),_stack_position(c.b,c.id,1))
	for c in leads:
		for end in 2:
			var port: String=c.a if end==0 else c.b
			if port != "":
				_stack_socket(str(port),int(c.id),end)

func _port_position(id: String) -> Vector3:
	return terminal_bodies[id].global_position+Vector3(0,0,.08)

func _draw_cable(root: Node3D,c: Dictionary,a: Vector3,b: Vector3) -> void:
	root.add_child(CableMesh.build(a,b,JACKET_COLORS[c.color],cable_obstacles))
	for end_index in [0,1]:
		var pos: Vector3=a if end_index==0 else b
		var connector := _cylinder(root,pos,.023,.095,JACKET_COLORS[c.color],.3)
		connector.rotation.x = PI*.5
		var plug := _cylinder(root,pos-Vector3(0,0,.045),.009,.045,Color("b5b8ae"),.8)
		plug.rotation.x = PI*.5
		interaction_presentation.bind_connector(connector,int(c.id)/10000,int(c.id)%10000,end_index)
		interaction_presentation.bind_connector(plug,int(c.id)/10000,int(c.id)%10000,end_index)

func _process(_delta: float) -> void:
	if is_instance_valid(interaction_presentation) and is_instance_valid(player):
		var peer := multiplayer.get_unique_id()
		var holding: bool = (is_instance_valid(school) and school.held(peer)!=0
			or is_instance_valid(hotbar) and not hotbar.selected_food().is_empty()
			or is_instance_valid(kit_world) and kit_world.held()
			or is_instance_valid(dc_lab) and (dc_lab.held_board(peer)>=0 or dc_lab.lead_color>=0))
		interaction_presentation.set_local_item_held(player.enabled and holding)
	if is_instance_valid(carried_root) and is_instance_valid(camera):
		var trace: Node=get_meta("campus_hitch_trace",null) if has_meta("campus_hitch_trace") else null
		var span: int=trace.begin_span("carried_lead_visuals") if is_instance_valid(trace) else -1
		_render_carried()
		if is_instance_valid(trace):trace.end_span(span)

func held_item_position(peer: int, fallback: Vector3) -> Vector3:
	if is_instance_valid(interaction_presentation):
		var actor: Node=interaction_presentation.actors.get(peer)
		if is_instance_valid(actor) and is_instance_valid(actor.hand):
			return actor.hand.global_position
	return fallback

func held_cable_position() -> Vector3:
	return held_item_position(multiplayer.get_unique_id(),camera.to_global(Vector3(.12,-.32,-.42))) + held_cable_grip_offset()

func held_cable_grip_offset() -> Vector3:
	return camera.global_basis * Vector3(-.055, -.075, -.085)

func held_cable_tail(grip: Vector3) -> Vector3:
	return grip + camera.global_basis * Vector3(-.2, -.6, 0)

func held_lead_connector(parent: Node3D, color: Color, point: Vector3) -> MeshInstance3D:
	var connector := _cylinder(parent, point, .023, .095, color, .3)
	connector.rotation.x = PI * .5
	return connector

func _constrain_carried_lead() -> void:
	var peer := multiplayer.get_unique_id()
	for cable in leads:
		var a_connected: bool=cable.a!=""
		var b_connected: bool=cable.b!=""
		if cable.owner!=peer or a_connected==b_connected:continue
		var anchor := _stack_position(cable.a if a_connected else cable.b,cable.id,0 if a_connected else 1)
		var offset := held_cable_position()-anchor
		var excess := offset.length()-5.0
		if excess<=0.0:continue
		var correction := -offset.normalized()*excess
		if is_instance_valid(player.seated):
			player.seated.move_and_collide(correction)
			player.global_position=player.seated.global_position
		else:
			player.move_and_collide(correction)

func _render_carried() -> void:
	if not is_instance_valid(carried_root):
		return
	var active := {}
	for c in leads:
		if c.a!="" and c.b!="":
			continue
		var anchor_id: String = c.a if c.a!="" else c.b
		var end: Vector3
		if c.owner==multiplayer.get_unique_id():
			end=held_cable_position()
		elif c.owner!=0 and avatars.has(c.owner):
			end=avatars[c.owner].to_global(Vector3(.2,1.2,-.3))
		elif anchor_id!="":
			end=_stack_position(anchor_id,c.id,0 if c.a!="" else 1)+Vector3(0,-.55,.12)
		else:
			continue
		var anchor := _stack_position(anchor_id,c.id,0 if c.a!="" else 1) if anchor_id!="" else held_cable_tail(end)
		active[c.id]=true
		if not carry_visuals.has(c.id):
			var group := Node3D.new()
			carried_root.add_child(group)
			var cable := MeshInstance3D.new()
			cable.material_override=CableMesh.jacket_material(JACKET_COLORS[c.color])
			group.add_child(cable)
			var ends: Array[MeshInstance3D] = []
			for i in range(2):
				var plug := held_lead_connector(group,JACKET_COLORS[c.color],Vector3.ZERO)
				ends.append(plug)
			var body := StaticBody3D.new()
			body.set_meta("role","loose_end")
			body.set_meta("id",c.id)
			body.set_meta("label","Loose connector")
			var hit := CollisionShape3D.new()
			var sphere := SphereShape3D.new()
			sphere.radius=.065
			hit.shape=sphere
			body.add_child(hit)
			group.add_child(body)
			carry_visuals[c.id]={"group":group,"mesh":cable,"ends":ends,"body":body,"a":Vector3.INF,"b":Vector3.INF}
		var visual: Dictionary = carry_visuals[c.id]
		var grip_offset := held_cable_grip_offset() if c.owner == multiplayer.get_unique_id() else Vector3.ZERO
		var visual_end: Vector3=interaction_presentation.carried_position(int(c.owner),end-grip_offset,int(c.id)/10000,int(c.id)%10000)+grip_offset if c.owner!=0 else end
		var coiled: bool = c.owner==multiplayer.get_unique_id() and anchor_id.is_empty()
		if coiled:
			if not visual.get("coiled",false):
				visual.mesh.mesh=CableMesh.held_geometry(Vector3.ZERO,Vector3.ZERO,Basis.IDENTITY,false)
			visual.mesh.transform=Transform3D(camera.global_basis,visual_end)
		elif visual.get("coiled",false) or visual.a!=anchor or visual.b!=visual_end:
			visual.mesh.transform=Transform3D.IDENTITY
			if c.owner==multiplayer.get_unique_id():
				visual.mesh.mesh=CableMesh.held_geometry(anchor,visual_end,camera.global_basis,true)
			else:
				visual.mesh.mesh=CableMesh.geometry(anchor,visual_end,cable_obstacles)
		visual.coiled=coiled
		visual.a=anchor
		visual.b=visual_end
		visual.ends[0].visible=c.owner!=multiplayer.get_unique_id() or not anchor_id.is_empty()
		visual.ends[0].position=anchor
		visual.ends[1].position=visual_end
		visual.ends[1].global_basis=camera.global_basis*Basis(Vector3.RIGHT,PI*.5) if c.owner==multiplayer.get_unique_id() else Basis(Vector3.RIGHT,PI*.5)
		for end_index in [0,1]:
			var logical_end: int=(0 if c.a!="" else 1) if end_index==0 else (0 if c.a=="" else 1)
			interaction_presentation.bind_connector(visual.ends[end_index],int(c.id)/10000,int(c.id)%10000,logical_end)
		visual.body.position=end
		visual.body.collision_layer=4 if c.owner==0 else 0
		visual.body.collision_mask=0
	for id in carry_visuals.keys():
		if not active.has(id):
			var group: Node3D=carry_visuals[id].group
			if is_instance_valid(current_target) and group.is_ancestor_of(current_target):
				current_target=null
			group.queue_free()
			carry_visuals.erase(id)

func _roster_changed() -> void:
	interaction_presentation.set_local_peer(multiplayer.get_unique_id())
	ui.update_roster()
	if not session.online:
		ui.connection_label.text="Local laboratory"
	elif multiplayer.is_server():
		ui.connection_label.text="Hosting UDP %d"%session.port
	elif session.roster.has(multiplayer.get_unique_id()):
		ui.connection_label.text="Connected • UDP %d"%session.port
	for id in avatars.keys():
		if not session.roster.has(id) or id==multiplayer.get_unique_id():
			interaction_presentation.remove_actor(int(id))
			avatars[id].queue_free()
			avatars.erase(id)
			avatar_targets.erase(id)
			avatar_last_movement.erase(id)
		else:
			var nameplate: Label3D = avatars[id].get_node_or_null("PlayerName")
			if is_instance_valid(nameplate):
				nameplate.text = str(session.roster[id].get("name", "Student"))

func _receive_pose(id: int,data: Dictionary) -> void:
	interaction_presentation.set_local_peer(multiplayer.get_unique_id())
	if id == multiplayer.get_unique_id():
		return
	if not avatars.has(id):
		var avatar := Node3D.new()
		add_child(avatar)
		avatar.position = data.position
		_set_avatar_model(id,avatar)
		var nameplate := Label3D.new()
		nameplate.name = "PlayerName"
		nameplate.position = Vector3(0, 2.1, 0)
		nameplate.text = str(session.roster.get(id, {}).get("name", "Student"))
		nameplate.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		nameplate.font_size = 40
		nameplate.pixel_size = 0.004
		nameplate.outline_size = 8
		avatar.add_child(nameplate)
		avatars[id] = avatar
	if avatar_targets.has(id):
		var previous: Vector3 = avatar_targets[id].position
		var displacement: Vector3 = data.position - previous
		displacement.y = 0.0
		if displacement.length() > 0.01:
			avatar_last_movement[id] = Time.get_ticks_msec()
	avatar_targets[id] = data
	interaction_presentation.reconcile(snapshot)

func _sound(hz: float,duration: float,volume := 0.0) -> void:
	if not is_instance_valid(tone) or DisplayServer.get_name()=="headless":
		return
	var audio := AudioStreamWAV.new()
	audio.format = AudioStreamWAV.FORMAT_16_BITS
	audio.mix_rate = 22050
	var bytes := PackedByteArray()
	bytes.resize(int(22050*duration)*2)
	for i in range(bytes.size()/2):
		var envelope := exp(-float(i)/(22050*duration*.2))
		var value := int(sin(TAU*hz*i/22050)*envelope*12000)
		bytes.encode_s16(i*2,value)
	audio.data = bytes
	tone.stream = audio
	tone.volume_db = -25+volume
	tone.play()

func _update_ui() -> void:
	pass

func _message(text: String) -> void:
	if is_instance_valid(ui):
		ui.log_message(text)

func toggle_fullscreen() -> void:
	var window := get_window()
	window.mode = Window.MODE_WINDOWED if window.mode in [Window.MODE_FULLSCREEN, Window.MODE_EXCLUSIVE_FULLSCREEN] else Window.MODE_FULLSCREEN

func _stack_position(port: String, cable_id: int,end_index := 0) -> Vector3:
	var layer := 0
	for cable in leads:
		for end in 2:
			if (cable.a if end==0 else cable.b)==port:
				if int(cable.id)==cable_id and end==end_index:return _port_position(port)+Vector3(0,0,layer*.095)
				layer+=1
	return _port_position(port)+Vector3(0,0,layer*.095)

func _stack_socket(port: String, cable_id: int,end_index := 0) -> void:
	var body := StaticBody3D.new()
	# Selectable by interaction rays, never a platform for player movement.
	body.collision_layer = 4
	body.collision_mask = 0
	body.position = _stack_position(port,cable_id,end_index)+Vector3(0,0,.048)
	body.set_meta("role","socket")
	var parts := port.split(":")
	body.set_meta("id",parts[-1])
	body.set_meta("station",int(parts[0]) if parts.size()>1 else 0)
	body.set_meta("label",port+" stacked banana plug")
	var collision := CollisionShape3D.new()
	var shape := SphereShape3D.new()
	shape.radius = .032
	collision.shape = shape
	body.add_child(collision)
	cables_root.add_child(body)
	var socket := _cylinder(body,Vector3.ZERO,.012,.003,Color("101519"))
	socket.rotation.x = PI*.5

func _add_chair(pos: Vector3, facing := 0.0) -> void:
	var chair := preload("res://scripts/rolling_chair.gd").new()
	add_child(chair)
	chair.position=pos
	chair.build(self)
	chair.swivel.rotation.y=facing
	chairs.append(chair)

func _tag_station(node: Node, number: int) -> void:
	if node is StaticBody3D:
		node.set_meta("station",number)
	for child in node.get_children():
		_tag_station(child,number)

func _station_x(number: int) -> float:
	return 0.0 if number==0 else (-6.0 if number==1 else 6.0)

func _active_station() -> int:
	if is_instance_valid(current_target) and (current_target.has_meta("station") or str(current_target.get_meta("role","")) in ["socket","switch","control","rack","drawer"]):
		return int(current_target.get_meta("station",0))
	return 1 if player.position.x < -3 else (2 if player.position.x > 3 else 0)

func _target_state() -> Dictionary:
	var index := _active_station()
	return station_snapshots[index] if index<station_snapshots.size() else snapshot

func _request(action: Dictionary) -> void:
	if is_instance_valid(dc_lab) and dc_lab.held_board()>=0 and action.get("op","") in ["pickup","grab","unplug"]:ui.log_message("Place or stow your circuit board first.");return
	if is_instance_valid(kit_world) and kit_world.held() and action.get("op","") in ["pickup","grab","unplug"]:ui.log_message("Place or stow your kit first.");return
	if is_instance_valid(school) and school.held(multiplayer.get_unique_id())!=0 and str(action.get("op","")) in ["pickup","grab","unplug"]:
		ui.log_message("Place your sheet on a table first.")
		return
	var number := _active_station()
	if str(action.op) in ["return","discard"]:
		for i in range(station_snapshots.size()):
			for cable in station_snapshots[i].cables:
				if cable.owner==multiplayer.get_unique_id():
					number=i
	if action.has("id") and int(action.id)>=10000:
		number=int(action.id)/10000
		action.id=int(action.id)%10000
	action["station"]=number
	if is_instance_valid(open_lab_tutorial):open_lab_tutorial.record_intent("ac_lab",number,action)
	session.request(action)

func _receive_ac_readings(station: int, revision: int, live: Dictionary) -> void:
	if station < 0 or station >= station_snapshots.size():
		return
	var data: Dictionary = station_snapshots[station]
	if data.revision != revision or not data.powered:
		return
	data.readings.merge(live, true)
	if station == 0:
		for i in 3:
			_set_meter("AMP%d"%i, readings.ammeters[i], readings.ammeter_ranges[i])
			_set_meter("VOLT%d"%i, readings.voltmeters[i], readings.voltmeter_ranges[i])
			physical_readouts["A%d"%i].text = "%.4f A"%readings.ammeters[i]
			physical_readouts["V%d"%i].text = "%.2f V"%readings.voltmeters[i]
		for i in 2:
			_set_meter("WATT%d"%i, readings.wattmeters[i], 250)
			physical_readouts["W%d"%i].text = "%+.3f W"%readings.wattmeters[i]
		_sync_supply_controls(self, data)
	else:
		_sync_station_meters(stations[station - 1].equipment, data)

func _sync_station_meters(equipment: Node3D, data: Dictionary) -> void:
	for i in 3:
		equipment.needle_bodies["AMP%d"%i].rotation.z=deg_to_rad(60-clampf(data.readings.ammeters[i]/data.readings.ammeter_ranges[i],0,1)*120)
		equipment.needle_bodies["VOLT%d"%i].rotation.z=deg_to_rad(60-clampf(data.readings.voltmeters[i]/data.readings.voltmeter_ranges[i],0,1)*120)
	for i in 2:
		equipment.needle_bodies["WATT%d"%i].rotation.z=deg_to_rad(60-clampf(data.readings.wattmeters[i]/250,-.1,1)*120)
	_sync_supply_controls(equipment,data)

func _render_stations() -> void:
	for n in range(stations.size()):
		if n+1>=station_snapshots.size():
			continue
		var data: Dictionary=station_snapshots[n+1]
		var equipment: Node3D=stations[n].equipment
		stations[n].drawer.sync(data.drawer_open)
		for kind in ["R","L","C"]:
			for i in range(9):
				var item: Dictionary=equipment.switch_meshes["%s_%d"%[kind,i]]
				item.handle.rotation.z=-.38 if data.switches[kind][i] else .38
				item.indicator.material_override=_mat(Color("58ef88") if data.switches[kind][i] else Color("56616e"),.2,data.switches[kind][i])
		_sync_station_meters(equipment,data)
		for wire in data.cables:
			var cable: Dictionary=wire.duplicate()
			cable.id=int(cable.id)+(n+1)*10000
			for end in ["a","b"]:
				if cable[end]!="":
					cable[end]=str(n+1)+":"+cable[end]
			leads.append(cable)

func _request_chair(index: int) -> void:
	if session.online and not multiplayer.is_server():
		_chair_claim.rpc_id(1,index)
	else:
		_claim_chair(1,index)

@rpc("any_peer","call_remote","reliable")
func _chair_claim(index: int) -> void:
	if multiplayer.is_server():
		_claim_chair(multiplayer.get_remote_sender_id(),index)

func _claim_chair(peer: int,index: int) -> void:
	if is_instance_valid(dorm_rest) and dorm_rest.state.resting.has(peer):return
	if not session.roster.has(peer) or index<0 or index>=chairs.size():
		return
	var chair: CharacterBody3D=chairs[index]
	var actor_position: Vector3 = player.global_position if peer==multiplayer.get_unique_id() else session.poses.get(peer,{}).get("position",Vector3.INF)
	if chair.occupant!=0 or actor_position.distance_to(chair.global_position)>3:
		return
	if is_instance_valid(computers):
		for station in computers.stations.values():
			if station.chair==index and not computers._private_allowed(peer,station):return
	for other in chairs:
		if other.occupant==peer:
			return
	chair.occupant=peer
	chair.turn_target=float(session.poses.get(peer,{}).get("yaw",0))
	chair.previous_turn_target=chair.turn_target
	if peer==multiplayer.get_unique_id():
		player.sit(chair)
	_send_chairs()

func _update_chair_network(delta: float) -> void:
	if session.online and multiplayer.multiplayer_peer.get_connection_status()!=MultiplayerPeer.CONNECTION_CONNECTED:
		return
	chair_clock+=delta
	if chair_clock<.05:
		return
	chair_clock=0
	var index := chairs.find(player.seated)
	var wish := Vector2(float(player.down("right"))-float(player.down("left")),float(player.down("back"))-float(player.down("forward"))).normalized()
	if session.online and not multiplayer.is_server():
		_chair_input.rpc_id(1,index,wish,player.yaw_target)
	else:
		_accept_chair_input(1,index,wish,player.yaw_target)
	if multiplayer.is_server():
		for chair in chairs:
			if chair.occupant!=0 and not session.roster.has(chair.occupant):
				chair.occupant=0
				chair.drive=Vector2.ZERO
			if Time.get_ticks_msec()-int(chair_input_times.get(chair.occupant,0))>300:
				chair.drive=Vector2.ZERO
		_send_chairs()

@rpc("any_peer","call_remote","unreliable_ordered",2)
func _chair_input(index: int,wish: Vector2,yaw: float) -> void:
	if multiplayer.is_server():
		_accept_chair_input(multiplayer.get_remote_sender_id(),index,wish,yaw)

func _accept_chair_input(peer: int,index: int,wish: Vector2,yaw: float) -> void:
	if not wish.is_finite() or not is_finite(yaw) or not session.roster.has(peer):
		return
	for i in range(chairs.size()):
		var chair: CharacterBody3D=chairs[i]
		if chair.occupant==peer and not chair.fixed_seat:
			if index==i:
				chair_input_times[peer]=Time.get_ticks_msec()
				chair.drive=wish.limit_length(1)
				chair.drive_yaw=float(session.poses.get(peer,{}).get("yaw",chair.swivel.rotation.y))
				chair.turn_target=yaw

func _send_chairs() -> void:
	if not session.online:
		return
	var states: Array=[]
	for chair in chairs:
		states.append({"position":chair.position,"yaw":chair.swivel.rotation.y,"velocity":chair.velocity,"spin":chair.spin,"spin_goal":chair.spin_goal,"occupant":chair.occupant})
	chair_packet_sequence+=1
	for peer in session.connected_peers():
		for offset in range(0,states.size(),4):_chair_states_chunk.rpc_id(peer,chair_packet_sequence,offset,states.slice(offset,offset+4))

@rpc("authority","call_remote","unreliable_ordered",2)
func _chair_states(states: Array,offset: int=0) -> void:
	for local_index in range(mini(states.size(),chairs.size()-offset)):
		var i := offset+local_index
		var chair: CharacterBody3D=chairs[i]
		var state: Dictionary=states[local_index]
		chair.occupant=state.occupant
		chair.network_target=state.position
		chair.network_yaw=state.yaw
		chair.network_ready=true
		if state.occupant==multiplayer.get_unique_id():
			chair.spin=lerpf(chair.spin,float(state.get("spin",0)),.25)
			chair.spin_goal=lerpf(chair.spin_goal,float(state.get("spin_goal",0)),.25)
			chair.velocity=chair.velocity.lerp(state.velocity,.25)
			chair.swivel.rotation.y=lerp_angle(chair.swivel.rotation.y,state.yaw,.15)
			if player.seated==null and not standing_pending:
				chair.position=state.position
				player.sit(chair)
			elif player.seated==chair and chair.position.distance_to(state.position)>.15:
				chair.position=chair.position.lerp(state.position,.35)
		else:
			if standing_pending and standing_chair_index>=offset and standing_chair_index<offset+states.size() and not states.any(func(item): return item.occupant==multiplayer.get_unique_id()):
				standing_pending=false
			if player.seated==chair:
				player.stand_up()

@rpc("authority","call_remote","unreliable",2)
func _chair_states_chunk(sequence: int,offset: int,states: Array) -> void:
	if offset<0 or offset>=chairs.size() or states.size()>4 or sequence<=int(chair_packet_revisions.get(offset,-1)):return
	chair_packet_revisions[offset]=sequence
	_chair_states(states,offset)

func _stand_from_chair() -> void:
	if player.seated==null:
		return
	standing_chair_index=chairs.find(player.seated)
	player.stand_up()
	if player.seated!=null:
		ui.log_message("No clear floor beside the chair." if player.seated.fixed_seat else "Move the chair clear of the table before standing.")
		return
	standing_pending=session.online and not multiplayer.is_server()
	if standing_pending:
		_chair_release.rpc_id(1)
	else:
		_release_chair(1)

@rpc("any_peer","call_remote","reliable")
func _chair_release() -> void:
	if multiplayer.is_server():
		_release_chair(multiplayer.get_remote_sender_id())
		_send_chairs()

func _release_chair(peer: int) -> void:
	for chair in chairs:
		if chair.occupant==peer:
			chair.occupant=0
			chair.drive=Vector2.ZERO

func _character_selected() -> void:
	var data: PackedByteArray=characters.avatar_bytes() if characters.selected!="" else PackedByteArray()
	session.set_appearance(data)
	var bytes: PackedByteArray=data if not data.is_empty() else FileAccess.get_file_as_bytes("res://assets/default_avatar.glb")
	var model=preload("res://scripts/avatar_model.gd").build(bytes)
	if model!=null:
		interaction_presentation.bind_local(model)
		model.free()

func _appearance_received(peer: int,data: PackedByteArray) -> void:
	interaction_presentation.set_local_peer(multiplayer.get_unique_id())
	avatar_data[peer]=data
	if avatars.has(peer):_set_avatar_model(peer,avatars[peer])

func _set_avatar_model(peer: int,avatar: Node3D) -> void:
	var old=avatar.get_node_or_null("CharacterModel")
	if old!=null:
		avatar.remove_child(old)
		old.queue_free()
	var data: PackedByteArray=avatar_data.get(peer,PackedByteArray())
	if data.is_empty():data=FileAccess.get_file_as_bytes("res://assets/default_avatar.glb")
	var model: Node3D
	if cosmetic_appearances.has(peer):
		var cosmetics = preload("res://scripts/avatar_cosmetics/core/coordinator.gd").new()
		if cosmetics.load_catalog():model=preload("res://scripts/avatar_cosmetics/core/avatar_renderer.gd").render_avatar(cosmetic_appearances[peer],cosmetics.catalog)
	if model==null:model=preload("res://scripts/avatar_model.gd").build(data)
	if model!=null:
		model.name="CharacterModel"
		avatar.add_child(model)
		preload("res://scripts/avatar_model.gd").animate(model,false)
		interaction_presentation.bind_avatar(peer,model)
		_apply_supply_accessories(peer,model)

func _sync_supply_controls(equipment: Node,data: Dictionary) -> void:
	equipment.control_bodies.variable.rotation.z=deg_to_rad(135.-270.*float(data.level))
	equipment.control_bodies.power.rotation.z=0 if data.powered else PI
	equipment.control_bodies.dyn_load.rotation.z=deg_to_rad(135.-270.*float(data.dyn_load))
	var selected: int=int(data.get("supply_meter",1))
	equipment.control_bodies.supply_meter.rotation.z=deg_to_rad(135.-270.*selected/13.)
	equipment.control_bodies.igbt_damping.rotation.z=-.6 if data.get("igbt_damping",false) else .6
	var legs: Array = data.readings.get("igbt", {}).get("legs", [0,0,0])
	for i in equipment.igbt_indicators.size():
		var active: bool = legs[i] != 0
		var indicator: StandardMaterial3D = equipment.igbt_indicators[i]
		indicator.albedo_color = Color("fd9660") if active else Color("5f342d")
		indicator.emission_enabled = active
		indicator.emission = Color("e9672b")
	var pairs := [["",""],["P_A","P_N"],["P_B","P_N"],["P_C","P_N"],["P_A","P_B"],["P_B","P_C"],["P_C","P_A"],["PV_A","PV_N"],["PV_B","PV_N"],["PV_C","PV_N"],["PV_A","PV_B"]]
	var volts: Dictionary=data.readings.voltages
	var value := 0.0
	var suffix := "AC"
	if selected < pairs.size():
		value = (volts.get(pairs[selected][0],Vector2.ZERO)-volts.get(pairs[selected][1],Vector2.ZERO)).length()
	else:
		var outlet: Dictionary = preload("res://scripts/ac_auxiliary.gd").supplies(data.level)[selected - pairs.size()]
		value = data.readings.get("outlet_volts", {}).get(outlet.a, outlet.volts)
		suffix = "DC" if outlet.dc else "AC"
	equipment.supply_display.text=("%.1f V %s"%[value,suffix] if selected!=0 else "—") if data.powered else "OFF"
	var measuring: bool=data.get("dyn_measure",false)
	equipment.control_bodies.dyn_measure.position.z=.535 if measuring else .56
	equipment.dynamo_display.text="%.0f RPM   %.2f N·m"%[data.readings.motor_rpm,data.readings.get("dynamo_torque",0.) if absf(data.readings.motor_rpm)>1 else 0.] if measuring else ""

func toggle_inspection() -> void:
	if player.inspecting:end_inspection();return
	var ray := PhysicsRayQueryParameters3D.create(camera.global_position,camera.global_position-camera.global_basis.z*6,5)
	var target=get_world_3d().direct_space_state.intersect_ray(ray).get("collider")
	if not is_instance_valid(target) or target.get_meta("role","") not in ["socket","control","switch"]:return
	if player.seated!=null:ui.log_message("Stand up before inspecting a device.");return
	var module: Node3D=target.get_parent()
	var distance := Vector2(player.global_position.x-module.global_position.x,player.global_position.z-module.global_position.z).length()
	if distance>3.25:ui.log_message("Walk closer to the workbench to inspect it.");return
	inspect_camera=Camera3D.new();add_child(inspect_camera);inspect_camera.global_position=module.global_position+module.global_basis.z*2.3
	inspect_camera.look_at(module.global_position);inspect_camera.fov=58;inspect_camera.near=.035;inspect_camera.current=true
	camera=inspect_camera;inspect_rotation=camera.rotation;player.inspecting=true
	_load_inspection_views()
	inspection_view_key=JSON.stringify([characters.selected,module.global_position.snapped(Vector3.ONE*.001)]).sha256_text()
	var remembered:Variant=inspection_views.get(inspection_view_key,{})
	if remembered is Dictionary:
		var fov:Variant=remembered.get("fov",58.)
		if (fov is int or fov is float) and is_finite(float(fov)):camera.fov=clampf(float(fov),28,78)
		var offset:Variant=remembered.get("offset",Vector2.ZERO)
		if offset is Vector2 and offset.is_finite():camera.rotation=inspect_rotation+Vector3(clampf(offset.x,-.5,.5),clampf(offset.y,-.7,.7),0)
	ui.log_message("Inspection · mouse to aim · wheel to zoom · F or Esc to return")
func end_inspection() -> void:
	if player.inspecting and is_instance_valid(inspect_camera) and inspection_view_key!="":
		inspection_views[inspection_view_key]={"fov":inspect_camera.fov,"offset":Vector2(inspect_camera.rotation.x-inspect_rotation.x,inspect_camera.rotation.y-inspect_rotation.y)}
		if inspection_views.size()>128:inspection_views.erase(inspection_views.keys()[0])
		var cfg:=ConfigFile.new();cfg.set_value("views","devices",inspection_views);cfg.save("user://inspection_views.cfg")
	player.inspecting=false;camera=player.eyes;camera.current=true
	if is_instance_valid(inspect_camera):inspect_camera.queue_free()

func _load_inspection_views() -> void:
	if inspection_views_loaded:return
	inspection_views_loaded=true
	if not FileAccess.file_exists("user://inspection_views.cfg"):return
	var file:=FileAccess.open("user://inspection_views.cfg",FileAccess.READ)
	if file==null:return
	var length:=file.get_length();file.close()
	if length>262144:return
	var cfg:=ConfigFile.new()
	if cfg.load("user://inspection_views.cfg")!=OK:return
	var stored:Variant=cfg.get_value("views","devices",{})
	if stored is Dictionary and stored.size()<=128:inspection_views=stored


func _toggle_supply_flashlight() -> void:
	if not is_instance_valid(supply_flashlight):
		supply_flashlight=SpotLight3D.new()
		supply_flashlight.spot_range=14
		supply_flashlight.spot_angle=27
		supply_flashlight.light_energy=2.3
		supply_flashlight.hide()
		player.eyes.add_child(supply_flashlight)
	supply_flashlight.visible=not supply_flashlight.visible

func _sync_supply_accessories() -> void:
	for peer in avatars:
		var model: Node3D=avatars[peer].get_node_or_null("CharacterModel")
		if is_instance_valid(model):_apply_supply_accessories(peer,model)

func _apply_supply_accessories(peer: int, model: Node3D) -> void:
	var gear: Dictionary=school.worn_gear.get(peer,{})
	if model.get_meta("supply_gear",{})==gear:return
	model.set_meta("supply_gear",gear.duplicate())
	for node_name in ["PhysicalGoggles","PhysicalBackpack"]:
		var old := model.find_child(node_name,true,false)
		if is_instance_valid(old):
			old.get_parent().remove_child(old)
			old.queue_free()
	const Toon = preload("res://scripts/toon_character.gd")
	if gear.get("head",false):
		var head := model.find_child("Head",true,false) as Node3D
		if is_instance_valid(head):
			var glasses := Node3D.new();glasses.name="PhysicalGoggles";head.add_child(glasses)
			var frame := Toon.material("3a7182")
			var lens := Toon.material("acddeb",.3)
			for side in [-1.0,1.0]:
				Toon.ellipsoid(glasses,Vector3(side*.092,.018,.197),Vector3(.081,.069,.024),frame)
				Toon.ellipsoid(glasses,Vector3(side*.092,.018,.213),Vector3(.068,.056,.014),lens)
				Toon.link(glasses,Vector3(side*.165,.018,.195),Vector3(side*.225,.007,.02),.015,frame)
			Toon.link(glasses,Vector3(-.032,.026,.218),Vector3(.032,.026,.218),.014,frame)
	if not str(gear.get("back","")).is_empty():
		var pack := Node3D.new();pack.name="PhysicalBackpack";model.add_child(pack)
		var width: float={"backpack_small":.18,"backpack_medium":.22,"backpack_large":.26,"backpack_giant":.29}.get(gear.back,.22)
		Toon.ellipsoid(pack,Vector3(0,1.05,-.20),Vector3(width,.33,.16),Toon.material("476775"))
		Toon.ellipsoid(pack,Vector3(0,.94,-.33),Vector3(width*.76,.13,.054),Toon.material("354e5c"))
