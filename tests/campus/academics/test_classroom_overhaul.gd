extends SceneTree

const Plan=preload("res://scripts/campus/academics/class_lesson_plan.gd")
const MathText=preload("res://scripts/campus/academics/speech_math.gd")
const Characters=preload("res://scripts/campus/academics/class_character_profile.gd")
const Brain=preload("res://scripts/campus/academics/teacher_brain.gd")
const Students=preload("res://scripts/campus/academics/classroom_students.gd")
const Voice=preload("res://scripts/campus/computers/TeacherVoiceActivity.cs")
const Round=preload("res://scripts/campus/academics/classroom_events/practice_round.gd")

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	create_timer(45).timeout.connect(func():quit(1))
	assert(MathText.display("Its magnitude is \\(\\sqrt{a^2+b^2}\\).")=="Its magnitude is √(a²+b²).")
	assert(MathText.display("\\(I_1 = \\frac{V}{R_1}\\)")=="I₁ = (V)⁄(R₁)")
	assert(MathText.display("\\(\\omega = 2\\pi f\\)")=="ω = 2π f")
	assert(MathText.display("For $V=a+jb$, use \\[\\sqrt{a^2+b^2}\\].")=="For V=a+jb, use √(a²+b²).")
	assert(MathText.display("$$f=10^{-12}\\text{ Hz}$$ and \\(R_12\\)")=="f=10⁻¹² Hz and R₁₂")
	assert(MathText.display("The lab kit costs $12 and the meter costs $20. Keep pin_a intact.")=="The lab kit costs $12 and the meter costs $20. Keep pin_a intact.")
	var outline:={"stages":[{"title":"Concept","text":"The ratio is constant."},{"title":"Worked example","text":"Determine the voltage."},{"title":"Summary","text":"Explain the units."}]}
	var teacher:=Characters.teacher("ms_clocks")
	var second:=Characters.teacher("mr_phillips")
	assert(Characters.speech(teacher,"gpt-4o-mini-tts",2).voice!=Characters.speech(second,"gpt-4o-mini-tts",2).voice)
	var first:=Plan.build(outline,teacher,10)
	var other:=Plan.build(outline,second,39)
	assert(first.duration_seconds!=other.duration_seconds)
	assert(first.stages[0].title=="Concept" and first.stages.any(func(stage: Dictionary):return stage.class_objective=="check"))
	var memory:=Brain.new()
	memory.memory_path="user://overhaul-test-memory.json"
	memory.remember_conversation(teacher.id,"student001","How do I find the voltage?","Start by finding resistance.",10)
	assert(memory.save_memory()==OK)
	var reloaded:=Brain.new()
	reloaded.memory_path=memory.memory_path
	assert(reloaded.load_memory())
	assert(reloaded.recall(teacher.id,"student001")[0].teacher=="Start by finding resistance.")
	assert(reloaded.recall(second.id,"student001").is_empty())
	_voice_probe()
	var students:=Students.new()
	root.add_child(students)
	students.configure(null)
	var seats: Array[Vector3]=[]
	for index in 8:seats.append(Vector3(index*2.,0.,0.))
	var count:=0
	var participant:=""
	for i in 64:
		var lesson:={"id":"example-class-%d"%i,"phase":"lesson"}
		var players: Array[Vector3]=[seats[0],seats[1]]
		students.start(lesson,{"seats":seats},players,0.)
		assert(lesson.classmates.size()<=5)
		for member in lesson.classmates.values():
			assert(member.seat not in players)
			participant=member.profile.id
		students.step(lesson,20.,3.)
		for member in students.snapshot(lesson,20.):assert(member.seated)
		count+=lesson.classmates.size()
	assert(count>0 and not participant.is_empty())
	var quiz:=Round.new()
	assert(quiz.prepare(true,"lesson-quiz","MTH147",1,2,453,30.,["student001",participant]))
	quiz.mode="quiz"
	assert(quiz.simulate_quiz_answer(participant,1.0,10.)=="accepted")
	assert(not quiz.submissions.has("student001"))
	print("CLASSROOM_OVERHAUL_CORE PASS")
	quit()

func _voice_probe() -> void:
	var splitter:=Voice.new()
	var frames:=PackedVector2Array()
	frames.resize(480)
	frames.fill(Vector2(.003,.003))
	for tick in 40:
		assert(not splitter.Push(frames,48000.,1.,false).has("audio"))
	frames.fill(Vector2(.025,.025))
	for tick in 40:
		assert(not splitter.Push(frames,48000.,1.,true).get("onset",false))
	frames.fill(Vector2(.18,.18))
	var detected:=false
	for tick in 60:
		var segment: Dictionary=splitter.Push(frames,48000.,1.,false)
		detected=detected or segment.get("onset",false)
	assert(detected)
	frames.fill(Vector2(.003,.003))
	var wav:=PackedByteArray()
	for tick in 200:
		var segment: Dictionary=splitter.Push(frames,48000.,1.,false)
		if segment.has("audio"):wav=segment.audio;break
	assert(wav.size()>=32000 and wav.size()<=224000)
