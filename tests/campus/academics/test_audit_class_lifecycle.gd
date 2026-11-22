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
	school.identities.erase(2)
	school.round_id=701
	school.phase="assignment"
	school.papers[701]={"id":701,"identity":token,"owner":0,"class_round":701,"project":{},"answers":{"0":"retained"},"mark":{},"revision":0,"held":false}
	session.roster[3]={"name":"Returning guest"}
	school._identify(3,token)
	assert(school.papers[701].owner==3 and school.papers[701].answers["0"]=="retained","Reconnect discarded existing assessment answers")

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
