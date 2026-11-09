class_name DormOwnershipAuthority
extends RefCounted

## Pure host-owned dorm lifecycle state. Peer IDs come from the authenticated
## session roster; this class never accepts a player identity from a payload.
const MAX_REQUEST_BYTES := 256
const MIN_REQUEST_INTERVAL_MS := 100
const MAX_REPLAY_ENTRIES := 32

var session_epoch := 0
var capacity := 0
var room_ids: Array[String] = []
var assignments: Dictionary = {} # authenticated peer -> stable room id
var occupants: Dictionary = {} # stable room id -> authenticated peer
var doors: Dictionary = {} # stable room id -> open bool
var last_request_ms: Dictionary = {}
var highest_sequence: Dictionary = {}
var replay_results: Dictionary = {}
var revision := 0

func configure(stable_room_ids: Array, max_players: int, epoch: int) -> Dictionary:
	if max_players <= 0 or stable_room_ids.size() != max_players:
		return _error("room_count_must_match_capacity")
	var seen := {}
	var clean: Array[String] = []
	for value in stable_room_ids:
		var room_id := str(value).strip_edges()
		if room_id.is_empty() or room_id.length() > 64 or seen.has(room_id):
			return _error("invalid_room_ids")
		seen[room_id] = true
		clean.append(room_id)
	capacity = max_players
	room_ids = clean
	session_epoch = epoch
	assignments.clear(); occupants.clear(); doors.clear()
	last_request_ms.clear(); highest_sequence.clear(); replay_results.clear()
	for room_id in room_ids: doors[room_id] = false
	revision += 1
	return {"ok":true,"snapshot":snapshot()}

func join_authenticated(peer: int) -> Dictionary:
	if peer <= 0 or capacity <= 0: return _error("invalid_session")
	if assignments.has(peer):
		return {"ok":true,"room_id":assignments[peer],"changed":false}
	for room_id in room_ids:
		if not occupants.has(room_id):
			assignments[peer] = room_id
			occupants[room_id] = peer
			doors[room_id] = false
			revision += 1
			return {"ok":true,"room_id":room_id,"changed":true}
	return _error("capacity_full")

func leave_authenticated(peer: int) -> Dictionary:
	if not assignments.has(peer): return {"ok":true,"changed":false}
	var room_id: String = assignments[peer]
	assignments.erase(peer); occupants.erase(room_id); doors[room_id] = false
	last_request_ms.erase(peer); highest_sequence.erase(peer); replay_results.erase(peer)
	revision += 1
	return {"ok":true,"room_id":room_id,"changed":true}

func reconcile_authenticated_peers(peers: Array) -> Dictionary:
	var present := {}
	for value in peers:
		var peer := int(value)
		if peer > 0: present[peer] = true
	var changed := false
	for value in assignments.keys():
		var peer := int(value)
		if not present.has(peer): changed = leave_authenticated(peer).changed or changed
	var ordered: Array = present.keys()
	ordered.sort()
	for value in ordered:
		var result := join_authenticated(int(value))
		if not result.ok: return result
		changed = bool(result.changed) or changed
	return {"ok":true,"changed":changed,"snapshot":snapshot()}

func request_door(peer: int, request: Dictionary, now_ms: int) -> Dictionary:
	if not assignments.has(peer): return _error("unassigned_peer")
	if var_to_bytes(request).size() > MAX_REQUEST_BYTES: return _error("request_too_large")
	if int(request.get("epoch",-1)) != session_epoch: return _error("stale_session")
	var sequence := int(request.get("sequence",-1))
	if sequence < 0: return _error("invalid_sequence")
	var peer_replays: Dictionary = replay_results.get(peer,{})
	if peer_replays.has(sequence): return peer_replays[sequence].duplicate(true)
	if sequence <= int(highest_sequence.get(peer,-1)): return _error("stale_sequence")
	if now_ms - int(last_request_ms.get(peer,now_ms-MIN_REQUEST_INTERVAL_MS)) < MIN_REQUEST_INTERVAL_MS:
		return _error("rate_limited")
	if typeof(request.get("open")) != TYPE_BOOL: return _error("invalid_door_state")
	var room_id: String = assignments[peer]
	# The room is derived from authenticated sender ownership. A forged room ID
	# cannot redirect an action to another participant's door.
	if request.has("room_id") and str(request.room_id) != room_id: return _error("not_owner")
	doors[room_id] = bool(request.open)
	highest_sequence[peer] = sequence
	last_request_ms[peer] = now_ms
	revision += 1
	var result := {"ok":true,"room_id":room_id,"open":doors[room_id],"sequence":sequence,"revision":revision}
	peer_replays[sequence] = result.duplicate(true)
	while peer_replays.size() > MAX_REPLAY_ENTRIES: peer_replays.erase(peer_replays.keys().min())
	replay_results[peer] = peer_replays
	return result

func may_enter(room_id: String) -> bool:
	# Entry is deliberately independent of ownership and private-data access.
	return doors.get(room_id,false) == true

func room_for(peer: int) -> String:
	return str(assignments.get(peer,""))

func snapshot() -> Dictionary:
	var compact_assignments: Array = []
	var ordered_peers: Array = assignments.keys(); ordered_peers.sort()
	for peer in ordered_peers: compact_assignments.append([int(peer),str(assignments[peer])])
	var open_doors: Array[String] = []
	for room_id in room_ids:
		if doors.get(room_id,false): open_doors.append(room_id)
	return {"schema":1,"epoch":session_epoch,"revision":revision,"capacity":capacity,"assignments":compact_assignments,"open_doors":open_doors}

func _error(message: String) -> Dictionary:
	return {"ok":false,"error":message}
