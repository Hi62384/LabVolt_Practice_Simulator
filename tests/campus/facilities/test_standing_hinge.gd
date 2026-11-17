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
			var torso: Node3D=actor.get_node("Body")
			var foot: Node3D=actor.get_node("LegR/Sole")
			var hand: Node3D=actor.get_node("Body/ArmR/Hand")
			var rest:=torso.transform;var foot_rest:=foot.global_position
			for exercise in ["deadlift","romanian_deadlift","bent_over_row","reverse_fly"]:
				activity.apply_event({"activity":"exercise","station":"gym/dumbbell/1","exercise":exercise,"phase":1,"half_ms":700},false)
				for i in 100:activity._process(.02)
				if torso.rotation.x<.5 or foot.global_position.distance_to(foot_rest)>.001:
					failures.append("Hinge did not bend forward with feet planted: %s %s %s" % [exercise,outfit,height])
				activity.apply_event({"activity":"idle"},false)
				if not torso.transform.is_equal_approx(rest) or foot.global_position.distance_to(foot_rest)>.001:
					failures.append("Hinge did not restore the avatar: "+exercise)
			activity.apply_event({"activity":"exercise","station":"gym/dumbbell/1","exercise":"overhead_extension","phase":1,"half_ms":700},false)
			for i in 100:activity._process(.02)
			if hand.global_position.y<actor.global_position.y+1.35*height:
				failures.append("Overhead extension did not raise the hand: %s %s" % [outfit,height])
			activity.apply_event({"activity":"idle"},false)
			var arm: Node3D=actor.get_node("Body/ArmR")
			activity.apply_event({"activity":"exercise","station":"gym/dumbbell/1","exercise":"squat","phase":1,"half_ms":700,"equipment":"dumbbell"},false)
			for i in 100:activity._process(.02)
			if absf(arm.rotation.z)>.6:failures.append("Dumbbell squat used the barbell shoulder pose")
			activity.apply_event({"activity":"idle"},false)
			activity.free();actor.free()
	for message in failures:push_error(message)
	print("STANDING_HINGE ","PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)
