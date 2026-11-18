extends SceneTree

const Host = preload("res://scripts/campus/facilities/facility_host.gd")
var saved := Host.empty_profile()
var now := 1000
var load_kg := 20.0
var last_event := {}

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var host := Host.new()
	host.live_lifts = true
	host.authority = func():return true
	host.clock = func():return now
	host.context = func(_peer):return {"identity":"student","position":Vector3.ZERO,"room_id":"gym","allowed":true,"grounded":true}
	host.load_profile = func(_identity):return saved
	host.commit_profile = func(_identity,_dollars,value):saved=value.duplicate(true);return true
	host.barbell_mass = func(_station):return load_kg
	host.anchors["gym/benchpress"] = {"kind":"benchpress","position":Vector3.ZERO,"room_id":"gym"}
	host.public_event.connect(func(_room,_peer,event):last_event=event.duplicate())
	assert(_action(host,"start").ok)
	assert(host.active[1].phase == 1 and last_event.lift_progress == 0.0)
	assert(not _action(host,"lower").ok)
	assert(not _action(host,"rep_fail").ok)
	assert(_action(host,"effort").ok)
	var first: float = last_event.lift_progress
	assert(first > 0.0 and first < 1.0)
	assert(not host.act(1, {"op":"effort","sequence":int(saved.last_sequence)+1}).ok)
	for press in 30:
		if host.active[1].phase == 0:break
		assert(_action(host,"effort").ok)
	assert(host.active[1].phase == 0 and last_event.lift_progress == 1.0 and host.active[1].reps == 0)
	assert(_action(host,"lower").ok)
	assert(not _action(host,"effort").ok)
	var duration: int = host.active[1].half_ms
	now = int(host.active[1].last_beat) + int(duration * .5)
	host.tick()
	assert(host.active[1].phase == 2 and last_event.lift_progress > .35 and last_event.lift_progress < .65)
	now = int(host.active[1].last_beat) + duration + 100
	host.tick()
	assert(host.active[1].phase == 1 and host.active[1].reps == 1 and last_event.lift_progress == 0.0)
	assert(_action(host,"finish").ok and not host.movement_locked(1))
	load_kg = 200.0
	assert(_action(host,"start").ok)
	for press in 20:
		if host.active[1].type == "trapped":break
		assert(_action(host,"effort").ok)
		host.tick()
		if host.active[1].type == "exercise":assert(host.active[1].lift_progress < 1.0 and host.active[1].reps == 0)
	assert(host.active[1].type == "trapped" and host.trapped_damage_rate(1) > 0.0)
	assert(saved.gym.history.size() == 2 and saved.gym.history.back().outcome == "failure")
	host.clear_activity(1)
	host.anchors["gym/cable_0"] = {"kind":"cable","position":Vector3.ZERO,"room_id":"gym"}
	assert(not host.set_cable_weight(1,"gym/cable_0",22).ok)
	assert(host.set_cable_weight(1,"gym/cable_0",25).ok)
	now += 100
	var request := {"op":"start","station":"gym/cable_0","exercise":"cable_row","weight":20,"sequence":int(saved.last_sequence)+1}
	assert(not host.act(1,request).ok)
	now += 100
	request.weight = 25
	assert(host.act(1,request).ok and host.active[1].weight == 25)
	assert(not host.set_cable_weight(1,"gym/cable_0",40).ok)
	print("LIVE_LIFT PASS")
	quit()

func _action(host: RefCounted, op: String) -> Dictionary:
	now += 100
	var request := {"op":op,"sequence":int(saved.last_sequence)+1}
	if op == "start":
		request.station = "gym/benchpress"
		request.exercise = "benchpress"
	return host.act(1, request)
