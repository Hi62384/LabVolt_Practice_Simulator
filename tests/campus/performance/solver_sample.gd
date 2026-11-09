extends SceneTree
## Tiny actual-solver timing sample, not a rendered or multiplayer benchmark.
const Station = preload("res://scripts/dc_station.gd")
const Readout = preload("res://scripts/campus/performance/readout_adapter.gd")
func _initialize() -> void:
	var station := Station.new()
	var times: Array[int] = []
	# Untouched baseline default bench, no fake analytical replacement.
	for i in 50:
		var start := Time.get_ticks_usec()
		station.step(0.0005)
		times.append(Time.get_ticks_usec() - start)
	var sum := 0
	for value in times:
		sum += value
	times.sort()
	var before := var_to_bytes(station.result)
	var before_time: float = station.solver.time
	var readout := Readout.new()
	var label := Label3D.new()
	readout.observe("actual_bench", station.snapshot(), label)
	readout.tick(1.0)
	var preserved: bool = before == var_to_bytes(station.result) and before_time == station.solver.time
	readout.clear()
	label.free()
	print(JSON.stringify({"scenario": "50 sequential default idle DCStation.step(0.0005), headless; micro-sample only", "calls": times.size(), "mean_usec": float(sum)/times.size(), "max_usec": times.back(), "p95_usec": times[46], "raw_usec": times, "processor": OS.get_processor_name(), "presentation_preserved_state": preserved, "result_present": not station.result.is_empty()}))
	quit(0 if preserved else 1)
