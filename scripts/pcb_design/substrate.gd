extends RefCounted
const Design=preload("res://scripts/pcb_design/design.gd")

static func standalone_height(bp: Dictionary) -> float:
	# Portable boards are scaled down in the world. Keep the laminate edge legible.
	return maxf(.028,float(bp.get("footprint",{}).get("thickness_mm",1.6))*.005)

static func surface_material(texture: Texture2D, standalone: bool) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_texture=texture
	if standalone:
		material.roughness=.68
	else:
		material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	return material

static func board_point(point: Vector2,height: float) -> Vector3:
	return Vector3((point.x/1000.-.5)*1.88,height,(point.y/440.-.5)*.78)
static func mesh(bp: Dictionary,rect: Rect2,base: float,top: float,texture_face: bool=false) -> ArrayMesh:
	var poly:=Design.polygon(bp.pcb_design)
	var triangles:=Geometry2D.triangulate_polygon(poly)
	var vertices:=PackedVector3Array();var uvs:=PackedVector2Array();var normals:=PackedVector3Array()
	for index in triangles:
		var pixel:=Design.map_point(bp,[poly[index].x,poly[index].y],rect)
		vertices.append(board_point(pixel,top));uvs.append(pixel/Vector2(1000,440));normals.append(Vector3.UP)
	if not texture_face:
		for index in range(triangles.size()-1,-1,-1):
			var value:=poly[triangles[index]];var pixel:=Design.map_point(bp,[value.x,value.y],rect)
			vertices.append(board_point(pixel,base));uvs.append(Vector2.ZERO);normals.append(Vector3.DOWN)
		for i in poly.size():
			var a:=Design.map_point(bp,[poly[i].x,poly[i].y],rect)
			var b:=Design.map_point(bp,[poly[(i+1)%poly.size()].x,poly[(i+1)%poly.size()].y],rect)
			var low_a:=board_point(a,base);var low_b:=board_point(b,base);var high_a:=board_point(a,top);var high_b:=board_point(b,top)
			var normal: Vector3=(high_a-low_a).cross(low_b-low_a).normalized()
			for value in [low_a,high_a,low_b,low_b,high_a,high_b]:vertices.append(value);uvs.append(Vector2.ZERO);normals.append(normal)
	var arrays: Array=[];arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=vertices;arrays[Mesh.ARRAY_TEX_UV]=uvs;arrays[Mesh.ARRAY_NORMAL]=normals
	var result:=ArrayMesh.new();result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays);return result
static func build(parent: Node3D,canvas: Control,bp: Dictionary,rect: Rect2,base: float,height: float) -> void:
	var standalone: bool=canvas.board.get("standalone",false)
	var body:=MeshInstance3D.new();body.mesh=mesh(bp,rect,.015+base,.015+base+height)
	var material:=StandardMaterial3D.new();material.albedo_color=Color("a59160") if standalone else Color(str(bp.footprint.color));material.roughness=.8;material.cull_mode=BaseMaterial3D.CULL_DISABLED
	body.material_override=material;body.set_meta("pcb_outline",true);parent.add_child(body)
	var face:=MeshInstance3D.new();face.mesh=mesh(bp,rect,0,.0155+base+height,true)
	var live:=surface_material(canvas.get_viewport().get_texture(),standalone);live.cull_mode=BaseMaterial3D.CULL_DISABLED
	face.material_override=live;face.set_meta("pcb_live_surface",true);parent.add_child(face)
