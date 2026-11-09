class_name DormEditService
extends RefCounted

const Edits = preload("res://scripts/campus/dorms/customization/room_edits.gd")

## Host-only adapter. Bind these to the integrated dorm authority and master
## inventory ledger; never expose this method as an RPC without deriving peer
## from multiplayer.get_remote_sender_id(). The commit callable must persist
## atomically and return false on save failure.
var authenticated_identity: Callable # (peer) -> stable identity or ""
var owner_of_room: Callable # (room_id) -> stable identity or ""
var room_side: Callable # (room_id) -> "west"/"east"
var read_room: Callable # (room_id) -> full saved customization
var commit_room: Callable # (room_id, expected_revision, state) -> bool
var eligible: Callable # (identity, intent, proposed_state) -> bool

func edit_for_peer(peer: int, room_id: String, expected_revision: int, intent: Dictionary) -> Dictionary:
	if not _ready() or peer <= 0 or room_id.is_empty(): return _error("unavailable")
	var identity := str(authenticated_identity.call(peer))
	if identity.is_empty() or str(owner_of_room.call(room_id)) != identity: return _error("owner_only")
	var saved: Dictionary = read_room.call(room_id)
	if saved.is_empty(): return _error("room_unavailable")
	var revision := int(saved.get("revision", -1))
	if revision != expected_revision: return {"ok":false, "error":"stale_revision", "state":saved.get("customization", {}), "revision":revision}
	var current: Dictionary = saved.get("customization", {})
	var check := func(candidate: Dictionary, proposed: Dictionary) -> bool:
		return bool(eligible.call(identity, candidate, proposed))
	var applied: Dictionary = Edits.apply(current, intent, str(room_side.call(room_id)), check)
	if not applied.ok: return {"ok":false, "error":applied.error, "state":current, "revision":revision}
	var proposed := saved.duplicate(true)
	proposed.customization = applied.state
	proposed.revision = revision + 1
	if not bool(commit_room.call(room_id, revision, proposed)):
		return {"ok":false, "error":"save_failed", "state":current, "revision":revision}
	return {"ok":true, "state":proposed.customization, "revision":proposed.revision}

func _ready() -> bool:
	return authenticated_identity.is_valid() and owner_of_room.is_valid() and room_side.is_valid() and read_room.is_valid() and commit_room.is_valid() and eligible.is_valid()

func _error(message: String) -> Dictionary:
	return {"ok":false, "error":message}
