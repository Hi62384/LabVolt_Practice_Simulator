extends Node3D
const MatPose=preload("res://scripts/campus/facilities/gym_mat_pose.gd")
const Bench=preload("res://scripts/campus/facilities/gym_bench.gd")
## Cosmetic only. Parent this beside the avatar; bind_visual(toon_or_imported_visual).
## Never changes player root, collision, camera, authoritative pose, or movement speed.
var visual: Node3D
var original := Transform3D.IDENTITY
var arms:={}
var legs:={}
var torso: Node3D
var torso_original:=Transform3D.IDENTITY
var smooth_phase:=0.0
var state:={}
var elapsed:=0.0
var food: Node3D
var exit_pose := {}
# Hand targets in avatar space. X is mirrored around the body center.
const CABLE_REACH := {
	"cable_fly":[Vector3(.65,1.24,.10),Vector3(.08,1.22,.50)],
	"cable_reverse_fly":[Vector3(.12,1.16,.48),Vector3(.64,1.24,.06)],
	"cable_press":[Vector3(.32,1.10,.20),Vector3(.21,1.23,.53)],
	"lat_pulldown":[Vector3(.38,1.71,.14),Vector3(.38,1.18,.22)],
	"cable_row":[Vector3(.22,1.03,.54),Vector3(.22,1.08,.21)],
	"lateral_raise":[Vector3(.26,.80,.12),Vector3(.69,1.23,.10)],
	"front_raise":[Vector3(.24,.81,.12),Vector3(.24,1.26,.54)],
	"overhead_press":[Vector3(.27,1.28,.19),Vector3(.26,1.76,.11)],
	"curl":[Vector3(.25,.81,.13),Vector3(.25,1.19,.26)],
	"tricep_pushdown":[Vector3(.24,1.24,.28),Vector3(.24,.83,.15)],
	"overhead_extension":[Vector3(.22,1.51,-.14),Vector3(.22,1.76,.14)],
	"cable_crunch":[Vector3(.20,1.55,.18),Vector3(.20,1.54,.23)]
}
var squat_bend=preload("res://scripts/campus/facilities/squat_bend.gd").new()
var arm_bend=preload("res://scripts/campus/facilities/arm_bend.gd").new()

func bind_visual(node: Node3D) -> void:
	_release_animation()
	restore()
	visual=node;original=node.transform;arms.clear();legs.clear()
	torso=visual.get_node_or_null("Body") as Node3D
	if is_instance_valid(torso):torso_original=torso.transform
	set_process(false)
	for name in ["ArmL","ArmR"]:
		var arm:=visual.find_child(name,true,false) as Node3D
		if arm:arms[name]={"node":arm,"transform":arm.transform}
	for name in ["LegL","LegR"]:
		var leg:=visual.find_child(name,true,false) as Node3D
		if leg:legs[name]={"node":leg,"transform":leg.transform}

func detach_visual() -> void:
	restore()
	_release_animation()
	visual=null;torso=null;arms.clear();legs.clear();set_process(false)

func apply_event(value: Dictionary, show_food: bool) -> void:
	if show_food:
		if value.has("held"):
			set_food(value.held)
		elif value.get("activity","")=="holding":
			set_food({"item":value.get("item",""),"station":""})
	if value.get("activity","") in ["holding","consume","place","pickup"]:return
	if value.get("activity","")=="exercise_exit":
		state=value.duplicate(true)
		elapsed=0.0
		exit_pose.clear()
		if is_instance_valid(visual):
			exit_pose.root=visual.transform
			exit_pose.torso=torso.transform if is_instance_valid(torso) else torso_original
			for key in arms:exit_pose[key]=arms[key].node.transform
			for key in legs:exit_pose[key]=legs[key].node.transform
		_hold_animation()
		set_process(true)
		return
	if value.get("activity","") in ["exercise","trapped"] and value.get("activity","")==state.get("activity","") and value.get("station","")==state.get("station","") and value.get("exercise","")==state.get("exercise",""):
		state=value.duplicate(true);return
	_release_animation()
	restore()
	state=value.duplicate(true);elapsed=0
	if (state.get("activity","") in ["exercise","trapped"] and state.get("exercise","") in ["squat","crunch"]) or state.has("bench_position"):squat_bend.bind(legs)
	if state.get("activity","")=="exercise" and state.get("exercise","") in ["curl","wrist_curl","overhead_extension","tricep_pushdown","pullup","dip","upright_row","cable_row","pushup","pike_pushup","benchpress","incline_press","overhead_press","bent_over_row","chest_supported_row","crunch"]:arm_bend.bind(arms)
	if state.get("activity", "") in ["exercise", "trapped", "spotting", "assist", "spot_assist", "emote"]:
		_hold_animation()
	smooth_phase=_lowered_phase()
	set_process(not state.get("activity","idle") in ["idle",""])

func set_food(held: Dictionary) -> void:
	if is_instance_valid(food):food.queue_free()
	food=null
	if not is_instance_valid(visual) or held.is_empty() or str(held.get("station",""))!="":return
	food=preload("res://scripts/campus/facilities/food_visual.gd").build(str(held.item),int(held.get("servings",4)),held.get("recipe",{}))
	food.name="FacilityFood";visual.add_child(food)
	food.position=Vector3(0.35,.98,-0.3)

func restore() -> void:
	squat_bend.restore()
	arm_bend.restore()
	if is_instance_valid(visual) and visual.has_meta(&"dorm_rest_pose"):return
	if is_instance_valid(visual):visual.transform=original
	if is_instance_valid(torso):torso.transform=torso_original
	for arm in arms.values():
		if is_instance_valid(arm.node):arm.node.transform=arm.transform
	for leg in legs.values():
		if is_instance_valid(leg.node):leg.node.transform=leg.transform

func _hold_animation() -> void:
	if not is_instance_valid(visual):return
	visual.set_meta("facility_activity_pose", true)
	for child in visual.find_children("*", "AnimationPlayer", true, false):
		(child as AnimationPlayer).pause()

func _release_animation() -> void:
	if is_instance_valid(visual) and visual.has_meta("facility_activity_pose"):
		visual.remove_meta("facility_activity_pose")

func _process(delta: float) -> void:
	if is_instance_valid(visual) and visual.has_meta(&"dorm_rest_pose"):return
	if not is_instance_valid(visual):set_process(false);return
	elapsed+=delta
	if state.get("activity","")=="exercise_exit":
		_animate_exit()
	elif state.get("activity","")=="emote":
		var emote:=str(state.get("emote","wave"))
		if elapsed*1000>int(state.get("duration_ms",1800)):
			restore();_release_animation();set_process(false);return
		for key in arms:
			if emote=="wave" and key!="ArmR":continue
			var arm: Node3D=arms[key].node
			arm.transform=arms[key].transform
			arm.rotation.z+=(1 if key=="ArmR" else -1)*(2.2+sin(elapsed*8)*0.22)
		# Imported visuals may lack named arm nodes: a small stationary torso turn is visible.
		if arms.is_empty():visual.rotation.y=original.basis.get_euler().y+sin(elapsed*8)*0.1
	elif state.get("activity","") in ["spotting","assist","spot_assist"]:
		if state.get("activity","") in ["assist","spot_assist"] and elapsed*1000>int(state.get("duration_ms",1800)):
			restore();_release_animation();set_process(false);return
		var effort:=sin(elapsed*7.0)*.10 if state.get("activity","") in ["assist","spot_assist"] else 0.0
		for arm in arms.values():
			arm.node.transform=arm.transform;arm.node.rotation.x=-.65+effort
	elif state.get("activity","") in ["exercise","trapped"]:
		var phase:=_lowered_phase()
		var duration:=maxf(.1,float(state.get("half_ms",700))/1000.0)
		smooth_phase=move_toward(smooth_phase,phase,delta/duration)
		phase=smooth_phase
		var kind:=str(state.get("exercise",""))
		var raised := 1.0-phase
		var target:=original
		# Bounded cosmetic offsets, never a new world position or traversal capability.
		if kind=="pushup":
			# The avatar faces local +Z. Tilt forward into a prone position;
			# rotating backwards made push-ups face the ceiling.
			target.basis=original.basis.rotated(Vector3.RIGHT,1.19+phase*.26)
			target.origin.y+=.025
		elif kind in ["crunch","leg_raise"]:
			target.basis=original.basis.rotated(Vector3.RIGHT,-1.35)
			target.origin.y-=.05
		elif kind=="squat":target.origin.y-=phase*0.3
		elif kind=="calf_raise":target.origin.y+=raised*.12
		elif kind in ["pullup","hanging_leg_raise","dip"]:target.origin.y+=raised*.2 if kind!="hanging_leg_raise" else .18
		elif kind=="benchpress":target.basis=original.basis.rotated(Vector3.RIGHT,-0.8)
		var on_bench: bool=state.get("bench_position") is Vector3
		if on_bench:
			var posture:=Bench.body_pose(kind,original.basis.get_scale().y)
			var bench_target: Vector3=state.bench_position+posture.origin
			visual.global_position=visual.global_position.lerp(bench_target,minf(delta*5.0,1.0))
			var current_basis:=visual.global_basis
			visual.global_basis=current_basis.orthonormalized().slerp(posture.basis,minf(delta*5.0,1.0)).scaled(current_basis.get_scale())
		elif state.get("mat_position") is Vector3:
			# Move only the rendered avatar onto the mat, keeping its collision and
			# authoritative player position in the aisle.
			var pitch:=lerpf(1.40,1.53,phase) if kind=="pushup" else .53 if kind=="pike_pushup" else -PI*.5
			var desired_basis:=Basis(Vector3.RIGHT,pitch)
			var mat_target: Vector3=MatPose.hips(state.mat_position,kind,phase)-desired_basis*Vector3.UP*.86*original.basis.get_scale().y
			visual.global_position=visual.global_position.lerp(mat_target,minf(delta*5.0,1.0))
			var current_basis:=visual.global_basis
			visual.global_basis=current_basis.orthonormalized().slerp(desired_basis,minf(delta*8.0,1.0)).scaled(current_basis.get_scale())
		elif state.get("grip_anchor") is Vector3:
			visual.basis=original.basis
			visual.global_rotation.y=0.0
		elif state.get("cable_stance") is Vector3:
			visual.global_position=visual.global_position.lerp(state.cable_stance,minf(delta*5.0,1.0))
			var direction: Vector3=state.machine_position-visual.global_position if state.get("machine_position") is Vector3 else Vector3.FORWARD
			var yaw:=visual.global_basis.orthonormalized().get_euler().y
			if direction.x*direction.x+direction.z*direction.z>.0001:
				yaw=atan2(direction.x,direction.z)
				if kind in ["cable_press","cable_fly","overhead_extension"]:yaw+=PI
			var current_basis:=visual.global_basis
			var pitch:=target.basis.orthonormalized().get_euler().x
			var desired_basis:=Basis.from_euler(Vector3(pitch,yaw,0))
			visual.global_basis=current_basis.orthonormalized().slerp(desired_basis,minf(delta*8.0,1.0)).scaled(current_basis.get_scale())
		else:
			var previous_yaw:=visual.global_rotation.y
			visual.transform=visual.transform.interpolate_with(target,minf(delta*12,1))
			if state.get("machine_position") is Vector3:
				var direction: Vector3=state.machine_position-visual.global_position
				if direction.x*direction.x+direction.z*direction.z>.0001:
					visual.global_rotation.y=lerp_angle(previous_yaw,atan2(direction.x,direction.z),minf(delta*8.0,1.0))
		if is_instance_valid(torso):
			torso.transform=torso_original
			if kind=="pike_pushup" and not on_bench:
				# Keep the legs planted while folding the torso at the hips.
				var bend:=Basis(Vector3.RIGHT,1.84+phase*.28)
				var hip:=Vector3(0,.86,0)
				torso.transform=torso_original*Transform3D(bend,hip-bend*hip)
			elif kind=="crunch" and not on_bench:
				var bend:=Basis(Vector3.RIGHT,.64*raised)
				var hip:=Vector3(0,.86,0)
				torso.transform=torso_original*Transform3D(bend,hip-bend*hip)
			elif kind=="good_morning":
				var bend:=Basis(Vector3.RIGHT,raised*(.48 if on_bench else .85))
				var hip:=Vector3(0,.86,0)
				torso.transform=torso_original*Transform3D(bend,hip-bend*hip)
			elif not on_bench and kind=="cable_crunch":
				var bend:=Basis(Vector3.RIGHT,raised*.48)
				var hip:=Vector3(0,.86,0)
				torso.transform=torso_original*Transform3D(bend,hip-bend*hip)
			elif not on_bench and kind in ["deadlift","romanian_deadlift","bent_over_row","reverse_fly"]:
				# Hinge at the hips while the legs and feet remain planted.
				var bend:=Basis(Vector3.RIGHT,.65 if kind in ["bent_over_row", "reverse_fly"] else .08+raised*.65)
				var hip:=Vector3(0,.86,0)
				torso.transform=torso_original*Transform3D(bend,hip-bend*hip)
		for arm in arms.values():
			arm.node.transform=arm.transform
			if kind=="curl":arm.node.rotation.x=-.55 if on_bench else 0.0
			elif kind=="benchpress" and on_bench:arm.node.rotation.x=-1.64+phase*1.04
			elif kind=="incline_press":arm.node.rotation.x=-1.30-raised*.64
			elif kind in ["benchpress","overhead_press"]:arm.node.rotation.x=-1.14-raised*1.45
			elif kind=="chest_fly" and on_bench:
				# A fly arcs out from above the chest, not down beside the bench.
				arm.node.rotation=Vector3(-1.25,(1 if arm.node.name=="ArmR" else -1)*phase*.9,0)
			elif kind=="chest_fly":arm.node.rotation.z+=(1 if arm.node.name=="ArmR" else -1)*(.25+phase*.9)
			elif kind in ["pullup","hanging_leg_raise","lat_pulldown"]:arm.node.rotation.x=-2.5+(phase*.75 if kind=="lat_pulldown" else 0.0)
			elif kind=="dip":
				arm.node.rotation.x=-.15
				arm.node.rotation.z+=(.42 if arm.node.name=="ArmR" else -.42)
			elif kind=="crunch":
				arm.node.rotation.x=-.68
			elif kind=="leg_raise":arm.node.rotation.x=.14
			elif kind=="pushup":arm.node.rotation.x=-1.20+phase*.71
			elif kind=="pike_pushup":arm.node.rotation.x=-2.10-phase*.20
			elif kind=="squat":
				if state.get("equipment","")=="dumbbell":
					arm.node.rotation.x=-.08
				else:
					arm.node.rotation.x=-.10
					arm.node.rotation.z+=(1 if arm.node.name=="ArmR" else -1)*1.5
			elif kind=="good_morning":
				arm.node.rotation.x=-.10
				arm.node.rotation.z+=(1 if arm.node.name=="ArmR" else -1)*1.5
			elif kind=="front_raise":arm.node.rotation.x=-raised*1.25
			elif kind=="upright_row":
				arm.node.rotation.x=-phase*.22
				arm.node.rotation.z+=(1 if arm.node.name=="ArmR" else -1)*phase*1.25
			elif kind=="cable_press":arm.node.rotation.x=-.8-phase*.65
			elif kind in ["cable_fly","cable_reverse_fly"]:
				arm.node.rotation.x=-1.1
				arm.node.rotation.z+=(1 if arm.node.name=="ArmR" else -1)*(.8-phase*.6 if kind=="cable_fly" else .2+phase*.7)
			elif kind=="tricep_pushdown":arm.node.rotation.x=-.8+phase*.6
			elif kind=="cable_row":arm.node.rotation.x=-.8+phase*.55
			elif kind=="cable_crunch":arm.node.rotation.x=-2.0
			elif kind in ["lateral_raise","reverse_fly"]:arm.node.rotation.z+=(1 if arm.node.name=="ArmR" else -1)*raised*1.15
			elif kind=="overhead_extension":
				# Lift the upper arms beside the head; the forearms supply the
				# extension instead of sweeping the whole arm behind the body.
				arm.node.rotation.x=-3.7 if on_bench or state.get("cable_stance") is Vector3 else -2.8
				# Keep the raised weights clear of the head, including wider styles.
				arm.node.rotation.z+=(.30 if arm.node.name=="ArmR" else -.30)
			elif kind in ["bent_over_row","chest_supported_row"]:arm.node.rotation.x=.28*raised
			elif kind in ["deadlift","romanian_deadlift"]:arm.node.rotation.x=-phase*.5
			elif kind=="shrug":arm.node.position.y+=raised*.08
			elif kind=="wrist_curl":arm.node.rotation.x=-.9 if on_bench else 0.0
			if state.get("activity","")=="trapped":arm.node.rotation.x=-.7+sin(elapsed*7.0)*.12
		for leg in legs.values():
			leg.node.transform=leg.transform
			if on_bench:
				var bench_mode: String=preload("res://scripts/campus/facilities/gym_bench.gd").position_for(kind)
				leg.node.rotation.x=.7 if bench_mode=="flat" else .92 if bench_mode=="incline" else -.75 if bench_mode=="supported" else -1.38
				if bench_mode=="supported":
					var side:=1.0 if leg.node.name=="LegR" else -1.0
					leg.node.position.x+=side*.14
					leg.node.rotation.z=side*.5
			elif kind=="squat":leg.node.rotation.x=0.0
			elif kind=="leg_raise":leg.node.rotation.x= -.08-raised*1.03
			elif kind=="hanging_leg_raise":leg.node.rotation.x=-raised
			elif kind=="crunch":leg.node.rotation.x=-.70
		if kind=="squat":squat_bend.apply(phase if state.get("activity","")=="exercise" else 1.0)
		elif kind=="crunch":squat_bend.apply(1.0,true)
		elif on_bench and preload("res://scripts/campus/facilities/gym_bench.gd").position_for(kind) in ["seated","seated_free"]:squat_bend.apply(1.0,true)
		if state.get("activity","")=="exercise":
			if kind=="curl":arm_bend.apply(1.45*raised,0.0)
			elif kind=="wrist_curl":arm_bend.apply(0.0,-.7*raised)
			elif kind=="overhead_extension":arm_bend.apply(.8*(1.0-phase),0.0)
			elif kind=="tricep_pushdown":arm_bend.apply(.75*(1.0-phase),0.0)
			elif kind=="pullup":arm_bend.apply(-1.45*raised,0.0)
			elif kind=="dip":arm_bend.apply(1.1*phase,0.0)
			elif kind=="upright_row":arm_bend.apply(0.0,0.0,1.25*phase)
			elif kind in ["cable_row","bent_over_row","chest_supported_row"]:arm_bend.apply(1.1*raised,0.0)
			elif kind in ["benchpress","incline_press","overhead_press"]:arm_bend.apply(-.78*phase,0.0)
			elif kind=="crunch":arm_bend.apply(.85,0.0)
			elif kind in ["pushup","pike_pushup"]:arm_bend.apply(.94*phase,0.0)
		if state.get("cable_stance") is Vector3 and CABLE_REACH.has(kind):
			var reach: Array=CABLE_REACH[kind]
			for key in arms:
				var side := -1.0 if key=="ArmL" else 1.0
				var hand_target: Vector3=reach[0].lerp(reach[1],raised)
				if kind in ["cable_fly","cable_reverse_fly"]:hand_target.z+=sin(PI*raised)*.12
				hand_target.x*=side
				var arm: Node3D=arms[key].node
				var frame: Node3D=arm.get_parent() if kind=="cable_crunch" else visual
				_aim_hand(arm,frame.to_global(hand_target),false)
		if state.get("mat_position") is Vector3 and kind in ["pushup","pike_pushup"]:
			for key in arms:
				var arm: Node3D=arms[key].node
				var side: float=-1.0 if key=="ArmL" else 1.0
				_aim_hand(arm,MatPose.palm(state.mat_position,side,kind),true)
				var leg: Dictionary=legs.get("LegL" if key=="ArmL" else "LegR",{})
				if leg.has("node"):
					_aim_end(leg.node,Vector3(0,-.83,.07),MatPose.toes(state.mat_position,side,kind),true)
		if state.get("grip_anchor") is Vector3 and arms.has("ArmL") and arms.has("ArmR"):
			var joints=preload("res://scripts/campus/facilities/arm_bend.gd")
			var left: Node3D=joints.hand_for(arms.ArmL.node)
			var right: Node3D=joints.hand_for(arms.ArmR.node)
			if is_instance_valid(left) and is_instance_valid(right):
				var grip: Vector3=(left.global_position+right.global_position)*.5
				visual.global_position+=state.grip_anchor-grip
				var spacing := .48 if kind=="dip" else .36
				_aim_hand(arms.ArmL.node,state.grip_anchor-Vector3.RIGHT*spacing,true)
				_aim_hand(arms.ArmR.node,state.grip_anchor+Vector3.RIGHT*spacing,true)
	elif state.get("activity","")=="seat":
		if state.get("bench_position") is Vector3:
			var posture:=Bench.body_pose("curl",original.basis.get_scale().y)
			visual.global_position=state.bench_position+posture.origin
			visual.global_basis=posture.basis.scaled(original.basis.get_scale())
			for leg in legs.values():leg.node.rotation.x=-1.38
			squat_bend.apply(1.0,true)
		elif state.has("seat_position"):
			visual.global_position=state.seat_position+Vector3.DOWN*.3
			visual.global_rotation.y=float(state.seat_yaw)
		else:visual.position=original.origin+Vector3(0,-.3,0)

func _lowered_phase() -> float:
	return 1.0-float(state.lift_progress) if state.has("lift_progress") else float(state.get("phase",0.0))

func _aim_hand(arm: Node3D, point: Vector3, fixed_contact: bool) -> void:
	var hand:=arm_bend.hand_for(arm)
	if is_instance_valid(hand):_aim_end(arm,hand.position,point,fixed_contact)

func _aim_end(limb: Node3D, tip: Vector3, point: Vector3, fixed_contact: bool) -> void:
	var current := limb.basis*tip
	var desired: Vector3=limb.get_parent().to_local(point)-limb.position
	if minf(current.length_squared(),desired.length_squared())<.00001:return
	var ratio := desired.length()/current.length()
	if not fixed_contact:ratio=clampf(ratio,.86,1.12)
	limb.basis=(Basis(Quaternion(current.normalized(),desired.normalized()))*limb.basis).scaled(Vector3.ONE*ratio)

func _animate_exit() -> void:
	if exit_pose.is_empty():return
	var time := clampf(elapsed*1000.0/maxf(1.0,float(state.duration_ms)),0.0,1.0)
	if state.has("bench_position") and state.get("equipment")!="dumbbell":
		# Leave time for the supported bar to clear the torso before sitting up.
		time=remap(clampf(time,.22,1.0),.22,1.0,0.0,1.0)
	var blend := smoothstep(0.0,1.0,time)
	var start: Transform3D=exit_pose.root
	var middle := original
	var with_intermediate := true
	if state.get("bench_position") is Vector3:
		# Sit upright over the seat before rising into the aisle.
		middle.origin=visual.get_parent().to_local(state.bench_position+Vector3(0,-.28,.70))
	elif state.get("mat_position") is Vector3:
		# Bring the knees in underneath the body before standing up.
		middle.origin=start.origin.lerp(original.origin,.44)+Vector3.DOWN*.42
		middle.basis=original.basis.rotated(Vector3.RIGHT,.32)
	elif state.get("grip_anchor") is Vector3:
		# Drop to a soft landing with bent knees, then straighten.
		middle.origin=original.origin+Vector3.DOWN*.19
	else:
		with_intermediate=false
	if with_intermediate:
		visual.transform=start.interpolate_with(middle,smoothstep(0.0,.58,time)) if time<.58 else middle.interpolate_with(original,smoothstep(.58,1.0,time))
	else:visual.transform=start.interpolate_with(original,blend)
	if is_instance_valid(torso):
		var body_start: Transform3D=exit_pose.torso
		torso.transform=body_start.interpolate_with(torso_original,blend)
	for key in arms:
		var base: Transform3D=arms[key].transform
		var arm_start: Transform3D=exit_pose[key]
		arms[key].node.transform=arm_start.interpolate_with(base,smoothstep(0.0,.82,time))
	for key in legs:
		var base: Transform3D=legs[key].transform
		var leg_start: Transform3D=exit_pose[key]
		var knee_bend := sin(PI*time)*.64 if with_intermediate else 0.0
		legs[key].node.transform=leg_start.interpolate_with(base,blend)
		legs[key].node.rotation.x-=knee_bend

func _exit_tree() -> void:
	restore()
	_release_animation()
