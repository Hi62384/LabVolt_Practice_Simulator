extends Node3D
## Optional restrained finish for M102 shop and teaching rooms; M101 stays untouched.
const IDS := ["shop","dc_lab","elm253_lecture","ety155_lecture","computer"]
var roots: Dictionary={}

func mount(id: String,campus: Node3D,registry: Object) -> bool:
	if id not in IDS or not is_instance_valid(campus) or not is_instance_valid(registry):return false
	if roots.has(id):return is_instance_valid(roots[id])
	var room: Dictionary=registry.call("get_room",id)
	if room.is_empty():return false
	var c: Array=room.center;var s: Array=room.size
	if c.size()!=3 or s.size()!=3:return false
	var cx:=float(c[0]);var cy:=float(c[1]);var cz:=float(c[2]);var width:=float(s[0]);var depth:=float(s[2])
	var root:=Node3D.new();root.name="ReferenceStyle_"+id;campus.add_child(root)
	# Wall-fixed wainscot and a single low baseboard. Keep teaching walls and doors clear.
	for z in [cz-depth*.5+.11,cz+depth*.5-.11]:
		_bar(root,Vector3(cx,cy+.53,z),Vector3(width-.5,1.04,.025),Color("7893a0"))
		_bar(root,Vector3(cx,cy+.08,z),Vector3(width-.5,.13,.04),Color("263c4c"))
	# Thin matte navy acoustic panels on the solid side wall only.
	var side_x:=cx-width*.5+.12 if cx<13 else cx+width*.5-.12
	for i in range(4):
		_bar(root,Vector3(side_x,cy+2.3,cz-3.45+i*2.3),Vector3(.035,1.30,.82),Color("263c4c"))
	# Rectangular luminous-looking fixture meshes, with no extra actual lights.
	for x in ([cx-2.7,cx+2.7] if id=="dc_lab" else [cx-4.5,cx,cx+4.5]):
		for z in [cz-2.8,cz+2.8]:
			_bar(root,Vector3(x,cy+3.96,z),Vector3(1.55,.045,.48),Color("e9e9dc"))
	if not campus.has_method("register_content") or not campus.call("register_content",id,root):root.queue_free();return false
	roots[id]=root;return true

func _bar(parent: Node3D,at: Vector3,size: Vector3,color: Color) -> void:
	var mesh:=BoxMesh.new();mesh.size=size
	var material:=StandardMaterial3D.new();material.albedo_color=color;material.roughness=.87
	var visual:=MeshInstance3D.new();visual.mesh=mesh;visual.position=at;visual.material_override=material;visual.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;parent.add_child(visual)
