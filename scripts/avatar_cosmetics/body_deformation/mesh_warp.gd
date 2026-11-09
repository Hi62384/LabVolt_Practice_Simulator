extends RefCounted
## Bake a coordinate map into INSTANCE-LOCAL geometry, retaining UVs/materials.
## Finite-difference inverse transpose preserves the source's smooth normals.
static func deform_tree(root: Node3D, mapping: Callable, live := false) -> void:
	_visit(root,root.transform,mapping,live)

static func _visit(node: Node3D, frame: Transform3D, mapping: Callable, live: bool) -> void:
	if node is MeshInstance3D:
		var inverse := frame.affine_inverse()
		deform_mesh(node,func(v: Vector3) -> Vector3: return inverse * mapping.call(frame*v),live)
	for child in node.get_children():
		if child is Node3D: _visit(child,frame*child.transform,mapping,live)

static func deform_mesh(instance: MeshInstance3D, mapping: Callable, live := false) -> void:
	if instance.mesh == null: return
	var source := instance.mesh
	var target := ArrayMesh.new()
	for surface in source.get_surface_count():
		var primitive: int = source.surface_get_primitive_type(surface) if source is ArrayMesh else Mesh.PRIMITIVE_TRIANGLES
		var arrays := source.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX].duplicate()
		var normals := PackedVector3Array()
		if arrays[Mesh.ARRAY_NORMAL] != null: normals = arrays[Mesh.ARRAY_NORMAL].duplicate()
		var positions := {}
		var normal_transforms := {}
		for i in vertices.size():
			var v := vertices[i]
			if not positions.has(v): positions[v] = mapping.call(v)
			if not live and i < normals.size() and not normal_transforms.has(v):
				var e := .0001
				var dx: Vector3 = (mapping.call(v+Vector3(e,0,0))-mapping.call(v-Vector3(e,0,0)))/(2.0*e)
				var dy: Vector3 = (mapping.call(v+Vector3(0,e,0))-mapping.call(v-Vector3(0,e,0)))/(2.0*e)
				var dz: Vector3 = (mapping.call(v+Vector3(0,0,e))-mapping.call(v-Vector3(0,0,e)))/(2.0*e)
				var jacobian := Basis(dx,dy,dz)
				normal_transforms[v] = jacobian.inverse().transposed() if absf(jacobian.determinant()) > .000001 else Basis.IDENTITY
			if not live and i < normals.size(): normals[i] = (normal_transforms[v]*normals[i]).normalized()
			vertices[i] = positions[v]
		arrays[Mesh.ARRAY_VERTEX] = vertices
		if not normals.is_empty(): arrays[Mesh.ARRAY_NORMAL] = normals
		# Imported normal maps require a regenerated tangent frame after warping.
		if not live:
			arrays[Mesh.ARRAY_TANGENT] = null
			if arrays[Mesh.ARRAY_TEX_UV] != null and not normals.is_empty() and primitive==Mesh.PRIMITIVE_TRIANGLES:
				var rebuilt := ArrayMesh.new()
				rebuilt.add_surface_from_arrays(primitive,arrays)
				var st := SurfaceTool.new(); st.create_from(rebuilt,0); st.generate_tangents()
				arrays = st.commit_to_arrays()
		target.add_surface_from_arrays(primitive,arrays)
		target.surface_set_material(surface,source.surface_get_material(surface))
	instance.mesh = target

static func section_mesh(rows: Array[Vector3]) -> ArrayMesh:
	var st := SurfaceTool.new(); st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for row in range(rows.size()-1):
		for i in 32:
			var points: Array[Vector3] = []
			for pair in [[row,i],[row+1,i],[row+1,i+1],[row,i+1]]:
				var r: Vector3 = rows[pair[0]]; var angle: float = TAU*pair[1]/32.0
				points.append(Vector3(cos(angle)*r.y,r.x,sin(angle)*r.z))
			for index in [0,2,1,0,3,2]: st.add_vertex(points[index])
	st.generate_normals()
	return st.commit()
