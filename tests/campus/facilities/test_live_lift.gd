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
	assert(not _action(host,"cancel").ok)
	assert(_action(host,"effort").ok)
	var first: float = last_event.lift_progress
	assert(first > 0.0 and first < 1.0)
	assert(not host.act(1, {"op":"effort","sequence":int(saved.last_sequence)+1}).ok)
	for press in 30:
		if host.active[1].phase == 0:break
		assert(_action(host,"effort").ok)
	assert(host.active[1].phase == 0 and last_event.lift_progress == 1.0 and host.active[1].reps == 1)
	assert(_action(host,"finish").ok)
	_finish_exit(host)
	assert(_action(host,"start").ok)
	for press in 30:
		if host.active[1].phase==0:break
		assert(_action(host,"effort").ok)
	assert(_action(host,"lower").ok)
	assert(not _action(host,"stand").ok)
	assert(not _action(host,"effort").ok)
	var duration: int = host.active[1].half_ms
	now = int(host.active[1].last_beat) + int(duration * .5)
	host.tick()
	assert(host.active[1].phase == 2 and last_event.lift_progress > .35 and last_event.lift_progress < .65)
	now = int(host.active[1].last_beat) + duration + 100
	host.tick()
	assert(host.active[1].phase == 1 and host.active[1].reps == 1 and last_event.lift_progress == 0.0)
	assert(not _action(host,"finish").ok)
	assert(_action(host,"effort").ok)
	now+=18000
	host.tick()
	assert(host.active[1].type=="trapped" and last_event.activity=="trapped")
	assert(not _action(host,"cancel").ok and not _action(host,"stop").ok)
	for attempt in 32:
		if host.active[1].type!="trapped":break
		now+=700
		assert(host.act(1,{"op":"wiggle","sequence":int(saved.last_sequence)+1,"direction":host.active[1].direction}).ok)
	assert(host.active[1].type=="exercise" and host.active[1].phase==0 and last_event.lift_progress==1.0)
	assert(_action(host,"finish").ok)
	assert(saved.gym.history.size()==2 and saved.gym.history.back().outcome=="failure")
	_finish_exit(host)
	load_kg=200.0
	assert(_action(host,"start").ok)
	assert(_action(host,"effort").ok)
	now+=4500
	assert(_action(host,"effort").ok and host.active[1].type=="trapped")
	now+=4500
	assert(host.trapped_damage_rate(1)>0.0)
	host.clear_activity(1)
	host.anchors["gym/cable_0"] = {"kind":"cable","position":Vector3.ZERO,"room_id":"gym"}
	assert(not host.set_cable_weight(1,"gym/cable_0",22).ok)
	assert(host.set_cable_weight(1,"gym/cable_0",70).ok)
	now += 100
	var request := {"op":"start","station":"gym/cable_0","exercise":"cable_row","weight":20,"sequence":int(saved.last_sequence)+1}
	assert(not host.act(1,request).ok)
	now += 100
	request.weight = 70
	host.cable_extra_mass=func(_station):return 6.25
	assert(host.act(1,request).ok and is_equal_approx(host.active[1].weight,70 * 0.45359237 + 6.25) and host.active[1].selector_weight==70)
	assert(not host.set_cable_weight(1,"gym/cable_0",40).ok)
	_check_drop_set()
	_check_carried_bar_pin("gym/seated_bench_1","benchpress")
	_check_carried_bar_pin("gym/barbell","squat")
	_check_carried_bar_pin("gym/barbell","overhead_press")
	_check_carried_bar_pin("gym/barbell","good_morning")
	print("LIVE_LIFT PASS")
	quit()

func _check_drop_set() -> void:
	saved=Host.empty_profile()
	saved.gym=Host.GymProgress.empty()
	var host := Host.new()
	host.live_lifts=true
	host.authority=func():return true
	host.clock=func():return now
	host.context=func(_peer):return {"identity":"student","position":Vector3.ZERO,"room_id":"gym","allowed":true,"grounded":true}
	host.load_profile=func(_identity):return saved
	host.commit_profile=func(_identity,_dollars,value):saved=value.duplicate(true);return true
	host.dumbbell_mass=func(_peer):return load_kg
	var fresh: float=Host.GymProgress.capacity(saved.gym,"curl")
	load_kg=fresh*.99
	assert(_start_curl(host).ok)
	assert(_action(host,"effort").ok)
	var live: Dictionary=host.profile({"identity":"student"}).gym
	assert(live.muscles.values().any(func(muscle):return muscle.fatigue>0.0 and muscle.stimulus>0.0))
	var peak := 0.0
	for press in 60:
		assert(_action(host,"effort").ok)
		assert(host.active[1].type=="exercise" and host.active[1].reps==0)
		peak=maxf(peak,float(host.active[1].lift_progress))
	assert(peak>.3 and peak<.85)
	assert(_action(host,"cancel").ok)
	if host.active[1].type=="exercise":
		now+=int(host.active[1].half_ms)+100
		host.tick()
	assert(saved.gym.history.back().outcome=="cancelled")
	_finish_exit(host)
	load_kg=fresh*.82
	assert(_start_curl(host).ok)
	assert(float(host.active[1].lift_settings.z)>.82)
	var reduced_capacity: float=Host.GymProgress.capacity(saved.gym,"curl")
	assert(_action(host,"effort").ok)
	assert(Host.GymProgress.capacity(host.profile({"identity":"student"}).gym,"curl")<reduced_capacity)

func _start_curl(host: RefCounted) -> Dictionary:
	now+=100
	return host.act(1,{"op":"start","station":"gym/dumbbell","exercise":"curl","sequence":int(saved.last_sequence)+1})

func _check_carried_bar_pin(station: String,exercise: String) -> void:
	saved=Host.empty_profile()
	var host:=Host.new()
	host.live_lifts=true
	host.authority=func():return true
	host.clock=func():return now
	host.context=func(peer):return {"identity":str(peer),"position":Vector3.ZERO if peer==1 else Vector3.RIGHT,"room_id":"gym","allowed":true,"grounded":true}
	var helper:={"profile":Host.empty_profile()}
	host.load_profile=func(identity):return saved if identity=="1" else helper.profile
	host.commit_profile=func(identity,_dollars,value):
		if identity=="1":saved=value.duplicate(true)
		else:helper.profile=value.duplicate(true)
		return true
	host.held_barbell_mass=func(_peer):return 105.0
	host.anchors["gym/seated_bench_1"]={"kind":"seated_bench","position":Vector3.ZERO,"bench_position":Vector3(0,0,-1),"room_id":"gym"}
	host.public_event.connect(func(_room,_peer,event):
		if event.get("activity")!="assist":last_event=event.duplicate())
	now+=100
	assert(host.act(1,{"op":"start","station":station,"exercise":exercise,"equipment":"barbell","sequence":1}).ok)
	assert(not _action(host,"cancel").ok)
	assert(_action(host,"effort").ok)
	now+=12000
	host.tick()
	assert(host.active[1].type=="trapped" and last_event.equipment=="barbell" and last_event.phase==1.0 and last_event.exercise==exercise)
	assert(not _action(host,"stop").ok)
	now+=1000
	assert(host.act(2,{"op":"assist","sequence":1,"target":1}).ok and host.active[1].progress>0.0)
	for attempt in 32:
		if host.active[1].type!="trapped":break
		now+=700
		assert(host.act(1,{"op":"wiggle","sequence":int(saved.last_sequence)+1,"direction":host.active[1].direction}).ok)
	assert(host.active[1].type=="exercise" and host.active[1].phase==0)
	assert(_action(host,"cancel").ok)
	_finish_exit(host)

func _action(host: RefCounted, op: String) -> Dictionary:
	now += 100
	var request := {"op":op,"sequence":int(saved.last_sequence)+1}
	if op == "start":
		request.station = "gym/benchpress"
		request.exercise = "benchpress"
	return host.act(1, request)

func _finish_exit(host) -> void:
	assert(host.active[1].type=="exercise_exit" and host.movement_locked(1))
	now=int(host.active[1].until)-1
	host.tick()
	assert(host.movement_locked(1))
	now+=1
	host.tick()
	assert(not host.movement_locked(1))
