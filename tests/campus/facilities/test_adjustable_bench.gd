extends SceneTree
const Bench=preload("res://scripts/campus/facilities/gym_bench.gd")
const Activity=preload("res://scripts/campus/facilities/avatar_activity.gd")
const Host=preload("res://scripts/campus/facilities/facility_host.gd")
var failures: Array[String]=[]
var profile=Host.empty_profile()
var now:=1000
var last_event:={}
func check(value: bool,message: String) -> void:
	if not value:failures.append(message)
func _initialize() -> void:call_deferred("run")
func run() -> void:
	var bench=Bench.new();root.add_child(bench);bench.build()
	check(Bench.position_for("benchpress")=="flat","flat press position")
	check(Bench.position_for("incline_press")=="incline","incline position")
	check(Bench.position_for("chest_supported_row")=="supported","chest support")
	check(Bench.position_for("curl")=="seated","seated position")
	bench.on_room_event(1,{"activity":"exercise","station":"gym/benchpress","exercise":"incline_press"})
	for i in 60:bench._process(.02)
	check(is_equal_approx(bench.backrest.rotation.x,.65),"backrest did not incline")
	bench.on_room_event(2,{"activity":"idle"})
	check(bench.occupant==1,"another player's idle event cleared bench")
	bench.on_room_event(1,{"activity":"idle"})
	for i in 60:bench._process(.02)
	check(is_zero_approx(bench.backrest.rotation.x),"backrest did not reset")
	var parent:=Node3D.new();root.add_child(parent)
	var visual:=preload("res://scripts/toon_character.gd").build({});parent.add_child(visual)
	var activity:=Activity.new();parent.add_child(activity);activity.bind_visual(visual)
	var event:={"activity":"exercise","station":"gym/benchpress","exercise":"curl","phase":0,"half_ms":700,"bench_position":Vector3(1,0,1)}
	activity.apply_event(event,false)
	for i in 60:activity._process(.02)
	check(visual.global_position.distance_to(Vector3(1,-.3,1))<.03,"avatar did not reach bench")
	activity.smooth_phase=.4;event.phase=1;activity.apply_event(event,false)
	check(is_equal_approx(activity.smooth_phase,.4),"phase event snapped animation")
	activity.apply_event({"activity":"idle"},false)
	check(visual.transform==activity.original,"idle did not restore pose")
	for kind in ["benchpress","incline_press"]:
		activity.apply_event({"activity":"exercise","station":"gym/benchpress","exercise":kind,"phase":1,"half_ms":700,"bench_position":Vector3(1,0,1)},false)
		for i in 100:activity._process(.02)
		check(visual.global_position.y>.5 and visual.global_rotation.x<-.8,"%s avatar did not lie above the bench" % kind)
	activity.apply_event({"activity":"trapped","station":"gym/benchpress","exercise":"benchpress","bench_position":Vector3(1,0,1)},false)
	for i in 100:activity._process(.02)
	check(visual.global_position.y>.5 and visual.global_rotation.x< -1.4,"trapped avatar fell underneath the bench")
	activity.apply_event({"activity":"idle"},false)
	var motion=preload("res://scripts/campus/presentation/decor/m105/gym_equipment_motion.gd").new();root.add_child(motion)
	motion.on_room_event(1,{"activity":"exercise","station":"gym/benchpress","exercise":"benchpress","phase":1})
	for i in 100:motion._process(.02)
	check(absf(motion.bars["gym/benchpress"].position.z-31.27)<.02 and absf(motion.bars["gym/benchpress"].position.y-1.03)<.02,"bar did not reach the lifter's lowered hands")
	motion.on_room_event(1,{"activity":"trapped","station":"gym/benchpress","exercise":"benchpress","progress":.5})
	for i in 100:motion._process(.02)
	check(motion.bars["gym/benchpress"].position.z<31.27,"escape progress did not move the bar toward its rack")
	motion.on_room_event(1,{"activity":"idle"})
	for i in 100:motion._process(.02)
	check(motion.bars["gym/benchpress"].position.distance_to(Vector3(4,1.25,30.2))<.02,"bar did not return to its rack")
	for exercise in Host.BENCH_BARBELL_EXERCISES:
		for phase in [0.0,1.0]:
			var pose:={"activity":"exercise","station":"gym/benchpress","exercise":exercise,"phase":phase,"half_ms":700,"bench_position":Vector3(4,0,31.5)}
			activity.apply_event(pose,false);motion.on_room_event(1,pose)
			for i in 100:activity._process(.02);motion._process(.02)
			var left: Node3D=visual.get_node("Body/ArmL/Hand")
			var right: Node3D=visual.get_node("Body/ArmR/Hand")
			var midpoint: Vector3=(left.global_position+right.global_position)*.5
			check(motion.bars["gym/benchpress"].global_position.distance_to(midpoint)<.05,"%s phase %.0f bar did not reach the hands" % [exercise,phase])
		activity.apply_event({"activity":"idle"},false)
	var grip:=Vector3(4,1.1,31.3)
	motion.grip_position=func(_peer):return grip
	motion.on_room_event(1,{"activity":"exercise","station":"gym/benchpress","exercise":"curl","phase":1})
	for i in 100:motion._process(.02)
	check(motion.bars["gym/benchpress"].global_position.distance_to(grip)<.01,"bar did not follow a customized avatar's hand position")
	motion.grip_position=Callable()
	motion.free()
	var host=Host.new();host.authority=func():return true
	host.clock=func():return now
	host.context=func(_peer):return {"identity":"student","position":Vector3.ZERO,"room_id":"gym","allowed":true,"grounded":true}
	host.load_profile=func(_id):return profile.duplicate(true)
	host.commit_profile=func(_id,_d,p):profile=p.duplicate(true);return true
	host.dumbbell_mass=func(_peer):return 5.0
	host.anchors["gym/benchpress"]={"kind":"benchpress","position":Vector3.ZERO,"bench_position":Vector3(1,0,1),"room_id":"gym"}
	host.public_event.connect(func(_room,_peer,value):last_event=value)
	var result=host.act(1,{"op":"start","station":"gym/benchpress","exercise":"incline_press","equipment":"dumbbell","sequence":1})
	check(result.ok and last_event.get("bench_position")==Vector3(1,0,1),"host did not publish bench anchor")
	if result.ok:
		now+=int(host.active[1].half_ms)
		result=host.act(1,{"op":"lower","sequence":2})
		check(result.ok and last_event.get("bench_position")==Vector3(1,0,1),"movement event lost bench anchor")
		now+=100;result=host.act(1,{"op":"cancel","sequence":3})
		check(result.ok,"could not stop dumbbell set")
	host.held_barbell_mass=func(_peer):return 80.0
	host.barbell_mass=func(_station):return 20.0
	now+=100;result=host.act(1,{"op":"start","station":"gym/benchpress","exercise":"benchpress","equipment":"barbell","sequence":4})
	check(not result.ok and not host.active.has(1),"carried bar overlapped an occupied rack")
	host.barbell_mass=func(_station):return 0.0
	now+=100;result=host.act(1,{"op":"start","station":"gym/benchpress","exercise":"benchpress","equipment":"barbell","sequence":4})
	check(result.ok and is_equal_approx(float(host.active.get(1,{}).get("weight",0)),80.0) and last_event.get("equipment","")=="barbell","bench did not use carried bar mass")
	if result.ok:
		for seq in [5,6,7,8]:
			now+=int(host.active[1].half_ms)
			result=host.act(1,{"op":"lower" if seq % 2 == 1 else "beat","sequence":seq})
			if result.get("muscular_failure",false):break
		check(result.get("muscular_failure",false) and host.active.get(1,{}).get("type","")=="trapped" and last_event.get("equipment","")=="barbell","failed carried bench press lost its bar or trapped state")
	parent.free();bench.free()
	for failure in failures:push_error(failure)
	print("ADJUSTABLE_BENCH ","PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)
