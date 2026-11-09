extends Node
## Optional bounded frame sampler. Times are observed frame intervals, not GPU time.
var max_samples := 3600
var sample_interval := 0.25
var enabled := true
var frames: Array[float] = []
var counters: Array[Dictionary] = []
var spans: Dictionary = {}
var _starts: Dictionary = {}
var _clock := 0.0
var _sent := 0
var _received := 0
var network_instrumented := false
var _frame_cursor := 0
var total_frames := 0
var peak_frame_ms := 0.0

func _process(delta: float) -> void:
	if enabled:
		record_frame(delta)

func record_frame(delta: float) -> void:
	if delta <= 0.0 or not is_finite(delta):
		return
	if frames.size() < maxi(1, max_samples):
		frames.append(delta * 1000.0)
	else:
		_frame_cursor %= frames.size()
		frames[_frame_cursor] = delta * 1000.0
		_frame_cursor = (_frame_cursor + 1) % frames.size()
	total_frames += 1
	peak_frame_ms = maxf(peak_frame_ms, delta * 1000.0)
	_clock += delta
	if _clock >= sample_interval:
		_clock = 0.0
		counters.append({"draw_calls": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), "triangles": Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME), "render_objects": Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME), "static_bytes": Performance.get_monitor(Performance.MEMORY_STATIC), "video_bytes": Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED), "process_ms": Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0, "physics_ms": Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0, "physics_active": Performance.get_monitor(Performance.PHYSICS_3D_ACTIVE_OBJECTS), "nodes": Performance.get_monitor(Performance.OBJECT_NODE_COUNT)})
		if counters.size() > 240:
			counters.pop_front()

func begin_span(label: String) -> void:
	_starts[label] = Time.get_ticks_usec()

func end_span(label: String) -> void:
	if not _starts.has(label):
		return
	var elapsed := Time.get_ticks_usec() - int(_starts[label])
	_starts.erase(label)
	var entry: Dictionary = spans.get(label, {"calls": 0, "total_usec": 0, "max_usec": 0})
	entry.calls += 1
	entry.total_usec += elapsed
	entry.max_usec = maxi(entry.max_usec, elapsed)
	spans[label] = entry

func add_network_bytes(sent: int, received: int) -> void:
	network_instrumented = true
	_sent += maxi(0, sent)
	_received += maxi(0, received)

func report() -> Dictionary:
	var sorted := frames.duplicate()
	sorted.sort()
	var result := {"sample_count": sorted.size(), "total_frames": total_frames, "peak_frame_ms": peak_frame_ms, "counters": counters.duplicate(true), "spans": spans.duplicate(true), "network_payload_sent": _sent, "network_payload_received": _received, "unavailable": ["GPU execution milliseconds", "per-script cost without explicit spans", "wire bandwidth without transport instrumentation"], "renderer": RenderingServer.get_current_rendering_method(), "adapter": RenderingServer.get_video_adapter_name(), "os": OS.get_name(), "processor": OS.get_processor_name()}
	result.network_payload_instrumented = network_instrumented
	result.headless = DisplayServer.get_name() == "headless"
	if sorted.is_empty():
		return result
	var sum_ms := 0.0
	for value in sorted:
		sum_ms += value
	var tail_count := maxi(1, int(ceil(sorted.size() * 0.01)))
	var tail_sum := 0.0
	for i in range(sorted.size() - tail_count, sorted.size()):
		tail_sum += sorted[i]
	result.merge({"average_fps": 1000.0 * sorted.size() / sum_ms, "mean_frame_ms": sum_ms / sorted.size(), "p50_ms": sorted[int((sorted.size()-1)*0.50)], "p95_ms": sorted[int((sorted.size()-1)*0.95)], "p99_ms": sorted[int((sorted.size()-1)*0.99)], "one_percent_low_fps": 1000.0 / (tail_sum / tail_count), "one_percent_low_definition": "1000 / mean of slowest ceil(1% of retained frame intervals)"})
	return result
