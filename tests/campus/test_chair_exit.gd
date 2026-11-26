extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var game: Node=load("res://scenes/Main.tscn").instantiate()
	root.add_child(game)
	for frame in 5:await physics_frame
	game.session.roster[1]={}
	var chair: CharacterBody3D=game.chairs[0]
	for direction in [Vector3.RIGHT,Vector3.BACK,Vector3.LEFT]:
		for frame in 30:chair._roll_casters(chair.basis*direction*.03,1.0/60.0)
		for caster in chair.wheels:
			assert(caster.basis.z.dot(direction)>.999,"Caster did not turn toward travel")
			var wheel: MeshInstance3D=caster.get_child(0)
			assert(absf(wheel.basis.y.dot(Vector3.RIGHT))>.999,"Wheel tilted off its axle")
	var stopped_spin: float=chair.wheel_spin
	chair._roll_casters(Vector3.ZERO,1.0/60.0)
	assert(chair.wheel_spin==stopped_spin,"Stationary wheels should not roll")
	var point:=Vector3(13,5.05,77.0)
	chair.global_position=point
	game.player.global_position=point+Vector3(0,0,1.15)
	game._request_chair(0)
	if game.player.seated!=chair:
		push_error("Could not set up the rolling chair in the north corridor.")
		quit(1)
		return
	await physics_frame
	game._stand_from_chair()
	var feet: Vector3=game.player.global_position
	if game.player.seated!=null or chair.occupant!=0 or chair.rider!=null or game.player.collider.disabled or absf(feet.y-5.0)>.3:
		push_error("Standing in the north corridor failed or landed on a different floor.")
		quit(1)
		return
	game.queue_free()
	for frame in 3:await process_frame
	print("CHAIR_EXIT PASS")
	quit()
