extends SceneTree
var failures := 0
var checks := 0
func check(value: bool,label: String) -> void:
	checks+=1
	if not value:failures+=1;printerr("FAIL "+label)
func _initialize() -> void:call_deferred("run")
func run() -> void:
	var scene=load("res://scenes/Main.tscn")
	if scene==null:scene=load("res://scenes/main.tscn")
	var game=scene.instantiate();root.add_child(game)
	await process_frame;await process_frame
	check(is_instance_valid(game.campus_services),"normal main scene composes campus")
	check(game.campus_services.facilities.movement_ready,"facility movement guards live")
	check(game.front.campus_adapter==game.campus_services.adapter,"menu uses live academic adapter")
	check(game.dc_lab.benches.size()==3 and game.dc_lab.ports[0]["CH1+"].z>20,"DC benches physically moved with their port coordinates")
	var result: Dictionary=game.school.start_activity({"mode":"Freeplay","course_id":"ELM253","kind":"lab","week":1,"difficulty":0})
	check(result.ok and game.school.activity.is_empty() and game.school.phase=="freeplay","freeplay keeps roaming teacher and no assessment")
	var provider=game.campus_services.provider
	var evidence=game.school.equipment_adapter
	for week in range(1,9):
		for difficulty in range(5):
			var assignment: Dictionary=provider.generate("ELM253",week,"lab",difficulty,253)
			assignment.assessment_id="test.%d.%d"%[week,difficulty]
			check(evidence.supports(assignment).get("ok",false),"physical AC plan available %d/%d"%[week,difficulty])
			var lab=game.session.labs[0]
			lab.cables.clear();lab.powered=false
			for kind in ["R","L","C"]:lab.switches[kind]=[false,false,false,false,false,false,false,false,false]
			var plan: Dictionary=assignment.physical_ac_plan
			lab.level=plan.variable_level;lab.frequency=plan.frequency_hz
			var node_pins: Dictionary=plan.source_nodes.duplicate()
			var serial := 1
			for bank in plan.banks:
				var id: String=str(bank.kind)+str(bank.index)
				var values: Array=preload("res://scripts/equipment_catalog.gd").LOADS[bank.kind].values
				for i in range(3):
					if absf(float(values[i])-float(bank.value))<maxf(1e-12,float(bank.value)*0.0001):lab.switches[bank.kind][int(bank.index)*3+i]=true
				for pair in [[bank.a,id+"_P"],[bank.b,id+"_N"]]:
					if not node_pins.has(pair[0]):node_pins[pair[0]]=pair[1]
					else:
						lab.cables.append({"id":serial,"a":node_pins[pair[0]],"b":pair[1],"color":0,"owner":0});serial+=1
			# Insert actual ammeter into R0's incoming lead, never inject a reading.
			for lead in lab.cables:
				if lead.b=="R0_P":lead.b="AM0_IN";break
			lab.cables.append({"id":serial,"a":"AM0_OUT","b":"R0_P","color":0,"owner":0});serial+=1
			lab.cables.append({"id":serial,"a":"V0_COM","b":"R0_N","color":1,"owner":0});serial+=1
			lab.cables.append({"id":serial,"a":"V0_150","b":"R0_P","color":1,"owner":0})
			game.school.activity={"course_id":"ELM253","kind":"lab"};game.school.project=assignment
			game.school.mode="Class";game.school.phase="assignment";game.school.class_students={"test":{"done":false}}
			evidence.observe_ac_action(1,0,{"op":"plug"},{"powered":false})
			lab.powered=true;lab.recalculate()
			check(lab.powered,"AC physical circuit remains powered %d/%d %s"%[week,difficulty,str(lab.readings.get("fault",""))])
			check(evidence.record_measurement(1,0,assignment),"records actual AC instruments %d/%d"%[week,difficulty])
			var captured: Dictionary=evidence.capture(1,0,assignment)
			var grade: Dictionary=evidence.grade(assignment,captured)
			check(grade.get("score",0)>=90,"AC topology and measured operating point %d/%d: %s"%[week,difficulty,str(grade)])
			lab.powered=false;lab.recalculate()
			evidence.observe_ac_action(1,0,{"op":"power"},{"powered":true})
			grade=evidence.grade(assignment,evidence.capture(1,0,assignment))
			check(grade.get("score",0)==100,"power-off retains verified measurements and procedure %d/%d"%[week,difficulty])
			lab.cables.pop_back()
			check(not evidence.capture(1,0,assignment).get("topology",false),"changed wiring invalidates retained evidence")
	game.school._reset_session()
	var current_assignment: Dictionary=provider.generate("ETY155",12,"lab",4,155)
	check(evidence.supports(current_assignment).get("ok",false),"expert DC current-source hardware admitted")
	check(current_assignment.equipment_plan.ok,"current-source construction plan uses installed physical channels")
	game.queue_free();await process_frame
	print("LIVE CAMPUS checks=%d failures=%d"%[checks,failures]);quit(1 if failures else 0)

