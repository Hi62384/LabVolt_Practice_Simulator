extends RefCounted
## Constructed only by the host. No client supplies snapshots, bindings or marks.
const Solver = preload("res://scripts/electronics_solver.gd")
var game: Node
var observations := {}
var verified_steps := {}
var retained_measurements := {}
var search_budget := 0

func _init(owner_game: Node=null) -> void:
	game=owner_game

func _key(peer: int,bench: int,assignment: Dictionary) -> String:
	var identity := str(peer)
	if game!=null and "school" in game and is_instance_valid(game.school):identity=str(game.school.identities.get(peer,identity))
	return str(assignment.get("assessment_id",assignment.get("seed",0)))+":"+identity+":"+str(bench)

func recovery_state() -> Dictionary:
	return {"observations":observations,"verified_steps":verified_steps,"retained_measurements":retained_measurements}

func restore_recovery(data: Dictionary) -> void:
	observations=data.get("observations",{}).duplicate(true)
	verified_steps=data.get("verified_steps",{}).duplicate(true)
	retained_measurements=data.get("retained_measurements",{}).duplicate(true)

func supports(assignment: Dictionary) -> Dictionary:
	if assignment.get("course_id","")!="ETY155":return {"ok":false,"error":"An authoritative AC experiment rubric adapter is required for this ELM253 practical. Lecture and legacy classes remain available."}
	if assignment.get("reference_parts",[]).is_empty():return {"ok":false,"error":"The practical has no validated physical circuit specification."}
	for capability in assignment.get("practical",{}).get("capabilities",[]):
		if capability=="adjustable_current_source":
			if game==null or not is_instance_valid(game.dc_lab):return {"ok":false,"error":"Physical current-source hardware is unavailable."}
			var count: int=assignment.get("reference_parts",[]).filter(func(part):return part.kind=="I").size()
			if count>int(game.dc_lab.equipment_capabilities(0).get("current_source_instances",0)):return {"ok":false,"error":"Not enough independent physical current sources."}
	return {"ok":true,"error":""}

func capture(peer: int,bench: int,assignment: Dictionary) -> Dictionary:
	if game==null or not game.multiplayer.is_server() or assignment.get("course_id","")!="ETY155":return {}
	if not is_instance_valid(game.dc_lab) or bench<0 or bench>=game.dc_lab.benches.size():return {}
	var station=game.dc_lab.benches[bench]
	# Cross-bench circuits require the combined authority solver, never a partial local solution.
	if station.linked:return {"error":"Disconnect cross-bench links before an individual practical assessment."}
	var wires: Array=station.wires.duplicate(true)
	if not station.board.is_empty():wires.append_array(preload("res://scripts/breadboard_model.gd").expand(station.board).wires)
	var key := _key(peer,bench,assignment)
	var evidence := snapshot(station.netlist(),wires,assignment)
	var signature := _passive_signature(station.netlist(),wires)
	if not evidence.get("topology",false) and not station.master and not station.generator.enabled and retained_measurements.has(key):
		var retained: Dictionary=retained_measurements[key]
		if signature==retained.signature and station.channels==retained.channels and station.generator==retained.generator:
			evidence=retained.evidence.duplicate(true)
			evidence.retained_after_power_off=true
	evidence.observations=observations.get(key,{}).duplicate(true)
	evidence.verified_procedure=verified_steps.get(key,[]).duplicate()
	evidence.meter_mode=station.meter_mode
	evidence.meter_range=station.meter_range
	evidence.fuse=station.fuse
	return evidence

func _passive_signature(parts: Array,wires: Array) -> String:
	var passive: Array=[]
	for part in parts:
		if part.kind not in ["V","I","supply","current_source"]:passive.append(part)
	return var_to_bytes([passive,wires]).hex_encode().sha256_text()

func snapshot(parts: Array,wires: Array,assignment: Dictionary) -> Dictionary:
	if parts.size()>96:return {}
	var result := Solver.new().solve(parts,wires)
	if not result.get("ok",false):return {"error":result.get("error","Invalid equipment circuit")}
	var roots := _roots(parts,wires)
	# The actual meter shunt remains in the electrical calculation. For connectivity
	# matching only, its two terminals represent an instrument inserted in a lead.
	for part in parts:
		if str(part.id)=="ammeter" and part.kind=="R":
			roots[Solver.root(roots,str(part.a))]=Solver.root(roots,str(part.b))
	search_budget=5000
	var match_result := _match(assignment.get("reference_parts",[]),parts,roots,0,{}, {}, {})
	return {"parts":parts.duplicate(true),"wires":wires.duplicate(true),"result":result,"bindings":match_result.get("bindings",{}),"nodes":match_result.get("nodes",{}),"topology":not match_result.is_empty(),"capabilities":[],"observations":{},"verified_procedure":[]}

func _roots(parts: Array,wires: Array) -> Dictionary:
	var parent := {}
	for part in parts:
		parent[str(part.a)]=str(part.a);parent[str(part.b)]=str(part.b)
	for wire in wires:
		for pin in wire:parent[str(pin)]=str(pin)
	for wire in wires:
		if wire.size()==2:parent[Solver.root(parent,str(wire[0]))]=Solver.root(parent,str(wire[1]))
	return parent

func _match(expected: Array,actual: Array,roots: Dictionary,index: int,bindings: Dictionary,nodes: Dictionary,used: Dictionary) -> Dictionary:
	search_budget-=1
	if search_budget<0 or expected.is_empty():return {}
	if index==expected.size():return {"bindings":bindings,"nodes":nodes}
	var wanted: Dictionary=expected[index]
	for part in actual:
		var kind := str(part.kind)
		if kind=="supply" and wanted.kind=="V":kind="V"
		if kind=="current_source" and wanted.kind=="I":kind="I"
		if kind!=str(wanted.kind) or used.has(str(part.id)):continue
		if absf(float(part.get("nominal_value",part.get("value",INF)))-float(wanted.value))>maxf(1e-9,absf(float(wanted.value))*.01):continue
		if str(part.id) in ["ammeter","vmeter","S1","S2"]:continue
		var orientations := [[str(part.b),str(part.a)]] if part.kind=="current_source" else [[str(part.a),str(part.b)]]
		if kind=="R":orientations.append([str(part.b),str(part.a)])
		for orientation in orientations:
			var next_nodes := nodes.duplicate()
			var valid := true
			for pair in [[str(wanted.a),orientation[0]],[str(wanted.b),orientation[1]]]:
				var root := Solver.root(roots,pair[1])
				if next_nodes.has(pair[0]) and next_nodes[pair[0]]!=root:valid=false;break
				if not next_nodes.has(pair[0]) and next_nodes.values().has(root):valid=false;break
				next_nodes[pair[0]]=root
			if not valid:continue
			var next_bindings := bindings.duplicate();next_bindings[str(wanted.id)]=str(part.id)
			var next_used := used.duplicate();next_used[str(part.id)]=true
			var answer := _match(expected,actual,roots,index+1,next_bindings,next_nodes,next_used)
			if not answer.is_empty():return answer
	return {}

func record_measurement(peer: int,bench: int,assignment: Dictionary) -> bool:
	var evidence := capture(peer,bench,assignment)
	if evidence.is_empty() or not evidence.get("topology",false):return false
	var target := str(evidence.bindings.get(str(assignment.get("practical",{}).get("target","")),""))
	var component := {}
	for part in evidence.parts:
		if str(part.id)==target:component=part;break
	if component.is_empty():return false
	var roots := _roots(evidence.parts,evidence.wires)
	var result: Dictionary=evidence.result
	var key := _key(peer,bench,assignment)
	if not observations.has(key):observations[key]={}
	var mode := str(evidence.meter_mode)
	var measured := 0.0
	var correct := false
	var quantity := ""
	if mode=="DC V":
		quantity="voltage"
		correct=Solver.root(roots,"VΩ")==Solver.root(roots,str(component.a)) and Solver.root(roots,"COM")==Solver.root(roots,str(component.b))
		measured=float(result.v.get("VΩ",0))-float(result.v.get("COM",0))
	elif mode=="DC A" and not evidence.fuse:
		quantity="current"
		measured=float(result.i.get("ammeter",0))
		var a := Solver.root(roots,"A");var b := Solver.root(roots,"COM")
		var ca := Solver.root(roots,str(component.a));var cb := Solver.root(roots,str(component.b))
		correct=a!=b and ((a==ca or b==ca) or (a==cb or b==cb)) and absf(measured-float(result.i.get(target,INF)))<=maxf(1e-8,absf(measured)*.02)
	if quantity=="":return false
	correct=correct and is_finite(measured) and (float(evidence.meter_range)<=0 or absf(measured)<=float(evidence.meter_range))
	if not correct:return false
	observations[key][quantity]={"component_id":target,"value_si":measured,"correct_connection":true,"mode":"V" if quantity=="voltage" else "A","time":Time.get_unix_time_from_system()}
	var station=game.dc_lab.benches[bench]
	retained_measurements[key]={"signature":_passive_signature(evidence.parts,evidence.wires),"channels":station.channels.duplicate(true),"generator":station.generator.duplicate(true),"evidence":evidence.duplicate(true)}
	if float(evidence.meter_range)>0:record_verified_step(peer,bench,assignment,"range_checked")
	return true

func grade(assignment: Dictionary,evidence: Dictionary,_student_procedure: Dictionary={}) -> Dictionary:
	if not evidence.get("topology",false):return {"score":0.0,"verified":false,"reason":"Required components and actual electrical connectivity were not found."}
	var actual: Dictionary=evidence.result
	var reference: Array=assignment.get("reference_parts",[]).duplicate(true)
	for wanted in reference:
		if wanted.kind!="R":continue
		var actual_id := str(evidence.bindings.get(str(wanted.id),""))
		for part in evidence.parts:
			if str(part.id)==actual_id and part.get("physical_resistor",false) and float(part.get("nominal_value",0))==float(wanted.value):wanted.value=part.value
	var expected := Solver.new().solve(reference,[])
	if not expected.get("ok",false):return {"score":0.0,"verified":false,"reason":"Invalid reference network."}
	var operating := true
	for wanted in assignment.get("reference_parts",[]):
		var id := str(evidence.bindings.get(str(wanted.id),""))
		for field in ["drop","i"]:
			var target := absf(float(expected.get(field,{}).get(wanted.id,INF)))
			var observed := absf(float(actual.get(field,{}).get(id,INF)))
			if not is_finite(target) or not is_finite(observed) or absf(target-observed)>maxf(1e-7,target*.02):operating=false
	var score := 40.0 if operating else 0.0
	var measurement_count := 0
	for quantity in ["voltage","current"]:
		var observation: Dictionary=evidence.get("observations",{}).get(quantity,{})
		var target_id := str(evidence.bindings.get(str(assignment.get("practical",{}).get("target","")),""))
		var field := "drop" if quantity=="voltage" else "i"
		var value := float(actual.get(field,{}).get(target_id,INF))
		var recorded := float(observation.get("value_si",INF))
		if observation.get("correct_connection",false) and observation.get("component_id","")==target_id and is_finite(value) and is_finite(recorded) and absf(value-recorded)<=maxf(1e-7,absf(value)*.02):measurement_count+=1
	score+=15.0*measurement_count
	var steps := 0
	for step in ["power_off_before_wiring","range_checked","power_off_after_measurement"]:
		if step in evidence.get("verified_procedure",[]):steps+=1
	return {"score":score+10.0*steps,"verified":true,"connectivity":true,"operating_point":operating,"measurement_count":measurement_count,"procedure_count":steps,"reason":"Host netlist, shared solver and actual instrument evidence."}

func record_verified_step(peer: int,bench: int,assignment: Dictionary,step: String) -> void:
	# Called only by the authority after verifying an actual equipment transition.
	if game==null or not game.multiplayer.is_server():return
	if step not in ["power_off_before_wiring","range_checked","power_off_after_measurement"]:return
	var key := _key(peer,bench,assignment)
	if not verified_steps.has(key):verified_steps[key]=[]
	if step not in verified_steps[key]:verified_steps[key].append(step)

func observe_action(peer: int,bench: int,assignment: Dictionary,op: String,before_parts: Array) -> void:
	if game==null or not game.multiplayer.is_server() or bench<0 or bench>=game.dc_lab.benches.size():return
	var station=game.dc_lab.benches[bench]
	var before_live := before_parts.any(func(part):return part.kind in ["V","I","supply","current_source"] and absf(float(part.get("value",0)))>1e-12)
	var after_live: bool=station.netlist().any(func(part):return part.kind in ["V","I","supply","current_source"] and absf(float(part.get("value",0)))>1e-12)
	if op in ["wire","unwire","board","resistor"] and not before_live:record_verified_step(peer,bench,assignment,"power_off_before_wiring")
	if op in ["master","channel","current_source"] and before_live and not after_live:
		var key := _key(peer,bench,assignment)
		if observations.get(key,{}).size()==2:record_verified_step(peer,bench,assignment,"power_off_after_measurement")
