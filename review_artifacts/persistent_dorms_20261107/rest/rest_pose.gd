extends RefCounted
## Instance-local rigid lying pose. Keeps all body/clothing attachment pivots.
const META := &"dorm_rest_pose"
static func apply(model: Node3D, active: bool) -> void:
	if active:
		if model.has_meta(META):return
		var player: AnimationPlayer=null
		for found in model.find_children("*","AnimationPlayer",true,false):player=found;break
		model.set_meta(META,{"transform":model.transform,"player":player,"animation":player.current_animation if player!=null else ""})
		if player!=null:
			for name in player.get_animation_list():
				if name.to_lower().ends_with("idle"):
					player.play(name);player.seek(0.0,true);break
			player.pause()
		# Rotate the complete existing segmented rig, preserving customized parts
		# and their rest transforms. Feet remain at the bed's foot anchor.
		model.rotate_object_local(Vector3.RIGHT,PI/2.0)
	else:
		if not model.has_meta(META):return
		var state: Dictionary=model.get_meta(META)
		model.transform=state.transform
		var player: AnimationPlayer=state.player
		if is_instance_valid(player) and not str(state.animation).is_empty():player.play(state.animation)
		model.remove_meta(META)
