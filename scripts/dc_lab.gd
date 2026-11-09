extends Node3D
const Station = preload("res://scripts/dc_station.gd")
const FIXED_BENCHES := 3
const AC_OFFSET := 32
const BENCH_TOP_SIZE := Vector3(4.8,.12,1.28)
const BENCH_TOP_OFFSET := Vector3(0,.82,-.16)
var game: Node
var campus_offset := Vector3.ZERO
var campus_readouts=preload("res://scripts/campus/performance/readout_adapter.gd").new()
var benches: Array=[]
var states: Array=[]
var displays: Array=[]
var instrument_fixtures: Array=[]
var physical_boards: Array=[]
const Coupling = preload("res://scripts/dc_coupling.gd")
const CableBinding = preload("res://scripts/campus/dc_lab/bindings/cable_binding.gd")
const CableMesh = preload("res://scripts/cable_mesh.gd")
var local_plug_layers := {}
var ports: Array=[]
var wire_roots: Array=[]
var drawn_wires := [{}, {}, {}]
var ui: CanvasLayer
var accumulator := 0.0
var inventory_clock := 0.0
var broadcast_clock := 0.0
var rate_limits := {}
var picked_port := ""
var picked_station := -1
var lead_color := -1
var drawer_views: Array[Node3D] = []
var drawer_open := [false, false, false]
var carried_leads := {}
var stowed_leads := {}
var local_stowed_leads := {}
var carried_lead_stations := {}
var hotbar_lead_pending := false
var held_visual: Node3D
var held_visual_clock := 0.0
var loose_visual_color := -1
var held_input := {}
var held_io := {}
var io_guard=preload("res://scripts/io_input_guard.gd").new()
var io_request_serial := 0
var io_pending := {}
var native_transfer=preload("res://scripts/native_program_transfer.gd").new()
var native_host=preload("res://scripts/native_circuit_host.gd").new()
var input_holders := {}
var peer_fields := {}
var bench_interest: Node
var external_links: Array=[]
var ac_bridges: Array=[]
var pending_endpoints := {}
var external_root: Node3D
var external_signature := ""
var benches_ready := false
var saved_departing_pcbs := {}

func build(owner_game: Node) -> void:
	game=owner_game
	external_root=Node3D.new();add_child(external_root)
	for i in range(3):
		var station = Station.new();station.restore_scope(preload("res://scripts/dc_scope/settings_store.gd").restore(i) if multiplayer.is_server() else {});benches.append(station);states.append(station.snapshot())
		build_bench(i)
		var physical=preload("res://scripts/physical_breadboard.gd").new();add_child(physical);physical.build(game,i);physical_boards.append(physical)
	benches_ready=instrument_fixtures.size()==benches.size() and drawer_views.size()==benches.size() and physical_boards.size()==benches.size()
	if not benches_ready:push_error("DC laboratory setup did not create all bench fixtures.")
	for state in game.session.labs:ac_bridges.append(preload("res://scripts/ac_supply_bridge.gd").new(state))
	ui=preload("res://scripts/dc_ui.gd").new();add_child(ui);ui.build(self)
	game.session.restarted.connect(func():
		native_host.close();native_transfer.uploads.clear();native_transfer.began.clear();io_pending.clear();io_guard.leases.clear()
		ac_bridges.clear()
		for state in game.session.labs:ac_bridges.append(preload("res://scripts/ac_supply_bridge.gd").new(state))
		benches.clear();states.clear();input_holders.clear();held_input.clear();peer_fields.clear();external_links.clear();pending_endpoints.clear()
		carried_leads.clear()
		stowed_leads.clear()
		local_stowed_leads.clear()
		carried_lead_stations.clear()
		saved_departing_pcbs.clear()
		hotbar_lead_pending = false
		drawer_open = [false, false, false]
		lead_color = -1
		picked_port = ""
		for i in physical_boards.size():
			var station=Station.new()
			station.portable_slot=i>=FIXED_BENCHES
			if station.portable_slot:drawer_open.append(false)
			elif multiplayer.is_server():station.restore_scope(preload("res://scripts/dc_scope/settings_store.gd").restore(i))
			benches.append(station);states.append(station.snapshot());drawn_wires[i]={}
		if ui.active:ui.close()
	)
	game.session.roster_changed.connect(func():
		if multiplayer.is_server():
			for peer in (carried_leads.keys() + stowed_leads.keys()):
				if not game.session.roster.has(peer):
					carried_leads.erase(peer)
					carried_lead_stations.erase(peer)
					stowed_leads.erase(peer)
					pending_endpoints.erase(peer)
			_recall_departed_boards()
			for key in input_holders.keys():
				var holder: Dictionary=input_holders[key]
				if not game.session.roster.has(holder.peer):
					benches[holder.index].apply({"op":"input","id":holder.id,"hold":true,"pressed":false});input_holders.erase(key)
			broadcast()
	)

	bench_interest=preload("res://scripts/campus/performance/dc_interest_bridge.gd").new()
	bench_interest.name="BenchInterest"
	add_child(bench_interest)
	bench_interest.bind_dc(self)

func ensure_portable_slot(index: int) -> void:
	while benches.size()<=index and benches.size()<AC_OFFSET:
		var slot := benches.size()
		var station := Station.new()
		station.portable_slot=true
		benches.append(station)
		states.append(station.snapshot())
		drawer_open.append(false)
		drawn_wires.append({})
		ports.append({})
		var wires_node := Node3D.new()
		add_child(wires_node)
		wire_roots.append(wires_node)
		var physical=preload("res://scripts/physical_breadboard.gd").new()
		add_child(physical);physical.build(game,slot);physical_boards.append(physical)

func _portable_slot() -> int:
	for index in range(FIXED_BENCHES,benches.size()):
		if benches[index].board.is_empty():return index
	if benches.size()>=AC_OFFSET:return -1
	var index := benches.size()
	ensure_portable_slot(index)
	return index

func _solver_index(index: int) -> int:
	return benches.size()+index-AC_OFFSET if index>=AC_OFFSET else index

func _link_access(peer: int,index: int) -> bool:
	if index>=AC_OFFSET:return game.school.equipment_access(peer,index-AC_OFFSET,"ELM253")
	if index<FIXED_BENCHES:return game.school.equipment_access(peer,index,"ETY155")
	return index in range(benches.size())

func bench_position(index: int) -> Vector3:
	return Vector3((index-1)*6,0,8.8)+campus_offset

func board_home(index: int) -> Vector3:
	return bench_position(index)+Vector3(0,.895,-.28)

func bench_surface_contains(point: Vector3) -> bool:
	for index in 3:
		var delta := point-(bench_position(index)+Vector3(0,.895,-BENCH_TOP_OFFSET.z))
		if absf(delta.x)<2.25 and absf(delta.z)<BENCH_TOP_SIZE.z*.5 and absf(delta.y)<.05:
			return true
	return false

func build_bench(index: int) -> void:
	var origin := Node3D.new();origin.position=bench_position(index);origin.rotation.y=PI;add_child(origin)
	game._box(origin,BENCH_TOP_OFFSET,BENCH_TOP_SIZE,Color("b9a17b"))
	var support_size := Vector3(.12,.8,1.04)
	for x in [-2.05,2.05]:game._box(origin,Vector3(x,.4,BENCH_TOP_OFFSET.z),support_size,Color("284e57"))
	var table := StaticBody3D.new();origin.add_child(table);table.position=BENCH_TOP_OFFSET
	var shape := CollisionShape3D.new();var box := BoxShape3D.new();box.size=BENCH_TOP_SIZE;shape.shape=box;table.add_child(shape)
	var support_shape := BoxShape3D.new()
	support_shape.size=support_size
	for x in [-2.05,2.05]:
		var support := CollisionShape3D.new()
		support.position=Vector3(x,-.42,0)
		support.shape=support_shape
		table.add_child(support)
	table.set_meta("role","table");table.set_meta("label","DC work surface")
	game.cable_obstacles.append(AABB(table.global_position-BENCH_TOP_SIZE*.5,BENCH_TOP_SIZE))
	for x in [-2.05,2.05]:game.cable_obstacles.append(AABB(origin.to_global(Vector3(x,.4,BENCH_TOP_OFFSET.z))-support_size*.5,support_size))
	var physical := preload("res://assets/campus/dc_lab/physical_models/fixture.gd").new()
	origin.add_child(physical)
	physical.build(index)
	var fixture := preload("res://scripts/campus/dc_lab/bindings/physical_binding.gd").new()
	origin.add_child(fixture)
	fixture.bind(self,index,physical)
	instrument_fixtures.append(fixture)
	var display := Label3D.new()
	origin.add_child(display)
	display.visible=false
	displays.append(display)
	ports.append(fixture.port_positions())
	var wires_node := Node3D.new();add_child(wires_node);wire_roots.append(wires_node)
	var drawer := preload("res://scripts/cable_drawer.gd").new()
	origin.add_child(drawer)
	drawer.build(game)
	drawer.position = Vector3(0,.40,-.03)
	drawer.front.set_meta("dc_station", index)
	for bag in drawer.bags:bag.set_meta("dc_station", index)
	drawer_views.append(drawer)

func held_board(peer: int=-1) -> int:
	if peer<0:peer=multiplayer.get_unique_id()
	for i in states.size():
		if states[i].get("board_owner",0)==peer and states[i].get("board_held",false):return i
	return -1
func scroll_instrument(target: Node,reverse: bool,shift := false) -> bool:
	if not is_instance_valid(target):return false
	var input_type := str(target.get_meta("input_type",""))
	if target.get_meta("role","")=="dc_input" and input_type in ["battery_adjustable","battery_generator_adjustable"]:
		request(int(target.get_meta("dc_station")),{"op":"input","id":str(target.get_meta("part_id")),"source_adjust":"frequency" if shift and input_type=="battery_generator_adjustable" else "voltage","reverse":reverse})
		return true
	if target.get_meta("role","")=="dc_input" and target.get_meta("input_type","") in ["pot10k","variable_cap","variable_inductor","photodiode","solar_panel"]:
		return interact(target,reverse)
	if not target.get_meta("dc_knob",false):return false
	return interact(target,reverse)

var preview_board_slot := -1
var breadboard_cable_bounds: Array[AABB] = []

func _lead_board_slot(target: Node) -> int:
	if not is_instance_valid(target) or target.get_meta("role","")!="dc_board":return -1
	var index := int(target.get_meta("dc_station",-1))
	if index not in range(states.size()) or index not in range(physical_boards.size()):return -1
	var board: Dictionary=states[index].get("board",{})
	if board.is_empty():return -1
	if lead_color<0 and _native_held_lead(multiplayer.get_unique_id()).is_empty():return -1
	return index

func _aimed_board_hole(target: Node,index: int) -> String:
	var hit := _io_hit(target)
	if hit.is_empty():return ""
	var board = physical_boards[index]
	return board.pcb_port_at_world(hit.position) if board.standalone_pcb else board.hole_at_world(hit.position)

func preview_lead_hole(target: Node) -> String:
	var index := _lead_board_slot(target)
	if preview_board_slot!=index and preview_board_slot in range(physical_boards.size()):
		physical_boards[preview_board_slot].show_lead_hole("")
	preview_board_slot=index
	if index<0:return ""
	var hole := _aimed_board_hole(target,index)
	physical_boards[index].show_lead_hole(hole)
	return hole

func attach_held_lead_to_board(target: Node) -> bool:
	var index := _lead_board_slot(target)
	if index<0:return false
	var port := "pending" if lead_color>=0 else "pending_ac"
	var hole := _aimed_board_hole(target,index)
	if physical_boards[index].standalone_pcb:
		if hole.is_empty():feedback("Aim at a PCB terminal to attach the lead.")
		else:_interact_port(index,hole,false)
	elif hole.is_empty():feedback("Aim at a breadboard hole to attach the lead.")
	else:request(index,{"op":"kit_lead","port":port,"hole":hole})
	return true

func aimed_breadboard_lead(target: Node, index: int) -> String:
	if index not in range(physical_boards.size()) or physical_boards[index].standalone_pcb:return ""
	var leads := kit_leads(index)
	if leads.is_empty():return ""
	var hole := _aimed_board_hole(target,index)
	if hole.is_empty():return ""
	for port in leads:
		if leads[port].get("hole","")==hole:return str(port)
	return ""

func interact(target: Node,right: bool) -> bool:
	if is_instance_valid(target) and target.get_meta("role","")=="table" and not right and held_board()>=0:
		var hit := get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(game.camera.global_position,game.camera.global_position-game.camera.global_basis.z*3.6,1))
		if not hit.is_empty() and hit.normal.y>.8:request(held_board(),{"op":"place_board","position":hit.position+Vector3(0,.03,0)})
		return true
	if is_instance_valid(target) and target.get_meta("role","")=="socket":
		var index := AC_OFFSET+int(target.get_meta("station",0));var port := str(target.get_meta("id",""))
		if right:
			if _detach_external_end(index,port): return true
		elif lead_color >= 0:
			if picked_port.is_empty():
				picked_port = port
				picked_station = index
				request(index,{"op":"begin_external","port":port,"physical":true})
			else:
				request(index,{"op":"link_external","port":port,"physical":true})
			return true
	if not is_instance_valid(target) or not target.has_meta("dc_station"):return false
	var index := int(target.get_meta("dc_station"))
	if target.get_meta("role") == "drawer":
		if not right:request(index, {"op":"lead_drawer"})
		return true
	if target.get_meta("role") == "rack":
		if not right:pick_lead(index, int(target.get_meta("color", 0)))
		return true
	if target.get_meta("role")=="dc_io":
		var board: Node=target.get_meta("io_board",null);var id := str(target.get_meta("part_id",""))
		if not is_instance_valid(board):return true
		if right:
			if target.get_meta("input_type","")=="io_encoder":board.io_turn(id,-1)
			return true
		var hit := _io_hit(target)
		if not hit.is_empty() and board.io_pointer(id,hit.position,true):held_io={"board":board,"id":id,"button":MOUSE_BUTTON_LEFT}
		return true
	if target.get_meta("role")=="dc_code":
		game.electronics.open("code",index);return true
	if target.get_meta("role")=="dc_input":
		var id := str(target.get_meta("part_id"))
		var type := str(target.get_meta("input_type",""))
		if type in preload("res://scripts/electronics/portable_sources.gd").CONTROLS:
			request(index,{"op":"input","id":id,"source_adjust":"voltage" if type=="battery_adjustable" else "wave","reverse":right})
		elif type=="button":
			if right:return true
			held_input={"index":index,"id":id};request(index,{"op":"input","id":id,"hold":true,"pressed":true})
		else:request(index,{"op":"input","id":id,"reverse":right})
		return true
	if target.get_meta("role")=="dc_board":
		if attach_held_lead_to_board(target):return true
		if right:
			var lead := aimed_breadboard_lead(target,index)
			if not lead.is_empty():return _interact_port(index,lead,true)
		if not right:
			if not game.hotbar.slots.has({}):feedback("Free a hotbar slot before picking up the board.")
			else:request(index,{"op":"carry_board","pickup":true})
		elif int(states[index].get("board_owner",0))==multiplayer.get_unique_id():
			game.electronics.open("physical_pcb" if states[index].get("board",{}).get("standalone",false) else "board",index)
		return true
	if target.get_meta("role")=="dc_instrument_control":
		var physical_action: Dictionary=instrument_fixtures[index].action_for(target,right,states[index])
		if not physical_action.is_empty():request(index,physical_action)
		return true
	if target.get_meta("role")=="dc_panel":
		if not right:ui.open(index)
		return true
	return _interact_port(index,str(target.get_meta("dc_port")),right)

func _interact_port(index: int,port: String,right: bool) -> bool:
	if right:
		if lead_color >= 0:
			if picked_station == index and picked_port == port:
				picked_port = ""
				request(index, {"op":"detach_held_end"})
			return true
		if _detach_external_end(index,port): return true
		for i in range(states[index].wires.size()-1,-1,-1):
			var wire: Array = states[index].wires[i]
			if port not in wire:continue
			if game.school.held(multiplayer.get_unique_id()) != 0 or game.school._holding_cable(multiplayer.get_unique_id()) or game.school._holding_kit(multiplayer.get_unique_id()) or held_board() >= 0:return true
			request(index, {"op":"detach_lead", "port":port})
			break
		return true
	if lead_color < 0:
		request(index,{"op":"attach_native_lead","port":port})
		return true
	if picked_port=="":
		picked_port=port;picked_station=index;request(index,{"op":"begin_external","port":port,"physical":true})
		game.ui.log_message("Click another terminal to attach the other end.")
	else:
		if picked_station!=index:request(index,{"op":"link_external","port":port,"physical":true})
		else:request(index,{"op":"wire","a":picked_port,"b":port,"physical":true})
	return true

func _detach_external_end(index: int, port: String) -> bool:
	if lead_color >= 0:
		if picked_station == index and picked_port == port:
			request(index,{"op":"detach_held_end"})
			picked_port = ""
		return true
	if states.is_empty(): return false
	for link in states[0].get("external_links",[]):
		var other := _other_end(link,index,port)
		if other.is_empty(): continue
		var peer := multiplayer.get_unique_id()
		if _can_hold_lead(peer):
			request(index,{"op":"detach_external","port":port})
		return true
	return false

func _can_hold_lead(peer: int) -> bool:
	return game.school.held(peer) == 0 and not game.school._holding_cable(peer) and not game.school._holding_kit(peer) and held_board(peer) < 0

static func _other_end(link: Dictionary, index: int, port: String) -> Dictionary:
	if link.a.station == index and link.a.port == port: return link.b
	if link.b.station == index and link.b.port == port: return link.a
	return {}

func pick_lead(index: int, color: int) -> void:
	if index not in range(drawer_views.size()):return
	if lead_color >= 0 or game.school.held(multiplayer.get_unique_id()) != 0 or held_board() >= 0:return
	if game.school._holding_cable(multiplayer.get_unique_id()) or game.school._holding_kit(multiplayer.get_unique_id()):return
	if not drawer_views[index].opened:return
	request(index, {"op":"take_lead", "color":color})

func stow_hotbar_lead() -> void:
	if lead_color < 0 or hotbar_lead_pending:return
	hotbar_lead_pending = true
	request(picked_station, {"op":"stow_hotbar_lead"})

func equip_hotbar_lead(index: int, color: int) -> void:
	if lead_color >= 0 or not _can_hold_lead(multiplayer.get_unique_id()):return
	if hotbar_lead_pending or not local_stowed_leads.has(Vector2i(index,color)):return
	hotbar_lead_pending = true
	request(index, {"op":"equip_hotbar_lead","color":color})

@rpc("authority","call_remote","reliable")
func sync_hotbar_lead(stored: Dictionary, station: int, color: int, accepted: bool) -> void:
	hotbar_lead_pending = false
	local_stowed_leads = stored.duplicate()
	if accepted or color<0 or picked_station!=station:
		picked_port = ""
	picked_station = station
	lead_color = color

func _reply_hotbar_lead(peer: int, accepted: bool) -> void:
	var stored: Dictionary = stowed_leads.get(peer,{})
	var station := int(carried_lead_stations.get(peer,-1))
	var color := int(carried_leads.get(peer,-1))
	if peer==1:sync_hotbar_lead(stored,station,color,accepted)
	else:sync_hotbar_lead.rpc_id(peer,stored,station,color,accepted)

@rpc("authority","call_remote","reliable")
func sync_stowed_leads(stored: Dictionary) -> void:
	local_stowed_leads=stored.duplicate()

func publish_stowed_leads(peer: int) -> void:
	var stored: Dictionary=stowed_leads.get(peer,{})
	if peer==multiplayer.get_unique_id():sync_stowed_leads(stored)
	else:sync_stowed_leads.rpc_id(peer,stored)

func return_lead() -> bool:
	if lead_color < 0:return false
	request(picked_station, {"op":"return_lead"})
	picked_port = ""
	lead_color = -1
	return true

func release_input() -> void:
	if held_input.is_empty():return
	request(int(held_input.index),{"op":"input","id":held_input.id,"hold":true,"pressed":false});held_input={}
func request(index: int,action: Dictionary) -> void:
	if action.get("op")=="input" and action.get("command") is Dictionary:
		action=action.duplicate(true);io_request_serial+=1;action.request_id=io_request_serial
		io_pending["%d:%s:%s"%[index,action.get("id",""),action.get("board_epoch",-1)]]=io_request_serial
	if is_instance_valid(game.open_lab_tutorial):game.open_lab_tutorial.record_intent("dc_lab",index,action)
	if multiplayer.is_server():accept(1,index,action)
	else:command.rpc_id(1,index,action)
@rpc("any_peer","call_remote","reliable")
func command(index: int,action: Dictionary) -> void:
	if multiplayer.is_server():accept(multiplayer.get_remote_sender_id(),index,action)
func accept(peer: int,index: int,action: Dictionary) -> void:
	_accept_checked(peer,index,action)
	if index>=0 and index<benches.size() and game.session.roster.has(peer) and action.get("op")=="input" and action.get("command") is Dictionary and var_to_bytes(action).size()<=24000:
		var id := str(action.get("id",""));var epoch := int(action.get("board_epoch",-1));var request_id := int(action.get("request_id",-1))
		var control: Dictionary=benches[index].board.get("io_controls",{}).get(id,{}).duplicate(true)
		var view := str(action.get("view_token","")).left(96)
		if peer==1:io_input_ack(index,id,epoch,request_id,control,view)
		else:io_input_ack.rpc_id(peer,index,id,epoch,request_id,control,view)
@rpc("authority","call_remote","reliable",7)
func io_input_ack(index: int,id: String,epoch: int,request_id: int,control: Dictionary,view := "") -> void:
	if index<0 or index>=states.size() or id.length()>256 or view.length()>96 or var_to_bytes(control).size()>2048:return
	var key := "%d:%s:%s"%[index,id,epoch]
	if int(io_pending.get(key,-2))!=request_id:return
	io_pending.erase(key)
	game.electronics.acknowledge_io_input(index,id,control,epoch,view)
	if int(states[index].get("board_epoch",0))==epoch and physical_boards[index].has_method("acknowledge_io"):physical_boards[index].acknowledge_io(id,control,view)
func _accept_checked(peer: int,index: int,action: Dictionary) -> void:
	if index<0 or (index>=benches.size() and index not in range(AC_OFFSET,AC_OFFSET+ac_bridges.size())) or not game.session.roster.has(peer) or var_to_bytes(action).size()>24000:return
	if action.get("op") in ["counter_checkout", "counter_return"]:
		var error := _counter_pcb(peer, index, action)
		if not error.is_empty():
			if peer == 1: feedback(error)
			else: feedback.rpc_id(peer, error)
		return
	if action.get("op") == "stow_hotbar_lead":
		var accepted: bool = carried_leads.has(peer) and carried_lead_stations.get(peer,-1)==index
		if accepted:
			var stored: Dictionary = stowed_leads.get(peer,{})
			stored[Vector2i(index,int(carried_leads[peer]))] = true
			stowed_leads[peer] = stored
			carried_leads.erase(peer)
			carried_lead_stations.erase(peer)
			pending_endpoints.erase(peer)
		_reply_hotbar_lead(peer,accepted)
		return
	if action.get("op") == "equip_hotbar_lead":
		var color: Variant = action.get("color",-1)
		if not color is int or color not in range(4):
			_reply_hotbar_lead(peer,false)
			return
		var stored: Dictionary = stowed_leads.get(peer,{})
		var key := Vector2i(index,color)
		var accepted: bool = not carried_leads.has(peer) and _can_hold_lead(peer) and stored.erase(key)
		if accepted:
			carried_leads[peer] = color
			carried_lead_stations[peer] = index
		_reply_hotbar_lead(peer,accepted)
		return
	if action.get("op") == "return_lead":
		carried_leads.erase(peer)
		carried_lead_stations.erase(peer)
		pending_endpoints.erase(peer)
		return
	var io_command: bool=action.get("op")=="input" and action.get("command") is Dictionary
	var io_type := io_kind(index,str(action.get("id",""))) if io_command and index<AC_OFFSET else ""
	var io_release: bool = io_command and io_guard.release_command(io_type,action.command)
	var release_only: bool=io_release or (action.get("op")=="input" and action.get("hold",false) and action.get("pressed",true)==false)
	if not release_only and is_instance_valid(game.school) and not _link_access(peer,index):return
	if io_command:
		if index>=AC_OFFSET:return
		io_guard.epochs[index]=benches[index].board_epoch
		if (benches[index].board_stowed or benches[index].board_held) and not io_release:return
		if io_type=="" or io_guard.check(peer,index,action.get("board_epoch"),str(action.get("id","")),io_type,action.command,str(action.get("view_token","")))!="":return
	var now := Time.get_ticks_msec()
	if peer!=1 and now-int(rate_limits.get(peer,0))<5 and not str(action.get("op","")).begins_with("native_") and not io_release and not (action.get("op")=="input" and action.get("hold",false) and action.get("pressed",true)==false):return
	rate_limits[peer]=now
	if index>=AC_OFFSET:
		var op := str(action.get("op",""));var port := str(action.get("port",""))
		if op == "detach_held_end":
			_release_dc_anchor(peer,index)
			return
		if op not in ["begin_external","link_external","unlink_external","detach_external"]:return
		if action.get("physical",false) and not carried_leads.has(peer):return
		var position: Vector3=game.player.position if peer==1 else game.session.poses.get(peer,{}).get("position",Vector3.ZERO)
		var endpoint=game.session.labs[index-AC_OFFSET].positions.get(port)
		if not endpoint is Vector3 or (position+Vector3.UP*1.65).distance_to(endpoint)>3.25:return
		var error := edit_external(peer,index,op,port)
		if error!="":
			if peer==1:feedback(error)
			else:feedback.rpc_id(peer,error)
		broadcast();return

	var position: Vector3=game.player.position if peer==1 else game.session.poses.get(peer,{}).get("position",Vector3.ZERO)
	var station=benches[index]
	var op := str(action.get("op",""))
	if index>=FIXED_BENCHES and op not in ["kit_lead","board","recall","input","firmware_reset","carry_board","place_board","rotate_board","stow_board","native_begin","native_chunk","native_finish","native_control","begin_external","link_external","unlink_external","detach_external","attach_native_lead","detach_held_end","detach_lead","wire","cabinet_board","retrieve_cabinet_board"]:return
	if op=="input" and action.has("board_epoch") and action.board_epoch!=station.board_epoch:return
	if op in ["cabinet_board","retrieve_cabinet_board"]:
		if not is_instance_valid(game.dorm_interactions) or not game.dorm_interactions.is_in_own_room(peer,position):return
		var storing := op=="cabinet_board"
		if storing:
			if station.board_owner!=peer or (not station.board_held and not station.board_stowed):return
			var storage_error := capture_nonvolatile(peer,index)
			if not storage_error.is_empty():
				if peer==1:feedback(storage_error)
				else:feedback.rpc_id(peer,storage_error)
				return
		else:
			if not station.board.is_empty():return
			var profile: Dictionary = game.dorm_interactions._profile(game.dorm_interactions.authenticated_identity(peer))
			var saved: Dictionary = profile.get("dorm",{}).get("stored_board",{}).get("design",{})
			if saved.is_empty() or preload("res://scripts/breadboard_model.gd").validate(saved,{},true)!="":return
			for other in benches:
				if other.board_owner==peer and other.board.get("authority_kit_id","existing_kit")==saved.get("authority_kit_id",""):return
		var transfer: Dictionary = game.electronics_trade.authority.transfer_cabinet_board(peer,index,station.board if storing else {})
		if not transfer.ok:
			if peer==1:feedback(str(transfer.error))
			else:feedback.rpc_id(peer,str(transfer.error))
			return
		if storing:
			remove_board_links(index)
			station.apply({"op":"recall"})
		else:
			station.apply({"op":"board","design":transfer.design})
			station.board_owner=peer
			station.board_stowed=true
		broadcast()
		return
	var input_key := str(index)+":"+str(action.get("id",""))
	var releasing: bool=op=="input" and action.get("hold",false) and action.get("pressed",true)==false
	if op=="input" and not io_command and not releasing and io_kind(index,str(action.get("id",""))).is_empty():return
	if releasing and int(input_holders.get(input_key,{}).get("peer",0))!=peer:return
	if op=="input" and not releasing and input_holders.has(input_key) and int(input_holders[input_key].peer)!=peer:return
	if op=="input" and (station.board_stowed or station.board_held) and station.board_owner!=peer:return
	var origin := Vector3((index-1)*6,0,8)+campus_offset
	var physical_port := str(action.get("port",""))
	if (op in ["begin_external","link_external","detach_external","attach_native_lead","detach_lead"] and Station.board_port(physical_port)) or (op=="wire" and action.get("physical",false)):
		var point: Variant = ports[index].get(str(action.get("b",physical_port)))
		if not point is Vector3 or (position+Vector3.UP*1.65).distance_to(point)>3.25:return
		origin=position
	elif op in ["kit_lead","board","recall","input","firmware_reset","carry_board","place_board","rotate_board","stow_board","native_begin","native_chunk","native_finish","native_control"] and not station.board.is_empty():
		origin=position if (station.board_held or station.board_stowed) and station.board_owner==peer else station.board_position if station.board_position!=Vector3.ZERO else origin
	if position.distance_to(origin)>4 and not releasing and not io_release:return
	if op=="kit_lead":
		var error := _place_kit_lead(peer,index,str(action.get("port","")),str(action.get("hole","")))
		if not error.is_empty():
			if peer==1:feedback(error)
			else:feedback.rpc_id(peer,error)
		broadcast()
		return
	var editing_kit: bool=op=="board" and bool(action.get("edit_placed_kit",false))
	if editing_kit:
		if station.board_owner!=peer or station.board_held or station.board_stowed or station.board.get("standalone",false) or not action.get("design") is Dictionary:return
		if action.design.get("standalone",false):return
		var kit_id := str(station.board.get("authority_kit_id",""))
		var profile: Dictionary=game.electronics_trade.authority.ledger.account(peer).get("profile",{}) if game.session.online else game.electronics.profile.data
		if kit_id.is_empty() or not profile.get("kits",{}).has(kit_id):return
		action=action.duplicate(true)
		action.design.authority_kit_id=kit_id
		var model=preload("res://scripts/breadboard_model.gd")
		var leads := _kit_connected_leads(index,station.wires,external_links,station.lead_colors,station.board.ports)
		var attached_ports := leads.keys()
		for endpoint in pending_endpoints.values():
			if int(endpoint.station) == index:
				attached_ports.append(str(endpoint.port))
		var error: String = model.fit_external_ports(action.design, station.board.ports, attached_ports)
		if error.is_empty():
			error=model.validate(action.design,profile.get("kits",{}).get(kit_id,{}).get("items",{}),false)
		if error.is_empty():
			for lead in leads.values():
				for part in action.design.parts:
					if lead.hole in model.pins(part):
						error="That hole already has a lab lead."
						break
				if not error.is_empty():break
		if not error.is_empty():
			if peer==1:feedback(error)
			else:feedback.rpc_id(peer,error)
			return
	if op in ["native_begin","native_chunk","native_finish","native_control"]:
		var native_error: String=native_transfer.apply(peer,index,action,station)
		if native_error!="":
			if peer==1:feedback(native_error)
			else:feedback.rpc_id(peer,native_error)
		elif op in ["native_finish","native_control"]:broadcast()
		return
	if op == "lead_drawer":
		drawer_open[index] = not drawer_open[index]
		_sync_drawer(index, drawer_open[index])
		if game.session.online:_sync_drawer.rpc(index, drawer_open[index])
		return
	if op == "take_lead":
		var color: Variant = action.get("color", -1)
		if game.school.held(peer) != 0 or game.school._holding_cable(peer) or game.school._holding_kit(peer) or held_board(peer) >= 0:return
		if drawer_open[index] and color is int and color in range(4) and not carried_leads.has(peer):
			_create_loose_lab_lead(peer,color,index)
		return
	if op == "attach_native_lead":
		var port := str(action.get("port",""))
		var point: Variant=ports[index].get(port)
		if not point is Vector3 or (position+Vector3.UP*1.65).distance_to(point)>3.25:return
		var error := _attach_native_lead(peer,index,port)
		if not error.is_empty():
			if peer==1:feedback(error)
			else:feedback.rpc_id(peer,error)
		broadcast()
		return
	if op == "detach_held_end":
		_release_dc_anchor(peer,index)
		return
	if op == "detach_lead":
		var port := str(action.get("port",""))
		var anchor: Variant = ports[index].get(port)
		if not anchor is Vector3 or (position + Vector3.UP * 1.65).distance_to(anchor) > 3.25:return
		if game.school.held(peer) != 0 or game.school._holding_cable(peer) or game.school._holding_kit(peer) or held_board(peer) >= 0:return
		for wire_index in range(station.wires.size()-1,-1,-1):
			var wire: Array = station.wires[wire_index]
			if port not in wire:continue
			var jacket := _lead_jacket(station.lead_colors, wire_index, wire)
			carried_leads[peer] = jacket if jacket in range(4) else 2
			carried_lead_stations[peer] = index
			var remaining_port := str(wire[1] if wire[0] == port else wire[0])
			pending_endpoints[peer] = {"station":index, "port":remaining_port}
			if peer==1:_sync_attached_lead(index,remaining_port,carried_leads[peer])
			else:_sync_attached_lead.rpc_id(peer,index,remaining_port,carried_leads[peer])
			action = {"op":"unwire","index":wire_index}
			op = "unwire"
			break
		if op == "detach_lead":return
	if action.get("physical", false):
		if not carried_leads.has(peer):return
		if op == "wire":
			var endpoint: Dictionary = pending_endpoints.get(peer, {})
			if endpoint.get("station", -1) != index or endpoint.get("port") != action.get("a"):return
			action = action.duplicate()
			action["lead_color"] = carried_leads[peer]
			var point_a: Variant = ports[index].get(str(action.get("a","")))
			var point_b: Variant = ports[index].get(str(action.get("b","")))
			if not point_a is Vector3 or not point_b is Vector3 or (position+Vector3.UP*1.65).distance_to(point_b)>3.25:return
			if point_a.distance_to(point_b)>5.0:
				if peer==1:feedback("This 5 m lead cannot reach.")
				else:feedback.rpc_id(peer,"This 5 m lead cannot reach.")
				return
	if op in ["begin_external","link_external","unlink_external","detach_external"]:
		var error := edit_external(peer,index,op,str(action.get("port","")))
		if error!="":
			if peer==1:feedback(error)
			else:feedback.rpc_id(peer,error)
		broadcast();return
	if op=="carry_board":
		var pickup: bool=action.get("pickup",false)==true
		if pickup and (station.board_held or station.board_stowed):return
		var holding_cable: bool=game.school._holding_cable(peer)
		if pickup and holding_cable:return
		var holding_board: bool=benches.any(func(other):return other!=station and other.board_owner==peer and other.board_held)
		var hands_busy: bool=holding_board or game.school.held(peer)!=0 or holding_cable or game.school._holding_kit(peer)
		if hands_busy:
			if not pickup:return
			op="stow_board"
			action={"op":op}
	if op=="place_board":
		var pos=action.get("position")
		if action.get("ground",false):
			pos=game.school.ground_drop_position(pos,peer)
			if pos==null:return
			action=action.duplicate()
			action.position=pos+Vector3.UP*.037
		elif not pos is Vector3 or not pos.is_finite() or position.distance_to(pos)>3.6 or not game.school._table_position(pos):return
	if str(action.get("op","")) in ["board","recall","firmware_reset","carry_board","place_board","rotate_board","stow_board"] and station.board_owner not in [0,peer]:
		if peer==1:game.ui.log_message("This board belongs to another player.")
		else:feedback.rpc_id(peer,"This board belongs to another player.")
		return
	if action.get("op")=="board":
		for other in benches:
			if not editing_kit and other!=station and other.board_owner==peer:
				if peer==1:game.ui.log_message("Recall your existing breadboard before deploying another.")
				else:feedback.rpc_id(peer,"Recall your existing breadboard before deploying another.")
				return
	if op in ["board","recall","stow_board"]:
		var stock_error := capture_nonvolatile(peer,index)
		if stock_error=="" and op=="board":
			if not action.get("design") is Dictionary:stock_error="Invalid board"
			elif preload("res://scripts/electronics/circuit_workspace/debug_instruments.gd").contains(action.design):
				stock_error="Remove simulation instruments before deploying."
			else:
				action=action.duplicate(true)
				if not game.session.online:stock_error=game.electronics_trade.authority.local_storage_error(action.design,index)
				if stock_error=="":action.design=game.electronics_trade.authority.materialize(peer,action.design,index)
				if game.session.online:stock_error=game.electronics_trade.authority.deployment(peer,index,action.design)
		if stock_error=="" and op=="recall" and game.session.online and not game.electronics_trade.authority.recall(peer,index):stock_error="Host inventory save failed"
		if stock_error!="":
			if peer==1:feedback(stock_error)
			else:feedback.rpc_id(peer,stock_error)
			return
	if io_command and io_release and io_guard.leases.get(str(index)+":"+str(action.id),{}).get("peer",-1)==peer:
		action=action.duplicate(true);action.command.revision=station.board.get("io_controls",{}).get(str(action.id),{}).get("revision",0)
	var academic_before: Array=station.netlist().duplicate(true) if game.school.formal_active() else []
	var message: String=station.apply(action)
	if message.is_empty() and op=="wire" and action.get("physical",false):
		carried_leads.erase(peer)
		carried_lead_stations.erase(peer)
		pending_endpoints.erase(peer)
		if peer==1:_finish_kit_lead()
		else:_finish_kit_lead.rpc_id(peer)
	if message=="" and game.school.activity.get("course_id","")=="ETY155":game.school.observe_equipment_action(peer,index,op,academic_before)
	if message=="" and io_command:io_guard.commit(peer,index,str(action.id),io_type,station.board.get("io_controls",{}).get(str(action.id),{}),str(action.get("view_token","")))
	if message=="" and (op=="recall" or (op=="board" and not editing_kit)):remove_board_links(index)
	if message=="" and op=="input" and action.get("hold",false):
		if releasing:input_holders.erase(input_key)
		else:input_holders[input_key]={"peer":peer,"index":index,"id":str(action.id)}
	if message=="" and action.get("op")=="board":station.board_owner=peer
	if message!="":
		if peer==1:game.ui.log_message(message)
		else:feedback.rpc_id(peer,message)
	if message=="" and op=="scope":
		var scope_save_error := preload("res://scripts/dc_scope/settings_store.gd").persist(index,station.scope)
		if scope_save_error!=OK:game.ui.log_message("Scope settings could not be saved: "+error_string(scope_save_error))
	states[index]=benches[index].snapshot();broadcast()
@rpc("authority","call_remote","reliable")
func feedback(message: String) -> void:
	game.ui.log_message(message)
	if ui.active:ui.notice.text=message

@rpc("authority","call_remote","reliable")
func _sync_drawer(index: int, opened: bool) -> void:
	if index in range(drawer_views.size()):drawer_views[index].sync(opened)
func _process(delta: float) -> void:
	if not benches_ready or not is_instance_valid(game):return
	_update_held_visual(delta)
	var trace: Node=game.get_meta("campus_hitch_trace",null) if game.has_meta("campus_hitch_trace") else null
	var span: int=trace.begin_span("dc_lab_process_total") if is_instance_valid(trace) else -1
	if not held_input.is_empty() and (not game.player.enabled or not (Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) or Input.is_physical_key_pressed(game.player.keys.interact))):release_input()
	if multiplayer.is_server():
		cleanup_io_holds()
		inventory_clock+=delta
		if inventory_clock>=1:
			inventory_clock=0
			var save_error := checkpoint_inventory()
			if save_error!="":game.ui.log_message(save_error)
			_recall_departed_boards()
		var simulation_span: int=trace.begin_span("dc_lab_simulation") if is_instance_valid(trace) else -1
		accumulator=minf(accumulator+delta,.04)
		var steps := mini(80,int(accumulator/.0005))
		var _step := 0
		var simulation_deadline := Time.get_ticks_usec()+4000
		native_host.refresh(benches)
		var coupled_stations: Array=benches+ac_bridges if not external_links.is_empty() else []
		var solver_links: Array=[]
		for link in external_links:
			solver_links.append({"a":{"station":_solver_index(link.a.station),"port":link.a.port},"b":{"station":_solver_index(link.b.station),"port":link.b.port}})
		var coupled_groups := Coupling.groups_for(coupled_stations.size(),solver_links) if not solver_links.is_empty() else []
		while _step<steps and Time.get_ticks_usec()<simulation_deadline:
			if native_host.active:
				var completed: bool=native_host.advance(benches+ac_bridges,solver_links,.0005,false)
				if completed:_step+=1
				continue
			if not solver_links.is_empty():Coupling.step(coupled_stations,solver_links,.0005,coupled_groups)
			else:
				for bench in benches:
					bench.linked=false
					if bench.master or bench.generator.enabled or bench.board_simulating():bench.step(.0005)
					elif _step==0 and not bench.portable_slot:bench.step(maxf(.0005,delta))
			_step+=1
		accumulator-=_step*.0005
		if is_instance_valid(trace):trace.end_span(simulation_span)
		var snapshot_span: int=trace.begin_span("dc_lab_snapshot_ui") if is_instance_valid(trace) else -1
		broadcast_clock+=delta
		if broadcast_clock>=.1:broadcast_clock=0;broadcast()
		if is_instance_valid(trace):trace.end_span(snapshot_span)
	var presentation_span: int=trace.begin_span("dc_lab_presentation") if is_instance_valid(trace) else -1
	var next_bounds: Array[AABB]=[]
	for board in physical_boards:
		var bounds: AABB=board.cable_bounds()
		if bounds.has_volume():next_bounds.append(bounds)
	if next_bounds!=breadboard_cable_bounds:
		breadboard_cable_bounds=next_bounds
		for index in states.size():drawn_wires[index]={}
		external_signature=""
	for index in range(states.size()):
		# Presentation only; host stepping above is unchanged. Out-of-interest
		# clients retain static geometry/last view until reliable full re-entry.
		if not multiplayer.is_server() and is_instance_valid(bench_interest) and bench_interest.has_stream() and not bench_interest.active(index):
			if index<FIXED_BENCHES:campus_readouts.budget.set_relevant(str(index),false)
			physical_boards[index].suspend_presentation()
			continue
		var state: Dictionary=states[index]
		if index<FIXED_BENCHES:drawer_views[index].sync(bool(state.get("drawer_open", false)))
		physical_boards[index].update_state(state)
		for id in ports[index].keys():
			if Station.board_port(id) and not physical_boards[index].external_ports.has(id):
				ports[index].erase(id)
				drawn_wires[index]={}
				external_signature=""
		for id in physical_boards[index].external_ports:
			var point: Vector3=physical_boards[index].to_global(physical_boards[index].external_ports[id])
			if ports[index].get(id)!=point:drawn_wires[index]={};external_signature=""
			ports[index][id]=point
		if index<FIXED_BENCHES:
			var fixture_relevant: bool=instrument_fixtures[index].global_position.distance_squared_to(game.camera.global_position)<=144.0
			var physical_ports: Dictionary=instrument_fixtures[index].port_positions()
			for id in physical_ports:
				if ports[index].get(id)!=physical_ports[id]:drawn_wires[index]={};external_signature=""
				ports[index][id]=physical_ports[id]
			instrument_fixtures[index].observe(state,delta,fixture_relevant)
		var wiring := {"wires":state.wires,"colors":state.get("lead_colors",[])}
		if wiring!=drawn_wires[index]:
			drawn_wires[index]=wiring
			for c in wire_roots[index].get_children():wire_roots[index].remove_child(c);c.queue_free()
			var layers := {}
			for wire_index in state.wires.size():
				var wire: Array = state.wires[wire_index]
				if not ports[index].has(wire[0]) or not ports[index].has(wire[1]):continue
				var a: Vector3=ports[index][wire[0]];var b: Vector3=ports[index][wire[1]]
				var jacket := _lead_jacket(wiring.colors, wire_index, wire)
				var color: Color = game.JACKET_COLORS[jacket] if jacket in range(4) else Color("dc9d5b")
				wire_roots[index].add_child(CableBinding.from_ports(self,index,str(wire[0]),a,index,str(wire[1]),b,color,game.cable_obstacles,layers))
			if local_plug_layers.get(index, {}) != layers:external_signature=""
			local_plug_layers[index]=layers
	campus_readouts.tick(delta,500)
	draw_external_links()
	if is_instance_valid(trace):
		trace.end_span(presentation_span)
		trace.end_span(span)

func _clear_held_visual() -> void:
	if is_instance_valid(held_visual):
		held_visual.get_parent().remove_child(held_visual)
		held_visual.queue_free()
		held_visual = null
	loose_visual_color = -1

func _update_held_visual(delta: float) -> void:
	if lead_color < 0 or not game.player.enabled:
		_clear_held_visual()
		return
	if picked_port.is_empty():
		# Keep the loose coil in camera space so it follows the view every frame.
		var camera: Camera3D=game.camera
		if loose_visual_color != lead_color or not is_instance_valid(held_visual):
			_clear_held_visual()
			held_visual = Node3D.new()
			camera.add_child(held_visual)
			var color: Color=game.JACKET_COLORS[lead_color]
			var coil := MeshInstance3D.new()
			coil.mesh=CableMesh.held_geometry(Vector3.ZERO,Vector3.ZERO,Basis.IDENTITY,false)
			coil.material_override=CableMesh.jacket_material(color)
			held_visual.add_child(coil)
			var grip := game.held_lead_connector(held_visual,color,Vector3.ZERO) as MeshInstance3D
			grip.rotation.x=PI
			loose_visual_color=lead_color
		var viewport := camera.get_viewport().get_visible_rect()
		var screen_grip := viewport.position+viewport.size*Vector2(.79,.72)
		held_visual.position=camera.to_local(camera.project_position(screen_grip,.65))
		held_visual_clock=.07
		return
	held_visual_clock += delta
	if held_visual_clock < .07:return
	held_visual_clock = 0.0
	_clear_held_visual()
	var hand: Vector3 = game.held_cable_position()
	var end: Vector3 = game.held_cable_tail(hand)
	if picked_station in range(ports.size()):
		end = ports[picked_station].get(picked_port, end)
	elif picked_station in range(AC_OFFSET,AC_OFFSET+game.session.labs.size()):
		end = game.session.labs[picked_station-AC_OFFSET].positions.get(picked_port,end)
	held_visual = Node3D.new()
	add_child(held_visual)
	var color: Color = game.JACKET_COLORS[lead_color]
	var attached: bool = not picked_port.is_empty() and end != game.held_cable_tail(hand)
	if attached:
		var key := "%d:%s" % [picked_station, picked_port]
		var layer := int(local_plug_layers.get(picked_station, {}).get(key, 0))
		for link in states[0].get("external_links", []):
			for endpoint in [link.a, link.b]:
				if endpoint.station == picked_station and endpoint.port == picked_port:layer += 1
		end = CableBinding.add_end(held_visual, self, picked_station, picked_port, end, color, layer)
	var cable := MeshInstance3D.new()
	var anchor_radius: float = CableBinding.end_radius(self,picked_station,picked_port) if attached else CableMesh.JACKET_RADIUS
	var clearance: Array[AABB]=breadboard_cable_bounds if attached else []
	cable.mesh=CableMesh.held_geometry(end,hand,game.camera.global_basis,attached,anchor_radius,clearance)
	cable.material_override=CableMesh.jacket_material(color)
	held_visual.add_child(cable)
	var grip: MeshInstance3D = game.held_lead_connector(held_visual, color, hand)
	grip.global_basis = game.camera.global_basis * Basis(Vector3.RIGHT, PI * .5)

func upgrade_deployed_circuit(index: int, design: Dictionary) -> void:
	var station = benches[index]
	var old_parts: Dictionary = {}
	for part in station.board.parts: old_parts[part.id] = part.type
	for part in design.parts:
		if old_parts.get(part.id) == part.type: continue
		var prefix := "board/"+str(part.id)
		for key in station.firmware_states.keys():
			if key == prefix or key.begins_with(prefix+"/"): station.firmware_states.erase(key)
	station.apply({"op":"board","design":design},true)
	station.solver.reset()
	station.revision += 1
	states[index] = station.snapshot()
	broadcast()

func broadcast() -> void:
	if not multiplayer.is_server():return
	for i in ac_bridges.size():
		var bridge=ac_bridges[i]
		if bridge.breaker_tripped:
			bridge.breaker_tripped=false
			game.session.broadcast()
		elif bridge.linked and bridge.lab.powered and bridge.lab.readings.has("external_supply_rms"):
			var live := {}
			for field in ["ammeters","voltmeters","wattmeters","daq_v","daq_i","daq_dc_v","daq_dc_i","daq_analog","daq_digital","dynamo_voltage","igbt"]:
				if bridge.lab.readings.has(field):live[field]=bridge.lab.readings[field]
			game.session.publish_ac_readings(i,bridge.lab.revision,live)
	states.clear()
	for index in benches.size():
		var state: Dictionary = benches[index].snapshot()
		state["drawer_open"] = drawer_open[index]
		state["lead_colors"] = benches[index].lead_colors.duplicate()
		states.append(state)
	states[0].external_links=external_links.duplicate(true)
	if is_instance_valid(bench_interest):bench_interest.publish()
	ui.refresh()
@rpc("authority","call_remote","unreliable_ordered",3)
func receive(data: Array) -> void:
	if data.size()!=3:return
	states=data;ui.refresh()
	if is_instance_valid(bench_interest):bench_interest.legacy_applied()

@rpc("authority","call_remote","reliable",3)
func receive_compressed(packet: PackedByteArray,raw_size: int) -> void:
	if raw_size<1 or raw_size>2000000 or packet.size()>2000000:return
	var decoded := packet.decompress(raw_size,FileAccess.COMPRESSION_ZSTD)
	if decoded.size()!=raw_size:return
	var data=bytes_to_var(decoded)
	if data is Array and data.size()==3:
		for index in 3:
			if not data[index] is Dictionary:return
			states[index].merge(data[index],true)
		ui.refresh()
		if is_instance_valid(bench_interest):bench_interest.legacy_applied()

func endpoint_available(index: int,port: String) -> bool:
	if index<0 or port.length()>32:return false
	if index>=AC_OFFSET:
		if index>=AC_OFFSET+ac_bridges.size():return false
		if bool(ac_bridges[index-AC_OFFSET].lab.protective_earth_profile.get("enabled",false)):return false
		return port in ac_bridges[index-AC_OFFSET].available_ports()
	if index>=benches.size() or (index>=FIXED_BENCHES and not Station.board_port(port)):return false
	if port not in Station.PORTS:return false
	var station=benches[index]
	if Station.board_port(port):
		if station.board.is_empty() or station.board_stowed or station.board_held:return false
		if port.begins_with("X"):
			if not station.pcb_pin_available(port):return false
		elif station.board.get("standalone",false):return false
	return true
func edit_external(peer: int,index: int,op: String,port: String) -> String:
	if op == "detach_external":
		if carried_leads.has(peer) or not _can_hold_lead(peer): return "Stow the item in your hand first."
		for i in range(external_links.size()-1,-1,-1):
			var link: Dictionary = external_links[i]
			var other := _other_end(link,index,port)
			if other.is_empty(): continue
			var jacket := int(link.get("jacket",-1))
			carried_leads[peer] = jacket if jacket in range(4) else 2
			carried_lead_stations[peer] = int(other.station)
			pending_endpoints[peer] = other.duplicate()
			external_links.remove_at(i)
			refresh_link_flags()
			if peer==1:_sync_attached_lead(int(other.station),str(other.port),carried_leads[peer])
			else:_sync_attached_lead.rpc_id(peer,int(other.station),str(other.port),carried_leads[peer])
			break
		return ""
	if op=="unlink_external":
		for i in range(external_links.size()-1,-1,-1):
			var link: Dictionary=external_links[i]
			if (link.a.station==index and link.a.port==port) or (link.b.station==index and link.b.port==port):external_links.remove_at(i);break
		pending_endpoints.erase(peer);refresh_link_flags();return ""
	if not endpoint_available(index,port):return "This terminal is unavailable."
	if op=="begin_external":
		if index>=AC_OFFSET and carried_leads.has(peer):
			var lab = game.session.labs[index-AC_OFFSET]
			if lab.cables.size()>=120:return "Cable limit reached at this bench."
			lab.cables.append({"id":lab.next_id,"a":port,"b":"","owner":peer,"creator":peer,"color":int(carried_leads[peer])})
			lab.next_id+=1
			lab.revision+=1
			carried_leads.erase(peer)
			carried_lead_stations.erase(peer)
			pending_endpoints.erase(peer)
			game.session.broadcast()
			if peer==1:_finish_kit_lead()
			else:_finish_kit_lead.rpc_id(peer)
		else:pending_endpoints[peer]={"station":index,"port":port}
		return ""
	if not pending_endpoints.has(peer):return "Select the starting terminal again."
	var start: Dictionary=pending_endpoints[peer]
	var jacket := int(carried_leads.get(peer, -1))
	var error := _connect_external(peer,index,port,start,jacket)
	if error.is_empty():
		pending_endpoints.erase(peer)
		carried_leads.erase(peer)
		carried_lead_stations.erase(peer)
		if peer==1:_finish_kit_lead()
		else:_finish_kit_lead.rpc_id(peer)
	return error

func _connect_external(peer: int,index: int,port: String,start: Dictionary,jacket: int) -> String:
	if not endpoint_available(index,port):return "This terminal is unavailable."
	if is_instance_valid(game.school) and not _link_access(peer,int(start.station)):return "That bench belongs to another class group."
	if start.station==index:return "Use a normal lead within one bench."
	if not endpoint_available(start.station,start.port):return "The starting terminal is no longer available."
	if external_links.size()>=24:return "Inter-bench lead limit reached (24)."
	var primitive_count := 0
	var connected: Array=[int(start.station),index]
	for _pass in external_links.size():
		var previous := connected.size()
		for link in external_links:
			if int(link.a.station) in connected or int(link.b.station) in connected:
				for candidate in [int(link.a.station),int(link.b.station)]:
					if candidate not in connected:connected.append(candidate)
		if previous==connected.size():break
	var all: Array=benches+ac_bridges
	for candidate in connected:primitive_count+=all[_solver_index(candidate)].netlist().size()
	if primitive_count>96:return "Connected benches exceed the 96-device solver budget. Reduce the circuits first."
	external_links.append({"a":start,"b":{"station":index,"port":port},"jacket":jacket});refresh_link_flags();return ""
func _lead_jacket(colors: Variant, wire_index: int, wire: Array) -> int:
	if colors is Array and wire_index < colors.size():
		return int(colors[wire_index])
	if colors is Dictionary:
		return int(colors.get(str(wire[0])+"|"+str(wire[1]),-1))
	return -1

func _kit_connected_leads(index: int, wires: Array, links: Array, colors: Variant, holes: Array, prefix := "B") -> Dictionary:
	var ports := {}
	for i in holes.size():ports[prefix+str(i+1)]=holes[i]
	var leads := {}
	for wire_index in wires.size():
		var wire: Array = wires[wire_index]
		for side in range(2):
			var port := str(wire[side])
			if ports.has(port):
				leads[port]={"label":str(wire[1-side]),"jacket":_lead_jacket(colors, wire_index, wire)}
	for link in links:
		for endpoint in [link.a,link.b]:
			var port := str(endpoint.port)
			if int(endpoint.station)==index and ports.has(port):
				var other := _other_end(link,index,port)
				leads[port]={"label":str(other.port),"jacket":int(link.get("jacket",-1))}
	for port in leads:
		var lead: Dictionary=leads[port]
		lead.hole=ports[port]
		lead.color=game.JACKET_COLORS[lead.jacket] if lead.jacket in range(4) else Color("dba45b")
	return leads

func pcb_leads(index: int) -> Dictionary:
	var state: Dictionary=states[index]
	var board: Dictionary=state.get("board",{})
	if not board.get("standalone",false) or board.get("parts",[]).is_empty():return {}
	var holes: Array=preload("res://scripts/breadboard_model.gd").pins(board.parts[0])
	var leads := _kit_connected_leads(index,state.wires,states[0].get("external_links",[]),state.get("lead_colors",[]),holes,"X")
	if picked_station==index and lead_color in range(4) and picked_port.begins_with("X"):
		var pin := int(picked_port.substr(1))-1
		if pin in range(holes.size()):
			leads[picked_port]={"hole":holes[pin],"color":game.JACKET_COLORS[lead_color],"label":"Loose end"}
	return leads

func kit_leads(index: int) -> Dictionary:
	var state: Dictionary=states[index]
	var ports: Array=state.get("board",{}).get("ports",[])
	if ports.size()!=4:return {}
	var leads := _kit_connected_leads(index,state.wires,states[0].get("external_links",[]),state.get("lead_colors",[]),ports)
	if not picked_port.is_empty() and lead_color in range(4):
		leads["pending"]={"label":picked_port+" · loose end","jacket":lead_color,"color":game.JACKET_COLORS[lead_color]}
	var ac := _loose_ac_lead(multiplayer.get_unique_id())
	if not ac.is_empty():
		leads["pending_ac"]={"label":ac.port+" · loose end","jacket":ac.cable.color,"color":game.JACKET_COLORS[ac.cable.color]}
	return leads

func _create_loose_lab_lead(peer: int,color: int,index: int) -> bool:
	if game.session.labs.is_empty():return false
	var lab = game.session.labs[clampi(index,0,game.session.labs.size()-1)]
	if lab.cables.size()>=120:return false
	lab.cables.append({"id":lab.next_id,"a":"","b":"","owner":peer,"creator":peer,"color":color})
	lab.next_id+=1
	lab.revision+=1
	game.session.broadcast()
	return true

func _release_dc_anchor(peer: int,index: int) -> void:
	if not carried_leads.has(peer):return
	if int(pending_endpoints.get(peer,{}).get("station",-1))!=index:return
	if not _create_loose_lab_lead(peer,int(carried_leads[peer]),index-AC_OFFSET if index>=AC_OFFSET else index):return
	pending_endpoints.erase(peer)
	carried_leads.erase(peer)
	carried_lead_stations.erase(peer)
	if peer==1:_finish_kit_lead()
	else:_finish_kit_lead.rpc_id(peer)

func _native_held_lead(peer: int) -> Dictionary:
	for index in game.session.labs.size():
		var cable: Dictionary=game.session.labs[index].holding(peer)
		if not cable.is_empty():return {"station":index,"cable":cable}
	return {}

func _attach_native_lead(peer: int,index: int,port: String) -> String:
	if not endpoint_available(index,port):return "This terminal is unavailable."
	var held := _native_held_lead(peer)
	if held.is_empty():return "Pick up a cable first."
	var cable: Dictionary=held.cable
	var anchor: String=cable.a if not cable.a.is_empty() else cable.b
	if anchor.is_empty():
		carried_leads[peer]=int(cable.color)
		carried_lead_stations[peer]=index
		pending_endpoints[peer]={"station":index,"port":port}
	else:
		var error := _connect_external(peer,index,port,{"station":int(held.station)+AC_OFFSET,"port":anchor},int(cable.color))
		if not error.is_empty():return error
	var lab = game.session.labs[int(held.station)]
	lab.cables.erase(cable)
	lab.revision+=1
	game.session.broadcast()
	if anchor.is_empty():
		if peer==1:_sync_attached_lead(index,port,int(cable.color))
		else:_sync_attached_lead.rpc_id(peer,index,port,int(cable.color))
	return ""

@rpc("authority","call_remote","reliable")
func _sync_attached_lead(index: int,port: String,color: int) -> void:
	picked_station=index
	picked_port=port
	lead_color=color

func _loose_ac_lead(peer: int) -> Dictionary:
	for index in game.session.labs.size():
		var cable: Dictionary = game.session.labs[index].holding(peer)
		if cable.is_empty() or (cable.a.is_empty() == cable.b.is_empty()):continue
		if int(cable.color) not in range(4):continue
		return {"station":index,"port":cable.b if cable.a.is_empty() else cable.a,"cable":cable}
	return {}

func _place_kit_lead(peer: int,index: int,port: String,hole: String) -> String:
	var station=benches[index]
	var board: Dictionary=station.board
	if board.is_empty() or station.board_held or station.board_stowed or board.get("standalone",false):return "Place the kit breadboard first."
	if port not in ["pending","pending_ac"] and station.board_owner!=peer:return "This breadboard belongs to another player."
	var model=preload("res://scripts/breadboard_model.gd")
	if not model.valid_hole(board,hole):return "Choose a valid breadboard hole."
	if board.get("ports",[]).size()!=4:return "This breadboard has no lab lead slots."
	var leads := _kit_connected_leads(index,station.wires,external_links,station.lead_colors,board.ports)
	for existing in leads:
		if existing!=port and leads[existing].hole==hole:return "That hole already has a lab lead."
	for part in board.parts:
		if hole in model.pins(part):return "That hole already has a component pin."
	if port in ["pending","pending_ac"]:
		var native := _native_held_lead(peer) if port=="pending_ac" else {}
		var ac := _loose_ac_lead(peer) if not native.is_empty() else {}
		var start: Dictionary=pending_endpoints.get(peer,{}) if port=="pending" else {}
		if native.is_empty() and not carried_leads.has(peer):return "Pick up a lab lead first."
		port=""
		var occupied: Array = leads.keys()
		for endpoint in pending_endpoints.values():
			if int(endpoint.station)==index:occupied.append(str(endpoint.port))
		for candidate in ["B1","B2","B3","B4"]:
			if candidate not in occupied:port=candidate;break
		if port.is_empty():return "All four lab lead connections are in use."
		if start.get("station",-1)==index and Station.board_port(str(start.get("port",""))) and board.ports[int(str(start.port).substr(1))-1]==hole:return "Choose a different hole for the other end."
		var error := ""
		if start.is_empty() and ac.is_empty():
			var previous: String=board.ports[int(port.substr(1))-1]
			board.ports[int(port.substr(1))-1]=hole
			if not native.is_empty():
				error=_attach_native_lead(peer,index,port)
			else:
				pending_endpoints[peer]={"station":index,"port":port}
				if peer==1:_sync_attached_lead(index,port,carried_leads[peer])
				else:_sync_attached_lead.rpc_id(peer,index,port,carried_leads[peer])
			if not error.is_empty():
				board.ports[int(port.substr(1))-1]=previous
				return error
			station.revision+=1
			return ""
		if not ac.is_empty():
			error=_connect_external(peer,index,port,{"station":int(ac.station)+AC_OFFSET,"port":ac.port},int(ac.cable.color))
			if error.is_empty():
				var lab = game.session.labs[int(ac.station)]
				lab.cables.erase(ac.cable)
				lab.revision+=1
				game.session.broadcast()
		elif int(start.station)==index:
			error=station.apply({"op":"wire","a":start.port,"b":port,"lead_color":carried_leads[peer]})
			if error.is_empty():
				carried_leads.erase(peer)
				carried_lead_stations.erase(peer)
				pending_endpoints.erase(peer)
		else:
			error=edit_external(peer,index,"link_external",port)
		if not error.is_empty():return error
		if peer==1:_finish_kit_lead()
		else:_finish_kit_lead.rpc_id(peer)
	elif not leads.has(port):return "That lab lead is no longer connected."
	board.ports[int(port.substr(1))-1]=hole
	station.revision+=1
	return ""

@rpc("authority","call_remote","reliable")
func _finish_kit_lead() -> void:
	picked_port=""
	lead_color=-1

func refresh_link_flags() -> void:
	for station in benches+ac_bridges:station.linked=false
	var all_stations: Array=benches+ac_bridges
	for link in external_links:
		all_stations[_solver_index(link.a.station)].linked=true;all_stations[_solver_index(link.b.station)].linked=true
	var ac_changed := false
	for i in ac_bridges.size():
		var bridge=ac_bridges[i]
		var station := AC_OFFSET + i
		var wiring := external_links.filter(func(link):return int(link.a.station)==station or int(link.b.station)==station)
		bridge.lab.external_connections=wiring.size()
		if wiring == bridge.external_wiring:
			continue
		bridge.external_wiring=wiring.duplicate(true)
		bridge.samples.clear()
		bridge.result.clear()
		bridge.lab.recalculate()
		bridge.lab.revision += 1
		ac_changed=true
	if ac_changed:
		game.session.broadcast()
func remove_board_links(index: int) -> void:
	external_links=external_links.filter(func(link):return not ((link.a.station==index and Station.board_port(link.a.port)) or (link.b.station==index and Station.board_port(link.b.port))))
	for peer in pending_endpoints.keys():
		var endpoint: Dictionary=pending_endpoints[peer]
		if int(endpoint.station)==index and Station.board_port(str(endpoint.port)):
			pending_endpoints.erase(peer)
			_reply_hotbar_lead(int(peer),true)
	refresh_link_flags()
func draw_external_links() -> void:
	var links: Array=states[0].get("external_links",[])
	var signature := str(links)
	if signature==external_signature:return
	external_signature=signature
	for child in external_root.get_children():external_root.remove_child(child);child.queue_free()
	var all_ports := {}
	for index in ports.size():all_ports[index]=ports[index]
	var layers := {}
	for station_layers in local_plug_layers.values():layers.merge(station_layers)
	for index in game.session.labs.size():all_ports[AC_OFFSET+index]=game.session.labs[index].positions
	for link in links:
		if not all_ports.get(link.a.station,{}).has(link.a.port) or not all_ports.get(link.b.station,{}).has(link.b.port):external_signature="";continue
		var a: Vector3=all_ports[link.a.station][link.a.port];var b: Vector3=all_ports[link.b.station][link.b.port]
		var jacket := int(link.get("jacket", -1))
		var color: Color = game.JACKET_COLORS[jacket] if jacket in range(4) else Color("dba45b")
		external_root.add_child(CableBinding.from_ports(self,int(link.a.station),str(link.a.port),a,int(link.b.station),str(link.b.port),b,color,game.cable_obstacles,layers))

# PROPOSAL: scene hit routing only. Existing host input validation still applies.
func _io_hit(target: Node) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(game.camera.global_position,game.camera.global_position-game.camera.global_basis.z*3.,4)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	return hit if hit.get("collider")==target else {}

func release_physical_io() -> void:
	if not held_io.is_empty() and is_instance_valid(held_io.get("board")):held_io.board.release_io_capture(str(held_io.id))
	held_io={}

func route_io_event(event: InputEvent) -> bool:
	# Release even if a modal just took the mouse or the ray left the surface.
	if not held_io.is_empty():
		var board=held_io.get("board")
		if not is_instance_valid(board):held_io={};return false
		if (event is InputEventMouseButton and event.button_index==int(held_io.button) and not event.pressed) or (event is InputEventKey and event.physical_keycode==game.player.keys.interact and not event.pressed):
			release_physical_io();return true
		if Input.mouse_mode!=Input.MOUSE_MODE_CAPTURED or not game.player.enabled:
			release_physical_io();return false
		if event is InputEventMouseMotion:
			board.io_drag(str(held_io.id),event.relative);return true
	if Input.mouse_mode!=Input.MOUSE_MODE_CAPTURED or not game.player.enabled:return false
	var target=game.current_target
	if not is_instance_valid(target) or target.get_meta("role","")!="dc_io":return false
	var board=target.get_meta("io_board",null);var id := str(target.get_meta("part_id",""))
	if not is_instance_valid(board):return false
	if event is InputEventMouseButton and event.pressed:
		if event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN] and target.get_meta("input_type","")=="io_encoder":
			return board.io_turn(id,1 if event.button_index==MOUSE_BUTTON_WHEEL_UP else -1)
		if event.button_index==MOUSE_BUTTON_MIDDLE and target.get_meta("input_type","")=="io_joystick":
			if board.io_press_switch(id,true):held_io={"board":board,"id":id,"button":MOUSE_BUTTON_MIDDLE};return true
	return false

# Nonvolatile capture is selected by host-owned model descriptors, never by a
# client claiming a runtime kind. Models/IO/native orchestration remains separate.
func capture_nonvolatile(peer: int,index: int) -> String:
	if not multiplayer.is_server() or index<0 or index>=benches.size():return ""
	var station=benches[index]
	if station.board.is_empty() or not is_instance_valid(game.electronics_trade):return ""
	var selected := {}
	for device in preload("res://scripts/breadboard_model.gd").expand(station.board,"board/",station.result.get("v",{}),station.firmware_states).parts:
		if device.get("kind")=="stateful" and device.get("model")=="worker:eeprom25" and station.firmware_states.has(device.id):selected[device.id]=station.firmware_states[device.id]
	if selected.is_empty():return ""
	return game.electronics_trade.authority.capture_components(peer,station.board,selected,index)
func checkpoint_inventory() -> String:
	var first_error := ""
	for i in benches.size():
		if benches[i].board_owner==0:continue
		var error := capture_nonvolatile(benches[i].board_owner,i)
		if first_error=="":first_error=error
	return first_error

func _save_carried_pcbs(peer: int) -> bool:
	var items: Array=[]
	for station in benches:
		var board: Dictionary=station.board
		if station.board_owner!=peer or not (station.board_held or station.board_stowed):continue
		if not board.get("standalone",false) or board.get("authority_kit_id","existing_kit")!="":continue
		var part: Dictionary=board.parts[0]
		items.append({"type":str(part.type),"instance":str(board.get("instance_ids",{}).get(part.id,""))})
		if items.size()==6:break
	return game.electronics_trade.authority.save_carried_pcbs(peer,items)

func checkpoint_carried_pcbs() -> void:
	var peers: Array=game.electronics_trade.authority.ledger.bindings.keys() if game.session.online else [1]
	for peer in peers:
		if not saved_departing_pcbs.has(peer) and not _save_carried_pcbs(int(peer)):
			game.ui.log_message("Could not save carried PCBs.")

func _recall_departed_boards() -> void:
	for index in benches.size():
		var peer: int=benches[index].board_owner
		if peer==0 or game.session.roster.has(peer):continue
		if not saved_departing_pcbs.has(peer):
			if not _save_carried_pcbs(peer):continue
			saved_departing_pcbs[peer]=true
		authority_recall(peer,index)

func restore_carried_pcbs(peer: int) -> void:
	saved_departing_pcbs.erase(peer)
	var authority=game.electronics_trade.authority
	var profile: Dictionary=authority.ledger.account(peer).get("profile",{}) if game.session.online else game.electronics.profile.data
	var dorm: Dictionary=profile.get("dorm",{})
	var free_slots: int=6-dorm.get("carry_items",[]).size()-dorm.get("carried_components",[]).size()
	var restored := 0
	for pcb in profile.get("carried_pcbs",[]):
		if restored>=free_slots:break
		if _carry_checked_out_pcb(peer,str(pcb.type),str(pcb.instance)).is_empty():restored+=1
	if restored>0:broadcast()

func _counter_pcb(peer: int, index: int, action: Dictionary) -> String:
	var position: Vector3 = game.player.global_position if peer == 1 else game.session.poses.get(peer, {}).get("position", Vector3.ZERO)
	if not game.shop_room.near_component_counter(position): return "Visit the Component Counter first"
	if action.op == "counter_return":
		if index >= benches.size(): return "PCB unavailable"
		var station = benches[index]
		if station.board_owner != peer or station.board.get("authority_kit_id", "existing_kit") != "":
			return "This PCB was not checked out at the counter"
		if not station.board_held and not station.board_stowed: return "Pick up the PCB before returning it"
		var error := authority_recall(peer, index)
		if error.is_empty(): broadcast()
		return error
	if not action.get("id") is String: return "Invalid PCB"
	var authority = game.electronics_trade.authority
	var profile: Dictionary = authority.ledger.account(peer).get("profile", {}) if game.session.online else game.electronics.profile.data
	var dorm: Dictionary = profile.get("dorm", {})
	if dorm.get("carry_items", []).size() + dorm.get("carried_components", []).size() >= 6:
		return "Free a hotbar slot first"
	var error := _carry_checked_out_pcb(peer,action.id)
	if error.is_empty():broadcast()
	return error

func _carry_checked_out_pcb(peer: int, id: String, preferred_instance := "") -> String:
	var slot := _portable_slot()
	if slot<0:return "All portable board slots are in use"
	var authority=game.electronics_trade.authority
	var result: Dictionary=authority.checkout_pcb(peer,slot,id,preferred_instance)
	if not result.ok: return str(result.error)
	var station = benches[slot]
	var error: String = station.apply({"op":"board", "design":result.design})
	if not error.is_empty():
		if game.session.online: authority.recall(peer,slot)
		return error
	station.board_owner = peer
	station.board_stowed = true
	return ""

func take_kit_board(peer: int,kit_id: String) -> String:
	if not _can_hold_lead(peer) or carried_leads.has(peer):return "Put down the item you are holding first."
	for index in benches.size():
		if benches[index].board_owner==peer:
			if benches[index].board_held:return "Put down the breadboard in your hand first."
			if benches[index].board.get("authority_kit_id","")==kit_id:return "That kit already has a breadboard out."
	var slot := _portable_slot()
	if slot<0:return "All portable board slots are in use."
	var authority=game.electronics_trade.authority
	var profile: Dictionary=authority.ledger.account(peer).get("profile",{}) if game.session.online else game.electronics.profile.data
	if not profile.get("kits",{}).has(kit_id):return "Kit not found."
	var saved_board: Dictionary=profile.get("dorm",{}).get("stored_board",{}).get("design",{})
	if saved_board.get("authority_kit_id","")==kit_id:return "Retrieve this kit breadboard from the cabinet first."
	var kit: Dictionary=profile.get("kits",{}).get(kit_id,{})
	var design: Dictionary=kit.get("board",{}).duplicate(true)
	design.authority_kit_id=kit_id
	var model=preload("res://scripts/breadboard_model.gd")
	if model.Debug.contains(design):return "Remove simulation instruments before taking this board."
	var stock: Dictionary=kit.get("items",{})
	var creative: bool=game.school.mode=="Creative Freeplay"
	var error: String=model.validate(design,stock,creative)
	var omitted := 0
	if error.begins_with("Kit does not contain enough "):
		omitted=_omit_unpacked_parts(design,stock)
		error=model.validate(design,stock,creative)
	if not error.is_empty():return error
	if not game.session.online:
		error=authority.local_storage_error(design,slot)
		if not error.is_empty():return error
	design=authority.materialize(peer,design,slot)
	if design.is_empty():return "Could not prepare this breadboard."
	if game.session.online:
		error=authority.deployment(peer,slot,design)
		if not error.is_empty():return error
	var station=benches[slot]
	error=station.apply({"op":"board","design":design})
	if not error.is_empty():
		if game.session.online:authority.recall(peer,slot)
		return error
	station.board_owner=peer
	station.board_held=true
	broadcast()
	if omitted>0:
		var message := "%s: left %d unpacked parts off the breadboard." % [kit.name,omitted]
		if peer==1:feedback(message)
		else:feedback.rpc_id(peer,message)
	return ""

func _omit_unpacked_parts(design: Dictionary,stock: Dictionary) -> int:
	var remaining := stock.duplicate()
	var removed := {}
	var parts: Array=[]
	for part in design.parts:
		if int(remaining.get(part.type,0))>0:
			remaining[part.type]-=1
			parts.append(part)
		else:removed[str(part.id)]=true
	design.parts=parts
	for field in ["instance_ids","component_runtime","controls","io_controls","programs"]:
		var entries: Dictionary=design.get(field,{})
		for key in entries.keys():
			var root := str(key).trim_prefix("board/").get_slice("/",0)
			if removed.has(root):entries.erase(key)
	return removed.size()

func authority_recall(peer: int,index: int) -> String:
	var error := capture_nonvolatile(peer,index)
	if error!="":return error
	if game.session.online and not game.electronics_trade.authority.recall(peer,index):return "Host inventory save failed"
	remove_board_links(index)
	return benches[index].apply({"op":"recall"})

func io_kind(index: int,id: String) -> String:
	if index<0 or index>=benches.size():return ""
	var board: Dictionary=benches[index].board
	var pieces := id.split("/")
	if pieces.size()<2 or pieces[0]!="board":return ""
	var parts: Array=board.get("parts",[]);var definitions: Dictionary=board.get("definitions",{})
	for depth in range(1,pieces.size()):
		var found: Dictionary={}
		for part in parts:
			if str(part.get("id",""))==pieces[depth]:found=part;break
		if found.is_empty():return ""
		if depth==pieces.size()-1:return str(preload("res://scripts/electronics_catalog.gd").simulation_entry(str(found.type)).get("kind",""))
		var definition: Dictionary=definitions.get(found.type,{})
		if not preload("res://scripts/pcb_design/surface_layout.gd").visible(definition,pieces[depth+1]):return ""
		parts=definition.get("parts",[])
	return ""
func cleanup_io_holds() -> void:
	for key in io_guard.leases.keys():
		var lease: Dictionary=io_guard.leases[key];var station=benches[lease.station]
		var gone: bool=not game.session.roster.has(lease.peer) or station.board_held or station.board_stowed or io_kind(lease.station,lease.id)!=lease.kind
		if station.board_epoch!=lease.epoch:io_guard.leases.erase(key);continue
		if gone:
			var current: Dictionary=station.board.get("io_controls",{}).get(lease.id,{})
			station.apply({"op":"input","id":lease.id,"command":{"op":"release","revision":current.get("revision",0)}})
			io_guard.leases.erase(key)

func upload_native(index: int,id: String,program: Dictionary,sources: Dictionary) -> void:
	if index<0 or index>=states.size():return
	var text := JSON.stringify({"program":program,"sources":sources})
	var bytes := text.to_utf8_buffer().size()
	if bytes>786432:feedback("Compiled image and sources exceed the 768 KiB live upload limit");return
	var epoch := int(states[index].get("board_epoch",-1))
	request(index,{"op":"native_begin","id":id,"board_epoch":epoch,"bytes":bytes,"hash":text.sha256_text()})
	var sequence := 0
	for offset in range(0,text.length(),2000):
		request(index,{"op":"native_chunk","id":id,"board_epoch":epoch,"sequence":sequence,"data":text.substr(offset,2000)})
		sequence+=1
	request(index,{"op":"native_finish","id":id,"board_epoch":epoch})

func _exit_tree() -> void:
	native_host.close()

func equipment_capabilities(index: int) -> Dictionary:
	if index<0 or index>=benches.size():return {}
	var station=benches[index];var source_instances: Array=[]
	var sources: Array=[station.current_source]+station.auxiliary_sources
	for source_index in 4:
		var source: Dictionary=sources[source_index];var suffix := "" if source_index==0 else str(source_index+1)
		source_instances.append({"kind":"current_source","positive_terminal":"IS"+suffix+"+","negative_terminal":"IS"+suffix+"-","a":"IS"+suffix+"-","b":"IS"+suffix+"+","current_amperes":float(source.current),"setpoint_amperes":float(source.current),"compliance_volts":float(source.compliance),"enabled":station.master and source.enabled,"polarity":"source arrow a->b; positive current leaves positive_terminal","output_resistance_ohms":1e9,"mode":station.result.get("mode",{}).get("isource"+suffix,"OFF")})
	return {"adjustable_current_source":true,"current_source_instances":4,"current_source":source_instances[0],"current_sources":source_instances,"voltage_channels":3,"dmm":true,"shared_solver":true}
