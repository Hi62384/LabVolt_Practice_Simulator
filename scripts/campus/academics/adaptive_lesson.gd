extends RefCounted
## Host-owned lesson pacing. AI supplies dialogue within a course stage.
## All worked examples and grading inputs remain course-provider data.
const Steps = [
	{"key":"introduction","title":"Introduction","share":.08,"prompt":"Welcome students and state the lesson objective."},
	{"key":"concept","title":"Core concept","share":.20,"prompt":"Explain a single idea using the supplied board."},
	{"key":"check","title":"Check understanding","share":.17,"prompt":"Ask one question to check understanding. Invite a student to ask for clarification or signal readiness."},
	{"key":"example","title":"Worked example","share":.20,"prompt":"Guide the first step of the trusted worked example or equipment procedure. Ask students to predict the result before proceeding."},
	{"key":"practice","title":"Practice","share":.24,"prompt":"Invite students to try the practice prompt or use the supplied equipment procedure. Do not reveal assessment answers."},
	{"key":"review","title":"Assessment preparation","share":.11,"prompt":"Summarize the concept and ask students to check their work. Do not disclose answers to any official assessment."},
]

static func window(elapsed: float,duration: float) -> Dictionary:
	var start := 0.0
	for index in Steps.size():
		var step: Dictionary=Steps[index]
		var end := start+duration*float(step.share)
		if elapsed<end or index==Steps.size()-1:
			return {"index":index,"key":step.key,"title":step.title,"prompt":step.prompt,"start":start,"end":end}
		start=end
	return {}

static func pacing_signal(state: Dictionary,identity: String,signal_name: String,elapsed: float,duration: float,present: Array[String]) -> float:
	var current := window(elapsed,duration)
	if current.key!="check" or identity not in present or signal_name not in ["ready","clarify"]:return 0.0
	var signals: Dictionary=state.get("understanding",{})
	signals[identity]=signal_name
	state.understanding=signals
	var ready := 0
	for token in present:
		if signals.get(token)=="ready":ready+=1
		elif signals.get(token)=="clarify":return 0.0
	# Let the teacher complete the explanation. Advance only on a clear
	# majority of the students actually attending this lesson.
	if ready*2<=present.size() or elapsed<float(current.start)+18.0:return 0.0
	return maxf(0.0,float(current.end)-elapsed+.01)
