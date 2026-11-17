extends SceneTree
const Host=preload("res://scripts/campus/facilities/facility_host.gd")
var profiles:={"1":Host.empty_profile(),"2":Host.empty_profile()}
var now:=1000
var failures: Array[String]=[]
var events:=[]
func check(value: bool,message: String) -> void:
	if not value:failures.append(message)
func _initialize() -> void:call_deferred("run")
func run() -> void:
	var host=Host.new();host.authority=func():return true
	host.clock=func():return now
	host.context=func(peer):return {"identity":str(peer),"position":Vector3.ZERO,"room_id":"gym","allowed":true,"grounded":true}
	host.load_profile=func(id):return profiles[id].duplicate(true)
	host.commit_profile=func(id,_d,p):profiles[id]=p.duplicate(true);return true
	host.barbell_mass=func(_station):return 200.0
	host.anchors["gym/benchpress"]={"kind":"benchpress","room_id":"gym","position":Vector3.ZERO,"bench_position":Vector3.ZERO}
	host.public_event.connect(func(_room,peer,event):events.append({"peer":peer,"event":event.duplicate(true)}))
	var result=host.act(1,{"op":"start","station":"gym/benchpress","exercise":"benchpress","sequence":1})
	check(result.ok,"start failed")
	if result.ok:
		for i in 2:
			now+=int(host.active[1].half_ms)
			result=host.act(1,{"op":"beat","sequence":int(profiles["1"].last_sequence)+1})
			check(result.ok,"beat failed")
	check(host.active.get(1,{}).get("type","")=="trapped","heavy bench did not trap")
	if host.active.get(1,{}).get("type","")=="trapped":
		now+=100
		result=host.act(1,{"op":"cancel","sequence":int(profiles["1"].last_sequence)+1})
		check(not result.ok,"cancel bypassed trap")
		now+=700
		result=host.act(1,{"op":"wiggle","direction":1,"sequence":int(profiles["1"].last_sequence)+1})
		check(not result.ok,"wrong direction accepted")
		now+=700
		result=host.act(1,{"op":"wiggle","direction":-1,"sequence":int(profiles["1"].last_sequence)+1})
		check(result.ok and float(host.active[1].progress)>0.0,"wiggle did not advance")
		var before: float=host.active[1].progress
		now+=1000
		result=host.act(2,{"op":"assist","target":1,"sequence":1})
		check(result.ok and float(host.active[1].progress)>before,"nearby help did not advance")
		now+=Host.TRAP_TIMEOUT_MS
		host.tick()
		check(not host.active.has(1) and not host.seats.has("gym/benchpress"),"safety timeout did not release station")
		now+=100
		result=host.act(1,{"op":"start","station":"gym/benchpress","exercise":"benchpress","sequence":int(profiles["1"].last_sequence)+1})
		if result.ok:
			for i in 2:
				now+=int(host.active[1].half_ms)
				result=host.act(1,{"op":"beat","sequence":int(profiles["1"].last_sequence)+1})
			for i in 40:
				if not host.active.has(1):break
				now+=700
				result=host.act(1,{"op":"wiggle","direction":int(host.active[1].direction),"sequence":int(profiles["1"].last_sequence)+1})
				if not result.ok:break
			check(not host.active.has(1),"repeated alternating movement did not free bar")
		else:check(false,"could not start another set after safety reset")
		host.dumbbell_mass=func(_peer):return 200.0
		now+=100
		result=host.act(1,{"op":"start","station":"gym/dumbbell","exercise":"deadlift","sequence":int(profiles["1"].last_sequence)+1})
		if result.ok:
			for i in 2:
				now+=int(host.active[1].half_ms)
				result=host.act(1,{"op":"beat","sequence":int(profiles["1"].last_sequence)+1})
			check(not host.active.has(1),"deadlift failure should not trap the player")
		else:check(false,"could not start deadlift")
	var panel=preload("res://scripts/campus/facilities/facility_panel.gd").new();root.add_child(panel)
	panel.station_kind="benchpress";panel.station_id="gym/benchpress"
	panel.state={"level":1,"profile":profiles["1"],"active":{"type":"trapped","progress":.2,"direction":-1}}
	panel.redraw()
	var sliders=panel.find_children("*","HSlider",true,false)
	check(sliders.size()==1 and not panel.workout_reached,"escape control missing or already complete")
	if sliders.size()==1:
		sliders[0].value=0.0
		check(panel.workout_reached,"escape control did not register movement")
	panel.free()
	for failure in failures:push_error(failure)
	print("TRAPPED_BAR ","PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)
