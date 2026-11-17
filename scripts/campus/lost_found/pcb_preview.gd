extends RefCounted
## A bounded visual-only description; firmware and private board data stay local.
const Board=preload("res://scripts/breadboard_model.gd")
const Design=preload("res://scripts/pcb_design/design.gd")
const Surface=preload("res://scripts/pcb_design/substrate.gd")
const Catalog=preload("res://scripts/electronics_catalog.gd")
const SCALE:=.13

static func describe(board: Dictionary) -> Dictionary:
	if var_to_bytes(board).size()>262144 or not board.get("standalone",false) or Board.validate(board,{},true)!="":return {}
	var part: Dictionary=board.parts[0]
	var bp: Dictionary=board.get("definitions",{}).get(str(part.type),{})
	if bp.get("package","")!="PCB" or not bp.get("footprint") is Dictionary:return {}
	var canvas=preload("res://scripts/breadboard_canvas.gd").new()
	canvas.board=board;canvas.size=Vector2(1000,440)
	var rect: Rect2=canvas.pcb_rect(part,bp)
	var outline: Array=[];var routes: Array=[];var pads: Array=[]
	if Design.active(bp):
		for point in bp.pcb_design.get("outline",[]):outline.append(Design.map_point(bp,point,rect))
		for pad in bp.pcb_design.get("pads",{}).values():pads.append(Design.map_point(bp,pad.position,rect))
		for route in bp.pcb_design.get("routes",[]):
			var points: Array=[]
			for point in route.points:points.append(Design.map_point(bp,point,rect))
			routes.append(points)
	else:outline=[rect.position,Vector2(rect.end.x,rect.position.y),rect.end,Vector2(rect.position.x,rect.end.y)]
	var devices: Array=[]
	for device in canvas.surface_devices():
		if devices.size()>=64:break
		var type:=str(device.get("type", ""))
		if type.length()>160 or Catalog.simulation_entry(type).is_empty():continue
		var row:={"id":"part"+str(devices.size()),"type":type,"center":device.center,"pins":device.get("pins",[]),"rotation":float(device.get("rotation",0))}
		if device.has("surface_size"):row.surface_size=device.surface_size
		devices.append(row)
	canvas.free()
	return {"outline":outline,"routes":routes,"pads":pads,"devices":devices,"color":str(bp.footprint.get("color","24775b"))}

static func point(pixel: Vector2,height: float) -> Vector3:
	var position:=Surface.board_point(pixel,0)*SCALE
	position.y=height
	return position

static func build(game: Node,parent: Node3D,preview: Dictionary) -> bool:
	var outline: Variant=preview.get("outline",[])
	if not outline is Array or outline.size()<3 or outline.size()>64:return false
	var polygon:=PackedVector2Array()
	for p in outline:
		if not p is Vector2 or not p.is_finite() or p.x<0 or p.x>1000 or p.y<0 or p.y>440:return false
		polygon.append(p)
	var triangles:=Geometry2D.triangulate_polygon(polygon)
	if triangles.is_empty():return false
	var surface:=SurfaceTool.new();surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for index in triangles:
		surface.set_normal(Vector3.UP);surface.add_vertex(point(polygon[index],.018))
	for index in polygon.size():
		var a:=point(polygon[index],.018);var b:=point(polygon[(index+1)%polygon.size()],.018)
		var normal: Vector3=(b-a).cross(Vector3.DOWN).normalized()
		for vertex in [a,b,a-Vector3.UP*.012,b,b-Vector3.UP*.012,a-Vector3.UP*.012]:surface.set_normal(normal);surface.add_vertex(vertex)
	var mesh:=MeshInstance3D.new();mesh.mesh=surface.commit()
	var material:=StandardMaterial3D.new();material.albedo_color=Color.from_string(str(preview.get("color","24775b")),Color("24775b"));material.roughness=.8;material.cull_mode=BaseMaterial3D.CULL_DISABLED
	mesh.material_override=material;mesh.name="PCB outline";parent.add_child(mesh)
	var paths: Variant=preview.get("routes",[])
	if paths is Array and paths.size()<=96:
		var copper:=SurfaceTool.new();copper.begin(Mesh.PRIMITIVE_TRIANGLES);var segment_count:=0
		for path in paths:
			if not path is Array or path.size()<2 or path.size()>16:continue
			for i in range(path.size()-1):
				if not _valid_point(path[i]) or not _valid_point(path[i+1]):continue
				var a:=point(path[i],.019);var b:=point(path[i+1],.019)
				if a.distance_squared_to(b)<1e-12:continue
				var side: Vector3=Vector3.UP.cross((b-a).normalized())*.0006
				for vertex in [a-side,b-side,a+side,b-side,b+side,a+side]:copper.set_normal(Vector3.UP);copper.add_vertex(vertex)
				segment_count+=1
		if segment_count>0:
			var copper_mesh:=MeshInstance3D.new();copper_mesh.mesh=copper.commit()
			var copper_mat:=StandardMaterial3D.new();copper_mat.albedo_color=Color("d4ae63");copper_mat.cull_mode=BaseMaterial3D.CULL_DISABLED
			copper_mesh.material_override=copper_mat;parent.add_child(copper_mesh)
	var pads: Variant=preview.get("pads",[])
	if pads is Array and pads.size()<=512:
		var valid_pads: Array=pads.filter(func(pad):return _valid_point(pad))
		if not valid_pads.is_empty():
			var cylinder:=CylinderMesh.new();cylinder.top_radius=.0012;cylinder.bottom_radius=.0012;cylinder.height=.001;cylinder.radial_segments=8
			var gold:=StandardMaterial3D.new();gold.albedo_color=Color("dfbf72");cylinder.material=gold
			var multimesh:=MultiMesh.new();multimesh.transform_format=MultiMesh.TRANSFORM_3D;multimesh.mesh=cylinder;multimesh.instance_count=valid_pads.size()
			for i in valid_pads.size():multimesh.set_instance_transform(i,Transform3D(Basis.IDENTITY,point(valid_pads[i],.019)))
			var pad_mesh:=MultiMeshInstance3D.new();pad_mesh.multimesh=multimesh;parent.add_child(pad_mesh)
	var devices: Variant=preview.get("devices",[])
	if devices is Array and devices.size()<=64:
		var renderer=preload("res://scripts/board_components_3d.gd").new();parent.add_child(renderer)
		renderer.scale=Vector3.ONE*SCALE;renderer.position.y=.018
		for device in devices:
			if not device is Dictionary or not _valid_point(device.get("center")) or not device.get("pins") is Array or device.pins.size()>64:continue
			if not device.get("id") is String or not device.get("type") is String or str(device.type).length()>160:continue
			if device.pins.any(func(pin):return not _valid_point(pin)):continue
			if device.has("surface_size") and (not device.surface_size is Vector2 or not device.surface_size.is_finite() or device.surface_size.x<0 or device.surface_size.y<0 or device.surface_size.x>1000 or device.surface_size.y>440):continue
			if not (device.get("rotation",0) is int or device.get("rotation",0) is float) or not is_finite(float(device.get("rotation",0))):continue
			var model: Dictionary=Catalog.simulation_entry(device.type)
			if model.is_empty():continue
			device=device.duplicate();device.rotation=float(device.get("rotation",0))
			var before:=renderer.get_child_count()
			renderer.build_device(game,device,model)
			if renderer.get_child_count()==before:
				var pos: Vector3=renderer.board_point(device.center,.035)
				game._box(renderer,pos,Vector3(.09,.025,.055),Color("253e45"))
		for label in renderer.find_children("*","Label3D",true,false):label.hide()
	return true

static func _valid_point(value: Variant) -> bool:
	return value is Vector2 and value.is_finite() and value.x>=0 and value.x<=1000 and value.y>=0 and value.y<=440
