extends Node
## Runtime owner only: --headless --path <isolated project> res://tests/campus/computers/network_fixture.tscn -- --host
## Start host then two clients with --client. Uses actual ENet/RPC; fixture seats are
## deterministic authority doubles, not a claim that campus navigation was tested.
const Manager = preload("res://scripts/campus/computers/computer_sessions.gd")
class Capture extends Manager:
	var received := {}
	func _receive(packet: Dictionary) -> void:
		received=packet.duplicate(true)
class SessionDouble extends Node:
	signal roster_changed
	signal leaving
	var roster := {1:{}}
	var poses := {}
	var online := true
class SchoolDouble extends Node:
	var local_identity := "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
	var papers := {}
	var activity := {}
	var phase := "freeplay"
	var submissions := 0
	func _public_project(project: Dictionary, _marked: bool=false) -> Dictionary:
		var copy := project.duplicate(true)
		copy.erase("answer_key")
		return copy
	func apply(peer: int, action: Dictionary) -> void:
		var paper: Dictionary=papers.get(action.id,{})
		if paper.get("owner",0)!=peer or not paper.mark.is_empty():return
		if action.op=="submit":
			submissions+=1
			paper.mark={"score":1}
		elif action.op=="answer":paper.answers[str(action.key)]=action.value
class ChairDouble extends Node:
	var occupant := 0
class GameDouble extends Node:
	var session: Node
	var school: Node
	var chairs: Array = []
	func _claim_chair(peer: int,index: int) -> void:
		if chairs[index].occupant==0:chairs[index].occupant=peer
	func _release_chair(peer: int) -> void:
		for chair in chairs:
			if chair.occupant==peer:chair.occupant=0
	func _send_chairs() -> void:pass
var manager: Capture
var game: GameDouble
var next_slot := 0
func _ready() -> void:
	call_deferred("start")
func start() -> void:
	game=GameDouble.new()
	game.name="FixtureGame"
	add_child(game)
	game.session=SessionDouble.new()
	game.school=SchoolDouble.new()
	game.add_child(game.session)
	game.add_child(game.school)
	for i in range(2):
		var chair := ChairDouble.new()
		game.add_child(chair)
		game.chairs.append(chair)
	manager=Capture.new()
	manager.name="ComputerSessions"
	game.add_child(manager)
	manager.build(game)
	manager.register_station("a",0,Vector3.ZERO)
	manager.register_station("b",1,Vector3.ZERO)
	var peer := ENetMultiplayerPeer.new()
	var host := OS.get_cmdline_user_args().has("--host")
	var error: Error=peer.create_server(24973,2) if host else peer.create_client("127.0.0.1",24973)
	assert(error==OK)
	multiplayer.multiplayer_peer=peer
	if host:
		multiplayer.peer_connected.connect(connected)
		multiplayer.peer_disconnected.connect(disconnected)
		await get_tree().create_timer(25).timeout
		print("NETWORK_FIXTURE_HOST_DONE")
		get_tree().quit()
	else:
		await get_tree().create_timer(20).timeout
		push_error("Fixture assignment timed out")
		get_tree().quit(1)
func connected(id: int) -> void:
	game.session.roster[id]={}
	game.session.poses[id]={"position":Vector3.ZERO}
	next_slot+=1
	assign.rpc_id(id,next_slot)
@rpc("authority","call_remote","reliable")
func assign(slot: int) -> void:
	var station := "a" if slot==1 else "b"
	manager.request({"op":"enter","station":station})
	await get_tree().create_timer(.3).timeout
	assert(manager.received.get("station","")==station)
	var packet := manager.received.duplicate(true)
	manager.request({"op":"restore","lease":packet.lease,"revision":packet.revision,"files":{}})
	await get_tree().create_timer(.2).timeout
	packet=manager.received.duplicate(true)
	manager.request({"op":"save","lease":packet.lease,"revision":packet.revision,"path":"work.txt","text":station,"version":0})
	await get_tree().create_timer(.2).timeout
	packet=manager.received.duplicate(true)
	assert(packet.files.size()==1 and packet.files["work.txt"].text==station)
	# Stale revision cannot replace acknowledged data.
	manager.request({"op":"save","lease":packet.lease,"revision":0,"path":"work.txt","text":"bad","version":1})
	await get_tree().create_timer(.15).timeout
	assert(manager.received.files["work.txt"].text==station)
	# Foreign owner metadata must reject the request entirely.
	manager.request({"op":"save","lease":packet.lease,"revision":packet.revision,"owner":1,"path":"work.txt","text":"bad","version":1})
	await get_tree().create_timer(.15).timeout
	assert(manager.received.files["work.txt"].text==station)
	manager.request({"op":"exit","lease":packet.lease,"revision":packet.revision})
	await get_tree().create_timer(.2).timeout
	assert(manager.received.is_empty())
	print("NETWORK_FIXTURE_CLIENT_PASS ",slot)
	get_tree().quit()


func disconnected(id: int) -> void:
	game.session.roster.erase(id)
	game.session.roster_changed.emit()
	assert(not manager.sessions.has(id) and not manager.workspaces.has(id))
	print("NETWORK_FIXTURE_DISCONNECT_PRUNED ",id)

