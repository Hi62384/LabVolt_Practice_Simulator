extends SceneTree
## Real Main.tscn + Session ENet + production ElevatorService. Runtime owner only.
## Two separate processes: -- host 19277 ; -- client 19277
var game: Node
var role := "host"
var port := 19277
var failures: Array[String] = []
var sent := false
var misuse_sent := false
func _initialize() -> void: call_deferred("run")
func check(value: bool, message: String) -> void:
	print("ELEVATOR_NET ", role, " ", "PASS " if value else "FAIL ", message)
	if not value: failures.append(message)
func wait_seconds(seconds: float) -> void: await create_timer(seconds).timeout
func run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0: role = args[0]
	if args.size() > 1: port = int(args[1])
	game = load("res://scenes/Main.tscn").instantiate(); root.add_child(game); current_scene = game
	await wait_seconds(2.0)
	game.player.enabled = false
	if role == "host":
		check(game.session.host_game("ElevatorFixtureHost", port) == OK, "real ENet host")
		await host_run()
	else:
		check(game.session.join_game("127.0.0.1", "ElevatorFixtureRider", port) == OK, "real ENet client")
		await client_run()
	print("ELEVATOR_NET_RESULT ", role, " failures=", failures.size())
	# No save/cache operations in the fixture. Main's normal lifecycle remains owner-guarded.
	quit(0 if failures.is_empty() else 1)
func host_run() -> void:
	var deadline := Time.get_ticks_msec() + 25000
	while game.session.roster.size() < 2 and Time.get_ticks_msec() < deadline: await wait_seconds(0.1)
	check(game.session.roster.size() == 2, "two actual registered peers")
	if game.session.roster.size() != 2: return
	var rider := 0
	for peer in game.session.roster:
		if int(peer) != 1: rider = int(peer)
	var integration: Node = game.campus_services
	var service: Node = integration.elevator_service
	integration._relocate(1, Vector3(16.65, 0.03, 59.0))
	integration._relocate(rider, Vector3(16.95, 0.03, 61.2))
	await wait_seconds(0.5)
	service.request(0, 1)
	await wait_seconds(2.0)
	check(service.state.phase == "open" and service.state.queue.has(1), "real doorway obstruction holds queued call")
	integration._relocate(1, Vector3(16.95, 0.03, 60.8))
	var observed_moving := false
	deadline = Time.get_ticks_msec() + 12000
	while Time.get_ticks_msec() < deadline:
		if service.state.phase == "moving":
			observed_moving = true
			check(service.state.riders.size() == 2, "host captures both real peers")
			break
		await wait_seconds(0.1)
	check(observed_moving, "departure after obstruction release")
	deadline = Time.get_ticks_msec() + 12000
	while not (service.state.floor_id == 1 and service.state.phase == "open") and Time.get_ticks_msec() < deadline: await wait_seconds(0.1)
	check(service.state.floor_id == 1 and service.state.phase == "open", "upper landing opens")
	check(absf(game.player.position.y - 5.0) < 0.2, "host arrived at actual upper floor")
	check(absf(float(game.session.poses.get(rider, {}).get("position", Vector3.ZERO).y) - 5.0) < 0.2, "remote peer arrived in same cabin")
	check(not service._local_locked() and service.state.riders.is_empty(), "host released after full opening")
	check(service.state.queue.is_empty(), "moving-state client misuse did not queue")
	service.request(1, 0)
	deadline = Time.get_ticks_msec() + 12000
	while not (service.state.floor_id == 0 and service.state.phase == "open") and Time.get_ticks_msec() < deadline: await wait_seconds(0.1)
	check(service.state.floor_id == 0 and service.state.phase == "open", "repeat return trip")
	check(absf(float(game.session.poses.get(rider, {}).get("position", Vector3(0, -100, 0)).y)) < 0.2, "remote rider returned too")
	# Allow client to observe release before host shutdown.
	await wait_seconds(2.0)
func client_run() -> void:
	var deadline := Time.get_ticks_msec() + 50000
	var saw_moving := false; var saw_upper := false; var saw_return := false
	while Time.get_ticks_msec() < deadline:
		var service: Node = game.campus_services.elevator_service
		var value: Dictionary = service.snapshot_state
		if not value.is_empty():
			if value.phase == "open" and int(value.floor) == 0 and game.player.position.x > 16.8 and not sent:
				# Concurrent request uses the real RPC and a host-positioned in-range rider.
				service.request(0, 1); sent = true
			if value.phase == "moving":
				saw_moving = true
				check(service._local_locked(), "remote rider frozen during transition")
				if not misuse_sent: service.request(int(value.floor), 0); misuse_sent = true
			if value.phase == "open" and int(value.floor) == 1:
				saw_upper = true
				check(absf(game.player.position.y - 5.0) < 0.2 and not service._local_locked(), "remote relocation and release match authoritative floor")
			if saw_upper and value.phase == "open" and int(value.floor) == 0:
				saw_return = true; break
		await wait_seconds(0.1)
	check(saw_moving and saw_upper and saw_return, "real RPC state/relocation observed in both directions")
