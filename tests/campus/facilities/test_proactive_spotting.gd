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
	var result=host.act(2,{"op":"spot","station":"gym/benchpress","sequence":1})
	check(result.ok and host.spotting_station(2)=="gym/benchpress","spotter could not prepare")
	now+=100
	result=host.act(3,{"op":"spot","station":"gym/benchpress","sequence":1})
	check(not result.ok,"second spotter claimed occupied station")
	positions[2]=Vector3(4,0,0);host.tick()
	check(host.spotting_station(2).is_empty(),"spotter stayed active after moving away")
	positions[2]=Vector3.ZERO;now+=100
	result=host.act(2,{"op":"spot","station":"gym/benchpress","sequence":2})
	check(result.ok,"spotter could not return")
	now+=100
	result=host.act(1,{"op":"start","station":"gym/benchpress","exercise":"benchpress","sequence":1})
	check(result.ok,"bench set did not start")
	if result.ok:
		for i in 2:
			now+=int(host.active[1].half_ms)
			result=host.act(1,{"op":"beat","sequence":int(profiles["1"].last_sequence)+1})
		check(result.ok and result.get("spot_saved",false) and not host.active.has(1),"prepared spotter failed to control manageable load")
		check(host.spotting_station(2).is_empty(),"spotter reservation not released")
		check(events.any(func(e):return e.peer==2 and e.event.get("activity","")=="spot_assist"),"spotter assistance was not broadcast")
	load_kg=200.0;now+=100
	result=host.act(2,{"op":"spot","station":"gym/benchpress","sequence":int(profiles["2"].last_sequence)+1})
	check(result.ok,"spotter could not prepare again")
	now+=100
	result=host.act(1,{"op":"start","station":"gym/benchpress","exercise":"incline_press","sequence":int(profiles["1"].last_sequence)+1})
	if result.ok:
		for i in 2:
			now+=int(host.active[1].half_ms)
			result=host.act(1,{"op":"beat","sequence":int(profiles["1"].last_sequence)+1})
		check(host.active.get(1,{}).get("type","")=="trapped" and float(host.active[1].progress)>0.0,"weak spotter did not partially assist heavy load")
	else:check(false,"heavy bench set did not start")
	var panel=preload("res://scripts/campus/facilities/facility_panel.gd").new();root.add_child(panel)
	panel.station_kind="benchpress";panel.station_id="gym/benchpress";panel.state={"level":1,"profile":profiles["2"],"active":{},"spotting":"gym/benchpress"};panel.redraw()
	check(panel.find_children("*","Button",true,false).any(func(node):return node.text=="Stop spotting"),"stop spotting control missing")
	panel.free()
	for failure in failures:push_error(failure)
	print("PROACTIVE_SPOTTING ","PASS" if failures.is_empty() else "FAIL")
	host.public_event.disconnect(host.public_event.get_connections()[0].callable)
	host.authority=Callable();host.clock=Callable();host.context=Callable();host.load_profile=Callable();host.commit_profile=Callable();host.barbell_mass=Callable()
	quit(0 if failures.is_empty() else 1)
