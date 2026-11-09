extends RefCounted
const Model=preload("res://scripts/breadboard_model.gd")
const Dorm=preload("res://scripts/campus/dorms/authority/persistent_dorm.gd")
var host: Node
var workspace: Control
var selection: RefCounted
var projects: Node
var physical := false
var accepted_history: Array=[]
var accepted_future: Array=[]

func mount(owner_ui: Node) -> Control:
	host=owner_ui
	var kit: Dictionary={} if host.designing else host.profile.data.kits[host.profile.data.equipped]
	if not host.designing and host.bench in range(host.game.dc_lab.states.size()):
		var state: Dictionary = host.game.dc_lab.states[host.bench]
		var placed_board: Dictionary = state.get("board",{})
		physical = int(state.get("board_owner",0)) == host.multiplayer.get_unique_id() and not str(placed_board.get("authority_kit_id","")).is_empty() and not placed_board.get("standalone",false)
	var board: Dictionary
	if host.designing:board=_project_board(host.profile.data.get("circuit_draft",Model.empty()))
	elif physical:board=host.game.dc_lab.states[host.bench].board.duplicate(true)
	else:board=kit.board.duplicate(true)
	if not host.designing and not physical:board.definitions=host.profile.data.get("blueprints",{}).duplicate(true)
	# Reuse the same inventory binding service as the existing picker.
	selection=preload("res://scripts/electronics/inventory_value_search/selection.gd").new()
	workspace=preload("res://scripts/electronics/circuit_workspace/workspace.gd").new()
	host.body.add_child(workspace)
	var stock: Dictionary = {} if host.designing else kit.items
	var catalog: Dictionary = Model.catalog(board)
	if physical:
		var actual_kit: String = str(board.get("authority_kit_id",host.profile.data.equipped))
		stock = host.profile.data.kits.get(actual_kit,{}).get("items",{})
		var kit_catalog := {}
		for id in stock:
			if catalog.has(id) and not Model.Debug.entries().has(id):kit_catalog[id]=catalog[id]
		catalog=kit_catalog
	if host.designing:
		catalog.merge(Model.Debug.entries())
		projects = preload("res://scripts/electronics/circuit_workspace/projects.gd").new()
		workspace.add_child(projects)
		workspace.configure_maker(board, {"new":projects.new_project,"open":projects.open_projects,
			"save":projects.save_project,"close":func():projects._guard(host.close)}, catalog, stock, true)
		projects.setup(workspace, host.screen, str(host.game.characters.selected), install_project)
	elif physical:
		workspace.configure_maker(board, {"close":host.close}, catalog, stock, false, true)
	else:
		workspace.configure(kit.board,{"save":func():host.profile.save(),"deploy":host.deploy,"recall":recall,"carry":carry,"close":host.close})
	host.canvas=workspace.canvas
	host.canvas.live_manual_inputs=physical
	host.wire_io_canvas(host.canvas)
	workspace.design_changed.connect(accept_candidate)
	workspace.component_selected.connect(func(_type):selection.selected_type="";selection.selected_instance="")
	var panels=preload("res://scripts/electronics/contextual_panels/panel_host.gd").new()
	var panel_parent: Control = workspace.sidebar if workspace.maker else workspace.canvas
	panel_parent.add_child(panels)
	panels.configure(workspace,{"profile":{} if host.designing else host.profile.data,"catalog":catalog,"limits":{} if host.designing else stock,"creative":host.designing or (host.creative and not physical),"analyzer_allowed":host.creative or host.designing or host.profile.data.get("analyzer",false)},{"record_instance":record_instance,"validate_property":validate_property,"apply_property":apply_property,"validate_port":validate_port,"apply_port":apply_port,"open_projects":func():host.open("kits",host.bench)})
	workspace.set_meta("panels",panels)
	if physical:
		panels.picker.lab_lead_chosen.connect(func(port): workspace._choose_mode("place");host.canvas.selected_lab_lead=port)
		host.canvas.lab_lead_placed.connect(func(port,hole):host.game.dc_lab.request(host.bench,{"op":"kit_lead","port":port,"hole":hole}))
		host.canvas.lab_lead_disconnected.connect(func(port):host.game.dc_lab._interact_port(host.bench,port,true))
		refresh_lab_leads()
	if not host.designing and host.board_view.has(host.profile.data.equipped):
		var saved: Dictionary=host.board_view[host.profile.data.equipped]
		if saved.get("manual", false):
			host.canvas.zoom=saved.zoom;host.canvas.pan=saved.pan;host.canvas.fitted=true;host.canvas.manual_view=true;host.canvas.last_rows=int(kit.board.rows)
	return workspace

func refresh_lab_leads() -> void:
	var lab = host.game.dc_lab
	var state: Dictionary=lab.states[host.bench]
	var leads: Dictionary=lab.kit_leads(host.bench)
	host.canvas.attached_resize_ports = leads.keys()
	if lab.picked_station == host.bench and lab.lead_color >= 0:
		host.canvas.attached_resize_ports.append(lab.picked_port)
	var ports: Array=state.get("board",{}).get("ports",[])
	if host.canvas.board.ports!=ports and ports.size()==4:
		host.canvas.board.ports=ports.duplicate()
		host.canvas.queue_redraw()
	if host.canvas.lab_leads!=leads:
		host.canvas.lab_leads=leads
		workspace.get_meta("panels").picker.set_lab_leads(leads)
		host.canvas.queue_redraw()

func _project_board(saved: Dictionary) -> Dictionary:
	var board: Dictionary = preload("res://scripts/electronics/ic_pcb_editor/upgrade.gd").resolve_board(host.profile.data,saved)
	board.erase("authority_kit_id")
	board.erase("instance_ids")
	return board

func install_project(board: Dictionary) -> String:
	board = _project_board(board)
	var error := Model.validate(board,{},true)
	if not error.is_empty():return error
	if not _save_draft(board):
		return "Could not restore the working circuit."
	host.canvas.board = board
	workspace.sync_board_options()
	refresh_maker_catalog()
	host.canvas.history.clear()
	host.canvas.future.clear()
	accepted_history.clear()
	accepted_future.clear()
	workspace._choose_mode("select")
	if workspace.has_meta("panels"):workspace.get_meta("panels").picker.set_board(board)
	host.canvas.fit_board()
	return ""

func _save_draft(board: Dictionary) -> bool:
	var data: Dictionary=host.profile.data
	var previous: Variant=data.get("circuit_draft")
	data.circuit_draft=board.duplicate(true)
	if host.profile.save()==OK:return true
	if previous==null:data.erase("circuit_draft")
	else:data.circuit_draft=previous
	return false

func _stock() -> Dictionary:
	if host.designing:return {}
	var id := str(host.canvas.board.get("authority_kit_id",host.profile.data.equipped)) if physical else str(host.profile.data.equipped)
	return host.profile.data.kits[id].items

func refresh_maker_catalog() -> void:
	var board: Dictionary = workspace.canvas.board
	var definitions: Dictionary = board.get("definitions",{})
	definitions.merge(host.profile.data.get("blueprints",{}),true)
	board.definitions = definitions
	var catalog := Model.catalog(board)
	catalog.merge(Model.Debug.entries())
	workspace.canvas.inventory_catalog = catalog
	if workspace.has_meta("panels"):
		var panels: Control = workspace.get_meta("panels")
		panels.context.catalog = catalog
		panels.picker.configure({},catalog,{},true)

func accept_candidate(candidate: Dictionary) -> Dictionary:
	var kit_id := ""
	var kit := {}
	var previous: Dictionary
	if host.designing:
		previous=_project_board(host.profile.data.get("circuit_draft",Model.empty()))
	else:
		kit_id=str(candidate.get("authority_kit_id",host.profile.data.equipped)) if physical else str(host.profile.data.equipped)
		kit=host.profile.data.kits[kit_id]
		previous=kit.board
	var error: String
	if host.designing:
		candidate.erase("instance_ids")
		error=Model.validate(candidate,{},true)
	else:
		error=selection.bind_new_parts(candidate,previous)
	if error=="" and not host.designing:
		var claimed := Dorm.packed_instance_ids(host.profile.data,kit_id)
		var previous_instances: Array = kit.board.get("instance_ids",{}).values()
		for instance in candidate.get("instance_ids",{}).values():
			if instance in claimed and instance not in previous_instances:
				error="That component is already assigned to another kit."
				break
	if error=="" and not host.designing:error=Model.validate(candidate,kit.items if physical else _stock(),host.creative and not physical)
	if physical and error.is_empty():
		for lead in host.canvas.lab_leads.values():
			var hole := str(lead.get("hole",""))
			if hole.is_empty():continue
			for part in candidate.parts:
				if hole in Model.pins(part):
					error="That hole already has a lab lead."
					break
			if not error.is_empty():break
	if error!="":
		host.canvas.history=accepted_history.duplicate(true);host.canvas.future=accepted_future.duplicate(true)
		host.canvas.board=previous.duplicate(true);host.canvas.queue_redraw();workspace.notify(error);return {"ok":false,"error":error}
	if not host.designing:kit.board=candidate.duplicate(true)
	var saved: bool=_save_draft(candidate) if host.designing else host.profile.save()==OK
	if not saved:
		host.canvas.history=accepted_history.duplicate(true);host.canvas.future=accepted_future.duplicate(true)
		if not host.designing:kit.board=previous
		host.canvas.board=previous.duplicate(true);workspace.notify("Save failed · edit reverted");host.canvas.queue_redraw();return {"ok":false,"error":"Save failed"}
	host.canvas.board=candidate.duplicate(true);host.canvas.queue_redraw()
	host.canvas.capture.samples.clear()
	if is_instance_valid(projects): projects.mark_dirty()
	else: workspace.notify("Editing · saved")
	accepted_history=host.canvas.history.duplicate(true);accepted_future=host.canvas.future.duplicate(true)
	if physical:
		host.game.electronics_trade.authority.request_world(host.bench,{"op":"board","design":candidate,"edit_placed_kit":true})
	elif not host.designing and host.bench>=0 and host.game.dc_lab.states[host.bench].get("board_owner",0)==host.multiplayer.get_unique_id():host.deploy()
	return {"ok":true}

func record_instance(type_id: String, instance_id: String) -> void:
	if host.designing:return
	var catalog: Dictionary=host.profile.catalog()
	var family: String=str(catalog.get(type_id,{}).get("kind",""))
	var reserved := {}
	if not host.designing:
		var id := str(host.canvas.board.get("authority_kit_id",host.profile.data.equipped)) if physical else str(host.profile.data.equipped)
		reserved.instance_ids = Dorm.packed_instance_ids(host.profile.data,id)
	var result: Dictionary=preload("res://scripts/electronics/inventory_value_search/query.gd").search_owned(host.profile.data,catalog,family,"",reserved,_stock())
	selection.refresh(result.rows)
	if not selection.choose(type_id,instance_id):workspace.notify("Selected component is no longer available")

func validate_port(index: int, raw: String, rows: int) -> Dictionary:
	var hole:=raw.strip_edges().to_upper()
	return {"ok":index>=0 and index<4 and Model.node(hole,rows)!="","value":hole,"error":"Unknown board hole"}

func apply_port(index: int, hole: String) -> Dictionary:
	if not validate_port(index,hole,int(host.canvas.board.rows)).ok:return {"ok":false,"error":"Unknown board hole"}
	var candidate: Dictionary=host.canvas.board.duplicate(true);candidate.ports[index]=hole
	return accept_candidate(candidate)

func validate_property(part: Dictionary, key: String, raw: String) -> Dictionary:
	if str(part.type) in [Model.Debug.SOURCE,Model.Debug.METER]:
		return Model.Debug.parse_field(key,raw)
	var values=preload("res://scripts/electronics/component_values/values.gd")
	var catalog: Dictionary=host.canvas.inventory_catalog if host.designing else host.profile.catalog()
	var resolved: Dictionary=values.resolve(str(part.type),catalog)
	if not resolved.ok:return resolved
	var settings: Dictionary={}
	for field in values.fields(resolved.entry):settings[field]=resolved.entry[field]
	settings[key]=raw
	var checked: Dictionary=values.configure(resolved.base_id,settings,catalog)
	if not checked.ok:return checked
	return {"ok":true,"value":checked.id}

func apply_property(payload: Dictionary) -> Dictionary:
	var candidate: Dictionary=host.canvas.board.duplicate(true)
	for part in candidate.parts:
		if str(part.id)==str(payload.id):
			if str(part.type) in [Model.Debug.SOURCE,Model.Debug.METER]:
				if not part.has("debug"):part.debug={}
				part.debug[str(payload.key)]=payload.value
			else:
				part.type=str(payload.value)
			if candidate.has("instance_ids"):candidate.instance_ids.erase(str(part.id))
			var error: String=Model.validate(candidate,_stock(),host.designing or host.creative)
			if error!="":return {"ok":false,"error":error}
			host.canvas.commit();host.canvas.board=candidate
			var result := accept_candidate(candidate)
			if result.ok: host.canvas.refresh_selection()
			return result
	return {"ok":false,"error":"Component no longer exists"}

func recall() -> void:
	if host.bench>=0:host.game.dc_lab.request(host.bench,{"op":"recall"})

func carry() -> void:
	if host.bench>=0:
		host.game.dc_lab.request(host.bench,{"op":"carry_board"});host.close()
