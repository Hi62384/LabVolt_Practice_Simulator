extends SceneTree
const Journal=preload("res://scripts/campus_recovery_journal.gd")
func _initialize() -> void:call_deferred("run")
func run() -> void:
	var game=load("res://scenes/Main.tscn").instantiate();root.add_child(game)
	await process_frame;game.capture()
	var school=game.school
	var started: Dictionary=school.start_activity({"mode":"Course","course_id":"ETY155","kind":"lab","week":1,"difficulty":0,"assessment_seconds":120})
	assert(started.ok,str(started.get("error","")))
	game.session.poses[1].position=school.teacher_position+Vector3(0,0,1)
	assert(school.begin_lesson())
	school.advance(school.teaching_seconds)
	assert(school.phase=="assignment")
	var papers: Array=school.papers.values().filter(func(p):return not p.lesson and p.class_round==school.round_id)
	assert(papers.size()==1)
	var original: Dictionary=papers[0];var paper_id: int=original.id
	game.session.poses[1].position=original.position-Vector3(0,.895,0)
	school.request({"op":"answer","id":paper_id,"key":"0","value":"1234"})
	school.request({"op":"page","id":paper_id,"page":2})
	school.request({"op":"stroke","id":paper_id,"page":2,"points":[Vector2(.2,.3),Vector2(.4,.5)]})
	assert(original.answers.get("0","")=="1234" and original.page==2 and not original.strokes.is_empty())
	var deadline: float=school.assessment_deadline;var token: String=school.local_identity
	school.checkpoint()
	assert(Journal.summary(token).ok)
	assert(not Journal.summary("f".repeat(48)).ok)
	game.queue_free();await process_frame
	game=load("res://scenes/Main.tscn").instantiate();root.add_child(game)
	await process_frame;await process_frame
	assert(game.school.local_identity==token)
	assert(game.front.body.get_children().any(func(n):return n is Button and n.text=="Resume Saved Class"))
	game.front.resume_class_page()
	var resume: Button
	for child in game.front.body.get_children():
		if child is Button and child.text=="Resume class":resume=child
	assert(resume!=null);resume.pressed.emit()
	assert(game.front.in_game and game.school.phase=="assignment")
	assert(game.school.assessment_deadline==deadline)
	assert(game.school.identities.get(1,"")==token)
	assert(game.school.papers.has(paper_id))
	var restored: Dictionary=game.school.papers[paper_id]
	assert(restored.owner==1 and restored.answers.get("0","")=="1234" and restored.page==2 and not restored.strokes.is_empty())
	assert(not Journal.summary("e".repeat(48)).ok)
	game.front.in_game=false;game.queue_free();await process_frame
	print("PASS: actual Main restart exposes profile-bound Resume Saved Class, normal button restores identity, original deadline, answers, page and ink")
	quit()
