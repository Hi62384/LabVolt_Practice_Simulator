extends RefCounted

const FULL := 3
const LOW_PASS := [2700.0, 5500.0, 10500.0]
const HIGH_PASS := [480.0, 270.0, 115.0]

static func apply(bus: int, quality: int) -> void:
	# Used on a dedicated device bus that contains only its own speaker effects.
	for index in range(AudioServer.get_bus_effect_count(bus)-1,-1,-1):
		AudioServer.remove_bus_effect(bus,index)
	if quality not in range(FULL):return
	var high:=AudioEffectHighPassFilter.new()
	high.cutoff_hz=HIGH_PASS[quality]
	high.resonance=.5
	AudioServer.add_bus_effect(bus,high)
	var low:=AudioEffectLowPassFilter.new()
	low.cutoff_hz=LOW_PASS[quality]
	low.resonance=.5
	AudioServer.add_bus_effect(bus,low)
