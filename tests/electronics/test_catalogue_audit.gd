extends SceneTree
## Exercises the built-in catalogue through the same expansion/solve/tick as a
## bench. Model-specific suites cover truth tables, timing and instrument UI.
const Catalog = preload("res://scripts/electronics_catalog.gd")
const Devices = preload("res://scripts/device_models.gd")
const IoDevices = preload("res://scripts/io_devices/devices.gd")
const Library = preload("res://scripts/component_models/library.gd")
const Stateful = preload("res://scripts/stateful_devices.gd")
const Solver = preload("res://scripts/electronics_solver.gd")
const DESCRIPTORS = ["controller", "io_device", "native_controller", "stateful"]
const TERMINALS = {
	"logic": [13, 6], "timer555": [7, 0], "flip74": [13, 6],
	"shift595": [15, 7], "spi_display": [0, 1], "controller": [0, 1],
	"opamp": [2, 3], "regulator": [0, 1], "io_bridge": [0, 1],
	"io_servo": [0, 1], "io_graphic": [0, 1], "io_pixels": [0, 1],
	"lm358": [7, 3], "lm324": [3, 10], "pca9685": [27, 13],
	"hd44780": [1, 0], "hd44780_20x4": [1, 0],
}
var failures := 0
var evaluated := 0

func _initialize() -> void:
	var catalogue := Catalog.all()
	for id: String in catalogue:
		_check_component(id, catalogue[id])
	_check_floating_logic()
	_check_analog_models()
	print("CATALOGUE_AUDIT %s (%d entries, %d states, %d failures)" %
		["PASS" if failures == 0 else "FAIL", catalogue.size(), evaluated, failures])
	quit(1 if failures else 0)

func _check_component(id: String, model: Dictionary) -> void:
	var pins: Array = model.pins
	_check(id, pins.size() >= 2 and not str(model.get("rating", "")).is_empty(), "documented footprint")
	_check(id, Catalog.simulation_entry(id) == model, "gameplay catalogue matches advertised device")
	var nodes: Array = []
	for pin in pins.size():
		nodes.append("p%02d" % pin)
	_check(id, Devices.expand(model, id, nodes.slice(0, -1), {}).is_empty(), "rejects truncated footprint")
	var power: Array = TERMINALS.get(model.get("worker_model", model.kind), [])
	if model.has("supply") and model.has("ground"):
		power = [int(model.supply), int(model.ground)]
	if model.kind == "native_controller":
		power = [pins.find("VSYS"), pins.find("GND3")] if model.board == "pico" else [pins.find("VIN"), pins.find("GND1")]
	if power.is_empty() and pins.size() > 2:
		for label in ["VCC", "VDD", "VDD1"]:
			if pins.has(label) and pins.has("GND"):
				power = [pins.find(label), pins.find("GND")]
				break
	if power.is_empty():
		power = [0, 1]

	var solver = Solver.new()
	var runtime := {}
	var voltages := {}
	for phase in ["disconnected", "startup", "powered", "shutdown", "shorted"]:
		var source_voltage := 5.0
		if model.has("vmin") and model.has("vmax"):
			source_voltage = (float(model.vmin) + float(model.vmax)) * .5
		if model.kind in ["ssd1306", "ili9341", "xpt2046", "native_controller"]:
			source_voltage = 3.3
		if model.kind == "native_controller" and model.board != "pico":
			source_voltage = 7.0
		var expanded := Devices.expand(model, id, nodes, {}, voltages, runtime)
		_check(id, not expanded.is_empty(), "produces a simulation model")
		var ids := {}
		var parts: Array = []
		if phase != "disconnected":
			parts.append({"id":"@fixture", "kind":"V", "a":nodes[power[0]],
				"b":nodes[power[1]], "value":0.0 if phase == "shutdown" else source_voltage,
				"resistance":100.0})
		for part: Dictionary in expanded:
			_check(id, not ids.has(part.id), "unique branch " + str(part.id))
			ids[part.id] = true
			if part.kind in DESCRIPTORS:
				continue
			for terminal in ["a", "b", "cp", "cn", "high"]:
				if part.has(terminal):
					var node := str(part[terminal])
					_check(id, node in nodes or node.begins_with(id + "/"), "valid " + terminal + " terminal")
			parts.append(part)
		var wires: Array = [[nodes[power[0]], nodes[power[1]]]] if phase == "shorted" else []
		var result: Dictionary = solver.solve(parts, wires, .0005)
		evaluated += 1
		_check(id, result.ok, "solver at %s (%s)" % [phase, result.get("error", "")])
		if not result.ok:
			continue
		voltages = result.v
		for field in ["v", "i", "drop"]:
			for value in result.get(field, {}).values():
				_check(id, is_finite(float(value)), "finite " + field + " result")
		_check_kirchhoff_current(id, parts, result.i, wires)
		for descriptor: Dictionary in expanded:
			if descriptor.kind == "io_device":
				runtime[id] = IoDevices.tick(descriptor, result, runtime.get(id, {}), .0005)
			elif descriptor.kind == "stateful":
				if str(descriptor.model).begins_with("worker:"):
					runtime[id] = Library.tick(model, nodes, voltages, runtime.get(id, {}), .0005, result.i, id)
				else:
					runtime[id] = Stateful.tick(descriptor.model, nodes, voltages, runtime.get(id, {}), .0005)
	solver.reset()

func _check_kirchhoff_current(id: String, parts: Array, currents: Dictionary, wires: Array) -> void:
	var balance := {}
	for part: Dictionary in parts:
		var a: String = part.a
		var b: String = part.b
		if not wires.is_empty():
			if a == wires[0][0]: a = wires[0][1]
			if b == wires[0][0]: b = wires[0][1]
		var current := float(currents.get(part.id, 0.0))
		balance[a] = float(balance.get(a, 0.0)) + current
		balance[b] = float(balance.get(b, 0.0)) - current
	for node: String in balance:
		_check(id, absf(float(balance[node])) < 1e-6, "current conservation at " + node)

func _check_floating_logic() -> void:
	var model := Catalog.simulation_entry("hc04")
	var nodes: Array = []
	for index in model.pins.size():
		nodes.append("p%02d" % index)
	var parts := Devices.expand(model, "part", nodes, {}, {"p06":-5.0, "p13":0.0})
	var output: Dictionary = parts.filter(func(part): return part.id == "part/out0").front()
	_check("hc04", output.b == "p13" and output.value == 40.0, "unconnected input follows local ground reference")
	parts = Devices.expand(model, "part", nodes, {}, {"p06":-5.0})
	output = parts.filter(func(part): return part.id == "part/out0").front()
	_check("hc04", output.value >= 1e12, "a floating supply remains unpowered")
	parts = Devices.expand(model, "part", nodes, {}, {"p13":5.0})
	output = parts.filter(func(part): return part.id == "part/out0").front()
	_check("hc04", output.value >= 1e12, "a floating ground remains unpowered")
	_check("timer555", not Stateful.tick("timer555", nodes.slice(0, 8), {"p00":-5.0}, {}, .0005).powered,
		"does not invent a 5 V power rail on an offset island")
	var logic := Catalog.simulation_entry("ls47")
	nodes.append_array(["p14", "p15"])
	_check("ls47", not Library.tick(logic, nodes, {"p07":-5.0}, {}, .0005).powered,
		"worker model does not invent a missing power rail")
	var bridge := {"id":"bridge", "model":"io_bridge", "nodes":nodes.slice(0, 6)}
	_check("io_bridge", not IoDevices.tick(bridge, {"ok":true, "v":{"p01":-5.0}}, {}, .0005).powered,
		"IO model does not invent a missing power rail")

func _check_analog_models() -> void:
	# Exact circuit equations for representative catalogue ratings, with a
	# 1 kΩ series resistor and a finite off-state conductance.
	for fixture in [
		["schottky", 5.0, (5.0 - .3) / 1001.0],
		["schottky", -5.0, 0.0],
		["zener5v1", -9.0, (-9.0 + 5.1) / 1005.0],
		["tvs12", 20.0, (20.0 - 12.7) / 1002.0],
		["tvs12", -20.0, (-20.0 + 12.7) / 1002.0],
		["polar_cap", -5.0, (-5.0 + .8) / 1033.0],
	]:
		var id: String = fixture[0]
		var parts := Devices.expand(Catalog.simulation_entry(id), "dut", ["positive", "return"], {})
		parts = parts.filter(func(part): return part.kind not in DESCRIPTORS)
		parts.append_array([
			{"id":"test_supply", "kind":"V", "a":"source", "b":"return",
				"value":fixture[1], "resistance":0.0},
			{"id":"feed", "kind":"R", "a":"source", "b":"positive", "value":1000.0},
		])
		var result: Dictionary = Solver.new().solve(parts)
		_check(id, result.ok and absf(result.i.feed - float(fixture[2])) < 1e-6,
			"loaded current at %s V" % fixture[1])
	for id in ["variable_cap", "variable_inductor"]:
		var model := Catalog.simulation_entry(id)
		var minimum: Dictionary = Devices.expand(model, "dut", ["one", "two"], {"setting":-.1})[0]
		var maximum: Dictionary = Devices.expand(model, "dut", ["one", "two"], {"setting":1.1})[0]
		_check(id, minimum.value == model.minimum and is_equal_approx(maximum.value, model.value),
			"physical adjustment is bounded at both advertised end stops")

func _check(id: String, condition: bool, label: String) -> void:
	if not condition:
		failures += 1
		printerr("FAIL ", id, " ", label)
