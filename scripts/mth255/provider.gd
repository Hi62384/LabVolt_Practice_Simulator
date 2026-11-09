extends RefCounted
const Advanced=preload("res://scripts/mth255/advanced_generators.gd")
const ADVANCED_TOPICS=["impedance_network","reactance_equation","rational_transformed","radical_transformed","trig_proof","log_combine","log_changebase"]
const A=preload("res://scripts/mth255/algebra_generators.gd")
const Applications=preload("res://scripts/mth255/application_generators.gd")
const APPLICATION_TOPICS=["quadratic_system","polynomial_remaining","resistor_pair","engineering_power","half_angle","log_variable_base","exp_substitution","card_union","dice_event","decibel_inverse"]
const T=preload("res://scripts/mth255/trig_generators.gd")
const M=preload("res://scripts/mth255/model_generators.gd")
const V=preload("res://scripts/mth255/verifier.gd")
const C=preload("res://scripts/mth255/complex_domain.gd")
const VERSION=1
const TOPICS=[
["j_power","complex_convert","complex_plot","complex_components"],
["complex_operation","complex_power","complex_roots","impedance","impedance_network"],
["quadratic","quadratic_formula"],
["rational_quadratic","radical_quadratic","biquadratic","quadratic_application","quadratic_vertex","quadratic_system","polynomial_remaining","resistor_pair","engineering_power","reactance_equation","rational_transformed","radical_transformed"],
["angle_conversion","exact_trig","trig_identity","half_angle","trig_proof"],
["trig_equation","waveform","wave_combine","wave_threshold","wave_graph","wave_from_graph"],
["exponential","exp_equation","rc_model","exp_substitution"],
["log_evaluate","log_rules","log_equation","decibels","log_variable_base","decibel_inverse","log_combine","log_changebase"],
["statistics","frequency"],
["dice","coins","cards","card_union","dice_event"]]
const MIN_DIFFICULTY={"complex_roots":1,"impedance":1,"impedance_network":3,"quadratic_formula":1,"rational_quadratic":1,"radical_quadratic":1,"biquadratic":2,"quadratic_system":2,"polynomial_remaining":2,"resistor_pair":2,"engineering_power":3,"reactance_equation":3,"rational_transformed":3,"radical_transformed":3,"trig_identity":1,"half_angle":2,"trig_proof":2,"trig_equation":1,"wave_combine":2,"wave_threshold":2,"wave_from_graph":1,"exp_equation":1,"rc_model":1,"exp_substitution":3,"log_rules":1,"log_equation":2,"log_variable_base":3,"decibel_inverse":2,"log_combine":2,"log_changebase":3,"frequency":1,"card_union":1,"dice_event":1}
var core: Variant=null
func configure_shared_core(shared: Variant) -> void:
	core=shared
func _core() -> Variant:
	if core==null and ResourceLoader.exists("res://scripts/mth147/math_core.gd"):core=load("res://scripts/mth147/math_core.gd")
	return core
func _scalar(value: Variant,angle_unit: String="radians") -> Dictionary:
	if value is int or value is float:return {"ok":is_finite(float(value)),"value":float(value)}
	if _core()==null:return {"ok":false,"value":0.0,"error":"Shared math core is unavailable."}
	return core.evaluate(value,{},angle_unit)
func _equivalent(left: Variant,right: Variant) -> bool:
	if _core()==null:return false
	var result=core.equivalent(left,right)
	return result.get("ok",false) and result.get("equivalent",false)
func catalog() -> Array:
	return [{"id":"MTH255","title":"Applied Mathematics","subject":"Mathematics","description":"Apply mathematics to technology problems through lectures and problem-solving assessments.","lecture_only":true,"weeks":10,"difficulties":["Beginner","Easy","Normal","Hard","Expert"],"provider":"res://scripts/mth255/provider.gd"}]
func weeks(kind: String="lecture") -> Array:
	if kind!="lecture":return []
	var data=JSON.parse_string(FileAccess.get_file_as_string("res://assets/mth255/curriculum.json"))
	return data.weeks.duplicate(true) if data is Dictionary else []
func formula_reference() -> Dictionary:
	var data=JSON.parse_string(FileAccess.get_file_as_string("res://assets/mth255/formula_reference.json"))
	return data if data is Dictionary else {}
func generate_problem(topic: String,difficulty: int,seed_value: int) -> Dictionary:
	if difficulty<0 or difficulty>4:return {"error":"Difficulty must be 0 through 4."}
	var week=0
	for i in range(TOPICS.size()):
		if TOPICS[i].has(topic):week=i+1;break
	if week==0:return {"error":"Unknown MTH255 topic."}
	var rng=RandomNumberGenerator.new();rng.seed=seed_value
	var p=Advanced.make(topic,difficulty,rng) if topic in ADVANCED_TOPICS else Applications.make(topic,difficulty,rng) if topic in APPLICATION_TOPICS else A.make(topic,difficulty,rng) if week<=4 else T.make(topic,difficulty,rng) if week<=6 else M.make(topic,difficulty,rng)
	if p.has("error"):return p
	p.merge({"id":"mth255.v%d.%s"%[VERSION,("%s|%d|%d"%[topic,difficulty,seed_value]).sha256_text().substr(0,32)],"version":VERSION,"course":"MTH255","generator_id":topic,"seed":str(seed_value),"week":week,"difficulty":difficulty,"points":10},true)
	if not V.verify(p) or not _verify_exact(p):return {"error":"Independent verification failed or required shared primitive unavailable.","generator_id":topic,"seed":str(seed_value)}
	if p.input.kind=="structured" and p.input.fields.is_empty():
		for field in p.answer:
			p.input.fields.append({"id":field,"label":str(field).replace("_"," "),"kind":"solutions" if p.answer[field] is Array else "scalar"})
	p.steps.append({"text":"Verified result (shown only during teaching or after marking).","math":JSON.stringify(p.answer)})
	p.verified=true
	p=JSON.parse_string(JSON.stringify(p))
	p.private_checksum=JSON.stringify(p).sha256_text()
	return p
func _verify_exact(p: Dictionary) -> bool:
	if p.generator_id=="quadratic":
		if _core()==null:return false
		var x={"op":"symbol","name":"x"};var q=p.parameters;var standard=_op("add",_op("add",_op("mul",_num(q.a),_op("pow",x,_num(2))),_op("mul",_num(q.b),x)),_num(q.c))
		return _equivalent(_op("sub",p.ast.args[0],p.ast.args[1]),standard) and (not p.answer.has("factored") or _equivalent(p.answer.factored,standard))
	if p.generator_id=="trig_proof":
		return _equivalent("%d*sin(x)^2/(%d*(1-cos(x)^2))"%[p.parameters.scale,p.parameters.scale],"1") and _equivalent(p.answer.step1,p.answer.step2)
	if p.generator_id=="log_combine":
		return _equivalent(p.answer.argument,"y^%d*x^%d/(z^%d)"%[p.parameters.v,p.parameters.u,p.parameters.w])
	if p.generator_id=="log_changebase":
		return _equivalent(p.answer.expression,"(%d*b+%d*a)/(%d*b+%d*a)"%[p.parameters.n,p.parameters.m,p.parameters.v,p.parameters.u]) and _equivalent(p.answer.denominator,"%d*b+%d*a"%[p.parameters.v,p.parameters.u])
	if p.generator_id=="half_angle":
		var squared=_scalar(p.answer.squared_magnitude);var theta=deg_to_rad(p.parameters.theta/2.0)
		return squared.ok and V.near(p.answer.sign*sqrt(maxf(0,squared.value)),cos(theta) if p.parameters.cosine else sin(theta))
	if p.generator_id=="angle_conversion":
		var value=_scalar(p.answer.value)
		return value.ok and V.near(value.value,p.parameters.degrees*PI/180 if p.parameters.to_radians else p.parameters.degrees)
	if p.generator_id=="exact_trig":
		var value=_scalar(p.answer.value);var angle=deg_to_rad(p.parameters.degrees)
		var expected=cos(angle) if p.parameters.cosine else sin(angle)
		if p.parameters.mode==2:expected=1/sin(angle)
		elif p.parameters.mode==3:expected=p.parameters.a*sin(angle)+p.parameters.b*cos(angle)
		elif p.parameters.mode==4:expected=sin(angle+deg_to_rad(p.parameters.other))
		return value.ok and V.near(value.value,expected)
	if p.generator_id=="quadratic_formula":
		var q=p.parameters
		for root in p.answer.values:
			if q.nonreal:
				var real=_scalar(root.real);var imag=_scalar(root.imag)
				if not real.ok or not imag.ok or not C.near(C.power(Vector2(real.value-q.h,imag.value),2),Vector2(-q.rad,0)):return false
			else:
				var value=_scalar(root)
				if not value.ok or not V.near(pow(value.value-q.h,2),q.rad):return false
		return true
	if p.generator_id=="trig_identity":
		# Core must prove the named schema exactly; numerical sampling never establishes an identity.
		var source=["sin(x)^2+cos(x)^2","1+tan(x)^2","sin(2*x)","cos(2*x)","sin(x+y)"][p.parameters.variant]
		return _equivalent("%d*(%s)"%[p.parameters.scale,source],p.answer.expression)
	return true
func generate(week: int,difficulty: int,seed_value: int,count: int=8,focus: String="") -> Dictionary:
	if week<1 or week>10 or count<1 or count>24 or difficulty<0 or difficulty>4:return {"error":"Invalid assessment configuration."}
	var topics=TOPICS[week-1].duplicate();var mixed=focus=="mixed";var unit_focus=focus.begins_with("unit:");var unit=0;var unit_subtopic=""
	if mixed:
		topics=[]
		for group in TOPICS:topics.append_array(group)
	elif unit_focus:
		var parts=focus.split(":")
		if parts.size() not in [2,3] or not parts[1].is_valid_int():return {"error":"Invalid unit focus."}
		unit=int(parts[1])
		if unit<1 or unit>5:return {"error":"Unit must be 1 through 5."}
		topics=TOPICS[2*(unit-1)].duplicate();topics.append_array(TOPICS[2*(unit-1)+1])
		if parts.size()==3:
			unit_subtopic=parts[2]
			if not topics.has(unit_subtopic):return {"error":"Subtopic is not in the selected unit."}
			topics=[unit_subtopic]
	elif not focus.is_empty():
		if not topics.has(focus):return {"error":"Focus is not in the selected week."}
		topics=[focus]
	if focus.is_empty() or mixed or unit_focus and unit_subtopic.is_empty():
		var appropriate=[]
		for topic in topics:
			if difficulty>=MIN_DIFFICULTY.get(topic,0):appropriate.append(topic)
		topics=appropriate
	var rng=RandomNumberGenerator.new();rng.seed=seed_value
	var questions=[];var offset=rng.randi_range(0,topics.size()-1)
	for i in range(count):
		var topic=topics[(offset+i)%topics.size()];var p=generate_problem(topic,difficulty,int(rng.randi()))
		if p.has("error"):return p
		questions.append(p)
	return {"version":VERSION,"course":"MTH255","week":week,"difficulty":difficulty,"seed":str(seed_value),"questions":questions,"maximum":count*10,"assessment_seconds":1800,"lecture_only":true,"formula_access":"host_policy","mode":"unit" if unit_focus else "mixed" if mixed else "week","unit":unit if unit_focus else int((week+1)/2)}
func lesson(week: int,difficulty: int=2,seed_value: int=255,duration_seconds: int=420,focus: String="") -> Dictionary:
	var definitions=weeks()
	if week<1 or week>definitions.size():return {"error":"Invalid week."}
	var result=definitions[week-1].duplicate(true);var examples=generate(week,difficulty,seed_value,mini(5,TOPICS[week-1].size()),focus)
	if examples.has("error"):return examples
	result.duration_seconds=clampi(duration_seconds,300,600);result.worked_examples=examples.questions
	for i in range(result.stages.size()):result.stages[i].duration_seconds=float(result.duration_seconds)/result.stages.size()
	result.practice=generate(week,difficulty,seed_value+1,3,focus)
	if result.practice.has("error"):return result.practice
	result.practice.official=false
	return result
func public_copy(assignment: Dictionary,reveal: bool=false) -> Dictionary:
	if reveal:return assignment.duplicate(true)
	var out={}
	for key in ["version","course","course_id","title","kind","week","difficulty","maximum","assessment_seconds","lecture_only","formula_access","mode","unit","week_range","data","theory","procedure","official","practice"]:
		if assignment.has(key):out[key]=assignment[key]
	out.questions=[]
	for p in assignment.get("questions",[]):out.questions.append(public_problem(p))
	return JSON.parse_string(JSON.stringify(out))
func public_problem(problem: Dictionary) -> Dictionary:
	var out={}
	for key in ["id","version","course","generator_id","week","difficulty","points","prompt","expected_form","input","ast"]:
		if problem.has(key):out[key]=_scrub_private(problem[key])
	if problem.get("diagram") is Dictionary:
		var diagram=_scrub_private(problem.diagram)
		for key in ["magnitude","phase_degrees","lead_seconds","tau","reference_points","critical_points","alternatives","unknown","accepted"]:diagram.erase(key)
		if problem.expected_form=="graph_points" or problem.generator_id=="exact_trig" or problem.generator_id=="complex_convert" and problem.get("parameters",{}).get("requested",problem.get("expected_form",""))=="rectangular":diagram.points=[]
		if diagram.get("kind","")=="triangle":
			for key in ["sides","angles"]:
				for field in diagram.get(key,{}).keys():
					if field not in diagram.get("given",[]):diagram[key].erase(field)
		if diagram.get("kind","")=="probability":
			# Event counts/flags are a worked demonstration, not assessment givens.
			diagram.outcomes=[];diagram.erase("branches")
		var curves=[]
		if diagram.has("function"):curves.append(diagram.function)
		curves.append_array(diagram.get("curves",[]));var sampled=[]
		for curve in curves:
			var visible=_sample_curve(curve,diagram.get("domain",[-5,5]))
			if not visible.is_empty():sampled.append({"kind":"samples","points":visible,"label":str(curve.get("label","curve"))})
		if not curves.is_empty():
			diagram.erase("function");diagram.curves=sampled;diagram.erase("samples")
		out.diagram=diagram
	return out
func _scrub_private(value: Variant) -> Variant:
	if value is Dictionary:
		var out={}
		for key in value:
			if key not in ["answer","answers","answer_key","solution","solutions","parameters","rubric","steps","verification","verified","seed","expected","correct","favorable","reference_points","critical_points","alternatives","unknown","accepted","default_answer","grading","host_only","private","reference","target","hidden","oracle","correct_value","root_values"]:out[key]=_scrub_private(value[key])
		return out
	if value is Array:
		var out=[]
		for child in value:out.append(_scrub_private(child))
		return out
	return value
func _num(value: float) -> Dictionary:
	return core.input_ast(value).get("ast",{})
func _op(operation: String,a: Dictionary,b: Dictionary={}) -> Dictionary:
	return {"op":operation,"args":[a] if b.is_empty() else [a,b]}
func _sample_curve(f: Dictionary,domain: Array) -> Array:
	if f.get("kind","")=="samples":return _scrub_private(f.get("points",[]))
	if _core()==null or domain.size()!=2:return []
	var x={"op":"symbol","name":"x"};var body={};var kind=str(f.get("kind",""))
	if kind in ["sin","cos"]:
		var angle=_op("div",_op("mul",_num(TAU),_op("sub",x,_num(f.get("phase",0)))),_num(f.get("period",360)))
		body=_op(kind,angle)
	elif kind=="exponential":
		body=_op("pow",_num(f.get("base",exp(1))),_op("mul",_num(f.get("rate",1)),_op("sub",x,_num(f.get("phase",0)))))
	elif kind=="log":body=_op("log",_op("mul",_num(f.get("rate",1)),_op("sub",x,_num(f.get("phase",0)))),_num(f.get("base",10)))
	elif kind=="quadratic":body=_op("add",_op("add",_op("mul",_num(f.a),_op("pow",x,_num(2))),_op("mul",_num(f.b),x)),_num(f.c))
	else:return []
	if kind!="quadratic":body=_op("add",_num(f.get("offset",0)),_op("mul",_num(f.get("amplitude",1)),body))
	var points=[]
	for i in range(129):
		var xx=lerpf(float(domain[0]),float(domain[1]),float(i)/128);var value=core.evaluate(body,{"x":xx},"radians")
		if value.get("ok",false):points.append({"x":xx,"y":value.value})
	return points
func _values(value: Variant) -> Array:
	if value is Array:return value
	if value is Dictionary and value.get("values") is Array:return value.values
	return []
func _number_match(value: Variant,key: Variant,exact: bool=false,angle_period: float=0,angle_unit: String="radians") -> bool:
	if exact:return _equivalent(value,key)
	var a=_scalar(value,angle_unit);var b=_scalar(key,angle_unit)
	if not a.ok or not b.ok:return false
	if angle_period>0:return absf(wrapf(a.value-b.value,-angle_period/2,angle_period/2))<=0.00000501
	return absf(a.value-b.value)<=0.00000501
func _set_match(value: Variant,key: Array,exact: bool=false,complex_values: bool=false,angle_unit: String="radians") -> bool:
	var submitted=_values(value)
	if submitted.size()>24:return false
	var unique=[]
	for entry in submitted:
		var duplicate=false
		for previous in unique:
			if _complex_match(entry,previous,exact,angle_unit) if complex_values else _number_match(entry,previous,exact,0,angle_unit):duplicate=true;break
		if not duplicate:unique.append(entry)
	if unique.size()!=key.size():return false
	var used=[]
	for entry in unique:
		var found=-1
		for i in range(key.size()):
			if not used.has(i) and (_complex_match(entry,key[i],exact,angle_unit) if complex_values else _number_match(entry,key[i],exact,0,angle_unit)):found=i;break
		if found<0:return false
		used.append(found)
	return true
func _complex_match(value: Variant,key: Variant,exact: bool=false,angle_unit: String="radians") -> bool:
	if not value is Dictionary or not key is Dictionary:return false
	return value.get("form","rectangular")=="rectangular" and value.has("real") and value.has("imag") and _number_match(value.real,key.real,exact,0,angle_unit) and _number_match(value.imag,key.imag,exact,0,angle_unit)
func check(problem: Dictionary,answer: Variant) -> Dictionary:
	if not problem.get("verified",false) or not _checksum_valid(problem) or not V.verify(problem):return {"correct":false,"fraction":0.0,"reason":"Unverified problem."}
	if not answer is Dictionary:return {"correct":false,"fraction":0.0,"reason":"Use the structured answer fields."}
	if problem.expected_form=="frequency_table":return _grade_frequency_table(problem,answer)
	var form=problem.expected_form;var scalar_units=str(problem.input.get("angle_unit",problem.rubric.get("angle_unit","radians")));var key=problem.answer;var credit=0.0;var total=0.0;var fields=[]
	if form=="system_points" and not answer.has("points"):
		answer={"points":[{"x":answer.get("x1",null),"y":answer.get("y1",null)},{"x":answer.get("x2",null),"y":answer.get("y2",null)}]}
	if problem.input.get("kind","")=="complex":
		scalar_units=str(answer.get("angle_unit",scalar_units))
		if answer.has("form") and answer.form!=form:return {"correct":false,"fraction":0.0,"reason":"The requested complex representation is required."}
		if form in ["polar","exponential"] and answer.get("angle_unit","degrees")=="radians":
			var angle=_scalar(answer.get("angle",""),"radians")
			if not angle.ok:return {"correct":false,"fraction":0.0,"reason":"Invalid angle."}
			answer=answer.duplicate(true);answer.angle=rad_to_deg(angle.value)
		elif answer.get("angle_unit","degrees") not in ["degrees","radians"]:return {"correct":false,"fraction":0.0,"reason":"Unknown angle units."}
	for field in key:
		total+=1;var ok=false;var value=answer.get(field,null)
		if value!=null:
			if form in ["graph_points","system_points"] and field=="points":
				ok=_points_match(value,key.points,problem.rubric.get("point_tolerance",{"x":0.05,"y":0.05}))
			elif key[field] is Array:
				ok=_set_match(value,key[field],form in ["exact_roots","exact_complex_roots"],form in ["complex_roots","exact_complex_roots"],scalar_units)
			elif field=="expression" or field in problem.rubric.get("expression_fields",[]):
				ok=_equivalent(value,key[field])
				if ok and form=="identity" and _core()!=null:
					var parsed=core.input_ast(value)
					ok=parsed.get("ok",false) and _identity_form(parsed.get("ast",{}),int(problem.parameters.variant))
			else:ok=_number_match(value,key[field],form in ["exact_fields","exact_probability"],360.0 if field=="angle" and form in ["polar","exponential"] else TAU if field=="angle" and problem.generator_id=="wave_combine" else 0.0,scalar_units)
		if ok and problem.rubric.get("expression_forms",{}).has(field):
			var inspected=core.inspect_form(problem.rubric.expression_forms[field],value,key[field],{})
			ok=inspected.get("ok",false)
		if ok and form=="proof" and field in ["step1","step2"]:
			var ast=core.input_ast(value)
			ok=ast.get("ok",false)
			if ok and field=="step1":ok=ast.ast.get("op","")=="div" and _has_op(ast.ast,"sin") and not _has_op(ast.ast,"cos")
			elif ok:ok=not _has_op(ast.ast,"sin") and not _has_op(ast.ast,"cos")
		if problem.rubric.get("field_tolerances",{}).has(field):
			var given=_scalar(value,scalar_units);var expected=_scalar(key[field],scalar_units);ok=given.ok and expected.ok and absf(given.value-expected.value)<=float(problem.rubric.field_tolerances[field])
		if problem.rubric.get("field_forms",{}).has(field):
			ok=false
			if value!=null and _core()!=null:
				var field_form=problem.rubric.field_forms[field];var inspected=core.inspect_form(field_form.form,value,key[field],field_form)
				var a=_scalar(value);var b=_scalar(key[field]);var digits=int(field_form.digits)
				if inspected.get("ok",false) and a.ok and b.ok:
					var step=pow(10,floor(log(absf(b.value))/log(10))-digits+1) if b.value!=0 else 0.0
					ok=absf(a.value-b.value)<=step*0.500001
		if ok:credit+=1
		fields.append({"field":field,"correct":ok,"earned":1 if ok else 0,"maximum":1})
	var fraction=credit/total if total>0 else 0.0
	return {"correct":fraction==1.0,"fraction":fraction,"fields":fields,"reason":"Structured fields checked with required representations, complete sets and original domains.","accepted":key.duplicate(true),"steps":problem.steps.duplicate(true)}
func grade(assignment: Dictionary,answers: Dictionary) -> Dictionary:
	if assignment.get("course","")!="MTH255":return {"error":"Wrong course."}
	var earned=0.0;var maximum=0.0;var feedback=[]
	for i in range(assignment.get("questions",[]).size()):
		var p=assignment.questions[i];var marked=check(p,answers.get(p.id,answers.get(str(i),{})));var points=float(p.get("points",10));marked.id=p.id;marked.earned=points*marked.fraction;marked.maximum=points;feedback.append(marked);earned+=marked.earned;maximum+=points
	return {"course":"MTH255","earned":earned,"maximum":maximum,"possible":maximum,"scope":"written_only","engine":"MTH255.plugin.v1","shared_math":"MTH147.math_core facade","mutates_profile":false,"rewards_issued":false,"percentage":100*earned/maximum if maximum>0 else 0,"feedback":feedback,"authoritative_ledger_required":true}


func _identity_form(ast: Dictionary,variant: int) -> bool:
	var op=str(ast.get("op",""))
	if op in ["sin","cos","tan","sec","csc","cot"]:
		if variant==0:return false
		if variant==1 and op!="sec":return false
		if variant>=2 and op not in ["sin","cos"]:return false
		if ast.get("args",[]).size()!=1 or ast.args[0].get("op","")!="symbol":return false
	for child in ast.get("args",[]):
		if not _identity_form(child,variant):return false
	return true

func _points_match(value: Variant,key: Array,tolerance: Dictionary) -> bool:
	if not value is Array or value.size()!=key.size() or value.size()>24:return false
	var used=[]
	for point in value:
		if not point is Dictionary:return false
		var x=_scalar(point.get("x",null));var y=_scalar(point.get("y",null));var found=-1
		if not x.ok or not y.ok:return false
		for i in range(key.size()):
			if not used.has(i) and absf(x.value-key[i].x)<=tolerance.x and absf(y.value-key[i].y)<=tolerance.y:found=i;break
		if found<0:return false
		used.append(found)
	return true

func _has_op(ast: Dictionary,operation: String) -> bool:
	if ast.get("op","")==operation:return true
	for child in ast.get("args",[]):
		if _has_op(child,operation):return true
	return false

func restore(saved: Dictionary) -> Dictionary:
	if saved.get("course","")!="MTH255" or saved.get("version",0)!=VERSION:return {"error":"Unknown saved course or engine version; keep the original attempt for host review."}
	if not saved.get("questions") is Array or saved.questions.is_empty() or saved.questions.size()>24:return {"error":"Invalid saved assessment size."}
	for problem in saved.questions:
		if not problem is Dictionary or not problem.get("verified",false) or not problem.has("parameters") or not problem.has("answer"):return {"error":"A private host assessment is required."}
		if not _checksum_valid(problem):return {"error":"Saved question integrity check failed; keep the original attempt for host review."}
		if not V.verify(problem) or not _verify_exact(problem):return {"error":"Saved assessment validation failed; do not reroll an active attempt."}
	return saved.duplicate(true)

func _checksum_valid(problem: Dictionary) -> bool:
	if not problem.get("private_checksum") is String:return false
	var copy=problem.duplicate(true);var stored=copy.private_checksum;copy.erase("private_checksum")
	return JSON.stringify(copy).sha256_text()==stored

func units() -> Array:
	var titles=["Complex numbers","Quadratics","Trigonometry and waveforms","Exponentials and logarithms","Statistics and probability"];var result=[]
	for index in range(5):
		var topics=TOPICS[2*index].duplicate();topics.append_array(TOPICS[2*index+1])
		result.append({"unit":index+1,"title":titles[index],"weeks":[2*index+1,2*index+2],"topics":topics})
	return result
func generate_unit(unit: int,difficulty: int,seed_value: int,count: int=8,focus: String="") -> Dictionary:
	if unit<1 or unit>5:return {"error":"Unit must be 1 through 5."}
	var out=generate(2*unit-1,difficulty,seed_value,count,"unit:%d"%unit+(":"+focus if not focus.is_empty() else ""))
	if not out.has("error"):out.week_range=[2*unit-1,2*unit]
	return out
func week_for_topic(topic: String) -> int:
	for index in range(TOPICS.size()):
		if topic in TOPICS[index]:return index+1
	return 0

func _grade_frequency_table(problem: Dictionary,answer: Dictionary) -> Dictionary:
	var key=problem.answer.rows;var rows=answer.get("rows",[])
	if not rows is Array or rows.size()>64:return {"correct":false,"fraction":0.0,"reason":"Use the frequency table rows."}
	var used=[];var matched=0;var feedback=[]
	for i in range(rows.size()):
		var ok=false
		if rows[i] is Array and rows[i].size()==2:
			var value=_scalar(rows[i][0]);var count=_scalar(rows[i][1])
			if value.ok and count.ok and count.value>=0 and count.value==floor(count.value):
				for j in range(key.size()):
					if not used.has(j) and absf(value.value-key[j][0])<=0.00000501 and count.value==key[j][1]:used.append(j);matched+=1;ok=true;break
		feedback.append({"row":i,"correct":ok,"earned":1 if ok else 0,"maximum":1})
	var fraction=float(matched)/maxi(key.size(),rows.size())
	return {"correct":fraction==1.0,"fraction":fraction,"fields":feedback,"reason":"Each distinct value and integer occurrence count is checked; row order does not matter.","accepted":problem.answer.duplicate(true),"steps":problem.steps.duplicate(true)}
