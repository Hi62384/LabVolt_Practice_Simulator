extends Node
## Opt-in bounded timeline. Wall spans locate an observed gap; they do not prove CPU
## execution/GPU timing or exclude descheduling while a callback is in progress.
signal window_finished(phase: String)

class Ring extends RefCounted:
	var capacity: int
	var data: Array = []
	var cursor := 0
	var overwritten := 0
	func _init(limit: int) -> void:
		capacity = maxi(1,limit)
	func push(item: Dictionary) -> void:
		if data.size() < capacity:
			data.append(item)
		else:
			data[cursor] = item
			cursor = (cursor+1)%capacity
			overwritten += 1
	func entries() -> Array:
		if overwritten == 0:
			return data.duplicate(true)
		return (data.slice(cursor)+data.slice(0,cursor)).duplicate(true)

class Edge extends Node:
	var recorder: WeakRef
	var early := false
	func _process(delta: float) -> void:
		var trace: Node = recorder.get_ref()
		if trace != null:
			trace._process_edge(early,delta)
	func _physics_process(_delta: float) -> void:
		var trace: Node = recorder.get_ref()
		if trace != null:
			trace._physics_edge(early)

var enabled := true
var hitch_threshold_usec := 100000
var phase := "startup"
var _frames := Ring.new(4096)
var _events := Ring.new(8192)
var _spans := Ring.new(4096)
var _hitches := Ring.new(64)
var _labels := {}
var _pending := {}
var _next_token := 1
var _early_usec := 0
var _early_frame := -1
var _last_late_usec := 0
var _phase_first_interval := false
var _sequence := 0
var _physics_start := 0
var _physics_id := -1
var _pipeline_monitors := {}
var _windows: Array[Dictionary] = []
var _windows_overwritten := 0
var _deadline := 0
var _window_start := 0
var _owner_thread := 0
var _rejected_spans := 0
var _priority_support := false
var _max_late_record_usec := 0

func _ready() -> void:
	_owner_thread = OS.get_thread_caller_id()
	for property in get_property_list():
		if str(property.name) == "process_physics_priority":
			_priority_support = true
	for early in [true,false]:
		var edge := Edge.new()
		edge.name = "TraceEarly" if early else "TraceLate"
		edge.recorder = weakref(self)
		edge.early = early
		edge.process_priority = -1000000 if early else 1000000
		if _priority_support:
			edge.set("process_physics_priority",edge.process_priority)
		add_child(edge)
	for label in ClassDB.class_get_integer_constant_list("Performance"):
		if "PIPELINE_COMPILATIONS" in str(label):
			_pipeline_monitors[label] = ClassDB.class_get_integer_constant("Performance",label)
	RenderingServer.frame_pre_draw.connect(_render_pre)
	RenderingServer.frame_post_draw.connect(_render_post)
	mark("trace_attached")

func mark(label: String) -> void:
	if enabled:
		_event("marker",{"label":label.left(64)})

func begin_window(label: String, seconds: float) -> void:
	phase = label.left(64)
	_window_start = Time.get_ticks_usec()
	_deadline = _window_start+int(clampf(seconds,0.01,120.0)*1000000.0)
	_phase_first_interval = true # Retain the boundary interval, including any hitch.
	mark("window_begin")

func stop() -> void:
	mark("trace_stop")
	enabled = false
	_deadline = 0

func begin_span(label: String) -> int:
	if not enabled or _pending.size() >= 64:
		_rejected_spans += 1
		return -1
	label = label.left(64)
	if not _labels.has(label) and _labels.size() >= 32:
		_rejected_spans += 1
		return -1
	_labels[label] = true
	var token := _next_token
	_next_token += 1
	_pending[token] = {"label":label,"begin_usec":Time.get_ticks_usec(),"phase":phase,"begin_frame":Engine.get_process_frames()}
	return token

func end_span(token: int) -> void:
	if not _pending.has(token):
		return
	var entry: Dictionary = _pending[token]
	_pending.erase(token)
	entry.end_usec = Time.get_ticks_usec()
	entry.duration_usec = entry.end_usec-entry.begin_usec
	entry.end_frame = Engine.get_process_frames()
	_spans.push(entry)

func _event(kind: String, fields: Dictionary = {}) -> void:
	var entry := {"kind":kind,"at_usec":Time.get_ticks_usec(),"engine_process_frame":Engine.get_process_frames(),"engine_physics_frame":Engine.get_physics_frames(),"thread_id":OS.get_thread_caller_id(),"phase":phase}
	entry.merge(fields)
	_events.push(entry)

func _render_pre() -> void:
	if enabled:
		_event("render_pre_signal")

func _render_post() -> void:
	if enabled:
		_event("render_post_signal")

func _physics_edge(early: bool) -> void:
	if not enabled:
		return
	var now := Time.get_ticks_usec()
	var id := Engine.get_physics_frames()
	if early:
		_physics_start = now
		_physics_id = id
	elif _physics_id == id:
		_event("physics_bracket",{"begin_usec":_physics_start,"end_usec":now,"duration_usec":now-_physics_start,"priority_supported":_priority_support})

func _process_edge(early: bool, delta: float) -> void:
	if not enabled:
		return
	var now := Time.get_ticks_usec()
	var frame := Engine.get_process_frames()
	if early:
		_early_usec = now
		_early_frame = frame
		return
	_sequence += 1
	var interval_begin := _window_start if _phase_first_interval else _last_late_usec
	var interval := now-interval_begin if interval_begin > 0 else 0
	var bracket := now-_early_usec if _early_frame == frame else -1
	var row := {"sequence":_sequence,"phase":phase,"engine_process_frame":frame,"engine_physics_frame":Engine.get_physics_frames(),"early_usec":_early_usec,"late_usec":now,"previous_late_usec":_last_late_usec,"interval_begin_usec":interval_begin,"interval_origin":"phase_start" if _phase_first_interval else "previous_late_callback","interval_usec":interval,"process_bracket_usec":bracket,"between_late_and_next_early_usec":_early_usec-_last_late_usec if _last_late_usec>0 else -1,"simulation_delta":delta,"time_scale":Engine.time_scale,"thread_id":OS.get_thread_caller_id(),"counters":_counters()}
	_frames.push(row)
	_last_late_usec = now
	_phase_first_interval = false
	if interval >= hitch_threshold_usec:
		_hitches.push(row.duplicate(true))
	_max_late_record_usec = maxi(_max_late_record_usec,Time.get_ticks_usec()-now)
	if _deadline > 0 and now >= _deadline:
		_deadline = 0
		_windows.append({"phase":phase,"begin_usec":_window_start,"end_usec":now,"observed_usec":now-_window_start})
		if _windows.size() > 32:
			_windows.pop_front()
			_windows_overwritten += 1
		mark("window_end")
		window_finished.emit(phase)

func _counters() -> Dictionary:
	var result := {"sample_at_usec":Time.get_ticks_usec(),"process_ms":Performance.get_monitor(Performance.TIME_PROCESS)*1000.0,"physics_ms":Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)*1000.0,"draw_calls":Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),"primitives":Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),"static_bytes":Performance.get_monitor(Performance.MEMORY_STATIC),"video_bytes":Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED),"nodes":Performance.get_monitor(Performance.OBJECT_NODE_COUNT)}
	for label in _pipeline_monitors:
		result[label] = Performance.get_monitor(_pipeline_monitors[label])
	return result

func report() -> Dictionary:
	return {"format":1,"clock":"Time.get_ticks_usec monotonic wall clock, not GPU/presentation timestamps","owner_thread":_owner_thread,"frames":_frames.entries(),"events":_events.entries(),"spans":_spans.entries(),"hitches":_hitches.entries(),"windows":_windows.duplicate(true),"open_spans":_pending.duplicate(true),"overwritten":{"frames":_frames.overwritten,"events":_events.overwritten,"spans":_spans.overwritten,"hitches":_hitches.overwritten,"windows":_windows_overwritten},"capacities":{"frames":_frames.capacity,"events":_events.capacity,"spans":_spans.capacity,"hitches":_hitches.capacity,"windows":32},"rejected_spans":_rejected_spans,"physics_priority_supported":_priority_support,"max_late_recording_usec":_max_late_record_usec,"pipeline_monitor_names":_pipeline_monitors.keys(),"pipeline_backend_coverage_assumed":false,"scope":"process/physics brackets cover main-thread callbacks inside priorities -1000000..1000000; rendering signals may include deferred CPU delivery on threaded rendering; counter samples are latest engine monitor values with independent update cadence; no cause is automatically assigned"}

func save_report(path: String) -> Error:
	if enabled:
		return ERR_BUSY # Never write disk data inside a measured window.
	var file := FileAccess.open(path,FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(report(),"\t"))
	file.close()
	return OK

func _exit_tree() -> void:
	if RenderingServer.frame_pre_draw.is_connected(_render_pre):
		RenderingServer.frame_pre_draw.disconnect(_render_pre)
	if RenderingServer.frame_post_draw.is_connected(_render_post):
		RenderingServer.frame_post_draw.disconnect(_render_post)
