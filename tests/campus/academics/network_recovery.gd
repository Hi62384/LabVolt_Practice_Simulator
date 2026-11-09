extends SceneTree
const Fixtures = preload("res://tests/campus/academics/test_academics.gd")
const School = preload("res://scripts/school_session.gd")
var failures := 0
var game: Node
var school: Node
var role := ""
var client_token := "b".repeat(48)
var reconnect_count := 0
var saw_saved := false

func check(value: bool,label: String) -> void:
	if not value:failures+=1;push_error("NETWORK FAIL: "+label)
	else:print("NETWORK PASS: "+label)

func wait_for(predicate: Callable,seconds: float=12) -> bool:
	var deadline := Time.get_ticks_msec()+int(seconds*1000)
	while Time.get_ticks_msec()<deadline:
		if predicate.call():return true
		await create_timer(.05).timeout
	return false

func _initialize() -> void:call_deferred("run")

func run() -> void:
	role=OS.get_cmdline_user_args()[0]
	game=Fixtures.GameStub.new();game.name="Game";root.add_child(game)
	game.add_child(game.session);game.add_child(game.ui);game.add_child(game.sfx)
	game.session.roster={1:{"name":"Host"}};game.session.online=true
	school=School.new();school.name="School";game.add_child(school);school.game=game
	school.local_identity="a".repeat(48) if role=="host" else client_token
	school.identities={1:school.local_identity} if role=="host" else {}
	school.configure_campus(Fixtures.RoomStub.new(),Fixtures.ProviderStub.new())
	if role=="host":
		var peer := ENetMultiplayerPeer.new();check(peer.create_server(25550,7)==OK,"Host port 25550")
		root.get_multiplayer().multiplayer_peer=peer
		root.get_multiplayer().peer_connected.connect(func(id):
			game.session.roster[id]={"name":"Student"};game.session.poses[id]={"position":Vector3.ZERO}
			school._identify(id,client_token);reconnect_count+=1)
		root.get_multiplayer().peer_disconnected.connect(func(id):
			game.session.roster.erase(id);school.roster_changed();saw_saved=school.class_students.get(client_token,{}).has("saved"))
		check(await wait_for(func():return reconnect_count==1),"Student connected")
		var config := {"mode":"Course","course_id":"ETY155","kind":"lab","week":4,"teaching_seconds":300}
		# Activity-start movement is core-owned; test peers are already inside the fixture room.
		check(school.start_activity(config).ok,"Host authoritative course start")
		school.begin_lesson();school.advance(300)
		var original_deadline: float=school.assessment_deadline
		check(await wait_for(func():return saw_saved),"Disconnect saves actual written sheet")
		check(await wait_for(func():return reconnect_count==2),"Student reconnects with a new peer ID")
		check(school.assessment_deadline==original_deadline,"Reconnect never resets original deadline")
		check(await wait_for(func():return school.class_students[client_token].done),"Reconnected student submits original assessment")
		check(school.archive.get(client_token,{}).size()==1,"Exactly one immutable grade for reconnect attempt")
		await create_timer(.5).timeout
	else:
		connect_client()
		check(await wait_for(func():return school.phase=="assignment" and not own_official().is_empty()),"Client receives matching class state and official paper")
		var paper := own_official();var id := int(paper.get("id",0))
		school.request({"op":"answer","id":id,"key":"0","value":".01"})
		school.request({"op":"stroke","id":id,"page":1,"points":[Vector2(.2,.3),Vector2(.5,.6)],"color":"b24c45","width":5.0})
		check(await wait_for(func():return school.papers.get(id,{}).get("answers",{}).get("0","")==".01"),"Authoritative answer acknowledgement")
		root.get_multiplayer().multiplayer_peer.close()
		root.get_multiplayer().multiplayer_peer=OfflineMultiplayerPeer.new()
		await create_timer(.4).timeout
		connect_client()
		check(await wait_for(func():return school.papers.has(id) and int(school.papers[id].owner)==root.get_multiplayer().get_unique_id()),"Reconnect receives original physical paper")
		check(school.papers[id].answers.get("0","")==".01" and school.papers[id].strokes.get("1",[]).size()==1,"Answers and ink survive a real network disconnect")
		# Restored paper lies on desk; move host fixture pose within pickup range.
		school.request({"op":"pickup","id":id})
		await create_timer(.2).timeout
		school.request({"op":"submit","id":id})
		check(await wait_for(func():return not school.papers[id].mark.is_empty()),"Marked return delivered over reliable RPC")
	print("ACADEMICS_NETWORK %s failures=%d"%[role,failures])
	root.get_multiplayer().multiplayer_peer=OfflineMultiplayerPeer.new()
	game.free()
	quit(0 if failures==0 else 1)

func connect_client() -> void:
	var peer := ENetMultiplayerPeer.new()
	check(peer.create_client("127.0.0.1",25550)==OK,"Client connection request")
	root.get_multiplayer().multiplayer_peer=peer

func own_official() -> Dictionary:
	for paper in school.papers.values():
		if int(paper.owner)==root.get_multiplayer().get_unique_id() and not paper.lesson:return paper
	return {}
