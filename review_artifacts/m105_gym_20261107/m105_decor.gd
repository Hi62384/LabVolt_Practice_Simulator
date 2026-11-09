extends Node3D
## Streamed M105 presentation; leaves existing facility furniture and collision alone.
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
	campus.add_child(stage)
	if campus.has_method("register_content"):campus.call("register_content","gym",stage)
	installed=true
	return true
