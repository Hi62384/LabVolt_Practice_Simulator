extends RefCounted

static func find(actor: CharacterBody3D, anchor: Transform3D, previous: Vector3, exclude_self := true, aisle: Vector3 = Vector3.INF) -> Variant:
	var candidates: Array[Vector3] = []
	var floor_y := aisle.y if aisle.is_finite() else previous.y
	if previous.is_finite() and previous.distance_to(anchor.origin) < 3.0:
		candidates.append(Vector3(previous.x, floor_y, previous.z))
	if aisle.is_finite():
		candidates.append(aisle)
		for offset in [Vector3.FORWARD, Vector3.BACK, Vector3.LEFT, Vector3.RIGHT]:
			candidates.append(aisle + offset * .45)
	for radius in [.85, 1.15, 1.5, 2.0, 2.5]:
		for step in 16:
			var angle := TAU * step / 16.0
			candidates.append(Vector3(anchor.origin.x + cos(angle) * radius, floor_y, anchor.origin.z + sin(angle) * radius))

	var space := actor.get_world_3d().direct_space_state
	var capsule := CapsuleShape3D.new()
	capsule.radius = .25
	capsule.height = 1.7
	var exclusions: Array[RID] = []
	if exclude_self:
		exclusions.append(actor.get_rid())
	var clearance := PhysicsShapeQueryParameters3D.new()
	clearance.shape = capsule
	clearance.collision_mask = actor.collision_mask | actor.collision_layer
	clearance.exclude = exclusions
	for candidate in candidates:
		# Search around the actual dorm floor, below furniture tops and above any
		# lower storey. Require support plus room for the full standing capsule.
		var ray := PhysicsRayQueryParameters3D.create(candidate + Vector3.UP * .24, candidate - Vector3.UP * .5, actor.collision_mask, exclusions)
		var support := space.intersect_ray(ray)
		if support.is_empty() or support.normal.dot(Vector3.UP) < .7:
			continue
		var feet: Vector3 = support.position + Vector3.UP * .065
		clearance.transform = Transform3D(Basis.IDENTITY, feet + Vector3.UP * .85)
		if space.intersect_shape(clearance, 1).is_empty():
			return feet
	return null
