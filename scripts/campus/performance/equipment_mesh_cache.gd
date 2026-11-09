extends RefCounted
## Exact dimensions/materials are retained. Only curved-surface tessellation changes.
## Cached resources are immutable to callers; original primitive resources are untouched.
var _cache := {}
var sphere_segments := 16
var sphere_rings := 8
var hits := 0
var replacements := 0
var max_resources := 1024
var uncached := 0

func replacement(source: Mesh) -> Mesh:
	var fields: Array = []
	if source is SphereMesh:
		fields = ["sphere",source.radius,source.height,source.is_hemisphere,mini(source.radial_segments,sphere_segments),mini(source.rings,sphere_rings),source.flip_faces,source.add_uv2,source.uv2_padding]
	elif source is CylinderMesh:
		fields = ["cylinder",source.top_radius,source.bottom_radius,source.height,source.radial_segments,0,source.cap_top,source.cap_bottom,source.flip_faces,source.add_uv2,source.uv2_padding]
	elif source is BoxMesh:
		fields = ["box",source.size,source.subdivide_width,source.subdivide_height,source.subdivide_depth,source.flip_faces,source.add_uv2,source.uv2_padding]
	else:
		return source
	# Material belongs to the resource on some primitives. Preserve that identity too.
	fields.append(source.material.get_instance_id() if source.material != null else 0)
	var key := var_to_bytes(fields)
	if _cache.has(key):
		hits += 1
		return _cache[key]
	var mesh: PrimitiveMesh = source.duplicate()
	if mesh is SphereMesh:
		mesh.radial_segments = mini(mesh.radial_segments,sphere_segments)
		mesh.rings = mini(mesh.rings,sphere_rings)
	elif mesh is CylinderMesh:
		mesh.rings = 0
	if _cache.size() < max_resources:
		_cache[key] = mesh
	else:
		# Moving lead lengths must not create an unbounded persistent cache.
		uncached += 1
	replacements += 1
	return mesh

func stats() -> Dictionary:
	return {"resources":_cache.size(),"cache_hits":hits,"new_resources":replacements,"uncached":uncached,"max_resources":max_resources,"sphere_segments":sphere_segments,"sphere_rings":sphere_rings}
