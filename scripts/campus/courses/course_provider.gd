extends RefCounted
const Legacy = preload("res://scripts/course_generator.gd")
const DC = preload("res://scripts/campus/courses/dc_assignments.gd")
const Quantity = preload("res://scripts/campus/courses/quantity.gd")
const LegacyLesson = preload("res://scripts/lesson_content.gd")
const DIFFICULTIES = ["Beginner","Easy","Normal","Hard","Expert"]
const AC_LABS = [0,2,3,4,5,2,6,4]
const AC_LAB_TITLES = ["Equipment familiarization","Single-phase series AC","Parallel AC and power","Series-parallel AC","Three-phase power","Basic AC practical test","Three-phase PF correction","Integrated AC capstone"]
const AC_FILES = ["ELM253 Lab1 Familiarization with Lab Equipment.pdf","Lec 1 - Sinusoidal Alternating waveforms.pdf; Lec 2 - Basic AC curcuits and power, Phasors.pdf","ELM253 Lab2 1Ø Series AC Circuits.pdf","ELM253 Lab3 1Ø Parallel AC Circuits and Power.pdf","ELM253 Lab4 Series-Parallel AC Circuits.pdf; ELM253 Lab6 LabTest1 Practice.pdf","ELM253 Lab5 3Ø AC Power.pdf","ELM253 Lab7 3Ø AC PF Correction.pdf","1a ELM253 Three-Phase AC Induction Motors Fall 2025.pdf; 1b ELM253 Electrical machines and Three-phase Induction motors Fall 2025.pdf","Lec 8 Transformers Nov 2025.pdf","1d ELM253 - Inverters Fall 2025.pdf","1 Lec 5 - Magnetism and Electromagnetism.pdf"]
const AC_PAGES = ["1-5","1-34;1-44","1-7","1-6","1-6;1-4","1-5","1-3","1-13;1-52","1-7","1-10","1-15"]
static var _dc_rows: Array=[]
static func catalog() -> Array:
	return [{"id":"ELM253","course_id":"ELM253","title":"AC Electrical Systems","subject":"Electrical","description":"Study AC waveforms, single-phase and three-phase circuits, and electrical machines through lectures and practical labs.","icon":"ac_wave","lecture_weeks":11,"lab_weeks":8,"sequence_status":"Source-derived proposed simulator sequence; supplied labs 1-7 plus original capstone"},{"id":"ETY155","course_id":"ETY155","title":"Basic DC Electricity","subject":"Electrical","description":"Study DC circuit fundamentals, network analysis, and electrical measurements through lectures and practical labs.","icon":"dc_nodes","lecture_weeks":12,"lab_weeks":12,"sequence_status":"Proposed 12-week organization requested by user; not an official timetable"}]
static func dc_content() -> Array:
	if _dc_rows.is_empty():_dc_rows=JSON.parse_string(FileAccess.get_file_as_string("res://assets/campus/courses/ety155.json"))
	return _dc_rows.duplicate(true)
static func weeks(course_id: String,kind: String="lecture") -> Array:
	if kind not in ["lecture","lab"]:return []
	var result: Array=[]
	if course_id=="ETY155":
		for row in dc_content():result.append({"week":int(row.week),"title":row.title,"topics":[row.title],"source":row.source,"equipment":row.equipment,"kind":kind,"sequence_status":"proposed","lab_capability_gate":"adjustable_current_source" if int(row.week)==12 and kind=="lab" else ""})
	elif course_id=="ELM253":
		for i in range(AC_LABS.size() if kind=="lab" else Legacy.TOPICS.size()):
			var topic: int=AC_LABS[i] if kind=="lab" else i
			result.append({"week":i+1,"title":AC_LAB_TITLES[i] if kind=="lab" else Legacy.TOPICS[topic],"topics":[Legacy.TOPICS[topic]],"topic":topic,"kind":kind,"source":{"document":AC_FILES[topic],"pages":AC_PAGES[topic],"supplement":"ELM253.docx headings cross-checked; notes are not an answer authority"},"equipment":["AC supply","R/L/C banks","AC voltmeter","AC ammeter","wattmeter"],"sequence_status":"proposed"})
			if kind=="lab" and i==5:result[-1].source={"document":"ELM253 Lab6 LabTest1 Practice.pdf","pages":"1-4","basis":"Source-derived series and parallel practical test"}
			if kind=="lab" and i==7:result[-1].source={"document":"ELM253 Labs2-7","pages":"See individual lab references","basis":"Original integrated capstone, not a supplied eighth lab"}
	return preload("res://scripts/campus/academics/grade_weight_policy.gd").decorate(course_id,kind,result)
static func teaching(course_id: String,kind: String,week: int) -> Dictionary:
	return lesson(course_id,week,kind)
static func lesson(course_id: String,week: int,kind: String="lecture",duration_seconds: int=420) -> Dictionary:
	var list := weeks(course_id,kind)
	if week<1 or week>list.size():return {"error":"Unknown course, kind or week"}
	var meta: Dictionary=list[week-1].duplicate(true)
	var explanation := "";var formulas := "";var worked := "";var procedure := "";var checkpoint := "";var response := ""
	if course_id=="ETY155":
		var row: Dictionary=dc_content()[week-1]
		explanation=row.explanation;formulas=row.formulas;worked=row.worked;procedure=row.procedure
		checkpoint=row.checkpoint.prompt;response=row.checkpoint.answer;meta.objectives=row.objectives
	else:
		var topic: int=meta.topic
		var sample := Legacy.generate(topic,0,253)
		var guide := LegacyLesson.teaching(topic)
		explanation=sample.theory;formulas=sample.theory;worked=guide.worked;procedure=guide.equipment+"\n"+sample.procedure
		if topic==5:
			explanation+=" In balanced delta, Vphase = Vline and Iline = sqrt(3) Iphase. For an unbalanced load, sum individual complex powers and obtain line currents from signed node-current sums. A single arbitrary line-current reading cannot be used in the balanced total-power shortcut."
			formulas+=" Delta: VL = Vphase; IL = sqrt(3) Iphase (balanced only). Unbalanced: Stotal = sum(Vphase × conjugate(Iphase))."
		checkpoint="Predict a sign, phase relationship or magnitude before calculating. Explain why the instrument location measures the requested quantity."
		response="Check the named reference, actual nodes, RMS convention and equipment range. Compare calculations with the stated model and physical instrument loading."
		meta.objectives=["Explain "+meta.title,"Derive the governing relationships before substitution","Build and compare supported equipment measurements"]
	var duration := clampi(duration_seconds,300,600)
	var captions: Array=[
		"Today: "+meta.title+". "+"; ".join(meta.objectives)+". First sketch what you expect, and name the measured quantity and its unit.",
		explanation+"\n"+formulas+"\nPause to define every symbol, reference node and polarity. Identify assumptions before substituting numbers. Work in base SI units and carry precision to the last step.",
		worked+"\nWrite the equation on the board, substitute each value with its unit, and show the intermediate result. Check dimensions and whether the final sign or magnitude matches the prediction. Now change one stated value and predict the direction of the response before calculating again.",
		procedure+"\nWith power isolated, trace each node aloud and check meter range and connection mode. Record a prediction first, then a measurement. Explain any difference using the actual model, tolerance, loading or an incorrect connection; do not edit a measurement to match the prediction.",
		checkpoint+"\nDiscuss your reasoning or calculate independently before revealing the feedback.\nFeedback: "+response,
		"Reconcile your prediction, calculation and observation for "+meta.title+". State which assumptions mattered. Keep all intermediate precision, label the final quantity and units, and identify the next safe step. Your assessment uses its own explicitly stated values; this worked example is not its answer key."
	]
	var weights := [0.08,0.23,0.25,0.24,0.13,0.07]
	var names := ["Objectives and prediction","Theory and derivation","Worked example","Practical demonstration" if kind=="lab" else "Guided application","Check understanding","Synthesis and assessment briefing"]
	var stages: Array=[];var at := 0
	for i in range(6):
		var end := duration if i==5 else at+int(round(duration*float(weights[i])))
		stages.append({"id":"%s.%s.%d.%d"%[course_id,kind,week,i],"start_seconds":at,"duration_seconds":end-at,"duration":end-at,"title":names[i],"caption":captions[i],"text":captions[i],"formulas":formulas if i in [1,2] else "","worked":worked if i==2 else "","highlight":i,"interaction":"predict, calculate or explain" if i in [0,2,4] else "demonstrate"})
		at=end
	meta.merge({"course_id":course_id,"duration_seconds":duration,"duration":duration,"presentation_id":"%s.%s.%d.v1"%[course_id,kind,week],"stages":stages,"timeline":stages,"theory":explanation,"formulas":formulas,"worked":worked,"equipment_text":procedure,"procedure":procedure,"equipment":meta.equipment,"diagram":{"type":"original_concept","asset":"res://assets/campus/courses/dc_concepts.svg" if course_id=="ETY155" else "","legacy_topic":meta.get("topic",0)},"source_gates":[],"source_notes":"Original randomized scenarios follow documented concepts and representative diagram conventions; no full PDF transcription/review gate."},true)
	if course_id=="ETY155":meta.diagram=dc_content()[week-1].worked_diagram
	return meta
static func generate(course_id: String,week: int,kind: String,difficulty: int,seed_value: int) -> Dictionary:
	var info := lesson(course_id,week,kind)
	if info.has("error"):return info
	var d := clampi(difficulty,0,4)
	var assignment: Dictionary={}
	if course_id=="ETY155":assignment=DC.build(week,d,seed_value)
	else:
		assignment=Legacy.generate(int(info.topic),mini(d,2),seed_value)
		if kind=="lab" and week==5:assignment=preload("res://scripts/campus/courses/ac_assignments.gd").three_phase(d,seed_value)
		if kind=="lab" and week==6:
			var parallel := Legacy.generate(3,mini(d,2),seed_value+6)
			assignment.data+="\nParallel practical-test part:\n"+parallel.data
			for question in parallel.questions:
				var copy: Dictionary=question.duplicate(true);copy.prompt="Parallel practical-test part: "+str(copy.prompt);assignment.questions.append(copy)
		# Preserve old parameter semantics while five-level course tasks add additional
		# independent analyses rather than merely changing displayed difficulty labels.
		if d>=1:
			var extra := Legacy.generate(int(info.topic),mini(d,2),seed_value+253)
			assignment.data+="\nIndependent extension case:\n"+extra.data
			for i in range(mini(d,extra.questions.size())):
				var q: Dictionary=extra.questions[i].duplicate(true);q.prompt="Extension case: "+str(q.prompt);assignment.questions.append(q)
			if d>=3:
				for i in range(extra.questions.size()):
					if not extra.questions[i].options.is_empty() or not assignment.questions[i].options.is_empty():continue
					var difference := DC.numeric("Signed change, extension minus base case: "+str(extra.questions[i].prompt),float(extra.questions[i].answer)-float(assignment.questions[i].answer),str(extra.questions[i].unit),"Solve both independently, retain sign, and compare the two operating conditions.")
					difference.template_id="difference."+str(extra.questions[i].template_id)
					difference.inputs={"generator":"difference.v3","base":assignment.questions[i].get("inputs",assignment.get("scenario",{})),"base_prompt":assignment.questions[i].prompt,"base_template":assignment.questions[i].get("template_id",""),"extension":extra.questions[i].inputs,"extension_template":extra.questions[i].template_id}
					assignment.questions.append(difference)
					break
		assignment.practical={"capabilities":["ac_bench"],"rubric":{"connectivity":40,"measurements":30,"procedure":30},"requires_host_adapter":true}
		if not assignment.has("diagram"):assignment.diagram={"kind":"legacy_ac","topic":info.topic}
	if assignment.has("error"):return assignment
	assignment.merge({"course_id":course_id,"week":week,"kind":kind,"difficulty":d,"difficulty_name":DIFFICULTIES[d],"title":info.title,"topic":info.get("topic",0),"theory":info.theory,"procedure":info.procedure,"source":info.source,"seed":seed_value,"source_gates":info.source_gates,"teaching_id":info.presentation_id,"is_exam":bool(info.get("is_exam",false)),"assessment_type":info.get("assessment_type","assignment"),"grade_weight":info.get("grade_weight"),"assessment_policy":{"practice_never_official":true,"default_seconds":1800,"gradebook_owner":"academics"}},true)
	if course_id=="ETY155":assignment.equipment_plan=preload("res://scripts/campus/courses/equipment_plan.gd").for_assignment(assignment)
	assignment.teaching={"equipment":info.equipment_text,"worked":info.worked}
	assignment.equipment_text=info.equipment_text
	assignment.worked_example=info.worked
	if course_id=="ELM253" and kind=="lab":
		var physical := preload("res://scripts/campus/courses/ac_lab_plan.gd").build(week,d,seed_value,assignment.get("physical_ac_plan",{}))
		if physical.has("error"):return physical
		assignment.physical_ac_plan=physical.plan
		assignment.reference_ac=physical.reference
		assignment.questions.append_array(physical.questions)
		assignment.data+="\n\n"+str(physical.instructions)
		assignment.procedure=physical.instructions
		assignment.diagram=physical.diagram
	for i in range(assignment.questions.size()):
		if not assignment.questions[i].has("template_id"):assignment.questions[i].template_id="%s.%d.d%d.%d"%[course_id,week,d,i]
	assignment.generator_schema=3
	return assignment
static func grade(assignment: Dictionary,answers: Dictionary) -> Dictionary:
	var feedback: Array=[];var earned := 0
	for i in range(assignment.get("questions",[]).size()):
		var q: Dictionary=assignment.questions[i];var raw := str(answers.get(str(i),"")).strip_edges()
		var check := {"correct":false,"reason":"Select an answer."}
		if not q.get("options",[]).is_empty():check.correct=raw.is_valid_int() and int(raw)==int(q.answer)
		else:check=Quantity.check(q,raw)
		if check.correct:earned+=1
		feedback.append({"correct":check.correct,"reason":check.reason,"expected":q.options[int(q.answer)] if not q.get("options",[]).is_empty() else "%.9f %s"%[q.answer,q.unit],"explanation":q.explanation})
	return {"score":100.0*earned/maxi(1,feedback.size()),"feedback":feedback,"scope":"written_only"}
static func public_copy(assignment: Dictionary,marked: bool=false) -> Dictionary:
	var copy := assignment.duplicate(true)
	copy.erase("reference_parts");copy.erase("reference_result")
	copy.erase("reference_ac")
	if copy.has("practical"):copy.practical.erase("variants")
	if not marked:
		copy.erase("scenario");copy.erase("extension_scenarios")
		for q in copy.get("questions",[]):q.erase("answer");q.erase("explanation");q.erase("inputs")
	return copy
static func validate_practical(assignment: Dictionary,evidence: Dictionary) -> Dictionary:
	return preload("res://scripts/campus/courses/practical_validation.gd").validate(assignment,evidence)
