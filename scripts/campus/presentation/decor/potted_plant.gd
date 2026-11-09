extends RefCounted

static func mount(parent: Node3D, at: Vector3) -> void:
	var plant := StaticBody3D.new()
	plant.name = "PottedPlant"
	plant.position = at
	parent.add_child(plant)
	var shape := CylinderShape3D.new()
	shape.radius = .24
	shape.height = .43
	var collider := CollisionShape3D.new()
	collider.shape = shape
	collider.position.y = .215
	plant.add_child(collider)
	_pot_part(plant, .197, .245, .167, .385, "c6b8a2")
	_pot_part(plant, .394, .254, .247, .065, "d6c6af")
	_pot_part(plant, .429, .213, .213, .014, "574737")
	var leaves := SurfaceTool.new()
	leaves.begin(Mesh.PRIMITIVE_TRIANGLES)
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.roughness = .85
	leaves.set_material(material)
	for i in range(12):
		var azimuth := i * 2.39996
		var outward := Vector3(cos(azimuth), 0, sin(azimuth))
		var tangent := outward.cross(Vector3.UP)
		var height: float = [.48, .73, .91][i % 3]
		var spread: float = [.43, .35, .25][i % 3]
		var tint := Color(["456d36","568242","6a934e","3c6639"][i % 4])
		var previous := PackedVector3Array()
		for row in range(9):
			var t := row / 8.0
			var stem := Vector3(0,.435,0) + outward * (spread * t * t + .025) + Vector3.UP * height * sin(t * 1.8)
			var width := maxf(.001, .118 * sin(PI * clampf((t - .18) / .82, 0, 1)))
			var current := PackedVector3Array([stem - tangent * width, stem + outward * width * .29, stem + tangent * width])
			if row > 0:
				for side in range(2):
					leaves.set_color(tint.lightened(.12) if side == 0 else tint)
					for v in [previous[side], current[side], previous[side+1], previous[side+1], current[side], current[side+1]]:
						leaves.add_vertex(v)
			previous = current
	leaves.generate_normals()
	var foliage := MeshInstance3D.new()
	foliage.mesh = leaves.commit()
	plant.add_child(foliage)

static func _pot_part(parent: Node3D, y: float, top: float, bottom: float, height: float, tint: String) -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = top
	mesh.bottom_radius = bottom
	mesh.height = height
	mesh.radial_segments = 24
	var part := MeshInstance3D.new()
	part.mesh = mesh
	part.position.y = y
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(tint)
	material.roughness = .76
	part.material_override = material
	parent.add_child(part)

