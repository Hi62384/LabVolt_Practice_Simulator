extends SceneTree
const Archive=preload("res://scripts/campus/computers/usb_archive.gd")
const Drive=preload("res://scripts/campus/computers/device_filesystem.gd")
var game: Node
var deadline: int
func _initialize() -> void:call_deferred("run")
func until(condition: Callable,label: String) -> bool:
	while Time.get_ticks_msec()<deadline:
		if condition.call():return true
		await create_timer(.05).timeout
	push_error("USB LOST ACK TIMEOUT: "+label);quit(1);return false
func run() -> void:
	var args:=OS.get_cmdline_user_args()
	if args.size()!=2 or args[0] not in ["host","client"] or not args[1].is_valid_int():quit(1);return
	var role:=str(args[0]);var port:=int(args[1]);var id:="d".repeat(32);var token:="e".repeat(32)
	game=load("res://scenes/Main.tscn").instantiate();root.add_child(game)
	for i in 4:await process_frame
	var signal_node=preload("res://tests/campus/computers/usb_test_signal.gd").new();signal_node.name="UsbTestSignal";game.add_child(signal_node)
	var profile=game.electronics.profile;profile.open("usb-lost-ack-"+role)
	game.school.local_identity=profile.data.dorm.owner
	var drive=Drive.new(8*1024*1024);drive.write_file("receipt.txt","verified archive".to_utf8_buffer())
	if Archive.save(game.school.local_identity,id,"USB drive",8,drive)!=OK:quit(1);return
	if role=="host":
		profile.data.dorm.usb_drives={id:{"name":"USB drive","capacity_mb":8,"location":"handoff"}}
		profile.data.usb_handoff_pending={id:token};profile.save()
	deadline=Time.get_ticks_msec()+60000
	var point:=Vector3(20,5,63)
	if role=="host":
		if game.session.host_game("USB host",port)!=OK:quit(1);return
		print("USB_LOST_ACK_HOST_READY")
		if not await until(func():return game.session.roster.size()==2 and game.electronics_trade.authority.ledger.bindings.size()==2,"both inventory bindings"):return
		var peer:=0
		for key in game.session.roster:
			if int(key)!=1:peer=int(key)
		if not await until(func():return signal_node.staged,"recipient staged archive"):return
		var ledger=game.electronics_trade.authority.ledger
		var target_owner: String=ledger.bindings[peer]
		var committed: Dictionary=ledger.commit_usb_handoff(1,peer,id,token)
		if not committed.get("ok",false):push_error("USB commit failed: "+str(committed.get("error","")));quit(1);return
		# Deliberately omit the final recipient snapshot; the client disconnects
		# normally and reconnects with its pre-commit profile and staged archive.
		game.electronics_trade.authority.send_snapshot(1,committed.source)
		if not await until(func():return game.session.roster.size()==1,"recipient disconnected"):return
		if not await until(func():return game.session.roster.size()==2 and ledger.bindings.values().has(target_owner),"recipient rebound"):return
		if not ledger.state.accounts[target_owner].profile.dorm.get("usb_drives",{}).has(id) or ledger.state.accounts[profile.data.dorm.owner].profile.dorm.get("usb_drives",{}).has(id):push_error("Committed ownership was not reconciled");quit(1);return
		print("USB_LOST_ACK_HOST PASS")
	else:
		if game.session.join_game("127.0.0.1","USB recipient",port)!=OK:quit(1);return
		if not await until(func():return game.session.roster.size()==2 and game.electronics_trade.authority.bound,"initial binding"):return
		profile.data.usb_received_pending={id:{"token":token,"host":game.electronics_trade.authority.bound_host}}
		var pending_callback: Callable=profile.authority_submit;profile.authority_submit=Callable()
		if profile.save()!=OK:push_error("Could not persist staged receipt");quit(1);return
		profile.authority_submit=pending_callback
		var stale_profile: Dictionary=profile.data.duplicate(true)
		signal_node.report_staged.rpc_id(1)
		await create_timer(2.0).timeout
		# Simulate losing the final acknowledgement even if an unrelated
		# authority refresh delivered it during the fixture's wait.
		profile.data=stale_profile
		var callback: Callable=profile.authority_submit;profile.authority_submit=Callable()
		if profile.save()!=OK:push_error("Could not restore stale fixture");quit(1);return
		profile.authority_submit=callback
		game.session.leave();await create_timer(2.0).timeout
		if game.session.join_game("127.0.0.1","USB recipient",port)!=OK:quit(1);return
		if not await until(func():return game.session.roster.size()==2 and game.electronics_trade.authority.bound and profile.data.dorm.get("usb_drives",{}).has(id),"committed delivery recovered"):return
		if profile.data.get("usb_received_pending",{}).has(id):push_error("Recovered delivery left a pending receipt");quit(1);return
		var loaded: Dictionary=Archive.load(game.school.local_identity,id,8)
		if loaded.has("error") or loaded.drive.entries["receipt.txt"].data.get_string_from_utf8()!="verified archive":push_error("Staged archive did not survive reconnect");quit(1);return
		await create_timer(.5).timeout
		print("USB_LOST_ACK_CLIENT PASS")
	game.session.leave();game.queue_free();await process_frame;quit()
