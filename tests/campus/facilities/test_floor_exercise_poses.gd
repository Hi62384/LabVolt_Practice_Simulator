extends SceneTree
const Toon=preload("res://scripts/toon_character.gd")
const Activity=preload("res://scripts/campus/facilities/avatar_activity.gd")
var failures: Array[String]=[]

func _initialize() -> void:call_deferred("run")

func run() -> void:
	for outfit in ["Tee","Hoodie"]:
		for height in [.85,1.15]:
			var config: Dictionary=Toon.defaults();config.outfit=outfit;config.height=height
			var actor: Node3D=Toon.build(config);root.add_child(actor)
			var activity=Activity.new();root.add_child(activity);activity.bind_visual(actor)
			var body: Node3D=actor.get_node("Body")
			var foot: Node3D=actor.get_node("LegR/Sole")
			var hand: Node3D=actor.get_node("Body/ArmR/Hand")
			var head: Node3D=actor.get_node("Body/Head")
			var original:=actor.transform;var original_body:=body.transform
			for exercise in ["pushup","pike_pushup","crunch","leg_raise"]:
				var feet: Array[Vector3]=[];var heads: Array[Vector3]=[]
				for phase in [0.0,1.0]:
					activity.apply_event({"activity":"exercise","station":"gym/pushup","exercise":exercise,"phase":phase,"half_ms":700},false)
					for i in 100:activity._process(.02)
					feet.append(foot.global_position);heads.append(head.global_position)
					if exercise in ["pushup","pike_pushup"]:
						if absf(hand.global_position.y)>.17 or absf(foot.global_position.y)>.17:
							failures.append("Hands or feet left the floor: %s %s %s phase %s" % [exercise,outfit,height,phase])
						if head.global_position.y<.20*height:
							failures.append("Head crossed the floor: "+exercise)
						if exercise=="pike_pushup" and (body.global_transform*Vector3(0,.86,0)).y<head.global_position.y+.20*height:
							failures.append("Pike hips did not rise above the head")
				if exercise=="crunch" and (feet[0].distance_to(feet[1])>.03 or heads[1].y<heads[0].y+.10*height):
					failures.append("Crunch did not keep the feet still and raise the torso")
				if exercise=="leg_raise" and feet[1].y<feet[0].y+.20*height:
					failures.append("Leg raise did not lift the legs")
				activity.apply_event({"activity":"idle"},false)
				if not actor.transform.is_equal_approx(original) or not body.transform.is_equal_approx(original_body):
					failures.append("Floor exercise did not restore avatar: "+exercise)
				var mat:=Vector3(2,.08,3)
				activity.apply_event({"activity":"exercise","station":"gym/pushup","exercise":exercise,"phase":1,"half_ms":700,"mat_position":mat},false)
				for i in 100:activity._process(.02)
				var other_foot: Node3D=actor.get_node("LegL/Sole")
				var midpoint: Vector3=(head.global_position+(foot.global_position+other_foot.global_position)*.5)*.5
				if absf(midpoint.x-mat.x)>.05 or absf(midpoint.z-mat.z)>.4:
					failures.append("Avatar did not line up with the mat: %s %s %s midpoint %s" % [exercise,outfit,height,midpoint])
				activity.apply_event({"activity":"idle"},false)
				if not actor.transform.is_equal_approx(original):failures.append("Mat pose did not restore avatar: "+exercise)
			activity.free();actor.free()
	for message in failures:push_error(message)
	print("FLOOR_EXERCISE_POSES ","PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)
