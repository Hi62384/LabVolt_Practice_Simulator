extends SceneTree
const NetworkAdapter=preload("res://scripts/campus/dorms/authority/network_adapter.gd")
const Session=preload("res://scripts/session.gd")
var failures:=0
func check(ok:bool,label:String)->void:
	if not ok:failures+=1;printerr("FAIL "+label)
func _initialize()->void:call_deferred("run")
func run()->void:
	var host:=Node.new();root.add_child(host)
	var session:=Session.new();host.add_child(session);session.initialize([],{});session.roster={1:{"name":"Host"}}
	# Exercise the roster-based transport adapter directly.
	var authority:=NetworkAdapter.new()
	host.add_child(authority)
	var ids:Array=[]
	for i in session.MAX_PLAYERS:ids.append("dorm_%02d"%i)
	authority.is_host=func():return true
	authority.authenticated_peers=func():return session.roster.keys()
	authority.peer_is_connected=func(peer:int):return peer==1 or session.roster.has(peer)
	check(authority.configure(ids,session.MAX_PLAYERS,1).ok,"capacity matches production session")
	for peer in range(2,session.MAX_PLAYERS+1):session.roster[peer]={"name":"Guest"}
	check(authority.reconcile().ok and authority.model.assignments.size()==session.MAX_PLAYERS,"all authenticated participants assigned")
	check(not authority.model.join_authenticated(99).ok,"full capacity rejects ninth participant")
	check(not authority.receive_door_request(99,{"epoch":1,"sequence":0,"open":true}).ok,"unrostered sender rejected")
	check(not authority.receive_door_request(2,{"epoch":1,"sequence":0,"room_id":ids[0],"open":true}).ok,"visitor cannot open owner's door")
	check(authority.receive_door_request(1,{"epoch":1,"sequence":0,"open":true}).ok,"host opens own door")
	check(authority.model.may_enter(ids[0]),"open door permits visitor passage")
	check(not authority.receive_door_request(1,{"epoch":0,"sequence":1,"open":false}).ok,"old session rejected")
	check(authority.receive_door_request(1,{"epoch":1,"sequence":0,"open":true}).ok,"duplicate request idempotent")
	var released:String=authority.model.room_for(3);session.roster.erase(3)
	check(authority.reconcile().ok and authority.model.room_for(3).is_empty(),"disconnect releases room")
	session.roster[20]={"name":"Replacement"};check(authority.reconcile().ok and authority.model.room_for(20)==released,"new participant reclaims room")
	check(authority.initial_snapshot(20).ok and authority.model.snapshot().assignments.size()==session.MAX_PLAYERS,"reconnect snapshot covers capacity")
	print("INTEGRATED DORM AUTHORITY failures=%d"%failures);quit(1 if failures else 0)
