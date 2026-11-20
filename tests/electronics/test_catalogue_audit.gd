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
	_check_led_ratings()
	_check_storage_and_flyback()
	_check_signal_transformer()
	_check_worker_controls()
	_check_invalid_wires()
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

# These numerical cases complement the all-catalog power-cycle smoke sweep.
# They're bounded educational-model checks, not manufacturer calibration.
func _check_led_ratings() -> void:
	for kind in ["led", "led_green", "led_blue", "led_yellow"]:
		var model: Dictionary = Catalog.simulation_entry(kind)
		var parts: Array = Devices.expand(model, "device", ["anode", "cathode"], {})
		parts.append_array([
			{"id":"drive", "kind":"V", "a":"positive", "b":"cathode", "value":5.0, "resistance":0.0},
			{"id":"series", "kind":"R", "a":"positive", "b":"anode", "value":220.0}
		])
		var result: Dictionary = Solver.new().solve(parts)
		var expected: float = (5.0-float(model.vf))/(220.0+float(model.ron))
		_check(kind, result.get("ok",false) and absf(float(result.get("i",{}).get("device",0.0))-expected)<0.00002, "forward 5 V current matches LED knee and series resistance")
		var reversed: Dictionary = parts[0].duplicate()
		reversed.a="cathode"
		reversed.b="anode"
		parts[0]=reversed
		result=Solver.new().solve(parts)
		_check(kind, result.get("ok",false) and absf(float(result.get("i",{}).get("device",0.0)))<0.0000001, "reverse connection blocks LED current")

func _check_storage_and_flyback() -> void:
	var solver := Solver.new()
	var parts: Array = [
		{"id":"drive", "kind":"V", "a":"s", "b":"ground", "value":5.0, "resistance":0.0},
		{"id":"feed", "kind":"R", "a":"s", "b":"p", "value":1000.0},
		{"id":"cap", "kind":"C", "a":"p", "b":"ground", "value":0.00001}
	]
	var result: Dictionary = {}
	for i in 200:
		result=solver.solve(parts,[],0.0001)
		if not result.get("ok",false):break
	var charged: float=float(result.get("drop",{}).get("cap",0.0))
	_check("capacitor",result.get("ok",false) and charged>3.0 and charged<5.0,"capacitor charges through resistor")
	parts=[
		{"id":"cap", "kind":"C", "a":"p", "b":"ground", "value":0.00001},
		{"id":"bleed", "kind":"R", "a":"p", "b":"ground", "value":1000.0}
	]
	for i in 100:
		result=solver.solve(parts,[],0.0001)
		if not result.get("ok",false):break
	var discharged: float=float(result.get("drop",{}).get("cap",0.0))
	_check("capacitor",result.get("ok",false) and discharged>0.0 and discharged<charged*0.6,"capacitor discharges after source removal")
	solver.reset()
	parts=[
		{"id":"drive", "kind":"V", "a":"s", "b":"ground", "value":5.0, "resistance":0.0},
		{"id":"feed", "kind":"R", "a":"s", "b":"p", "value":250.0},
		{"id":"coil", "kind":"L", "a":"p", "b":"ground", "value":0.2, "resistance":0.1}
	]
	for i in 300:
		result=solver.solve(parts,[],0.0001)
		if not result.get("ok",false):break
	var charged_current: float=float(result.get("i",{}).get("coil",0.0))
	_check("inductor",result.get("ok",false) and charged_current>0.019,"inductor stores current")
	# Disconnect the supply but leave a ground-to-p flyback loop through LED.
	parts=[
		{"id":"coil", "kind":"L", "a":"p", "b":"ground", "value":0.2, "resistance":0.1},
		{"id":"led", "kind":"LED", "a":"ground", "b":"x", "vf":1.8, "ron":10.0},
		{"id":"flyback", "kind":"R", "a":"x", "b":"p", "value":20.0}
	]
	result=solver.solve(parts,[],0.0001)
	_check("inductor",result.get("ok",false) and float(result.get("i",{}).get("led",0.0))>0.005 and float(result.get("i",{}).get("coil",0.0))>0.0 and float(result.get("i",{}).get("coil",0.0))<charged_current,"inductor powers correctly oriented flyback LED")

func _check_signal_transformer() -> void:
	var model: Dictionary=Catalog.simulation_entry("signal_transformer")
	var parts: Array=Devices.expand(model,"transformer",["p","ground","secondary_plus","secondary_minus"],{})
	_check("signal_transformer",parts.size()==2,"has independently connected coupled windings")
	if parts.size()!=2:return
	parts.append_array([
		{"id":"drive","kind":"V","a":"p","b":"ground","value":0.0,"resistance":0.0},
		{"id":"load","kind":"R","a":"secondary_plus","b":"secondary_minus","value":10000.0}
	])
	var solver:=Solver.new()
	var primary_energy:=0.0
	var secondary_energy:=0.0
	var result: Dictionary={}
	for index in 800:
		var drive: Dictionary=parts[2].duplicate()
		drive.value=5.0*sin(TAU*10.0*float(index)*0.0005)
		parts[2]=drive
		result=solver.solve(parts,[],0.0005)
		if not result.get("ok",false):break
		if index>=400:
			primary_energy+=pow(float(result.get("drop",{}).get("transformer/primary",0.0)),2)
			secondary_energy+=pow(float(result.get("drop",{}).get("transformer/secondary",0.0)),2)
	var ratio:=sqrt(secondary_energy/primary_energy) if primary_energy>0.0 else 0.0
	_check("signal_transformer",result.get("ok",false) and ratio>0.40 and ratio<0.56,"10 Hz isolated secondary approaches 2:1 voltage ratio")

func _check_worker_controls() -> void:
	var fuse: Dictionary=Catalog.simulation_entry("fuse0_1")
	var state: Dictionary=Library.tick(fuse,["a","b"],{},{},0.01,{"f/link":1.0},"f")
	var expanded: Array=Library.expand(fuse,"f",["a","b"],{},{},{"f":state})
	var link: Dictionary=expanded.filter(func(p):return p.id=="f/link").front()
	_check("fuse0_1",state.get("blown",false) and float(link.value)>=1e12,"overcurrent opens the non-resetting fuse")
	state=Library.tick(fuse,["a","b"],{},state,0.01,{"f/link":0.0},"f")
	_check("fuse0_1",state.get("blown",false),"fuse remains blown when current stops")
	var relay: Dictionary=Catalog.simulation_entry("relay5")
	var pins: Array=["coil_plus","coil_minus","common","nc","no"]
	state=Library.tick(relay,pins,{},{},0.02,{"r/coil":0.04},"r")
	expanded=Library.expand(relay,"r",pins,{},{},{"r":state})
	var nc: Dictionary=expanded.filter(func(p):return p.id=="r/nc").front()
	var no: Dictionary=expanded.filter(func(p):return p.id=="r/no").front()
	_check("relay5",state.get("closed",false) and float(nc.value)>1e10 and float(no.value)<0.1,"energized coil switches NC to NO")
	state=Library.tick(relay,pins,{},state,0.02,{"r/coil":0.0},"r")
	_check("relay5",not state.get("closed",true),"relay returns to NC after release delay")
	for kind in ["nmos","pmos","njfet","pjfet"]:
		var fet: Dictionary=Catalog.simulation_entry(kind)
		var sign: float=-1.0 if fet.polarity=="P" else 1.0
		var on_gate: float=sign*5.0 if fet.worker_model=="mosfet" else 0.0
		var off_gate: float=0.0 if fet.worker_model=="mosfet" else -sign*5.0
		var on: Array=Library.expand(fet,"fet",["drain","gate","source"],{},{"drain":sign,"gate":on_gate,"source":0.0})
		var off: Array=Library.expand(fet,"fet",["drain","gate","source"],{},{"drain":sign,"gate":off_gate,"source":0.0})
		var on_channel: Dictionary=on.filter(func(p):return p.id=="fet/channel").front()
		var off_channel: Dictionary=off.filter(func(p):return p.id=="fet/channel").front()
		_check(kind,float(on_channel.value)<1e4 and float(off_channel.value)>1e10,"channel responds to gate bias and polarity")

func _check_invalid_wires() -> void:
	var result: Dictionary=Solver.new().solve([{"id":"r","kind":"R","a":"p","b":"g","value":1000.0}],[[]])
	_check("circuit_input",not result.get("ok",false) and result.get("error","")=="Invalid wire connection.","invalid saved wire returns controlled error")
