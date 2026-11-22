extends SceneTree
## Integration regressions for AI lesson completion, lost guests and host-side movement.
const Computer = preload("res://scripts/campus/computers/computer_sessions.gd")
const Phone = preload("res://scripts/campus/phones/phone_network.gd")
const Elevator = preload("res://scripts/campus/elevator/elevator_service.gd")
const Geometry = preload("res://scripts/campus/elevator/elevator_geometry.gd")

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	assert(Computer.bounded_request({"op":"save","text":"ok"}))
	assert(not Computer.bounded_request({"op":"save","text":"x".repeat(Computer.MAX_REQUEST_BYTES)}),"Oversized computer RPC accepted")
	assert(not Computer.bounded_request({"op":"restore","profile":"forged"}),"Client-owned identity accepted")
	assert(Phone.bounded_request("message","hello"))
	assert(not Phone.bounded_request("message","z".repeat(241)),"Oversized phone message accepted")
	var interior_button: Vector3=Geometry.control_position(0,0)
	assert(Elevator._inside(interior_button,0),"Elevator cabin control must be inside the cabin")

	var game = load("res://scenes/Main.tscn").instantiate()
	root.add_child(game)
	for frame in 4:
		await process_frame
	game.front.entered()
	var session=game.session
	session.roster[2]={"name":"Audit guest"}
	session.pose_epochs[2]=0
	var start_pose:=Vector3(13,0,-18)
	session.poses[2]={"position":start_pose}
	for i in 100:
		session.last_pose[2]=Time.get_ticks_msec()
		var current: Vector3=session.poses[2].position
		session.accept_pose(2,{"position":current+Vector3(.395,0,0),"pose_epoch":0})
	assert(session.poses[2].position.distance_to(start_pose)<1.0,"Movement rate limit grants free distance per packet")
	session.poses[2].position=Vector3(23,0,30)
	session._travel(2,true)
	assert(not session.shop_returns.has(2),"Remote peer entered shop from arbitrary location")
	session.poses[2].position=start_pose
	session._travel(2,true)
	assert(session.shop_returns.has(2) and session.poses[2].position==Vector3(26,0,3),"Legitimate menu shop entry was rejected")
	session._travel(2,false)
	assert(not session.shop_returns.has(2),"Legitimate shop exit was rejected")

	var school=game.school
	var token: String=Crypto.new().generate_random_bytes(24).hex_encode()
	school.mode="Class"
	school.phase="lesson"
	school.class_students[token]={"done":false,"replay":false}
	school.identities[2]=token
	school._fail_departing(token,2)
	assert(not school.archive.has(token) or school.archive[token].is_empty(),"Disconnected guest was assigned an official zero")
	# Use a real worksheet produced by the game; a partial synthetic
	# dictionary would crash the unrelated SchoolWorld render/grade pipeline.
	var project: Dictionary=school.course_bridge.generate("ETY155",1,"lecture",0,123)
	assert(not project.is_empty() and not project.has("error"))
	var paper_id: int=school._give(2,project,false,false)
	assert(paper_id>0)
	school.papers[paper_id].class_round=701
	school.papers[paper_id].answers["0"]="retained"
	school.papers[paper_id].held=false
	school.papers[paper_id].owner=0
	school.identities.erase(2)
	school.round_id=701
	school.phase="assignment"
	session.roster[3]={"name":"Returning guest"}
	school._identify(3,token)
	assert(school.papers[paper_id].owner==3 and school.papers[paper_id].answers["0"]=="retained","Reconnect discarded existing assessment answers")
	# Restore the fixture to Freeplay so the main game timer cannot grade a
	# synthetic active class during test teardown.
	school.class_students.clear()
	school.papers.clear()
	school.identities.erase(3)
	school.mode="Freeplay"
	school.phase="freeplay"

	var classes=game.lecture_classes
	game.faculty.current["dc_lab"]="mr_phillips"
	var error: String=classes._start("dc_lab",{"kind":"lab","course_id":"ETY155","week":1,"difficulty":0})
	assert(error.is_empty(),error)
	var activity: Dictionary=classes.classes["dc_lab"]
	activity.phase="lesson"
	activity.ai_teaching=true
	activity.ai_waiting=true
	activity.deadline=classes._now()-1.0
	# Empty enrollment does not need a model response. The deadline must
	# advance into assessment rather than extend itself forever.
	classes._process(.25)
	assert(activity.phase=="assignment","AI-taught class remained stuck in the lesson phase")
	print("AUDIT_CLASS_LIFECYCLE PASS")
	quit()
