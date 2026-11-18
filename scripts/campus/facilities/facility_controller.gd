extends Node
## Same node path on all peers. No full-save or currency broadcast.
signal owner_result(result: Dictionary)
signal room_event(peer: int, state: Dictionary)
signal sandwich_rejected(message: String)
signal cable_selection_rejected(message: String)
const Rules=preload("res://scripts/campus/facilities/facility_host.gd")
var host=Rules.new()
var interested_peers := Callable() # (room_id)->Array[int], from authoritative zone service
var tick_accumulator:=0.0
var room_states:={}
var sandwich_request_times: Dictionary = {}
var refresh_times:={}
var visual_states:={}
var preview_times:={}

func _ready() -> void:
	host.authority=is_host
	host.live_lifts = true
	host.physical_sandwich_orders = true
	host.live_lift_result.connect(_deliver)
	host.public_event.connect(_public)
	multiplayer.peer_disconnected.connect(_left)

func _process(delta: float) -> void:
	if not is_host():return
	tick_accumulator+=delta
	if tick_accumulator>=0.1:
		tick_accumulator=0
		host.tick()

func request(value: Dictionary) -> void:
	if not connected():return
	if is_host():_deliver(1,host.act(1,value))
	else:_request.rpc_id(1,value)

func sandwich_action(station: String, choice: String) -> void:
	if not connected(): return
	if is_host(): _sandwich_for(multiplayer.get_unique_id(),station,choice)
	else: _sandwich_request.rpc_id(1,station,choice)

@rpc("any_peer","call_remote","reliable")
func _sandwich_request(station: String, choice: String) -> void:
	if not is_host() or station.length()>40 or choice.length()>40:return
	var sender := multiplayer.get_remote_sender_id()
	var now := Time.get_ticks_msec()
	if choice!="cancel" and now-int(sandwich_request_times.get(sender,-1000))<80:return
	sandwich_request_times[sender]=now
	_sandwich_for(sender,station,choice)

func _sandwich_for(peer: int, station: String, choice: String) -> void:
	var result: Dictionary = host.sandwich_action(peer,station,choice)
	if result.ok: return
	if peer == multiplayer.get_unique_id(): sandwich_rejected.emit(result.error)
	else: _sandwich_rejection.rpc_id(peer,result.error)

@rpc("authority","call_remote","reliable")
func _sandwich_rejection(message: String) -> void:
	sandwich_rejected.emit(message)

func select_cable_weight(station: String, weight: int) -> void:
	if not connected():
		return
	if is_host():
		_select_cable_for(multiplayer.get_unique_id(),station,weight)
	else:
		_select_cable_weight.rpc_id(1,station,weight)

@rpc("any_peer","call_remote","reliable")
func _select_cable_weight(station: String, weight: int) -> void:
	if is_host() and station.length() <= 32:
		_select_cable_for(multiplayer.get_remote_sender_id(),station,weight)

func _select_cable_for(peer: int, station: String, weight: int) -> void:
	var result := host.set_cable_weight(peer,station,weight)
	if not result.ok:
		if peer == multiplayer.get_unique_id():
			cable_selection_rejected.emit(result.error)
		else:
			_cable_rejection.rpc_id(peer,result.error)
		return
	var event := {"activity":"cable_pin","station":station,"weight":weight}
	room_event.emit(peer,event)
	if multiplayer.has_multiplayer_peer():
		for other in multiplayer.get_peers():
			_event.rpc_id(other,peer,event)

@rpc("authority","call_remote","reliable")
func _cable_rejection(message: String) -> void:
	cable_selection_rejected.emit(message)

func preview_motion(progress: float,expected_phase: int,expected_reps: int,expected_start: int) -> void:
	if not connected():return
	if is_host():_accept_preview(multiplayer.get_unique_id(),progress,expected_phase,expected_reps,expected_start)
	else:_preview.rpc_id(1,progress,expected_phase,expected_reps,expected_start)

@rpc("any_peer","call_remote","unreliable")
func _preview(progress: float,expected_phase: int,expected_reps: int,expected_start: int) -> void:
	if is_host():_accept_preview(multiplayer.get_remote_sender_id(),progress,expected_phase,expected_reps,expected_start)

func _accept_preview(peer: int,progress: float,expected_phase: int,expected_reps: int,expected_start: int) -> void:
	if host.live_lifts:return
	if not is_finite(progress) or progress<0.0 or progress>1.0 or expected_phase not in [0,1] or expected_reps<0:return
	var now:=Time.get_ticks_msec()
	if now-int(preview_times.get(peer,-1000))<120:return
	var active: Dictionary=host.active.get(peer,{})
	var context: Dictionary=host.trusted(peer)
	if active.get("type","")!="exercise" or int(active.get("phase",-1))!=expected_phase or int(active.get("reps",-1))!=expected_reps or int(active.get("started",-1))!=expected_start or context.is_empty() or not host.activity_valid(context,active):return
	preview_times[peer]=now
	var phase:=progress if int(active.phase)==0 else 1.0-progress
	var event:={"activity":"exercise","station":active.station,"exercise":active.exercise,"phase":phase,"weight":active.weight,"reps":active.reps,"half_ms":active.half_ms}
	if active.has("equipment"):event.equipment=active.equipment
	if active.has("bench_position"):event.bench_position=active.bench_position
	if active.has("grip_anchor"):event.grip_anchor=active.grip_anchor
	if active.has("mat_position"):event.mat_position=active.mat_position
	_public(str(active.room_id),peer,event)

func refresh() -> void:
	if not connected():return
	if is_host():
		host.commit_recovery(1)
		var state: Dictionary=host.private_state(1)
		_restore_placed_order(1,state)
		owner_result.emit({"ok":true,"state":state})
	else:_refresh.rpc_id(1)

@rpc("any_peer","call_remote","reliable")
func _refresh() -> void:
	if not is_host():return
	var peer:=multiplayer.get_remote_sender_id()
	var now:=Time.get_ticks_msec()
	if now-int(refresh_times.get(peer,-1000))<200:return
	refresh_times[peer]=now
	host.commit_recovery(peer)
	var state: Dictionary=host.private_state(peer)
	_restore_placed_order(peer,state)
	_deliver(peer,{"ok":true,"state":state})
	var c: Dictionary=host.trusted(peer)
	if c.get("room_id") == "gym":
		for station in host.cable_weights:
			_event.rpc_id(peer,1,{"activity":"cable_pin","station":station,"weight":host.cable_weights[station]})
	if c.is_empty() or not interested_peers.is_valid() or not peer in interested_peers.call(str(c.get("room_id",""))):return
	for key in room_states:
		var entry: Dictionary=room_states[key]
		if str(entry.room_id)==str(c.get("room_id","")):
			for event in entry.events.values():
				if event.get("activity") == "sandwich_counter":
					var prep: Dictionary = host.sandwich_counter.snapshot(host.now())
					if not prep.is_empty() and prep.owner == int(entry.peer):
						_event.rpc_id(peer,int(entry.peer),{"activity":"sandwich_counter","prep":prep})
				else:
					_event.rpc_id(peer,int(entry.peer),event)

@rpc("any_peer","call_remote","reliable")
func _request(value: Dictionary) -> void:
	if is_host():
		var peer:=multiplayer.get_remote_sender_id()
		_deliver(peer,host.act(peer,value))

func _deliver(peer: int, result: Dictionary) -> void:
	if peer==multiplayer.get_unique_id():owner_result.emit(result)
	else:_result.rpc_id(peer,result)

@rpc("authority","call_remote","reliable")
func _result(value: Dictionary) -> void:owner_result.emit(value)

func _public(room: String, peer: int, state: Dictionary) -> void:
	if not is_host():return
	var key:=room+"/"+str(peer)
	var entry: Dictionary=room_states.get(key,{"room_id":room,"peer":peer,"events":{}})
	if state.get("activity","")=="sandwich_counter":
		if state.prep.is_empty(): entry.events.erase("sandwich_counter")
		else: entry.events["sandwich_counter"] = state.duplicate(true)
	elif state.has("held"):
		var order_key := "food/" + str(state.get("order_id", "0"))
		if str(state.held.get("station", "")).is_empty():
			entry.events.erase(order_key)
		else:
			entry.events[order_key] = state.duplicate(true)
	else:
		entry.events["activity"] = {"activity":"idle"} if state.get("activity","") in ["emote","assist","spot_assist"] else state.duplicate(true)
	room_states[key]=entry
	# Host sees its local room only; remote recipients selected by zone interest.
	var recipients: Array=interested_peers.call(room) if interested_peers.is_valid() else []
	if not peer in recipients:recipients.append(peer)
	for recipient in recipients:
		if int(recipient)==multiplayer.get_unique_id():_emit_local(peer,state)
		elif int(recipient)>1 and int(recipient) in multiplayer.get_peers():_event.rpc_id(int(recipient),peer,state)

@rpc("authority","call_remote","reliable")
func _event(peer: int, state: Dictionary) -> void:_emit_local(peer,state)

func _emit_local(peer: int,state: Dictionary) -> void:
	if not state.has("held") and state.get("activity","") not in ["holding","consume","place","pickup","cable_pin","sandwich_counter"]:
		visual_states[peer]={"activity":"idle"} if state.get("activity","") in ["emote","assist","spot_assist"] else state.duplicate(true)
	room_event.emit(peer,state)

func reset_presentation() -> void:
	for peer in visual_states.keys():room_event.emit(int(peer),{"activity":"idle"})
	visual_states.clear();room_states.clear();preview_times.clear();sandwich_request_times.clear()
	for station in host.cable_weights:
		room_event.emit(multiplayer.get_unique_id(), {"activity":"cable_pin","station":station,"weight":5})
	host.cable_weights.clear()

func finish_session() -> void:
	if not is_host():return
	host.clear_sandwich()
	# The session emits leaving before roster, ledger and transport teardown.
	for peer in host.active.keys():host.clear_activity(int(peer),"interrupted")
	if not host.pending_sets.is_empty():push_warning("Gym workout records are still waiting for the profile save. Keep the host open and reconnect the affected student to retry.")

func _left(peer: int) -> void:
	if host.sandwich_counter.owner==peer: host.clear_sandwich()
	sandwich_request_times.erase(peer)
	host.clear_activity(peer,"interrupted");host.last_request.erase(peer);host.last_assist.erase(peer);refresh_times.erase(peer)
	visual_states.erase(peer);preview_times.erase(peer)
	for key in room_states.keys():
		if int(room_states[key].peer)==peer:
			var entry: Dictionary = room_states[key]
			for event in entry.events.values():
				if event.has("held"):
					_public(str(entry.room_id), peer, {"activity":"consume", "order_id":event.get("order_id", "0"), "held":{}})
			room_states.erase(key)

func _restore_placed_order(peer: int,state: Dictionary) -> void:
	var orders: Dictionary = state.get("profile", {}).get("orders", {})
	for id in orders:
		var held: Dictionary = orders[id]
		var station := str(held.get("station", ""))
		if station.is_empty():continue
		var room := str(held.get("room", "")) if station=="table" else str(host.anchors.get(station, {}).get("room_id", ""))
		if room.is_empty() or room_states.get(room+"/"+str(peer), {}).get("events", {}).has("food/"+id):continue
		_public(room, peer, {"activity":"place", "order_id":id, "held":held})

func connected() -> bool:
	return multiplayer.has_multiplayer_peer() and multiplayer.multiplayer_peer.get_connection_status()==MultiplayerPeer.CONNECTION_CONNECTED

func is_host() -> bool:return connected() and multiplayer.is_server()
