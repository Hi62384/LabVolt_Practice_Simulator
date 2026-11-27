extends RefCounted

const POSES:=["raise_hand","point","wave","nod"]
const APPEARANCE:={
	"angry":[.18,.73,.97],"irritated":[.13,.82,.97],"frustrated":[.15,.78,.96],
	"stressed":[.13,.95,1.03],"anxious":[.14,1.18,1.04],"embarrassed":[.24,.8,.96],
	"amused":[-.1,.70,1.08],"happy":[-.03,.78,1.06],"excited":[-.15,1.15,1.1],
	"tired":[.22,.55,.9],"bored":[.16,.66,.94],"sad":[.21,.67,.91],"disappointed":[.18,.76,.94],
	"interested":[-.09,1.12,1.04],"confident":[-.07,1.04,1.02],"patient":[-.015,.88,.97],
}

static func pitch(mood: String) -> float:
	return float(APPEARANCE.get(mood,[0.,1.,1.])[2])

static func express(model: Node3D,mood: String,delta: float,pose := "",elapsed := .0,point := Vector3.INF) -> void:
	if not is_instance_valid(model):return
	var appearance: Array=APPEARANCE.get(mood,[0.,1.,1.])
	var blend:=minf(1.,delta*12.)
	var head:=model.get_node_or_null("Body/Head") as Node3D
	if is_instance_valid(head):
		var nod:=sin(elapsed*TAU*1.5)*.21 if pose=="nod" else 0.
		head.rotation.x=lerpf(head.rotation.x,float(appearance[0])+nod,blend)
		for path in ["EyeL","EyeR"]:
			var eye:=head.get_node_or_null(path) as Node3D
			if is_instance_valid(eye):eye.scale.y=lerpf(eye.scale.y,float(appearance[1]),blend)
	var arm:=model.get_node_or_null("Body/ArmR") as Node3D
	if not is_instance_valid(arm):return
	if pose not in ["raise_hand","wave","point"] and not arm.has_meta("character_arm_engaged"):return
	if not arm.has_meta("classroom_arm_rest"):arm.set_meta("classroom_arm_rest",arm.rotation)
	var rest: Vector3=arm.get_meta("classroom_arm_rest")
	var goal:=rest
	match pose:
		"raise_hand":goal+=Vector3(-.45,0.,2.4)
		"wave":goal+=Vector3(-.7,0.,2.05+sin(elapsed*TAU*2.5)*.3)
		"point":
			var toward:=model.global_basis.orthonormalized().inverse()*(point-arm.global_position) if point.is_finite() else Vector3.FORWARD
			var pitch_angle:=atan2(toward.y,Vector2(toward.x,toward.z).length())
			goal+=Vector3(-PI*.5-pitch_angle,0.,clampf(-atan2(toward.x,toward.z),-.75,.75))
	arm.rotation=arm.rotation.lerp(goal,blend)
	if pose in ["raise_hand","wave","point"]:arm.set_meta("character_arm_engaged",true)
	elif arm.rotation.distance_squared_to(rest)<.0001:
		arm.rotation=rest
		arm.remove_meta("character_arm_engaged")
