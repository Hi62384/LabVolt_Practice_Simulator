extends RefCounted
## Pure cosmetic state. No state mutation, timers, scene references or queued work.
const DURATIONS = {"insert":0.30,"remove":0.30,"knob":0.24,"switch":0.22,"grasp":0.20}
var enabled = true
var suspended = false
var last_sequence = -1
var elapsed = 0.0
var event = {}
var hold = {}

func accept(value: Dictionary) -> bool:
	var kind = str(value.get("kind",""))
	var sequence = int(value.get("sequence",-1))
	if not enabled or suspended or not kind in DURATIONS or sequence <= last_sequence:
		return false
	last_sequence = sequence
	var continuous_knob = kind == "knob" and event.get("kind","") == "knob" and event.get("station",0) == value.get("station",0) and event.get("port","") == value.get("port","")
	var previous_elapsed = elapsed
	event = value.duplicate(true)
	elapsed = minf(previous_elapsed,DURATIONS["knob"]*0.55) if continuous_knob else 0.0
	return true

func reconcile_hold(value: Dictionary) -> void:
	hold = value.duplicate(true)

func cancel() -> void:
	event = {}
	elapsed = 0.0

func reset() -> void:
	suspended = false
	cancel()
	hold = {}
	last_sequence = -1

func set_enabled(value: bool) -> void:
	enabled = value
	if not value:
		cancel()

func set_suspended(value: bool) -> void:
	suspended = value
	if value:
		cancel()

func active() -> bool:
	return enabled and not suspended and (not event.is_empty() or not hold.is_empty())

func advance(delta: float) -> void:
	if not is_finite(delta) or delta <= 0.0 or event.is_empty():
		return
	elapsed += delta
	if elapsed >= DURATIONS[event["kind"]]:
		cancel()

func sample() -> Dictionary:
	var result = {"active":active(),"reach":0.0,"grip":0.0,"twist":0.0,"connector":0.0,"transfer":0.0}
	if not result["active"]:
		return result
	result["grip"] = 0.75 if not hold.is_empty() else 0.0
	if event.is_empty():
		return result
	var phase = clampf(elapsed / DURATIONS[event["kind"]],0.0,1.0)
	var reach = minf(phase / 0.30,1.0) * minf((1.0-phase) / 0.25,1.0)
	result["reach"] = reach
	result["grip"] = maxf(result["grip"],reach)
	var contact = clampf((phase-0.30)/0.45,0.0,1.0)
	if event["kind"] == "knob":
		result["twist"] = float(event.get("turn",0.0)) * contact * reach
	elif event["kind"] == "switch":
		result["twist"] = float(event.get("turn",0.0)) * sin(phase*PI) * 0.20
	elif event["kind"] == "insert":
		result["connector"] = (1.0-contact)*0.065
	elif event["kind"] == "remove":
		result["connector"] = sin(phase*PI)*0.065
		result["transfer"] = contact
	return result
