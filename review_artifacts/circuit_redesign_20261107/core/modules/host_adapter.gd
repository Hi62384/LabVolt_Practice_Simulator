extends RefCounted
const Model=preload("res://scripts/breadboard_model.gd")
var host: Node
var workspace: Control
var selection: RefCounted
var accepted_history: Array=[]
var accepted_future: Array=[]

func mount(owner_ui: Node) -> Control:
	host=owner_ui
	var kit: Dictionary=host.profile.data.kits[host.profile.data.equipped]
	kit.board.definitions=host.profile.data.get("blueprints",{}).duplicate(true)
	# Reuse the same inventory binding service as the existing picker.
	selection=preload("res://scripts/electronics/inventory_value_search/selection.gd").new()
	workspace=preload("res://scripts/electronics/circuit_workspace/workspace.gd").new()
	host.body.add_child(workspace)
	workspace.configure(kit.board,{"save":func():host.profile.save(),"deploy":host.deploy,"recall":recall,"carry":carry,"close":host.close})
	host.canvas=workspace.canvas;host.wire_io_canvas(host.canvas)
	workspace.design_changed.connect(accept_candidate)
	workspace.component_selected.connect(func(_type):selection.selected_type="";selection.selected_instance="")
	var panels=preload("res://scripts/electronics/contextual_panels/panel_host.gd").new()
	workspace.canvas.add_child(panels)
	panels.configure(workspace,{"profile":host.profile.data,"catalog":Model.catalog(kit.board),"limits":kit.items,"creative":host.creative or host.designing,"analyzer_allowed":host.creative or host.designing or host.profile.data.get("analyzer",false)},{"record_instance":record_instance,"validate_property":validate_property,"apply_property":apply_property,"validate_port":validate_port,"apply_port":apply_port,"open_projects":func():host.open("kits",host.bench)})
	workspace.set_meta("panels",panels)
	if host.board_view.has(host.profile.data.equipped):
		var saved: Dictionary=host.board_view[host.profile.data.equipped]
		host.canvas.zoom=saved.zoom;host.canvas.pan=saved.pan;host.canvas.fitted=true;host.canvas.last_rows=int(kit.board.rows)
	return workspace

func accept_candidate(candidate: Dictionary) -> Dictionary:
	var kit: Dictionary=host.profile.data.kits[host.profile.data.equipped]
	var error: String=selection.bind_new_parts(candidate,kit.board)
	if error=="":error=Model.validate(candidate,kit.items,host.creative or host.designing)
	if error!="":
		host.canvas.history=accepted_history.duplicate(true);host.canvas.future=accepted_future.duplicate(true)
		host.canvas.board=kit.board.duplicate(true);host.canvas.queue_redraw();workspace.state.text=error;return {"ok":false,"error":error}
	var previous: Dictionary=kit.board.duplicate(true)
	kit.board=candidate.duplicate(true)
	if host.profile.save()!=OK:
		host.canvas.history=accepted_history.duplicate(true);host.canvas.future=accepted_future.duplicate(true)
		kit.board=previous;host.canvas.board=previous.duplicate(true);workspace.state.text="Save failed · edit reverted";host.canvas.queue_redraw();return {"ok":false,"error":"Save failed"}
	host.canvas.board=candidate.duplicate(true);host.canvas.queue_redraw()
	host.canvas.capture.samples.clear();workspace.state.text="Editing · saved"
	accepted_history=host.canvas.history.duplicate(true);accepted_future=host.canvas.future.duplicate(true)
	if not host.designing and host.bench>=0 and host.game.dc_lab.states[host.bench].get("board_owner",0)==host.multiplayer.get_unique_id():host.deploy()
	return {"ok":true}

func record_instance(type_id: String, instance_id: String) -> void:
	var catalog: Dictionary=host.profile.catalog()
	var family: String=str(catalog.get(type_id,{}).get("kind",""))
	var result: Dictionary=preload("res://scripts/electronics/inventory_value_search/query.gd").search_owned(host.profile.data,catalog,family,"",{},host.profile.data.kits[host.profile.data.equipped].items)
	selection.refresh(result.rows)
	if not selection.choose(type_id,instance_id):workspace.state.text="Selected component is no longer available"

func validate_port(index: int, raw: String, rows: int) -> Dictionary:
	var hole:=raw.strip_edges().to_upper()
	return {"ok":index>=0 and index<4 and Model.node(hole,rows)!="","value":hole,"error":"Unknown board hole"}

func apply_port(index: int, hole: String) -> Dictionary:
	if not validate_port(index,hole,int(host.canvas.board.rows)).ok:return {"ok":false,"error":"Unknown board hole"}
	var candidate: Dictionary=host.canvas.board.duplicate(true);candidate.ports[index]=hole
	return accept_candidate(candidate)

func validate_property(part: Dictionary, key: String, raw: String) -> Dictionary:
	var values=preload("res://scripts/electronics/component_values/values.gd")
	var catalog: Dictionary=host.profile.catalog()
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
			part.type=str(payload.value)
			if candidate.has("instance_ids"):candidate.instance_ids.erase(str(part.id))
			var error: String=Model.validate(candidate,host.profile.data.kits[host.profile.data.equipped].items,host.creative or host.designing)
			if error!="":return {"ok":false,"error":error}
			host.canvas.commit();host.canvas.board=candidate
			return accept_candidate(candidate)
	return {"ok":false,"error":"Component no longer exists"}

func recall() -> void:
	if host.bench>=0:host.game.dc_lab.request(host.bench,{"op":"recall"})

func carry() -> void:
	if host.bench>=0:
		host.game.dc_lab.request(host.bench,{"op":"carry_board"});host.close()
