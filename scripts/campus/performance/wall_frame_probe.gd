extends "res://scripts/campus/performance/frame_probe.gd"
## Monotonic process-callback cadence, independent of engine simulation delta.
var _previous_tick := 0

func _process(_delta: float) -> void:
	var now := Time.get_ticks_usec()
	if enabled and _previous_tick > 0:
		record_frame((now-_previous_tick)/1000000.0)
	_previous_tick = now if enabled else 0

func report() -> Dictionary:
	var result := super.report()
	result.frame_interval_source = "Time.get_ticks_usec between process callbacks; first interval excluded"
	result.presentation_timestamps = false
	return result
