extends RefCounted
## HUD-only cue data. Never parents anything to instrument trees or changes materials.
static func cue(view: Dictionary,camera: Camera3D,target_position: Vector3,viewport_size: Vector2) -> Dictionary:
	if not view.get("active",false) or not is_instance_valid(camera):return {"visible":false}
	if camera.is_position_behind(target_position):return {"visible":false}
	var pixel: Vector2=camera.unproject_position(target_position)
	if pixel.x<0 or pixel.y<0 or pixel.x>viewport_size.x or pixel.y>viewport_size.y:return {"visible":false}
	return {"visible":true,"position":pixel,"label":str(view.step.get("instruction","")),"cue":str(view.step.get("cue","")),"peer_id":int(view.peer_id)}
