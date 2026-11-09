extends SceneTree
## Run only in an isolated headless Godot process, never against the live game.

const Player = preload("res://tests/campus/chairs/acceptance/test_player.gd")
const Chair = preload("res://scripts/rolling_chair.gd")
var failures: Array[String] = []
var checks := 0
var world: Node3D
var player: CharacterBody3D
var chair: CharacterBody3D
var floor_body: StaticBody3D

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		printerr("CHAIR_ACCEPTANCE_FAIL: ", label)

func _initialize() -> void:
	call_deferred("run")

func make_box(name: String, center: Vector3, size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = name
	body.collision_layer = 1
	body.collision_mask = 1
	body.position = center
	var shape_node := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	shape_node.shape = shape
	body.add_child(shape_node)
	world.add_child(body)
	return body

func physics_settle() -> void:
	await physics_frame
	await physics_frame

func make_chair(at: Vector3) -> void:
	chair = Chair.new()
	chair.name = "ProductionRollingChair"
	chair.position = at
	chair.collision_layer = 1
	chair.collision_mask = 1
	var shape_node := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = 0.36
	shape.height = 0.56
	shape_node.shape = shape
	shape_node.position.y = 0.3
	chair.add_child(shape_node)
	var rider_shape := CapsuleShape3D.new()
	rider_shape.radius = .30
	rider_shape.height = .84
	var rider_collision := CollisionShape3D.new()
	rider_collision.shape = rider_shape
	rider_collision.position.y = .82
	rider_collision.disabled = true
	chair.add_child(rider_collision)
	chair.rider_collision = rider_collision
	var swivel := Node3D.new()
	chair.add_child(swivel)
	chair.swivel = swivel
	world.add_child(chair)
	chair.set_physics_process(false)

func run() -> void:
	world = Node3D.new()
	root.add_child(world)
	floor_body = make_box("Floor", Vector3(0,-0.1,0), Vector3(12,0.2,12))
	make_box("Table", Vector3(0,0.76,-0.7), Vector3(2.2,0.14,1.5))
	make_chair(Vector3.ZERO)
	player = Player.new()
	player.name = "ProductionFirstPerson"
	player.position = Vector3(0,0.03,1.3)
	world.add_child(player)
	player.set_physics_process(false)
	player.enabled = true
	player.sensitivity = 0.00225
	await physics_settle()

	for initial_yaw in [-2.4,0.0,2.8]:
		player.rotation.y = initial_yaw
		player.yaw_target = initial_yaw
		player.sit(chair)
		check(player.seated == chair and chair.rider == player, "production sit assigns rider")
		player.look(Vector2(-2000,2000))
		player._physics_process(0.016)
		check(is_equal_approx(player.seated_look.head_yaw,PI/2), "head yaw right clamp relative to chair")
		check(is_equal_approx(player.pitch_target,-1.46), "normal seated pitch clamp")
		check(absf(wrapf(player.rotation.y-chair.swivel.rotation.y,-PI,PI)-PI/2)<0.001, "world yaw follows chair plus head")
		var old_turn: float = player.seated_look.chair_turn
		player.test_ctrl_pressed = true
		player.look(Vector2(-200,0))
		player.test_ctrl_pressed = false
		chair._physics_process(0.016)
		var ctrl_ok: bool = is_equal_approx(player.seated_look.head_yaw,PI/2) and player.seated_look.chair_turn>old_turn
		if not ctrl_ok:
			printerr("CTRL_DIAG enabled=", player.enabled, " old_turn=", old_turn, " new_turn=", player.seated_look.chair_turn, " head=", player.seated_look.head_yaw, " chair_turn=", chair.turn_target)
		check(ctrl_ok, "Ctrl seam feeds chair turn without changing head offset")
		player.look(Vector2(100,0))
		check(player.seated_look.head_yaw<PI/2, "release Ctrl resumes from clamp without stored overrun")
		chair.swivel.rotation.y += 0.4
		player._physics_process(0.016)
		var expected_yaw: float = player.rotation.y
		player.stand_up()
		check(player.seated == null and chair.rider == null, "table-adjacent chair exits")
		check(absf(wrapf(player.yaw_target-expected_yaw,-PI,PI))<0.001, "stand preserves head world heading")
		check(not player.collider.disabled, "stand restores collider")
		player.global_position = Vector3(0,0.03,1.3)
		chair.swivel.rotation.y = 0.0
		chair.spin = 0.0
		chair.spin_goal = 0.0
		await physics_settle()

	# Invalidate the saved entry location after sitting; the radial search must
	# pick a different floor-supported, collision-free point.
	player.sit(chair)
	var entry_blocker := make_box("EntryBlocker", Vector3(0,0.8,1.3), Vector3(0.7,1.6,0.7))
	await physics_settle()
	player.stand_up()
	check(player.seated == null, "blocked entry falls back to radial candidate")
	check(player.global_position.distance_to(Vector3(0,0,1.3))>0.5, "blocked entry was not reused")
	check(player.global_position.y>-0.1 and player.global_position.y<0.2, "fallback remains on floor")
	entry_blocker.queue_free()
	await physics_settle()

	# No supported floor: failure must leave both sides seated and collision
	# disabled, so another attempt can succeed after the scene becomes safe.
	player.global_position = Vector3(0,0.03,1.3)
	player.sit(chair)
	floor_body.collision_layer = 0
	await physics_settle()
	player.stand_up()
	check(player.seated == chair and chair.rider == player and player.collider.disabled, "failed search keeps seat atomic")
	floor_body.collision_layer = 1
	await physics_settle()
	player.stand_up()
	check(player.seated == null and chair.rider == null, "retry succeeds after floor returns")

	if failures.is_empty():
		print("CHAIR_ACCEPTANCE_OK checks=", checks)
		quit(0)
	else:
		printerr("CHAIR_ACCEPTANCE_FAILED checks=", checks, " failures=", failures.size())
		quit(1)
