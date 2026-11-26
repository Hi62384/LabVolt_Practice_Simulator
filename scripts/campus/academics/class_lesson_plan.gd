extends RefCounted
## Re-times the trusted curriculum without altering its content or adding answers.
const MIN_SEGMENT:=22.0
const MAX_SEGMENT:=90.0
const CORE_PROMPTS:={
	"introduction":"Start from an everyday example. Explain the terms and state the objective.",
	"concept":"Build from material already introduced. Explain the current concept and its units.",
	"example":"Read the given quantities and work through the example in order. Explain the reason for each step.",
	"practice":"Give students time to attempt the supplied practice. Offer a hint without disclosing official answers.",
	"check":"Ask one concrete understanding question about the current objective. Allow time to answer.",
	"review":"Tie the results to the lesson objectives. Summarize without previewing assessment answers."
}

static func build(presentation: Dictionary, personality: Dictionary, variation: int) -> Dictionary:
	var original: Array=presentation.get("stages",[])
	var result:=presentation.duplicate(true)
	if original.is_empty():return result
	var seed_value:=posmod(variation,1619)
	var talk:=clampf(float(personality.get("talkativeness",.5)),0.,1.)
	var teaching:=clampf(float(personality.get("teaching",.5)),0.,1.)
	var stages: Array[Dictionary]=[]
	var cursor:=0.
	for index in original.size():
		var stage: Dictionary=original[index].duplicate(true)
		var key:=_objective(stage,index,original.size())
		var words:=str(stage.get("text",stage.get("caption",""))).split(" ",false).size()
		var pace:=clampf(24.+words*.28+stage.get("steps",[]).size()*3.+talk*12.+posmod(seed_value+index*19,15),MIN_SEGMENT,MAX_SEGMENT)
		if key=="practice":pace+=12.
		cursor=_append(stages,stage,key,cursor,pace)
		if index+1<original.size() and key in ["concept","example"] and posmod(seed_value+index*37,7)<int(2+teaching*2.):
			var check:=stage.duplicate(true)
			check.title="Understanding check"
			check.text="Explain the main idea in your own words. What would change if one of the quantities changed?"
			cursor=_append(stages,check,"check",cursor,24.+talk*6.)
	if not stages.any(func(step: Dictionary):return step.get("class_objective")=="check"):
		var check: Dictionary=original[-1].duplicate(true)
		check.title="Before you finish"
		check.text="Name one idea from this lesson and explain where you would use it."
		cursor=_append(stages,check,"check",cursor,24.+talk*6.)
	result.stages=stages
	result.duration_seconds=cursor
	return result

static func _objective(stage: Dictionary,index: int,count: int) -> String:
	if index==0:return "introduction"
	if index==count-1:return "review"
	var title:=str(stage.get("title","")).to_lower()
	if "practice" in title or "exercise" in title:return "practice"
	if "example" in title or "worked" in title or "demonstration" in title:return "example"
	return "concept"

static func _append(stages: Array[Dictionary],stage: Dictionary,key: String,cursor: float,duration: float) -> float:
	stage.class_objective=key
	stage.start_seconds=cursor
	stage.duration_seconds=duration
	stages.append(stage)
	return cursor+duration

static func step(board: Dictionary,elapsed: float,duration: float) -> Dictionary:
	var key:=str(board.get("class_objective",""))
	if not CORE_PROMPTS.has(key):
		return preload("res://scripts/campus/academics/adaptive_lesson.gd").window(elapsed,duration)
	var start:=float(board.get("start_seconds",0.))
	return {"index":int(board.get("index",0)),"key":key,"title":str(board.get("title","")),
		"prompt":CORE_PROMPTS[key],"start":start,"end":start+float(board.duration_seconds)}
