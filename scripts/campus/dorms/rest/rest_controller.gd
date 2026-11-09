extends Node
const State=preload("res://scripts/campus/dorms/rest/rest_state.gd")
const Stand=preload("res://scripts/campus/dorms/rest/safe_stand.gd")
var state=State.new()
var game: Node
var authority: Object
var revision := 0
var received_revision := -1
var public_states := {}
var pending_exits := {}
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
		if state.resting.has(peer):pending_exits[peer]=true
		return
	var pose: Dictionary=game.session.poses.get(peer,{})
	var busy: bool=pose.get("seated",false)
	if game.session.facility_translation_guard.is_valid():
		var at: Vector3=pose.get("position",Vector3.ZERO)
		busy=busy or game.session.facility_translation_guard.call(peer,at+Vector3.RIGHT*.01,at).is_equal_approx(at)
	for chair in game.chairs:
		if chair.occupant==peer:busy=true
	var position: Vector3=game.player.global_position if peer==multiplayer.get_unique_id() else pose.get("position",Vector3.INF)
	if not state.begin(peer,room,position,authority,game.session.roster,busy).ok:
		if peer==multiplayer.get_unique_id():_rest_feedback()
		else:_rest_feedback.rpc_id(peer)
		return
	game.session.poses[peer].position=state.resting[peer].anchor.origin
	_publish({})

func _physics_process(_delta: float) -> void:
	if pending_exits.is_empty():return
	var exits := {}
	for peer in pending_exits:
		if not state.resting.has(peer):continue
		var old: Dictionary=state.resting[peer]
		var destination=Stand.find(game.player,old.anchor,old.return_position,peer==multiplayer.get_unique_id(),state.exit_aisles.get(old.room,Vector3.INF))
		if not state.end(peer,destination).get("ok",false):
			if peer==multiplayer.get_unique_id():_exit_blocked()
			else:_exit_blocked.rpc_id(peer)
			continue
		game.session.poses[peer].position=destination
		exits[peer]=destination
	pending_exits.clear()
	if not exits.is_empty():_publish(exits)

@rpc("authority","call_remote","reliable")
func _exit_blocked() -> void:
	game.ui.log_message("There is no clear space beside the bed. Try standing again when it clears.")

@rpc("authority","call_remote","reliable")
func _rest_feedback() -> void:
	game.ui.log_message("Rest is available at your own bed when you are standing nearby.")
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
		if not game.session.roster.has(peer):state.remove_peer(peer);changed=true
	if changed:_publish({})
func _reset() -> void:
	pending_exits.clear()
	if game.player.resting:
		var entry: Dictionary=state.resting.get(multiplayer.get_unique_id(),{})
		var destination=Stand.find(game.player,game.player.rest_anchor,entry.get("return_position",game.player.global_position),true,state.exit_aisles.get(entry.get("room",""),Vector3.INF))
		if destination==null:return # Retain a safe locked state; exit can retry.
		game.player.end_rest(destination)
	state.clear();public_states.clear();received_revision=-1;revision=0
