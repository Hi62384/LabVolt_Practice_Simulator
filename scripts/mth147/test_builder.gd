extends RefCounted
## Host preparation job. Call step(1) on successive preparation frames; never
## start the assessment clock until result().ok is true and the save is durable.
const Provider = preload("res://scripts/mth147/provider.gd")
const Curriculum = preload("res://scripts/mth147/curriculum.gd")
var assignment: Dictionary={}
var schedule: Array=[]
var cursor: int=0
var error: String=""

func begin(week: int,difficulty: int,seed_value: int,count: int=8,focus: String="") -> Dictionary:
	assignment={};schedule=[];cursor=0;error=""
	if count<1 or count>24:error="Question count outside 1..24.";return {"error":error}
	var first := Provider.generate(week,difficulty,seed_value,1,focus)
	if first.has("error"):error=str(first.error);return first
	assignment=first;assignment.question_count=count
	var scope := Curriculum.focus_for(week,difficulty,focus)
	var rng := RandomNumberGenerator.new();rng.seed=seed_value
	var order: Array=scope.types.duplicate()
	for i in range(order.size()-1,0,-1):
		var j := rng.randi_range(0,i);var temp: Variant=order[i];order[i]=order[j];order[j]=temp
	for i in range(count):schedule.append({"id":"w%d.%s"%[week,order[i%order.size()]],"seed":int(rng.randi())})
	cursor=1
	return {"ok":true,"prepared":cursor,"total":count,"complete":cursor==count}

func step(max_questions: int=1) -> Dictionary:
	if not error.is_empty():return {"error":error}
	if assignment.is_empty():return {"error":"Begin preparation first."}
	for _i in range(clampi(max_questions,1,2)):
		if cursor>=schedule.size():break
		var problem := Provider.generate_problem(schedule[cursor].id,int(assignment.difficulty),int(schedule[cursor].seed))
		if problem.has("error"):error=str(problem.error);return {"error":error}
		assignment.questions.append(problem);cursor+=1
	return {"ok":true,"prepared":cursor,"total":schedule.size(),"complete":cursor==schedule.size()}

func result() -> Dictionary:
	if not error.is_empty():return {"error":error}
	if assignment.is_empty() or cursor<schedule.size():return {"error":"Preparation is incomplete; do not issue a timed paper."}
	return {"ok":true,"assignment":Provider.seal(assignment)}
