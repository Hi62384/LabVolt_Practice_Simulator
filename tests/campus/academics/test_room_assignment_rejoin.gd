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
		var old_peer: int=activity.students[token].peer
		if not await until(func():return not game.session.roster.has(old_peer),"peer disconnected"):return
		if not await until(func():return activity.students[token].done,"assignment settled"):return
		var grades: Array=game.school.archive[token].values().filter(func(record):return record.get("assessment_id","")==activity.id)
		if grades.size()!=1 or grades[0].get("score",-1)!=0.0 or not grades[0].get("reason","").contains("Left the classroom"):push_error("FAIL incorrect departure grade "+str(grades));quit(1);return
		if not await until(func():return game.school.identities.values().has(token),"same identity rejoined"):return
		await create_timer(3).timeout
		print("PASS host settled one zero and accepted returning identity")
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
		var assessment: String=game.school.papers.values().filter(func(p):return p.owner==game.multiplayer.get_unique_id())[0].assessment_id
		var old_peer: int=game.multiplayer.get_unique_id()
		game.session.leave()
		await create_timer(.75).timeout
		if game.session.join_game("127.0.0.1","Student",26310)!=OK:quit(1);return
		if not await until(func():
			return game.school.gradebook.values().any(func(g):return g.get("assessment_id","")==assessment and g.get("score",-1)==0.0)
		,"zero grade received on reconnect"):return
		if game.multiplayer.get_unique_id()==old_peer or game.school.papers.values().any(func(p):return p.get("assessment_id","")==assessment and p.owner==game.multiplayer.get_unique_id()):push_error("FAIL assignment was reissued");quit(1);return
		print("PASS client rejoined and received zero without another assignment")
	quit()
