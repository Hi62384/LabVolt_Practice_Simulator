extends SceneTree
const Provider = preload("res://scripts/mth147/provider.gd")
const Grader = preload("res://scripts/mth147/grader.gd")
const Attempts = preload("res://scripts/mth147/attempts.gd")
const Core = preload("res://scripts/mth147/math_core.gd")
const Registry = preload("res://scripts/mth147/course_registry.gd")
const N = preload("res://scripts/mth147/numeric.gd")
const Builder = preload("res://scripts/mth147/test_builder.gd")
const Validator = preload("res://scripts/mth147/validator.gd")
var checks: int=0
var failures: int=0
func expect(ok: bool,label: String) -> void:
	checks+=1
	if not ok:failures+=1;print("FAIL ",label)
func _initialize() -> void:
	expect(Provider.catalog()[0].lab_weeks==0 and Provider.weeks("lab").is_empty(),"lecture only")
	expect(Provider.weeks().size()==9,"nine weeks")
	expect(Registry.weeks("MTH147","lab").is_empty(),"registry no math lab")
	var mixed := Provider.practice(["w1.scientific","w6.reduce","w8.ssa","w9.zeros"],3,147,8)
	expect(not mixed.has("error") and mixed.practice and not mixed.official_eligible and mixed.week==0,"mixed-unit practice explicitly ineligible")
	var mixed_answers := {}
	for question in mixed.questions:mixed_answers[question.id]=question.answer
	var practice_result := Provider.grade(mixed,mixed_answers)
	expect(practice_result.score==100 and practice_result.practice_only and not practice_result.official_eligible and not practice_result.rewards_issued,"mixed practice grade cannot create a reward")
	expect(Provider.formula_reference().sections.size()==9,"nine reference sections")
	for id in ["w1.arithmetic","w8.ratio","w8.reciprocal"]:
		for d in range(5):
			for seed_value in range(4):
				var question := Provider.generate_problem(id,d,147+seed_value)
				var value := N.from_value(question.answer)
				var scale := pow(10.0,5-floor(log(absf(value))/log(10.0))) if value!=0 else 1.0
				var rounded := roundf(value*scale)/scale
				expect(Provider.check(question,N.literal(rounded)).correct,"stated six-significant-figure accuracy accepted")
	var builder := Builder.new();builder.begin(7,3,7171,8)
	expect(builder.result().has("error"),"incomplete preparation cannot be issued")
	for _i in range(7):builder.step(1)
	expect(JSON.stringify(builder.result().assignment,"",true,true)==JSON.stringify(Provider.generate(7,3,7171,8),"",true,true),"incremental preparation same immutable test")
	for week in range(1,10):
		for d in range(5):
			var assignment := Provider.generate(week,d,88000+week*10+d,4)
			if assignment.has("error"):expect(false,"assignment %d/%d %s"%[week,d,str(assignment)]);continue
			var answers := {}
			for question in assignment.questions:answers[question.id]=question.answer
			expect(Provider.grade(assignment,answers).score==100.0,"perfect paper %d/%d"%[week,d])
			expect(Provider.grade(assignment,{}).score==0.0,"empty paper %d/%d"%[week,d])
			var restored := Provider.restore(JSON.parse_string(JSON.stringify(assignment,"",true,true)))
			expect(not restored.has("error"),"restore %d/%d"%[week,d])
			var lesson := Provider.lesson(week,d,88000+week*10+d)
			if lesson.has("error"):expect(false,"lesson %d/%d %s"%[week,d,str(lesson)]);continue
			expect(lesson.duration_seconds>=300 and lesson.duration_seconds<=600,"lesson duration")
			expect(lesson.focus==assignment.focus,"lesson test focus alignment")
			var at := 0
			expect(not Provider.lecture_stage(lesson,0).has("worked") and not Provider.teacher_context(lesson,0,true).has("stage"),"staged teaching and AI test privacy")
			for stage in lesson.stages:expect(int(stage.start_seconds)==at and int(stage.duration)>0,"progressive timeline");at+=int(stage.duration)
			expect(at==lesson.duration,"full timeline")
	expect(Grader.scalar("1/2","2/4").correct,"fraction equivalent")
	expect(Grader.scalar("2*x+2","2*(x+1)").correct,"algebra equivalent")
	expect(not Grader.scalar("(x-1)*(x+1)","x^2-1","factored").correct,"factored required")
	expect(Grader.scalar("(x-1)*(x+1)","(1-x)*(-1-x)","factored").correct,"factor units and order")
	var bad_factor := Provider.generate_problem("w5.quadratic",2,147)
	bad_factor.answer="x^2-1";bad_factor.parameters.expression="x^2-1";bad_factor.parameters.proof={"kind":"factor","original":"x^2-1","reference":"x^2-1"}
	expect(not Validator.verify(bad_factor).ok,"independent irreducibility rejects an unfactored reference key")
	expect(Grader.scalar("sqrt(2)/2","1/sqrt(2)").correct,"equivalent radical unrestricted")
	expect(not Grader.scalar("sqrt(2)/2","1/sqrt(2)","radical").correct,"radical rationalization required")
	expect(not Grader.scalar("2*x","x+x","expanded").correct,"simplification required")
	expect(Grader.scalar("1.20e6",Core.parse("1.20*10^6").ast,"scientific").correct,"AST scientific input")
	expect(not Grader.scalar("1.200e3","1200","significant",{"digits":4}).correct,"significant trailing zeros")
	expect(Grader.set_match([30,150,390],[390,30,150,30]).correct,"set order and deduplication")
	expect(not Grader.set_match([30,150,390],[30,150]).correct,"complete solution set")
	expect(not Grader.set_match([30,150],[30,150,210]).correct,"extraneous solution")
	expect(not Grader.set_match([],"").correct,"blank not empty solution")
	for answer in [17,{},true,{"values":"none"}]:expect(not Grader.set_match([],answer).correct,"malformed empty set rejected")
	var rational := Provider.generate_problem("w6.reduce",2,147)
	var missing: Dictionary= rational.answer.duplicate(true);missing.excluded=[]
	expect(not Provider.check(rational,missing).correct,"canceled restrictions retained")
	var extra: Dictionary= rational.answer.duplicate(true);extra.expression="(%s)*(x-999)/(x-999)"%rational.answer.expression
	expect(not Provider.check(rational,extra).correct,"extra domain hole rejected")
	var uncanceled: Dictionary= rational.answer.duplicate(true);uncanceled.expression=rational.parameters.expression
	expect(not Provider.check(rational,uncanceled).correct,"lowest terms required")
	var radical := Provider.generate_problem("w7.equation",3,147)
	var bad: Array=radical.answer.duplicate(true);bad.append("-999")
	expect(not Provider.check(radical,bad).correct,"radical invalid candidate rejected")
	var g := Provider.generate_problem("w9.graph",3,147)
	var graph: Dictionary= g.answer.duplicate(true);graph.function.kind="cos";graph.function.phase=float(graph.function.phase)+float(graph.function.period)/4
	expect(Provider.check(g,graph).correct,"equivalent sine cosine phase")
	graph.points[1].y=float(graph.points[1].y)+100
	expect(not Provider.check(g,graph).correct,"bad graph coordinate rejected")
	expect(not Provider.check(g,{"function":[]}).correct,"malformed graph rejected")
	expect(not Provider.check(g,{"points":"wrong"}).correct,"malformed point container rejected")
	expect(not Provider.check(g,{"points":[{"x":"wrong","y":"wrong"}]}).correct,"malformed point coordinate rejected")
	expect(not Provider.check(g,{"points":[{"x":NAN,"y":0}]}).correct,"nonfinite graph rejected")
	var state := {};var request := {"week":6,"difficulty":2,"seed":6001,"count":4,"seconds":600}
	var first := Attempts.issue(state,"attempt-a","student-a",request,100)
	expect(not first.has("error"),"issue attempt")
	var encoded := JSON.stringify(first.assignment,"",true,true)
	request.seed=9009
	var reopened := Attempts.issue(state,"attempt-a","student-a",request,200)
	expect(JSON.stringify(reopened.assignment,"",true,true)==encoded and reopened.deadline==700,"reopen immutable assignment and deadline")
	expect(Attempts.reopen(state,"attempt-a","student-b").has("error"),"other student private")
	var own_answers := {}
	for q in state["attempt-a"].assignment.questions:own_answers[q.id]=q.answer
	expect(Attempts.save_answers(state,"attempt-a","student-a",own_answers,{"ink":[[1,2],[3,4]],"pen":"blue"},300).get("ok",false),"private answers and ink save")
	var loaded: Dictionary=JSON.parse_string(JSON.stringify(state,"",true,true))
	expect(Attempts.validate_saved(loaded).get("ok",false),"persisted private assessment validates")
	expect(Attempts.reopen(loaded,"attempt-a","student-a").workspace.pen=="blue","ink restored")
	var finished := Attempts.finish(loaded,"attempt-a","student-a","submit",400)
	expect(finished.result.score==100 and not finished.academic_event.is_empty(),"official event")
	expect(Attempts.finish(loaded,"attempt-a","student-a","submit",500).academic_event.is_empty(),"idempotent event no second payout")
	Attempts.issue(loaded,"practice","student-a",request,100,true)
	expect(Attempts.finish(loaded,"practice","student-a","submit",200).academic_event.is_empty(),"practice excluded")
	Attempts.issue(loaded,"hostlost","student-a",request,100)
	expect(Attempts.finish(loaded,"hostlost","student-a","host_cancel",200).academic_event.is_empty(),"host loss no penalty event")
	Attempts.issue(loaded,"trash","student-a",request,100)
	expect(Attempts.finish(loaded,"trash","student-a","dispose_confirmed",200).result.score==0,"confirmed disposal zero")
	Attempts.issue(loaded,"timeout","student-a",request,100)
	expect(Attempts.finish(loaded,"timeout","student-a","timeout",200).has("error"),"early timeout rejected")
	expect(Attempts.finish(loaded,"timeout","student-a","timeout",701).result.score==0,"unanswered timeout zero")
	print("BEHAVIOUR_CHECKS ",checks," FAILURES ",failures)
	quit(1 if failures else 0)
