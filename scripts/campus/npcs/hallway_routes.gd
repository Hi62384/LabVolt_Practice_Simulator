extends RefCounted
## Derive safe corridor-only loops from the world registry's published layout data.
## Room interiors can supply their own authored routes around furniture separately.
static func from_registry(registry: Object) -> Dictionary:
	var result := {}
	if not is_instance_valid(registry) or not registry.has_method("locate") or not registry.has_method("search"):
		return result
	var has_data := false
	for property in registry.get_property_list():
		if str(property.name) == "data":
			has_data = true
	if not has_data:
		return result
	var data: Variant = registry.get("data")
	if not data is Dictionary:
		return result
	var corridor: Dictionary = data.get("corridor", {})
	for key in ["x_min", "x_max", "z_min", "z_max"]:
		if not corridor.has(key):
			return result
	var x := (float(corridor.x_min) + float(corridor.x_max)) * 0.5
	var z_start := float(corridor.z_min) + 6.0
	var z_end := float(corridor.z_max) - 6.0
	# Avoid staircase/elevator landings; floor transitions are player-only.
	if data.get("stairs") is Dictionary:
		z_end = minf(z_end, float(data.stairs.get("z_min", z_end + 4.0)) - 4.0)
	if z_end - z_start < 4.0 or float(corridor.x_max) - float(corridor.x_min) < 3.0:
		return result
	var heights := {}
	for room in registry.call("search", ""):
		if room.get("anchor") is Array and room.anchor.size() >= 3:
			heights[float(room.anchor[1])] = true
	for y in heights:
		var midpoint := Vector3(x, float(y), (z_start + z_end) * 0.5)
		var zone := str(registry.call("locate", midpoint))
		if zone.is_empty():
			continue
		result[zone] = [PackedVector3Array([Vector3(x-0.6, y, z_start), Vector3(x-0.6, y, z_end), Vector3(x+0.6, y, z_end), Vector3(x+0.6, y, z_start)])]
	return result
