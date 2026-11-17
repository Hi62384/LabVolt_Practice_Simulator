extends SceneTree
const Toon=preload("res://scripts/toon_character.gd")
const Activity=preload("res://scripts/campus/facilities/avatar_activity.gd")
const Joints=preload("res://scripts/campus/facilities/arm_bend.gd")
var failures: Array[String]=[]
func _initialize() -> void:call_deferred("run")
func run() -> void:
	for height in [.85,1.15]:
		var actor:=Node3D.new();actor.position=Vector3(1.2,0,.8);actor.rotation.y=PI*.5;root.add_child(actor)
		var config: Dictionary=Toon.defaults();config.height=height
		var avatar: Node3D=Toon.build(config);actor.add_child(avatar)
		var activity=Activity.new();actor.add_child(activity);activity.bind_visual(avatar)
		for exercise in ["pullup","hanging_leg_raise","dip"]:
			var anchor:=Vector3(0,1.05,.75) if exercise=="dip" else Vector3(0,2.6,0)
			var previous_y:=0.0
			for phase in [0.0,1.0]:
				activity.apply_event({"activity":"exercise","station":"gym/pullup","exercise":exercise,"phase":phase,"half_ms":700,"grip_anchor":anchor},false)
				for i in 180:activity._process(.02)
				var left: Node3D=Joints.hand_for(avatar.get_node("Body/ArmL"))
				var right: Node3D=Joints.hand_for(avatar.get_node("Body/ArmR"))
				var midpoint: Vector3=(left.global_position+right.global_position)*.5
				if midpoint.distance_to(anchor)>.02:failures.append("Grip missed station for %s at height %.2f" % [exercise,height])
				if exercise=="dip" and (absf(absf(left.global_position.x)-.48)>.12 or absf(absf(right.global_position.x)-.48)>.12):failures.append("Dip hands missed the parallel handles at %.2f / %.0f: %.3f, %.3f" % [height,phase,left.global_position.x,right.global_position.x])
				if phase==1.0 and exercise in ["pullup","dip"] and absf(avatar.global_position.y-previous_y)<.025:failures.append("Body did not move during "+exercise)
				previous_y=avatar.global_position.y
			activity.apply_event({"activity":"idle"},false)
			if avatar.transform!=activity.original or actor.position!=Vector3(1.2,0,.8):failures.append("Station exercise did not restore its pose")
		actor.free()
	for failure in failures:push_error(failure)
	print("STATION_GRIPS ","PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)
