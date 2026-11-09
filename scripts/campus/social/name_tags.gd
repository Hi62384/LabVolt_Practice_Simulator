extends RefCounted
static func relevant(viewer: Vector3, target: Vector3, same_zone: bool, occluded: bool, max_distance := 12.0) -> bool:
	return same_zone and not occluded and viewer.distance_squared_to(target)<=max_distance*max_distance
static func inspectable(viewer: Vector3, target: Vector3, same_zone: bool, occluded: bool) -> bool:
	return relevant(viewer,target,same_zone,occluded,4.0)
