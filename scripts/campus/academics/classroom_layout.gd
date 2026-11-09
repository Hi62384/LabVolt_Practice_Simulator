extends RefCounted
## Furniture anchors derive from the single registry room, never duplicate room IDs.
static func point(value: Variant) -> Vector3:
	if value is Vector3:return value
	if value is Array and value.size()>=3:return Vector3(float(value[0]),float(value[1]),float(value[2]))
	return Vector3.ZERO

static func desks(room: Dictionary) -> Array:
	var center := point(room.get("center",room.get("anchor",Vector3.ZERO)))
	var result: Array=[]
	for row in range(2):
		for column in range(4):result.append(center+Vector3(-3.6+2.4*column,.895,-1.0-2.5*row))
	return result

static func teacher(room: Dictionary) -> Vector3:
	return point(room.get("center",room.get("anchor",Vector3.ZERO)))+Vector3(0,0,3.5)

static func recycling(room: Dictionary) -> Vector3:
	var center := point(room.get("center", room.get("anchor", Vector3.ZERO)))
	var low := point(room.get("bounds_min", center - Vector3(10, 0, 6)))
	return Vector3(center.x + 6.8, center.y, low.z + .58)
