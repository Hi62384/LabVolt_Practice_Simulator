extends SceneTree
const PORT := 26318
const SHOE := "shoes.beacon_hightop"
var game
var authority
var role: String
var deadline: int
var actor := 0
var observed := false

func _initialize() -> void:call_deferred("run")

func until(condition: Callable,label: String) -> bool:
	while Time.get_ticks_msec()<deadline:
		if condition.call():return true
		await create_timer(.07).timeout
	push_error("COSMETICS NETWORK TIMEOUT "+label)
	quit(1)
	return false

func equipped(peer: int) -> bool:
	var appearance: Dictionary=game.cosmetic_appearances.get(peer,{})
	if appearance.get("equipped",{}).get("footwear",{}).get("id","")!=SHOE:return false
	var avatar: Node=game.avatars.get(peer)
	return avatar!=null and avatar.has_node("CharacterModel/LegL/LeftFootwear") and avatar.has_node("CharacterModel/LegR/RightFootwear") and not appearance.has("dollars")

func run() -> void:
	role=OS.get_cmdline_user_args()[0]
	game=load("res://scenes/Main.tscn").instantiate()
	root.add_child(game)
	for i in 4:await process_frame
	var character_id := "cosmetics-network-"+role
	var error: String=game.characters.save_character(character_id,{"name":role})
	if not error.is_empty():push_error(error);quit(1);return
	game.characters.select_profile(character_id)
	if game.characters.selected!=character_id:push_error("FAIL character selection");quit(1);return
	authority=game.electronics_trade.authority
	deadline=Time.get_ticks_msec()+35000
	if role=="host":
		if game.session.host_game("Host",PORT)!=OK:quit(1);return
	else:
		if game.session.join_game("127.0.0.1",role,PORT)!=OK:quit(1);return
	game.session.chat_received.connect(func(_peer,_sender,message):if message=="COSMETICS_OBSERVED":observed=true)
	game.capture()
	if not await until(func():return authority.bound,"inventory enrollment"):return
	if role=="actor":
		authority.submit("avatar_cosmetic",[{"op":"equip","id":SHOE}])
		if not await until(func():return authority.pending.is_empty(),"unowned equip rejected"):return
		if game.electronics.profile.data.get("avatar_cosmetics",{}).get("equipped",{}).get("footwear",{}).get("id","")==SHOE:push_error("FAIL unowned item equipped");quit(1);return
		authority.submit("cosmetic_purchase",[{"op":"purchase","id":SHOE}])
		if not await until(func():return SHOE in game.electronics.profile.data.get("owned_cosmetics",[]),"purchase"):return
		authority.submit("avatar_cosmetic",[{"op":"equip","id":SHOE}])
		if not await until(func():return game.cosmetic_appearances.get(game.multiplayer.get_unique_id(),{}).get("equipped",{}).get("footwear",{}).get("id","")==SHOE,"own authoritative equip"):return
		print("PASS actor rejected unowned equip, purchased and equipped footwear")
		if not await until(func():return observed,"late observer saw the equipped shoes"):return
		var previous_peer: int=game.multiplayer.get_unique_id()
		game.session.leave()
		await create_timer(.8).timeout
		if game.session.join_game("127.0.0.1",role,PORT)!=OK:quit(1);return
		if not await until(func():
			var own: int=game.multiplayer.get_unique_id()
			return own!=previous_peer and authority.bound and game.cosmetic_appearances.get(own,{}).get("equipped",{}).get("footwear",{}).get("id","")==SHOE
		,"equipped shoes after reconnect"):return
		print("PASS actor kept equipped footwear after reconnect")
		await create_timer(3).timeout
	elif role=="host":
		if not await until(func():return game.session.roster.size()>=2,"actor joined"):return
		actor=game.session.roster.keys().filter(func(peer):return peer!=1)[0]
		if not await until(func():return equipped(actor),"remote equipped avatar on host"):return
		print("PASS host received and built remote equipped avatar")
		if not await until(func():return not game.session.roster.has(actor),"actor departed"):return
		if not await until(func():
			for peer in game.session.roster:
				if peer!=actor and game.session.roster[peer].name=="actor" and equipped(peer):return true
			return false
		,"returning actor mesh includes equipped shoes"):return
		print("PASS host rebuilt equipped footwear on returning avatar")
	else:
		if not await until(func():
			for peer in game.session.roster:
				if peer!=game.multiplayer.get_unique_id() and equipped(peer):return true
			return false
		,"existing equipped avatar on late join"):return
		print("PASS late observer received existing equipped avatar")
		game.session.chat("COSMETICS_OBSERVED")
	await create_timer(.5).timeout
	quit()
