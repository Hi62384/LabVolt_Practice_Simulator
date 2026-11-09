extends RefCounted
## Read-only fixture for a later safe Godot boundary. Never invoked in this audit.
## Call capture(equipment_root) before and after environment mounting, then compare
## the returned dictionaries or their var_to_bytes digests. Do not save user data.

static func capture(root: Node3D) -> Dictionary:
	var entries := []
	_walk(root,"",entries)
	return {"root":str(root.name),"nodes":entries,"count":entries.size()}

static func _walk(node: Node,path: String,entries: Array) -> void:
	var here := path+"/"+str(node.name)
	var item := {"path":here,"class":node.get_class(),"child_count":node.get_child_count()}
	if node is Node3D:
		item["transform"]=node.transform
		item["global_transform"]=node.global_transform
		item["scale"]=node.scale
		item["visible"]=node.visible
	if node is MeshInstance3D:
		item["mesh"]=_mesh(node.mesh)
		item["material_override"]=_material(node.material_override)
		item["surface_overrides"]=[]
		for i in node.get_surface_override_material_count():
			item["surface_overrides"].append(_material(node.get_surface_override_material(i)))
	if node is CollisionShape3D:
		item["shape"]=_resource(node.shape)
		item["disabled"]=node.disabled
	if node is Label3D:
		item["label"]={"text":node.text,"font_size":node.font_size,"pixel_size":node.pixel_size,"modulate":node.modulate,"billboard":node.billboard,"no_depth_test":node.no_depth_test}
	if node is Light3D:
		item["light"]={"color":node.light_color,"energy":node.light_energy,"shadow":node.shadow_enabled}
	var important_meta := {}
	for key in ["role","id","label","station","terminal_legend","printed_face_z"]:
		if node.has_meta(key):important_meta[key]=node.get_meta(key)
	if not important_meta.is_empty():item["meta"]=important_meta
	entries.append(item)
	for child in node.get_children():_walk(child,here,entries)

static func _mesh(mesh: Mesh) -> Dictionary:
	if mesh==null:return {}
	var result := _resource(mesh)
	result["surface_count"]=mesh.get_surface_count()
	result["materials"]=[]
	for i in mesh.get_surface_count():result["materials"].append(_material(mesh.surface_get_material(i)))
	if mesh is PrimitiveMesh:
		result["aabb"]=mesh.get_aabb()
	return result

static func _material(material: Material) -> Dictionary:
	if material==null:return {}
	var result := _resource(material)
	if material is StandardMaterial3D:
		result["albedo_color"]=material.albedo_color
		result["albedo_texture"]=_resource(material.albedo_texture)
		result["metallic"]=material.metallic
		result["roughness"]=material.roughness
		result["transparency"]=material.transparency
		result["emission_enabled"]=material.emission_enabled
		result["emission"]=material.emission
	return result

static func _resource(resource: Resource) -> Dictionary:
	if resource==null:return {}
	return {"class":resource.get_class(),"path":resource.resource_path,"name":resource.resource_name}
