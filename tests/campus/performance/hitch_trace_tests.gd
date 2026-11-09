extends SceneTree
const Trace = preload("res://scripts/campus/performance/hitch_trace.gd")
var failures := 0
var checks := 0

class Work extends Node:
	var trace: Node
	var performed := false
	var calls := 0
	func _process(_delta: float) -> void:
		calls += 1
		if calls < 2:
			return # First late edge must exist before injecting known work.
		if performed:
			return
		performed = true
		var token: int = trace.begin_span("fixture_process_work")
		trace.mark("fixture_work_begin")
		OS.delay_usec(2000) # One deliberately identifiable2ms fixture, not a benchmark.
		trace.mark("fixture_work_end")
		trace.end_span(token)

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, text: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL " + text)

func run() -> void:
	var trace := Trace.new()
	trace.hitch_threshold_usec = 1 # Exercise retention without an expensive hitch.
	root.add_child(trace)
	var work := Work.new()
	work.trace = trace
	root.add_child(work)
	check(trace.save_report("user://must-not-write-while-running.json")==ERR_BUSY,"recorder refuses disk writes while measuring")
	trace.begin_window("fixture",0.025)
	await trace.window_finished
	trace.stop()
	var report: Dictionary = trace.report()
	check(report.frames.size()>=2,"actual engine process callbacks recorded")
	check(report.physics_priority_supported,"engine supports independent physics priority")
	check(report.spans.size()==1 and report.spans[0].label=="fixture_process_work","actual default-priority work span retained")
	check(report.spans[0].duration_usec>=1500,"injected wall span is measured")
	var matched := false
	for frame in report.frames:
		if frame.engine_process_frame==report.spans[0].begin_frame:
			matched = frame.early_usec<=report.spans[0].begin_usec and frame.late_usec>=report.spans[0].end_usec and frame.process_bracket_usec>=report.spans[0].duration_usec and frame.interval_usec>0
	check(matched,"priority sentinels bracket known real callback work on same engine frame")
	check(not report.hitches.is_empty(),"threshold gaps retain full timestamp/counter records")
	check(report.windows[0].observed_usec>=25000,"deadline closes on observed monotonic late callback")
	check(report.frames[0].interval_origin=="phase_start" and report.frames[0].interval_usec>0,"first boundary interval is retained instead of dropping a possible hitch")
	var measured_sum := 0
	for frame in report.frames:
		measured_sum += int(frame.interval_usec)
	check(measured_sum==report.windows[0].observed_usec,"raw observed intervals cover entire measured window without a boundary gap")
	check(report.frames.back().counters.has("sample_at_usec"),"counter observations carry their own timestamp")
	check(report.frames.back().counters.sample_at_usec>=report.frames.back().late_usec,"counter sampling time is distinguished from edge time")
	check(report.events.any(func(event): return event.kind=="physics_bracket" and event.end_usec>=event.begin_usec),"actual physics callbacks produce ordered timestamped brackets")
	var previous := 0
	for frame in report.frames:
		check(frame.late_usec>previous and frame.process_bracket_usec>=0,"retained frame order and phase brackets valid")
		previous = frame.late_usec
	var ring := Trace.Ring.new(2)
	ring.push({"n":1});ring.push({"n":2});ring.push({"n":3})
	check(ring.entries()==[{"n":2},{"n":3}] and ring.overwritten==1,"bounded ring reports chronological retained history and loss")
	check(trace.save_report("user://hitch-test.json")==OK,"stopped recorder can serialize full raw evidence")
	var loaded: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("user://hitch-test.json"))
	check(loaded.frames.size()==report.frames.size() and loaded.spans[0].duration_usec==report.spans[0].duration_usec,"serialized timestamps/spans survive JSON round trip")
	trace.queue_free()
	work.queue_free()
	await process_frame
	print("HITCH TRACE %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
