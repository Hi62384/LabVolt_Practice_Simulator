extends Node
signal changed
var game: Node
var calls:={}
var local_call:={}
var messages: Array=[]
var ring: AudioStreamPlayer
var last_message:={}
var prune_clock:=0.0

func build(owner: Node) -> void:
	game=owner
	ring=AudioStreamPlayer.new();ring.volume_db=-4;ring.stream=_ringtone();add_child(ring)
	game.session.roster_changed.connect(_prune)
	game.session.leaving.connect(_reset)

func _ringtone() -> AudioStreamWAV:
	var stream:=AudioStreamWAV.new();stream.format=AudioStreamWAV.FORMAT_16_BITS;stream.mix_rate=16000
	var data:=PackedByteArray();data.resize(32000)
	for i in 16000:
		var envelope: float=1.0 if i<5600 else 0.0
		data.encode_s16(i*2,roundi(sin(TAU*440.0*i/16000.0)*envelope*11000.0))
	stream.data=data;stream.loop_mode=AudioStreamWAV.LOOP_FORWARD;stream.loop_begin=0;stream.loop_end=16000
	return stream

func _owns_phone(peer: int) -> bool:
	var identity: String=game.dorm_interactions.authenticated_identity(peer)
	if identity.is_empty():return false
	var profile: Dictionary=game.dorm_interactions._profile(identity)
	var dorm: Dictionary=profile.get("dorm",{}).duplicate(true)
	var held: String=str(dorm.get("teacher_phone_custody",{}).get("id",""))
	if not held.is_empty():
		dorm.get("smartphones",{}).erase(held)
		dorm.get("carry_items",[]).erase("phone:"+held)
	return preload("res://scripts/campus/phones/phone_inventory.gd").carried(dorm)

func request(op: String,target: int=0,text: String="") -> void:
	if not game.session.online:return
	if multiplayer.is_server():_apply(multiplayer.get_unique_id(),op,target,text)
	else:_request.rpc_id(1,op,target,text)

func end_local_call() -> void:
	if local_call.is_empty():return
	_call_state({})
	request("end")

@rpc("any_peer","call_remote","reliable",7)
func _request(op: String,target: int,text: String) -> void:
	if multiplayer.is_server():_apply(multiplayer.get_remote_sender_id(),op,target,text)

func _apply(peer: int,op: String,target: int,text: String) -> void:
	if not game.session.roster.has(peer):return
	if op=="end":
		_end(peer);return
	if not _owns_phone(peer):return
	if op=="answer":
		var incoming: Dictionary=calls.get(peer,{})
		if incoming.get("state","")!="incoming":return
		var caller: int=incoming.peer
		if not calls.has(caller) or not _owns_phone(caller):_end(peer);return
		calls[peer].state="active";calls[caller].state="active";_send_call(peer);_send_call(caller);return
	if target==peer or not game.session.roster.has(target) or not _owns_phone(target):return
	if op=="message":
		var value:=text.strip_edges().replace("\n"," ").left(240)
		if value.is_empty() or Time.get_ticks_msec()-int(last_message.get(peer,-1000))<250:return
		last_message[peer]=Time.get_ticks_msec()
		_deliver_message(peer,peer,target,value);_deliver_message(target,peer,target,value)
	elif op=="call":
		if calls.has(peer) or calls.has(target):return
		calls[peer]={"peer":target,"state":"outgoing"};calls[target]={"peer":peer,"state":"incoming"};_send_call(peer);_send_call(target)

func _end(peer: int) -> void:
	if not calls.has(peer):return
	var other: int=calls[peer].peer
	calls.erase(peer);calls.erase(other);_send_call(peer);_send_call(other)

func _send_call(peer: int) -> void:
	var value: Dictionary=calls.get(peer,{})
	if peer==multiplayer.get_unique_id():_call_state(value)
	elif peer in multiplayer.get_peers():_receive_call.rpc_id(peer,value)

@rpc("authority","call_remote","reliable",7)
func _receive_call(value: Dictionary) -> void:
	if multiplayer.get_remote_sender_id()==1:_call_state(value)

func _call_state(value: Dictionary) -> void:
	local_call=value.duplicate(true)
	if local_call.get("state","")=="incoming":ring.play()
	else:ring.stop()
	changed.emit()

func _deliver_message(recipient: int,from_peer: int,to_peer: int,value: String) -> void:
	if recipient==multiplayer.get_unique_id():_message(from_peer,to_peer,value)
	elif recipient in multiplayer.get_peers():_receive_message.rpc_id(recipient,from_peer,to_peer,value)

@rpc("authority","call_remote","reliable",7)
func _receive_message(from_peer: int,to_peer: int,value: String) -> void:
	if multiplayer.get_remote_sender_id()==1:_message(from_peer,to_peer,value)

func _message(from_peer: int,to_peer: int,value: String) -> void:
	messages.append({"from":from_peer,"to":to_peer,"text":value.left(240)})
	while messages.size()>100:messages.pop_front()
	changed.emit()

func connected(a: int,b: int) -> bool:
	return calls.get(a,{}).get("state","")=="active" and int(calls.get(a,{}).get("peer",0))==b

func _process(delta: float) -> void:
	if local_call.get("state","") in ["active","incoming","outgoing"] and not preload("res://scripts/campus/phones/phone_inventory.gd").carried(game.electronics.profile.data.get("dorm",{})):
		end_local_call()
	if calls.is_empty() or not multiplayer.is_server():return
	prune_clock+=delta
	if prune_clock>=.1:prune_clock=0;_prune()

func _prune() -> void:
	if not multiplayer.is_server():return
	for peer in calls.keys():
		if not game.session.roster.has(peer) or not _owns_phone(int(peer)):_end(int(peer))

func _reset() -> void:
	calls.clear();local_call.clear();last_message.clear();messages.clear();ring.stop();changed.emit()
