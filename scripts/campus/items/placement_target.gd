extends RefCounted

static func choose(hit: Dictionary, feet: Vector3, floor_surface: Callable) -> Dictionary:
	if not hit.is_empty() and hit.get("normal",Vector3.ZERO) is Vector3 and hit.normal.y>.8:
		var point: Variant=hit.get("position")
		if point is Vector3 and point.is_finite():
			var collider: Object=hit.get("collider")
			if is_instance_valid(collider) and collider.get_meta("role","")=="table":
				return {"position":point,"table":true}
			var floor_point: Variant=floor_surface.call(point)
			if floor_point is Vector3:return {"position":floor_point,"table":false}
	var fallback: Variant=floor_surface.call(feet)
	return {"position":fallback,"table":false} if fallback is Vector3 else {}

static func host_position(school: Object, point: Variant, actor: Vector3, peer: int) -> Variant:
	if point==null:point=actor+Vector3(0,0,-.6)
	if not point is Vector3 or not point.is_finite() or not actor.is_finite():return null
	if school.has_method("is_throw_landing") and school.is_throw_landing(peer,point):return point+Vector3.UP*.01
	if actor.distance_to(point)<=3.0 and school.has_method("_table_position") and school._table_position(point,peer):
		return point+Vector3.UP*.01
	return school.ground_drop_position(point,peer)
