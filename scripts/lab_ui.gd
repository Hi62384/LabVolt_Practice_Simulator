extends CanvasLayer
const UI = preload("res://scripts/ui/design_system/widgets.gd")
const HudTheme = preload("res://scripts/ui/design_system/theme.gd")
const Layout = preload("res://scripts/ui/hud_settings/layout.gd")
var crosshair: Label
var game: Node
var hud: Label
var prompt: Label
var log_label: Label
var fps_label: Label
var fps_elapsed := 0.0
var objective: Label
var menu: PanelContainer
var sheet: PanelContainer
var roster_label: Label
var connection_label: Label
var sheet_text: Label
var name_input: LineEdit
var address: LineEdit
var port: SpinBox
var modes: OptionButton
var tasks: OptionButton
var seed_input: SpinBox
var inputs := {}
var chat_input: LineEdit
var result: Label
var assists: CheckBox
var logs: Array[String] = []
var public_visibility: RefCounted
var graphics_controller: Node
var lobby: VBoxContainer
var records_label: Label
var records_body: VBoxContainer
var roster_body: VBoxContainer

func label(text: String, parent: Node, size := 16) -> Label:
	var node: Label = preload("res://scripts/ui/hud_settings/readout.gd").new() if parent == self and text != "·" else Label.new()
	node.text = text
	node.add_theme_font_size_override("font_size",size)
	parent.add_child(node)
	return node

func button(text: String,parent: Node,callback: Callable) -> Button:
	var icons := {"Single Player":"play", "Enter / Resume":"play", "Exit":"close", "Ready / Unready":"check", "Leave Session":"back", "Preflight":"check", "Record instruments":"save", "Submit":"course", "Toggle fullscreen - F11 / Alt+Enter":"settings"}
	var node := UI.action(text, icons.get(text, UI.action_icon(text)), callback, text in ["Enter / Resume", "Submit"])
	parent.add_child(node)
	return node

func panel(position: Vector2, size: Vector2) -> PanelContainer:
	var node := PanelContainer.new()
	node.position = position
	node.custom_minimum_size = size
	node.theme = HudTheme.create()
	node.add_theme_stylebox_override("panel", HudTheme.card_style())
	add_child(node)
	return node

func build(owner_game: Node) -> void:
	game = owner_game
	hud = label("",self,18)
	hud.position = Vector2(28,24)
	objective = label("",self,15)
	objective.position = Vector2(28,82)
	log_label = label("",self,14)
	log_label.resized.connect(_position_notification)
	fps_label = label("",self,13)
	fps_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	fps_label.set("icon_key", "")
	prompt = label("",self,15)
	prompt.position = Vector2(360,390)
	prompt.custom_minimum_size.x = 560
	prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	crosshair=label("·",self,28)
	crosshair.add_theme_color_override("font_outline_color",Color.BLACK)
	crosshair.add_theme_constant_override("outline_size",3)
	for gameplay_label in [hud,objective,log_label,prompt,crosshair,fps_label]:
		gameplay_label.hide()
	var cross := crosshair
	cross.position = Vector2(634,342)
	chat_input = LineEdit.new()
	chat_input.position = Vector2(28,550)
	chat_input.size = Vector2(650,36)
	chat_input.max_length = 240
	chat_input.placeholder_text = "Team chat / shared observations — Enter to send"
	chat_input.visible = false
	add_child(chat_input)
	chat_input.text_submitted.connect(func(value): game.session.chat(value); chat_input.text=""; chat_input.hide(); game.capture())
	menu = panel(Vector2(160,30),Vector2(0,0))
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation",8)
	menu.add_child(box)
	box.add_child(UI.header("Laboratory", "Your session, experiment and personal settings", func(): game.capture()))
	var tabs := TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(tabs)
	lobby = Layout.page(tabs, "Session", "network")
	var session_card := Layout.section(lobby, "Connect with your team", "Direct IP • 2–8 players • UDP", "network")
	name_input = LineEdit.new()
	name_input.placeholder_text = "Player name"
	name_input.text = game.characters.display_name() if is_instance_valid(game.characters) else "Student"
	name_input.max_length = 24
	Layout.field(session_card, "Player name", name_input)
	var network := VBoxContainer.new()
	session_card.add_child(network)
	address = LineEdit.new()
	address.text = "127.0.0.1"
	address.placeholder_text = "Host IP"
	address.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	Layout.field(network, "Host address", address)
	port = SpinBox.new()
	port.min_value = 1024
	port.max_value = 65535
	port.value = 24842
	Layout.field(network, "UDP port", port)
	var row := Layout.flow(session_card)
	button("Single Player",row,func(): game.session.leave(); game.capture())
	button("Host Laboratory",row,func(): var error=game.session.host_game(name_input.text,int(port.value)); connection_label.text="Hosting UDP %d"%port.value if error==OK else "Cannot host: "+error_string(error))
	button("Join Laboratory",row,func(): var error=game.session.join_game(address.text,name_input.text,int(port.value)); connection_label.text="Connecting…" if error==OK else error_string(error))
	connection_label = label("Direct IP • 2–8 players • UDP 24842",lobby,14)
	var team_card := Layout.section(lobby, "Team roster", "Ready up when your team is prepared.", "network")
	roster_label = label("",team_card,15)
	roster_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	roster_body = VBoxContainer.new()
	team_card.add_child(roster_body)
	row = Layout.flow(team_card)
	button("Ready / Unready",row,func(): game.session.ready_toggle())
	button("Leave Session",row,func(): game.session.leave(); connection_label.text="Local laboratory")
	var experiment_card := Layout.section(lobby, "Experiment setup", "Host controls • applies through the existing session request", "circuit")
	modes = OptionButton.new()
	for text in ["Free Laboratory","Guided Learning","Practical Exam","Cooperative Challenge"]:
		modes.add_item(text)
	Layout.field(experiment_card, "Laboratory mode", modes)
	tasks = OptionButton.new()
	for text in ["Balanced Wye","Balanced Delta","Power factor correction"]:
		tasks.add_item(text)
	Layout.field(experiment_card, "Experiment", tasks)
	row = Layout.flow(experiment_card)
	label("Experiment seed",row,14)
	seed_input = SpinBox.new()
	seed_input.min_value = 1
	seed_input.max_value = 999999
	seed_input.value = 101
	seed_input.custom_minimum_size.y = 44
	row.add_child(seed_input)
	button("Assign experiment (host)",experiment_card,func(): game._request({"op":"configure","mode":modes.get_item_text(modes.selected),"task":tasks.selected,"seed":int(seed_input.value)}))
	var note := label("LAN: join the host's local IP. Internet: forward the chosen\nUDP port to the host and allow Godot through the firewall.\nNo matchmaking service or automatic NAT traversal.",lobby,13)
	note.theme_type_variation = "MutedLabel"
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	graphics_controller=preload("res://scripts/campus/ui/graphics_settings.gd").new()
	add_child(graphics_controller)
	# Initial application waits until static equipment is assembled and batched.
	graphics_controller.viewport=get_viewport();graphics_controller.world=game
	graphics_controller.load_settings()
	public_visibility=preload("res://scripts/campus/ui/profile_visibility.gd").new()
	public_visibility.load_settings()
	assists = CheckBox.new()
	assists.button_pressed = true
	add_child(assists)
	assists.hide()
	var records_tab := Layout.page(tabs, "Records", "course")
	var record_card := Layout.section(records_tab, "Personal lab record", "Your best results and recent submissions", "course")
	records_label = label("No submissions yet.",record_card,16)
	records_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	records_body = VBoxContainer.new()
	record_card.add_child(records_body)
	row = Layout.flow(box)
	button("Enter / Resume",row,func(): game.capture())
	button("Exit",row,func(): game.get_tree().quit())
	sheet = panel(Vector2(160,36),Vector2.ZERO)
	sheet.hide()
	box = VBoxContainer.new()
	box.add_theme_constant_override("separation",10)
	var sheet_scroll := ScrollContainer.new()
	sheet_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sheet_scroll.follow_focus = true
	sheet.add_child(sheet_scroll)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sheet_scroll.add_child(box)
	box.add_child(UI.header("Experiment record", "Measure • record • submit", func(): sheet.hide(); game.capture()))
	sheet_text = label("",box,16)
	sheet_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sheet_text.custom_minimum_size = Vector2(0,180)
	row = Layout.flow(box)
	for key in ["v","i","p"]:
		var field := UI.field({"v":"Voltage · V RMS","i":"Current · A RMS","p":"Real power · W"}[key], {"v":"Measured V RMS","i":"Measured A RMS","p":"Total watts (W1 + W2)"}[key])
		field.custom_minimum_size.x = 190
		var input := field.get_node("Input") as LineEdit
		row.add_child(field)
		inputs[key] = input
	row = Layout.flow(box)
	button("Preflight",row,func(): game._request({"op":"check"}))
	button("Record instruments",row,func(): game._request({"op":"record"}))
	button("Submit",row,func(): game._request({"op":"submit","v":float(inputs.v.text),"i":float(inputs.i.text),"p":float(inputs.p.text)}))
	result = label("",box,15)
	result.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	result.custom_minimum_size.y = 60
	label("Use your course's real safety procedures. This model does not certify wiring.\nEsc menu • B clipboard • C preflight • E operate • Q unplug • Z undo\n1–4 cable color • G return held cable • T chat • X ping • F8 telemetry",box,14)
	button("Close clipboard",box,func(): sheet.hide(); game.capture())
	for overlay in [hud, objective, prompt, log_label, fps_label]:
		overlay.theme = menu.theme
		overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
		overlay.add_theme_color_override("font_shadow_color", Color.BLACK)
		overlay.add_theme_constant_override("shadow_outline_size", 3)
	hud.add_theme_stylebox_override("normal", HudTheme.card_style())
	hud.set("icon_key", "switch")
	objective.set("icon_key", "course")
	prompt.set("icon_key", "")
	log_label.set("icon_key", "info")
	objective.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	log_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	chat_input.theme = menu.theme
	get_viewport().size_changed.connect(_fit_layout)
	_fit_layout()
	update_roster()

func _fit_layout() -> void:
	var area := get_viewport().get_visible_rect().size
	for window in [menu, sheet]:
		window.size = Vector2(minf(960, area.x - 32), minf(660, area.y - 32))
		window.position = (area - window.size) * 0.5
	crosshair.position = area * 0.5 - Vector2(6, 18)
	hud.position = Vector2(52, 24)
	objective.position = Vector2(52, 88)
	objective.custom_minimum_size.x = minf(580, area.x - 80)
	prompt.position = Vector2(maxf(16, (area.x - 560) * 0.5), area.y * 0.56)
	prompt.custom_minimum_size.x = minf(560, area.x - 32)
	fps_label.size.x = 108
	fps_label.position = Vector2(area.x - fps_label.size.x - 22, 52)
	log_label.custom_minimum_size.x = clampf(area.x - 80, 1, 340)
	log_label.reset_size()
	_position_notification()

func _position_notification() -> void:
	var area := get_viewport().get_visible_rect().size
	log_label.position = Vector2(maxf(34, area.x - log_label.size.x - 26), maxf(28, area.y - 116 - log_label.size.y))

func _process(delta: float) -> void:
	if not is_instance_valid(fps_label) or not fps_label.visible:
		return
	fps_elapsed += delta
	if fps_elapsed < .25:
		return
	fps_elapsed = 0.0
	fps_label.text = "%d FPS" % Engine.get_frames_per_second()

func update_records(history: Array) -> void:
	var best := {}
	for item in history:
		var key := str(item.get("task",0))+":"+str(item.seed)+":"+str(item.mode)
		var score := int(str(item.result).get_slice("/",0))
		best[key] = maxi(int(best.get(key,0)),score)
	var xp := 0
	var perfect := false
	for key in best:
		xp += best[key]
		perfect = perfect or best[key]==100
	records_label.text = "%d XP • %d experiment records" % [xp,best.size()]
	for child in records_body.get_children():
		records_body.remove_child(child); child.queue_free()
	records_body.add_child(UI.badge("Accurate measurements earned" if perfect else "Earn 100/100 to unlock Accurate measurements", "check" if perfect else "course"))
	records_body.add_child(UI.text("Personal bests improve XP once per mode / task / seed. All training equipment remains available in Free Laboratory.", "MutedLabel"))
	if history.is_empty():
		records_body.add_child(UI.text("No submissions yet. Complete an experiment to start your record.", "MutedLabel"))
	for i in range(maxi(0,history.size()-5),history.size()):
		var item: Dictionary = history[i]
		var card := UI.card(str(item.mode), "Seed %s • %s/100" % [str(item.seed),str(item.result).get_slice("/",0)], "course")
		card.get_node("Content/Copy/Rarity").hide()
		records_body.add_child(card)

func update_roster() -> void:
	if not is_instance_valid(roster_label):
		return
	roster_label.text = "%d players in this session" % game.session.roster.size()
	for child in roster_body.get_children():
		roster_body.remove_child(child); child.queue_free()
	for id in game.session.roster:
		var entry: Dictionary = game.session.roster[id]
		var card := UI.card(str(entry.name), ("Ready" if entry.ready else "Waiting") + (" • Host" if id==1 else ""), "check" if entry.ready else "network")
		card.get_node("Content/Copy/Rarity").hide()
		roster_body.add_child(card)

func log_message(text: String) -> void:
	log_label.text = text
	log_label.reset_size()
	_position_notification()
	get_tree().create_timer(3.0).timeout.connect(func():
		if log_label.text == text:
			log_label.text = ""
	)

func refresh(data: Dictionary) -> void:
	var held := ""
	for c in data.cables:
		if c.owner == game.multiplayer.get_unique_id():
			held = " • carrying %s lead" % ["red","blue","yellow","black"][c.color]
	hud.text = ("POWER ON" if data.powered else "POWER OFF")+held
	var task_name: String = ["Balanced Wye","Balanced Delta","Power factor correction"][data.task]
	objective.text = "Esc: menu" if data.mode=="Free Laboratory" else task_name+" | B: worksheet"
	var ohms: float = [1200.0,600.0,300.0][data.element]
	sheet_text.text = "%s — %s\nSeed %d\n\n" % [data.mode,task_name,data.seed]
	if data.task < 2:
		sheet_text.text += "Build a balanced three-phase %s using %.0f Ω per branch.\n" % ["Wye" if data.task==0 else "Delta",ohms]
		sheet_text.text += "Use the fixed supply for Wye; set variable supply to 57%% for Delta.\n"
	else:
		sheet_text.text += "Compensate a 1200 Ω resistor and 3.2 H inductive load using a 2.2 µF capacitor, supplied at 120 V / 60 Hz. Target |Q| < 0.75 var.\n"
	sheet_text.text += "Measure branch voltage, line current, and total real power with the physical instruments. Complete preflight before energizing, record readings, enter your observations, then submit.\n\n"
	if data.mode=="Guided Learning":
		sheet_text.text += ["Connect one load to each phase. Join the three returns to neutral. Put current coils in series, voltage coils in parallel.","Bridge AB, BC and CA with the three loads. Do not join the branch returns to neutral. Put current coils in series with supply lines.","Connect the first R, L and C elements in parallel across phase A and N. Compare Q before and after compensation."][data.task]
	else:
		sheet_text.text += "Reference: ZL = j2πfL; ZC = 1/(j2πfC); S = V·conj(I)."
	result.text = data.result
	if not data.records.is_empty():
		result.text += "\nRecorded: %.3f V / %.5f A / %.3f W" % [data.records.v,data.records.i,data.records.p]
	var exam: bool = data.mode=="Practical Exam"
	assists.disabled = exam
	if game.telemetry and assists.button_pressed and not exam:
		objective.text += "\nP %.3f W  Q %.3f var  PF %.4f\nV %s\nA %s\nW %s" % [data.readings.p,data.readings.q,data.readings.pf,str(data.readings.voltmeters),str(data.readings.ammeters),str(data.readings.wattmeters)]
	var team: Dictionary=data.get("team_challenge",{})
	if not team.is_empty():
		objective.text="Team troubleshooting · "+str(team.get("title",""))+""
		sheet_text.text=str(team.get("objective",""))+"\nUse the dedicated Team Troubleshooting panel for diagnosis, assigned roles and team submission. Existing record controls capture real instruments."
		result.text="Optional team progression; official course marks and personal history are separate."
