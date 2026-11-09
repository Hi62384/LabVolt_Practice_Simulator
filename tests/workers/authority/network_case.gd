extends SceneTree
var game
var role := ""
var phase := ""
var port := 25350
var control := ""
var deadline := 0
func mark(label: String) -> void:
	var file := FileAccess.open(control+"/"+label,FileAccess.WRITE);file.store_string("ok");file.close()
func wait_until(test: Callable,label: String) -> bool:
	while not test.call():
		if Time.get_ticks_msec()>deadline:push_error("TIMEOUT "+label);quit(1);return false
		await create_timer(.05).timeout
	return true
func _initialize() -> void:call_deferred("run")
func run() -> void:
	var args := OS.get_cmdline_user_args();role=args[0];phase=args[1];port=int(args[2]);control=args[3]
	deadline=Time.get_ticks_msec()+45000
	game=load("res://scenes/Main.tscn").instantiate();root.add_child(game)
	for frame in 4:await process_frame
	game.characters.selected="authority-network-"+role
	game.school._identity_changed()
	game.electronics.profile.open("authority-network-"+role)
	var trade=game.electronics_trade;var authority=trade.authority
	if role=="host":
		assert(game.session.host_game("Host",port)==OK);game.school.start("Freeplay",0)
		mark("listening-"+phase)
	else:assert(game.session.join_game("127.0.0.1","Client",port)==OK)
	if not await wait_until(func():return authority.bound,"profile binding"):return
	if phase=="recover":
		assert(game.electronics.profile.data.inventory.r1000==(6 if role=="host" else 10))
		assert(game.electronics.profile.data.inventory.r220==(5 if role=="host" else 3))
		mark(role+"-recovered")
		if role=="host":await wait_until(func():return FileAccess.file_exists(control+"/client-recovered"),"other recovery")
		print("PASS network "+role+" restart/reconnect host stock and local save convergence");quit();return
	if role=="host":
		if not await wait_until(func():return authority.ledger.bindings.size()==2,"two authoritative accounts"):return
		var target=authority.ledger.bindings.keys().filter(func(peer):return peer!=1)[0]
		trade.request({"op":"invite","target":target})
	if not await wait_until(func():return not trade.current.is_empty(),"trade invitation"):return
	var id: String=trade.current.id
	if phase=="cancel":
		if role=="client":
			trade.request({"op":"offer","id":id,"items":{"r220":99999},"definitions":{}})
			await create_timer(.3).timeout
			assert(trade.current.offers[game.multiplayer.get_unique_id()].is_empty())
			print("PASS network forged offer rejected; disconnect before confirmation");quit();return
		if not await wait_until(func():return game.session.roster.size()==1 and trade.trades.is_empty(),"disconnect cancels review"):return
		assert(authority.ledger.account(1).profile.inventory.r1000==8)
		print("PASS network cancellation leaves host stock unchanged");quit();return
	# A modified client asks the host to accept a free priced purchase and stock report.
	if role=="client":
		var fake: Dictionary=game.electronics.profile.data.duplicate(true);fake.inventory.r1000=99999;fake.dollars=999999;fake.analyzer=true
		authority.submit("metadata",[fake]);authority.submit("reward",["forged",100,2,false])
		if not await wait_until(func():return authority.pending.is_empty(),"forged operations replies"):return
		assert(game.electronics.profile.data.inventory.r1000==8 and game.electronics.profile.data.dollars==100 and not game.electronics.profile.data.analyzer)
	trade.request({"op":"offer","id":id,"items":{"r1000":2} if role=="host" else {"r220":1},"definitions":{}})
	if not await wait_until(func():return trade.current.offers.values().all(func(offer):return not offer.is_empty()),"offers"):return
	if role=="client":
		trade.command.rpc_id(1,{"op":"confirm","id":id,"revision":-1})
		await create_timer(.2).timeout
		assert(game.multiplayer.get_unique_id() not in trade.current.confirmed)
	trade.request({"op":"confirm","id":id})
	if not await wait_until(func():return game.electronics.profile.data.get("applied_trades",{}).has(id),"atomic commit"):return
	assert(game.electronics.profile.data.inventory.r1000==(6 if role=="host" else 10))
	assert(game.electronics.profile.data.inventory.r220==(5 if role=="host" else 3))
	mark(role+"-committed")
	print("PASS network "+role+" host-authoritative trade and forged metadata/reward rejection")
	if role=="host":
		await wait_until(func():return FileAccess.file_exists(control+"/client-committed"),"client commit")
		mark("host-crash-ready")
		# The Python parent kills only this test-owned process after this marker.
		await create_timer(30).timeout
	else:quit()

