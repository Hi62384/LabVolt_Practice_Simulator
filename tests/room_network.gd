extends SceneTree
var game: Node
var failures := 0
func check(value: bool,label: String) -> void:
	if not value:
		failures+=1
		printerr("FAIL ROOM: "+label)
	else:
		print("PASS ROOM: "+label)
func wait(t: float) -> void:
	await create_timer(t).timeout
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	game=load("res://scenes/Main.tscn").instantiate()
	root.add_child(game)
	await wait(.3)
	var role: String=OS.get_cmdline_user_args()[0]
	if role=="host":
		game.capture()
		var room: Dictionary=game.school.room_bridge.room("ELM253","lecture")
		var seat: Vector3=game.school.room_bridge.point(room.seats[0])
		var desk: Vector3=game.school.room_bridge.point(room.desks[0])
		var lecture_chair: CharacterBody3D
		for chair in game.chairs:
			if chair.global_position.distance_to(seat)<.08:
				lecture_chair=chair
				break
		if lecture_chair == null:
			check(false,"found lecture chair")
		else:
			var toward_desk := Vector3(desk.x-seat.x,0.,desk.z-seat.z)
			var empty_fits := not lecture_chair.test_move(lecture_chair.global_transform,toward_desk)
			lecture_chair.occupant=1
			await physics_frame
			await physics_frame
			check(empty_fits and lecture_chair.test_move(lecture_chair.global_transform,toward_desk),"occupied chair collides with the lecture desk")
			lecture_chair.occupant=0
		game.chairs[0].position=Vector3(0,0,1)
		game.session.labs[2].act(1,{"op":"switch","kind":"L","index":2,"expected":false},game.session.labs[2].positions.L_2)
		check(game.session.host_game("Host",24907)==OK,"host started")
		var claimed := false
		var moved := false
		var turned := false
		for i in range(350):
			await wait(.05)
			claimed=claimed or game.chairs[0].occupant!=0
			moved=moved or game.chairs[0].position.distance_to(Vector3(0,0,1))>.25
			turned=turned or absf(game.chairs[0].swivel.rotation.y)>.25
		check(claimed,"remote chair ownership arrived")
		check(moved and turned,"remote input rolls and swivels host physics")
		check(game.chairs[0].occupant==0,"remote stand releases chair")
	else:
		var address := OS.get_environment("LABVOLT_TEST_HOST")
		check(game.session.join_game(address if not address.is_empty() else "127.0.0.1","Guest",24907)==OK,"client started")
		for i in range(50):
			await wait(.05)
			if game.session.roster.size()==2:
				break
		await wait(.2)
		check(game.station_snapshots.size()==3 and game.station_snapshots[2].switches.L[2],"late join receives third bench state")
		game.player.position=Vector3(0,0,2)
		for i in range(90):
			game.session.send_pose({"position":game.player.position})
			await wait(.05)
			var pose: Vector3=game.session.poses.get(game.multiplayer.get_unique_id(),{}).get("position",Vector3.INF)
			if pose.distance_to(Vector3(0,0,1))<2:break
		game._request_chair(0)
		for i in range(100):
			await wait(.05)
			if game.player.seated==game.chairs[0]:break
		check(game.player.seated==game.chairs[0],"client seated after host claim")
		game.set_physics_process(false)
		for i in range(50):
			game._chair_input.rpc_id(1,0,Vector2(0,-1),i*.008)
			await wait(.05)
		check(game.chairs[0].network_target.distance_to(Vector3(0,0,1))>.25,"client receives moving chair")
		game._stand_from_chair()
		await wait(.4)
		check(game.player.seated==null and game.chairs[0].occupant==0,"client stays standing after updates")
	print("ROOM NETWORK %s: %d failures"%[role,failures])
	quit(1 if failures else 0)
