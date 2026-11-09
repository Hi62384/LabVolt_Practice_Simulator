extends Node
## Same node path on all peers. No full-save or currency broadcast.
signal owner_result(result: Dictionary)
signal room_event(peer: int, state: Dictionary)
const Rules=preload("res://scripts/campus/facilities/facility_host.gd")
var host=Rules.new()
var interested_peers := Callable() # (room_id)->Array[int], from authoritative zone service
var tick_accumulator:=0.0
var room_states:={}
var refresh_times:={}

func _ready() -> void:
	host.authority=is_host
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

func refresh() -> void:
	if not connected():return
	if is_host():
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
	var state: Dictionary=host.private_state(peer)
	_restore_placed_order(peer,state)
	_deliver(peer,{"ok":true,"state":state})
	var c: Dictionary=host.trusted(peer)
	if c.is_empty() or not interested_peers.is_valid() or not peer in interested_peers.call(str(c.get("room_id",""))):return
	for key in room_states:
		var entry: Dictionary=room_states[key]
		if str(entry.room_id)==str(c.get("room_id","")):
			for event in entry.events.values():_event.rpc_id(peer,int(entry.peer),event)

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
	if state.has("held"):
		var order_key := "food/" + str(state.get("order_id", "0"))
		if str(state.held.get("station", "")).is_empty():
			entry.events.erase(order_key)
		else:
			entry.events[order_key] = state.duplicate(true)
	else:
		entry.events["activity"] = state.duplicate(true)
	room_states[key]=entry
	# Host sees its local room only; remote recipients selected by zone interest.
	var recipients: Array=interested_peers.call(room) if interested_peers.is_valid() else []
	if not peer in recipients:recipients.append(peer)
	for recipient in recipients:
		if int(recipient)==multiplayer.get_unique_id():room_event.emit(peer,state)
		elif int(recipient)>1 and int(recipient) in multiplayer.get_peers():_event.rpc_id(int(recipient),peer,state)

@rpc("authority","call_remote","reliable")
func _event(peer: int, state: Dictionary) -> void:room_event.emit(peer,state)

func _left(peer: int) -> void:
	host.clear_activity(peer);host.last_request.erase(peer);refresh_times.erase(peer)
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
