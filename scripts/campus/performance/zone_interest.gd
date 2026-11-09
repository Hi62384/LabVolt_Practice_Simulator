extends RefCounted
## Server-side opt-in predicate. Never use it to authorize a client command.
var distance_limit := 35.0

func is_relevant(peer: Dictionary, object: Dictionary) -> bool:
	if object.get("global", false):
		return true
	var peer_id: int = int(peer.get("id", -1))
	if peer_id >= 0 and (int(object.get("owner", -2)) == peer_id or peer_id in object.get("dependencies", [])):
		return true
	var session_id := str(object.get("session_id", ""))
	if not session_id.is_empty() and session_id == str(peer.get("session_id", "")):
		return true
	if object.get("dependency_only",false):
		return false
	var building := str(object.get("building", ""))
	var peer_building := str(peer.get("building", ""))
	if not building.is_empty() and not peer_building.is_empty() and building != peer_building:
		return false
	var zone := str(object.get("zone_id", ""))
	var peer_zone := str(peer.get("zone_id", ""))
	# Unknown metadata retains existing updates rather than hiding critical state.
	if zone.is_empty() or peer_zone.is_empty():
		return true
	if zone != peer_zone and zone not in peer.get("interest_zones", []):
		return false
	if object.get("room_scoped", false) and str(object.get("room_id", "")) == str(peer.get("room_id", "")):
		return true
	if object.get("position") is Vector3 and peer.get("position") is Vector3:
		return object.position.distance_squared_to(peer.position) <= distance_limit * distance_limit
	return true

func recipients(peers: Dictionary, object: Dictionary) -> Array:
	var result: Array = []
	for id in peers:
		var peer: Dictionary = peers[id].duplicate()
		peer.id = int(id)
		if is_relevant(peer, object):
			result.append(id)
	return result
