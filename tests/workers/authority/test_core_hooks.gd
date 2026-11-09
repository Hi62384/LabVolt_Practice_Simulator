extends SceneTree
# Integration admission test. Run ONLY after integrator applies the proposed DC
# guards; the immutable baseline deliberately fails this test.
var game
var role := ""
var control := ""
var deadline := 0
func marker(label: String) -> void:
	var file := FileAccess.open(control+"/"+label,FileAccess.WRITE);file.store_string("ok");file.close()
func wait_until(test: Callable,label: String) -> bool:
	while not test.call():
		if Time.get_ticks_msec()>deadline:push_error("TIMEOUT "+label);quit(1);return false
		await create_timer(.05).timeout
	return true
func _initialize() -> void:call_deferred("run")
func run() -> void:
	var args := OS.get_cmdline_user_args();role=args[0];var port := int(args[1]);control=args[2]
	deadline=Time.get_ticks_msec()+30000
	game=load("res://scenes/Main.tscn").instantiate();root.add_child(game)
	for frame in 4:await process_frame
	game.characters.selected="core-guard-"+role;game.school._identity_changed();game.electronics.profile.open("core-guard-"+role)
	if role=="host":
		assert(game.dc_lab.has_method("checkpoint_inventory"),"Apply authority proposed-hooks.patch before this integration admission test")
		assert(game.session.host_game("Host",port)==OK);game.school.start("Freeplay",0);marker("listening")
	else:assert(game.session.join_game("127.0.0.1","Client",port)==OK)
	var authority=game.electronics_trade.authority
	if not await wait_until(func():return authority.bound,"authority binding"):return
	if role=="host":
		if not await wait_until(func():return authority.ledger.bindings.size()==2,"peer binding"):return
		var peer: int=authority.ledger.bindings.keys().filter(func(id):return id!=1)[0]
		# Put the hostile request in valid physical reach, isolating stock validation.
		game.session.poses[peer]={"position":Vector3(0,0,8),"yaw":0.,"pitch":0.,"crouch":false};marker("reach")
		if not await wait_until(func():return FileAccess.file_exists(control+"/forged-sent"),"forged request"):return
		await create_timer(.4).timeout
		assert(game.dc_lab.benches[1].board.is_empty(),"Unowned component deployed by modified client")
		marker("forged-blocked")
		game.session.poses[peer].position=Vector3(0,0,8)
		if not await wait_until(func():return game.dc_lab.benches[1].board_owner==peer,"owned request"):return
		assert(authority.ledger.free_stock(peer,"r1000")==7,"World deployment did not reserve master stock")
		var token: String=authority.ledger.bindings[peer];marker("owned-accepted")
		if not await wait_until(func():return not game.session.roster.has(peer) and not authority.ledger.bindings.has(peer),"disconnect cleanup"):return
		assert(authority.ledger.state.accounts[token].deployment.is_empty())
		print("PASS core hooks: forged deployment rejected, valid deployment reserved, disconnect released");quit()
	else:
		game.player.position=Vector3(0,0,8)
		if not await wait_until(func():return FileAccess.file_exists(control+"/reach"),"reach fixture"):return
		var board: Dictionary=load("res://scripts/breadboard_model.gd").empty()
		board.parts=[{"id":"p","type":"r100000","a":"A1","b":"F1"}]
		game.dc_lab.request(1,{"op":"board","design":board});marker("forged-sent")
		if not await wait_until(func():return FileAccess.file_exists(control+"/forged-blocked"),"host rejects forged board"):return
		board.parts[0].type="r1000";authority.request_world(1,{"op":"board","design":board})
		if not await wait_until(func():return FileAccess.file_exists(control+"/owned-accepted"),"owned deployment"):return
		print("PASS core client: ordinary deploy and disconnect");quit()
