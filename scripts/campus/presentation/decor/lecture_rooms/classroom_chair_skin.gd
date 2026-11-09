extends RefCounted
## Presentation skin on the existing rolling chair swivel; physics/network unchanged.
const UPHOLSTERY:=Color("344a59")
const FRAME:=Color("718089")
static var mats: Dictionary={}

static func dress(chair: CharacterBody3D) -> bool:
	if not is_instance_valid(chair) or not is_instance_valid(chair.swivel):return false
	var swivel: Node3D=chair.swivel
	if swivel.has_node("LectureChairSkin"):return true
	var root:=Node3D.new();root.name="LectureChairSkin";swivel.add_child(root)
	_box(root,Vector3(0,.51,0),Vector3(.57,.12,.55),UPHOLSTERY)
	_box(root,Vector3(0,.88,.255),Vector3(.56,.69,.09),UPHOLSTERY)
	for x in [-.32,.32]:
		_box(root,Vector3(x,.72,0),Vector3(.055,.045,.36),UPHOLSTERY)
		_box(root,Vector3(x,.61,.11),Vector3(.035,.25,.035),FRAME)
	for child in swivel.get_children():
		if child!=root and child is MeshInstance3D:child.hide()
	return true

static func _box(parent: Node3D,at: Vector3,size: Vector3,color: Color) -> void:
	var key:=color.to_html()
	if not mats.has(key):
		var mat:=StandardMaterial3D.new();mat.albedo_color=color;mat.roughness=.85;mats[key]=mat
	var mesh:=BoxMesh.new();mesh.size=size
	var inst:=MeshInstance3D.new();inst.mesh=mesh;inst.position=at;inst.material_override=mats[key];inst.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;parent.add_child(inst)
