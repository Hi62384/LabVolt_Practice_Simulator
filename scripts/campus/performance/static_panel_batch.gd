extends RefCounted
## Batches only direct, opaque, plain-material primitive siblings approved by caller.
## Original nodes remain alive. clear() restores render layers exactly.
var _records: Array[Dictionary] = []
var _batches: Array[MeshInstance3D] = []
var _protected: Array = []
var max_vertices_per_batch := 120000
var stats := {"source_instances":0,"batch_instances":0,"saved_instances":0,"skipped_interaction_branches":0}

func apply(root: Node3D, protected_nodes: Array = []) -> Dictionary:
	_protected = protected_nodes
	_visit(root,root)
	return stats.duplicate()

func _visit(parent: Node3D, root: Node3D) -> void:
	if parent in _protected or parent is CollisionObject3D:
		stats.skipped_interaction_branches += 1
		return
	if parent != root and parent.get_script() != null:
		return
	var groups := {}
	var children := parent.get_children()
	for child in children:
		if _eligible(child):
			var material: StandardMaterial3D = child.get_active_material(0)
			var key := "%s:%s:%s:%s:%s:%s:%s" % [material.get_instance_id(),child.layers,child.cast_shadow,child.gi_mode,child.visibility_range_begin,child.visibility_range_end,child.ignore_occlusion_culling]
			if not groups.has(key):
				groups[key] = []
			groups[key].append(child)
	for group in groups.values():
		# Bound vertex work and AABB size to a single physical panel parent.
		var segment: Array = []
		var vertices := 0
		for child in group:
			var arrays: Array = child.mesh.surface_get_arrays(0)
			var count: int = arrays[Mesh.ARRAY_VERTEX].size()
			if vertices + count > max_vertices_per_batch:
				_commit(parent,segment)
				segment = []
				vertices = 0
			segment.append(child)
			vertices += count
		_commit(parent,segment)
	for child in children:
		if child is Node3D and not child is MeshInstance3D:
			_visit(child,root)

func _eligible(node: Node) -> bool:
	if not node is MeshInstance3D or node in _protected or node.get_script() != null:
		return false
	if node.has_meta("campus_static_batch_source") or node.has_meta("role") or not node.visible or node.layers == 0:
		return false
	if not node.mesh is PrimitiveMesh or node.mesh.get_surface_count() != 1:
		return false
	if node.skin != null or (not node.skeleton.is_empty() and node.get_node_or_null(node.skeleton) is Skeleton3D):
		return false
	if not node.scale.is_equal_approx(Vector3.ONE):
		return false
	if node.material_overlay != null or node.transparency != 0.0 or node.visibility_parent != NodePath(""):
		return false
	if node.visibility_range_fade_mode != GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED:
		return false
	if node.visibility_range_begin != 0.0 or node.visibility_range_end != 0.0:
		return false
	var material := node.get_active_material(0) as StandardMaterial3D
	if material == null or material.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED or material.grow or material.proximity_fade_enabled or material.distance_fade_mode != BaseMaterial3D.DISTANCE_FADE_DISABLED or material.next_pass != null:
		return false
	# Textures, animation uniforms and per-instance materials are kept independent.
	for slot in BaseMaterial3D.TEXTURE_MAX:
		if material.get_texture(slot) != null:
			return false
	return true

func _commit(parent: Node3D, nodes: Array) -> void:
	if nodes.size() < 3:
		return
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for node in nodes:
		surface.append_from(node.mesh,0,node.transform)
	var mesh := surface.commit()
	var batch := MeshInstance3D.new()
	batch.name = "StaticPanelBatch"
	batch.mesh = mesh
	var first: MeshInstance3D = nodes[0]
	batch.material_override = first.get_active_material(0)
	batch.layers = first.layers
	batch.cast_shadow = first.cast_shadow
	batch.gi_mode = first.gi_mode
	batch.visibility_range_begin = first.visibility_range_begin
	batch.visibility_range_end = first.visibility_range_end
	batch.ignore_occlusion_culling = first.ignore_occlusion_culling
	parent.add_child(batch)
	_batches.append(batch)
	for node in nodes:
		_records.append({"node":weakref(node),"layers":node.layers})
		node.set_meta("campus_static_batch_source",true)
		node.layers = 0
	stats.source_instances += nodes.size()
	stats.batch_instances += 1
	stats.saved_instances += nodes.size() - 1

func clear() -> void:
	for record in _records:
		var node: MeshInstance3D = record.node.get_ref()
		if is_instance_valid(node):
			node.layers = record.layers
			node.remove_meta("campus_static_batch_source")
	for batch in _batches:
		if is_instance_valid(batch):
			batch.free()
	_records.clear()
	_batches.clear()
	stats = {"source_instances":0,"batch_instances":0,"saved_instances":0,"skipped_interaction_branches":0}
