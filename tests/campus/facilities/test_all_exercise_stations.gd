extends SceneTree
const Host=preload("res://scripts/campus/facilities/facility_host.gd")
class RequestReceiver extends Node:
	var last := {}
	func request(value: Dictionary) -> void:
		last = value

var saved=Host.empty_profile()
var now:=1000
var failures: Array[String]=[]

func _initialize() -> void:call_deferred("run")

func run() -> void:
	var host=Host.new()
	host.live_lifts = true
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
	_test_shared_selector()
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
	if cable:request.weight=10
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
	if Host._can_pin(host.active[1]):
		# This sweep checks station setup, independently of the live lift sequence.
		host.active[1].phase=0
		host.active[1].lift_progress=1.0
	now+=100
	result=host.act(1,{"op":"cancel","sequence":int(saved.last_sequence)+1})
	if host.active.get(1,{}).get("type")=="exercise_exit":
		now=int(host.active[1].until)+1
		host.tick()
	if not result.get("ok",false) or host.active.has(1):failures.append("Could not stop "+exercise)

func _test_shared_selector() -> void:
	var panel: PanelContainer = preload("res://scripts/campus/facilities/facility_panel.gd").new()
	var receiver := RequestReceiver.new()
	root.add_child(panel)
	root.add_child(receiver)
	panel.controller = receiver
	panel.state = {"profile":saved,"active":{}}
	panel.cable_resistance = func(_station):return 35
	panel.dumbbell_mass = func():return 10.0
	panel.barbell_mass = func(_station):return 20.0
	var kinds := Host.STATION_EXERCISES.duplicate()
	kinds["bench_dumbbell"] = Host.BENCH_DUMBBELL_EXERCISES
	kinds["bench_barbell"] = Host.BENCH_BARBELL_EXERCISES
	for kind in kinds:
		panel.station_kind = kind
		panel.station_id = "gym/benchpress" if kind.begins_with("bench_") else "gym/" + kind
		panel.pending = false
		panel.redraw()
		var selectors := panel.find_children("*","OptionButton",true,false)
		var selector: OptionButton = selectors[0]
		var found := []
		for i in selector.item_count:
			var exercise: Variant = selector.get_item_metadata(i)
			if exercise == null:
				continue
			found.append(exercise)
			panel.pending = false
			selector.select(i)
			selector.item_selected.emit(i)
			for action in panel.service_actions:
				if action.text != "Start set":
					continue
				if action.disabled:
					failures.append("Equipped exercise incorrectly disabled: " + str(exercise))
				action.pressed.emit()
				if receiver.last.get("exercise") != exercise or receiver.last.get("station") != panel.station_id:
					failures.append("Selector dispatched the wrong request for " + str(exercise))
				if kind == "cable" and receiver.last.get("weight") != 35:
					failures.append("Selector did not use cable pin resistance")
		if found.size() != kinds[kind].size() or not kinds[kind].all(func(id):return id in found):
			failures.append("Selector omitted exercises at " + kind)
	panel.free()
	receiver.free()
