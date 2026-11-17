extends SceneTree

func _initialize() -> void:
	var gear=preload("res://scripts/campus/facilities/gym_barbells.gd").new()
	var small: MeshInstance3D=gear._plate_model(2.5)
	var large: MeshInstance3D=gear._plate_model(45.0)
	var another: MeshInstance3D=gear._plate_model(45.0)
	var vertices: PackedVector3Array=large.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array=large.mesh.surface_get_arrays(0)[Mesh.ARRAY_NORMAL]
	var valid:=not vertices.is_empty() and large.mesh.get_aabb().size.x>small.mesh.get_aabb().size.x
	valid=valid and normals.size()==vertices.size()
	var has_top:=false;var has_bottom:=false;var has_outer:=false;var has_inner:=false
	for normal in normals:
		if not normal.is_finite() or normal.length_squared()<.9:valid=false
		has_top=has_top or normal.dot(Vector3.UP)>.9
		has_bottom=has_bottom or normal.dot(Vector3.DOWN)>.9
		has_outer=has_outer or normal.x>.9
		has_inner=has_inner or normal.x<-.9
	valid=valid and has_top and has_bottom and has_outer and has_inner
	for vertex in vertices:
		if Vector2(vertex.x,vertex.z).length()<.044:valid=false
	valid=valid and large.mesh==another.mesh
	var engravings:=large.find_children("EngravedWeight*","MeshInstance3D",true,false)
	valid=valid and engravings.size()==2
	for engraving in engravings:
		valid=valid and engraving.mesh is TextMesh and engraving.mesh.text=="45 lbs"
	var small_engraving:=small.find_children("EngravedWeight*","MeshInstance3D",true,false)
	valid=valid and small_engraving.size()==2 and small_engraving.all(func(mark):return mark.mesh.text=="2.5 lbs")
	valid=valid and large.find_children("*","Label3D",true,false).is_empty()
	var weights=preload("res://scripts/campus/facilities/gym_weights.gd").new()
	var pair: Node3D=weights._pair_model(25.0)
	var labels:=pair.find_children("*","Label3D",true,false)
	valid=valid and labels.size()==4 and labels.all(func(label):return label.text=="25.0")
	if not valid:push_error("Plate mesh profile, recessed weight marks, or cached geometry is invalid")
	small.free();large.free();another.free();gear.free();pair.free();weights.free()
	print("PLATE_GEOMETRY ","PASS" if valid else "FAIL")
	quit(0 if valid else 1)
