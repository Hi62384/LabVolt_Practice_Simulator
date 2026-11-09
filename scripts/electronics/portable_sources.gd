extends RefCounted

const WAVES := ["Sine","Square","Triangle","Sawtooth"]
const CONTROLS := ["battery_adjustable","battery_generator","battery_generator_adjustable"]
const MAX_VOLTAGE := 30.0
const MIN_FREQUENCY := .1
const MAX_FREQUENCY := 200.0

static func readout(entry: Dictionary,state: Dictionary) -> String:
	var peak := float(state.get("source_voltage",entry.value))
	if not entry.has("frequency"):return "%.1f V DC" % peak
	var wave: String=WAVES[clampi(int(state.get("source_wave",0)),0,WAVES.size()-1)]
	return "%s · %.1f Vpk · %.1f Hz" % [wave,peak,float(state.get("source_frequency",entry.frequency))]

static func adjust(entry: Dictionary, state: Dictionary, action: Dictionary) -> void:
	var mode := str(entry.get("source_mode",""))
	var direction := -1.0 if action.get("reverse",false) else 1.0
	match action.get("source_adjust",""):
		"wave":
			if mode in ["battery_generator","battery_generator_adjustable"]:
				state.source_wave=posmod(int(state.get("source_wave",0))+int(direction),WAVES.size())
		"voltage":
			if mode in ["battery_adjustable","battery_generator_adjustable"]:
				state.source_voltage=clampf(float(state.get("source_voltage",entry.value))+direction*.5,0.0,MAX_VOLTAGE)
		"frequency":
			if mode=="battery_generator_adjustable":
				state.source_frequency=clampf(float(state.get("source_frequency",entry.frequency))+direction,MIN_FREQUENCY,MAX_FREQUENCY)

static func voltage(entry: Dictionary,state: Dictionary,time: float) -> float:
	var mode := str(entry.source_mode)
	var adjustable := mode in ["battery_adjustable","battery_generator_adjustable"]
	var peak := float(entry.value)
	if adjustable:peak=clampf(float(state.get("source_voltage",peak)),0.0,MAX_VOLTAGE)
	if mode=="battery_adjustable":return peak
	var frequency := float(entry.frequency)
	if adjustable:frequency=clampf(float(state.get("source_frequency",frequency)),MIN_FREQUENCY,MAX_FREQUENCY)
	var phase := fposmod(time*frequency,1.0)
	var wave := 0 if mode=="battery_ac" else clampi(int(state.get("source_wave",0)),0,WAVES.size()-1)
	match wave:
		1:return peak*(1.0 if phase<.5 else -1.0)
		2:return peak*(1.0-4.0*absf(phase-.5))
		3:return peak*(phase*2.0-1.0)
	return peak*sin(TAU*phase)
