extends SceneTree
const Adapter=preload("res://scripts/campus/dorms/authority/network_adapter.gd")
var failed:=false
var peers:Array=[1,8]
var sent:Array=[]
var broadcasts:Array=[]
func check(value:bool,label:String)->void:
	if not value: failed=true;push_error(label)
func _init()->void:
	var a=Adapter.new();root.add_child(a)
	a.is_host=func():return true
	a.authenticated_peers=func():return peers.duplicate()
	a.peer_is_connected=func(peer:int):return peer in peers
	a.clock_ms=func():return 1000
	a.send_snapshot_to_peer=func(peer:int,data:Dictionary):sent.append([peer,data])
	a.broadcast_snapshot=func(data:Dictionary):broadcasts.append(data)
	check(a.configure(["room-0","room-1"],2,77).ok,"host configures")
	check(a.reconcile().ok and a.model.room_for(1)=="room-0" and a.model.room_for(8)=="room-1","authenticated roster allocated")
	check(not a.authenticated_join(99).ok,"unrostered peer rejected")
	check(not a.receive_door_request(99,{"epoch":77,"sequence":0,"open":true}).ok,"forged sender rejected")
	check(a.receive_door_request(8,{"epoch":77,"sequence":0,"open":true}).ok,"authenticated owner request")
	check(a.initial_snapshot(8).ok and sent[-1][0]==8 and sent[-1][1].assignments.size()==2,"initial snapshot sent")
	peers.erase(8);check(a.reconcile().ok and a.model.room_for(8).is_empty() and not a.model.may_enter("room-1"),"disconnect cleanup")
	check(broadcasts.size()>=3,"authoritative deltas published")
	print(JSON.stringify({"suite":"dorm_network_adapter","ok":not failed,"checks":"auth sender initial snapshot replication disconnect"}))
	quit(1 if failed else 0)
