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
		var B=load("res://scripts/breadboard_model.gd")
		var source=B.empty();source.parts=[{"id":"cpu","type":"lv_mcu","a":"A1","b":"A2","pins":["A1","A2","A3","A4","A5","A6"],"firmware":"mode D0 out\nwrite D0 1\nhalt"}]
		var child=B.blueprint(source,"Nested CPU")
		var outer=B.empty();outer.parts=[{"id":"module","type":"ic:net_cpu","a":"A1","b":"F1","pins":["A1","F1","A2","F2"]}]
		var pcb=B.blueprint(outer,"Programmable PCB");pcb.package="PCB";pcb.footprint={"width":8,"height":8,"color":"24775b"};pcb.layout={"rows":30,"parts":outer.parts.duplicate(true),"wires":[]}
		game.electronics.profile.data.blueprints={"ic:net_cpu":child,"ic:net_pcb":pcb};game.electronics.profile.data.inventory["ic:net_pcb"]=1;assert(game.electronics.profile.save()==OK)
		assert(game.session.host_game("Host",24923)==OK)
		game.school.start("Freeplay",0)
	else:assert(game.session.join_game("127.0.0.1","Client",24923)==OK)
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
	game.electronics_trade.request({"op":"offer","id":id,"items":{"ic:net_pcb":1} if role=="host" else {"r220":1},"definitions":game.electronics.profile.data.get("blueprints",{})})
	while game.electronics_trade.current.offers.values().any(func(o):return o.is_empty()):await create_timer(.1).timeout
	game.electronics_trade.request({"op":"confirm","id":id})
	while not game.electronics.profile.data.get("applied_trades",{}).has(id):
		if Time.get_ticks_msec()>deadline:push_error("NETWORK TIMEOUT trade");quit(1);return
		await create_timer(.1).timeout
	assert(game.electronics.profile.data.inventory.get("ic:net_pcb",0)==(0 if role=="host" else 1))
	assert(game.electronics.profile.data.blueprints["ic:net_cpu"].parts[0].firmware=="mode D0 out\nwrite D0 1\nhalt")
	assert(game.electronics.profile.data.blueprints["ic:net_pcb"].package=="PCB")
	assert(game.electronics.profile.data.inventory.r220==(5 if role=="host" else 3))
	assert(game.electronics_trade.current.is_empty())
	print("PASS: ENet "+role+" PCB trade, nested blueprint dependencies, firmware and inventory commit")
	await create_timer(1).timeout
	quit()

