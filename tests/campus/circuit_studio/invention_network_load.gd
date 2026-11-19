extends SceneTree
## Max-player ENet exercise in one process. Every peer uses the production
## invention RPCs, while the fixture omits campus meshes and player cameras.
const World=preload("res://scripts/campus/facilities/circuit_studio/invention_world.gd")
const Model=preload("res://scripts/campus/facilities/circuit_studio/assembly_model.gd")
const Session=preload("res://scripts/session.gd")
const Board=preload("res://scripts/breadboard_model.gd")
const PCBRun=preload("res://scripts/campus/facilities/circuit_studio/assembly_pcb_runtime.gd")

class TestSession extends Node:
	var online := true
	var roster := {}
	var poses := {}
	signal restarted
	signal roster_changed
	func connected_peers() -> Array:
		return Array(multiplayer.get_peers())

class TestGame extends Node3D:
	var session := TestSession.new()
	var player := Node3D.new()

var peers: Array[SceneMultiplayer]=[]
var peers_world: Array[Node3D]=[]

func _initialize() -> void:
	call_deferred("_run")

func _connect(transport: ENetMultiplayerPeer) -> Node3D:
	var game := TestGame.new()
	root.add_child(game)
	var api := SceneMultiplayer.new()
	set_multiplayer(api,game.get_path())
	api.multiplayer_peer=transport
	peers.append(api)
	game.add_child(game.session)
	game.add_child(game.player)
	var world := World.new()
	world.name="InventionWorld"
	game.add_child(world)
	world.build(game)
	world.set_process(false)
	world.set_physics_process(false)
	peers_world.append(world)
	return world

func _wait(condition: Callable) -> bool:
	var deadline := Time.get_ticks_msec()+6000
	while Time.get_ticks_msec()<deadline:
		for api in peers:api.poll()
		if condition.call():return true
		await create_timer(.005).timeout
	return false

func _peer_ids() -> Array:
	var ids: Array=[]
	for api in peers:ids.append(api.get_unique_id())
	return ids

func _run() -> void:
	multiplayer_poll=false
	var server:=ENetMultiplayerPeer.new()
	var port:=29766
	assert(server.create_server(port,Session.MAX_PLAYERS-1)==OK)
	var host:=_connect(server)
	for slot in range(1,Session.MAX_PLAYERS):
		var client:=ENetMultiplayerPeer.new()
		assert(client.create_client("127.0.0.1",port)==OK)
		_connect(client)
	assert(await _wait(func():return host.game.session.connected_peers().size()==Session.MAX_PLAYERS-1),"ENet peers did not connect")
	var ids:=_peer_ids()
	for id in ids:
		host.game.session.roster[id]={"name":"Player %d"%id}
		host.game.session.poses[id]={"position":Vector3.ZERO}

	# Flatten a legal nested blueprint with 63 visible parts, close to the
	# 64-part physical cap, so the complete world exceeds one RPC packet.
	var nested := Model.empty("Nested parts")
	var design := Model.empty("Large assembly")
	nested.parts=[]
	design.parts=[]
	for i in 32:
		var x:=i%13-6
		var y:=floori(float(i)/13)
		nested.parts.append({"type":"wood_frame","x":x,"y":y,"z":-2,"control":"","ref":""})
		if i<31:design.parts.append({"type":"wood_frame","x":x,"y":y,"z":-1,"control":"","ref":""})
	design.parts.append({"type":"nested","x":0,"y":0,"z":2,"ref":"nested"})
	var parts:=Model.flattened("assembly",{"assembly":design,"nested":nested},{})
	assert(parts.size()==63)
	for slot in World.MAX_PLACEMENTS:
		var owner: int=ids[slot%ids.size()]
		var key: String=host._key(owner,"assembly",slot)
		host.placed[key]={
			"owner":owner,"id":"assembly","name":"Large assembly","parts":parts,
			"controls":{"A":"toggle","B":"toggle"},
			"state":{"A":false,"B":false},"effective":{"A":false,"B":false},
			"drive":{"A":"pcb" if slot<8 else "manual","B":"manual"},
			"pcb_voltage":{"A":0.0,"B":0.0},"pcb_error":"",
			"holder":{"A":0,"B":0},"expiry":{"A":0,"B":0},
			"features":{"battery":false,"switch_a":true},"position":Vector3.ZERO,
			"yaw":0.0,"angle":0.0,"hinge_angles":{}
		}
		if slot<8:host.simulators[key]={"runtime":_pcb(),"clock":0.0}

	var size:=var_to_bytes(host.placed).size()
	assert(size>131072,"Snapshot fixture must exceed the old packet cap")
	server.host.pop_statistic(ENetConnection.HOST_TOTAL_SENT_DATA)
	var started:=Time.get_ticks_usec()
	host._sync()
	assert(await _wait(func():return _matches(host.placed)),"Maximum world did not reach all clients")
	var sync_ms: float=(Time.get_ticks_usec()-started)/1000.0
	var structural_bytes:=int(server.host.pop_statistic(ENetConnection.HOST_TOTAL_SENT_DATA))

	var host_key: String=host._key(1,"assembly",0)
	var owned_key: String=host._key(ids[1],"assembly",1)
	var client:=peers_world[1]
	client.command.rpc_id(1,{"op":"pickup","key":host_key})
	client.command.rpc_id(1,{"op":"control","key":owned_key,"control":"A","pressed":true})
	assert(await _wait(func():return host.placed[owned_key].state.A),"Remote control was not accepted")
	assert(host.placed.has(host_key),"Guest removed another player's invention")

	started=Time.get_ticks_usec()
	for frame in 60:host._physics_process(1.0/60.0)
	var tick_ms: float=(Time.get_ticks_usec()-started)/1000.0
	assert(await _wait(func():return _matches(host.placed)),"Dynamic updates did not converge on all clients")
	var dynamic_bytes:=int(server.host.pop_statistic(ENetConnection.HOST_TOTAL_SENT_DATA))
	assert(dynamic_bytes<structural_bytes/10,"Motion traffic approached the structural transfer size")
	client.command.rpc_id(1,{"op":"pickup","key":owned_key})
	assert(await _wait(func():return not host.placed.has(owned_key) and _matches(host.placed)),"Owner retrieval did not reach all peers")
	host.game.session.poses[ids[1]].position=Vector3(45,0,0)
	host._physics_process(.1)
	assert(await _wait(func():return _matches(host.placed)),"Nearby subscription flickered between the cutoffs")
	host.game.session.poses[ids[1]].position=Vector3(60,0,0)
	host._physics_process(.1)
	var owned_count: int=host.placed.values().filter(func(item):return item.owner==ids[1]).size()
	assert(await _wait(func():return client.placed.size()==owned_count),"Distant non-owned inventions remained subscribed")
	host.game.session.poses[ids[1]].position=Vector3(45,0,0)
	host._physics_process(.1)
	assert(await _wait(func():return client.placed.size()==owned_count),"Distant subscription flickered between the cutoffs")
	host.game.session.poses[ids[1]].position=Vector3.ZERO
	host._physics_process(.1)
	assert(await _wait(func():return _matches(host.placed)),"Returning player did not receive a fresh structural baseline")

	var departing: Node3D=peers_world.pop_back()
	var old_api:=peers.pop_back() as SceneMultiplayer
	var old_id:=old_api.get_unique_id()
	old_api.multiplayer_peer.close()
	assert(await _wait(func():return host.game.session.connected_peers().size()==Session.MAX_PLAYERS-2))
	host.game.session.roster.erase(old_id)
	host.game.session.roster_changed.emit()
	assert(host.placed.values().all(func(item):return item.owner!=old_id),"Disconnect retained the owner's active inventions")
	assert(await _wait(func():return _matches(host.placed)),"Remaining peers retained abandoned inventions")
	var replacement:=ENetMultiplayerPeer.new()
	assert(replacement.create_client("127.0.0.1",port)==OK)
	_connect(replacement)
	assert(await _wait(func():return host.game.session.connected_peers().size()==Session.MAX_PLAYERS-1))
	host._sync()
	assert(await _wait(func():return _matches(host.placed)),"Replacement peer did not receive the current world")
	print("INVENTION_NETWORK_LOAD PASS: %d players, %d inventions, 8 live PCBs, %d serialized bytes, initial sync %.1f ms, 60 host ticks %.1f ms, network bytes %d initial / %d dynamic"%[Session.MAX_PLAYERS,World.MAX_PLACEMENTS,size,sync_ms,tick_ms,structural_bytes,dynamic_bytes])
	for api in peers:api.multiplayer_peer.close()
	for world in peers_world:world.game.queue_free()
	departing.game.queue_free()
	await process_frame
	quit()

func _matches(expected: Dictionary) -> bool:
	for i in range(1,peers_world.size()):
		if peers_world[i].placed!=expected:return false
	return true

func _pcb() -> RefCounted:
	var source:=Board.empty()
	source.parts=[{"id":"gate","type":"toggle","a":"A1","b":"A2"},{"id":"pull","type":"r1000","a":"A2","b":"F1"}]
	var bp: Dictionary=Board.blueprint(source,"Drive PCB")
	bp.package="PCB"
	bp.footprint={"width":8,"height":8,"color":"24775b"}
	bp.layout={"rows":30,"parts":source.parts.duplicate(true),"wires":[]}
	bp.pins=[{"name":"VCC","node":"L1"},{"name":"GND","node":"R1"},{"name":"OUT_A","node":"L2"}]
	var runtime:=PCBRun.new()
	assert(runtime.configure("ic:drive",{"ic:drive":bp},{"power":0,"ground":1,"A":2,"B":-1}))
	assert(runtime.input("board/pcb/gate",true))
	return runtime
