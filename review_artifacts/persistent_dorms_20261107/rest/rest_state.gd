extends RefCounted
## Host-only transient occupancy. Identity remains owned by dorm authority.
var beds := {}
var resting := {}
var revisions := {}

func register_bed(room: String, anchor: Transform3D) -> bool:
	if room.is_empty() or not anchor.is_finite() or beds.has(room): return false
	beds[room]=anchor
	return true

func begin(peer: int, room: String, position: Vector3, authority: Object, roster: Dictionary, busy: bool) -> Dictionary:
	if not roster.has(peer) or busy or resting.has(peer) or not beds.has(room): return {"ok":false}
	var identity: String=authority.authenticated_identity(peer)
	# Beds are owner-only even when the room admits visitors.
	if identity.is_empty() or not authority.can_enter(identity,room) or not authority.is_owner(identity,room): return {"ok":false}
	for state in resting.values():
		if state.room==room:return {"ok":false}
	var anchor: Transform3D=beds[room]
	if not position.is_finite() or position.distance_to(anchor.origin)>3.0:return {"ok":false}
	revisions[peer]=int(revisions.get(peer,0))+1
	var state := {"room":room,"anchor":anchor,"return_position":position,"revision":revisions[peer]}
	resting[peer]=state
	return {"ok":true,"state":state.duplicate(true)}

func end(peer: int, destination: Variant) -> Dictionary:
	# The host must supply a collision-checked standing location; blocked exits
	# retain occupancy and permit an immediate retry, never a forced timer.
	if not resting.has(peer) or not destination is Vector3 or not destination.is_finite():return {"ok":false}
	resting.erase(peer);revisions[peer]=int(revisions.get(peer,0))+1
	return {"ok":true,"position":destination,"revision":revisions[peer]}

func disconnect(peer: int) -> void:
	resting.erase(peer);revisions.erase(peer)

func clear() -> void:
	resting.clear();revisions.clear();beds.clear()
