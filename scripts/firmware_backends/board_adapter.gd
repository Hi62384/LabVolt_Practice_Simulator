extends RefCounted
## Opt-in native board electrical adapter; no shared catalog mutation.
## Logical node order is NOT a physical board footprint. Integrator maps headers.
static func catalog() -> Dictionary:
	var uno_pins: Array=["VCC","GND"]
	for i in 14:uno_pins.append("D"+str(i))
	for i in 6:uno_pins.append("A"+str(i))
	var pico_pins: Array=["3V3","GND"]
	for i in 30:pico_pins.append("GP"+str(i))
	var models := {
		"uno":{"name":"Arduino Uno R3 · staged AVR machine code","kind":"native_firmware","board":"uno","pins":uno_pins,"logic_voltage":5.0,"power_min":4.5,"power_max":5.5,"format":"intel_hex","onboard_led":"D13","limits":"ATmega328P; external C/C++ compilation; no USB bridge"},
		"pico":{"name":"Raspberry Pi Pico · staged RP2040 machine code","kind":"native_firmware","board":"pico","pins":pico_pins,"logic_voltage":3.3,"power_min":3.0,"power_max":3.6,"format":"bin_base64","onboard_led":"GP25","limits":"Single core; external C/C++ compilation; no boot ROM/MicroPython/USB claim; GP23/24/25/29 are onboard signals, not headers"}
	}

	models.nano=models.uno.duplicate(true);models.nano.name="Arduino Nano · ATmega328P 16 MHz";models.nano.board="nano";models.nano.pins.append_array(["A6","A7"]);models.nano.limits="Classic 5V ATmega328P Nano only; A6/A7 analog-only; no Nano Every/33/ESP32 or USB bridge"
	return models

static func all() -> Dictionary:
	return catalog()

static func tick_request(model: Dictionary,nodes: Array,voltages: Dictionary,dt: float,run := true) -> Dictionary:
	if nodes.size()!=model.pins.size():return {"error":"Native board logical pin mapping mismatch"}
	var zero := float(voltages.get(nodes[1],0))
	var pins := {}
	for i in range(2,nodes.size()):pins[model.pins[i]]=float(voltages.get(nodes[i],0))-zero
	return {"op":"tick","vcc":float(voltages.get(nodes[0],0))-zero,"pins":pins,"dt":dt,"run":run}

static func expand(model: Dictionary,id: String,nodes: Array,_state: Dictionary,voltages: Dictionary={},runtime: Dictionary={}) -> Array:
	if nodes.size()!=model.pins.size():return []
	var current: Dictionary=runtime.get(id,{})
	var out: Array=[]
	# Approximate electrical impedances, not manufacturer-characterized drivers.
	# VCC here is the regulated logic rail; VIN/VSYS regulator simulation is external.
	for i in range(2,nodes.size()):
		var pin: String=model.pins[i]
		var driving: bool=current.get("powered",false) and current.get("outputs",{}).has(pin)
		var pull: String=str(current.get("pulls",{}).get(pin,"")) if current.get("powered",false) else ""
		var high: bool=float(current.get("outputs",{}).get(pin,0))>.5 if driving else pull=="up"
		out.append({"id":id+"/"+pin,"kind":"R","a":nodes[i],"b":nodes[0] if high else nodes[1],"value":40.0 if driving else (30000.0 if pull!="" else 1e12)})
	var vcc := float(voltages.get(nodes[0],0))-float(voltages.get(nodes[1],0))
	if vcc>=float(model.power_min) and vcc<=float(model.power_max):
		out.append({"id":id+"/power","kind":"R","a":nodes[0],"b":nodes[1],"value":1000.0})
	return out
