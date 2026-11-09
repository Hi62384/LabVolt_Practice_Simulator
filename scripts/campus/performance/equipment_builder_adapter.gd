extends "res://scripts/equipment_builder.gd"
## Drop-in builder inheritance adapter: same helper APIs, dimensions and materials.
## Builds reduced/shared primitives directly instead of first allocating dense ones.
const MeshCache = preload("res://scripts/campus/performance/equipment_mesh_cache.gd")
static var shared_equipment_meshes := MeshCache.new()
var render_mesh_optimization_enabled := true

func _instance(parent: Node3D, at: Vector3, mesh: PrimitiveMesh, color: Color, metallic: float) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh = shared_equipment_meshes.replacement(mesh) if render_mesh_optimization_enabled else mesh
	node.position = at
	node.material_override = _mat(color,metallic)
	parent.add_child(node)
	return node

func _box(parent: Node3D, pos: Vector3, size: Vector3, color: Color, metallic := 0.1) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	return _instance(parent,pos,mesh,color,metallic)

func _cylinder(parent: Node3D, pos: Vector3, radius: float, height: float, color: Color, metallic := 0.1) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 18
	return _instance(parent,pos,mesh,color,metallic)

func _sphere(parent: Node3D, pos: Vector3, radius: float, color: Color) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius*2.0
	return _instance(parent,pos,mesh,color,0.2)
