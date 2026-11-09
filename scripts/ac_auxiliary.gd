extends RefCounted
## Electrical model shared by the AC rack and the mixed-board transient solver.

const SUPPLY_PORTS := ["DC_7", "DC_N7", "DC_8", "DC_N8", "LOW_0", "LOW_1"]
const CONTROL_COMMON := "DAQ_DI2_N"
const LOGIC_THRESHOLD := 2.5

static func supplies(level: float) -> Array:
	return [
		{"a":"DC_7", "b":"DC_N7", "volts":120.0 * level, "amps":8.0, "dc":true},
		{"a":"DC_8", "b":"DC_N8", "volts":120.0, "amps":2.0, "dc":true},
		{"a":"LOW_0", "b":"LOW_1", "volts":24.0, "amps":3.0, "dc":false}
	]

static func daq_outputs(settings: Dictionary) -> Array:
	var outputs := []
	for i in 2:
		outputs.append({"a":"DAQ_AO%d"%i, "b":"DAQ_AO%d_N"%i, "volts":float(settings.get("AO%d"%i, 0.0)), "ohms":50.0})
		outputs.append({"a":"DAQ_DO%d"%i, "b":CONTROL_COMMON, "volts":5.0 if settings.get("DO%d"%i, false) else 0.0, "ohms":50.0})
	return outputs

static func impedances(damping: bool) -> Array:
	var parts := [{"a":"DYN_0", "b":"DYN_1", "id":"DYN_COIL", "ohms":120.0}]
	for i in 8:
		parts.append({"a":"DAQ_AI%d"%i, "b":CONTROL_COMMON, "id":"DAQ_AI%d"%i, "ohms":1000000.0})
	for i in 3:
		parts.append({"a":"DAQ_DI%d"%i, "b":"DAQ_DI%d_N"%i, "id":"DAQ_DI%d"%i, "ohms":100000.0})
	for input in ["IGBT_DISABLE", "IGBT_SYNC", "IGBT_GATE1", "IGBT_GATE2", "IGBT_GATE3", "IGBT_GATE4", "IGBT_GATE5", "IGBT_GATE6"]:
		parts.append({"a":input, "b":"IGBT_COMMON", "id":input, "ohms":10000.0})
	if damping:
		parts.append({"a":"IGBT_1", "b":"IGBT_2", "id":"IGBT_DAMP", "ohms":1000.0})
	return parts

static func switch_state(dc_volts: Dictionary) -> Dictionary:
	var common: Vector2 = dc_volts.get("IGBT_COMMON", Vector2.ZERO)
	var disabled: Vector2 = dc_volts.get("IGBT_DISABLE", Vector2.ZERO)
	var sync: Vector2 = dc_volts.get("IGBT_SYNC", Vector2.ZERO)
	var gates := []
	var blocked := []
	for leg in 3:
		var high: Vector2 = dc_volts.get("IGBT_GATE%d"%(2 * leg + 1), Vector2.ZERO)
		var low: Vector2 = dc_volts.get("IGBT_GATE%d"%(2 * leg + 2), Vector2.ZERO)
		var high_on := high.x - common.x >= LOGIC_THRESHOLD
		var low_on := low.x - common.x >= LOGIC_THRESHOLD
		blocked.append(high_on and low_on)
		gates.append(0 if high_on == low_on or disabled.x - common.x >= LOGIC_THRESHOLD else (1 if high_on else 2))
	return {"legs":gates, "interlock":blocked, "disabled":disabled.x - common.x >= LOGIC_THRESHOLD, "sync":sync.x - common.x >= LOGIC_THRESHOLD}

static func switch_impedances(state: Dictionary) -> Array:
	var parts := []
	for leg in state.get("legs", []).size():
		var rail: int = state.legs[leg]
		if rail != 0:
			parts.append({"a":"IGBT_%d"%rail, "b":"IGBT_%d"%(leg + 3), "id":"IGBT_LEG%d"%leg, "ohms":0.05})
	return parts

static func readouts(ac: Dictionary, dc: Dictionary) -> Dictionary:
	var analog := []
	var digital := []
	var common_ac: Vector2 = ac.get(CONTROL_COMMON, Vector2.ZERO)
	var common_dc: Vector2 = dc.get(CONTROL_COMMON, Vector2.ZERO)
	for i in 8:
		var a: Vector2 = ac.get("DAQ_AI%d"%i, Vector2.ZERO) - common_ac
		var d: Vector2 = dc.get("DAQ_AI%d"%i, Vector2.ZERO) - common_dc
		analog.append({"ac_rms":a.length(), "dc":d.x})
	for i in 3:
		var signal_level: Vector2 = dc.get("DAQ_DI%d"%i, Vector2.ZERO) - dc.get("DAQ_DI%d_N"%i, Vector2.ZERO)
		digital.append(signal_level.x >= LOGIC_THRESHOLD)
	var coil: Vector2 = ac.get("DYN_0", Vector2.ZERO) - ac.get("DYN_1", Vector2.ZERO)
	return {"daq_analog":analog, "daq_digital":digital, "dynamo_voltage":coil.length()}
