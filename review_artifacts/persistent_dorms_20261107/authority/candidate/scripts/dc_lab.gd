extends Node3D
const Station = preload("res://scripts/dc_station.gd")
var game: Node
var campus_offset := Vector3.ZERO
var campus_readouts=preload("res://scripts/campus/performance/readout_adapter.gd").new()
var benches: Array=[]
var states: Array=[]
var displays: Array=[]
var instrument_fixtures: Array=[]
var physical_boards: Array=[]
var ports: Array=[]
var wire_roots: Array=[]
var drawn_revisions := [-1,-1,-1]
var ui: CanvasLayer
var accumulator := 0.0
var inventory_clock := 0.0
var broadcast_clock := 0.0
var rate_limits := {}
var picked_port := ""
var picked_station := -1
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

func build(owner_game: Node) -> void:
	game=owner_game
	external_root=Node3D.new();add_child(external_root)
	for i in range(3):
		var station = Station.new();station.restore_scope(preload("res://scripts/dc_scope/settings_store.gd").restore(i) if multiplayer.is_server() else {});benches.append(station);states.append(station.snapshot())
		build_bench(i)
		var physical=preload("res://scripts/physical_breadboard.gd").new();add_child(physical);physical.build(game,i);physical_boards.append(physical)
	for state in game.session.labs:ac_bridges.append(preload("res://scripts/ac_supply_bridge.gd").new(state))
	ui=preload("res://scripts/dc_ui.gd").new();add_child(ui);ui.build(self)
	game.session.restarted.connect(func():
		native_host.close();native_transfer.uploads.clear();native_transfer.began.clear();io_pending.clear();io_guard.leases.clear()
		ac_bridges.clear()
		for state in game.session.labs:ac_bridges.append(preload("res://scripts/ac_supply_bridge.gd").new(state))
		benches.clear();states.clear();input_holders.clear();held_input.clear();peer_fields.clear();external_links.clear();pending_endpoints.clear()
		for i in range(3):
			var station=Station.new();station.restore_scope(preload("res://scripts/dc_scope/settings_store.gd").restore(i) if multiplayer.is_server() else {});benches.append(station);states.append(station.snapshot());drawn_revisions[i]=-1
		if ui.active:ui.close()
	)
	game.session.roster_changed.connect(func():
		if multiplayer.is_server():
			for station in benches:
				if station.board_owner!=0 and not game.session.roster.has(station.board_owner):
					if authority_recall(station.board_owner,benches.find(station))!="":continue
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

func build_bench(index: int) -> void:
	var origin := Node3D.new();origin.position=Vector3((index-1)*6,.0,8.8)+campus_offset;origin.rotation.y=PI;add_child(origin)
	game._box(origin,Vector3(0,.82,0),Vector3(4.8,.12,1.6),Color("b9a17b"))
	for x in [-2.05,2.05]:game._box(origin,Vector3(x,.4,0),Vector3(.12,.8,1.3),Color("284e57"))
	var table := StaticBody3D.new();origin.add_child(table);table.position=Vector3(0,.82,0)
	var shape := CollisionShape3D.new();var box := BoxShape3D.new();box.size=Vector3(4.8,.12,1.6);shape.shape=box;table.add_child(shape)
	table.set_meta("role","table");table.set_meta("label","DC work surface")
	game.cable_obstacles.append(AABB(table.global_position-Vector3(2.4,.06,.8),Vector3(4.8,.12,1.6)))
	for x in [-2.05,2.05]:game.cable_obstacles.append(AABB(origin.to_global(Vector3(x,.4,0))-Vector3(.06,.4,.65),Vector3(.12,.8,1.3)))
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

func held_board(peer: int=-1) -> int:
	if peer<0:peer=multiplayer.get_unique_id()
	for i in states.size():
		if states[i].get("board_owner",0)==peer and states[i].get("board_held",false):return i
	return -1
func interact(target: Node,right: bool) -> bool:
	if is_instance_valid(target) and target.get_meta("role","")=="table" and right and held_board()>=0:
		var hit := get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(game.camera.global_position,game.camera.global_position-game.camera.global_basis.z*3.6,1))
		if not hit.is_empty() and hit.normal.y>.8:request(held_board(),{"op":"place_board","position":hit.position+Vector3(0,.03,0)})
		return true
	if is_instance_valid(target) and target.get_meta("role","")=="socket":
		var index := 3+int(target.get_meta("station",0));var port := str(target.get_meta("id",""))
		if right:
			for link in states[0].get("external_links",[]):
				if (link.a.station==index and link.a.port==port) or (link.b.station==index and link.b.port==port):request(index,{"op":"unlink_external","port":port});picked_port="";return true
		elif picked_port!="":
			request(index,{"op":"link_external","port":port});picked_port="";return true
	if not is_instance_valid(target) or not target.has_meta("dc_station"):return false
	var index := int(target.get_meta("dc_station"))
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
		if target.get_meta("input_type","")=="button":
			if right:return true
			held_input={"index":index,"id":id};request(index,{"op":"input","id":id,"hold":true,"pressed":true})
		else:request(index,{"op":"input","id":id,"reverse":right})
		return true
	if target.get_meta("role")=="dc_board":
		if right:request(index,{"op":"carry_board"})
		else:game.electronics.open("board",index)
		return true
	if target.get_meta("role")=="dc_instrument_control":
		var physical_action: Dictionary=instrument_fixtures[index].action_for(target,right,states[index])
		if not physical_action.is_empty():request(index,physical_action)
		return true
	if target.get_meta("role")=="dc_panel":ui.open(index);return true
	var port := str(target.get_meta("dc_port"))
	if right:
		for link in states[0].get("external_links",[]):
			if (link.a.station==index and link.a.port==port) or (link.b.station==index and link.b.port==port):
				request(index,{"op":"unlink_external","port":port});picked_port="";return true
		for i in range(states[index].wires.size()-1,-1,-1):
			if port in states[index].wires[i]:request(index,{"op":"unwire","index":i});break
		picked_port="";return true
	if picked_port=="":
		picked_port=port;picked_station=index;request(index,{"op":"begin_external","port":port})
		game.ui.log_message("Lead from "+port+": click another terminal, including another DC bench or an AC supply output. Right click cancels.")
	else:
		if picked_station!=index:request(index,{"op":"link_external","port":port})
		else:request(index,{"op":"wire","a":picked_port,"b":port})
		picked_port=""
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
	if index<0 or index>=3+ac_bridges.size() or not game.session.roster.has(peer) or var_to_bytes(action).size()>24000:return
	var io_command: bool=action.get("op")=="input" and action.get("command") is Dictionary
	var io_type := io_kind(index,str(action.get("id",""))) if io_command and index<3 else ""
	var io_release := io_command and io_guard.release_command(io_type,action.command)
	var release_only: bool=io_release or (action.get("op")=="input" and action.get("hold",false) and action.get("pressed",true)==false)
	if not release_only and is_instance_valid(game.school) and not game.school.equipment_access(peer,index if index<3 else index-3,"ETY155" if index<3 else "ELM253"):return
	if io_command:
		if index>=3:return
		io_guard.epochs[index]=benches[index].board_epoch
		if (benches[index].board_stowed or benches[index].board_held) and not io_release:return
		if io_type=="" or io_guard.check(peer,index,action.get("board_epoch"),str(action.get("id","")),io_type,action.command,str(action.get("view_token","")))!="":return
	var now := Time.get_ticks_msec()
	if peer!=1 and now-int(rate_limits.get(peer,0))<5 and not str(action.get("op","")).begins_with("native_") and not io_release and not (action.get("op")=="input" and action.get("hold",false) and action.get("pressed",true)==false):return
	rate_limits[peer]=now
	if index>=3:
		var op := str(action.get("op",""));var port := str(action.get("port",""))
		if op not in ["link_external","unlink_external"]:return
		var position: Vector3=game.player.position if peer==1 else game.session.poses.get(peer,{}).get("position",Vector3.ZERO)
		var endpoint=game.session.labs[index-3].positions.get(port)
		if not endpoint is Vector3 or (position+Vector3.UP*1.65).distance_to(endpoint)>3.25:return
		var error := edit_external(peer,index,op,port)
		if error!="":
			if peer==1:feedback(error)
			else:feedback.rpc_id(peer,error)
		broadcast();return

	var position: Vector3=game.player.position if peer==1 else game.session.poses.get(peer,{}).get("position",Vector3.ZERO)
	var station=benches[index]
	var op := str(action.get("op",""))
	var input_key := str(index)+":"+str(action.get("id",""))
	var releasing: bool=op=="input" and action.get("hold",false) and action.get("pressed",true)==false
	if releasing and int(input_holders.get(input_key,{}).get("peer",0))!=peer:return
	if op=="input" and not releasing and input_holders.has(input_key) and int(input_holders[input_key].peer)!=peer:return
	if op=="input" and (station.board_stowed or station.board_held) and station.board_owner!=peer:return
	var origin := Vector3((index-1)*6,0,8)+campus_offset
	if op in ["board","recall","input","firmware_reset","carry_board","place_board","rotate_board","stow_board","native_begin","native_chunk","native_finish","native_control"] and not station.board.is_empty():
		origin=position if (station.board_held or station.board_stowed) and station.board_owner==peer else station.board_position if station.board_position!=Vector3.ZERO else origin
	if position.distance_to(origin)>4 and not releasing and not io_release:return
	if op in ["native_begin","native_chunk","native_finish","native_control"]:
		var native_error: String=native_transfer.apply(peer,index,action,station)
		if native_error!="":
			if peer==1:feedback(native_error)
			else:feedback.rpc_id(peer,native_error)
		elif op in ["native_finish","native_control"]:broadcast()
		return
	if op in ["begin_external","link_external","unlink_external"]:
		var error := edit_external(peer,index,op,str(action.get("port","")))
		if error!="":
			if peer==1:feedback(error)
			else:feedback.rpc_id(peer,error)
		broadcast();return
	if op=="carry_board" and (game.school.held(peer)!=0 or game.school._holding_cable(peer) or game.kit_world.kits.get(peer,{}).get("held",false)):return
	if op=="place_board":
		var pos=action.get("position")
		if not pos is Vector3 or not pos.is_finite() or position.distance_to(pos)>3.6 or not game.school._table_position(pos):return
	if op=="wire" and (Station.board_port(str(action.get("a",""))) or Station.board_port(str(action.get("b","")))) and station.board_position!=Vector3.ZERO and station.board_position.distance_to(Vector3((index-1)*6,.895,8.18)+campus_offset)>3:
		if peer==1:feedback("Move this board closer to its DC bench before connecting leads.")
		else:feedback.rpc_id(peer,"Move this board closer to its DC bench before connecting leads.")
		return
	if str(action.get("op","")) in ["board","recall","firmware_reset","carry_board","place_board","rotate_board","stow_board"] and station.board_owner not in [0,peer]:
		if peer==1:game.ui.log_message("This board belongs to another player.")
		else:feedback.rpc_id(peer,"This board belongs to another player.")
		return
	if action.get("op")=="board":
		for other in benches:
			if other!=station and other.board_owner==peer:
				if peer==1:game.ui.log_message("Recall your existing breadboard before deploying another.")
				else:feedback.rpc_id(peer,"Recall your existing breadboard before deploying another.")
				return
	if op in ["board","recall","stow_board"]:
		var stock_error := capture_nonvolatile(peer,index)
		if stock_error=="" and op=="board":
			if not action.get("design") is Dictionary:stock_error="Invalid board"
			else:
				action=action.duplicate(true)
				if not game.session.online:stock_error=game.electronics_trade.authority.local_storage_error(action.design)
				if stock_error=="":action.design=game.electronics_trade.authority.materialize(peer,action.design)
				if game.session.online:stock_error=game.electronics_trade.authority.deployment(peer,index,action.design)
		if stock_error=="" and op=="recall" and game.session.online and not game.electronics_trade.authority.recall(peer):stock_error="Host inventory save failed"
		if stock_error!="":
			if peer==1:feedback(stock_error)
			else:feedback.rpc_id(peer,stock_error)
			return
	if io_command and io_release and io_guard.leases.get(str(index)+":"+str(action.id),{}).get("peer",-1)==peer:
		action=action.duplicate(true);action.command.revision=station.board.get("io_controls",{}).get(str(action.id),{}).get("revision",0)
	var academic_before: Array=station.netlist().duplicate(true) if game.school.formal_active() else []
	var message: String=station.apply(action)
	if message=="" and game.school.activity.get("course_id","")=="ETY155":game.school.observe_equipment_action(peer,index,op,academic_before)
	if message=="" and io_command:io_guard.commit(peer,index,str(action.id),io_type,station.board.get("io_controls",{}).get(str(action.id),{}),str(action.get("view_token","")))
	if message=="" and op in ["recall","board"]:remove_board_links(index)
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
func _process(delta: float) -> void:
	if not is_instance_valid(game):return
	var trace: Node=game.get_meta("campus_hitch_trace",null) if game.has_meta("campus_hitch_trace") else null
	var span: int=trace.begin_span("dc_lab_process_total") if is_instance_valid(trace) else -1
	if not held_input.is_empty() and (not game.player.enabled or not (Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) or Input.is_physical_key_pressed(KEY_E))):release_input()
	if multiplayer.is_server():
		cleanup_io_holds()
		inventory_clock+=delta
		if inventory_clock>=1:
			inventory_clock=0
			var save_error := checkpoint_inventory()
			if save_error!="":game.ui.log_message(save_error)
			for i in benches.size():
				if benches[i].board_owner!=0 and not game.session.roster.has(benches[i].board_owner):authority_recall(benches[i].board_owner,i)
		var simulation_span: int=trace.begin_span("dc_lab_simulation") if is_instance_valid(trace) else -1
		accumulator=minf(accumulator+delta,.04)
		var steps := mini(80,int(accumulator/.0005))
		var _step := 0;var native_budget := Time.get_ticks_usec()+4000
		native_host.refresh(benches)
		while _step<steps:
			if native_host.active:
				var completed: bool=native_host.advance(benches+ac_bridges,external_links,.0005,false)
				if completed:_step+=1
				if Time.get_ticks_usec()>=native_budget:break
				continue
			if not external_links.is_empty():preload("res://scripts/dc_coupling.gd").step(benches+ac_bridges,external_links,.0005)
			else:
				for bench in benches:
					bench.linked=false
					if bench.master or bench.generator.enabled or not bench.board.is_empty():bench.step(.0005)
					elif _step==0:bench.step(maxf(.0005,delta))
			_step+=1
		accumulator-=_step*.0005
		if is_instance_valid(trace):trace.end_span(simulation_span)
		var snapshot_span: int=trace.begin_span("dc_lab_snapshot_ui") if is_instance_valid(trace) else -1
		broadcast_clock+=delta
		if broadcast_clock>=.1:broadcast_clock=0;broadcast()
		if is_instance_valid(trace):trace.end_span(snapshot_span)
	var presentation_span: int=trace.begin_span("dc_lab_presentation") if is_instance_valid(trace) else -1
	for index in range(states.size()):
		# Presentation only; host stepping above is unchanged. Out-of-interest
		# clients retain static geometry/last view until reliable full re-entry.
		if not multiplayer.is_server() and is_instance_valid(bench_interest) and bench_interest.has_stream() and not bench_interest.active(index):
			campus_readouts.budget.set_relevant(str(index),false)
			continue
		var state: Dictionary=states[index]
		physical_boards[index].update_state(state)
		for id in physical_boards[index].external_ports:ports[index][id]=physical_boards[index].to_global(physical_boards[index].external_ports[id])
		var display_relevant: bool=displays[index].is_visible_in_tree() and displays[index].global_position.distance_squared_to(game.camera.global_position)<=1225.
		var fixture_relevant: bool=instrument_fixtures[index].global_position.distance_squared_to(game.camera.global_position)<=144.0
		# Read opening transforms every presentation pass; rebuild cable geometry when anchors move.
		var physical_ports: Dictionary=instrument_fixtures[index].port_positions()
		for id in physical_ports:
			if ports[index].get(id)!=physical_ports[id]:drawn_revisions[index]=-1;external_signature=""
			ports[index][id]=physical_ports[id]
		instrument_fixtures[index].observe(state,delta,fixture_relevant)
		if state.revision!=drawn_revisions[index]:
			drawn_revisions[index]=state.revision
			for c in wire_roots[index].get_children():wire_roots[index].remove_child(c);c.queue_free()
			for wire in state.wires:
				if not ports[index].has(wire[0]) or not ports[index].has(wire[1]):continue
				var a: Vector3=ports[index][wire[0]];var b: Vector3=ports[index][wire[1]]
				wire_roots[index].add_child(preload("res://scripts/campus/dc_lab/bindings/cable_binding.gd").from_ports(self,index,str(wire[0]),a,index,str(wire[1]),b,Color("dc9d5b"),game.cable_obstacles))
	campus_readouts.tick(delta,500)
	draw_external_links()
	if is_instance_valid(trace):
		trace.end_span(presentation_span)
		trace.end_span(span)
func broadcast() -> void:
	if not multiplayer.is_server():return
	states.clear()
	for bench in benches:states.append(bench.snapshot())
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
	if index>=3:
		if index>=3+ac_bridges.size():return false
		if bool(ac_bridges[index-3].lab.protective_earth_profile.get("enabled",false)):return false
		return port in ac_bridges[index-3].available_ports()
	if port not in Station.PORTS:return false
	var station=benches[index]
	if Station.board_port(port):
		if station.board.is_empty() or station.board_stowed or station.board_held:return false
		if port.begins_with("X"):
			if not station.pcb_pin_available(port):return false
	return true
func edit_external(peer: int,index: int,op: String,port: String) -> String:
	if op=="unlink_external":
		for i in range(external_links.size()-1,-1,-1):
			var link: Dictionary=external_links[i]
			if (link.a.station==index and link.a.port==port) or (link.b.station==index and link.b.port==port):external_links.remove_at(i);break
		pending_endpoints.erase(peer);refresh_link_flags();return ""
	if not endpoint_available(index,port):return "This terminal is unavailable."
	if op=="begin_external":pending_endpoints[peer]={"station":index,"port":port};return ""
	if not pending_endpoints.has(peer):return "Select the starting terminal again."
	var start: Dictionary=pending_endpoints[peer];pending_endpoints.erase(peer)
	if is_instance_valid(game.school) and not game.school.equipment_access(peer,int(start.station) if int(start.station)<3 else int(start.station)-3,"ETY155" if int(start.station)<3 else "ELM253"):return "That bench belongs to another class group."
	if start.station==index:return "Use a normal lead within one bench."
	if not endpoint_available(start.station,start.port):return "The starting terminal is no longer available."
	if external_links.size()>=24:return "Inter-bench lead limit reached (24)."
	var primitive_count := 0
	var connected: Array=[int(start.station),index]
	for _pass in 6:
		for link in external_links:
			if int(link.a.station) in connected or int(link.b.station) in connected:
				for candidate in [int(link.a.station),int(link.b.station)]:
					if candidate not in connected:connected.append(candidate)
	var all: Array=benches+ac_bridges
	for candidate in connected:primitive_count+=all[candidate].netlist().size()
	if primitive_count>96:return "Connected benches exceed the 96-device solver budget. Reduce the circuits first."
	external_links.append({"a":start,"b":{"station":index,"port":port}});refresh_link_flags();return ""
func refresh_link_flags() -> void:
	for station in benches+ac_bridges:station.linked=false
	for bridge in ac_bridges:bridge.lab.external_connections=0
	var all_stations: Array=benches+ac_bridges
	for link in external_links:
		all_stations[link.a.station].linked=true;all_stations[link.b.station].linked=true
		for endpoint in [link.a,link.b]:
			if int(endpoint.station)>=3:ac_bridges[int(endpoint.station)-3].lab.external_connections+=1
func remove_board_links(index: int) -> void:
	external_links=external_links.filter(func(link):return not ((link.a.station==index and Station.board_port(link.a.port)) or (link.b.station==index and Station.board_port(link.b.port))))
	refresh_link_flags()
func draw_external_links() -> void:
	var links: Array=states[0].get("external_links",[])
	var signature := str(links)
	if signature==external_signature:return
	external_signature=signature
	for child in external_root.get_children():external_root.remove_child(child);child.queue_free()
	var all_ports: Array=ports.duplicate()
	for state in game.session.labs:all_ports.append(state.positions)
	for link in links:
		if not all_ports[link.a.station].has(link.a.port) or not all_ports[link.b.station].has(link.b.port):external_signature="";continue
		var a: Vector3=all_ports[link.a.station][link.a.port];var b: Vector3=all_ports[link.b.station][link.b.port]
		external_root.add_child(preload("res://scripts/campus/dc_lab/bindings/cable_binding.gd").from_ports(self,int(link.a.station),str(link.a.port),a,int(link.b.station),str(link.b.port),b,Color("dba45b"),game.cable_obstacles))

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
	return game.electronics_trade.authority.capture_components(peer,station.board,selected)
func checkpoint_inventory() -> String:
	var first_error := ""
	for i in benches.size():
		if benches[i].board_owner==0:continue
		var error := capture_nonvolatile(benches[i].board_owner,i)
		if first_error=="":first_error=error
	return first_error
func authority_recall(peer: int,index: int) -> String:
	var error := capture_nonvolatile(peer,index)
	if error!="":return error
	if game.session.online and not game.electronics_trade.authority.recall(peer):return "Host inventory save failed"
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
		if definition.get("package","")!="PCB" and pieces[depth+1] not in definition.get("exposed",[]):return ""
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
