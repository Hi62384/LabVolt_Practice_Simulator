extends SceneTree
var game: Node
var deadline: int
const ID: String="dddddddddddddddddddddddddddddddd"
const Economy=preload("res://scripts/economy/temporary_playtest/policy.gd")
func _initialize() -> void:call_deferred("run")
func until(condition: Callable,label: String) -> bool:
	while Time.get_ticks_msec()<deadline:
		if condition.call():return true
		await create_timer(.05).timeout
	push_error("LAPTOP LOST REPLY TIMEOUT: "+label);quit(1);return false
func fail(message: String) -> void:push_error(message);quit(1)
func run() -> void:
	var args:=OS.get_cmdline_user_args()
	if args.size()!=2 or args[0] not in ["host","client"]:fail("Invalid arguments");return
	var role:=str(args[0]);var port:=int(args[1])
	game=load("res://scenes/Main.tscn").instantiate();root.add_child(game)
	for i in 4:await process_frame
	var profile=game.electronics.profile
	profile.open("laptop-lost-reply-"+role)
	game.school.local_identity=profile.data.dorm.owner
	if role=="client":profile.data.dollars=10000
	deadline=Time.get_ticks_msec()+70000
	if role=="host":
		if game.session.host_game("Host",port)!=OK:fail("Host failed");return
		print("LAPTOP_LOST_REPLY_HOST_READY")
		if not await until(func():return game.electronics_trade.authority.ledger.bindings.size()==2,"client bound"):return
		var ledger=game.electronics_trade.authority.ledger
		var peer:=0
		for candidate in ledger.bindings:
			if candidate!=1:peer=int(candidate)
		if peer==0:fail("Client peer missing");return
		var identity: String=ledger.bindings[peer]
		if not await until(func():return game.session.roster.size()==1,"client left"):return
		# Simulate an in-flight request finishing after its client disconnected.
		ledger.bindings[peer]=identity
		var result: Dictionary=ledger.transact(peer,"simulated-lost-reply","buy_portable_laptop",["standard",6,ID])
		ledger.bindings.erase(peer)
		if not result.get("ok",false):fail("Host purchase failed: "+str(result));return
		if not await until(func():return game.session.roster.size()==2 and ledger.bindings.values().has(identity),"client rebound"):return
		var account: Dictionary=ledger.state.accounts[identity]
		if account.profile.dorm.portable_laptops.size()!=1 or int(account.profile.dollars)!=int(Economy.purchase_debit(10000,1500,true).next_balance):fail("Host reconciliation duplicated purchase");return
		if not await until(func():return game.session.roster.size()==1,"client completed"):return
		print("LAPTOP_LOST_REPLY_HOST PASS")
	else:
		if game.session.join_game("127.0.0.1","Student",port)!=OK:fail("Join failed");return
		if not await until(func():return game.electronics_trade.authority.bound,"bound"):return
		var authority=game.electronics_trade.authority
		var before: Dictionary=profile.data.duplicate(true)
		profile.data.laptop_purchase_pending={ID:{"tier":"standard","host":authority.bound_host}}
		var callback: Callable=profile.authority_submit;profile.authority_submit=Callable()
		if profile.save()!=OK:fail("Pending marker save failed");return
		profile.authority_submit=callback
		if profile.data.dorm.get("portable_laptops",{}).has(ID) or int(profile.data.dollars)!=int(before.dollars):fail("Unexpected purchase reply received");return
		game.session.leave();await create_timer(3.0).timeout
		if game.session.join_game("127.0.0.1","Student",port)!=OK:fail("Reconnect failed");return
		if not await until(func():return authority.bound and profile.data.dorm.get("portable_laptops",{}).has(ID),"purchase recovered"):return
		if profile.data.dorm.portable_laptops.size()!=1 or int(profile.data.dollars)!=int(Economy.purchase_debit(10000,1500,true).next_balance) or not profile.data.get("laptop_purchase_pending",{}).is_empty():fail("Purchase recovery duplicated or lost inventory");return
		print("LAPTOP_LOST_REPLY_CLIENT PASS")
	await create_timer(.5).timeout
	game.session.leave();game.queue_free();await process_frame;quit()
