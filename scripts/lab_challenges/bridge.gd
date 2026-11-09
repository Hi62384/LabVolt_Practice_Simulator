extends Node
const Host = preload("res://scripts/lab_challenges/host.gd")
const Decor = preload("res://scripts/lab_challenges/decorations.gd")
var game: Node
var host := Host.new()
var panel: CanvasLayer
var viewers := {}
var history_offsets := {}
var briefs := {}
var dirty := true
var timer := 0.0
var ledger_id := 0
var offline_cleared := false
var hooks_ready := false
var academic_suspended := false
var decor_roots := {}
var decor_hashes := {}
var sent_decor := {}
var sent_profile := {}
var last_request := {}
func build(owner_game: Node) -> void:
	game=owner_game
	host.allowed=_allowed
	host.names=func(peer):return str(game.session.roster.get(peer,{}).get("name","Student"))
	host.store.authority=func():return hooks_ready and multiplayer.is_server() and game.session.online and game.electronics_trade.authority.healthy
	hooks_ready=game.session.get_property_list().any(func(property):return property.name=="lab_challenge_observer") and game.session.get_property_list().any(func(property):return property.name=="lab_challenge_guard") and game.session.get_property_list().any(func(property):return property.name=="lab_challenge_brief")
	if hooks_ready:
		game.session.set("lab_challenge_guard",_guard);game.session.set("lab_challenge_observer",host.observe);game.session.set("lab_challenge_brief",brief)
	panel=preload("res://scripts/lab_challenges/panel.gd").new();add_child(panel);panel.build();panel.request.connect(_request);panel.closed.connect(func():game.capture())
	host.changed.connect(func():dirty=true)
	host.notice.connect(func(peer,bench,message):_send_frame(peer,bench,message))
	game.session.roster_changed.connect(func():dirty=true;sent_decor.clear();sent_profile.clear())
func open() -> void:
	game.release_mouse();game.front.screen.hide();panel.show_at(int(game._active_station()))
	if not hooks_ready:panel.update_frame({},"Core challenge hooks are unavailable.")
func _formal_class() -> bool:
	if not is_instance_valid(game.school):return false
	if game.school.has_method("formal_active"):return bool(game.school.call("formal_active"))
	# Compatibility only for older hosts without the authoritative School helper.
	if game.school.get("mode")=="Class" and game.school.get("phase") in ["travel","lesson","assignment"]:return true
	return game.school.get("activity") is Dictionary and game.school.activity.get("mode","")=="Course" and game.school.phase not in ["complete","freeplay"]
func _guard(peer: int,bench: int,action: Dictionary) -> String:
	if _formal_class() or game.school.mode=="Creative Freeplay" or host.needs_resume.get(bench,false):return ""
	return host.guard(peer,bench,action)
func _allowed(peer: int,bench: int,command: String) -> bool:
	if not game.session.roster.has(peer) or bench<0 or bench>=game.session.labs.size():return false
	if command=="view":return true
	if _formal_class():return false
	if game.school.mode=="Creative Freeplay" and command in ["start","resume","submit","diagnose","observe"]:return false
	var position: Vector3=game.player.position if peer==1 else game.session.poses.get(peer,{}).get("position",Vector3(9999,0,0))
	if position.distance_to(Vector3(game._station_x(bench),0,-2))>4.25:return false
	if game.session.academic_equipment_guard.is_valid() and not game.session.academic_equipment_guard.call(peer,bench,{"op":"team_challenge","command":command}):return false
	return true
func _process(delta: float) -> void:
	if not is_instance_valid(game):return
	timer+=delta
	if timer<.2:return
	timer=0
	if not game.session.online:
		if not offline_cleared:_clear_session_views()
		return
	offline_cleared=false
	if not multiplayer.is_server():return
	for mapping in [viewers,history_offsets,last_request,sent_profile,sent_decor]:
		for peer in mapping.keys():
			if not game.session.roster.has(peer):mapping.erase(peer)
	for peer in viewers.keys():
		if not game.session.roster.has(peer):viewers.erase(peer);history_offsets.erase(peer);last_request.erase(peer);sent_profile.erase(peer);sent_decor.erase(peer)
	var authority: Node=game.electronics_trade.authority
	if not authority.healthy or not game.session.online:return
	host.store.ledger=authority.ledger;host.labs=game.session.labs
	if ledger_id!=authority.ledger.get_instance_id():ledger_id=authority.ledger.get_instance_id();host.recover_journal();dirty=true;sent_profile.clear();sent_decor.clear()
	var formal: bool=_formal_class() or game.school.mode=="Creative Freeplay"
	if formal and not academic_suspended:host.recover_journal();dirty=true
	academic_suspended=formal
	if dirty:
		dirty=false
		_refresh_briefs()
		for peer in viewers.keys():
			if not game.session.roster.has(peer):viewers.erase(peer);continue
			_send_frame(int(peer),int(viewers[peer]),"")
	var root := host.store.root()
	if root.is_empty():return
	var decorations: Dictionary=root.decorations
	var digest := var_to_bytes(decorations).hex_encode().sha256_text()
	for peer in authority.ledger.bindings:
		if not game.session.roster.has(peer):continue
		if sent_decor.get(peer,"")!=digest:
			var frame := {}
			for bench in decorations:
				frame[bench]={}
				for anchor in decorations[bench]:frame[bench][anchor]={"id":decorations[bench][anchor].id}
			if peer==1:_apply_decor(frame)
			else:_decoration_frame.rpc_id(int(peer),frame)
			sent_decor[peer]=digest
		var account: Dictionary=authority.ledger.account(peer)
		if not account.is_empty() and sent_profile.get(peer,-1)!=account.revision:
			authority.send_snapshot(peer,authority.ledger.snapshot(peer));sent_profile[peer]=account.revision
func _request(bench: int,action: Dictionary) -> void:
	if multiplayer.is_server():_accept(1,bench,action)
	elif game.session.online:_challenge_request.rpc_id(1,bench,action)
@rpc("any_peer","call_remote","reliable",8)
func _challenge_request(bench: int,action: Dictionary) -> void:
	if multiplayer.is_server():_accept(multiplayer.get_remote_sender_id(),bench,action)
func _accept(peer: int,bench: int,action: Dictionary) -> void:
	if not hooks_ready or bench<0 or bench>=3 or var_to_bytes(action).size()>2048:return
	if not game.session.roster.has(peer):return
	var time := Time.get_ticks_msec()
	if time-int(last_request.get(peer,-1000))<150:return
	last_request[peer]=time
	if action.get("command")=="view":
		if not action.get("history_offset",0) is int or int(action.get("history_offset",0))<0 or int(action.get("history_offset",0))>199:return
		viewers[peer]=bench;history_offsets[peer]=int(action.get("history_offset",0))
	if not host.available(peer,bench,"view"):_send_frame(peer,bench,"Connect to the host's inventory and gather at this AC bench outside a formal class.");return
	viewers[peer]=bench
	if action.get("command")=="view":_send_frame(peer,bench,"");return
	var response: Dictionary=host.act(peer,bench,action)
	_send_frame(peer,bench,str(response.get("message",response.get("error","Challenge updated."))))
	if response.ok:_refresh_briefs();game.session.broadcast()
func _send_frame(peer: int,bench: int,message: String) -> void:
	var frame := host.view(peer,bench,int(history_offsets.get(peer,0)))
	if peer==1:panel.update_frame(frame,message)
	elif game.session.peer_connected_now(peer):_challenge_frame.rpc_id(peer,frame,message)
@rpc("authority","call_remote","reliable",8)
func _challenge_frame(frame: Dictionary,message: String) -> void:
	if multiplayer.get_remote_sender_id()==1:panel.update_frame(frame,message)
@rpc("authority","call_remote","reliable",8)
func _decoration_frame(frame: Dictionary) -> void:
	if multiplayer.get_remote_sender_id()==1:_apply_decor(frame)
func _apply_decor(frame: Dictionary) -> void:
	if frame.size()>3:return
	for bench in 3:
		var choices: Variant=frame.get(str(bench),{})
		if not choices is Dictionary or choices.size()>2:continue
		var safe := {}
		for anchor in choices:
			if anchor in Decor.ANCHORS and choices[anchor] is Dictionary and choices[anchor].get("id") in Decor.DEFINITIONS:safe[anchor]={"id":choices[anchor].id}
		var digest := var_to_bytes(safe).hex_encode().sha256_text()
		if decor_hashes.get(bench,"")==digest:continue
		if is_instance_valid(decor_roots.get(bench)):decor_roots[bench].queue_free()
		decor_roots[bench]=Decor.render(game,bench,safe);decor_hashes[bench]=digest

func brief(bench: int) -> Dictionary:
	if not is_instance_valid(game) or not game.session.online or not host.store.available() or _formal_class() or game.school.mode=="Creative Freeplay" or host.needs_resume.get(bench,false):return {}
	return briefs.get(bench,{}).duplicate(true)
func _clear_session_views() -> void:
	for model in decor_roots.values():
		if is_instance_valid(model):model.queue_free()
	decor_roots.clear();decor_hashes.clear();briefs.clear();viewers.clear();history_offsets.clear();last_request.clear();sent_profile.clear();sent_decor.clear();ledger_id=0;offline_cleared=true
	panel.update_frame({},"Reconnect to the host to restore the saved team journal.")
func _refresh_briefs() -> void:
	briefs.clear()
	if _formal_class() or game.school.mode=="Creative Freeplay":return
	var root := host.store.root()
	for key in root.get("active",{}):
		if host.needs_resume.get(int(key),false):continue
		var attempt: Dictionary=root.active[key]
		var catalog := preload("res://scripts/lab_challenges/scenario_catalog.gd")
		var plan: Dictionary=catalog.generate(attempt.kind,int(attempt.seed))
		briefs[int(key)]={"title":str(attempt.kind).replace("_"," ").capitalize(),"objective":catalog.brief(plan)}
