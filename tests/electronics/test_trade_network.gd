extends SceneTree
var game
var role := "host"
func _initialize() -> void:call_deferred("run")
func run() -> void:
	role=OS.get_cmdline_user_args()[0]
	game=load("res://scenes/Main.tscn").instantiate();root.add_child(game)
	for f in 4:await process_frame
	game.characters.selected="net-"+role
	game.school._identity_changed()
	game.electronics.profile.open("net-"+role)
	# The default starter kit reserves the stock this fixture trades.
	game.electronics.profile.data.kits.starter.items.clear()
	assert(game.electronics.profile.save()==OK)
	if role=="host":
		assert(game.session.host_game("Host",24919)==OK)
		game.school.start("Freeplay",0)
	else:assert(game.session.join_game("127.0.0.1","Client",24919)==OK)
	game.capture()
	var deadline=Time.get_ticks_msec()+60000
	while game.session.roster.size()<2 or (role=="host" and game.school.identities.size()<2):
		if Time.get_ticks_msec()>deadline:push_error("NETWORK TIMEOUT registration");quit(1);return
		await create_timer(.1).timeout
	while not game.electronics_trade.authority.bound or (role=="host" and game.session.roster.keys().any(func(peer):return game.electronics_trade.authority.ledger.account(peer).is_empty())):
		if Time.get_ticks_msec()>deadline:push_error("NETWORK TIMEOUT authority enrollment");quit(1);return
		await create_timer(.1).timeout
	if role=="host":
		var target=game.session.roster.keys().filter(func(p):return p!=1)[0]
		game.electronics_trade.request({"op":"invite","target":target})
	while game.electronics_trade.current.is_empty():await create_timer(.1).timeout
	var id=game.electronics_trade.current.id
	game.electronics_trade.request({"op":"offer","id":id,"items":{"r1000":2} if role=="host" else {"r220":1},"definitions":{}})
	while game.electronics_trade.current.offers.values().any(func(o):return o.is_empty()):await create_timer(.1).timeout
	game.electronics_trade.request({"op":"confirm","id":id})
	while not game.electronics.profile.data.get("applied_trades",{}).has(id):
		if Time.get_ticks_msec()>deadline:push_error("NETWORK TIMEOUT trade");quit(1);return
		await create_timer(.1).timeout
	assert(game.electronics.profile.data.inventory.r1000==(6 if role=="host" else 10))
	assert(game.electronics.profile.data.inventory.r220==(5 if role=="host" else 3))
	assert(game.electronics_trade.current.is_empty())
	print("PASS: ENet "+role+" offer/confirm/commit inventory and UI state")
	await create_timer(1).timeout
	quit()

