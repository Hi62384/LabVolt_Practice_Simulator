extends RefCounted
## Persistent affect layers over the normal walk/seated animation. The rig cache
## stores authored scales; expressions never resize eyes to unit scale or modify
## speech-mouth visibility. Unsupported rigs degrade to available body parts.
const POSES:=["raise_hand","point","wave","nod","phone","write","sleep","whisper","argue","think","celebrate","shrug","turn_away","defensive"]
const APPEARANCE:={
	"angry":[.18,.63,.97],"irritated":[.13,.74,.97],"frustrated":[.15,.7,.96],
	"stressed":[.13,.95,1.03],"anxious":[.14,1.18,1.04],"embarrassed":[.24,.8,.96],
	"amused":[-.1,.70,1.08],"happy":[-.03,.78,1.06],"excited":[-.15,1.15,1.1],
	"tired":[.22,.45,.9],"bored":[.16,.58,.94],"sad":[.21,.67,.91],"disappointed":[.18,.76,.94],
	"interested":[-.09,1.12,1.04],"confident":[-.07,1.04,1.02],"patient":[-.015,.88,.97],
}

static func pitch(mood: String) -> float:
	return float(APPEARANCE.get(mood,[0.,1.,1.])[2])

static func express(model: Node3D,mood: String,delta: float,pose := "",elapsed := .0,point := Vector3.INF,affect: Dictionary={},traits: Dictionary={}) -> void:
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
		var pitch_angle:=float(appearance[0])+nod
		if pose in ["phone","write","think"]:pitch_angle+=.19
		if pose=="phone":pitch_angle=.38
		if pose=="sleep":pitch_angle=.48
		var yaw:=0.
		if pose=="turn_away":yaw=.55
		elif mood in ["embarrassed","sad"]:yaw=-.14
		elif anxiety>.5:yaw=sin(elapsed*1.7)*.055*anxiety
		head.rotation.x=lerpf(head.rotation.x,pitch_angle,blend)
		head.rotation.y=lerp_angle(head.rotation.y,yaw,blend)
		head.rotation.z=lerpf(head.rotation.z,sin(elapsed*1.1)*.025*anxiety,blend)
		var openness:=float(appearance[1])
		if pose=="sleep":openness=.08
		elif pose=="phone":openness=minf(openness,.88)
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
			var at: Vector3=entry.position
			var side:=signf(at.x)
			var slant:=side*(anger*.5-anxiety*.27-sadness*.4)*amplitude
			var lift:=anxiety*.013+sadness*.006-anger*.018
			var a: Vector3=entry.a
			var b: Vector3=entry.b
			a.y+=lift+tan(slant)*(a.x-float(entry.center_x))
			b.y+=lift+tan(slant)*(b.x-float(entry.center_x))
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
	var body: Node3D=rig.body
	if is_instance_valid(body):
		var lean:=(tired*.1+anxiety*.045-anger*.035-(confidence-.5)*.04)*amplitude
		if pose=="sleep":lean=.18
		if pose=="argue":lean=-.045
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
	var entry:={"node":node,"position":node.position,"rotation":node.rotation,"scale":node.scale}
	if node is MeshInstance3D and node.mesh is CylinderMesh:
		var half: Vector3=node.basis.y*node.mesh.height*.5
		entry.a=node.position-half;entry.b=node.position+half
		entry.height=node.mesh.height
	return entry

static func _rig(model: Node3D) -> Dictionary:
	if model.has_meta("character_expression_rig"):return model.get_meta("character_expression_rig")
	var head:=model.get_node_or_null("Body/Head") as Node3D
	var result:={"head":head,"body":model.get_node_or_null("Body"),"left":model.get_node_or_null("Body/ArmL"),"right":model.get_node_or_null("Body/ArmR"),"eyes":[],"brows":[],"mouth":[],"mouth_radius":.056,"mouth_center":-.122}
	if is_instance_valid(head):
		for child in head.get_children():
			if not child is Node3D:continue
			var part:=str(child.get_meta("toon_part",child.name))
			var entry:=_segment(child)
			if part in ["EyeWhite","Iris","Pupil","EyeSpark","EyeL","EyeR"] or str(child.name) in ["EyeL","EyeR"]:
				result.eyes.append(entry)
			elif child is MeshInstance3D and child.mesh is CylinderMesh and child.position.y>.07 and child.position.y<.14 and child.position.z>.12:
				result.brows.append(entry)
		for entry in result.brows:
			var total:=0.
			var count:=0
			for neighbor in result.brows:
				if signf(neighbor.position.x)==signf(entry.position.x):total+=neighbor.position.x;count+=1
			entry.center_x=total/maxi(1,count)
		var mouth:=head.get_node_or_null("NeutralMouth")
		if is_instance_valid(mouth):
			var central_distance:=INF
			for segment in mouth.get_children():
				if not segment is Node3D:continue
				var entry:=_segment(segment)
				if entry.has("a"):
					result.mouth_radius=maxf(float(result.mouth_radius),maxf(absf(entry.a.x),absf(entry.b.x)))
					if absf(segment.position.x)<central_distance:
						central_distance=absf(segment.position.x)
						result.mouth_center=segment.position.y
				result.mouth.append(entry)
	model.set_meta("character_expression_rig",result)
	return result
