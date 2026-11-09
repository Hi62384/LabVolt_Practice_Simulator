extends SceneTree
const P = preload("res://scripts/mth147/provider.gd")
const G = preload("res://scripts/mth147/generator.gd")
const A = preload("res://scripts/mth147/attempts.gd")
var checks: int=0
var failures: int=0
func expect(ok: bool,label: String) -> void:
	checks+=1
	if not ok:failures+=1;print("FAIL ",label)
func _initialize() -> void:
	for id in G.ids():
		for difficulty in range(5):
			var private := P.generate_problem(id,difficulty,915000+difficulty)
			if private.has("error"):expect(false,str(private));continue
			var public := P.public_problem(private)
			for field in ["answer","parameters","rubric","steps","verification","seed"]:expect(not public.has(field),"secret projection "+id+" "+field)
			if private.has("diagram"):
				var diagram: Dictionary=public.diagram
				if diagram.kind=="triangle":
					for group in ["sides","angles"]:
						for field in diagram[group]:expect(field in diagram.given,"triangle unknown hidden "+id+" "+field)
					expect(not diagram.has("alternatives"),"SSA answer alternatives hidden")
				if id=="w9.equation":expect(not diagram.has("function") and public.ast.op=="text" and diagram.samples.size()==129,"inferred function hidden, sampled graph retained")
				if id in ["w9.graph","w9.table","w9.critical"]:expect(not diagram.has("function") and not diagram.has("points"),"plotted answer targets hidden "+id)
	var state := {};var request := {"week":9,"difficulty":3,"seed":915001,"count":6}
	A.issue(state,"class:student-a","student-a",request,1000)
	request.seed=915002;A.issue(state,"class:student-b","student-b",request,1000)
	var first := A.reopen(state,"class:student-a","student-a")
	var second := A.reopen(state,"class:student-b","student-b")
	expect(first.assignment.questions[0].id!=second.assignment.questions[0].id,"per-student independent tests")
	expect(A.reopen(state,"class:student-a","student-b").has("error"),"late join cannot read another student's paper")
	expect(A.save_answers(state,"class:student-a","student-b",{"0":"wrong"},{},1050).has("error"),"other peer cannot edit answers")
	expect(A.finish(state,"class:student-a","student-b","dispose_confirmed",1050).has("error"),"other peer cannot dispose official paper")
	var restart: Dictionary=JSON.parse_string(JSON.stringify(state,"",true,true))
	expect(A.validate_saved(restart).get("ok",false),"host restart private state validates")
	var again := A.reopen(restart,"class:student-a","student-a")
	expect(JSON.stringify(first.assignment,"",true,true)==JSON.stringify(again.assignment,"",true,true) and first.deadline==again.deadline,"late reconnect preserves assigned public paper and original deadline")
	print("PROJECTION_CHECKS ",checks," FAILURES ",failures)
	quit(1 if failures else 0)
