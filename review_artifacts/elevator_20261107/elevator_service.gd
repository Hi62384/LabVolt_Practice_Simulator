extends Node
## Adapter for the EXISTING campus transition/pose-epoch service, not another teleporter.
const State = preload("res://scripts/campus/elevator/elevator_state.gd")
const Geometry = preload("res://scripts/campus/elevator/elevator_geometry.gd")
var state = State.new()
var integration: Node
var game: Node
var geometry: Node3D
var timer: Timer
var snapshot_state: Dictionary = {}
var previous_guard: Callable
var previous_local_lock: Callable
var request_times: Dictionary = {}
var received := false
var recovery_pending := false
var leaving_session := false

func configure(owner_integration: Node) -> void:
	integration = owner_integration; game = integration.game
	geometry = game.campus.elevator_geometry
	previous_guard = game.session.facility_translation_guard
	previous_local_lock = game.player.facility_movement_locked
	game.session.facility_translation_guard = _guard
	game.player.facility_movement_locked = _local_locked
	game.session.restarted.connect(_reset)
	game.session.leaving.connect(_session_leaving)
	game.session.roster_changed.connect(_roster_changed)
	multiplayer.peer_disconnected.connect(_left)
	timer = Timer.new(); timer.wait_time = 0.1; timer.timeout.connect(_tick); add_child(timer)
	_reset()

func request(floor_id: int, button: int) -> void:
	if multiplayer.is_server(): _accept(1, floor_id, button)
	elif game.session.online: _request.rpc_id(1, floor_id, button)

@rpc("any_peer", "call_remote", "reliable", 4)
func _request(floor_id: int, button: int) -> void:
	if multiplayer.is_server(): _accept(multiplayer.get_remote_sender_id(), floor_id, button)

func _accept(peer: int, floor_id: int, button: int) -> void:
	if floor_id not in [0, 1] or button not in [-1, 0, 1]: return
	if not game.session.roster.has(peer) or not _eligible(peer): return
	var now := Time.get_ticks_msec()
	if now - int(request_times.get(peer, -1000)) < 180: return
	request_times[peer] = now
	var position_value := _position(peer)
	if (position_value + Vector3.UP * 1.2).distance_to(Geometry.control_position(floor_id, button)) > 2.1: return
	# Front/back sided controls cannot be activated through the shut doors.
	if button < 0:
		if position_value.x > 16.0: return
	else:
		if floor_id != state.floor_id or not _inside(position_value, floor_id): return
	if state.request(floor_id if button < 0 else button, button >= 0):
		geometry.play_tone()
		_publish(); timer.start()

func _position(peer: int) -> Vector3:
	return game.player.global_position if peer == 1 else game.session.poses.get(peer, {}).get("position", Vector3(-100, -100, -100))

func _eligible(peer: int) -> bool:
	return not game.school.formal_active() and not game.session.poses.get(peer, {}).get("seated", false) and not integration.facilities.controller.host.movement_locked(peer) and not game.school._holding_cable(peer)

static func _inside(point: Vector3, floor_id: int) -> bool:
	return point.x >= 16.35 and point.x <= 23.95 and point.z >= 56.1 and point.z <= 61.9 and point.y >= floor_id * 5.0 - 0.2 and point.y <= floor_id * 5.0 + 2.4

static func _doorway(point: Vector3, floor_id: int) -> bool:
	# Expanded by capsule radius, network sampling allowance, and door movement.
	return point.x >= 15.25 and point.x <= 16.85 and point.z >= 57.55 and point.z <= 60.45 and point.y >= floor_id * 5.0 - 0.2 and point.y <= floor_id * 5.0 + 3.4

func _tick() -> void:
	if not multiplayer.is_server():
		if game.session.online and not received and multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED: _sync_request.rpc_id(1)
		return
	var blocked := false; var eligible := true; var occupants := {}
	if state.phase in ["open", "closing"]:
		for peer in game.session.roster:
			var point := _position(int(peer))
			if _doorway(point, state.floor_id): blocked = true
			if _inside(point, state.floor_id):
				occupants[int(peer)] = point
				if not _eligible(int(peer)): eligible = false
	var revision: int = state.revision
	var event: String = state.advance(0.1, blocked, occupants, eligible)
	if event == "arrive":
		# All riders retain their distinct cabin offsets. No requester-only transport.
		for peer in state.riders:
			if game.session.roster.has(peer):
				var point: Vector3 = state.riders[peer]
				point.y += (state.floor_id * 5.0 - roundf(point.y / 5.0) * 5.0)
				integration._relocate(int(peer), point)
	if state.revision != revision: _publish()
	if state.phase == "open" and state.queue.is_empty(): timer.stop()

func _guard(peer: int, proposed: Vector3, previous: Vector3) -> Vector3:
	if state.riders.has(peer): return previous
	for floor_id in [0, 1]:
		if floor_id == state.floor_id and state.phase == "open": continue
		if previous.y >= floor_id * 5.0 - 0.2 and previous.y <= floor_id * 5.0 + 3.8 and minf(previous.z, proposed.z) <= 60.45 and maxf(previous.z, proposed.z) >= 57.55:
			if (previous.x < 16.18 and proposed.x >= 16.18) or (previous.x > 16.18 and proposed.x <= 16.18): return previous
	return previous_guard.call(peer, proposed, previous) if previous_guard.is_valid() else proposed

func _local_locked() -> bool:
	return snapshot_state.get("riders", {}).has(multiplayer.get_unique_id()) or (previous_local_lock.is_valid() and previous_local_lock.call())

func _publish() -> void:
	var value: Dictionary = state.snapshot()
	_apply(value)
	if game.session.online:
		for peer in game.session.roster:
			if int(peer) != 1: _snapshot.rpc_id(int(peer), value)

@rpc("authority", "call_remote", "reliable", 4)
func _snapshot(value: Dictionary) -> void:
	_apply(value)

func _apply(value: Dictionary) -> void:
	if received and int(value.revision) < int(snapshot_state.get("revision", -1)): return
	var first := not received
	snapshot_state = value.duplicate(true); received = true
	geometry.apply_snapshot(snapshot_state, not first)
	if not multiplayer.is_server(): timer.stop()

@rpc("any_peer", "call_remote", "reliable", 4)
func _sync_request() -> void:
	if not multiplayer.is_server(): return
	var peer := multiplayer.get_remote_sender_id()
	var now := Time.get_ticks_msec()
	var key := -peer
	if now - int(request_times.get(key, -1000)) < 800: return
	request_times[key] = now
	if game.session.roster.has(peer): _snapshot.rpc_id(peer, state.snapshot())

func _roster_changed() -> void:
	if leaving_session: return
	if multiplayer.is_server():
		for peer in state.riders.keys():
			if not game.session.roster.has(peer): state.forget(int(peer))
		_publish()
	else:
		received = false; timer.wait_time = 1.0; timer.start()

func _left(peer: int) -> void:
	request_times.erase(peer)
	request_times.erase(-peer)
	if not leaving_session and multiplayer.is_server(): state.forget(peer); _publish()

func _session_leaving() -> void:
	# Capture the OLD local ID before Session.leave swaps ENet for offline peer 1.
	recovery_pending = snapshot_state.get("riders", {}).has(multiplayer.get_unique_id())
	leaving_session = true
	timer.stop()

func _reset() -> void:
	var was_locked: bool = recovery_pending or snapshot_state.get("riders", {}).has(multiplayer.get_unique_id())
	state = State.new(); snapshot_state.clear(); received = false; request_times.clear()
	recovery_pending = false; leaving_session = false
	# Session.leave already restores pose epochs/roster. Clear any local frozen cabin pose.
	if was_locked:
		integration._relocate(1, Vector3(14.5, 0.05, 59))
	timer.stop(); timer.wait_time = 0.1
	if multiplayer.is_server(): _publish()
	else: timer.wait_time = 1.0; timer.start()
