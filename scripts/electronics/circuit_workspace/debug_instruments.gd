extends RefCounted

const SOURCE := "debug_source"
const METER := "debug_meter"

const CHOICES := {
	"wave":{"DC":["DC","wave_dc"],"AC":["Sine (AC)","wave_ac"],"SQUARE":["Square","wave_square"],"TRIANGLE":["Triangle","wave_triangle"]},
	"mode":{"Volts":["Voltage (V)","meter_volts"],"Amps":["Current (A)","meter_amps"],"Ohms":["Resistance (Ω)","meter_ohms"]}
}

static func entries() -> Dictionary:
	return {
		SOURCE:{"name":"Debug voltage source","kind":SOURCE,"category":"Simulation","pins":["+","−"],"rating":"Simulation only. Set the voltage, waveform and frequency in component properties.","rarity":"Common","space":0},
		METER:{"name":"Debug multimeter","kind":METER,"category":"Simulation","pins":["+","−"],"rating":"Simulation only. Select volts, amps or ohms. For ohms, disconnect other sources.","rarity":"Common","space":0},
	}

static func contains(board: Dictionary) -> bool:
	for part in board.get("parts",[]):
		if str(part.get("type","")) in [SOURCE,METER]:return true
	return false

static func settings(type: String) -> Dictionary:
	if type==SOURCE:
		return {"voltage":5.0,"wave":"DC","frequency":60.0}
	if type==METER:return {"mode":"Volts"}
	return {}

static func parse_field(key: String, raw: Variant) -> Dictionary:
	if key=="wave":
		var wave := str(raw).strip_edges().to_upper()
		return {"ok":CHOICES.wave.has(wave),"value":wave,"error":"Choose DC, AC, Square or Triangle."}
	if key=="mode":
		var mode := str(raw).strip_edges().capitalize()
		return {"ok":CHOICES.mode.has(mode),"value":mode,"error":"Choose Volts, Amps or Ohms."}
	if key not in ["voltage","frequency"]:return {"ok":false,"error":"Unsupported setting"}
	var parsed := preload("res://scripts/electronics/component_values/values.gd").parse(raw,"V" if key=="voltage" else "Hz")
	if not parsed.ok:return parsed
	var value := float(parsed.value)
	var valid := absf(value)<=100.0 if key=="voltage" else value>=.1 and value<=200.0
	return {"ok":valid,"value":value,"error":"Use ±100 V or 0.1–200 Hz."}

static func valid(part: Dictionary) -> bool:
	var config: Variant = part.get("debug",{})
	if not config is Dictionary:return false
	var defaults := settings(str(part.type))
	for key in config:
		if not defaults.has(key) or not parse_field(key,config[key]).ok:return false
	return true

static func expand(type: String, id: String, pins: Array, part: Dictionary, time: float) -> Array:
	var config := settings(type)
	config.merge(part.get("debug",{}),true)
	if type==SOURCE:
		var voltage := float(config.voltage)
		var phase := fposmod(time*float(config.frequency),1.0)
		match config.wave:
			"AC":voltage*=sin(TAU*phase)
			"SQUARE":voltage*=1 if phase<.5 else -1
			"TRIANGLE":voltage*=1.0-4.0*absf(phase-.5)
		return [{"id":id,"kind":"V","a":pins[0],"b":pins[1],"value":voltage,"resistance":.03}]
	var input := {"id":id,"kind":"R","a":pins[0],"b":pins[1],"value":.01 if config.mode=="Amps" else 1e7}
	if config.mode=="Ohms":
		return [input,{"id":id+"/test","kind":"I","a":pins[1],"b":pins[0],"value":.001}]
	return [input]
