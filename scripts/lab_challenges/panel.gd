extends CanvasLayer
const UI = preload("res://scripts/ui/design_system/widgets.gd")
signal request(bench: int,action: Dictionary)
signal closed
var screen: PanelContainer
var bench_picker: OptionButton
var scenario: OptionButton
var seed_box: SpinBox
var info: Label
var status: Label
var history: Label
var unlocked: Label
var decoration: OptionButton
var anchor: OptionButton
var diagnosis: OptionButton
var start_button: Button
var attempt_id := ""
var history_offset := 0
var history_total := 0
func build() -> void:
	layer=46
	screen=PanelContainer.new();screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);screen.offset_left=40;screen.offset_top=28;screen.offset_right=-40;screen.offset_bottom=-28;screen.theme=preload("res://scripts/campus/ui/campus_theme.gd").create();add_child(screen);screen.hide()
	var skin := StyleBoxFlat.new();skin.bg_color=Color("10222c");skin.set_corner_radius_all(12);skin.set_content_margin_all(22);screen.add_theme_stylebox_override("panel",skin)
	var box := VBoxContainer.new();box.add_theme_constant_override("separation",10);screen.add_child(box)
	screen.theme=preload("res://scripts/ui/design_system/theme.gd").create()
	box.add_child(UI.card("Troubleshooting studio","Work together: measure, diagnose, repair and verify.","circuit"))
	var top := HBoxContainer.new();box.add_child(top);var heading := _label(top,"TEAM / VOLT · TROUBLESHOOTING");heading.add_theme_font_size_override("font_size",24);heading.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	_button(top,"Return",func():screen.hide();closed.emit())
	bench_picker=OptionButton.new();for i in 3:bench_picker.add_item("AC station %d"%(i+1))
	box.add_child(bench_picker);bench_picker.item_selected.connect(func(i):request.emit(i,{"command":"view"}))
	var tabs := TabContainer.new();tabs.size_flags_vertical=Control.SIZE_EXPAND_FILL;box.add_child(tabs)
	var scroll := ScrollContainer.new();scroll.name="Challenge";tabs.add_child(scroll)
	var active := VBoxContainer.new();active.size_flags_horizontal=Control.SIZE_EXPAND_FILL;scroll.add_child(active)
	scenario=OptionButton.new();for entry in preload("res://scripts/lab_challenges/scenario_catalog.gd").catalog():scenario.add_item(entry.title);scenario.set_item_metadata(scenario.item_count-1,entry.id)
	active.add_child(scenario)
	seed_box=SpinBox.new();seed_box.min_value=0;seed_box.max_value=2147483647;seed_box.value=1;seed_box.step=1;seed_box.prefix="Project variant ";seed_box.tooltip_text="The same variant creates the same circuit problem. Change it for a different problem.";active.add_child(seed_box)
	start_button=_button(active,"Start team challenge · host",func():_send({"command":"start","kind":scenario.get_selected_metadata(),"seed":int(seed_box.value)}))
	info=_label(active,"Bring 2–8 authenticated players to the same AC bench. Only the host starts or restores a challenge.")
	_label(active,"Workflow: safe preflight → energize and record the original fault → diagnose → power off and repair → preflight and record again → submit. Assigned roles need actual electrical evidence. No reward for speed or unsafe shortcuts.")
	diagnosis=OptionButton.new()
	for entry in [["Missing matching PF capacitor","missing_capacitor"],["Open phase 1","open_phase_1"],["Open phase 2","open_phase_2"],["Open phase 3","open_phase_3"],["Voltmeter 1 reference","voltmeter_reference_1"],["Voltmeter 2 reference","voltmeter_reference_2"],["Voltmeter 3 reference","voltmeter_reference_3"],["Load bank 1 selection","load_bank_1"],["Load bank 2 selection","load_bank_2"],["Load bank 3 selection","load_bank_3"]]:diagnosis.add_item(entry[0]);diagnosis.set_item_metadata(diagnosis.item_count-1,entry[1])
	active.add_child(diagnosis)
	_button(active,"Submit measured diagnosis",func():_send({"command":"diagnose","attempt_id":attempt_id,"diagnosis":diagnosis.get_selected_metadata()}))
	_button(active,"Submit repaired circuit and team evidence",func():_send({"command":"submit","attempt_id":attempt_id}))
	_button(active,"Restore journaled attempt · host",func():_send({"command":"resume","attempt_id":attempt_id}))
	_button(active,"End optional attempt · host · no academic penalty",func():_send({"command":"abandon","attempt_id":attempt_id}))
	var history_page := VBoxContainer.new();history_page.name="Team records";tabs.add_child(history_page)
	var navigation := HBoxContainer.new();history_page.add_child(navigation)
	_button(navigation,"Newer records",func():history_offset=maxi(0,history_offset-20);_send({"command":"view","history_offset":history_offset}))
	_button(navigation,"Older records",func():history_offset=mini(maxi(0,int(floor((history_total-1)/20.0))*20),history_offset+20);_send({"command":"view","history_offset":history_offset}))
	var history_scroll := ScrollContainer.new();history_scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL;history_page.add_child(history_scroll);history=_label(history_scroll,"");history.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	var cosmetics := VBoxContainer.new();cosmetics.name="Lab honours";tabs.add_child(cosmetics)
	unlocked=_label(cosmetics,"Earn distinct seeded team completions to unlock fixed laboratory wall decorations. Essential equipment stays available in Free Laboratory.")
	anchor=OptionButton.new();anchor.add_item("Left honours mount");anchor.set_item_metadata(0,"left_award");anchor.add_item("Right honours mount");anchor.set_item_metadata(1,"right_award");cosmetics.add_child(anchor)
	decoration=OptionButton.new();cosmetics.add_child(decoration)
	_button(cosmetics,"Place earned decoration",func():_send({"command":"decorate","anchor":anchor.get_selected_metadata(),"decoration":decoration.get_selected_metadata()}))
	_button(cosmetics,"Clear own mount · host may clear any",func():_send({"command":"decorate","anchor":anchor.get_selected_metadata(),"decoration":""}))
	status=_label(box,"")
func show_at(bench: int) -> void:
	bench_picker.select(clampi(bench,0,2));screen.show();request.emit(bench_picker.selected,{"command":"view"})
func _send(action: Dictionary) -> void:request.emit(bench_picker.selected,action)
func _label(parent: Node,value: String) -> Label:
	var label := Label.new();label.text=value;label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;parent.add_child(label);return label
func _button(parent: Node,value: String,callback: Callable) -> Button:
	var key := "check" if value.begins_with("Submit") else "play" if value.begins_with("Start") else "back" if value=="Return" else "warning" if value.begins_with("End") else "course"
	var button := UI.action(value,key,callback,value.begins_with("Submit"));parent.add_child(button);return button
func _role_title(role: String) -> String:
	return {"repair":"Repair the circuit","verify":"Check the wiring","measure_final":"Measure the circuit"}.get(role,role.replace("_"," ").capitalize())
func _progress(evidence: Dictionary) -> String:
	var steps: Array[String]=[]
	for pair in [["measure_fault","Original fault measured"],["repair","Repair confirmed"],["verify","Wiring check passed"],["measure_final","Final readings saved"]]:
		if evidence.get(pair[0],false):steps.append(pair[1])
	return "Ready to begin" if steps.is_empty() else " · ".join(steps)
func update_frame(frame: Dictionary,message := "") -> void:
	status.text=message
	history_offset=int(frame.get("history_offset",0));history_total=int(frame.get("history_total",0))
	var active: Dictionary=frame.get("active",{});attempt_id=str(active.get("id",""))
	info.text="No active team attempt. Start one while the circuit is powered off." if active.is_empty() else str(active.get("objective",""))+"\n"+("Host restore required after recovery.\n" if active.get("needs_resume",false) else "")
	scenario.disabled=not active.is_empty();seed_box.editable=active.is_empty();start_button.disabled=not active.is_empty()
	if not active.is_empty():
		for i in scenario.item_count:
			if scenario.get_item_metadata(i)==active.get("kind",""):scenario.select(i);break
		seed_box.value=int(active.get("seed",seed_box.value))
	for player in active.get("participants",[]):info.text+="\n"+str(player.name)+" — "+_role_title(str(player.role))+"\n"+_progress(player.get("evidence",{}))
	history.text="TEAM COMPLETION HISTORY · host journal · newest first\n"
	var records: Array=frame.get("history",[]).duplicate();records.reverse()
	for record in records:
		history.text+="\n%s · seed %d · %s\n"%[str(record.kind),int(record.seed),str(record.outcome)]
		for player in record.participants:history.text+=str(player.name)+" ("+str(player.role).replace("_"," ")+")  "
		if record.get("outcome","")=="completed":history.text+="\nActual P %.3f W · Q %.3f var · PF %.4f · motor %.1f RPM\n"%[float(record.measurements.p),float(record.measurements.q),float(record.measurements.pf),float(record.measurements.motor_rpm)]
	decoration.clear()
	for id in frame.get("unlocks",[]):
		if preload("res://scripts/lab_challenges/decorations.gd").DEFINITIONS.has(id):decoration.add_item(preload("res://scripts/lab_challenges/decorations.gd").DEFINITIONS[id].name);decoration.set_item_metadata(decoration.item_count-1,id)
	unlocked.text="Earned lab honours: %d. Repeating the same kind and seed keeps a team record but awards no duplicate dollars or mastery. First128distinct completions per profile grant mastery; later records remain available. Essential Free Laboratory equipment is never locked."%decoration.item_count
