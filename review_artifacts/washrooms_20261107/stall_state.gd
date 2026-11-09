extends RefCounted
## Deterministic host rules. The caller supplies a trusted peer position.
const CENTERS := [-6.8, -2.6, 1.6, 5.8]
var rooms := {}

func _key(room: String, stall: int) -> String:
	return room + ":" + str(stall)

func state(room: String, stall: int) -> Dictionary:
	return rooms.get(_key(room, stall), {"open": true, "owner": 0}).duplicate()

func act(room: String, stall: int, action: String, peer: int, local_position: Vector3) -> Dictionary:
	if room not in ["washroom_1", "washroom_2"] or stall < 0 or stall >= CENTERS.size() or peer < 1:
		return {"ok": false, "reason": "invalid target"}
	var key := _key(room, stall)
	var value := state(room, stall)
	var x: float = CENTERS[stall]
	var inside := absf(local_position.x - x) < 1.45 and local_position.z > 2.7 and local_position.z < 5.65
	var near_door := absf(local_position.x - x) < 1.45 and local_position.z > 1.35 and local_position.z < 3.55
	if not inside and not near_door:
		return {"ok": false, "reason": "out of reach"}
	match action:
		"lock":
			if not inside or value.open or (value.owner != 0 and value.owner != peer): return {"ok": false, "reason": "lock requires closed door and occupant"}
			value.owner = peer
		"unlock":
			if not inside or value.owner != peer: return {"ok": false, "reason": "only occupant can unlock"}
			value.owner = 0
		"toggle":
			if value.owner != 0: return {"ok": false, "reason": "occupied"}
			value.open = not value.open
		"flush":
			if not inside: return {"ok": false, "reason": "enter stall first"}
			return {"ok": true, "state": value, "effect": "flush"}
		_:
			return {"ok": false, "reason": "unknown action"}
	rooms[key] = value
	return {"ok": true, "state": value}

func release_peer(peer: int) -> Array[String]:
	var changed: Array[String] = []
	for key in rooms:
		if int(rooms[key].owner) == peer:
			rooms[key] = {"open": true, "owner": 0}
			changed.append(key)
	return changed
