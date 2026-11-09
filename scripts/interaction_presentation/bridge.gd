extends Node
## Binds existing Game visuals. No electrical writes; main integration is proposed separately.
const Events = preload("res://scripts/interaction_presentation/accepted_event.gd")
const Actor = preload("res://scripts/interaction_presentation/actor.gd")
var game: Node
var actors = {}
var bindings = {}
var motions = {}
var facility_activities = {}
var facility_food = {}
var enabled = true
var local_visual: Node3D
var local_actor: Node
var local_peer: int = 0

func attach(value: Node) -> void:
	game = value
	set_local_peer(game.multiplayer.get_unique_id())
	set_process(false)
	process_priority = 100

func bind_avatar(peer: int, model: Node3D) -> bool:
	# A remote host avatar must never repurpose the first-person actor, even
	# across an offline 1 -> joined ID -> offline 1 transition.
	if peer<=0 or peer==local_peer:
		return false
	var actor = _actor(peer)
	if actor==local_actor:
		return false
	var supported: bool = actor.bind_visual(model)
	_drop_motions_for_actor(actor)
	return supported

func set_local_peer(peer: int) -> void:
	# Caller supplies the current real MultiplayerAPI ID after transport change.
	# Zero means unbound during teardown. No equipment/pose identity is changed.
	peer = maxi(peer,0)
	if peer==local_peer:
		return
	if is_instance_valid(local_actor):
		if actors.get(local_peer)==local_actor:
			actors.erase(local_peer)
		local_actor.reset()
		_drop_motions_for_actor(local_actor)
	if peer>0 and actors.has(peer) and actors[peer]!=local_actor:
		var previous: Node = actors[peer]
		previous.reset()
		_drop_motions_for_actor(previous)
		previous.queue_free()
		actors.erase(peer)
	local_peer = peer
	if peer>0 and is_instance_valid(local_actor):
		actors[peer] = local_actor

func session_transition() -> void:
	# session.leaving occurs before the MultiplayerAPI switches back to offline.
	# Detach all old ID aliases now; a later roster/snapshot binds the real new ID.
	reset()
	for actor in actors.values():
		if actor!=local_actor:
			actor.queue_free()
	actors.clear()
	local_peer = 0

func bind_local(model: Node3D) -> void:
	# Copy only the existing art's arm, with shared mesh/material resources.
	# Unsupported imported avatars get no fabricated hand or whole-body fallback.
	var source = model.find_child("ArmR",true,false) as Node3D
	set_local_peer(game.multiplayer.get_unique_id())
	if not is_instance_valid(local_actor):
		local_actor = Actor.new()
		add_child(local_actor)
		local_actor.set_enabled(enabled)
	if local_peer>0:
		actors[local_peer] = local_actor
	var actor: Node = local_actor
	actor.bind_visual(null)
	_drop_motions_for_actor(actor)
	if is_instance_valid(local_visual):
		local_visual.queue_free()
	local_visual = null
	if source == null:
		return
	local_visual = source.duplicate() as Node3D
	game.camera.add_child(local_visual)
	local_visual.position = Vector3(0.40,-0.70,-0.44)
	local_visual.rotation = Vector3(2.8,0.0,0.25)
	actor.bind_visual(local_visual,true)

func _actor(peer: int) -> Node:
	if not actors.has(peer):
		var actor = Actor.new()
		add_child(actor)
		actor.set_enabled(enabled)
		actors[peer] = actor
		actor.set_suspended(bool(facility_activities.get(peer,false)) or bool(facility_food.get(peer,false)))
	return actors[peer]

func accepted(value: Dictionary) -> void:
	if not enabled or not actors.has(int(value.get("peer",0))):
		return # A late avatar spawn receives holds via snapshots, never stale gestures.
	var actor: Node = actors[int(value["peer"])]
	if not actor.apply_accepted(value):
		return
	if value.get("kind","") in ["insert","remove"]:
		var key = "%d:%d:%d" % [value["station"],value["cable"],value["end"]]
		motions[key] = {"actor":actor,"sequence":value["sequence"]}
		set_process(true)

func reconcile(snapshot: Dictionary) -> void:
	bindings = _live_bindings()
	var held = {}
	var stations: Array = [snapshot] + snapshot.get("stations",[])
	for station in range(stations.size()):
		for cable in stations[station].get("cables",[]):
			var peer = int(cable.get("owner",0))
			if peer > 0 and (cable.get("a","") == "" or cable.get("b","") == ""):
				held[peer] = {"station":station,"cable":int(cable["id"]),"end":0 if cable["a"] == "" else 1}
	for peer in actors:
		actors[peer].reconcile_hold(held.get(peer,{}))
		var event: Dictionary = actors[peer].timeline.event
		if int(event.get("cable",-1)) >= 0:
			var station = int(event.get("station",-1))
			var cable = Events.cable(stations[station],int(event["cable"])) if station>=0 and station<stations.size() else {}
			if cable.is_empty():
				actors[peer].cancel()
			elif event.get("kind","") in ["insert","remove"]:
				var field = "a" if int(event.get("end",-1))==0 else "b"
				var expected = str(event.get("port","")) if event["kind"]=="insert" else ""
				if str(cable[field]) != expected:
					actors[peer].cancel()

func carried_position(peer: int, fallback: Vector3, station: int, cable: int) -> Vector3:
	if enabled and actors.has(peer):
		var actor: Node = actors[peer]
		var anchor: Vector3 = actor.hand_anchor(Transform3D(Basis.IDENTITY,fallback)).origin
		var event: Dictionary = actor.timeline.event
		if actor.timeline.active() and event.get("kind","") == "remove" and int(event.get("station",-1)) == station and int(event.get("cable",-1)) == cable:
			# The accepted disconnect already happened. Only the rendered cable/plug
			# travels from the socket face into the hand; its hit body stays canonical.
			var start: Vector3 = event["target"] + Vector3.BACK*0.08
			var transfer: float = actor.timeline.sample()["transfer"]
			return start.lerp(anchor,transfer*transfer*(3.0-2.0*transfer))
		return anchor
	return fallback

func bind_connector(mesh: Node3D, station: int, cable: int, end: int) -> void:
	# Register only existing render meshes, NEVER hit bodies or circuit objects.
	bindings[mesh.get_instance_id()] = {"mesh":weakref(mesh),"base":mesh.transform,"key":"%d:%d:%d" % [station,cable,end]}

func set_enabled(value: bool) -> void:
	enabled = value
	for actor in actors.values():
		actor.set_enabled(value)
	if not value:
		_clear_connectors()

func facility_event(peer: int, state: Dictionary) -> void:
	var activity = str(state.get("activity",""))
	if activity in ["idle","seat","emote","exercise"]:
		facility_activities[peer] = activity != "idle"
	if peer==multiplayer.get_unique_id():
		facility_food.erase(peer)
	elif state.has("held"):
		var food: Dictionary = state["held"]
		facility_food[peer] = not food.is_empty() and str(food.get("station","")) == ""
	elif activity == "holding":
		facility_food[peer] = true
	set_actor_suspended(peer,bool(facility_activities.get(peer,false)) or bool(facility_food.get(peer,false)))

func set_actor_suspended(peer: int, value: bool) -> void:
	if actors.has(peer):
		actors[peer].set_suspended(value)

func set_local_item_held(value: bool) -> void:
	if is_instance_valid(local_actor):local_actor.set_carrying_item(value)

func cancel_actor(peer: int) -> void:
	if actors.has(peer):
		actors[peer].cancel()

func remove_actor(peer: int) -> void:
	# Game may remove an obsolete remote avatar whose ID has become local.
	# Local lifetime is owned by bind_local/session_transition, never this hook.
	if actors.get(peer)==local_actor and is_instance_valid(local_actor):
		return
	facility_activities.erase(peer)
	facility_food.erase(peer)
	if actors.has(peer):
		actors[peer].reset()
		_drop_motions_for_actor(actors[peer])
		actors[peer].queue_free()
		actors.erase(peer)
	
func reset() -> void:
	facility_activities.clear()
	facility_food.clear()
	for actor in actors.values():
		actor.reset()
	if is_instance_valid(local_actor) and not actors.values().has(local_actor):
		local_actor.reset()
	_clear_connectors()

func _clear_connectors() -> void:
	for binding in bindings.values():
		var mesh = binding["mesh"].get_ref()
		if is_instance_valid(mesh):
			mesh.transform = binding["base"]
	motions.clear()
	bindings = _live_bindings()
	set_process(false)

func _process(_delta: float) -> void:
	for id in bindings.keys():
		var binding: Dictionary = bindings[id]
		var mesh = binding["mesh"].get_ref()
		if not is_instance_valid(mesh):
			bindings.erase(id)
			continue
		mesh.transform = binding["base"]
		if motions.has(binding["key"]):
			var motion: Dictionary = motions[binding["key"]]
			var actor: Node = motion["actor"]
			if is_instance_valid(actor) and int(actor.timeline.event.get("sequence",-1)) == int(motion["sequence"]) and actor.timeline.active():
				# All current bench sockets face world +Z. No authoritative endpoint moves.
				mesh.global_position += Vector3.BACK * float(actor.timeline.sample()["connector"])
	for key in motions.keys():
		var actor: Node = motions[key]["actor"]
		if not is_instance_valid(actor) or not actor.timeline.active() or int(actor.timeline.event.get("sequence",-1)) != int(motions[key]["sequence"]):
			motions.erase(key)
	if motions.is_empty():
		_clear_connectors()

func _live_bindings() -> Dictionary:
	var live = {}
	for id in bindings:
		if bindings[id]["mesh"].get_ref() != null:
			live[id] = bindings[id]
	return live

func _drop_motions_for_actor(actor: Node) -> void:
	for key in motions.keys():
		if motions[key]["actor"]==actor:
			motions.erase(key)
	if motions.is_empty():
		_clear_connectors()
