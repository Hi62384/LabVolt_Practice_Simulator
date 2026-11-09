extends Node
const Authority = preload("res://scripts/campus/dorms/authority/network_adapter.gd")
const Router = preload("res://scripts/campus/dorms/interactions/personal_station_router.gd")
const Fallback = preload("res://scripts/campus/dorms/interactions/shop_fallback_policy.gd")
var game: Node
var hall: Node3D
var authority: Node
var router: Node
var snapshot := {}
var epoch := 0
var sequence := 0

func build(owner_game: Node) -> void:
	game=owner_game
	hall=preload("res://scripts/campus/dorms/world/dorm_hall.gd").new();game.campus.add_child(hall);hall.build(game.session.MAX_PLAYERS)
	authority=Authority.new();authority.name="Authority";add_child(authority)
	authority.is_host=func():return multiplayer.is_server()
	authority.authenticated_peers=func():return game.session.roster.keys()
	authority.peer_is_connected=game.session.peer_connected_now
	authority.broadcast_snapshot=func(data: Dictionary):
		_receive(data)
		for peer in game.session.connected_peers():_receive.rpc_id(int(peer),data)
	router=Router.new();add_child(router);router.configure(game,self)
	for room in hall.room_contracts:
		for kind in ["kit_workshop","loadout","notes"]:
			var target := StaticBody3D.new();target.collision_layer=4;target.collision_mask=0
			target.position=room.workshop_anchor+Vector3(0,1,0) if kind=="kit_workshop" else room.loadout_notes_anchor+Vector3(0,1,-.35 if kind=="notes" else .35)
			var collision := CollisionShape3D.new();var shape := BoxShape3D.new();shape.size=Vector3(.6,.6,.6);collision.shape=shape;target.add_child(collision);hall.add_child(target)
			router.register_station(target,str(room.dorm_id),kind)
	game.session.restarted.connect(_restart)
	game.session.leaving.connect(func():snapshot={};router.assignment_changed())
	game.session.roster_changed.connect(_roster_changed)
	_restart()

func _restart() -> void:
	sequence=0;snapshot={};epoch+=1
	if multiplayer.is_server():
		var ids: Array=[]
		for room in hall.room_contracts:ids.append(room.dorm_id)
		authority.configure(ids,game.session.MAX_PLAYERS,epoch);authority.reconcile()

func _roster_changed() -> void:
	if multiplayer.is_server():
		authority.reconcile()
		# Send the complete compact projection to newly admitted peers as well.
		authority.broadcast_snapshot.call(authority.model.snapshot())

@rpc("authority","call_remote","reliable",7)
func _receive(data: Dictionary) -> void:
	if data.get("schema")!=1 or data.get("capacity")!=game.session.MAX_PLAYERS or var_to_bytes(data).size()>8192:return
	snapshot=data.duplicate(true)
	for id in hall.door_targets:
		var door: Node3D=hall.door_targets[id]
		door.get_parent().rotation.y=PI/2 if id in snapshot.get("open_doors",[]) else 0.0
	router.assignment_changed()
	for target in game.shop_room.get_children():
		if target.get_meta("role","")=="shop_station":Fallback.filter_legacy_station(router,target)

func room_for_peer(peer: int) -> String:
	for pair in snapshot.get("assignments",[]):
		if int(pair[0])==peer:return str(pair[1])
	return ""
func authenticated_identity(peer: int) -> String:
	return "peer:"+str(peer) if game.session.roster.has(peer) else ""
func owner_identity(room: String) -> String:
	for pair in snapshot.get("assignments",[]):
		if str(pair[1])==room:return authenticated_identity(int(pair[0]))
	return ""
func assignment_revision() -> int:return int(snapshot.get("revision",0))
func interact(target: Node) -> bool:
	if router.interact(target):return true
	if not is_instance_valid(target) or target.get_meta("role","")!="dorm_door":return false
	var peer := multiplayer.get_unique_id()
	var room := str(target.get_meta("dorm_id",""))
	if room_for_peer(peer)!=room:return true
	sequence+=1
	var request := {"epoch":snapshot.get("epoch",-1),"sequence":sequence,"open":not room in snapshot.get("open_doors",[])}
	if multiplayer.is_server():_door_for(peer,request)
	else:_door.rpc_id(1,request)
	return true
@rpc("any_peer","call_remote","reliable",7)
func _door(request: Dictionary) -> void:
	if multiplayer.is_server():_door_for(multiplayer.get_remote_sender_id(),request)
func _door_for(peer: int,request: Dictionary) -> void:
	var room := room_for_peer(peer)
	if not hall.door_targets.has(room):return
	var point: Vector3=game.player.global_position if peer==1 else game.session.poses.get(peer,{}).get("position",Vector3.INF)
	if point.distance_to(hall.door_targets[room].global_position)>3.0:return
	authority.receive_door_request(peer,request)
