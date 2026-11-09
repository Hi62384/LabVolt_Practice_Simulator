extends SceneTree
const Course=preload("res://scripts/course_generator.gd")
var failures := 0
var checks := 0
func check(value: bool,label: String) -> void:
	checks+=1
	if not value:failures+=1;printerr("FAIL SCHOOL: "+label)
func _initialize():call_deferred("run")
func run() -> void:
	for topic in range(Course.TOPICS.size()):
		for difficulty in range(3):
			var p: Dictionary=Course.generate(topic,difficulty,12345)
			var answers := {}
			for i in range(p.questions.size()):answers[str(i)]=str(p.questions[i].answer)
			check(Course.grade(p,answers).score==100,"answer key grades correctly %d/%d"%[topic,difficulty])
			check(not Course.public_copy(p).questions[0].has("answer"),"answer key excluded from student snapshots")
	var transformer: Dictionary=Course.generate(8,0,77)
	check(transformer.questions[0].answer*transformer.questions[1].answer>0,"transformer output positive")
	var ui=preload("res://scripts/paper_ui.gd")
	check(float(ui.calculate_expression("sqrt(9) + 2^3").trim_prefix("= "))==11,"calculator arithmetic")
	check(ui.calculate_expression("OS.execute('bad')")!="= 0","calculator rejects object access")
	var game=load("res://scenes/Main.tscn").instantiate()
	root.add_child(game)
	await create_timer(.3).timeout
	var school=game.school
	school.start("Freeplay",1)
	game.capture()
	game.session.poses[1].position=school.teacher_position
	school.request({"op":"new","topic":2,"difficulty":2})
	var id: int=school.held(1)
	check(id>0,"teacher gives carried assignment")
	var paper: Dictionary=school.papers[id]
	check(paper.project.questions.size()>=4,"generated assignment has questions")
	school.identities[99]="foreign"
	var old_answers: Dictionary=paper.answers.duplicate()
	school.apply(99,{"op":"answer","id":id,"key":"0","value":"999"})
	check(paper.answers==old_answers,"other player cannot write")
	school.apply(99,{"op":"pickup","id":id})
	check(paper.owner==1,"other player cannot pick up")
	school.identities.erase(99)
	game.session.poses[1].position=Vector3(6.5,0,6)
	school.request({"op":"place","id":id,"position":Vector3(6.0,.895,6)})
	check(not paper.held,"table placement")
	school.request({"op":"page","id":id,"page":2})
	school.request({"op":"stroke","id":id,"page":2,"points":[Vector2(.1,.2),Vector2(.7,.5)]})
	for i in range(paper.project.questions.size()):school.request({"op":"answer","id":id,"key":str(i),"value":str(paper.project.questions[i].answer)})
	school.request({"op":"pickup","id":id})
	check(paper.held and paper.page==2 and paper.strokes["2"].size()==1,"moving retains page, notes and answers")
	game.session.poses[1].position=school.teacher_position
	var old_count: int=school.gradebook.size()
	school.request({"op":"submit","id":id})
	check(paper.mark.score==100,"teacher returns marked assignment")
	school.request({"op":"submit","id":id})
	check(school.gradebook.size()==old_count,"Freeplay practice is marked without adding official grades, including repeated submission")
	school.start("Class",0)
	check(school.phase=="lesson" and school.remaining==300,"five-minute introduction")
	school.advance(300)
	check(school.phase=="assignment" and school.remaining==1800,"thirty-minute assignment")
	id=school.held(1)
	check(id>0,"Class sheet issued")
	game.session.roster[2]={"name":"Late student","ready":false}
	var late_token := Crypto.new().generate_random_bytes(24).hex_encode()
	school._identify(2,late_token)
	check(school.papers.values().any(func(p):return p.owner==2 and not p.lesson and p.class_round==0),"late arrival gets the complete assignment as ungraded practice")
	check(not school.class_students.has(late_token),"late arrival has no current deadline penalty")
	game.session.roster.erase(2)
	school.roster_changed()
	var token: String=school.local_identity
	school.papers[id].answers["0"]="12"
	game.session.roster.erase(1)
	school.roster_changed()
	check(school.papers.is_empty(),"disconnect removes owned physical sheets")
	game.session.roster[1]={"name":"Rejoined","ready":false}
	school._identify(1,token)
	check(school.papers.has(id) and school.papers[id].answers["0"]=="12","reconnect restores work")
	check(school.remaining==1800,"reconnect preserves original deadline")
	school.advance(1800)
	check(school.phase=="break" and school.papers[id].mark.score==0,"deadline gives failing grade then break")
	var marked_count: int=school.gradebook.size()
	school._mark(school.papers[id],true)
	check(school.gradebook.size()==marked_count and marked_count==old_count+1,"official deadline grade is recorded exactly once")
	school.advance(60)
	check(school.phase=="lesson" and school.round_id==2,"break repeats with next assignment")
	game.paper_ui.open_sheet(id)
	await create_timer(.1).timeout
	check(game.paper_ui.screen.visible,"sheet reader opens")
	print("SCHOOL: %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)
