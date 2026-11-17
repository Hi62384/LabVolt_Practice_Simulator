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
			for test in [{"exercise":"benchpress","tilt":-1.5},{"exercise":"incline_press","tilt":-.92},{"exercise":"overhead_press","tilt":0.0}]:
				activity.apply_event({"activity":"exercise","station":"gym/benchpress","exercise":test.exercise,"phase":1,"half_ms":700,"bench_position":Vector3(4,0,31.5)},false)
				for i in 120:activity._process(.02)
				var tilt: float=actor.global_basis.orthonormalized().get_euler().x
				if absf(tilt-float(test.tilt))>.04 or absf(actor.scale.x-height)>.01:
					failures.append("Bench angle or scale wrong: %s %s %s" % [test.exercise,outfit,height])
				if test.exercise=="overhead_press":
					var hip: Vector3=actor.global_transform*Vector3(0,.86,0)
					if absf(hip.y-.585)>.03:failures.append("Seated hips do not meet the bench: %s %s" % [outfit,height])
				activity.apply_event({"activity":"idle"},false)
				if not actor.transform.is_equal_approx(rest):failures.append("Bench pose did not restore")
			var widths: Array[float]=[]
			for phase in [0.0,1.0]:
				activity.apply_event({"activity":"exercise","station":"gym/benchpress","exercise":"chest_fly","equipment":"dumbbell","phase":phase,"half_ms":700,"bench_position":Vector3(4,0,31.5)},false)
				for i in 120:activity._process(.02)
				var left: Node3D=actor.get_node("Body/ArmL/Hand")
				var right: Node3D=actor.get_node("Body/ArmR/Hand")
				var head: Node3D=actor.get_node("Body/Head")
				widths.append(left.global_position.distance_to(right.global_position))
				if left.global_position.distance_to(head.global_position)<.35*height or right.global_position.distance_to(head.global_position)<.35*height:
					failures.append("Bench fly hands intersect the head")
			if widths[1]<widths[0]+.25*height:failures.append("Bench fly did not open the arms")
			activity.apply_event({"activity":"idle"},false)
			var motion=preload("res://scripts/campus/presentation/decor/m105/gym_equipment_motion.gd").new();root.add_child(motion)
			motion.grip_position=func(_peer):
				return (actor.get_node("Body/ArmL/Hand").global_position+actor.get_node("Body/ArmR/Hand").global_position)*.5
			for exercise in ["curl","good_morning","overhead_extension"]:
				var event:={"activity":"exercise","station":"gym/benchpress","exercise":exercise,"phase":1,"half_ms":700,"bench_position":Vector3(4,0,31.5)}
				activity.apply_event(event,false);motion.on_room_event(1,event)
				for i in 120:activity._process(.02);motion._process(.02)
				var grip: Vector3=motion.grip_position.call(1)
				if motion.bars["gym/benchpress"].global_position.distance_to(grip)>.06:
					failures.append("Bench bar lost the hands: %s %s %s" % [exercise,outfit,height])
				activity.apply_event({"activity":"idle"},false)
			var overhead_heights: Array[float]=[]
			for phase in [0.0,1.0]:
				activity.apply_event({"activity":"exercise","station":"gym/benchpress","exercise":"overhead_extension","phase":phase,"half_ms":700,"bench_position":Vector3(4,0,31.5)},false)
				for i in 120:activity._process(.02)
				var head: Vector3=actor.get_node("Body/Head").global_position
				var grip: Vector3=motion.grip_position.call(1)
				overhead_heights.append(grip.y)
				if head.z-grip.z<.22*height:failures.append("Overhead bar intersects head: %s %s phase %s" % [outfit,height,phase])
			if overhead_heights[1]-overhead_heights[0]<.10*height:failures.append("Overhead extension does not raise grip: %s %s" % [outfit,height])
			activity.apply_event({"activity":"idle"},false)
			motion.free();activity.free();actor.free()
	for message in failures:push_error(message)
	print("BENCH_SCALED_POSE ","PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)
