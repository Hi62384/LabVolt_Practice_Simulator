extends SceneTree
const Photos=preload("res://scripts/campus/phones/photo_library.gd")
var game: Node
var deadline: int
func _initialize() -> void:call_deferred("run")
func until(check: Callable,label: String) -> bool:
	while Time.get_ticks_msec()<deadline:
		if check.call():return true
		await create_timer(.05).timeout
	print("PHONE DEBUG ",label," call=",game.smartphones.comm.local_call," messages=",game.smartphones.comm.messages," roster=",game.session.roster," bound=",game.electronics_trade.authority.bound)
	push_error("PHONE NETWORK TIMEOUT: "+label);quit(1);return false
func fail(message: String) -> void:push_error(message);quit(1)
func run() -> void:
	var args:=OS.get_cmdline_user_args()
	if args.size()!=2 or args[0] not in ["host","client"]:fail("Invalid arguments");return
	var role:=str(args[0]);var port:=int(args[1])
	game=load("res://scenes/Main.tscn").instantiate();root.add_child(game)
	for i in 4:await process_frame
	var profile=game.electronics.profile;profile.open("phone-network-"+role)
	game.school.local_identity=profile.data.dorm.owner
	profile.data.dollars=10000
	if role=="host":
		profile.buy_smartphone("basic")
		var phone_id: String=profile.data.dorm.smartphones.keys()[0]
		var bag: String="a".repeat(24)
		profile.data.dorm.backpacks={bag:{"size":"backpack_small","location":"back","items":[]}}
		var packed: Dictionary=preload("res://scripts/campus/dorms/authority/persistent_dorm.gd").apply_intent(profile.data,profile.data.dorm.owner,{"op":"bag_pack","bag":bag,"item":{"kind":"phone","id":phone_id},"revision":profile.data.dorm.revision})
		if not packed.get("ok",false):fail("Phone backpack fixture failed");return
		profile.data=packed.profile
	deadline=Time.get_ticks_msec()+70000
	if role=="host":
		if game.session.host_game("Phone host",port)!=OK:fail("Host failed");return
		print("PHONE_HOST_READY")
		if not await until(func():return game.electronics_trade.authority.ledger.bindings.size()==2,"client bound"):return
		if not await until(func():return game.electronics_trade.authority.ledger.state.accounts.values().any(func(a):return not a.profile.dorm.get("smartphones",{}).is_empty()),"purchase recorded"):return
		var comm=game.smartphones.comm
		if not await until(func():return not comm.messages.is_empty() and comm.local_call.get("state","")=="incoming","message and incoming call"):return
		if comm.messages.back().text!="Hello host":fail("Phone message changed");return
		if not comm.ring.playing:fail("Incoming call did not ring");return
		comm.request("answer")
		if comm.local_call.get("state","")!="active" or comm.ring.playing:fail("Call answer failed");return
		await create_timer(1.0).timeout
		var packet:=PackedByteArray();packet.resize(int(game.voice_chat.SAMPLE_RATE*game.voice_chat.PACKET_SECONDS)*2)
		for i in 8:
			game.voice_chat._relay(1,packet)
			await create_timer(.05).timeout
		if not await until(func():return comm.local_call.is_empty(),"call ended"):return
		comm.request("call",int(comm.messages.back().from))
		if comm.local_call.get("state","")!="outgoing":fail("Second call did not start");return
		if not await until(func():return game.session.roster.size()==1,"client left"):return
		if not await until(func():return comm.local_call.is_empty(),"disconnected call cleared"):return
		if not await until(func():return game.session.roster.size()==2 and game.electronics_trade.authority.ledger.bindings.size()==2,"client returned"):return
		if not await until(func():return game.session.roster.size()==1,"client complete"):return
		print("PHONE_HOST PASS")
	else:
		if game.session.join_game("127.0.0.1","Student",port)!=OK:fail("Join failed");return
		if not await until(func():return game.session.roster.size()==2 and game.electronics_trade.authority.bound,"bound"):return
		profile.buy_smartphone("standard")
		if not await until(func():return not profile.data.dorm.get("smartphones",{}).is_empty(),"purchase"):return
		var id: String=profile.data.dorm.smartphones.keys()[0]
		if not profile.data.get("phone_purchase_pending",{}).is_empty():fail("Purchase marker not cleared");return
		game.player.global_position=Vector3(30,0,40)
		game.session.send_pose({"position":game.player.global_position})
		var comm=game.smartphones.comm
		comm.request("message",1,"Hello host")
		comm.request("call",1)
		if not await until(func():return comm.local_call.get("state","")=="active","call answered"):return
		if not await until(func():return game.voice_chat.call_players.has(1),"remote call audio"):return
		comm.request("end")
		if not await until(func():return comm.local_call.is_empty(),"call ended"):return
		var image:=Image.create(24,24,false,Image.FORMAT_RGB8);image.fill(Color("54b1a4"))
		if not Photos.capture(game.school.local_identity,id,image,1024*1024).has("id"):fail("Photo fixture failed");return
		if not await until(func():return comm.local_call.get("state","")=="incoming","second incoming call"):return
		game.session.leave();await create_timer(2.0).timeout
		if game.session.join_game("127.0.0.1","Student",port)!=OK:fail("Reconnect failed");return
		if not await until(func():return game.session.roster.size()==2 and game.electronics_trade.authority.bound,"rebound"):return
		if profile.data.dorm.smartphones.size()!=1 or not profile.data.dorm.smartphones.has(id) or Photos.list(game.school.local_identity,id).photos.size()!=1:fail("Phone or photo was lost or duplicated");return
		print("PHONE_CLIENT PASS")
	await create_timer(.7).timeout
	game.session.leave();game.queue_free();await process_frame;quit()
