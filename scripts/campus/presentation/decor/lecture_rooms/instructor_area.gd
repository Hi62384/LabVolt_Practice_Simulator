extends Node3D
## Perimeter storage for the lecture rooms. TeachingRoomFinish owns the instructor area.
const IDS := ["elm253_lecture","ety155_lecture"]
var mounted: Dictionary={}
var mats: Dictionary={}

func mount(id: String,campus: Node3D,registry: Object) -> bool:
	if id not in IDS or not is_instance_valid(campus) or not is_instance_valid(registry):return false
	if mounted.has(id):return is_instance_valid(mounted[id])
	var room: Dictionary=registry.call("get_room",id)
	if room.is_empty():return false
	var c: Array=room.center
	if c.size()!=3 or registry.vector(room.get("size", [])) != Vector3(20,4,12):return false
	var cx:=float(c[0]);var cy:=float(c[1]);var cz:=float(c[2])
	var scene:=Node3D.new();scene.name="InstructorArea_"+id;campus.add_child(scene)
	var cabinet_x:=cx-8.6 if cx<13 else cx+8.6
	var cabinet_at:=Vector3(cabinet_x,cy+.79,cz+4.8)
	var cabinet_size:=Vector3(.85,1.58,.56)
	_box(scene,cabinet_at,cabinet_size,Color("536a78"))
	_box(scene,Vector3(cabinet_x,cy+1.61,cz+4.8),Vector3(.9,.06,.61),Color("a88461"))
	var body:=StaticBody3D.new()
	body.position=cabinet_at
	body.collision_mask=0
	var hit:=CollisionShape3D.new()
	var shape:=BoxShape3D.new()
	shape.size=cabinet_size
	hit.shape=shape
	body.add_child(hit)
	scene.add_child(body)
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
