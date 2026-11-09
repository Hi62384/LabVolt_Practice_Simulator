extends RefCounted
## Exact XY projection of the actual triangulated mesh. A conservative envelope
## across Z, not a guessed ellipse/radius/AABB. Includes transformed child meshes.
static func collect(node: Node3D, frame: Transform3D) -> Array[Vector4]:
	var unique := {}
	_collect(node,frame,unique)
	var result: Array[Vector4] = []
	for edge in unique: result.append(edge)
	return result

static func _collect(node: Node3D, frame: Transform3D, unique: Dictionary) -> void:
	if not node.visible: return
	if node is MeshInstance3D and node.mesh != null:
		for surface in node.mesh.get_surface_count():
			if node.mesh is ArrayMesh and node.mesh.surface_get_primitive_type(surface) != Mesh.PRIMITIVE_TRIANGLES: continue
			var arrays: Array = node.mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var indices := PackedInt32Array()
			if arrays[Mesh.ARRAY_INDEX] != null: indices = arrays[Mesh.ARRAY_INDEX]
			var count := indices.size() if not indices.is_empty() else vertices.size()
			for i in range(0,count,3):
				for j in 3:
					var ia: int = indices[i+j] if not indices.is_empty() else i+j
					var ib: int = indices[i+(j+1)%3] if not indices.is_empty() else i+(j+1)%3
					var a: Vector3 = frame*vertices[ia]; var b: Vector3 = frame*vertices[ib]
					if a.y > b.y or (a.y == b.y and a.x > b.x):
						var swap := a; a = b; b = swap
					unique[Vector4(a.x,a.y,b.x,b.y)] = true
	for child in node.get_children():
		if child is Node3D: _collect(child,frame*child.transform,unique)

static func at_y(edges: Array[Vector4], y: float) -> Vector2:
	var result := Vector2(INF,-INF)
	for e in edges:
		if y < minf(e.y,e.w)-.000001 or y > maxf(e.y,e.w)+.000001: continue
		if absf(e.w-e.y) < .000001:
			result.x = minf(result.x,minf(e.x,e.z)); result.y = maxf(result.y,maxf(e.x,e.z))
		else:
			var x := lerpf(e.x,e.z,clampf((y-e.y)/(e.w-e.y),0.0,1.0))
			result.x = minf(result.x,x); result.y = maxf(result.y,x)
	return result

static func pose(edges: Array[Vector4], pivot: Vector2, length: float, side: float, angle: float) -> Array[Vector4]:
	var result: Array[Vector4] = []
	var co := cos(angle); var si := sin(angle)
	for e in edges:
		var a := Vector2(e.x*side,e.y*length); var b := Vector2(e.z*side,e.w*length)
		result.append(Vector4(pivot.x+co*a.x-si*a.y,pivot.y+si*a.x+co*a.y,pivot.x+co*b.x-si*b.y,pivot.y+si*b.x+co*b.y))
	return result

static func clears(torso: Array[Vector4], arm: Array[Vector4], below: float, margin := .003) -> bool:
	# Slice bounds are piecewise linear; all edge crossings can change which edge
	# forms the boundary. Include those exact crossing heights as well as vertices.
	# Each triangle projection is convex, so its extrema occur on an edge; the
	# pairwise test below checks every overlapping edge interval analytically.
	for a in arm:
		var alo := minf(a.y,a.w); var ahi := minf(maxf(a.y,a.w),below)
		if alo > ahi: continue
		for t in torso:
			var lo := maxf(alo,minf(t.y,t.w)); var hi := minf(ahi,maxf(t.y,t.w))
			if lo > hi: continue
			for y in [lo,hi]:
				var ax := minf(a.x,a.z) if absf(a.w-a.y)<.000001 else lerpf(a.x,a.z,(y-a.y)/(a.w-a.y))
				var tx := maxf(t.x,t.z) if absf(t.w-t.y)<.000001 else lerpf(t.x,t.z,(y-t.y)/(t.w-t.y))
				if ax < tx+margin: return false
	return true

static func joint_drop(edges: Array[Vector4], length: float) -> float:
	# The intentional shoulder overlap must accommodate the actual thick sleeve
	# cap, including at horizontal splay. A fixed drop fails wide/short arms.
	var radius := 0.0
	for e in edges: radius = maxf(radius,maxf(absf(e.x),absf(e.z)))
	return maxf(.115*length,1.05*radius)

## Exact convex envelope of supplied deformed projected endpoints. Used ONLY
## for the arm: filling its concavities is conservative for torso clearance.
## Torso retains its actual concave waist/hip mesh edges.
static func convex_edges(edges: Array[Vector4]) -> Array[Vector4]:
	var unique := {}
	for e in edges:
		unique[Vector2(e.x,e.y)] = true; unique[Vector2(e.z,e.w)] = true
	var points: Array[Vector2] = []
	for point in unique: points.append(point)
	points.sort_custom(func(a: Vector2,b: Vector2) -> bool: return a.x < b.x or (a.x==b.x and a.y<b.y))
	if points.size()<3: return edges
	var hull: Array[Vector2] = []
	for point in points:
		while hull.size()>=2 and (hull[-1]-hull[-2]).cross(point-hull[-1])<=0: hull.pop_back()
		hull.append(point)
	var lower := hull.size()
	for i in range(points.size()-2,-1,-1):
		var point := points[i]
		while hull.size()>lower and (hull[-1]-hull[-2]).cross(point-hull[-1])<=0: hull.pop_back()
		hull.append(point)
	var result: Array[Vector4] = []
	for i in range(hull.size()-1): result.append(Vector4(hull[i].x,hull[i].y,hull[i+1].x,hull[i+1].y))
	return result
