extends SceneTree
const Rooms=preload("res://scripts/campus/world/room_registry.gd")
var game
var role: String
var room: String
var deadline: int
func until(condition: Callable,label: String) -> bool:
	while Time.get_ticks_msec()<deadline:
		if condition.call():return true
		await create_timer(.05).timeout
	push_error("CLASS NETWORK TIMEOUT "+label)
	quit(1)
	return false
func _initialize():call_deferred("run")
func run():
	role=OS.get_cmdline_user_args()[0]
	game=load("res://scenes/Main.tscn").instantiate()
	root.add_child(game)
	for i in 4:await process_frame
	deadline=Time.get_ticks_msec()+42000
	var classes=game.lecture_classes
	room=Rooms.LECTURE_ROOMS[0]
	var desk: Vector3=classes.signs[room].desk
	if role=="host":
		if game.session.host_game("Host",26310)!=OK:quit(1);return
		if not await until(func():return classes.classes.has(room),"remote desk start"):return
		var activity: Dictionary=classes.classes[room]
		activity.deadline=0.0
		classes._advance()
		if not await until(func():return activity.students.size()==1,"remote attendance during lesson"):return
		activity.deadline=0.0
		classes._advance()
		if not await until(func():return activity.phase=="assignment","assignment starts"):return
		var token: String=activity.students.keys()[0]
		var paper_id: int=activity.students[token].paper
		game.school.papers[paper_id].answers["0"]="saved before reconnect"
		var old_peer: int=activity.students[token].peer
		if not await until(func():return not game.session.roster.has(old_peer),"peer disconnected"):return
		if activity.students[token].done:push_error("FAIL guest was marked on disconnect");quit(1);return
		var grades: Array=game.school.archive[token].values().filter(func(record):return record.get("assessment_id","")==activity.id)
		if grades.size()!=1 or grades[0].has("score"):push_error("FAIL enrollment was settled early "+str(grades));quit(1);return
		if not await until(func():
			var new_peer: Variant=game.school.identities.find_key(token)
			return new_peer!=null and new_peer!=old_peer and game.school.papers[paper_id].owner==new_peer
		,"same assessment rebound to returning identity"):return
		if game.school.papers[paper_id].answers.get("0","")!="saved before reconnect":push_error("FAIL answer lost on reconnect");quit(1);return
		await create_timer(3).timeout
		print("PASS host preserved pending enrollment, paper and answer")
	else:
		if game.session.join_game("127.0.0.1","Student",26310)!=OK:quit(1);return
		if not await until(func():
			game.player.global_position=desk
			game.session.send_pose({"position":desk})
			if game.session.roster.size()!=2:return false
			var own: Dictionary=game.session.poses.get(game.multiplayer.get_unique_id(),{})
			return own.get("position",Vector3.INF).distance_to(desk)<.6
		,"host-validated classroom approach"):return
		classes._send("start",room,{"kind":"lecture","course_id":"MTH147","week":1,"difficulty":0})
		if not await until(func():return classes.public_classes.get(room,{}).get("phase","")=="lesson","replicated lesson phase"):return
		classes._send("sign",room,{})
		if not await until(func():return classes.public_classes.get(room,{}).get("phase","")=="assignment" and game.school.papers.values().any(func(p):return p.owner==game.multiplayer.get_unique_id()),"replicated assignment and owned paper"):return
		var paper: Dictionary=game.school.papers.values().filter(func(p):return p.owner==game.multiplayer.get_unique_id())[0]
		var paper_id: int=paper.id
		var old_peer: int=game.multiplayer.get_unique_id()
		game.session.leave()
		await create_timer(.75).timeout
		if game.session.join_game("127.0.0.1","Student",26310)!=OK:quit(1);return
		if not await until(func():
			var restored: Dictionary=game.school.papers.get(paper_id,{})
			return restored.get("owner",0)==game.multiplayer.get_unique_id() and restored.get("answers",{}).get("0","")=="saved before reconnect"
		,"assigned paper and answer restored on reconnect"):return
		if game.multiplayer.get_unique_id()==old_peer:push_error("FAIL reconnect did not get a new peer id");quit(1);return
		print("PASS client regained the same assignment and answer")
	quit()
