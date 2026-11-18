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
var workout_arms: Array[Node3D] = []
var workout_state := {}
var workout_phase := 0.0
var workout_camera_home := Transform3D.IDENTITY
var workout_camera_moved := false
var workout_look_origin:=Vector2.ZERO

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

	for arm in workout_arms:
		if is_instance_valid(arm):arm.queue_free()
	workout_arms.clear()
	for side in ["ArmL", "ArmR"]:
		var original := model.find_child(side,true,false) as Node3D
		if is_instance_valid(original):
			var copy := original.duplicate() as Node3D
			game.camera.add_child(copy)
			copy.set_meta("workout_left", side=="ArmL")
			copy.hide()
			workout_arms.append(copy)

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
	if activity in ["idle","seat","emote","exercise","exercise_exit"]:
		facility_activities[peer] = activity != "idle"
	if peer==multiplayer.get_unique_id():
		if activity in ["exercise", "trapped"]:
			workout_state = state.duplicate(true)
			set_process(true)
		elif activity == "exercise_exit":
			workout_state=state.duplicate(true)
			workout_state.return_camera=game.camera.transform
			workout_state.elapsed=0.0
			workout_state.exit_arms={}
			for arm in workout_arms:
				if arm.visible:workout_state.exit_arms[arm]=arm.transform
			set_process(true)
		elif activity == "idle":
			_clear_workout()
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
	_clear_workout()
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
	set_process(not workout_state.is_empty())

func _process(delta: float) -> void:
	_update_workout(delta)
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

func preview_workout(progress: float) -> void:
	if workout_state.get("activity") == "exercise":
		workout_state.phase = 1.0-progress

func _clear_workout() -> void:
	workout_state.clear()
	_restore_workout_camera()
	for arm in workout_arms:
		if is_instance_valid(arm):arm.hide()

func _restore_workout_camera() -> void:
	if workout_camera_moved:
		if is_instance_valid(game.camera):game.camera.transform = workout_camera_home
		if is_instance_valid(game.player):game.player.workout_camera_override = false
	workout_camera_moved = false

func _workout_camera(camera: Camera3D, exercise: String, bar: Node3D, machine: Node3D, raised: float, delta: float) -> void:
	var bench: Variant=workout_state.get("bench_position")
	var mat: Variant=workout_state.get("mat_position")
	var fixed_grip: Variant=workout_state.get("grip_anchor")
	var eye:=Vector3.ZERO
	var target:=Vector3.ZERO
	if is_instance_valid(machine):
		var yaw:=float(workout_state.get("workout_facing",game.player.yaw_target))
		var forward:=Basis(Vector3.UP,yaw)*Vector3.FORWARD
		eye=game.player.global_position+Vector3(0,1.62,0)
		if exercise in ["cable_row","lat_pulldown"]:eye.y-=.30
		target=eye+forward+Vector3(0,-.24,0)
	elif bench is Vector3:
		var mode: String=preload("res://scripts/campus/facilities/gym_bench.gd").position_for(exercise)
		match mode:
			"flat","incline":
				eye=bench+Vector3(0,.83 if mode=="flat" else 1.05,.22)
				target=bar.global_position if is_instance_valid(bar) and workout_state.get("equipment","")!="dumbbell" else bench+Vector3(0,1.42,-.30)
			"supported":
				eye=bench+Vector3(0,1.03,-.23)
				target=eye+Vector3(0,-.40,.75)
			_:
				eye=bench+Vector3(0,1.18,.46)
				target=eye+Vector3(0,-.06,-1)
	elif mat is Vector3 and exercise in ["pushup","pike_pushup"]:
		eye=mat+Vector3(0,lerpf(.36,.53,raised),.42)
		target=mat+Vector3(0,.03,.72)
	elif fixed_grip is Vector3:
		if exercise=="dip":
			eye=fixed_grip+Vector3(0,lerpf(.31,.58,raised),-.16)
			target=fixed_grip+Vector3(0,0,.35)
		else:
			eye=fixed_grip+Vector3(0,lerpf(-.54,-.12,raised),.26)
			target=fixed_grip
	else:
		_restore_workout_camera()
		return
	if not workout_camera_moved:
		workout_camera_home=camera.transform
		workout_camera_moved=true
		workout_look_origin=Vector2(game.player.yaw_target,game.player.pitch_target)
		game.player.workout_camera_override=true
	var head_look:=Vector2(clampf(wrapf(game.player.yaw_target-workout_look_origin.x,-PI,PI),-.28,.28),clampf(game.player.pitch_target-workout_look_origin.y,-.21,.21))
	var aim:=Basis.looking_at((target-eye).normalized(),Vector3.UP)*Basis.from_euler(Vector3(head_look.y,head_look.x,0))
	var desired:=Transform3D(aim,eye)
	camera.global_transform=camera.global_transform.interpolate_with(desired,1.0 if game.player.reduced_motion else minf(delta*6.0,1.0))

func _cable_grip(movement: String, side: float, raised: float) -> Vector3:
	var start:=Vector3(side*.24,-.28,-.54)
	var end:=Vector3(side*.21,-.12,-.67)
	match movement:
		"cable_fly":
			start=Vector3(side*.62,-.12,-.46)
			end=Vector3(side*.08,-.14,-.78)
		"cable_reverse_fly":
			start=Vector3(side*.12,-.22,-.72)
			end=Vector3(side*.62,-.12,-.46)
		"cable_press":
			start=Vector3(side*.29,-.25,-.36)
			end=Vector3(side*.21,-.14,-.76)
		"lat_pulldown":
			start=Vector3(side*.22,.31,-.62)
			end=Vector3(side*.22,-.23,-.40)
		"cable_row":
			start=Vector3(side*.22,-.34,-.77)
			end=Vector3(side*.22,-.28,-.38)
		"lateral_raise":
			start=Vector3(side*.21,-.52,-.51)
			end=Vector3(side*.60,-.13,-.52)
		"front_raise":
			start=Vector3(side*.24,-.49,-.51)
			end=Vector3(side*.24,.01,-.77)
		"overhead_press","overhead_extension":
			start=Vector3(side*.24,-.18,-.47)
			end=Vector3(side*.24,.32,-.62)
		"curl":
			start=Vector3(side*.22,-.44,-.56)
			end=Vector3(side*.22,-.01,-.46)
		"tricep_pushdown":
			start=Vector3(side*.22,-.10,-.52)
			end=Vector3(side*.22,-.46,-.61)
		"cable_crunch":
			start=Vector3(side*.22,.13,-.45)
			end=Vector3(side*.22,-.23,-.50)
	return start.lerp(end,raised)

func _update_workout(delta: float) -> void:
	if workout_state.is_empty():
		return
	var camera: Camera3D = game.camera
	if workout_state.get("activity")=="exercise_exit":
		workout_state.elapsed+=delta
		var progress := smoothstep(0.0,maxf(.1,float(workout_state.duration_ms)/1000.0),float(workout_state.elapsed))
		if workout_camera_moved:
			var start: Transform3D=workout_state.return_camera
			camera.transform=start.interpolate_with(workout_camera_home,progress)
		for arm in workout_arms:
			if not workout_state.exit_arms.has(arm) or progress>.75:
				arm.hide()
				continue
			var start: Transform3D=workout_state.exit_arms[arm]
			var release := smoothstep(0.0,.75,progress)
			arm.transform=start.translated(Vector3(0,-.6,.08)*release)
		return
	var active: bool = enabled and game.front.in_game and game.player.enabled and not game.health.death_screen.visible
	var exercise := str(workout_state.get("exercise",""))
	var pinned: bool = workout_state.get("activity") == "trapped"
	var target_phase := 1.0-float(workout_state.lift_progress) if workout_state.has("lift_progress") else float(workout_state.get("phase",0.0))
	workout_phase = move_toward(workout_phase, target_phase, delta * 3.75)
	var raised := 1.0-workout_phase
	var station := str(workout_state.get("station", ""))
	var machine: Node3D = game.campus_services._cable_machine(station) if station.begins_with("gym/cable_") else null
	var bar: Node3D = game.campus_services.gym_motion.bars.get(station)
	if active:_workout_camera(camera,exercise,bar,machine,raised,delta)
	else:_restore_workout_camera()
	if active and is_instance_valid(machine):
		var yaw:=float(workout_state.get("workout_facing",game.player.yaw_target))
		var base:=Basis.from_euler(Vector3(-.24,yaw,0))
		var eye: Vector3=game.player.global_position+Vector3(0,1.62,0)
		if exercise in ["cable_row","lat_pulldown"]:eye.y-=.30
		machine.position_local_grips(game.multiplayer.get_unique_id(),eye+base*_cable_grip(exercise,-1,raised),eye+base*_cable_grip(exercise,1,raised))
	var handheld_bar: Node3D = game.gym_barbells.bar_hand
	var pair: Node3D = game.gym_weights.held_visual
	for arm in workout_arms:
		arm.visible = active
		if not active:
			continue
		var left := bool(arm.get_meta("workout_left",false))
		var side := -1.0 if left else 1.0
		var shoulder := Vector3(side*.34,-.46,-.15)
		var grip := Vector3(side*.22, -.28, -.58)
		if pinned:
			grip.y = -.14 + float(workout_state.get("progress",0.0))*.20
		elif exercise in ["benchpress","incline_press","overhead_press","pushup","pike_pushup"]:
			grip.y += raised*.31
			grip.z -= raised*.14
		elif exercise in ["curl","overhead_extension","wrist_curl","lat_pulldown","cable_row","bent_over_row"]:
			grip.y += raised*.22
			grip.z += raised*.15
		else:
			grip.y += raised*.15
		var fixed_grip: Variant=workout_state.get("grip_anchor")
		var mat: Variant=workout_state.get("mat_position")
		if fixed_grip is Vector3:
			grip=camera.to_local(fixed_grip+Vector3(side*(.48 if exercise=="dip" else .36),0,0))
		elif mat is Vector3 and exercise in ["pushup","pike_pushup"]:
			grip=camera.to_local(mat+Vector3(side*.27,.035,.49))
		if is_instance_valid(machine):
			var grip_node: Node3D = machine.second_handle if not left and machine.second_handle.visible else machine.handle
			var offset := Vector3.ZERO if machine.second_handle.visible else Vector3(side*.22,0,0)
			var actual := camera.to_local(grip_node.to_global(offset))
			grip = actual
		elif is_instance_valid(bar):
			var actual := camera.to_local(bar.to_global(Vector3(side*.27,0,0)))
			grip = actual
		elif is_instance_valid(pair) and workout_state.get("equipment") == "dumbbell":
			var weight := pair.get_node_or_null("LeftDumbbell" if left else "RightDumbbell") as Node3D
			if weight:
				match exercise:
					"curl":
						var elbow:=Vector3(side*.31,-.62,-.26)
						var arc:=lerpf(.20,2.15,raised)
						grip=elbow+Vector3(0,-cos(arc),-sin(arc))*.30
						weight.rotation=Vector3(arc-PI*.5,PI*.5,0)
					"lateral_raise":
						var arc:=lerpf(.15,PI*.48,raised)
						grip=shoulder+Vector3(side*sin(arc),-cos(arc),-.16)*.55
						weight.rotation=Vector3(0,0,side*arc)
					"front_raise":
						var arc:=lerpf(.12,PI*.53,raised)
						grip=shoulder+Vector3(0,-cos(arc),-sin(arc))*.55
						weight.rotation=Vector3(arc,0,0)
					"overhead_press","incline_press","benchpress":
						grip=Vector3(side*.29,lerpf(-.24,.25,raised),lerpf(-.39,-.50,raised))
						weight.rotation=Vector3(0,PI*.5,0)
					"bent_over_row","chest_supported_row","cable_row":
						grip=Vector3(side*.24,lerpf(-.66,-.39,raised),lerpf(-.64,-.34,raised))
						weight.rotation=Vector3.ZERO
				weight.position=grip
		elif is_instance_valid(handheld_bar) and workout_state.get("equipment") == "barbell":
			handheld_bar.position=Vector3(0,grip.y,grip.z)
			grip=camera.to_local(handheld_bar.to_global(Vector3(side*.26,0,0)))
		_pose_gym_arm(arm,shoulder,grip)

func render_idle_gym_hold(bar: Node3D, dumbbells: Node3D) -> void:
	if not workout_state.is_empty():return
	for arm in workout_arms:
		var left: bool=arm.get_meta("workout_left",false)
		var side: float=-1.0 if left else 1.0
		var grip:=Vector3.INF
		if is_instance_valid(bar) and bar.visible:
			grip=game.camera.to_local(bar.to_global(Vector3(side*.48,0,0)))
		elif is_instance_valid(dumbbells) and dumbbells.visible:
			var weight:=dumbbells.get_node_or_null("LeftDumbbell" if left else "RightDumbbell") as Node3D
			if is_instance_valid(weight):grip=game.camera.to_local(weight.global_position)
		arm.visible=enabled and grip.is_finite()
		if arm.visible:_pose_gym_arm(arm,Vector3(side*.34,-.46,-.15),grip)

func _pose_gym_arm(arm: Node3D, shoulder: Vector3, grip: Vector3) -> void:
	var hand := arm.find_child("Hand*",true,false) as Node3D
	if not is_instance_valid(hand):return
	var reach := grip-shoulder
	if reach.length_squared() < .001:return
	var rotation := Basis(Quaternion(hand.position.normalized(), reach.normalized()))
	var length_scale := clampf(reach.length()/maxf(hand.position.length(),.01), .72, 1.24)
	rotation.x *= .82
	rotation.y *= length_scale
	rotation.z *= .82
	arm.transform = Transform3D(rotation,grip-rotation*hand.position)

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
