extends RefCounted
## Bake the existing student geometry into one shared vertex-colour draw surface.
## Medium LOD omits facial/clothing detail; no new imported character asset.
const Toon = preload("res://scripts/toon_character.gd")
const WALK = preload("res://assets/campus/npcs/crowd_walk.gdshader")
const MAJOR := ["TailoredTop", "Neck", "Trouser", "Sneaker", "Sleeve", "Forearm", "Hand", "Face", "Ear", "HairCap"]

static func build(simple := false) -> ArrayMesh:
	var profile := Toon.preset(0)
	profile.glasses = "None"
	profile.hair = "Crop"
	profile.outfit = "Tee"
	var root: Node3D = Toon.build(profile)
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	_append(root, Transform3D.IDENTITY, surface, simple, Vector3.ZERO, 0.0)
	var mesh := surface.commit()
	root.free()
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.roughness = 0.85
	if simple:
		mesh.surface_set_material(0, material)
	else:
		var walk_material := ShaderMaterial.new()
		walk_material.shader = WALK
		mesh.surface_set_material(0, walk_material)
	return mesh

static func _append(node: Node3D, parent_transform: Transform3D, surface: SurfaceTool, simple: bool, pivot: Vector3, limb: float) -> void:
	var transform := parent_transform * node.transform
	if str(node.name) in ["LegL", "LegR", "ArmL", "ArmR"]:
		pivot = transform.origin
		limb = -1.0 if str(node.name).ends_with("L") else 1.0
		if str(node.name).begins_with("Arm"):
			limb *= 2.0
	if node is MeshInstance3D and (not simple or str(node.name) in MAJOR):
		var mesh: Mesh = node.mesh
		for index in mesh.get_surface_count():
			var arrays := mesh.surface_get_arrays(index)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
			var indices := PackedInt32Array()
			if arrays[Mesh.ARRAY_INDEX] != null:
				indices = arrays[Mesh.ARRAY_INDEX]
			var material := node.get_active_material(index) as StandardMaterial3D
			var color := material.albedo_color if material != null else Color.WHITE
			var normal_basis := transform.basis.inverse().transposed()
			var count := indices.size() if not indices.is_empty() else vertices.size()
			for i in count:
				var vertex_index := indices[i] if not indices.is_empty() else i
				surface.set_color(color)
				surface.set_uv(Vector2(pivot.x, pivot.y))
				surface.set_uv2(Vector2(limb, pivot.z))
				if not normals.is_empty():
					surface.set_normal((normal_basis * normals[vertex_index]).normalized())
				surface.add_vertex(transform * vertices[vertex_index])
	for child in node.get_children():
		if child is Node3D:
			_append(child, transform, surface, simple, pivot, limb)
