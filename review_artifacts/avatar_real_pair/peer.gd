extends SceneTree
## Actual Main/Session/InventoryAuthority; runner must isolate APPDATA per role.
var game: Node
var role := "host"
var port := 26148
var failures := 0
var deadline := 0
const CLIENT_ID := "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
func check(value: bool, label: String) -> void:
	if not value: failures += 1; printerr("FAIL AVATAR_PAIR ", role, " ", label)
func until(predicate: Callable) -> bool:
	while Time.get_ticks_msec() < deadline:
		if predicate.call(): return true
		await create_timer(.05).timeout
	return false
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	role = args[0]
	if args.size() > 1: port = int(args[1])
	deadline = Time.get_ticks_msec() + 35000
	game = load("res://scenes/Main.tscn").instantiate(); root.add_child(game)
	for frame in 4: await process_frame
	game.characters.selected = "avatar-pair-" + ("host" if role == "host" else "client")
	game.electronics.profile.open(game.characters.selected)
	game.school.local_identity = "a".repeat(48) if role == "host" else CLIENT_ID
	var authority: Node = game.electronics_trade.authority
	if role == "host":
		game.electronics.profile.data.owned_cosmetics = ["shoes.velocity_runner"]
		game.electronics.profile.data.avatar_cosmetics = {"version":1,"body":{"height":1.25,"width":.8},"equipped":{"footwear":{"id":"shoes.velocity_runner","parameters":{}}}}
		check(game.electronics.profile.save() == OK, "host synthetic profile saved")
		check(game.session.host_game("AvatarHost", port) == OK, "host opened")
		game.school.start("Freeplay",0)
		check(await until(func(): return authority.ledger.bindings.values().has(CLIENT_ID)), "first client authenticated through production handshake")
		var first_peer := 0
		for key in authority.ledger.bindings:
			if authority.ledger.bindings[key] == CLIENT_ID: first_peer = int(key)
		check(await until(func(): return not authority.ledger.bindings.has(first_peer)), "first client disconnected and unbound")
		check(await until(func(): return authority.ledger.bindings.values().has(CLIENT_ID)), "stable client reauthenticated")
		var second_peer := 0
		for key in authority.ledger.bindings:
			if authority.ledger.bindings[key] == CLIENT_ID: second_peer = int(key)
		check(first_peer != second_peer, "reconnect uses new peer ID")
		await create_timer(2).timeout
	else:
		check(game.session.join_game("127.0.0.1","AvatarClient",port) == OK, "client opened")
		check(await until(func(): return authority.bound), "production inventory registration acknowledged")
		check(await until(func(): return game.cosmetic_appearances.has(1)), "late join receives host appearance")
		if game.cosmetic_appearances.has(1):
			var appearance: Dictionary = game.cosmetic_appearances[1]
			check(appearance.body.height == 1.25 and appearance.equipped.footwear.id == "shoes.velocity_runner", "host body and item match")
			check(not appearance.has("dollars") and var_to_bytes(appearance).size() < 65536, "compact public payload")
		var before: Dictionary = game.electronics.profile.data.duplicate(true)
		var outcomes: Array = []
		authority.operation_result.connect(func(_op: String, result: Dictionary): outcomes.append(result))
		authority.submit("avatar_cosmetic",[{"op":"equip","id":"missing.item","parameters":{}}])
		check(await until(func(): return outcomes.size() == 1), "invalid ID response arrives")
		check(not outcomes.is_empty() and not outcomes[0].get("ok",true), "invalid ID rejected by host")
		authority.submit("avatar_cosmetic",[{"op":"equip","id":"shoes.ionstep","parameters":{}}])
		check(await until(func(): return outcomes.size() == 2), "unowned response arrives")
		check(outcomes.size() == 2 and not outcomes[1].get("ok",true), "unowned ID rejected by host")
		check(game.electronics.profile.data == before, "rejected appearance preserves client profile")
		if role == "client":
			game.session.leave()
			await create_timer(.7).timeout
			check(game.session.join_game("127.0.0.1","AvatarClient",port) == OK, "reconnect opened")
			check(await until(func(): return authority.bound and game.cosmetic_appearances.has(1)), "reconnect restores compact host appearance")
			check(game.school.local_identity == CLIENT_ID, "stable selected profile identity retained")
		await create_timer(.5).timeout
	print("AVATAR_REAL_PAIR ", role, " failures=", failures)
	game.session.leave()
	quit(1 if failures else 0)
