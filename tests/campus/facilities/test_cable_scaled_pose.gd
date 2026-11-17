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
			var rest:=actor.transform
			var foot: Node3D=actor.get_node("LegR/Sole")
			var body: Node3D=actor.get_node("Body")
			for phase in [0.0,1.0]:
				activity.apply_event({"activity":"exercise","station":"gym/cable_0","exercise":"cable_crunch","phase":phase,"half_ms":700,"machine_position":Vector3.ZERO,"cable_stance":Vector3(0,0,1.25)},false)
				for i in 120:activity._process(.02)
				var facing: Vector3=actor.global_basis.orthonormalized().z
				if facing.dot(Vector3.FORWARD)<.98 or absf(actor.scale.x-height)>.01:
					failures.append("Cable stance facing or scale wrong: %s %s" % [outfit,height])
				if absf(foot.global_position.y)>.15 or actor.global_position.distance_to(Vector3(0,0,1.25))>.03:
					failures.append("Cable crunch did not keep its feet on the floor")
				if absf(body.rotation.x-.48*phase)>.03:failures.append("Cable crunch did not hinge through its repetition")
			activity.apply_event({"activity":"idle"},false)
			if not actor.transform.is_equal_approx(rest):failures.append("Cable pose did not restore avatar")
			for exercise in ["cable_press","cable_fly","cable_reverse_fly","overhead_extension"]:
				activity.apply_event({"activity":"exercise","station":"gym/cable_0","exercise":exercise,"phase":1,"half_ms":700,"machine_position":Vector3.ZERO,"cable_stance":Vector3(0,0,1.25)},false)
				for i in 120:activity._process(.02)
				var expected:=Vector3.FORWARD if exercise=="cable_reverse_fly" else Vector3.BACK
				if actor.global_basis.orthonormalized().z.dot(expected)<.98:failures.append("Cable exercise faced the wrong direction: "+exercise)
				activity.apply_event({"activity":"idle"},false)
			var arm: Node3D=actor.get_node("Body/ArmR")
			var hand: Node3D=arm.get_node("Hand")
			var hand_rest:=hand.transform
			activity.apply_event({"activity":"exercise","station":"gym/cable_0","exercise":"cable_row","phase":1,"half_ms":700,"machine_position":Vector3.ZERO,"cable_stance":Vector3(0,0,1.25)},false)
			for i in 120:activity._process(.02)
			if hand.transform==hand_rest:failures.append("Cable row did not bend the elbow")
			activity.apply_event({"activity":"idle"},false)
			if hand.transform!=hand_rest:failures.append("Cable row did not restore the hand")
			activity.free();actor.free()
	for message in failures:push_error(message)
	print("CABLE_SCALED_POSE ","PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)
