extends RefCounted

const BITE_MATERIAL := preload("res://scripts/campus/facilities/food_bite.gdshader")

static func placed(item: String, servings: int, peer: int, title: String) -> StaticBody3D:
	var target := StaticBody3D.new()
	target.collision_layer=4;target.collision_mask=0
	target.set_meta("role","facility_food");target.set_meta("owner",peer);target.set_meta("label",title)
	var hit := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size=Vector3(.25,.18,.17)
	hit.shape=shape;hit.position.y=.09
	target.add_child(hit)
	target.add_child(build(item,servings))
	return target

static func build(item: String, servings: int = 4) -> Node3D:
	var food := Node3D.new()
	match item:
		"coffee", "tea":
			var color := "a82f37" if item == "coffee" else "ac6142"
			var cup := CylinderMesh.new()
			cup.top_radius=.06;cup.bottom_radius=.043;cup.height=.135;cup.cap_top=false
			var shell := _piece(food,cup,Vector3(0,.0675,0),color)
			shell.material_override.cull_mode=BaseMaterial3D.CULL_DISABLED
			var rim := TorusMesh.new()
			rim.inner_radius=.056;rim.outer_radius=.063
			_piece(food,rim,Vector3(0,.135,0),"e9d2a8")
			var height := .122*clampf(servings/3.0,0,1)
			_cylinder(food,lerpf(.042,.058,height/.135),.042,height,.006+height*.5,"38251d" if item=="coffee" else "b7773c")
		"water":
			var height := .127*clampf(servings/3.0,0,1)
			_cylinder(food,.044,.044,height,.004+height*.5,"71b8d4")
			var bottle := _cylinder(food, .047, .047, .134, .067, "8fc8dd")
			bottle.material_override.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
			bottle.material_override.albedo_color=Color("8fc8dd45")
			_cylinder(food, .025, .047, .028, .148, "b6e2ed")
			_cylinder(food, .026, .026, .022, .173, "35769e")
		"donut":
			var dough := TorusMesh.new()
			dough.inner_radius=.027;dough.outer_radius=.087
			_piece(food,dough,Vector3(0,.029,0),"bf7839")
			var icing := TorusMesh.new()
			icing.inner_radius=.029;icing.outer_radius=.083
			_piece(food,icing,Vector3(0,.039,0),"d88a9d",Vector3(1,.66,1))
			for i in 12:
				var angle := TAU*i/12.0
				var sprinkle := BoxMesh.new()
				sprinkle.size=Vector3(.013,.003,.004)
				_piece(food,sprinkle,Vector3(cos(angle)*.056,.057,sin(angle)*.056),["f9d58a","f4ead8","6c4037"][i%3]).rotation.y=angle
			if servings<2:_bite(food,.005,.047)
		_:
			var length := .245
			_oval(food,Vector3(0,.019,0),Vector3(length,.038,.094),"bb7839")
			_oval(food,Vector3(0,.036,0),Vector3(length,.022,.102),"659544")
			_oval(food,Vector3(0,.047,0),Vector3(length*.94,.021,.09),"bc7951" if item=="chicken_sub" else "bb4736")
			_oval(food,Vector3(0,.064,0),Vector3(length,.052,.095),"de9e52")
			for i in 4:
				_oval(food,Vector3((i-1.5)*length*.16,.088,.006*(i%2)),Vector3(.014,.005,.004),"f3d59d")
			if servings<4:_bite(food,(-.50+.25*clampi(servings,1,3))*length,.095)
	return food

static func _bite(food: Node3D, edge: float, half_depth: float) -> void:
	for part: MeshInstance3D in food.get_children():
		var material := ShaderMaterial.new()
		material.shader=BITE_MATERIAL
		material.set_shader_parameter("tint",part.material_override.albedo_color)
		material.set_shader_parameter("part_transform",part.transform)
		material.set_shader_parameter("bite_edge",edge)
		material.set_shader_parameter("half_depth",half_depth)
		part.material_override=material

static func _oval(root: Node3D, at: Vector3, size: Vector3, color: String) -> void:
	_piece(root,SphereMesh.new(),at,color,size)

static func _cylinder(root: Node3D, top: float, bottom: float, height: float, y: float, color: String) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius=top;mesh.bottom_radius=bottom;mesh.height=height;mesh.radial_segments=24
	return _piece(root,mesh,Vector3(0,y,0),color)

static func _piece(root: Node3D, mesh: Mesh, at: Vector3, color: String, size := Vector3.ONE) -> MeshInstance3D:
	var part := MeshInstance3D.new()
	var material := StandardMaterial3D.new()
	material.albedo_color=Color(color);material.roughness=.78
	part.mesh=mesh;part.material_override=material;part.position=at;part.scale=size
	part.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(part)
	return part
