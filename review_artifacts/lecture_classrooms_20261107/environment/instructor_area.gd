extends Node3D
## Course-neutral instructor furniture; functional board remains owned by SchoolWorld.
const IDS := ["elm253_lecture","ety155_lecture"]
var mounted: Dictionary={}
var mats: Dictionary={}

func mount(id: String,campus: Node3D,registry: Object) -> bool:
	if id not in IDS or not is_instance_valid(campus) or not is_instance_valid(registry):return false
	if mounted.has(id):return is_instance_valid(mounted[id])
	var room: Dictionary=registry.call("get_room",id)
	if room.is_empty():return false
	var c: Array=room.center
	if c.size()!=3 or room.get("size",[])!=[20,4,12]:return false
	var cx:=float(c[0]);var cy:=float(c[1]);var cz:=float(c[2])
	var scene:=Node3D.new();scene.name="InstructorArea_"+id;campus.add_child(scene)
	# Lectern is outside the x±2.85m live board and 3.5m lateral to teacher.
	_box(scene,Vector3(cx+3.65,cy+.82,cz-4.4),Vector3(1.25,.10,.65),Color("a88461"))
	for x in [cx+3.13,cx+4.17]:
		_box(scene,Vector3(x,cy+.4,cz-4.4),Vector3(.07,.8,.54),Color("526772"))
	_box(scene,Vector3(cx+3.65,cy+1.11,cz-4.55),Vector3(.32,.16,.24),Color("344a59"))
	# Small analog clock and a rear storage cabinet occupy perimeter space.
	var clock:=MeshInstance3D.new();var disk:=CylinderMesh.new();disk.top_radius=.25;disk.bottom_radius=.25;disk.height=.045;disk.radial_segments=16
	clock.mesh=disk;clock.position=Vector3(cx+6.3,cy+2.7,cz-5.7);clock.rotation.x=PI/2;clock.material_override=_mat(Color("dfddd0"));scene.add_child(clock)
	var cabinet_x:=cx-8.6 if cx<13 else cx+8.6
	_box(scene,Vector3(cabinet_x,cy+.79,cz+4.8),Vector3(.85,1.58,.56),Color("536a78"))
	_box(scene,Vector3(cabinet_x,cy+1.61,cz+4.8),Vector3(.9,.06,.61),Color("a88461"))
	if not campus.has_method("register_content") or not campus.call("register_content",id,scene):scene.queue_free();return false
	mounted[id]=scene;return true

func _mat(color: Color) -> StandardMaterial3D:
	var key:=color.to_html()
	if not mats.has(key):
		var m:=StandardMaterial3D.new();m.albedo_color=color;m.roughness=.85;mats[key]=m
	return mats[key]

func _box(parent: Node3D,at: Vector3,size: Vector3,color: Color) -> void:
	var mesh:=BoxMesh.new();mesh.size=size
	var inst:=MeshInstance3D.new();inst.mesh=mesh;inst.position=at;inst.material_override=_mat(color);inst.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;parent.add_child(inst)
