extends SceneTree

const Aux = preload("res://scripts/ac_auxiliary.gd")

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var game = load("res://scenes/Main.tscn").instantiate()
	root.add_child(game)
	for i in 4:await process_frame
	var state: Dictionary = game.session.lab.snapshot()
	state.powered = true
	state.readings.voltages = {"PV_A": Vector2(10, 0), "PV_B": Vector2(20, 0), "PV_C": Vector2(50, 0)}
	for test in [[11, "30.0 V AC"], [12, "40.0 V AC"]]:
		state.supply_meter = test[0]
		game._sync_supply_controls(game, state)
		assert(game.supply_display.text == test[1])
		var expected := deg_to_rad(135.0 - 270.0 * test[0] / 15.0)
		assert(absf(game.control_bodies.supply_meter.rotation.z - expected) < .0001)
	assert(Aux.SUPPLY_SELECTOR_LABELS[11] == "5-6" and Aux.SUPPLY_SELECTOR_LABELS[12] == "6-4")
	game.session.lab.supply_meter = 15
	var position: Vector3 = game.session.lab.positions.supply_meter
	assert(game.session.lab.act(1, {"op":"supply_meter", "delta":1}, position).is_empty())
	assert(game.session.lab.supply_meter == 0)
	print("PASS supply selector labels, variable phase measurements, dial position, and wrap")
	quit()
