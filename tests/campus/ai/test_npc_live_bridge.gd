extends SceneTree
const Client=preload("res://scripts/campus/ai/host_openai_client.gd")
const Bridge=preload("res://scripts/campus/voice/npc_live_conversation.gd")
const Characters=preload("res://scripts/campus/academics/class_character_profile.gd")
const RESPONSE:="Voltage is the difference in electric potential."
var failures: Array[String]=[]

class SessionStub extends Node:
	signal roster_changed
	signal leaving
	signal restarted
	var roster: Dictionary={1:{}}
	var online:=false
	func peer_connected_now(peer: int) -> bool:return roster.has(peer)

class GameStub extends Node:
	var session:=SessionStub.new()
	var host_openai: Node

class RouterStub extends Node:
	var permitted:=true
	var tokens: Dictionary={}
	var errors: Array=[]
	func _permitted() -> bool:return permitted
	func is_current(peer: int,token: String) -> bool:return tokens.get(peer,"")==token
	func _error(message: String) -> void:errors.append(message)
	func begin_remote(token: String,target: Dictionary) -> void:
		tokens[multiplayer.get_unique_id()]=token
		_begin.rpc_id(1,token,target)
	@rpc("any_peer","call_remote","reliable",10)
	func _begin(token: String,_target: Dictionary) -> void:
		if multiplayer.is_server():tokens[multiplayer.get_remote_sender_id()]=token

class FacultyStub extends Node:
	var allowed:=true
	var ai_busy: Dictionary={}
	var question_channels: Dictionary={}
	var character_epoch:=0
	var profile_loaded:=false
	var delay:=0.03
	var received: Array=[]
	var played: Array=[]
	func _sync_character_profile() -> bool:
		if profile_loaded:return true
		if not ai_busy.is_empty():return false
		profile_loaded=true;character_epoch+=1;return true
	func voice_target_valid(_peer: int,target: Dictionary) -> bool:return allowed and target.get("id") in ["mr_bro","bill_nye"]
	func resume_voice_target(_target: Dictionary) -> void:pass
	func answer_live_delegation(peer: int,target: Dictionary,transcript: String,guard: Callable) -> Dictionary:
		if not _sync_character_profile():return {"ok":false,"error":"Profile cannot load during a reservation"}
		received.append({"peer":peer,"target":target,"transcript":transcript})
		await get_tree().create_timer(delay).timeout
		if not guard.call():return {"ok":false,"error":"stale"}
		return {"ok":true,"text":RESPONSE,"delivery":Characters.speech(Characters.teacher(str(target.id)),"gpt-live-1.1",3,"happy"),"presentation":{"authority":"fixture"}}
	func present_live_voice(peer: int,target: Dictionary,text: String,stream: AudioStreamWAV,guard: Callable,delivery: Dictionary,presentation: Dictionary={}) -> void:
		if guard.call():played.append({"peer":peer,"target":target,"text":text,"stream":stream,"delivery":delivery,"presentation":presentation})

func check(value: bool,message: String) -> void:
	if not value:failures.append(message);push_error(message)

func until(condition: Callable,seconds: float=8.) -> bool:
	var deadline:=Time.get_ticks_msec()+int(seconds*1000)
	while Time.get_ticks_msec()<deadline:
		if condition.call():return true
		await process_frame
	return false

func _initialize() -> void:call_deferred("run")

func harness(label: String,api: SceneMultiplayer=null) -> Dictionary:
	var game:=GameStub.new();game.name=label;root.add_child(game)
	if api!=null:set_multiplayer(api,game.get_path())
	game.add_child(game.session)
	var provider:=Client.new();provider._environment_key_disconnected=true;game.add_child(provider);game.host_openai=provider
	var router:=RouterStub.new();router.name="NaturalVoice";game.add_child(router)
	var faculty:=FacultyStub.new();game.add_child(faculty)
	var bridge:=Bridge.new();bridge.name="LiveConversation";router.add_child(bridge);bridge.build(game,faculty,router)
	return {"game":game,"client":provider,"router":router,"faculty":faculty,"bridge":bridge}

func configure_host(provider: Node) -> void:
	provider.set_session_key("sk-fixture-12345678901234567890")
	provider.configure("gpt-5.4-mini",64,"",true);provider.live_enabled=true
	var port:=OS.get_environment("LABVOLT_VOICE_FIXTURE_PORT")
	provider.set_local_test_voice_endpoint("ws://127.0.0.1:"+port+"/v1")

func run() -> void:
	create_timer(35).timeout.connect(func():push_error("NPC_LIVE_BRIDGE timeout");quit(1))
	var target:={"id":"mr_bro","name":"Mr Bro","room":"ac_lab","class_id":"fixture_class","student":""}
	var pcm:=PackedByteArray();pcm.resize(640)
	var local:=harness("Singleplayer");configure_host(local.client)
	local.router.tokens[1]="local_turn"
	for _i in 5:local.bridge.feed_packet(pcm)
	check(local.bridge.begin_turn("local_turn",target),"Live consumes the selected turn")
	for _i in 8:local.bridge.feed_packet(pcm)
	local.faculty.ai_busy[99]="ac_lab";local.faculty.question_channels[99]="mr_bro"
	local.bridge.finish_turn("local_turn")
	await create_timer(.8).timeout
	check(local.faculty.received.is_empty(),"Live waits for an existing typed/manual turn on the same actor")
	local.faculty.ai_busy.clear();local.faculty.question_channels.clear()
	check(await until(func():return local.faculty.played.size()==1),"singleplayer reaches verified PCM presentation")
	check(local.faculty.ai_busy.is_empty() and local.faculty.question_channels.is_empty(),"authoritative reservation is released after Live generation")
	check(local.faculty.profile_loaded,"authoritative profile loads before the first Live turn reserves ai_busy")
	if not local.faculty.played.is_empty():
		var result: Dictionary=local.faculty.played[0]
		check(result.stream is AudioStreamWAV and result.stream.mix_rate==16000 and result.text==RESPONSE,"Live uses documented 16k PCM and exact authoritative text")
	check(local.faculty.received.size()==1 and local.faculty.received[0].transcript=="What is voltage?","duplicate delegation reaches authority once with the actual accumulated transcript")
	var existing: Node=local.bridge.sessions[1].node
	local.router.tokens[1]="reuse_turn"
	local.bridge.begin_turn("reuse_turn",target)
	check(local.bridge.sessions[1].node==existing,"same-player same-character conversation reuses one session")
	local.router.permitted=false
	var accepted: int=local.bridge.sessions[1].input_bytes
	for _i in 12:local.bridge.feed_packet(pcm)
	check(local.bridge.sessions[1].input_bytes==accepted,"permission loss never forwards raw microphone PCM")
	local.bridge.cancel_local("reuse_turn")
	check(local.bridge.sessions.is_empty(),"mute or explicit cancellation releases the active conversation")
	local.game.queue_free();await process_frame

	# Two actual ENet peers share the loopback provider fixture. Only the host has
	# an API key. NaturalVoice begin and Live begin travel on the same channel.
	var server_api:=SceneMultiplayer.new();var client_api:=SceneMultiplayer.new()
	var server_peer:=ENetMultiplayerPeer.new();var remote_peer:=ENetMultiplayerPeer.new()
	var port:=int(OS.get_environment("LABVOLT_LIVE_NETWORK_PORT"))
	check(server_peer.create_server(port,2,16)==OK,"ENet host starts")
	server_api.multiplayer_peer=server_peer
	var host:=harness("Host",server_api);configure_host(host.client)
	check(remote_peer.create_client("127.0.0.1",port,16)==OK,"ENet client starts")
	client_api.multiplayer_peer=remote_peer
	var remote:=harness("Remote",client_api)
	check(await until(func():return remote_peer.get_connection_status()==MultiplayerPeer.CONNECTION_CONNECTED),"ENet client connects")
	var peer:=client_api.get_unique_id()
	check(await until(func():return peer in server_api.get_peers()),"host completes the peer handshake")
	host.game.session.roster[peer]={};remote.game.session.roster[peer]={}
	host.game.session.online=true;remote.game.session.online=true
	host.bridge._publish_offer(true)
	check(await until(func():return remote.bridge.enabled()),"host opt-in is offered to the remote player")
	check(not remote.client.configured(),"remote player never receives provider credentials")
	remote.router.begin_remote("network_turn",target)
	check(remote.bridge.begin_turn("network_turn",target),"remote chooses Live without local STT")
	for _i in 8:remote.bridge.feed_packet(pcm)
	remote.bridge.finish_turn("network_turn")
	check(await until(func():return host.faculty.played.size()==1),"actual RPC microphone packets reach host Live and guarded presentation")
	check(host.faculty.received.size()==1 and int(host.faculty.received[0].peer)==peer,"delegation uses authenticated network sender")
	check(remote.faculty.received.is_empty() and remote.faculty.played.is_empty(),"remote cannot independently reason or publish provider audio")
	remote.bridge.cancel_local("network_turn")
	check(await until(func():return host.bridge.sessions.is_empty()),"network cancellation closes the host-owned session")

	host.faculty.delay=.4
	target.id="bill_nye"
	remote.router.begin_remote("stale_turn",target);remote.bridge.begin_turn("stale_turn",target)
	for _i in 8:remote.bridge.feed_packet(pcm)
	remote.bridge.finish_turn("stale_turn")
	check(await until(func():return host.faculty.received.size()==2),"new target reaches authoritative work")
	host.faculty.character_epoch+=1
	host.faculty.ai_busy[peer]="new_session";host.faculty.question_channels[peer]="new_actor"
	remote.bridge.cancel_local("stale_turn")
	await create_timer(.7).timeout
	check(host.faculty.played.size()==1,"canceled backend completion cannot produce a late voice")
	check(host.faculty.ai_busy.get(peer)=="new_session" and host.faculty.question_channels.get(peer)=="new_actor","an old Live callback cannot erase a new session's reservation")
	host.game.session.online=false;remote.game.session.online=false
	host.bridge.clear_session();remote.bridge.clear_session()
	server_peer.close();remote_peer.close()
	host.game.queue_free();remote.game.queue_free();await process_frame
	print("NPC_LIVE_BRIDGE ","PASS" if failures.is_empty() else "FAIL "+str(failures.size()))
	quit(0 if failures.is_empty() else 1)
