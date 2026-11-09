extends RefCounted
const MathCourses=preload("res://scripts/campus_math_router.gd")
const Base=preload("res://scripts/campus/courses/course_provider.gd")
const Network=preload("res://scripts/ac_network.gd")
const Questions=preload("res://scripts/campus/courses/dc_assignments.gd")
func grade(assignment: Dictionary,answers: Dictionary) -> Dictionary:
	return MathCourses.grade(assignment,answers) if assignment.get("course_id","") in MathCourses.PATHS else Base.grade(assignment,answers)
func public_copy(assignment: Dictionary,marked := false) -> Dictionary:
	return MathCourses.public_copy(assignment,marked) if assignment.get("course_id","") in MathCourses.PATHS else Base.public_copy(assignment,marked)
func catalog() -> Array:return Base.catalog()+MathCourses.catalog()
func weeks(course: String,kind: String) -> Array:
	return MathCourses.weeks(course,kind) if course in MathCourses.PATHS else Base.weeks(course,kind)
func lesson(course: String,week: int,kind: String,duration: int=420,difficulty: int=2,seed_value: int=147) -> Dictionary:
	return MathCourses.lesson(course,week,kind,difficulty,seed_value,duration) if course in MathCourses.PATHS else Base.lesson(course,week,kind,duration)
func lesson_for_assignment(assignment: Dictionary,duration: int=420) -> Dictionary:
	var result:Dictionary=lesson(str(assignment.get("course_id","ELM253")),int(assignment.get("week",1)),str(assignment.get("kind","lecture")),duration,int(assignment.get("difficulty",2)),int(str(assignment.get("seed",147))))
	if assignment.get("physical_wire_steps") is Array and not assignment.physical_wire_steps.is_empty():
		result.equipment_text=str(assignment.get("procedure",""))
	return result
func paper_policy(assignment: Dictionary,practice := false) -> Dictionary:
	var config: Dictionary=assignment.get("assessment_policy",{})
	var policy := {"formula_allowed":practice or bool(config.get("formula_allowed",false)),"calculator_allowed":practice or bool(config.get("calculator_allowed",false)),"formula_sections":[]}
	if not policy.formula_allowed:return policy
	var plugin: Variant=MathCourses.provider(str(assignment.get("course_id","")))
	if plugin==null:return policy
	var reference: Dictionary=plugin.formula_reference()
	for section in reference.get("sections",[]):
		var formulas: Array=section.get("formulas",[]).duplicate(true)
		for entry in section.get("entries",[]):formulas.append({"text":str(entry.get("title","")),"ast":entry.get("formula",{})})
		policy.formula_sections.append({"id":str(section.get("id","")),"title":str(section.get("title","")),"formulas":formulas})
	return policy
func generate(course: String,week: int,kind: String,difficulty: int,seed_value: int) -> Dictionary:
	if course in MathCourses.PATHS:
		var generated: Dictionary=MathCourses.generate(course,week,kind,difficulty,seed_value)
		if generated.is_empty() or generated.has("error"):return generated
		generated.merge({"course_id":course,"week":week,"kind":"lecture","difficulty":difficulty,"lecture_only":true},true)
		if course=="MTH147":
			for question in generated.questions:question.id="m147."+str(question.id).sha256_text().substr(0,32)
		if not generated.has("title"):
			var sequence: Array=weeks(course,"lecture")
			generated.title=str(sequence[week-1].get("title",course)) if week>0 and week<=sequence.size() else course
		return generated
	var assignment := Base.generate(course,week,kind,difficulty,seed_value)
	if assignment.has("error"):return assignment
	if int(assignment.get("generator_schema",0))>=3:return preload("res://scripts/beginner_bench_instructions.gd").apply(assignment)
	if course=="ETY155":
		var plan: Dictionary=assignment.get("equipment_plan",{})
		var missing: Array=plan.get("missing_capabilities",[])
		missing=missing.filter(func(value):return value!="adjustable_current_source")
		plan.missing_capabilities=missing;plan.ok=missing.is_empty()
		if week==2:
			for device in plan.get("devices",[]):
				var old_id := str(device.get("catalog_id",""))
				if old_id.begins_with("r") and old_id.trim_prefix("r").is_valid_int():
					var measured_id := old_id+"_t5_w25"
					plan.catalog_counts[old_id]=int(plan.catalog_counts.get(old_id,1))-1
					if plan.catalog_counts[old_id]<=0:plan.catalog_counts.erase(old_id)
					plan.catalog_counts[measured_id]=int(plan.catalog_counts.get(measured_id,0))+1
					device.catalog_id=measured_id
			assignment.data+="\nUse the shop resistor labelled ±5%, 0.25 W for this practical. Each owned resistor has a real fixed manufactured value. Calculate the written theory answers from the stated nominal value; compare measured resistance with its tolerance range. Practical circuit grading uses the owned unit’s actual value."
		var index := 0
		for device in plan.get("devices",[]):
			if device.get("equipment","")=="adjustable_current_source":
				device.hardware_index=index
				device.positive_terminal="IS"+("" if index==0 else str(index+1))+"+"
				device.negative_terminal="IS"+("" if index==0 else str(index+1))+"-"
				device.instructions="For the requested a-to-b current arrow, connect the minus terminal to node a and the plus terminal to node b."
				index+=1
		return assignment
	if kind!="lab":return assignment
	var plan: Dictionary=assignment.get("physical_ac_plan",{})
	var banks: Array=[]
	if plan.has("phase_arms"):
		for i in plan.phase_arms.size():
			var arm: Dictionary=plan.phase_arms[i]
			for spec in [["R","resistance_ohms"],["L","inductance_henry"],["C","capacitance_farad"]]:
				if float(arm.get(spec[1],0))>0:banks.append({"kind":spec[0],"index":i,"value":arm[spec[1]],"a":arm.a,"b":arm.b})
	else:
		banks=[{"kind":"R","index":0,"value":600.0,"a":"A","b":"0"}]
		if week in [2,6]:
			banks[0].b="j";banks.append({"kind":"L","index":0,"value":1.6 if week==2 else 0.8,"a":"j","b":"0"})
		elif week in [3,7]:
			banks.append({"kind":"L","index":0,"value":1.6,"a":"A","b":"0"})
			if week==7:banks.append({"kind":"C","index":0,"value":4.4e-6,"a":"A","b":"0"})
		elif week in [4,8]:
			banks[0].b="j"
			banks.append({"kind":"L","index":0,"value":1.6,"a":"j","b":"0"})
			banks.append({"kind":"C","index":0,"value":4.4e-6,"a":"j","b":"0"})
		plan={"variable_level":0.5,"frequency_hz":60.0}
	plan.banks=banks
	plan.source_nodes={"A":"PV_A","0":"PV_N"}
	if plan.has("phase_arms"):plan.source_nodes.merge({"B":"PV_B","C":"PV_C"})
	var nodes: Array=["0"];var branches: Array=[]
	for node in plan.source_nodes:
		if node=="0":continue
		if not nodes.has(node):nodes.append(node)
		var phase := 0.0 if node=="A" else -TAU/3 if node=="B" else TAU/3
		branches.append({"id":"source_"+node,"type":"voltage","a":node,"b":"0","value":Vector2(cos(phase),sin(phase))*120.0*float(plan.variable_level)})
	var instructions: Array[String]=["PHYSICAL BENCH TASK (the calculation cases above are separate exercises)","Before wiring or rewiring, turn the power supply OFF and turn every R, L and C switch OFF. Open its drawer underneath the tabletop. Take one cable at a time, click the first socket, then click the second socket. Get another cable from the drawer for the next connection.","Set the large power-supply dial to %.1f%% and frequency to 60 Hz only after the wiring is complete. The red variable socket numbered 4 is PV_A. The yellow N socket beside 4/5/6 is PV_N. A socket is the round hole you plug a cable into."%(float(plan.variable_level)*100)]
	for bank in banks:
		for node in [bank.a,bank.b]:
			if not nodes.has(node):nodes.append(node)
		var z := Vector2(float(bank.value),0) if bank.kind=="R" else Vector2(0,TAU*60*float(bank.value)) if bank.kind=="L" else Vector2(0,-1/(TAU*60*float(bank.value)))
		var id: String=str(bank.kind)+str(bank.index)
		branches.append({"id":id,"type":"impedance","a":bank.a,"b":bank.b,"value":z})
		instructions.append("%s bank %d: enable only the switch labelled %s. Its top socket (%s_P) is node %s; its bottom socket (%s_N) is node %s."%["Resistance" if bank.kind=="R" else "Inductance" if bank.kind=="L" else "Capacitance",int(bank.index)+1,str(bank.value)+(" Ω" if bank.kind=="R" else " H" if bank.kind=="L" else " F"),id,bank.a,id,bank.b])
	instructions.append("Join sockets with the SAME node letter using cables. Node A includes power output 4. Node 0 includes the variable yellow N. Node j, when present, is just the join between components; it does not connect to the supply directly. For three-phase work, B is output 5 and C is output 6.")
	instructions.append("Measure the first resistor: with power OFF, connect the first voltmeter COM to R0_N and its yellow 100 V socket to R0_P. For current, insert the first ammeter in the wire feeding R0_P: move that wire to the ammeter ± socket, then add a cable from its 0.5 A socket to R0_P. Do not connect both ammeter sockets across the resistor. Set the meter ranges before turning power ON, then use Record equipment on your sheet. Afterwards turn power OFF before moving any leads or rewiring.")
	var result := Network.new().solve(nodes,branches)
	if result.fault!="":return {"error":result.fault}
	var first: Dictionary=branches.filter(func(item):return item.id=="R0")[0]
	var volts: Vector2=result.voltages[first.a]-result.voltages[first.b]
	assignment.questions.append(Questions.numeric("Physical bench task: RMS voltage across R0",volts.length(),"V","Solve the explicitly stated physical network; then compare with the correctly connected voltmeter."))
	assignment.questions.append(Questions.numeric("Physical bench task: RMS current through R0",result.currents.R0.length(),"A","Use the R0 voltage divided by its resistance, and compare with the in-series ammeter."))
	assignment.physical_ac_plan=plan
	assignment.reference_ac={"nodes":nodes,"branches":branches,"result":result}
	assignment.data+="\n\n"+"\n".join(instructions)
	assignment.procedure="\n".join(instructions)
	return assignment

