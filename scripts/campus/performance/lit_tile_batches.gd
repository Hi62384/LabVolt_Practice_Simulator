extends RefCounted
## Keep corridor tile batches local to allow frustum culling.
static func build(parent: Node3D,points: Array,size: Vector3,material: Material,cell_size := 5.0) -> Array:
	var sections:={}
	for point in points:
		var key:=Vector2i(floori(point.x/cell_size),floori(point.z/cell_size))
		if not sections.has(key):sections[key]=[]
		sections[key].append(point)
	var tile := PlaneMesh.new()
	tile.size = Vector2(size.x, size.z)
	var result:=[]
	for key in sections:
		var group: Array=sections[key]
		var center: Vector3=group[0]
		var batch:=MultiMesh.new();batch.transform_format=MultiMesh.TRANSFORM_3D;batch.mesh=tile;batch.instance_count=group.size()
		for i in group.size():batch.set_instance_transform(i,Transform3D(Basis.IDENTITY,group[i]-center+Vector3.UP*size.y*.5))
		var node:=MultiMeshInstance3D.new();node.position=center;node.multimesh=batch;node.material_override=material
		node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;parent.add_child(node);result.append(node)
	return result


# Forward Mobile assigns positional lights per render instance. All tiles
# in an enclosed room share an instance so the light list does not switch
# at arbitrary batch boundaries or between differently colored tiles.
static func satin_material(tint: Color, vertex_colors := false, lighting_profile := 0) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader=preload("res://scripts/campus/presentation/lighting/satin_tiles.gdshader")
	material.set_shader_parameter("tile_color",tint)
	material.set_shader_parameter("use_tile_vertex_color",vertex_colors)
	material.set_shader_parameter("lighting_profile",lighting_profile)
	return material

static func room_floor(parent: Node3D, groups: Array, size: Vector2, top: float, roughness: float, satin := false, lighting_profile := 0) -> MultiMeshInstance3D:
	var mesh := PlaneMesh.new()
	mesh.size = size
	var material := StandardMaterial3D.new()
	material.roughness = roughness
	material.vertex_color_use_as_albedo = true
	var count := 0
	for group in groups:
		count += group.points.size()
	var batch := MultiMesh.new()
	batch.transform_format = MultiMesh.TRANSFORM_3D
	batch.use_colors = true
	batch.mesh = mesh
	batch.instance_count = count
	var index := 0
	for group in groups:
		for point in group.points:
			batch.set_instance_transform(index, Transform3D(Basis.IDENTITY, Vector3(point.x, top, point.z)))
			batch.set_instance_color(index, group.color)
			index += 1
	var floor_mesh := MultiMeshInstance3D.new()
	floor_mesh.name = "RoomFloorTiles"
	floor_mesh.multimesh = batch
	floor_mesh.material_override = satin_material(Color.WHITE,true,lighting_profile) if satin else material
	if satin:floor_mesh.set_meta("satin_floor",true)
	floor_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(floor_mesh)
	return floor_mesh
