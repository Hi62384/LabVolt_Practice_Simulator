extends Node3D
## Streamed M105 presentation and collision for the separate perimeter furnishings.
const DATA := "res://assets/campus/decor/m105/profiles.json"
var installed := false

func mount(campus: Node3D) -> bool:
	if installed or not is_instance_valid(campus):return installed
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(DATA))
	if not parsed is Dictionary:return false
	var profile: Dictionary=parsed.get("profiles",{}).get("gym",{})
	if profile.is_empty():return false
	var stage:=Node3D.new()
	stage.name="M105AuthoredGym"
	var origin: Array=profile.get("origin",[])
	if origin.size()!=3:return false
	stage.position=Vector3(float(origin[0]),float(origin[1]),float(origin[2]))
	for group in profile.get("groups",[]):
		var mesh: Mesh=load(str(group.get("mesh","")))
		var spec: Array=parsed.get("materials",{}).get(str(group.get("material","")),[])
		if mesh==null or spec.size()!=3:
			stage.free();return false
		var mat:=StandardMaterial3D.new()
		mat.albedo_color=Color(str(spec[0]))
		mat.roughness=float(spec[1]);mat.metallic=float(spec[2])
		var visual:=MeshInstance3D.new()
		visual.mesh=mesh;visual.material_override=mat
		visual.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		stage.add_child(visual)
	var furniture := StaticBody3D.new()
	furniture.name = "PerimeterFurniture"
	furniture.collision_mask = 0
	stage.add_child(furniture)
	# These bounds follow the authored meshes along the walls, outside training stations.
	for z in [-4.0,-3.0,-2.0,2.0,3.0,4.0]:
		_add_hit(furniture,Vector3(-9.35,1.0,z),Vector3(.78,2.0,.88))
	for x in [-5.6,4.8]:
		_add_hit(furniture,Vector3(x,.44,5.1),Vector3(2.2,.88,.56))
	_add_hit(furniture,Vector3(7.3,.83,4.78),Vector3(2.07,1.66,.72))
	for x in [1.0,2.2,3.4]:
		_add_hit(furniture,Vector3(x,.35,5.15),Vector3(.74,.7,.74))
	campus.add_child(stage)
	if campus.has_method("register_content"):campus.call("register_content","gym",stage)
	installed=true
	return true

func _add_hit(body: StaticBody3D, at: Vector3, size: Vector3) -> void:
	var shape := BoxShape3D.new()
	shape.size = size
	var hit := CollisionShape3D.new()
	hit.shape = shape
	hit.position = at
	body.add_child(hit)
