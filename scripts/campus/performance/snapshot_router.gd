extends RefCounted
## Authoritative caller supplies canonical state dictionaries, never scene trees.
## Interest is a traffic decision; access control must happen before this adapter.
## Use a reliable ordered channel. On failed send call forget_peer before retrying.
## Unreliable traffic requires acknowledged baselines and is outside this adapter.
const Interest = preload("res://scripts/campus/performance/zone_interest.gd")
var interest := Interest.new()
var _previous: Dictionary = {}
var _pending: Dictionary = {}
var _next_token := 1

func build_patch(peer_id: int, peer: Dictionary, objects: Dictionary, force_full := false) -> Dictionary:
	# Compatibility API for callers that deliver synchronously. Network callers use
	# prepare_patch/commit_patch so a failed enqueue never advances their baseline.
	var prepared := prepare_patch(peer_id,peer,objects,force_full)
	commit_patch(peer_id,int(prepared.token))
	return prepared.patch

func prepare_patch(peer_id: int, peer: Dictionary, objects: Dictionary, force_full := false) -> Dictionary:
	var previous: Dictionary = _previous.get(peer_id, {})
	var next: Dictionary = {}
	var updates := {}
	var removed_fields := {}
	var entered: Array = []
	var left: Array = []
	var context := peer.duplicate()
	context.id = peer_id
	for id in objects:
		var object: Dictionary = objects[id]
		if not interest.is_relevant(context, object.get("meta", {})):
			continue
		var state: Dictionary = object.get("state", {})
		var fields := {}
		var removed: Array = []
		if not previous.has(id):
			entered.append(id)
		for key in state:
			if force_full or not previous.has(id) or not previous[id].has(key) or previous[id][key] != state[key]:
				fields[key] = state[key]
		if previous.has(id):
			for key in previous[id]:
				if not state.has(key):
					removed.append(key)
		if not fields.is_empty() or not previous.has(id):
			updates[id] = fields.duplicate(true)
		if not removed.is_empty():
			removed_fields[id] = removed
		next[id] = state.duplicate(true)
	for id in previous:
		if not next.has(id):
			left.append(id)
	var token := _next_token
	_next_token += 1
	_pending[peer_id] = {"token":token,"next":next}
	return {"token":token,"patch":{"updates": updates, "removed_fields": removed_fields, "entered_interest": entered, "left_interest": left}}

func commit_patch(peer_id: int, token: int) -> bool:
	if not _pending.has(peer_id) or int(_pending[peer_id].token)!=token:
		return false
	_previous[peer_id] = _pending[peer_id].next
	_pending.erase(peer_id)
	return true

func cancel_patch(peer_id: int) -> void:
	_pending.erase(peer_id)

func forget_peer(peer_id: int) -> void:
	_previous.erase(peer_id)
	_pending.erase(peer_id)

func clear() -> void:
	_previous.clear()
	_pending.clear()
