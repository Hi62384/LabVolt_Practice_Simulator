extends SceneTree
const Rules = preload("res://review_artifacts/washrooms_20261107/stall_state.gd")
var failures := 0

func _check(value: bool, label: String) -> void:
	if not value:
		failures += 1
		printerr(label)

func _initialize() -> void:
	var rules = Rules.new()
	for room in ["washroom_1", "washroom_2"]:
		var inside := Vector3(-6.8, 0, 3.4)
		var outside := Vector3(-6.8, 0, 1.9)
		_check(rules.state(room, 0).open, room + " starts open")
		_check(not rules.act(room, 0, "lock", 2, inside).ok, room + " cannot lock open door")
		_check(rules.act(room, 0, "toggle", 3, outside).ok, room + " closes")
		_check(rules.act(room, 0, "lock", 2, inside).ok, room + " occupant locks")
		_check(not rules.act(room, 0, "toggle", 3, outside).ok, room + " outsider cannot open locked door")
		_check(not rules.act(room, 0, "unlock", 3, outside).ok, room + " outsider cannot unlock")
		_check(not rules.act(room, 0, "unlock", 4, inside).ok, room + " other player cannot unlock")
		_check(rules.act(room, 0, "unlock", 2, inside).ok, room + " occupant unlocks")
		_check(rules.act(room, 0, "toggle", 2, inside).ok, room + " inside exit opens")
		_check(not rules.act(room, 0, "flush", 2, outside).ok, room + " flush inside only")
		_check(rules.act(room, 0, "flush", 2, inside).ok, room + " flush inside")
		_check(rules.act(room, 0, "toggle", 2, inside).ok, room + " close again")
		_check(rules.act(room, 0, "lock", 2, inside).ok, room + " relock")
	var changed := rules.release_peer(2)
	_check(changed.size() == 2, "disconnect releases both rooms")
	for room in ["washroom_1", "washroom_2"]:
		_check(rules.state(room, 0).open and rules.state(room, 0).owner == 0, room + " safely reopens")
	_check(not rules.act("washroom_3", 0, "toggle", 2, Vector3.ZERO).ok, "unknown room denied")
	_check(not rules.act("washroom_1", 4, "toggle", 2, Vector3.ZERO).ok, "unknown stall denied")
	print("Washroom state failures: ", failures)
	quit(1 if failures else 0)
