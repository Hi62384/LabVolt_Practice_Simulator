extends Node3D
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
	if value.get("activity","") in ["exercise","trapped"] and value.get("activity","")==state.get("activity","") and value.get("station","")==state.get("station","") and value.get("exercise","")==state.get("exercise",""):
		state=value.duplicate(true);return
	_release_animation()
	restore()
	state=value.duplicate(true);elapsed=0
	if state.get("activity","") in ["exercise","trapped"] and state.get("exercise","")=="squat":squat_bend.bind(legs)
	if state.get("activity","")=="exercise" and state.get("exercise","") in ["curl","wrist_curl","overhead_extension","tricep_pushdown","pullup","dip","upright_row","cable_row","pushup","pike_pushup"]:arm_bend.bind(arms)
	if state.get("activity", "") in ["exercise", "trapped", "spotting", "assist", "spot_assist", "emote"]:
		_hold_animation()
	smooth_phase=1.0-float(state.get("phase",0))
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
	if state.get("activity","")=="emote":
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
		var phase:=float(state.get("phase",0))
		var duration:=maxf(.1,float(state.get("half_ms",700))/1000.0)
		smooth_phase=move_toward(smooth_phase,phase,delta/duration)
		phase=smooth_phase
		var kind:=str(state.get("exercise",""))
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
		elif kind=="calf_raise":target.origin.y+=phase*.12
		elif kind in ["pullup","hanging_leg_raise","dip"]:target.origin.y+=phase*.2 if kind!="hanging_leg_raise" else .18
		elif kind=="benchpress":target.basis=original.basis.rotated(Vector3.RIGHT,-0.8)
		var on_bench: bool=state.get("bench_position") is Vector3
		if on_bench:
			var mode: String=preload("res://scripts/campus/facilities/gym_bench.gd").position_for(kind)
			var tilt:=0.0
			var yaw:=0.0
			# Align the hips with the seat for both short and tall avatars.
			var avatar_height:=original.basis.get_scale().y
			var bench_offset:=Vector3(0,.585-.86*avatar_height,0)
			if mode=="flat":
				tilt=-1.50;bench_offset=Vector3(0,.70,.60)
			elif mode=="incline":
				tilt=-.92;bench_offset=Vector3(0,.55,.18)
			elif mode=="supported":
				tilt=.75;yaw=PI;bench_offset=Vector3(0,.35,0)
			var bench_target: Vector3=state.bench_position+bench_offset
			visual.global_position=visual.global_position.lerp(bench_target,minf(delta*5.0,1.0))
			var current_basis:=visual.global_basis
			var desired_basis:=Basis.from_euler(Vector3(tilt,yaw,0))
			visual.global_basis=current_basis.orthonormalized().slerp(desired_basis,minf(delta*5.0,1.0)).scaled(current_basis.get_scale())
		elif state.get("mat_position") is Vector3:
			# Move only the rendered avatar onto the mat, keeping its collision and
			# authoritative player position in the aisle.
			var offset_z:=.85 if kind in ["crunch","leg_raise"] else -.35 if kind=="pike_pushup" else -.85
			var mat_target: Vector3=state.mat_position+Vector3(0,target.origin.y,offset_z)
			visual.global_position=visual.global_position.lerp(mat_target,minf(delta*5.0,1.0))
			var current_basis:=visual.global_basis
			var desired_basis:=Basis.from_euler(Vector3(target.basis.orthonormalized().get_euler().x,0,0))
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
				var bend:=Basis(Vector3.RIGHT,2.10+phase*.20)
				var hip:=Vector3(0,.86,0)
				torso.transform=torso_original*Transform3D(bend,hip-bend*hip+Vector3.DOWN*(.10-.06*phase))
			elif kind=="crunch" and not on_bench:
				var bend:=Basis(Vector3.RIGHT,.3*phase)
				var hip:=Vector3(0,.86,0)
				torso.transform=torso_original*Transform3D(bend,hip-bend*hip)
			elif kind=="good_morning" and on_bench:
				var bend:=Basis(Vector3.RIGHT,.45*phase)
				var hip:=Vector3(0,.86,0)
				torso.transform=torso_original*Transform3D(bend,hip-bend*hip)
			elif not on_bench and kind=="cable_crunch":
				var bend:=Basis(Vector3.RIGHT,phase*.48)
				var hip:=Vector3(0,.86,0)
				torso.transform=torso_original*Transform3D(bend,hip-bend*hip)
			elif not on_bench and kind in ["deadlift","romanian_deadlift","bent_over_row","reverse_fly"]:
				# Hinge at the hips while the legs and feet remain planted.
				var bend:=Basis(Vector3.RIGHT,.15+phase*.55)
				var hip:=Vector3(0,.86,0)
				torso.transform=torso_original*Transform3D(bend,hip-bend*hip)
		for arm in arms.values():
			arm.node.transform=arm.transform
			if kind=="curl":arm.node.rotation.x=-.55 if on_bench else 0.0
			elif kind=="benchpress" and on_bench:arm.node.rotation.x=-1.64+phase*1.04
			elif kind in ["benchpress","incline_press","overhead_press"]:arm.node.rotation.x=-1.2-phase*.85
			elif kind=="chest_fly" and on_bench:
				# A fly arcs out from above the chest, not down beside the bench.
				arm.node.rotation=Vector3(-1.25,(1 if arm.node.name=="ArmR" else -1)*phase*.9,0)
			elif kind=="chest_fly":arm.node.rotation.z+=(1 if arm.node.name=="ArmR" else -1)*(.25+phase*.9)
			elif kind in ["pullup","hanging_leg_raise","lat_pulldown"]:arm.node.rotation.x=-2.5+(phase*.75 if kind=="lat_pulldown" else 0.0)
			elif kind=="dip":
				arm.node.rotation.x=-.15
				arm.node.rotation.z+=(.42 if arm.node.name=="ArmR" else -.42)
			elif kind=="pushup":arm.node.rotation.x=-1.20+phase*.71
			elif kind=="pike_pushup":arm.node.rotation.x=-2.10-phase*.20
			elif kind=="squat":
				if state.get("equipment","")=="dumbbell":
					arm.node.rotation.x=-.08
				else:
					arm.node.rotation.x=-.10
					arm.node.rotation.z+=(1 if arm.node.name=="ArmR" else -1)*1.5
			elif kind=="good_morning" and on_bench:
				arm.node.rotation.x=-.10
				arm.node.rotation.z+=(1 if arm.node.name=="ArmR" else -1)*1.5
			elif kind=="front_raise":arm.node.rotation.x=-phase*1.25
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
			elif kind in ["lateral_raise","reverse_fly"]:arm.node.rotation.z+=(1 if arm.node.name=="ArmR" else -1)*phase*1.15
			elif kind=="overhead_extension":
				# Lift the upper arms beside the head; the forearms supply the
				# extension instead of sweeping the whole arm behind the body.
				arm.node.rotation.x=-3.7 if on_bench or state.get("cable_stance") is Vector3 else -2.8
				# Keep the raised weights clear of the head, including wider styles.
				arm.node.rotation.z+=(.30 if arm.node.name=="ArmR" else -.30)
			elif kind in ["bent_over_row","chest_supported_row","deadlift","romanian_deadlift"]:arm.node.rotation.x=-phase*.5
			elif kind=="shrug":arm.node.position.y+=phase*.08
			elif kind=="wrist_curl":arm.node.rotation.x=-.9 if on_bench else 0.0
			if state.get("activity","")=="trapped":arm.node.rotation.x=-.7+sin(elapsed*7.0)*.12
		for leg in legs.values():
			leg.node.transform=leg.transform
			if on_bench:
				var bench_mode: String=preload("res://scripts/campus/facilities/gym_bench.gd").position_for(kind)
				leg.node.rotation.x=.7 if bench_mode=="flat" else .92 if bench_mode=="incline" else -.75 if bench_mode=="supported" else -.7
				if bench_mode=="supported":
					var side:=1.0 if leg.node.name=="LegR" else -1.0
					leg.node.position.x+=side*.14
					leg.node.rotation.z=side*.5
			elif kind=="squat":leg.node.rotation.x=0.0
			elif kind=="leg_raise":leg.node.rotation.x=-.1-phase*.9
			elif kind=="hanging_leg_raise":leg.node.rotation.x=-phase
			elif kind=="crunch":leg.node.rotation.x=-.14
		if kind=="squat":squat_bend.apply(phase if state.get("activity","")=="exercise" else 1.0)
		if state.get("activity","")=="exercise":
			if kind=="curl":arm_bend.apply(1.45*phase,0.0)
			elif kind=="wrist_curl":arm_bend.apply(0.0,-.7*phase)
			elif kind=="overhead_extension":arm_bend.apply(.8*(1.0-phase),0.0)
			elif kind=="tricep_pushdown":arm_bend.apply(.75*(1.0-phase),0.0)
			elif kind=="pullup":arm_bend.apply(-1.45*phase,0.0)
			elif kind=="dip":arm_bend.apply(1.1*phase,0.0)
			elif kind=="upright_row":arm_bend.apply(0.0,0.0,1.25*phase)
			elif kind=="cable_row":arm_bend.apply(1.1*phase,0.0)
			elif kind in ["pushup","pike_pushup"]:arm_bend.apply(.94*phase,0.0)
		if state.get("mat_position") is Vector3 and kind in ["pushup","pike_pushup"]:
			for key in arms:
				var arm: Node3D=arms[key].node
				var hand:=arm_bend.hand_for(arm)
				if not is_instance_valid(hand):continue
				var side: float=-1.0 if key=="ArmL" else 1.0
				var contact: Vector3=arm.get_parent().to_local(state.mat_position+Vector3(side*.27,.035,.49))
				var aim: Vector3=contact-arm.position
				var current: Vector3=arm.basis*hand.position
				if aim.length_squared()>.001 and current.length_squared()>.001:
					var correction:=Basis(Quaternion(current.normalized(),aim.normalized()))
					arm.basis=(correction*arm.basis).scaled(Vector3.ONE*clampf(aim.length()/current.length(),.81,1.19))
		if state.get("grip_anchor") is Vector3 and arms.has("ArmL") and arms.has("ArmR"):
			var joints=preload("res://scripts/campus/facilities/arm_bend.gd")
			var left: Node3D=joints.hand_for(arms.ArmL.node)
			var right: Node3D=joints.hand_for(arms.ArmR.node)
			if is_instance_valid(left) and is_instance_valid(right):
				var grip: Vector3=(left.global_position+right.global_position)*.5
				visual.global_position+=(state.grip_anchor-grip)*minf(delta*8.0,1.0)
	elif state.get("activity","")=="seat":
		visual.position=original.origin+Vector3(0,-0.3,0)
		if state.has("seat_position"):
			visual.global_position=state.seat_position+Vector3.DOWN*.3
			visual.global_rotation.y=float(state.seat_yaw)

func _exit_tree() -> void:
	restore()
	_release_animation()
