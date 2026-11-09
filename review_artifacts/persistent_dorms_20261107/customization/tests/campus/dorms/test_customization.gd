extends SceneTree

const Rules = preload("res://scripts/campus/dorms/customization/placement_rules.gd")
const Edits = preload("res://scripts/campus/dorms/customization/room_edits.gd")
const Service = preload("res://scripts/campus/dorms/customization/edit_service.gd")

func _initialize() -> void:
	var owned := func(intent: Dictionary, _state: Dictionary) -> bool:
		if intent.get("op") == "style": return intent.get("variant") in ["classic", "tile", "teal", "oak"]
		return str(intent.get("item", {}).get("id", "")) in ["owned:bed", "owned:rug"]
	var empty := {"items":[], "styles":{}}
	var bed := {"id":"owned:bed", "kind":"bed", "x":-1.8, "z":-2.5, "rotation":0}
	assert(Rules.validate([bed], "west") == "")
	var placed: Dictionary = Edits.apply(empty, {"op":"place", "item":bed}, "west", owned)
	assert(placed.ok and placed.state.items.size() == 1)
	assert(not Edits.apply(placed.state, {"op":"place", "item":bed}, "west", owned).ok)
	assert(not Edits.apply(empty, {"op":"place", "item":{"id":"unowned", "kind":"bed", "x":0.0, "z":0.0, "rotation":0}}, "west", owned).ok)
	assert(not Edits.apply(empty, {"op":"place", "item":{"id":"owned:bed", "kind":"bed", "x":-2.7, "z":0.0, "rotation":0}}, "west", owned).ok)
	assert(not Edits.apply(empty, {"op":"place", "item":{"id":"owned:bed", "kind":"bed", "x":3.1, "z":0.0, "rotation":0}}, "west", owned).ok)
	assert(not Edits.apply(empty, {"op":"style", "category":"wall", "variant":"sage"}, "west", owned).ok)
	assert(Edits.apply(empty, {"op":"style", "category":"wall", "variant":"classic"}, "west", owned).ok)
	var moved: Dictionary = Edits.apply(placed.state, {"op":"move", "item":{"id":"owned:bed", "kind":"bed", "x":-1.7, "z":-2.3, "rotation":1}}, "west", owned)
	assert(moved.ok and moved.state.items[0].rotation == 1)
	var picked: Dictionary = Edits.apply(moved.state, {"op":"pickup", "id":"owned:bed"}, "west", owned)
	assert(picked.ok and picked.state.items.is_empty())
	assert(placed.state.items.size() == 1) # old snapshot remains intact
	var durable := {"revision":1, "customization":empty.duplicate(true)}
	var service := Service.new()
	service.authenticated_identity = func(peer: int): return "owner" if peer == 1 else "visitor"
	service.owner_of_room = func(_room: String): return "owner"
	service.room_side = func(_room: String): return "west"
	service.read_room = func(_room: String): return durable.duplicate(true)
	service.eligible = func(_identity: String, candidate: Dictionary, proposed: Dictionary): return owned.call(candidate, proposed)
	service.commit_room = func(_room: String, revision: int, proposed: Dictionary):
		if revision != durable.revision: return false
		durable = proposed.duplicate(true)
		return true
	assert(service.edit_for_peer(2, "room", 1, {"op":"place", "item":bed}).error == "owner_only")
	assert(durable.revision == 1)
	assert(service.edit_for_peer(1, "room", 0, {"op":"place", "item":bed}).error == "stale_revision")
	assert(service.edit_for_peer(1, "room", 1, {"op":"place", "item":bed}).ok)
	assert(durable.revision == 2 and durable.customization.items.size() == 1)
	service.commit_room = func(_room: String, _revision: int, _proposed: Dictionary): return false
	assert(service.edit_for_peer(1, "room", 2, {"op":"pickup", "id":"owned:bed"}).error == "save_failed")
	assert(durable.customization.items.size() == 1)
	quit()
