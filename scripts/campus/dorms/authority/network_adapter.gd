class_name DormAuthorityNetworkAdapter
extends Node

## Narrow transport adapter. Integration binds authenticated roster/presence
## callables; RPC payloads never supply the acting peer identity.
signal authoritative_snapshot(data: Dictionary)
signal request_rejected(peer: int, reason: String)

var model := DormOwnershipAuthority.new()
var is_host := Callable()
var authenticated_peers := Callable()
var peer_is_connected := Callable()
var send_snapshot_to_peer := Callable()
var broadcast_snapshot := Callable()
var clock_ms := Callable()

func configure(stable_room_ids: Array, max_players: int, epoch: int) -> Dictionary:
	if not _host(): return {"ok":false,"error":"host_authority_required"}
	var result := model.configure(stable_room_ids,max_players,epoch)
	if result.ok: _publish()
	return result

func reconcile() -> Dictionary:
	if not _host() or not authenticated_peers.is_valid(): return {"ok":false,"error":"host_authority_required"}
	var peers: Array = authenticated_peers.call()
	var connected: Array = []
	for value in peers:
		var peer := int(value)
		if not peer_is_connected.is_valid() or peer_is_connected.call(peer): connected.append(peer)
	var result := model.reconcile_authenticated_peers(connected)
	if result.ok and result.changed: _publish()
	return result

func authenticated_join(peer: int) -> Dictionary:
	if not _host() or not _authenticated_and_connected(peer): return {"ok":false,"error":"unauthenticated_peer"}
	var result := model.join_authenticated(peer)
	if result.ok:
		_publish()
		if send_snapshot_to_peer.is_valid(): send_snapshot_to_peer.call(peer,model.snapshot())
	return result

func authenticated_leave(peer: int) -> Dictionary:
	if not _host(): return {"ok":false,"error":"host_authority_required"}
	var result := model.leave_authenticated(peer)
	if result.changed: _publish()
	return result

func receive_door_request(authenticated_sender: int, request: Dictionary) -> Dictionary:
	if not _host() or not _authenticated_and_connected(authenticated_sender): return {"ok":false,"error":"unauthenticated_peer"}
	var now := int(clock_ms.call()) if clock_ms.is_valid() else Time.get_ticks_msec()
	var result := model.request_door(authenticated_sender,request,now)
	if result.ok: _publish()
	else: request_rejected.emit(authenticated_sender,str(result.error))
	return result

func initial_snapshot(peer: int) -> Dictionary:
	if not _host() or not _authenticated_and_connected(peer): return {"ok":false,"error":"unauthenticated_peer"}
	var data := model.snapshot()
	if send_snapshot_to_peer.is_valid(): send_snapshot_to_peer.call(peer,data)
	return {"ok":true,"snapshot":data}

func _authenticated_and_connected(peer: int) -> bool:
	if peer <= 0 or not authenticated_peers.is_valid(): return false
	if peer not in authenticated_peers.call(): return false
	return not peer_is_connected.is_valid() or bool(peer_is_connected.call(peer))

func _host() -> bool:
	return is_host.is_valid() and bool(is_host.call())

func _publish() -> void:
	var data := model.snapshot()
	authoritative_snapshot.emit(data)
	if broadcast_snapshot.is_valid(): broadcast_snapshot.call(data)
