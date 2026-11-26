extends SceneTree
const Plan = preload("res://scripts/campus/academics/ai_assessment_plan.gd")
const Provider = preload("res://scripts/campus/academics/course_bridge.gd")

func _initialize() -> void:call_deferred("run")

func run() -> void:
	var valid:=Plan.parse('{"focus":"evidence","scenarios":[37,526,1044]}')
	assert(valid.scenarios==[37,526,1044])
	for rejected in [
		'{"focus":"evidence","scenarios":[37,526,1044],"grade":100}',
		'{"focus":"wrong","scenarios":[37,526,1044]}',
		'{"focus":"method","scenarios":[37,37,1044]}',
		'{"focus":"method","scenarios":[37,526.5,1044]}',
		'{"focus":"method","scenarios":[37,0,1044]}',
		'{"focus":"method","scenarios":[37,526,4097]}'
	]:
		assert(Plan.parse(rejected).is_empty())
	valid.salt="host-private-test-salt"
	var bridge:=Provider.new()
	for case in [["ETY155","lab"],["ELM253","lab"],["DGS266","lab"],["MTH147","lecture"],["MTH255","lecture"]]:
		for week in bridge.weeks(case[0],case[1]):
			var original: Dictionary=bridge.generate(case[0],int(week.week),case[1],0,954)
			assert(not original.is_empty() and not original.has("error"))
			original.assessment_id="stable-attempt"
			original.official_curriculum_id="extra:verified"
			original.assessment_policy={"formula_allowed":false}
			var generated:=Plan.compile(bridge,original,valid,"student-a")
			assert(not generated.is_empty(),str(case)+" week "+str(week.week))
			assert(generated.course_id==original.course_id and generated.week==original.week and generated.assessment_id=="stable-attempt")
			assert(generated.official_curriculum_id=="extra:verified" and generated.assessment_policy==original.assessment_policy)
			assert(generated.get("practical",{}).get("type","")==original.get("practical",{}).get("type",""))
			assert(generated==Plan.compile(bridge,original,valid,"student-a"))
			assert(generated!=Plan.compile(bridge,original,valid,"student-b"))
			assert(not bridge.grade(generated,{}).has("error"))
			assert(not bridge.public_copy(generated).questions[0].has("answer"))
	if OS.get_environment("LABVOLT_TEST_OPENAI")=="1":
		await room_assessment()
	print("AI_ASSESSMENT_PLAN PASS")
	quit()

func room_assessment() -> void:
	var game=load("res://scenes/Main.tscn").instantiate()
	root.add_child(game)
	for i in 4:await process_frame
	game.front.entered()
	game.school.start("Freeplay",0)
	var client: Node=game.host_openai
	assert(client.set_local_test_endpoint("http://127.0.0.1:28768/v1"))
	assert(client.set_session_key("sk-test-12345678901234567890"))
	assert(client.configure("gpt-5.4-mini",128,"",true)==OK)
	var verification: Dictionary=await client.verify_class_connection()
	assert(verification.ok)
	var classes: Node=game.lecture_classes
	var room:="dc_lab"
	game.player.global_position=classes.signs[room].desk
	classes._apply(1,"start",room,{"kind":"lab","course_id":"ETY155","week":1,"difficulty":0})
	assert(classes.classes.has(room))
	assert(classes._sign(1,room)=="")
	var activity: Dictionary=classes.classes[room]
	activity.phase="lesson"
	activity.deadline=classes._now()+classes.LessonSeconds
	var identity: String=game.school.identities[1]
	var original: Dictionary=activity.students[identity].project
	assert(not classes._begin_assignment(room,activity))
	assert(activity.phase=="lesson" and activity.students[identity].paper==0)
	var timeout:=Time.get_ticks_msec()+6000
	while activity.assessment_plan_state.pending and Time.get_ticks_msec()<timeout:await process_frame
	assert(classes._begin_assignment(room,activity))
	var paper: Dictionary=game.school.papers[activity.students[identity].paper]
	assert(paper.project.assessment_focus==Plan.FOCUS.evidence and paper.project.get("seed","")!=original.get("seed",""))
	assert(paper.project.practical.get("type","")==original.practical.get("type",""))
	var answers := {}
	for index in paper.project.questions.size():
		var question: Dictionary=paper.project.questions[index]
		answers[str(index)]=str(question.answer) if not question.options.is_empty() else "%s %s"%[question.answer,question.unit]
	assert(game.school.course_bridge.grade(paper.project,answers).score==100)
	classes.classes.erase(room)
	print("AI_ROOM_ASSESSMENT PASS")

	var school: Node=game.school
	var started: Dictionary=school.request_activity({"mode":"Course","kind":"lecture","course_id":"MTH147","week":1,"difficulty":0})
	assert(started.ok,str(started))
	school.phase="lesson"
	var lecture_room: String=school.activity.room.id
	game.campus.request_room(lecture_room)
	game.player.global_position=game.campus.registry.vector(game.campus.registry.get_room(lecture_room).center)
	game.campus.set_viewer_position(game.player.global_position)
	await physics_frame
	await physics_frame
	game.faculty._sync_lectures()
	var lecturer: Node3D=game.faculty.lecture_models.get(lecture_room)
	assert(is_instance_valid(lecturer),"Course lecture has no instructor")
	var origin:=lecturer.global_position
	timeout=Time.get_ticks_msec()+8000
	while origin.distance_to(lecturer.global_position)<.25 and Time.get_ticks_msec()<timeout:
		game.faculty.formal_lesson_ready()
		await process_frame
	assert(origin.distance_to(lecturer.global_position)>=.25,"Course instructor did not move during the AI lesson")
	assert(game.campus.registry.room_contains(lecture_room,lecturer.global_position))
	print("AI_FORMAL_LECTURER_MOVEMENT PASS")
	school.remaining=0.0
	var old_project: Dictionary=school._individual_project(identity)
	school.advance(0.0)
	assert(school.phase=="lesson" and school.formal_assessment_plan.pending)
	timeout=Time.get_ticks_msec()+6000
	while school.formal_assessment_plan.pending and Time.get_ticks_msec()<timeout:await process_frame
	school.advance(0.0)
	assert(school.phase=="assignment")
	var assigned: Dictionary=school._individual_project(identity)
	assert(assigned.assessment_focus==Plan.FOCUS.evidence and assigned.assessment_id==old_project.assessment_id)
	assert(assigned.questions!=old_project.questions)
	assert(school.course_bridge.grade(assigned,{})["score"]==0.0)
	print("AI_FORMAL_ASSESSMENT PASS")
	game.queue_free()
	await process_frame
