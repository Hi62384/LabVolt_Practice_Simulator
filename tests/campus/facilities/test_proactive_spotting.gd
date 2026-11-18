extends SceneTree
const Host=preload("res://scripts/campus/facilities/facility_host.gd")
var profiles:={"1":Host.empty_profile(),"2":Host.empty_profile(),"3":Host.empty_profile()}
var positions:={1:Vector3.ZERO,2:Vector3.ZERO,3:Vector3.ZERO}
var now:=1000
var load_kg:=65.0
var events:=[]
var failures: Array[String]=[]
func check(value: bool,message: String) -> void:
	if not value:failures.append(message)
func _initialize() -> void:call_deferred("run")
func run() -> void:
	var host=Host.new()
	host.authority=func():return true
	host.clock=func():return now
	host.context=func(peer):return {"identity":str(peer),"position":positions.get(peer,Vector3.INF),"room_id":"gym","allowed":true,"grounded":true}
	host.load_profile=func(id):return profiles[id].duplicate(true)
	host.commit_profile=func(id,_d,p):profiles[id]=p.duplicate(true);return true
	host.barbell_mass=func(_station):return load_kg
	host.anchors["gym/benchpress"]={"kind":"benchpress","position":Vector3.ZERO,"room_id":"gym"}
	host.public_event.connect(func(_room,peer,event):events.append({"peer":peer,"event":event.duplicate(true)}))
	var result = host.act(2,{"op":"spot","station":"gym/benchpress","sequence":1})
	check(not result.ok,"obsolete proactive spotting was accepted")
	now += 100
	result = host.act(2,{"op":"assist","target":1,"sequence":1})
	check(not result.ok,"an idle player could be rescued")
	now += 100
	result = host.act(1,{"op":"start","station":"gym/benchpress","exercise":"benchpress","sequence":1})
	check(result.ok,"bench set did not start")
	if result.ok:
		now += 200
		result = host.act(1,{"op":"lower","sequence":2})
		check(result.ok,"lowering failed")
		now += 200
		result = host.act(1,{"op":"rep_fail","sequence":3})
		check(result.ok and host.active.get(1,{}).get("type")=="trapped","failed bench lift did not trap")
		positions[2]=Vector3(8,0,0)
		now += 200
		result = host.act(2,{"op":"assist","target":1,"sequence":1})
		check(not result.ok,"an out-of-range rescuer was accepted")
		positions[2]=Vector3.ZERO
		for attempt in 10:
			if not host.active.has(1):
				break
			now += 1050
			result = host.act(2,{"op":"assist","target":1,"sequence":int(profiles["2"].last_sequence)+1})
			check(result.ok, "nearby rescue rejected")
		check(not host.movement_locked(1) and not host.seats.has("gym/benchpress"),"rescue left the lifter locked")
		check(events.any(func(e):return e.peer==2 and e.event.get("activity")=="assist"),"rescue event was not broadcast")

	for failure in failures:push_error(failure)
	print("REACTIVE_RESCUE ","PASS" if failures.is_empty() else "FAIL")
	host.public_event.disconnect(host.public_event.get_connections()[0].callable)
	host.authority=Callable();host.clock=Callable();host.context=Callable();host.load_profile=Callable();host.commit_profile=Callable();host.barbell_mass=Callable()
	quit(0 if failures.is_empty() else 1)
