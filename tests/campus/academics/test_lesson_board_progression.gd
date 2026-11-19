extends SceneTree
const State=preload("res://scripts/campus/academics/lesson_board_state.gd")
const Director=preload("res://scripts/campus/academics/lecture_director.gd")
func _initialize() -> void:
	var stages: Array=[]
	for i in 5:stages.append({"title":"Concept %d"%i,"text":"Explanation %d"%i,"formulas":"F%d"%i,"duration_seconds":10.0})
	var lesson:={"stages":stages}
	var first:=State.at(lesson,"Lesson",0.0,50.0)
	assert(first.index==0 and first.board_history.is_empty())
	var middle:=State.at(lesson,"Lesson",25.0,50.0)
	assert(middle.index==2 and middle.board_history.size()==2)
	assert(middle.board_history[0].title=="Concept 0" and middle.board_history[1].formula=="F1")
	assert(not str(middle).contains("Concept 3") and not str(middle).contains("F4"))
	var last:=State.at(lesson,"Lesson",99.0,50.0)
	assert(last.index==4 and last.board_history.size()==4)
	assert(last.board_history[0].title=="Concept 0" and last.board_history[3].title=="Concept 3")
	var fallback:=State.at({"worked":"A verified example"},"Fallback",20.0,50.0)
	assert(fallback.index==0 and fallback.text=="A verified example")
	var activity := {"course":"ELM253","deadline":420.0,"title":"Equipment and measurement"}
	var stage := {"index":1,"title":"Voltmeter connections","text":"A voltmeter connects across the component. An ammeter connects in series."}
	var entrance := Director.cue(activity,stage,0.0,{})
	assert(entrance.text.contains("ELM253") and entrance.text.contains("voltmeter"))
	assert(Director.cue(activity,stage,38.0,{}).key != entrance.key)
	assert(Director.cue(activity,stage,404.0,{}).text.contains("assessment"))
	assert(Director.answer("How does the ammeter connect?",stage).contains("series"))
	print("LESSON_BOARD_PROGRESSION PASS")
	quit()
