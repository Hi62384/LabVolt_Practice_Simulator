extends SceneTree
## SOURCE-ONLY candidate. Actual Godot execution requires a fresh exact root lease.
## Domain input below is a deterministic test fixture, not device/student evidence.
const State = preload("res://scripts/lab_state.gd")
const Events = preload("res://scripts/interaction_presentation/accepted_event.gd")
const Timeline = preload("res://scripts/interaction_presentation/timeline.gd")
const Actor = preload("res://scripts/interaction_presentation/actor.gd")
const Bridge = preload("res://scripts/interaction_presentation/bridge.gd")
const Avatar = preload("res://scripts/avatar_model.gd")
class LocalGame extends Node:
	var camera: Camera3D

var failures: int = 0
var checks: int = 0
var sequence: int = 0
var last_error: String = ""
var state = State.new()

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("HANDS_ADMISSION_FAIL: "+label)

func domain() -> Dictionary:
	# Includes real electrical topology/settings/ownership, excluding cosmetic state.
	var s: Dictionary = state.snapshot()
	var value: Dictionary = {}
	for key in ["cables","switches","powered","level","frequency","dyn_load"]:
		value[key] = s[key]
	return value.duplicate(true)

func host_action(action: Dictionary, at: Vector3 = Vector3.ZERO, peer: int = 2) -> Dictionary:
	# Mirrors ONLY the proposed Session success boundary; real Session/RPC hook
	# compilation and transport remain separate integrator checks.
	var before: Dictionary = state.snapshot()
	last_error = state.act(peer,action,at,false)
	if last_error != "":
		return {}
	sequence += 1
	return Events.project(peer,0,action,before,state.snapshot(),state.positions,sequence)

func run() -> void:
	state.initialize(["P_A","P_N"],{"P_A":Vector3(0,1,0),"P_N":Vector3(1,1,0),"storage":Vector3.ZERO,"variable":Vector3.ZERO,"R_0":Vector3.ZERO})
	host_action({"op":"drawer"})
	var grasp: Dictionary = host_action({"op":"pickup","color":0})
	check(last_error=="" and grasp.get("kind","")=="grasp","A1 real host pickup projects grasp")
	var first: Dictionary = host_action({"op":"plug","port":"P_A"})
	check(first.get("kind","")=="insert" and int(first.get("end",-1))==0,"A2 first insertion from actual diff")
	var second: Dictionary = host_action({"op":"plug","port":"P_N"})
	check(second.get("kind","")=="insert" and state.completed().size()==1,"A3 topology commits before animation")
	check(state.holding(2).is_empty(),"A4 completed connection releases owner")
	var installed: Dictionary = domain()
	var rejected: Dictionary = host_action({"op":"plug","port":"P_A"})
	check(last_error!="" and rejected.is_empty() and domain()==installed,"R1 no held cable rejects without electrical/cosmetic change")
	rejected = host_action({"op":"unplug","port":"P_N"},Vector3(99,0,0))
	check(last_error!="" and rejected.is_empty() and domain()==installed,"R2 reach rejection cannot animate or disconnect")
	var removal: Dictionary = host_action({"op":"unplug","port":"P_N"})
	check(last_error=="" and removal.get("kind","")=="remove" and state.completed().is_empty(),"A5 accepted disconnect commits before presentation")

	# Instantiate current default-avatar art in headless memory. No camera, viewport
	# capture, editor import, native host, OS process API, multiplayer or audio.
	var model: Node3D = Avatar.build(FileAccess.get_file_as_bytes("res://assets/default_avatar.glb"))
	check(model!=null,"G1 existing default GLB builds")
	if model==null:
		finish()
		return
	root.add_child(model)
	var original_root: Transform3D = model.transform
	var bridge = Bridge.new()
	root.add_child(bridge)
	bridge.attach(root)
	bridge.bind_avatar(2,model)
	bridge.reconcile(state.snapshot())
	var actor: Node = bridge.actors[2]
	check(is_instance_valid(actor.arm) and is_instance_valid(actor.hand),"G2 existing ArmR and Hand binding")
	if not is_instance_valid(actor.arm):
		bridge.free()
		model.free()
		finish()
		return
	var rest: Transform3D = actor.arm.transform
	var disconnected: Dictionary = domain()
	bridge.accepted(removal)
	actor._process(0.15)
	check(model.transform.is_equal_approx(original_root),"G3 root/locomotion transform unchanged")
	check(domain()==disconnected,"C1 animation cannot mutate actual host state")
	var fallback: Vector3 = Vector3(0.2,1.2,-0.3)
	var bounded: Transform3D = actor.hand_anchor(Transform3D(Basis.IDENTITY,fallback))
	check(bounded.origin.distance_to(fallback)<=0.18001,"G4 ordinary hand anchor bounded to 0.18m")
	bridge.cancel_actor(2)
	bridge._process(0.0)
	check(actor.timeline.event.is_empty() and not actor.timeline.hold.is_empty(),"C2 cancel clears transient event and retains snapshot hold")
	check(actor.arm.transform.is_equal_approx(rest) and domain()==disconnected,"C3 cancel restores arm without reconnecting lead")
	check(not actor.apply_accepted(removal),"C4 cancel cannot replay old sequence")

	# Real host release/re-grab models snapshot rebaseline; does not claim live
	# reconnect transport coverage. No past transient is reapplied.
	state.release(2)
	bridge.reset()
	bridge.reconcile(state.snapshot())
	check(actor.timeline.hold.is_empty() and actor.timeline.event.is_empty(),"N1 owner release resets presentation")
	var loose: Dictionary = state.cables[0]
	host_action({"op":"grab","id":int(loose["id"])})
	check(last_error=="","N2 actual host re-grab accepts")
	bridge.reconcile(state.snapshot())
	check(not actor.timeline.hold.is_empty() and actor.timeline.event.is_empty(),"N3 snapshot restores hold without replay")
	check(actor.is_processing(),"N4 held pose reactivates after reset")

	# Actual rapid host voltage actions; simulated deltas advance only cosmetics.
	var level_before: float = state.level
	var revision_before: int = state.revision
	for i in range(20):
		var knob: Dictionary = host_action({"op":"voltage","delta":0.008})
		check(last_error=="" and knob.get("kind","")=="knob","K1 real rapid knob accepted %d"%i)
		bridge.accepted(knob)
		actor._process(0.035)
	check(is_equal_approx(state.level,level_before+0.16) and state.revision==revision_before+20,"K2 host timing independent of animation")
	check(float(actor.timeline.sample()["reach"])>0.9 and float(actor.timeline.sample()["twist"])>0.05,"K3 fast updates cannot starve knob contact")
	var stable: Dictionary = domain()
	actor._process(1.0)
	check(actor.timeline.event.is_empty() and domain()==stable,"K4 finite gesture completion without extra electrical work")
	var switch_event: Dictionary = host_action({"op":"switch","kind":"R","index":0,"expected":false})
	check(last_error=="" and switch_event.get("kind","")=="switch","R3 real compare-and-set switch accepts")
	stable = domain()
	rejected = host_action({"op":"switch","kind":"R","index":0,"expected":false})
	check(last_error!="" and rejected.is_empty() and domain()==stable,"R4 stale switch rejects with no invented gesture")
	bridge.set_enabled(false)
	check(not actor.is_processing() and domain()==stable,"C5 display off has no electrical effect")
	bridge.reset()
	check(actor.timeline.event.is_empty() and actor.timeline.hold.is_empty(),"N5 reset clears stale sequence and carry state")
	bridge.free()
	model.free()
	run_identity_and_unsupported()
	finish()

func finish() -> void:
	print("HANDS_ADMISSION_V1_2 checks=",checks," failures=",failures)
	quit(1 if failures>0 else 0)

func run_identity_and_unsupported() -> void:
	var model: Node3D = Avatar.build(FileAccess.get_file_as_bytes("res://assets/default_avatar.glb"))
	var remote_model: Node3D = Avatar.build(FileAccess.get_file_as_bytes("res://assets/default_avatar.glb"))
	check(model!=null and remote_model!=null,"I0 real GLB art available for identity transition")
	if model==null or remote_model==null:
		if model!=null:model.free()
		if remote_model!=null:remote_model.free()
		return
	root.add_child(model)
	root.add_child(remote_model)
	var game = LocalGame.new()
	root.add_child(game)
	game.camera = Camera3D.new()
	game.add_child(game.camera)
	var bridge = Bridge.new()
	root.add_child(bridge)
	bridge.attach(game)
	bridge.bind_local(model)
	var local: Node = bridge.local_actor
	var local_arm: Node3D = local.arm
	var camera_before: Transform3D = game.camera.transform
	var model_before: Transform3D = model.transform
	var remote_before: Transform3D = remote_model.transform
	check(bridge.local_peer==1 and bridge.actors.get(1)==local,"I1 offline first-person actor keyed at actual initial ID")
	# Explicit deterministic transport-ID inputs exercise the module lifecycle API;
	# they do not claim that a network connection or real joined peer was created.
	bridge.set_local_peer(7)
	check(not bridge.actors.has(1) and bridge.actors.get(7)==local,"I2 joined-ID rekey removes old local alias")
	check(bridge.bind_avatar(1,remote_model),"I3 host ID 1 can bind a separate remote actor after join")
	var host_actor: Node = bridge.actors[1]
	check(host_actor!=local and local.arm==local_arm and local.local_hand,"I4 remote host cannot repurpose local arm")
	var local_event: Dictionary = host_action({"op":"voltage","delta":0.008},Vector3.ZERO,7)
	check(last_error=="" and int(local_event.get("peer",0))==7,"I5 real domain action for new actor ID projects event")
	bridge.accepted(local_event)
	check(int(local.timeline.event.get("sequence",-1))==int(local_event.get("sequence",-2)),"I6 joined-local event reaches rekeyed first-person actor")
	var local_sequence: int = local.timeline.last_sequence
	var remote_event: Dictionary = host_action({"op":"voltage","delta":0.008},Vector3.ZERO,1)
	bridge.accepted(remote_event)
	check(int(host_actor.timeline.event.get("peer",0))==1 and local.timeline.last_sequence==local_sequence,"I7 remote host event remains separate from local event")
	bridge.remove_actor(7)
	check(bridge.actors.get(7)==local and is_instance_valid(local.arm),"I8 stale remote-avatar cleanup cannot delete current local actor")
	bridge.session_transition()
	check(bridge.local_peer==0 and bridge.actors.is_empty() and bridge.motions.is_empty(),"I9 teardown unbinds all old IDs and connector work")
	check(local.timeline.event.is_empty() and not local.is_processing(),"I10 teardown hides and resets local presentation")
	bridge.set_local_peer(1)
	check(bridge.actors.size()==1 and bridge.actors.get(1)==local and not bridge.actors.has(7),"I11 offline rebind has one local alias and no joined alias")
	check(not bridge.bind_avatar(1,remote_model) and local.arm==local_arm,"I12 local ID blocks remote bind after reconnect")
	bridge.set_local_peer(11)
	check(bridge.actors.get(11)==local and not bridge.actors.has(1),"I13 second join rekeys without accumulated aliases")
	check(game.camera.transform.is_equal_approx(camera_before) and model.transform.is_equal_approx(model_before) and remote_model.transform.is_equal_approx(remote_before),"I14 identity changes preserve camera and avatar roots")
	bridge.free()
	game.free()

	var unsupported = Bridge.new()
	root.add_child(unsupported)
	unsupported.attach(root)
	var empty_rig = Node3D.new()
	root.add_child(empty_rig)
	check(not unsupported.bind_avatar(3,empty_rig),"U1 missing ArmR reports unsupported")
	var unsupported_actor: Node = unsupported.actors[3]
	state.release(2)
	var removal: Dictionary = host_action({"op":"unplug","port":"P_A"},Vector3.ZERO,3)
	check(last_error=="" and removal.get("kind","")=="remove","U2 real host removal remains accepted independently of unsupported art")
	var actual: Dictionary = domain()
	unsupported.accepted(removal)
	check(unsupported_actor.timeline.event.is_empty() and not unsupported_actor.is_processing(),"U3 unsupported removal drops transient instead of retaining active timeline")
	check(unsupported.motions.is_empty() and not unsupported.is_processing() and domain()==actual,"U4 unsupported removal allocates no connector work and cannot mutate domain")
	var insertion: Dictionary = host_action({"op":"plug","port":"P_A"},Vector3.ZERO,3)
	unsupported.accepted(insertion)
	check(last_error=="" and insertion.get("kind","")=="insert" and unsupported.motions.is_empty() and not unsupported.is_processing(),"U5 unsupported insertion also has bounded zero-work cleanup")
	unsupported.bind_avatar(3,model)
	check(not unsupported_actor.apply_accepted(insertion),"U6 supported replacement cannot replay discarded unsupported event")
	var next_removal: Dictionary = host_action({"op":"unplug","port":"P_A"},Vector3.ZERO,3)
	unsupported.accepted(next_removal)
	check(not unsupported.motions.is_empty() and unsupported.is_processing(),"U7 supported real removal initially schedules bounded work")
	unsupported.bind_avatar(3,empty_rig)
	unsupported._process(0.0)
	check(unsupported_actor.timeline.event.is_empty() and unsupported.motions.is_empty() and not unsupported.is_processing(),"U8 mid-gesture unsupported replacement cancels by one cleanup tick")
	actual = domain()
	unsupported.reconcile(state.snapshot())
	unsupported.accepted(next_removal)
	unsupported._process(0.0)
	check(unsupported_actor.timeline.event.is_empty() and not unsupported_actor.is_processing() and not unsupported.is_processing() and domain()==actual,"U9 unsupported retained hold cannot keep a motion alive or change electrical state")
	unsupported.free()
	empty_rig.free()
	model.free()
	remote_model.free()
