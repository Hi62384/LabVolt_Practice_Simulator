extends SceneTree

class CountingSolver extends "res://scripts/circuit_solver.gd":
	var calls := 0
	func solve(terminals: Array, leads: Array, switches: Dictionary, powered: bool, variable_level: float, dynamometer_load: float = 0.0, motor_slip := 0.05, iteration := 0) -> Dictionary:
		calls += 1
		return super.solve(terminals, leads, switches, powered, variable_level, dynamometer_load, motor_slip, iteration)

func _initialize() -> void:
	var lab = preload("res://scripts/lab_state.gd").new()
	var solver := CountingSolver.new()
	lab.solver = solver
	lab.initialize(["P_A", "P_N", "V0_150", "V0_COM"], {"storage": Vector3.ZERO, "P_A": Vector3.UP, "V0_150": Vector3.UP, "power": Vector3.ZERO})
	var initial_calls := solver.calls
	var initial_readings: Dictionary = lab.readings.duplicate(true)
	assert(lab.act(1, {"op":"drawer"}, Vector3.ZERO).is_empty())
	assert(lab.act(1, {"op":"pickup", "color":0}, Vector3.ZERO).is_empty())
	assert(solver.calls == initial_calls and lab.readings == initial_readings)
	assert(lab.act(1, {"op":"plug", "port":"P_A"}, Vector3.ZERO).is_empty())
	assert(lab.act(1, {"op":"plug", "port":"V0_150"}, Vector3.ZERO).is_empty())
	assert(solver.calls == initial_calls + 2)
	assert(lab.act(1, {"op":"power"}, Vector3.ZERO).is_empty())
	assert(solver.calls == initial_calls + 3 and lab.powered)
	print("PASS AC non-electrical actions skip solving; wiring and power recalculate")
	quit()
