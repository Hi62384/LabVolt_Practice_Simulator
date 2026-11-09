extends SceneTree
## DEFERRED: run only after main applies all four patches and user ends play.
## This script has not been parsed/executed. No save/export/network writes.
const Renderer = preload("res://scripts/avatar_cosmetics/core/avatar_renderer.gd")
const Core = preload("res://scripts/avatar_cosmetics/core/avatar_core.gd")
func _initialize() -> void:
	for field in ["neck_length","neck_width","torso_length","torso_width","hips","arm_width","leg_width"]:
		for value in [.65,1.4]:
			var body := Core.sanitize_body({field:value})
			var model := Renderer.render_avatar({"body":body},{})
			for path in ["Body","Body/Head","Body/ArmL","Body/ArmR","LegL","LegR"]:
				var node := model.get_node(path) as Node3D
				assert(node.transform.is_finite())
			assert(is_equal_approx(model.get_node("LegL").scale.y,body.leg_length))
			assert(is_equal_approx(model.get_node("Body/ArmL").scale.y,body.arm_length))
			var player := model.get_node("AnimationPlayer") as AnimationPlayer
			for name in ["Idle","Walk","Seated"]:
				var animation := player.get_animation(name)
				assert(animation!=null)
				for track in animation.get_track_count():
					assert(model.has_node(animation.track_get_path(track)))
			model.free()
	print("Body deformation runtime smoke checks passed; visual/export/network acceptance still separate")
	quit()
