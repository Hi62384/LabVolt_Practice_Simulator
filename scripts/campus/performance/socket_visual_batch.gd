extends RefCounted
## Authored LabVolt socket visuals only. Body/collider/selection transform stay intact.
## All four source meshes are static opaque colours; changing socket materials later
## requires clear() first. Switch indicators/knobs are never included.
const Eligibility = preload("res://scripts/campus/performance/static_panel_batch.gd")
var _eligibility := Eligibility.new()
var _records: Array[Dictionary] = []
var _batches: Array[MeshInstance3D] = []
var _meshes := {}
var _material: ShaderMaterial
var sockets_batched := 0
var saved_instances := 0
var _default_properties := {}
var _plain_cache := {}

func _init() -> void:
	var baseline := StandardMaterial3D.new()
	for property in baseline.get_property_list():
		var property_name := str(property.name)
		if (int(property.usage) & PROPERTY_USAGE_STORAGE) != 0 and property_name not in ["albedo_color","metallic","roughness","resource_name","resource_local_to_scene"]:
			_default_properties[property_name] = baseline.get(property_name)
	var shader := Shader.new()
	shader.code = """shader_type spatial;
void vertex() {
	// Same sRGB vertex-colour handling as Godot4.5 StandardMaterial3D.
	if (!OUTPUT_IS_SRGB) {
		COLOR.rgb = mix(pow((COLOR.rgb + vec3(0.055)) / 1.055, vec3(2.4)), COLOR.rgb / 12.92, lessThan(COLOR.rgb,vec3(0.04045)));
	}
}
void fragment() {
	ALBEDO = COLOR.rgb;
	METALLIC = UV2.x;
	ROUGHNESS = UV2.y;
	SPECULAR = 0.5;
}
"""
	_material = ShaderMaterial.new()
	_material.shader = shader

func _plain(material: StandardMaterial3D) -> bool:
	var id := material.get_instance_id()
	if _plain_cache.has(id):
		return _plain_cache[id]
	for property_name in _default_properties:
		if material.get(property_name) != _default_properties[property_name]:
			_plain_cache[id] = false
			return false
	_plain_cache[id] = true
	return true

func apply(socket: StaticBody3D) -> bool:
	if str(socket.get_meta("role","")) != "socket":
		return false
	var nodes: Array[MeshInstance3D] = []
	var key_fields: Array = []
	for child in socket.get_children():
		if child is MeshInstance3D:
			if not _eligibility._eligible(child):
				return false
			var material := child.get_active_material(0) as StandardMaterial3D
			if not _plain(material) or material.albedo_color.a != 1.0:
				return false
			nodes.append(child)
			key_fields.append([child.mesh.get_instance_id(),child.transform,material.albedo_color,material.metallic,material.roughness])
	if nodes.size() != 4:
		return false
	var first: MeshInstance3D = nodes[0]
	for node in nodes:
		if node.layers != first.layers or node.cast_shadow != first.cast_shadow or node.gi_mode != first.gi_mode or node.ignore_occlusion_culling != first.ignore_occlusion_culling:
			return false
	var key := var_to_bytes(key_fields)
	if not _meshes.has(key):
		var surface := SurfaceTool.new()
		surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		for node in nodes:
			_append(surface,node)
		# _append expands indexed triangles. Restore an index buffer so identical
		# position/normal/colour/UV vertices share vertex-shader work again.
		surface.index()
		_meshes[key] = surface.commit()
	var batch := MeshInstance3D.new()
	batch.name = "SocketVisualBatch"
	batch.mesh = _meshes[key]
	batch.material_override = _material
	batch.layers = first.layers
	batch.cast_shadow = first.cast_shadow
	batch.gi_mode = first.gi_mode
	batch.ignore_occlusion_culling = first.ignore_occlusion_culling
	socket.add_child(batch)
	_batches.append(batch)
	for node in nodes:
		_records.append({"node":weakref(node),"layers":node.layers})
		node.layers = 0
		node.set_meta("campus_static_batch_source",true)
	sockets_batched += 1
	saved_instances += 3
	return true

func _append(surface: SurfaceTool, node: MeshInstance3D) -> void:
	var material := node.get_active_material(0) as StandardMaterial3D
	var arrays := node.mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
	var normal_basis := node.transform.basis.inverse().transposed()
	var count := indices.size() if not indices.is_empty() else vertices.size()
	for i in count:
		var j := indices[i] if not indices.is_empty() else i
		surface.set_color(material.albedo_color)
		surface.set_uv2(Vector2(material.metallic,material.roughness))
		surface.set_normal((normal_basis*normals[j]).normalized())
		surface.add_vertex(node.transform*vertices[j])

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
	_meshes.clear()
	sockets_batched = 0
	saved_instances = 0
