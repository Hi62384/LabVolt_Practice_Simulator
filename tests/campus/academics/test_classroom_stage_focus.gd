extends SceneTree
const Selector=preload("res://scripts/campus/academics/classroom_events/event_selector.gd")
const Round=preload("res://scripts/campus/academics/classroom_events/practice_round.gd")

func _initialize() -> void:
	var activity:={"deadline":100.0,"title":"Circuit lesson","teaching":{"duration_seconds":30.0,"stages":[{"start_seconds":0.0,"duration_seconds":10.0,"title":"Series resistance","text":"Add resistors in series."},{"start_seconds":10.0,"duration_seconds":20.0,"title":"Waveform","text":"Compare AC frequency."}]}}
	assert(Selector.stage_focus(activity,70.0).contains("Series resistance"))
	assert(Selector.stage_focus(activity,85.0).contains("Waveform"))
	var round:=Round.new()
	round.private_assignment={"questions":[{"prompt":"Identify the AC waveform frequency","answer":"50 Hz","options":[]},{"prompt":"Calculate total resistance of series resistors","answer":"3 kΩ","options":[]}]}
	round.question_index=0
	round.public_question={"prompt":"Identify the AC waveform frequency"}
	round.focus_question("Series resistance. Add resistors in series.")
	assert(round.question_index==1 and round.public_question.prompt.contains("resistance"))
	assert(not round.public_question.has("answer"))
	round.focus_question("No matching lesson topic",[1])
	assert(round.question_index==1)
	print("CLASSROOM_STAGE_FOCUS PASS")
	quit(0)
