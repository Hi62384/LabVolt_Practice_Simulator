extends SceneTree
const Session=preload("res://scripts/session.gd")
var failures: Array[String]=[]
var results: Array[bool]=[]
var leave_signals:=0
var barrier_calls:=0

func check(value: bool,message: String) -> void:
	if not value:failures.append(message)

func _initialize() -> void:
	_run.call_deferred()

func _barrier() -> bool:
	barrier_calls+=1
	await process_frame
	await process_frame
	return true

func _leave(session: Node) -> void:
	results.append(await session.leave_gracefully())

func _server(session: Node) -> ENetMultiplayerPeer:
	var peer:=ENetMultiplayerPeer.new()
	check(peer.create_server(0,1)==OK,"Ephemeral test server opens")
	root.multiplayer.multiplayer_peer=peer
	session.online=true;session.was_host=true
	return peer

func _run() -> void:
	var session:=Session.new();root.add_child(session)
	session.leaving.connect(func():leave_signals+=1)
	session.set_departure_barrier(_barrier)
	check(await session.leave_gracefully(),"Offline leave completes immediately")
	check(barrier_calls==0 and leave_signals==1,"Offline leave does not enter async drain")
	var original:=_server(session)
	results.clear()
	_leave(session)
	_leave(session)
	check(session.online and root.multiplayer.multiplayer_peer==original,"Transport stays active until barrier completion")
	for _frame in 5:await process_frame
	check(results==[true,true] and not session.online,"Concurrent deliberate exits share one completion")
	check(barrier_calls==1 and leave_signals==2,"Concurrent exits run callbacks and drain once")
	original=_server(session)
	results.clear()
	_leave(session)
	session.leave()
	var replacement:=_server(session)
	for _frame in 5:await process_frame
	check(results==[false],"Old async exit reports superseded transport")
	check(session.online and root.multiplayer.multiplayer_peer==replacement and replacement!=original,"Stale continuation cannot close replacement connection")
	check(leave_signals==3,"Synchronous replacement does not announce the prepared leave twice")
	session.leave();session.free()
	for failure in failures:printerr("FAIL: "+failure)
	print("SESSION_GRACEFUL_LIFECYCLE "+("PASS" if failures.is_empty() else "FAIL"))
	quit(0 if failures.is_empty() else 1)
