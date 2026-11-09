extends RefCounted
const Generator = preload("res://scripts/mth147/generator.gd")
const Validator = preload("res://scripts/mth147/validator.gd")
const Grader = preload("res://scripts/mth147/grader.gd")
const Curriculum = preload("res://scripts/mth147/curriculum.gd")
const Core = preload("res://scripts/mth147/math_core.gd")
const DIFFICULTIES = ["Beginner","Easy","Normal","Hard","Expert"]
const VERSION: int=1

static func catalog() -> Array:
	return [{"id":"MTH147","course_id":"MTH147","title":"Mathematics for Technology","subject":"Mathematics","description":"Nine lecture units in algebra, exact arithmetic, trigonometry and sinusoidal mathematics, with procedural assessments.","icon":"res://assets/mth147/course_icon.svg","lecture_weeks":9,"lab_weeks":0,"lecture_only":true,"kinds":["lecture"],"difficulties":DIFFICULTIES,"practice_location":"existing classroom/study/library"}]

static func weeks(kind: String="lecture") -> Array:
	return Curriculum.weeks(kind)

static func generate_problem(generator_id: String,difficulty: int,seed_value: int) -> Dictionary:
	if generator_id not in Generator.ids() or difficulty<0 or difficulty>4:return {"error":"Unsupported generator or difficulty."}
	if seed_value<0 or seed_value>0x7fffffffffffffff-4000000:return {"error":"Seed outside supported nonnegative bounded range."}
	for attempt in range(32):
		# Stable bounded local stream; no global RNG and no hidden mutable generator cache.
		var actual_seed := seed_value+attempt*104729
		if actual_seed>0x7fffffffffffffff-4000000:return {"error":"Seed outside supported bounded range."}
		var problem := Generator.new().generate(generator_id,difficulty,actual_seed)
		var verified := Validator.verify(problem)
		if not verified.ok:continue
		problem.seed=str(seed_value);problem.id="mth147.v1.%s.%d.%d"%[generator_id,difficulty,seed_value]
		problem.parameters.generation_seed=str(actual_seed);problem.parameters.generation_attempt=attempt
		problem.verification=verified
		var canonical := seal(problem)
		if canonical.has("error") or not Validator.verify(canonical).ok:continue
		return canonical
	return {"error":"No valid bounded instance after 32 deterministic attempts.","generator_id":generator_id,"seed":str(seed_value)}

static func generate(week: int,difficulty: int,seed_value: int,count: int=8,focus: String="") -> Dictionary:
	if week<1 or week>9 or difficulty<0 or difficulty>4 or count<1 or count>24:return {"error":"Invalid week, difficulty or question count."}
	var scope := Curriculum.focus_for(week,difficulty,focus)
	if scope.has("error"):return scope
	var rng := RandomNumberGenerator.new();rng.seed=seed_value
	var order: Array=scope.types.duplicate()
	for i in range(order.size()-1,0,-1):
		var j := rng.randi_range(0,i);var temp: Variant=order[i];order[i]=order[j];order[j]=temp
	var questions: Array=[]
	for i in range(count):
		var id := "w%d.%s"%[week,order[i%order.size()]]
		var problem := generate_problem(id,difficulty,int(rng.randi()))
		if problem.has("error"):return problem
		questions.append(problem)
	return seal({"version":VERSION,"engine":"MTH147.engine.v1","course_id":"MTH147","week":week,"kind":"lecture","lecture_only":true,"difficulty":difficulty,"difficulty_name":DIFFICULTIES[difficulty],"seed":str(seed_value),"focus":scope.id,"title":Curriculum.UNITS[week-1].title,"questions":questions,"question_count":count,"theory":"\n".join(Curriculum.UNITS[week-1].rules),"equipment":[],"assessment_policy":{"practice_never_official":true,"default_seconds":clampi(1200+difficulty*180,600,2400),"host_grading_only":true,"persist_before_timer":true,"gradebook_owner":"academics","currency_owner":"academics"}})

static func check(problem: Dictionary,answer: Variant) -> Dictionary:
	return Grader.check(problem,answer)

static func practice(topic_ids: Array,difficulty: int,seed_value: int,count: int=8) -> Dictionary:
	# A mixed-unit practice paper is explicitly ineligible for official records.
	if topic_ids.is_empty() or topic_ids.size()>79 or difficulty<0 or difficulty>4 or count<1 or count>24:return {"error":"Invalid practice topic selection."}
	for id in topic_ids:
		if str(id) not in Generator.ids():return {"error":"Unknown practice generator."}
	var rng := RandomNumberGenerator.new();rng.seed=seed_value
	var selected: Array=topic_ids.duplicate()
	for i in range(selected.size()-1,0,-1):
		var j := rng.randi_range(0,i);var temp: Variant=selected[i];selected[i]=selected[j];selected[j]=temp
	var questions: Array=[]
	for i in range(count):
		var question := generate_problem(str(selected[i%selected.size()]),difficulty,int(rng.randi()))
		if question.has("error"):return question
		questions.append(question)
	return seal({"version":VERSION,"engine":"MTH147.engine.v1","course_id":"MTH147","week":0,"kind":"practice","practice":true,"official_eligible":false,"lecture_only":true,"difficulty":difficulty,"difficulty_name":DIFFICULTIES[difficulty],"seed":str(seed_value),"title":"Mixed mathematics practice","questions":questions,"question_count":count,"assessment_policy":{"practice_never_official":true,"host_grading_only":true,"default_seconds":0}})

static func formula_reference() -> Dictionary:
	var sections: Array=[]
	for i in range(Curriculum.UNITS.size()):
		var unit: Dictionary=Curriculum.UNITS[i];var entries: Array=[]
		for rule in unit.rules:entries.append({"title":"Rule "+str(entries.size()+1),"formula":{"op":"text","value":str(rule)},"definitions":"Assumptions and notation follow the selected lecture; this reference contains methods, never an assessment answer key."})
		sections.append({"id":"mth147.unit%d"%[i+1],"title":unit.title,"entries":entries})
	return {"course_id":"MTH147","sections":sections,"policy":"Host enables reference access; marked assessments deny it unless their policy explicitly permits it."}

static func grade(assignment: Dictionary,answers: Dictionary) -> Dictionary:
	if assignment.get("course_id","")!="MTH147" or int(assignment.get("version",0))!=VERSION or assignment.get("questions",[]).is_empty() or assignment.get("questions",[]).size()>24:return {"error":"Invalid host assessment."}
	var earned := 0.0;var total := 0.0;var feedback: Array=[]
	for i in range(assignment.questions.size()):
		var question: Dictionary=assignment.questions[i]
		if not question.has("answer"):return {"error":"Private host keys are required for official grading."}
		var response: Variant=answers.get(question.id,answers.get(str(i),""))
		var marked := check(question,response);var weight := float(question.get("points",1.0))
		earned+=weight*float(marked.fraction);total+=weight
		feedback.append({"id":question.id,"correct":marked.correct,"fraction":marked.fraction,"earned":weight*float(marked.fraction),"possible":weight,"reason":marked.reason,"answer":response,"expected":question.answer.duplicate(true) if question.answer is Dictionary or question.answer is Array else question.answer,"steps":question.steps.duplicate(true),"parts":marked.get("parts",[])})
	return {"score":100.0*earned/maxf(1,total),"earned":earned,"possible":total,"feedback":feedback,"course_id":"MTH147","scope":"written_only","engine":"MTH147.engine.v1","mutates_profile":false,"rewards_issued":false,"practice_only":bool(assignment.get("practice",false)),"official_eligible":not bool(assignment.get("practice",false))}

static func public_copy(assignment: Dictionary,reveal: bool=false) -> Dictionary:
	var copy := assignment.duplicate(true)
	if reveal:return copy
	copy.erase("seed")
	if copy.has("questions"):
		for i in range(copy.questions.size()):copy.questions[i]=public_problem(copy.questions[i])
	return copy

static func seal(payload: Dictionary) -> Dictionary:
	# Normalize JSON number types/round-trip representation BEFORE first issue.
	# Saved and reopened papers then have identical protocol payloads, not merely
	# equivalent mathematical keys. Never regenerate a previously issued paper.
	var result: Dictionary=payload.duplicate(true)
	for _pass in range(4):
		var encoded := JSON.stringify(result,"",true,true)
		var decoded: Variant=JSON.parse_string(encoded)
		if not decoded is Dictionary:return {"error":"Assessment is not serializable."}
		result=decoded
		if JSON.stringify(result,"",true,true)==encoded:return result
	return {"error":"Assessment payload did not reach a stable JSON representation."}

static func public_problem(problem: Dictionary) -> Dictionary:
	var out := problem.duplicate(true)
	for key in ["answer","parameters","rubric","steps","verification","seed"]:out.erase(key)
	if out.get("generator_id","")=="w9.equation":out.ast={"op":"text","value":"Infer the waveform from its generated graph."}
	if out.has("diagram"):
		var diagram: Dictionary=out.diagram
		if diagram.get("kind","")=="triangle":
			for key in ["sides","angles"]:
				for field in diagram.get(key,{}).keys():
					if field not in diagram.get("given",[]):diagram[key].erase(field)
			diagram.erase("alternatives")
		if diagram.get("kind","")=="sinusoid":
			if problem.generator_id=="w9.equation":
				diagram.samples=preload("res://scripts/mth147/numeric.gd").wave_points(diagram.function,float(diagram.domain[0]),float(diagram.domain[1]),129)
				diagram.erase("function")
			if problem.generator_id in ["w9.graph","w9.table","w9.critical"]:diagram.erase("points");diagram.erase("function");diagram.erase("samples")
	return out

static func restore(saved: Dictionary) -> Dictionary:
	# Validate a persisted instance, never reroll or recreate it on reconnect.
	if saved.get("engine","")!="MTH147.engine.v1" or int(saved.get("version",0))!=VERSION:return {"error":"Unknown saved engine version; retain the original attempt for host review."}
	if saved.get("questions",[]).is_empty() or saved.questions.size()>24:return {"error":"Corrupt saved assessment."}
	for problem in saved.questions:
		var check_result := Validator.verify(problem)
		if not check_result.ok:return {"error":"Saved key validation failed: "+str(check_result.reason)}
	return saved.duplicate(true)

static func lecture_stage(presentation: Dictionary,index: int) -> Dictionary:
	# Only the current board event is transmitted; no future solution slides or
	# practice keys enter the public session snapshot/optional AI teacher context.
	if index<0 or index>=presentation.get("stages",[]).size():return {"error":"Unknown teaching stage."}
	var stage: Dictionary=presentation.stages[index].duplicate(true)
	return {"course_id":"MTH147","presentation_id":presentation.presentation_id,"week":presentation.week,"focus":presentation.focus,"stage_index":index,"stage":stage,"duration_seconds":presentation.duration_seconds}

static func teacher_context(presentation: Dictionary,index: int,assessment_active: bool=false) -> Dictionary:
	if assessment_active:return {"course_id":"MTH147","policy":"During a marked test explain general methods only; do not expose private questions, answers, future steps or change grades.","week":presentation.get("week",0),"focus":presentation.get("focus","")}
	return lecture_stage(presentation,index)

static func lesson(week: int,difficulty: int=2,seed_value: int=147,duration_seconds: int=420,focus: String="") -> Dictionary:
	if week<1 or week>9 or difficulty<0 or difficulty>4:return {"error":"Unknown lecture."}
	var scope := Curriculum.focus_for(week,difficulty,focus)
	if scope.has("error"):return scope
	var meta: Dictionary=Curriculum.weeks()[week-1];var duration := clampi(duration_seconds,300,600)
	var worked := generate_problem("w%d.%s"%[week,scope.types[0]],difficulty,seed_value)
	var practice := generate_problem("w%d.%s"%[week,scope.types[-1]],difficulty,seed_value+8191)
	if worked.has("error") or practice.has("error"):return {"error":"Lecture example failed validation."}
	var stages: Array=[]
	var slides: Array=[{"title":"Predict and connect","text":"Today: %s. Recall %s. Predict the answer's sign, scale or geometric possibility before calculating. The lesson covers this focused subtopic; other techniques have separate focus selections."%[scope.title,", ".join(meta.prerequisites)],"interaction":"prediction"},{"title":"Rules and why they work","text":"\n".join(meta.rules),"interaction":"teacher explanation"},{"title":"Read the generated example","text":worked.prompt,"problem":public_problem(worked),"interaction":"identify givens, unknowns and conditions"}]
	for i in range(worked.steps.size()):
		var item: Dictionary=worked.steps[i].duplicate(true)
		slides.append({"title":"Worked step %d"%[i+1],"text":item.text,"step_index":i,"math":item.get("math",{}),"diagram":item.get("diagram",{}),"interaction":"explain this transformation before advancing"})
	slides.append({"title":"Verify the example","text":"Generated solution: %s. %s"%[JSON.stringify(worked.answer),str(worked.verification.reason)],"solution":worked.answer,"diagram":worked.get("diagram",{}),"interaction":"substitution/domain/units check"})
	slides.append({"title":"Try independently","text":practice.prompt,"problem":public_problem(practice),"interaction":"practice answer; no official grade"})
	slides.append({"title":"Discuss and compare","text":"%s\nPractice solution: %s\nExplain the method, not just the final result."%["\n".join(meta.misconceptions),JSON.stringify(practice.answer)],"solution":practice.answer,"steps":practice.steps,"interaction":"reveal after practice"})
	slides.append({"title":"Prepare for the test","text":"The test uses new seeded problems from %s. Record restrictions, required forms, units, and all solutions. Only structured answers are graded; personal ink stays on your paper."%scope.title,"interaction":"assessment briefing"})
	var at := 0
	for i in range(slides.size()):
		var end := int(round(float(duration)*(i+1)/slides.size()));var stage: Dictionary=slides[i].duplicate(true)
		stage.merge({"id":"MTH147.%d.%s.%d"%[week,scope.id,i],"start_seconds":at,"duration_seconds":end-at,"duration":end-at,"caption":stage.text,"highlight":i},true)
		stages.append(stage);at=end
	meta.merge({"difficulty":difficulty,"focus":scope.id,"focus_title":scope.title,"duration":duration,"duration_seconds":duration,"presentation_id":"MTH147.lecture.%d.%s.v1"%[week,scope.id],"stages":stages,"timeline":stages,"theory":"\n".join(meta.rules),"worked":worked,"practice":practice,"assessment_types":scope.types,"progression":{"requires":meta.prerequisites,"next_week":mini(9,week+1)},"equipment_text":"Existing classroom or study/library table; mathematics is lecture-only."},true)
	return meta
