extends CanvasLayer
## Local tutorial UI and HUD. No equipment mutation or network request.
const Catalog = preload("res://scripts/campus/academics/open_lab/tutorials/catalog.gd")
const Session = preload("res://scripts/campus/academics/open_lab/tutorials/session.gd")
const Targets = preload("res://scripts/campus/academics/open_lab/tutorials/target_resolver.gd")
const CueProjection = preload("res://scripts/campus/academics/open_lab/tutorials/projection.gd")
const UI = preload("res://scripts/ui/design_system/widgets.gd")
var game: Node
var registry: Object
var lesson := Session.new()
var panel: PanelContainer
var body: VBoxContainer
var cue: PanelContainer
var cue_text: Label
var pending: Dictionary={}
var previous_snapshot: Dictionary={}

func open(owner: Node) -> bool:
	game=owner
	registry=game.school.room_bridge.registry
	if registry==null:return false
	var lab_id := str(registry.call("locate",game.player.global_position))
	if not Catalog.COURSES.has(lab_id) or game.school.mode not in ["Open Lab","Freeplay","Creative Freeplay"]:return false
	var index := _bench(lab_id)
	lesson.configure(game.multiplayer.get_unique_id(),lab_id,index)
	if panel==null:_build()
	panel.show();cue.hide();_list()
	game.release_mouse()
	return true

func _bench(lab_id: String) -> int:
	if lab_id=="ac_lab":return game._active_station()
	var chosen := 0;var best := INF
	for i in game.dc_lab.instrument_fixtures.size():
		var distance: float=game.player.global_position.distance_squared_to(game.dc_lab.instrument_fixtures[i].global_position)
		if distance<best:best=distance;chosen=i
	return chosen

func _build() -> void:
	panel=PanelContainer.new()
	panel.theme=preload("res://scripts/ui/design_system/theme.gd").create()
	panel.add_theme_stylebox_override("panel",preload("res://scripts/ui/design_system/theme.gd").card_style())
	add_child(panel)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus=true
	panel.add_child(scroll)
	body=VBoxContainer.new();body.size_flags_horizontal=Control.SIZE_EXPAND_FILL;scroll.add_child(body)
	body.add_theme_constant_override("separation",10)
	get_viewport().size_changed.connect(_fit_panel)
	_fit_panel()
	cue=PanelContainer.new();cue.mouse_filter=Control.MOUSE_FILTER_IGNORE;cue.hide();add_child(cue)
	cue_text=Label.new();cue_text.custom_minimum_size=Vector2(270,42);cue_text.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;cue.add_child(cue_text)
	set_process(true)

func _fit_panel() -> void:
	var viewport_size := get_viewport().get_visible_rect().size
	panel.size=Vector2(minf(780,viewport_size.x-44),minf(580,viewport_size.y-44))
	panel.position=(viewport_size-panel.size)*.5

func _clear() -> void:
	for child in body.get_children():body.remove_child(child);child.queue_free()

func _text(value: String) -> void:
	var label := Label.new();label.text=value;label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;body.add_child(label)

func _button(value: String,handler: Callable) -> void:
	body.add_child(UI.action(value,"course",handler))

func _list() -> void:
	_clear()
	body.add_child(UI.header("Equipment tutorial",str(Catalog.COURSES[lesson.lab_id]),close))
	_button("Guided tour",func():lesson.start_tour();_detail())
	for entry in Catalog.devices(lesson.lab_id):
		var id: String=entry.id
		var card := UI.card(entry.title,entry.purpose,"meter")
		body.add_child(card)
		card.get_node("Content/Copy").add_child(UI.action("Start lesson","play",func():lesson.choose(id);_detail()))
	_button("Close",close)

func _detail() -> void:
	_clear()
	var view := lesson.view()
	if not view.active:_list();return
	_text(view.title+" · "+view.purpose)
	_text("What it does: "+view.output)
	_text("Controls: "+view.controls)
	_text("Connections: "+view.ports)
	_text("How to use it: "+view.detail)
	_text("Watch for: "+view.mistakes)
	_text("Step %d/%d: %s"%[view.step_index+1,view.step_count,view.step.instruction])
	if view.step.check.is_empty():_button("Got it · next step",func():lesson.acknowledge();_detail())
	else:_button("Practice in the lab",func():panel.hide();game.capture())
	_button("Skip this step",func():lesson.skip();_detail())
	_button("Restart this device",func():lesson.restart();_detail())
	_button("Device list",_list)
	_button("Exit tutorial",close)

func close() -> void:
	lesson.exit();pending.clear();panel.hide();cue.hide();game.capture()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode==KEY_F6 and lesson.active and is_instance_valid(panel) and not panel.visible:
		panel.show();cue.hide();_detail();game.release_mouse();get_viewport().set_input_as_handled();return
	if event.is_action_pressed("ui_cancel") and lesson.active and is_instance_valid(panel) and not panel.visible:
		close();get_viewport().set_input_as_handled();return
	if event.is_action_pressed("ui_cancel") and is_instance_valid(panel) and panel.visible:
		close();get_viewport().set_input_as_handled()

func record_intent(lab_id: String,index: int,action: Dictionary) -> void:
	if not lesson.active or lesson.lab_id!=lab_id or lesson.bench_index!=index:return
	pending={"peer_id":lesson.peer_id,"lab_id":lab_id,"bench_index":index,"action":action.duplicate(true)}
	previous_snapshot=_snapshot()

func accepted_snapshot(lab_id: String,index: int,state: Dictionary) -> void:
	if pending.is_empty() or str(pending.lab_id)!=lab_id or int(pending.bench_index)!=index:return
	if not _intent_applied(pending.action,previous_snapshot,state):return
	var event: Dictionary=pending.action.duplicate(true)
	event.peer_id=pending.peer_id;event.lab_id=lab_id;event.bench_index=index;event.accepted=true
	if lesson.observe(event,state) and panel.visible:_detail()
	pending.clear();previous_snapshot.clear()

func _intent_applied(action: Dictionary,before: Dictionary,after: Dictionary) -> bool:
	if int(after.get("revision",-1))<=int(before.get("revision",-1)):return false
	var op := str(action.get("op",""));var key := str(action.get("key",""))
	var index := int(action.get("index",-1))
	match op:
		"channel":
			if index<0 or index>=3:return false
			return before.channels[index].get(key)!=after.channels[index].get(key) and after.channels[index].get(key)==action.get("value")
		"master":return before.get("master")!=after.get("master")
		"current_source":
			if index<0 or index>=4:return false
			return before.current_sources[index].get(key)!=after.current_sources[index].get(key) and after.current_sources[index].get(key)==action.get("value")
		"generator":return before.generator.get(key)!=after.generator.get(key) and after.generator.get(key)==action.get("value")
		"meter":return before.get("meter_mode")!=after.get("meter_mode") and after.get("meter_mode")==action.get("mode")
		"meter_range":return before.get("meter_range")!=after.get("meter_range") and after.get("meter_range")==action.get("value")
		"scope":
			if action.has("channel"):
				var channel := int(action.channel)
				return channel>=0 and channel<2 and before.scope.channels[channel].get(key)!=after.scope.channels[channel].get(key) and after.scope.channels[channel].get(key)==action.get("value")
			return before.scope.get(key)!=after.scope.get(key) and after.scope.get(key)==action.get("value")
		"resistor":return index>=0 and index<2 and before.resistance[index]!=after.resistance[index] and after.resistance[index]==action.get("value")
		"wire":return after.get("wires",[]).size()>before.get("wires",[]).size() and [action.get("a"),action.get("b")] in after.wires
		"plug":
			var earlier := {}
			for cable in before.get("cables",[]):earlier[int(cable.id)]=cable
			for cable in after.get("cables",[]):
				var old: Dictionary=earlier.get(int(cable.id),{})
				if str(action.get("port","")) in [str(cable.a),str(cable.b)] and str(action.get("port","")) not in [str(old.get("a","")),str(old.get("b",""))] and (int(cable.get("owner",0))==lesson.peer_id or int(cable.get("creator",0))==lesson.peer_id):return true
			return false
		"switch":
			var kind := str(action.get("kind",""))
			return index>=0 and index<9 and before.switches[kind][index]!=after.switches[kind][index]
		"voltage":return before.get("level")!=after.get("level")
		"dyn_load":return before.get("dyn_load")!=after.get("dyn_load")
		"dyn_measure":return before.get("dyn_measure")!=after.get("dyn_measure")
		"igbt_damping":return before.get("igbt_damping")!=after.get("igbt_damping")
		"check":return before.get("checked")!=after.get("checked") and after.get("checked",false)
		"drawer":return before.get("drawer_open")!=after.get("drawer_open")
		"pickup":return after.get("cables",[]).size()>before.get("cables",[]).size()
	return false

func _snapshot() -> Dictionary:
	if lesson.lab_id=="dc_lab":return game.dc_lab.states[lesson.bench_index].duplicate(true)
	return game.station_snapshots[lesson.bench_index].duplicate(true)

func _process(_delta: float) -> void:
	if not pending.is_empty():accepted_snapshot(str(pending.lab_id),int(pending.bench_index),_snapshot())
	elif lesson.active:
		var current := lesson.view()
		if current.active and current.step.check.has("state") and not current.step.check.has("op"):
			if lesson.observe({"peer_id":lesson.peer_id,"lab_id":lesson.lab_id,"bench_index":lesson.bench_index},_snapshot()) and panel.visible:_detail()
	if not lesson.active or panel.visible:cue.hide();return
	var view := lesson.view();var target: Variant=null
	if lesson.lab_id=="ac_lab":
		var positions: Dictionary=_ac_positions()
		target=Targets.world_point("ac_lab",str(view.step.cue),positions,null)
	else:
		var fixture: Node=game.dc_lab.instrument_fixtures[lesson.bench_index]
		target=Targets.world_point("dc_lab",str(view.step.cue),{},fixture)
	if not target is Vector3:cue.hide();return
	var projection := CueProjection.cue(view,game.camera,target,get_viewport().get_visible_rect().size)
	cue.visible=bool(projection.get("visible",false))
	if cue.visible:
		cue.position=projection.position+Vector2(14,-22)
		cue_text.text=projection.label+"  ·  F6: steps  ·  Esc: exit"

func _ac_positions() -> Dictionary:
	var equipment: Node=game if lesson.bench_index==0 else game.stations[lesson.bench_index-1].equipment
	var result := {}
	for id in equipment.terminal_bodies:result[id]=equipment.terminal_bodies[id].global_position
	for id in equipment.control_bodies:result[id]=equipment.control_bodies[id].global_position
	for id in equipment.switch_meshes:result[id]=equipment.switch_meshes[id].handle.global_position
	if lesson.bench_index==0:result.storage=game.drawer.global_position
	else:result.storage=game.stations[lesson.bench_index-1].drawer.global_position
	return result
