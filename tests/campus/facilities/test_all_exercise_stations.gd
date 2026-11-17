extends SceneTree
const Host=preload("res://scripts/campus/facilities/facility_host.gd")
var saved=Host.empty_profile()
var now:=1000
var failures: Array[String]=[]

func _initialize() -> void:call_deferred("run")

func run() -> void:
	var host=Host.new()
	host.authority=func():return true
	host.clock=func():return now
	host.context=func(_peer):return {"identity":"student","position":Vector3.ZERO,"room_id":"gym","allowed":true,"grounded":true}
	host.load_profile=func(_identity):return saved.duplicate(true)
	host.commit_profile=func(_identity,_dollars,value):saved=value.duplicate(true);return true
	host.dumbbell_mass=func(_peer):return 10.0
	host.barbell_mass=func(_station):return 20.0
	host.held_barbell_mass=func(_peer):return 20.0
	for kind in ["pushup","pullup","benchpress","squat","curl","cable"]:
		host.anchors["gym/"+kind]={"kind":kind,"room_id":"gym","position":Vector3.ZERO}
	host.anchors["gym/pullup"].pullup_grip=Vector3(0,2.6,0)
	host.anchors["gym/pullup"].dip_grip=Vector3(0,1.05,.75)
	host.anchors["gym/pushup"].mat_position=Vector3(1,.08,2)
	for kind in Host.STATION_EXERCISES:
		for exercise in Host.STATION_EXERCISES[kind]:
			var station: String="gym/"+kind
			if kind=="barbell":station="gym/barbell"
			_test_set(host,station,str(exercise),"",kind=="cable")
	for exercise in Host.BENCH_DUMBBELL_EXERCISES:
		_test_set(host,"gym/benchpress",str(exercise),"dumbbell",false)
	for failure in failures:push_error(failure)
	print("ALL_EXERCISE_STATIONS ","PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)

func _test_set(host: RefCounted,station: String,exercise: String,equipment: String,cable: bool) -> void:
	if not Host.GymProgress.exercise_data().has(exercise):
		failures.append("Missing exercise definition: "+exercise);return
	var definition: Dictionary=Host.GymProgress.exercise_data()[exercise]
	if definition.get("muscles",{}).is_empty():failures.append("Missing muscle mapping: "+exercise);return
	var request:={"op":"start","station":station,"exercise":exercise,"sequence":int(saved.last_sequence)+1}
	if not equipment.is_empty():request.equipment=equipment
	if cable:request.weight=5
	now+=100
	var result: Dictionary=host.act(1,request)
	if not result.get("ok",false):
		failures.append("Could not start %s at %s: %s" % [exercise,station,result.get("error","")]);return
	if not host.active.has(1) or float(host.active[1].weight)<0.0:
		failures.append("Invalid active exercise: "+exercise);return
	if station=="gym/curl" and host.active[1].get("equipment","")!="dumbbell":
		failures.append("Dumbbell exercise omitted equipment identity: "+exercise)
	if station=="gym/pullup":
		var expected:=Vector3(0,1.05,.75) if exercise=="dip" else Vector3(0,2.6,0)
		if host.active[1].get("grip_anchor")!=expected:failures.append("Missing station grip for "+exercise)
	if station=="gym/pushup" and host.active[1].get("mat_position")!=Vector3(1,.08,2):
		failures.append("Missing mat anchor for "+exercise)
	now+=100
	result=host.act(1,{"op":"cancel","sequence":int(saved.last_sequence)+1})
	if not result.get("ok",false) or host.active.has(1):failures.append("Could not stop "+exercise)
