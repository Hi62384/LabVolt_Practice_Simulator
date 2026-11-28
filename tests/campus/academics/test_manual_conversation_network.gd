extends SceneTree
## Actual ENet RPCs exercise session ordering, request dedup and cancellation.
## The production admission queue is held; no AI provider or audio hardware runs.
const Faculty=preload("res://scripts/campus/academics/faculty.gd")
const Player=preload("res://scripts/campus/academics/teacher_speech_player.gd")
const ROOM:="elm253_lecture"
const CLASS_ID:="manual_network_class"
const ACTOR:="mr_bro"
const FIRST_NONCE:="11111111111111111111111111111111"
class Session extends Node:
	var online:=true
	var roster: Dictionary={}
	func peer_connected_now(peer: int) -> bool:return peer in multiplayer.get_peers()
class School extends Node:
	var identities: Dictionary={}
	func formal_active() -> bool:return false
class Classes extends Node:
	var classes:={ROOM:{"id":CLASS_ID,"phase":"lesson","teacher":ACTOR}}
	var public_classes:=classes.duplicate(true)
	func _inside(_peer: int,room: String) -> bool:return room==ROOM
class Provider extends Node:
	var busy:=false
class Game extends Node:
	var session:=Session.new()
	var school:=School.new()
	var lecture_classes:=Classes.new()
	var host_openai:=Provider.new()
	func _init() -> void:
		add_child(session);add_child(school);add_child(lecture_classes);add_child(host_openai)
class QueuedFaculty extends Faculty:
	func _next_question() -> void:pass
class Bus extends Node:
	var stage:=0
	var acknowledged:=0
	@rpc("authority","call_remote","reliable")
	func announce(value: int) -> void:stage=value
	@rpc("any_peer","call_remote","reliable")
	func acknowledge(value: int) -> void:
		if multiplayer.is_server():acknowledged=value
var deadline:=0
var game: Game
var faculty: QueuedFaculty
var bus: Bus

func _initialize() -> void:run.call_deferred()
func until(check: Callable,label: String) -> bool:
	while Time.get_ticks_msec()<deadline:
		if bool(check.call()):return true
		await create_timer(.01).timeout
	push_error("Manual conversation network timeout: "+label);quit(1);return false

func run() -> void:
	var args:=OS.get_cmdline_user_args()
	var host:=args[0]=="host"
	var network:=ENetMultiplayerPeer.new()
	if (network.create_server(int(args[1]),1) if host else network.create_client("127.0.0.1",int(args[1])))!=OK:quit(1);return
	root.multiplayer.multiplayer_peer=network
	bus=Bus.new();bus.name="Verification";root.add_child(bus)
	game=Game.new();game.name="Game";root.add_child(game)
	faculty=QueuedFaculty.new();faculty.name="Faculty";game.add_child(faculty);faculty.game=game;faculty.set_process(false)
	faculty.conversation=PanelContainer.new();faculty.add_child(faculty.conversation)
	faculty.conversation_text=Label.new();faculty.conversation.add_child(faculty.conversation_text)
	faculty.conversation_name=Label.new();faculty.conversation.add_child(faculty.conversation_name)
	faculty.conversation_scroll=ScrollContainer.new();faculty.conversation.add_child(faculty.conversation_scroll)
	faculty.speech_player=Player.new();faculty.add_child(faculty.speech_player)
	faculty.conversation_room=ROOM;faculty.conversation_class=CLASS_ID
	faculty.conversation.set_meta("selected_character_id",ACTOR)
	deadline=Time.get_ticks_msec()+18000
	if host:print("MANUAL_CONVERSATION_HOST_READY")
	if not await until(func():return not root.multiplayer.get_peers().is_empty(),"connection"):return
	var client:=int(root.multiplayer.get_peers()[0]) if host else root.multiplayer.get_unique_id()
	game.session.roster={1:{},client:{}};game.school.identities={1:"network_host",client:"network_guest"}
	if host:
		if not await until(func():return faculty.questions.size()==1,"first remote turn"):return
		assert(faculty.questions.size()==1 and int(faculty.manual_conversations[client].last_turn)==1,"Repeated reliable WAV uploads enter the host queue once")
		var former: Dictionary=faculty.questions[0].voice_context.duplicate(true)
		var host_nonce:="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
		assert(faculty._begin_manual_session(1,ROOM,CLASS_ID,"",ACTOR,host_nonce))
		assert(faculty._manual_question_request(1,host_nonce,1,host_nonce+":1","Host pending turn."))
		bus.announce.rpc_id(client,1)
		if not await until(func():return faculty.manual_conversations.has(client) and faculty.manual_conversations[client].token!=FIRST_NONCE and faculty.questions.size()==2,"close then reopen ordering"):return
		assert(not faculty._voice_context_valid(client,former),"Former context is invalid even when the selected NPC is unchanged")
		var fresh: Dictionary=faculty.questions.filter(func(entry):return int(entry.peer)==client)[0].voice_context
		assert(faculty._voice_context_valid(client,fresh) and faculty.questions.filter(func(entry):return int(entry.peer)==1).size()==1,"Guest reopen preserves the host's independent queued turn")
		faculty._manual_dialogue_reply.rpc_id(client,ROOM,ACTOR,"Stale remote reply",FIRST_NONCE,FIRST_NONCE+":1")
		faculty._manual_dialogue_reply.rpc_id(client,ROOM,ACTOR,"Current remote reply",fresh.token,fresh.request_id)
		faculty._manual_speech_started.rpc_id(client,FIRST_NONCE,1,"late-wire-envelope",18)
		bus.announce.rpc_id(client,2)
		if not await until(func():return bus.acknowledged==2 and not faculty.manual_conversations.has(client),"remote cancel"):return
		assert(faculty.questions.size()==1 and int(faculty.questions[0].peer)==1,"A client close removes only its own queued request across ENet")
		bus.announce.rpc_id(client,3)
		if not await until(func():return bus.acknowledged==3,"client completion"):return
		print("MANUAL_CONVERSATION_HOST PASS real ENet typed/WAV dedup, ordered close/reopen, peer isolation")
	else:
		faculty.manual_conversation_nonce=FIRST_NONCE;faculty.manual_turn_serial=1;faculty.manual_latest_request=FIRST_NONCE+":1"
		faculty._begin_manual_conversation.rpc_id(1,ROOM,CLASS_ID,"",ACTOR,FIRST_NONCE)
		var pcm:=PackedByteArray();pcm.resize(6400)
		var wav: PackedByteArray=Faculty.TeacherAI.wav_16k(pcm)
		faculty._manual_question.rpc_id(1,FIRST_NONCE,1,FIRST_NONCE+":1",wav)
		faculty._manual_question.rpc_id(1,FIRST_NONCE,1,FIRST_NONCE+":1",wav)
		if not await until(func():return bus.stage==1,"first admission"):return
		faculty._close_manual_session();faculty._open_manual_session();faculty._send_manual_question("Fresh remote typed turn.")
		faculty._end_manual_conversation.rpc_id(1,FIRST_NONCE)
		faculty._manual_question.rpc_id(1,FIRST_NONCE,2,FIRST_NONCE+":2",wav)
		if not await until(func():return bus.stage==2,"fresh reply"):return
		assert(faculty.conversation_text.text=="Current remote reply","Only the reopened session's response updates the client UI")
		assert(faculty.speech_player.was_cancelled("late-wire-envelope",18),"A stale speech registration is canceled on the client before playback")
		var anchor:=Node3D.new();game.add_child(anchor)
		assert(not faculty.speech_player.accept("late-wire-envelope","Teacher",18,"Late envelope",3,anchor),"Late canceled serial cannot be resurrected by a subsequent envelope")
		faculty._close_manual_session();bus.acknowledge.rpc_id(1,2)
		if not await until(func():return bus.stage==3,"server cancellation receipt"):return
		bus.acknowledge.rpc_id(1,3)
		for frame in 10:await process_frame
		print("MANUAL_CONVERSATION_CLIENT PASS real ENet stale UI and speech envelope rejection")
	network.close();game.queue_free();bus.queue_free();await process_frame;quit(0)
