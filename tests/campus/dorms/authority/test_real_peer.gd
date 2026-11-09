extends SceneTree
## Two process, real ENet Session and production dorm coordinator. Never run
## against a live user process. Output stays under a private user:// directory.
const Session=preload("res://scripts/session.gd")
const Coordinator=preload("res://scripts/campus/dorms/integration/coordinator.gd")
class FixtureGame:
	extends Node
	var session:Node
	var campus:Node3D
	var shop_room:Node3D
	var player:Node3D
	var electronics:Node
class Electronics:
	extends Node
	var active:=false
	var current_page:=""
	var opened:Array=[]
	func open(page:String)->void:active=true;current_page=page;opened.append(page)
	func close()->void:active=false
class Control:
	extends Node
	var driver:SceneTree
	@rpc("any_peer","call_remote","reliable",7)
	func report(data:Dictionary)->void:
		if multiplayer.is_server():driver.client_report=data
	@rpc("authority","call_remote","reliable",7)
	func probe(room:String)->void:
		var d=driver
		var peer:=multiplayer.get_unique_id()
		var denied:Dictionary={}
		var opened:Dictionary={}
		for kind in ["kit_workshop","loadout","notes"]:
			var foreign:Node=d.station(room,kind)
			var before:int=d.game.electronics.opened.size()
			if foreign!=null:d.coordinator.interact(foreign)
			denied[kind]=foreign!=null and d.game.electronics.opened.size()==before
			var own:Node=d.station(d.coordinator.room_for_peer(peer),kind)
			before=d.game.electronics.opened.size()
			if own!=null:d.coordinator.interact(own)
			opened[kind]=own!=null and d.game.electronics.opened.size()==before+1
		report.rpc_id(1,{"room":d.coordinator.room_for_peer(peer),"visitor_denied":denied,"owner_opened":opened})
	@rpc("authority","call_remote","reliable",7)
	func rejoin()->void:
		var d=driver
		d.game.session.leave()
		d.game.session.join_game("127.0.0.1","Client",d.port)
	@rpc("authority","call_remote","reliable",7)
	func finish()->void:driver.finish()
var role:="host"
var port:=26118
var output:="user://dorm-real-peer-result.json"
var game:FixtureGame
var coordinator:Node
var control:Control
var client_report:Dictionary={}
var failures:Array[String]=[]
var deadline:=0
func station(room:String,kind:String)->Node:
	for target in coordinator.router._stations.values():
		if target.get_meta("dorm_room_id","")==room and target.get_meta("station_kind","")==kind:return target
	return null
func _initialize()->void:call_deferred("run")
func run()->void:
	for arg in OS.get_cmdline_user_args():
		var pair:=arg.split("=",true,1)
		if pair.size()!=2:continue
		match pair[0]:
			"--role":role=pair[1]
			"--port":port=int(pair[1])
			"--output":output=pair[1]
	deadline=Time.get_ticks_msec()+15000
	game=FixtureGame.new();root.add_child(game)
	game.session=Session.new();game.session.name="Session";game.add_child(game.session);game.session.campus_enabled=true;game.session.initialize([],{})
	game.campus=Node3D.new();game.add_child(game.campus)
	game.shop_room=Node3D.new();game.add_child(game.shop_room)
	game.player=Node3D.new();game.add_child(game.player)
	game.electronics=Electronics.new();game.add_child(game.electronics)
	coordinator=Coordinator.new();coordinator.name="Dorms";game.add_child(coordinator);coordinator.build(game)
	control=Control.new();control.name="Control";control.driver=self;root.add_child(control)
	var error:Error=game.session.host_game("Host",port) if role=="host" else game.session.join_game("127.0.0.1","Client",port)
	if error!=OK:failures.append("ENet start "+str(error));finish();return
	if role!="host":return
	var ready:=FileAccess.open(output+".ready",FileAccess.WRITE)
	if ready!=null:ready.store_string("ready");ready.close()
	if not await until(func():return game.session.roster.size()==2 and coordinator.snapshot.get("assignments",[]).size()==2):failures.append("two authenticated assignments timeout");finish();return
	var client:int=-1
	for peer in game.session.roster:
		if int(peer)!=1:client=int(peer)
	var host_room:String=coordinator.room_for_peer(1)
	var client_room:String=coordinator.room_for_peer(client)
	if host_room.is_empty() or client_room.is_empty() or host_room==client_room:failures.append("distinct assignments")
	var door:Node3D=coordinator.hall.door_targets[host_room]
	game.player.global_position=door.global_position
	coordinator.interact(door)
	if not await until(func():return host_room in coordinator.snapshot.get("open_doors",[])):failures.append("owner door open")
	control.rpc_id(client,"probe",host_room)
	if not await until(func():return not client_report.is_empty()):failures.append("client probe timeout")
	else:
		if client_report.get("room","")!=client_room:failures.append("client assignment")
		for kind in ["kit_workshop","loadout","notes"]:
			if not client_report.get("visitor_denied",{}).get(kind,false):failures.append("visitor accessed "+kind)
			if not client_report.get("owner_opened",{}).get(kind,false):failures.append("owner denied "+kind)
	for kind in ["kit_workshop","loadout","notes"]:
		var own:Node=station(host_room,kind)
		var before:int=game.electronics.opened.size()
		if own!=null:coordinator.interact(own)
		if own==null or game.electronics.opened.size()!=before+1:failures.append("host owner route "+kind)
	# The authenticated transport sender cannot choose another owner's room.
	var forged:Dictionary=coordinator.authority.receive_door_request(client,{"epoch":coordinator.epoch,"sequence":0,"room_id":host_room,"open":false})
	if forged.get("ok",false) or host_room not in coordinator.snapshot.get("open_doors",[]):failures.append("forged room mutation")
	game.session.poses[client]={"position":door.global_position}
	coordinator._door_for(client,{"epoch":coordinator.epoch,"sequence":1,"room_id":host_room,"open":false})
	if host_room not in coordinator.snapshot.get("open_doors",[]):failures.append("visitor door mutation")
	var stale:Dictionary=coordinator.authority.receive_door_request(1,{"epoch":coordinator.epoch-1,"sequence":99,"open":false})
	if stale.get("ok",false):failures.append("stale epoch accepted")
	control.rpc_id(client,"rejoin")
	if not await until(func():return not game.session.roster.has(client)):failures.append("disconnect timeout")
	elif not coordinator.room_for_peer(client).is_empty():failures.append("room retained after leave")
	if not await until(func():return game.session.roster.size()==2 and not coordinator.room_for_peer(_client_peer()).is_empty()):failures.append("rejoin timeout")
	else:
		var replacement:int=_client_peer()
		if coordinator.room_for_peer(replacement)!=client_room:failures.append("released room not reclaimed")
		client_report={};control.rpc_id(replacement,"probe",host_room)
		if not await until(func():return not client_report.is_empty()):failures.append("rejoin snapshot timeout")
		elif client_report.get("room","")!=client_room:failures.append("rejoin assignment snapshot")
		control.rpc_id(replacement,"finish")
	finish()
func _client_peer()->int:
	for peer in game.session.roster:
		if int(peer)!=1:return int(peer)
	return -1
func until(predicate:Callable)->bool:
	var end:=Time.get_ticks_msec()+4000
	while Time.get_ticks_msec()<end:
		if predicate.call():return true
		await create_timer(.025).timeout
	return false
func _process(_delta:float)->bool:
	if deadline>0 and Time.get_ticks_msec()>deadline:failures.append("global timeout");finish()
	return false
func finish()->void:
	deadline=0
	var file:=FileAccess.open(output,FileAccess.WRITE)
	if file!=null:file.store_string(JSON.stringify({"role":role,"failures":failures,"scope":"real two peer ENet; private electronics stub; no physics or eight peer proof"}));file.close()
	if is_instance_valid(game):game.session.leave()
	print("DORM REAL PEER "+role+" failures="+str(failures.size()))
	quit(1 if not failures.is_empty() else 0)
