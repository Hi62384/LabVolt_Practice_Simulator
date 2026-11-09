extends Node
signal projection_error(peer: int, message: String)
## Actual reliable ordered RPC endpoint. Add the same named child on host/clients.
## Core supplies snapshots/host contexts; this node never changes electrical state.
const Service = preload("res://scripts/campus/performance/dc_interest_service.gd")
const Context = preload("res://scripts/campus/performance/bench_interest_context.gd")
var service := Service.new()
var context := Context.new()
var session: Node
var source: Callable
var consume: Callable
var _known := {}
var _resync_times := {}
var _dc: Node
var last_enqueue_error := OK
var _projection_errors := {}

func bind_dc(dc: Node) -> void:
	_dc=dc
	configure(dc.game.session,_projection,_apply_dc)

func configure(authoritative_session: Node, projection: Callable, consumer: Callable) -> void:
	session=authoritative_session;source=projection;consume=consumer
	if session.has_signal("restarted") and not session.restarted.is_connected(reset_session):session.restarted.connect(reset_session)
	if session.has_signal("roster_changed") and not session.roster_changed.is_connected(prune):session.roster_changed.connect(prune)

func _projection() -> Dictionary:
	return context.from_game(_dc.game,_dc.states)

func _apply_dc() -> void:
	for index in _dc.AC_OFFSET:
		if service.active(index):
			_dc.ensure_portable_slot(index)
			_dc.states[index]=service.state(index)
		elif index>=_dc.FIXED_BENCHES and index<_dc.states.size():
			_dc.states[index]=_dc.benches[index].snapshot()
	# Link membership is a client projection, never an authoritative disconnection.
	_dc.states[0].external_links=service.links()
	_dc.ui.refresh()

func publish() -> void:
	if not multiplayer.is_server() or not is_instance_valid(session) or not session.online or not source.is_valid():return
	prune()
	var projection: Dictionary=source.call()
	for peer in session.roster:
		if int(peer)==1 or not session.peer_connected_now(int(peer)):continue
		var prepared: Dictionary=service.prepare(int(peer),projection.peers.get(int(peer),{}),projection.objects)
		if prepared.is_empty():continue
		if not prepared.get("ok",false):
			var message:=str(prepared.get("error","Projection failed"))
			if _projection_errors.get(peer,"")!=message:projection_error.emit(int(peer),message)
			_projection_errors[peer]=message
			continue
		_projection_errors.erase(peer)
		_known[int(peer)]=true
		var error: int = rpc_id(int(peer),"receive_interest",prepared.packet,int(prepared.raw_size))
		last_enqueue_error=error
		if error==OK:service.commit(int(peer),int(prepared.token))
		else:service.failed_send(int(peer))

@rpc("authority","call_remote","reliable",3)
func receive_interest(packet: PackedByteArray, raw_size: int) -> void:
	if multiplayer.is_server() or multiplayer.get_remote_sender_id()!=1:return
	var result:=service.accept_encoded(packet,raw_size)
	if result.ok:
		if consume.is_valid():consume.call()
	elif result.need_full:
		_request_resync()

func _request_resync() -> void:
	if is_instance_valid(session) and session.online and session.peer_connected_now(1):request_full.rpc_id(1)

@rpc("any_peer","call_remote","reliable",3)
func request_full() -> void:
	if not multiplayer.is_server() or not is_instance_valid(session):return
	var peer:=multiplayer.get_remote_sender_id()
	if not session.peer_connected_now(peer):return
	var now:=Time.get_ticks_msec()
	if _resync_times.has(peer) and now-int(_resync_times[peer])<500:return
	_resync_times[peer]=now
	service.request_full(peer)
	publish()

func prune() -> void:
	if not is_instance_valid(session):return
	for peer in _known.keys():
		if not session.roster.has(peer):
			service.forget_peer(int(peer));_known.erase(peer);_resync_times.erase(peer);_projection_errors.erase(peer)

func reset_session() -> void:
	service.reset_session();_known.clear();_resync_times.clear();_projection_errors.clear()

func active(index: int) -> bool:
	return service.active(index)

func has_stream() -> bool:
	return not service._stream.is_empty()

func legacy_applied() -> void:
	service.clear_receiver()
	if not multiplayer.is_server():_request_resync()
