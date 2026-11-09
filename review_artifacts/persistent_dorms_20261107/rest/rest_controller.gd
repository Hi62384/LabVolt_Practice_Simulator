extends Node
const State=preload("res://review_artifacts/persistent_dorms_20261107/rest/rest_state.gd")
const Stand=preload("res://review_artifacts/persistent_dorms_20261107/rest/safe_stand.gd")
var state=State.new()
var game: Node
var authority: Object
var revision := 0
var received_revision := -1
var public_states := {}
func configure(owner_game: Node, dorm_authority: Object) -> void:
	game=owner_game;authority=dorm_authority
	game.session.roster_changed.connect(_cleanup)
	game.session.restarted.connect(_reset)
func request(room: String, exit := false) -> void:
	if game.session.online and not multiplayer.is_server():_request.rpc_id(1,room,exit)
	else:_accept(multiplayer.get_unique_id(),room,exit)
@rpc("any_peer","call_remote","reliable")
func _request(room: String, exit: bool) -> void:
	if multiplayer.is_server():_accept(multiplayer.get_remote_sender_id(),room,exit)
func _accept(peer: int, room: String, exit: bool) -> void:
	if not game.session.roster.has(peer):return
	if exit:
		if not state.resting.has(peer):return
		var old: Dictionary=state.resting[peer]
		var destination=Stand.find(game.player,old.anchor,old.return_position,peer==multiplayer.get_unique_id())
		if not state.end(peer,destination).get("ok",false):return
		game.session.poses[peer].position=destination
		_publish({peer:destination});return
	var pose: Dictionary=game.session.poses.get(peer,{})
	var busy: bool=pose.get("seated",false)
	if game.session.facility_translation_guard.is_valid():
		var at: Vector3=pose.get("position",Vector3.ZERO)
		busy=busy or game.session.facility_translation_guard.call(peer,at+Vector3.RIGHT*.01,at).is_equal_approx(at)
	for chair in game.chairs:
		if chair.occupant==peer:busy=true
	if not state.begin(peer,room,pose.get("position",Vector3.INF),authority,game.session.roster,busy).ok:return
	game.session.poses[peer].position=state.resting[peer].anchor.origin
	_publish({})
func _publish(exits: Dictionary) -> void:
	revision+=1
	public_states=state.resting.duplicate(true)
	# Return locations are private to host; clients receive pose anchors only.
	for entry in public_states.values():entry.erase("return_position")
	_snapshot(revision,public_states,exits)
	if game.session.online:
		for peer in game.session.connected_peers():_snapshot.rpc_id(peer,revision,public_states,exits)
@rpc("authority","call_remote","reliable")
func _snapshot(sequence: int, states: Dictionary, exits: Dictionary) -> void:
	if sequence<=received_revision:return
	received_revision=sequence;public_states=states
	var local:=multiplayer.get_unique_id()
	if states.has(local):game.player.begin_rest(states[local].anchor)
	elif exits.has(local):game.player.end_rest(exits[local])
func canonical_pose(peer: int, pose: Dictionary) -> Dictionary:
	var clean:=pose.duplicate()
	clean.resting=state.resting.has(peer)
	if clean.resting:
		clean.position=state.resting[peer].anchor.origin;clean.seated=false;clean.crouch=false
	return clean
func _cleanup() -> void:
	if not multiplayer.is_server():return
	var changed:=false
	for peer in state.resting.keys():
		if not game.session.roster.has(peer):state.disconnect(peer);changed=true
	if changed:_publish({})
func _reset() -> void:
	if game.player.resting:
		var destination=Stand.find(game.player,game.player.rest_anchor,game.player.global_position)
		if destination==null:return # Retain a safe locked state; exit can retry.
		game.player.end_rest(destination)
	state.clear();public_states.clear();received_revision=-1;revision=0
