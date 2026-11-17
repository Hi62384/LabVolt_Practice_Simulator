extends SceneTree
const Host=preload("res://scripts/campus/facilities/facility_host.gd")
var profile=Host.empty_profile()
var now:=1000
var failures: Array[String]=[]
var connected:=true
func check(value: bool,message: String) -> void:
	if not value:failures.append(message)
func _initialize() -> void:call_deferred("run")
func action(host: RefCounted,request: Dictionary) -> Dictionary:
	now+=100;request.sequence=int(profile.last_sequence)+1
	return host.act(1,request)
func run() -> void:
	var host=Host.new()
	host.authority=func():return true
	host.clock=func():return now
	host.context=func(_peer):return {"identity":"student","position":Vector3.ZERO,"room_id":"gym","allowed":true,"grounded":true} if connected else {}
	host.load_profile=func(_id):return profile.duplicate(true)
	host.commit_profile=func(_id,_delta,p):profile=p.duplicate(true);return true
	host.dumbbell_mass=func(_peer):return 100.0
	host.anchors={"gym/pushup":{"kind":"pushup","room_id":"gym","position":Vector3.ZERO},"gym/curl":{"kind":"curl","room_id":"gym","position":Vector3.ZERO}}
	var result:=action(host,{"op":"start","station":"gym/pushup","exercise":"pushup","weight":0})
	check(result.ok,"could not start voluntary set")
	if result.ok:
		for i in 2:
			now+=int(host.active[1].half_ms)
			result=host.act(1,{"op":"beat","sequence":int(profile.last_sequence)+1})
			check(result.ok,"repetition failed: "+str(result)+" now="+str(now)+" half="+str(host.active[1].half_ms)+" last="+str(host.last_request.get(1)))
		result=action(host,{"op":"finish"})
		check(result.ok and profile.gym.history.back().outcome=="voluntary" and profile.gym.history.back().reps==1,"voluntary set was not recorded")
		check(profile.gym.history.back().get("fatigue_added",0.0)>0.0 and profile.gym.history.back().get("stimulus_added",0.0)>0.0,"set summary omitted accumulated fatigue or stimulus")
	result=action(host,{"op":"start","station":"gym/pushup","exercise":"pushup","weight":0})
	if result.ok:
		result=action(host,{"op":"cancel"})
		check(result.ok and profile.gym.history.back().outcome=="cancelled","cancelled set was not recorded")
	else:check(false,"could not start cancelled set")
	result=action(host,{"op":"start","station":"gym/pushup","exercise":"pushup","weight":0})
	if result.ok:
		now+=15001;host.tick()
		check(not host.active.has(1) and profile.gym.history.back().outcome=="input_failure","timed-out set was not recorded")
	else:check(false,"could not start timed-out set")
	# A late beat may arrive before the periodic timeout tick. Both paths must
	# record the same outcome instead of silently discarding the set.
	result=action(host,{"op":"start","station":"gym/pushup","exercise":"pushup","weight":0})
	if result.ok:
		var history_count: int=profile.gym.history.size()
		now+=15001
		result=host.act(1,{"op":"beat","sequence":int(profile.last_sequence)+1})
		check(not result.ok and not host.active.has(1) and profile.gym.history.size()==history_count+1 and profile.gym.history.back().outcome=="input_failure","late beat discarded the failed set")
	else:check(false,"could not start late-beat set")
	result=action(host,{"op":"start","station":"gym/pushup","exercise":"pushup","weight":0})
	if result.ok:
		connected=false;host.clear_activity(1,"interrupted");connected=true
		check(not host.active.has(1) and profile.gym.history.back().outcome=="interrupted","disconnect after roster removal was not recorded")
	else:check(false,"could not start interrupted set")
	result=action(host,{"op":"start","station":"gym/curl","exercise":"curl"})
	if result.ok:
		for i in 2:
			now+=int(host.active[1].half_ms)
			result=host.act(1,{"op":"beat","sequence":int(profile.last_sequence)+1})
		check(result.get("muscular_failure",false) and profile.gym.history.back().outcome=="failure","failure was not recorded")
		check(profile.gym.history.back().muscles.has("biceps") and profile.gym.history.back().relative_effort>1.0,"history omitted muscles or effort")
	else:check(false,"could not start failure set")
	check(Host.valid_profile(profile),"history broke profile validation")
	if not profile.get("gym",{}).has("history"):
		for message in failures:push_error(message)
		push_error("No set history was persisted");quit(1);return
	var bad: Dictionary=profile.gym.duplicate(true);bad.history[0].duration_seconds=NAN
	check(not Host.GymProgress.valid(bad),"invalid history was accepted")
	bad=profile.gym.duplicate(true);bad.history[0].fatigue_added=NAN
	check(not Host.GymProgress.valid(bad),"invalid set fatigue was accepted")
	var legacy: Dictionary=profile.gym.duplicate(true)
	for entry in legacy.history:entry.erase("fatigue_added");entry.erase("stimulus_added")
	check(Host.GymProgress.valid(legacy),"legacy set history no longer validates")
	var roundtrip: Variant=JSON.parse_string(JSON.stringify(profile.gym))
	check(Host.GymProgress.valid(roundtrip) and roundtrip.history.back().outcome=="failure","history did not survive a save-data roundtrip")
	for i in 30:Host.GymProgress.record_set(profile.gym,{"exercise":"pushup","weight":0,"started":now},"cancelled",now)
	check(profile.gym.history.size()==Host.GymProgress.HISTORY_LIMIT and Host.GymProgress.valid(profile.gym),"history was not bounded")
	for message in failures:push_error(message)
	print("GYM_SET_HISTORY ","PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)
