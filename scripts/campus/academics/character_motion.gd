extends RefCounted
## Persistent affect layers over the normal walk/seated animation. Facial parts
## have explicit roles and immutable authored rests. Blink uses a child pivot;
## expressions own the eye parent and head, and the mouth compositor owns audio.
## Unsupported imported rigs degrade to declared parts, without geometry guesses.
const Face=preload("res://scripts/campus/academics/character_face.gd")
const POSES:=["raise_hand","point","wave","nod","phone","write","sleep","whisper","argue","think","celebrate","shrug","turn_away","defensive","shake_head","confused","awkward_stare","laugh"]
const APPEARANCE:={
	"angry":[.18,.63,.97],"irritated":[.13,.74,.97],"frustrated":[.15,.7,.96],
	"stressed":[.13,.95,1.03],"anxious":[.14,1.18,1.04],"embarrassed":[.24,.8,.96],
	"amused":[-.1,.70,1.08],"happy":[-.03,.78,1.06],"excited":[-.15,1.15,1.1],
	"tired":[.22,.45,.9],"bored":[.16,.58,.94],"sad":[.21,.67,.91],"disappointed":[.18,.76,.94],
	"interested":[-.09,1.12,1.04],"confident":[-.07,1.04,1.02],"patient":[-.015,.88,.97],
}

static func pitch(mood: String) -> float:
	return float(APPEARANCE.get(mood,[0.,1.,1.])[2])

static func express(model: Node3D,mood: String,delta: float,pose := "",elapsed := .0,point := Vector3.INF,affect: Dictionary={},traits: Dictionary={},attention_point := Vector3.INF) -> void:
	if not is_instance_valid(model):return
	var rig:=_rig(model)
	var appearance: Array=APPEARANCE.get(mood,[0.,1.,1.])
	var blend:=1.-exp(-maxf(0.,delta)*9.)
	var anger:=float(affect.get("anger",.75 if mood=="angry" else .45 if mood in ["irritated","frustrated"] else 0.))
	var anxiety:=float(affect.get("anxiety",.7 if mood in ["anxious","stressed","embarrassed"] else 0.))
	var joy:=maxf(float(affect.get("happiness",.7 if mood=="happy" else 0.)),float(affect.get("amusement",.7 if mood=="amused" else 0.)))
	var sadness:=maxf(float(affect.get("sadness",.8 if mood=="sad" else 0.)),float(affect.get("disappointment",.6 if mood=="disappointed" else 0.))*.7)
	var tired:=float(affect.get("tiredness",.85 if mood in ["tired","bored"] else 0.))
	var confidence:=float(traits.get("confidence",.8 if mood=="confident" else .5))
	var expression:=float(traits.get("expressiveness",.65))
	var amplitude:=.45+expression*.65
	var head: Node3D=rig.head
	if is_instance_valid(head):
		var nod:=sin(elapsed*TAU*1.5)*.18 if pose=="nod" else 0.
		var pitch_angle:=float(appearance[0])+nod+sin(elapsed*TAU/4.)*.02
		if pose in ["phone","write","think"]:pitch_angle+=.19
		if pose=="phone":pitch_angle=.38
		if pose=="sleep":pitch_angle=.48
		var yaw:=0.
		if pose=="laugh":pitch_angle+=sin(elapsed*TAU*3.)*.075
		if pose=="confused":pitch_angle-=.085
		if pose=="turn_away":yaw=.75
		elif pose=="shake_head":yaw=sin(elapsed*TAU*1.55)*.28*exp(-elapsed*.35)
		elif mood in ["embarrassed","sad"]:yaw=-.14
		elif anxiety>.5:yaw=sin(elapsed*1.7)*.055*anxiety
		# Attention and emotion share one compositor. A seated person's pelvis
		# stays on the chair while their head glances within anatomical limits.
		if pose!="turn_away" and attention_point.is_finite() and head.is_inside_tree():
			var toward: Vector3=model.global_basis.orthonormalized().inverse()*(attention_point-head.global_position)
			if toward.length_squared()>.001:
				yaw+=clampf(atan2(toward.x,toward.z),-1.05,1.05)
				pitch_angle-=clampf(atan2(toward.y,Vector2(toward.x,toward.z).length()),-.38,.38)
		yaw=clampf(yaw,-1.15,1.15)
		pitch_angle=clampf(pitch_angle,-.55,.65)
		head.rotation.x=lerpf(head.rotation.x,pitch_angle,blend)
		head.rotation.y=lerp_angle(head.rotation.y,yaw,blend)
		var tilt:=sin(elapsed*1.1)*.025*anxiety
		if pose=="confused":tilt+=.13
		elif pose=="awkward_stare":tilt-=.045
		head.rotation.z=lerpf(head.rotation.z,tilt,blend)
		var openness:=float(appearance[1])
		if pose=="sleep":openness=.08
		elif pose=="phone":openness=minf(openness,.88)
		elif pose=="awkward_stare":openness=maxf(openness,1.18)
		elif pose=="confused":openness=maxf(openness,1.04)
		elif pose=="laugh":openness=minf(openness,.55)
		for entry in rig.eyes:
			var eye: Node3D=entry.node
			if not is_instance_valid(eye):continue
			var rest: Vector3=entry.scale
			eye.scale=eye.scale.lerp(Vector3(rest.x,rest.y*openness,rest.z),blend)
			var at: Vector3=entry.position
			eye.position=eye.position.lerp(at+Vector3(yaw*.013,-maxf(0.,pitch_angle)*.012,0.),blend)
		for entry in rig.brows:
			var brow: Node3D=entry.node
			if not is_instance_valid(brow):continue
			var side:=float(entry.side)
			var slant:=side*(anger*.5-anxiety*.27-sadness*.4)*amplitude
			var lift:=anxiety*.013+sadness*.006-anger*.018
			if pose=="confused":lift+=.014 if side>0 else .004
			elif pose=="awkward_stare":lift+=.009
			var a: Vector3=entry.a
			var b: Vector3=entry.b
			# Rotate both endpoints around the same authored brow anchor. A shear
			# stretched the outer/inner segments by different amounts at anger.
			var rotated_a:=Vector2(a.x,a.y).rotated(slant)
			var rotated_b:=Vector2(b.x,b.y).rotated(slant)
			a=Vector3(rotated_a.x,rotated_a.y+lift,a.z)
			b=Vector3(rotated_b.x,rotated_b.y+lift,b.z)
			_pose_link(brow,entry,a,b,blend)
		var mouth_strength:=clampf(maxf(maxf(joy,anger),maxf(sadness,tired))*amplitude,0.,1.)
		var curve:=clampf(joy*.028-anger*.024-sadness*.034-tired*.012,-.04,.035)
		for entry in rig.mouth:
			var segment: Node3D=entry.node
			if not is_instance_valid(segment):continue
			if not entry.has("a"):continue
			# Rebuild each lip link from its endpoints. Subtracting a small bend
			# from an authored smile left hurt faces smiling, and independent
			# Euler rotations broke the continuous curve at stronger emotions.
			var a: Vector3=entry.a
			var b: Vector3=entry.b
			var radius:=maxf(.001,float(rig.mouth_radius))
			a.y=lerpf(a.y,float(rig.mouth_center)+curve*pow(a.x/radius,2.),mouth_strength)
			b.y=lerpf(b.y,float(rig.mouth_center)+curve*pow(b.x/radius,2.),mouth_strength)
			_pose_link(segment,entry,a,b,blend)
		if pose=="laugh":curve=maxf(curve,.032);mouth_strength=maxf(mouth_strength,.8)
		Face.expression(head,curve,mouth_strength)
	var body: Node3D=rig.body
	if is_instance_valid(body):
		var lean:=(tired*.1+anxiety*.045-anger*.035-(confidence-.5)*.04)*amplitude
		if pose=="sleep":lean=.18
		if pose=="argue":lean=-.045
		if pose=="laugh":lean+=.045+sin(elapsed*TAU*3.)*.025
		body.rotation.x=lerpf(body.rotation.x,lean,blend)
		body.rotation.z=lerpf(body.rotation.z,sin(elapsed*2.4)*.018*anxiety,blend)
	for side in [-1,1]:
		var arm: Node3D=rig.left if side<0 else rig.right
		if not is_instance_valid(arm):continue
		if not arm.has_meta("classroom_arm_rest"):arm.set_meta("classroom_arm_rest",Vector3(0.,0.,arm.rotation.z))
		var rest: Vector3=arm.get_meta("classroom_arm_rest")
		var goal:=rest
		var engaged:=not pose.is_empty() or mood not in ["steady","patient"] or not affect.is_empty()
		if not engaged and not arm.has_meta("character_arm_engaged"):continue
		var beat:=sin(elapsed*TAU*1.25)*.09*amplitude
		match pose:
			"raise_hand":
				if side>0:goal+=Vector3(-.45,0.,2.4)
			"wave":
				if side>0:goal+=Vector3(-.7,0.,2.05+sin(elapsed*TAU*2.5)*.3)
			"point":
				if side>0:
					var toward:=model.global_basis.orthonormalized().inverse()*(point-arm.global_position) if point.is_finite() and model.is_inside_tree() else Vector3.FORWARD
					var pitch_angle:=atan2(toward.y,Vector2(toward.x,toward.z).length())
					goal+=Vector3(-PI*.5-pitch_angle,0.,clampf(-atan2(toward.x,toward.z),-.75,.75))
			"phone":goal+=Vector3(-1.05 if side>0 else -.85,side*.08,-side*.75)
			"write":goal+=Vector3(-.78+(beat*.22 if side>0 else 0.),side*.05,side*.18)
			"sleep":goal+=Vector3(-.75,side*.32,side*.35)
			"whisper":
				if side>0:goal+=Vector3(-1.28,-.2,.3)
			"argue":goal+=Vector3(-.6+beat,side*.12,side*(.5+beat))
			"think":
				if side>0:goal+=Vector3(-1.35,-.32,.28)
			"celebrate":goal+=Vector3(-.45+beat,0.,side*2.2)
			"shrug":goal+=Vector3(-.5,side*.2,side*.85)
			"defensive":goal+=Vector3(-1.2,-side*.18,-side*.9)
			"confused":
				if side>0:goal+=Vector3(-.65,.2,.4)
			"laugh":goal+=Vector3(-.55+beat,side*.1,side*.23)
			_:
				goal+=Vector3(-anger*.13+anxiety*beat*.5,0.,side*(anger*.12+joy*.045))
		arm.rotation=arm.rotation.lerp(goal,blend)
		if engaged:arm.set_meta("character_arm_engaged",true)
		elif arm.rotation.distance_squared_to(rest)<.0001:
			arm.rotation=rest
			arm.remove_meta("character_arm_engaged")

static func _pose_link(node: Node3D,entry: Dictionary,a: Vector3,b: Vector3,blend: float) -> void:
	var axis:=(b-a).normalized()
	var rest: Vector3=entry.scale
	node.position=node.position.lerp((a+b)*.5,blend)
	node.quaternion=node.quaternion.slerp(Quaternion(Vector3.UP,axis),blend)
	node.scale=node.scale.lerp(Vector3(rest.x,a.distance_to(b)/float(entry.height),rest.z),blend)

static func _segment(node: Node3D) -> Dictionary:
	var rest: Transform3D=node.get_meta(Face.REST,node.transform)
	var entry:={"node":node,"position":rest.origin,"rotation":rest.basis.get_euler(),"scale":rest.basis.get_scale(),"side":node.get_meta(Face.SIDE,0)}
	if node is MeshInstance3D and node.mesh is CylinderMesh:
		var half: Vector3=rest.basis.y*node.mesh.height*.5
		entry.a=rest.origin-half;entry.b=rest.origin+half
		entry.height=node.mesh.height
	return entry

static func _rig(model: Node3D) -> Dictionary:
	if model.has_meta("character_expression_rig"):return model.get_meta("character_expression_rig")
	var head:=Face.head_for(model)
	var result:={"head":head,"body":model.get_node_or_null("Body"),"left":model.get_node_or_null("Body/ArmL"),"right":model.get_node_or_null("Body/ArmR"),"eyes":[],"brows":[],"mouth":[],"mouth_radius":.056,"mouth_center":-.122}
	if is_instance_valid(head):
		var eyes:=Face.parts(head,"eye")
		if eyes.is_empty():
			# Stable imported rig nodes are an explicit compatibility seam. Never
			# identify an eyeball, brow or glasses frame by shape or coordinates.
			for path in ["EyeL","EyeR"]:
				var eye:=head.get_node_or_null(path) as Node3D
				if eye!=null:eyes.append(eye)
		for eye in eyes:result.eyes.append(_segment(eye))
		for brow in Face.parts(head,"brow_segment"):result.brows.append(_segment(brow))
		var central_distance:=INF
		for lip in Face.parts(head,"lip"):
			var entry:=_segment(lip)
			if not entry.has("a"):continue
			result.mouth_radius=maxf(float(result.mouth_radius),maxf(absf(entry.a.x),absf(entry.b.x)))
			if absf(entry.position.x)<central_distance:
				central_distance=absf(entry.position.x)
				result.mouth_center=entry.position.y
			result.mouth.append(entry)
		_claim_head_animation(model,head)
	model.set_meta("character_expression_rig",result)
	return result

static func _claim_head_animation(model: Node3D,head: Node3D) -> void:
	# Generated NPCs use this compositor for the complete head rotation. Their
	# locomotion retains body/limb tracks and independent Blink child tracks.
	# Player avatars not using Motion keep the original idle head animation.
	if str(head.get_meta(Face.ROLE,""))!="head":return
	var player:=model.get_node_or_null("AnimationPlayer") as AnimationPlayer
	if player==null:return
	for name in player.get_animation_list():
		var animation:=player.get_animation(name)
		for track in animation.get_track_count():
			if animation.track_get_type(track)==Animation.TYPE_ROTATION_3D and str(animation.track_get_path(track))=="Body/Head":
				animation.track_set_enabled(track,false)
