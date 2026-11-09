extends SceneTree
const Coordinator=preload("res://scripts/campus/dorms/integration/coordinator.gd")
const Session=preload("res://scripts/session.gd")
var failures:=0
func check(ok:bool,label:String)->void:
	if not ok:failures+=1;printerr("FAIL "+label)
func _initialize()->void:call_deferred("run")
func run()->void:
	var host:=Node.new();root.add_child(host)
	var session:=Session.new();host.add_child(session);session.initialize([],{});session.roster={1:{"name":"Host"}}
	var campus:=Node3D.new();host.add_child(campus)
	var shop:=Node3D.new();host.add_child(shop)
	var player:=Node3D.new();host.add_child(player)
	# Coordinator's transport model is exercised with an isolated roster.
	var coordinator:=Coordinator.new();host.add_child(coordinator)
	var ids:Array=[]
	for i in session.MAX_PLAYERS:ids.append("dorm_%02d"%i)
	coordinator.authority=preload("res://scripts/campus/dorms/authority/network_adapter.gd").new();coordinator.add_child(coordinator.authority)
	coordinator.authority.is_host=func():return true
	coordinator.authority.authenticated_peers=func():return session.roster.keys()
	coordinator.authority.peer_is_connected=func(peer:int):return peer==1 or session.roster.has(peer)
	check(coordinator.authority.configure(ids,session.MAX_PLAYERS,1).ok,"capacity matches production session")
	for peer in range(2,session.MAX_PLAYERS+1):session.roster[peer]={"name":"Guest"}
	check(coordinator.authority.reconcile().ok and coordinator.authority.model.assignments.size()==session.MAX_PLAYERS,"all authenticated participants assigned")
	check(not coordinator.authority.model.join_authenticated(99).ok,"full capacity rejects ninth participant")
	check(not coordinator.authority.receive_door_request(99,{"epoch":1,"sequence":0,"open":true}).ok,"unrostered sender rejected")
	check(not coordinator.authority.receive_door_request(2,{"epoch":1,"sequence":0,"room_id":ids[0],"open":true}).ok,"visitor cannot open owner's door")
	check(coordinator.authority.receive_door_request(1,{"epoch":1,"sequence":0,"open":true}).ok,"host opens own door")
	check(coordinator.authority.model.may_enter(ids[0]),"open door permits visitor passage")
	check(not coordinator.authority.receive_door_request(1,{"epoch":0,"sequence":1,"open":false}).ok,"old session rejected")
	check(coordinator.authority.receive_door_request(1,{"epoch":1,"sequence":0,"open":true}).ok,"duplicate request idempotent")
	var released:String=coordinator.authority.model.room_for(3);session.roster.erase(3)
	check(coordinator.authority.reconcile().ok and coordinator.authority.model.room_for(3).is_empty(),"disconnect releases room")
	session.roster[20]={"name":"Replacement"};check(coordinator.authority.reconcile().ok and coordinator.authority.model.room_for(20)==released,"new participant reclaims room")
	check(coordinator.authority.initial_snapshot(20).ok and coordinator.authority.model.snapshot().assignments.size()==session.MAX_PLAYERS,"reconnect snapshot covers capacity")
	print("INTEGRATED DORM AUTHORITY failures=%d"%failures);quit(1 if failures else 0)
