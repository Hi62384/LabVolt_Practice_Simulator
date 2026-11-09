extends SceneTree
const Provider=preload("res://scripts/campus/courses/course_provider.gd")
const State=preload("res://scripts/lab_state.gd")
const Adapter=preload("res://scripts/campus_equipment_adapter.gd")
const Catalog=preload("res://scripts/equipment_catalog.gd")
class SessionData extends RefCounted:
	var labs: Array=[]
class Host extends Node:
	var session := SessionData.new()
var checks := 0
var failures := 0
func check(value: bool,label: String) -> void:
	checks+=1
	if not value:failures+=1;push_error(label)
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var host := Host.new();root.add_child(host)
	await process_frame
	var adapter := Adapter.new(host)
	for week in range(1,9):
		for d in range(5):
			for seed_value in [1,155,902]:
				var a := Provider.generate("ELM253",week,"lab",d,seed_value)
				a.assessment_id="ac.%d.%d.%d"%[week,d,seed_value]
				check(adapter.supports(a).ok,"Integrated AC adapter accepts generated plan")
				var plan: Dictionary=a.physical_ac_plan
				var ids: Array=["PV_A","PV_B","PV_C","PV_N","P_N"]
				for kind in ["R","L","C"]:
					for i in range(3):ids.append("%s%d_P"%[kind,i]);ids.append("%s%d_N"%[kind,i])
				for i in range(3):
					for suffix in ["IN","OUT","2_5","8","25"]:ids.append("AM%d_%s"%[i,suffix])
					for suffix in ["COM","150","300"]:ids.append("V%d_%s"%[i,suffix])
				var lab := State.new();lab.initialize(ids,{})
				lab.level=plan.variable_level;lab.frequency=plan.frequency_hz
				var nodes: Dictionary=plan.source_nodes.duplicate()
				var serial := 1
				for bank in plan.banks:
					var id: String=str(bank.kind)+str(bank.index)
					var index: int=Catalog.LOADS[bank.kind].values.find(bank.value)
					check(index>=0,"Exact installed bank value")
					lab.switches[bank.kind][int(bank.index)*3+index]=true
					for pair in [[bank.a,id+"_P"],[bank.b,id+"_N"]]:
						if not nodes.has(pair[0]):nodes[pair[0]]=pair[1]
						else:lab.cables.append({"id":serial,"a":nodes[pair[0]],"b":pair[1],"owner":0,"color":0});serial+=1
				for lead in lab.cables:
					if lead.b=="R0_P":lead.b="AM0_IN";break
				for pair in [["AM0_OUT","R0_P"],["V0_COM","R0_N"],["V0_150","R0_P"]]:
					lab.cables.append({"id":serial,"a":pair[0],"b":pair[1],"owner":0,"color":0});serial+=1
				host.session.labs=[lab]
				lab.powered=true;lab.recalculate()
				check(lab.powered and lab.readings.fault=="","Actual switches/cables solve without trip")
				check(adapter.record_measurement(1,0,a),"Authoritative adapter records actual AC meters")
				var evidence := adapter.capture(1,0,a)
				var marked := adapter.grade(a,evidence)
				check(evidence.get("topology",false) and marked.get("operating_point",false),"Actual topology and operating point accepted")
				check(float(marked.score)>=80,"Actual meters add credit beyond calculated topology")
				for q in a.questions:
					if q.template_id=="ac.physical.voltage":check(absf(float(q.answer)-float(lab.readings.bank_voltages.R0))<maxf(1e-6,float(q.answer)*.02),"Physical voltage key includes loading tolerance")
					if q.template_id=="ac.physical.current":check(absf(float(q.answer)-float(lab.readings.bank_currents.R0))<maxf(1e-6,float(q.answer)*.02),"Physical current key includes loading tolerance")
				lab.cables.pop_back();lab.recalculate()
				adapter.ac_observations.clear()
				adapter.record_measurement(1,0,a)
				check(not adapter.capture(1,0,a).get("observations",{}).has("voltage"),"Disconnected voltage probe cannot create a new voltage observation")
	host.queue_free()
	print("AC BUILDABILITY cases=120 checks=%d failures=%d"%[checks,failures])
	quit(1 if failures else 0)
