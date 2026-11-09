extends RefCounted
static func find(actor: CharacterBody3D, anchor: Transform3D, previous: Vector3, exclude_self := true) -> Variant:
	var candidates: Array[Vector3]=[]
	if previous.distance_to(anchor.origin)<3.0:candidates.append(previous)
	for radius in [.85,1.15,1.5,2.0]:
		for step in 16:
			var angle:=TAU*step/16.0
			candidates.append(anchor.origin+Vector3(cos(angle)*radius,0,sin(angle)*radius))
	var space:=actor.get_world_3d().direct_space_state
	var capsule:=CapsuleShape3D.new();capsule.radius=.25;capsule.height=1.7
	for candidate in candidates:
		var exclusions: Array[RID]=[actor.get_rid()] if exclude_self else []
		var ray:=PhysicsRayQueryParameters3D.create(candidate+Vector3.UP*.5,candidate-Vector3.UP*2.0,1,exclusions)
		var floor_hit:=space.intersect_ray(ray)
		if floor_hit.is_empty() or floor_hit.normal.dot(Vector3.UP)<.7:continue
		var at: Vector3=floor_hit.position+Vector3.UP*.03
		var query:=PhysicsShapeQueryParameters3D.new();query.shape=capsule
		query.transform=Transform3D(Basis.IDENTITY,at+Vector3.UP*.85);query.collision_mask=3;query.exclude=exclusions
		if space.intersect_shape(query,8).is_empty():return at
	return null
