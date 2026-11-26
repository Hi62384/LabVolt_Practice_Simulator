extends SceneTree

const Spawn := Vector3(0, 150, 0)
const Throw = preload("res://scripts/campus/items/item_throw.gd")
const Config = preload("res://scripts/campus/items/equipment_configuration.gd")
var game: Node
var port: int

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var args := OS.get_cmdline_user_args()
	port = int(args[1])
	var host := args[0] == "host"
	create_timer(45).timeout.connect(func():push_error("Item throw test timed out");quit(1))
	assert(Throw.throw_speed(1.0, 0.0, 2.0) > Throw.throw_speed(.25, 0.0, 2.0))
	assert(Throw.throw_speed(1.0, .75, 2.0) > Throw.throw_speed(1.0, 0.0, 2.0))
	assert(Throw.throw_speed(1.0, .75, 2.0) > Throw.throw_speed(1.0, .75, 15.0))
	var configuration := Config.defaults(Config.CALCULATOR,2)
	assert(configuration.keypad == Config.Keypad.REQUIRED)
	assert(Config.quote(Config.CALCULATOR, 42, configuration).price == 42)
	configuration.keypad = ["+"]
	var migrated := Config.quote(Config.CALCULATOR, 42, configuration)
	assert(migrated.price == 44 and migrated.configuration.keypad == ["+"] + Config.Keypad.REQUIRED)

	game = load("res://scenes/Main.tscn").instantiate()
	root.add_child(game)
	for frame in 4:await process_frame
	var floor := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(80, 1, 80)
	collision.shape = shape
	floor.add_child(collision)
	game.add_child(floor)
	floor.position = Spawn - Vector3.UP * .5
	if host:
		assert(game.session.host_game("Host", port) == OK)
		while game.session.roster.size() < 2:await process_frame
		var remote := int(game.session.roster.keys().filter(func(peer):return peer != 1)[0])
		game.session.poses[remote] = {"position":Spawn,"yaw":0.0,"pitch":0.0,"crouch":false}
		var weights: Node = game.gym_weights
		weights.items[0].owner = remote
		weights.items[0].where = "held"
		weights._publish()
		while weights.items[0].where != "floor":await process_frame
		var distance: float = weights.items[0].position.distance_to(Spawn)
		assert(distance > 3.5, "A full throw should exceed ordinary placement reach")
		print("REMOTE_THROW_HOST PASS ", distance)
		await create_timer(.25).timeout
	else:
		assert(game.session.join_game("127.0.0.1", "Thrower", port) == OK)
		while game.session.roster.size() < 2 or game.gym_weights.held_id(game.multiplayer.get_unique_id()) != 0:
			await process_frame
		var service: Node = game.item_throw
		var peer: int = game.multiplayer.get_unique_id()
		service._send_charge("begin", "weight:0")
		await create_timer(1.25).timeout
		service._send_charge("release", "weight:0")
		while not service.flights.has(peer):await process_frame
		while game.gym_weights.items[0].where != "floor":await process_frame
		var distance: float = game.gym_weights.items[0].position.distance_to(Spawn)
		assert(distance > 3.5)
		print("REMOTE_THROW_CLIENT PASS ", distance)
	quit()
