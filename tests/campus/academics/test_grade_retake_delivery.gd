extends SceneTree
func _initialize() -> void:call_deferred("run")
func run() -> void:
	var game=load("res://scenes/Main.tscn").instantiate();root.add_child(game)
	for i in 4:await process_frame
	var school=game.school
	var identity: String=school.local_identity
	var first: Dictionary={"id":"first","profile":identity,"course_id":"ETY155","kind":"lecture","week":1,"gradebook_assessment_id":"lecture:1","course_attempt":1,"score":20.0,"time":"2026-01-01T12:00:00","lesson":false}
	school.gradebook={"first":first.duplicate(true)}
	var retake: Dictionary=first.duplicate(true);retake.id="retake";retake.course_attempt=2;retake.score=90.0
	school._receive_grade(retake)
	assert(school.gradebook.size()==2 and float(school.gradebook.retake.score)==90.0)
	var duplicate: Dictionary=retake.duplicate(true);duplicate.id="duplicate";duplicate.score=100.0
	school._receive_grade(duplicate)
	assert(school.gradebook.size()==2)
	var replay: Dictionary=first.duplicate(true);replay.id="replay";replay.score=100.0
	school._receive_grade(replay)
	assert(school.gradebook.size()==2 and float(school.gradebook.first.score)==20.0)
	print("GRADE_RETAKE_DELIVERY PASS")
	game.queue_free();await process_frame;quit(0)
