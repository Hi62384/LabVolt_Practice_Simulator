extends Node3D
## Private M204/M205 finish candidate; room-local visuals only.
var mats: Dictionary={}
func material(color: String) -> StandardMaterial3D:
	if mats.has(color):return mats[color]
	var m:=StandardMaterial3D.new();m.albedo_color=Color(color);m.roughness=.85;mats[color]=m;return m
func box(at: Vector3,size: Vector3,color: String) -> void:
	var mesh:=BoxMesh.new();mesh.size=size
	var item:=MeshInstance3D.new();item.mesh=mesh;item.position=at;item.material_override=material(color)
	item.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;add_child(item)
func batch(points: Array,size: Vector3,color: String) -> void:
	var mesh:=BoxMesh.new();mesh.size=size
	var mm:=MultiMesh.new();mm.transform_format=MultiMesh.TRANSFORM_3D;mm.mesh=mesh;mm.instance_count=points.size()
	for i in points.size():mm.set_instance_transform(i,Transform3D(Basis.IDENTITY,points[i]))
	var item:=MultiMeshInstance3D.new();item.multimesh=mm;item.material_override=material(color)
	item.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;add_child(item)
func sign(value: String,at: Vector3,yaw: float=0) -> void:
	var item:=Label3D.new();item.text=value;item.position=at;item.rotation.y=yaw;item.font_size=40;item.pixel_size=.003
	item.billboard=BaseMaterial3D.BILLBOARD_DISABLED;item.no_depth_test=false;item.modulate=Color("eeeadd");add_child(item)
func build(room_id: String) -> bool:
	if not room_id in ["library","study"]:return false
	var quiet:=room_id=="study"
	var floor_a: Array=[];var floor_b: Array=[]
	for x in range(20):
		for z in range(12):(floor_a if (x+z)%4==0 else floor_b).append(Vector3(-9.5+x,.008,-5.5+z))
	batch(floor_a,Vector3(.984,.012,.984),"748287");batch(floor_b,Vector3(.984,.012,.984),"69797e")
	for z in [-5.88,5.88]:
		box(Vector3(0,1,z),Vector3(19.8,1.9,.035),"586f79")
		box(Vector3(0,2.95,z),Vector3(19.8,1.99,.035),"e2e3dc")
		box(Vector3(0,.11,z),Vector3(19.8,.2,.07),"354d59")
	var door_west:=not quiet
	var wall_x: float=-9.88 if door_west else 9.88
	for z in [-3.65,3.65]:
		box(Vector3(wall_x,1,z),Vector3(.035,1.9,4.55),"586f79")
		box(Vector3(wall_x,2.95,z),Vector3(.035,1.99,4.55),"e2e3dc")
	var other_x: float=9.88 if door_west else -9.88
	box(Vector3(other_x,1,0),Vector3(.035,1.9,11.8),"586f79")
	box(Vector3(other_x,2.95,0),Vector3(.035,1.99,11.8),"e2e3dc")
	var ceil_a: Array=[];var ceil_b: Array=[]
	for x in range(10):
		for z in range(6):(ceil_a if (x+z)%3==0 else ceil_b).append(Vector3(-9+x*2,3.96,-5+z*2))
	batch(ceil_a,Vector3(1.975,.025,1.975),"d7dedb");batch(ceil_b,Vector3(1.975,.025,1.975),"e3e7df")
	var fixtures: Array=[]
	for x in [-5,0,5]:
		for z in [-3,3]:fixtures.append(Vector3(x,3.925,z))
	batch(fixtures,Vector3(1.08,.018,1.08),"efe8d6")
	var plaque_x: float=-9.79 if door_west else 9.79
	box(Vector3(plaque_x,3.28,0),Vector3(.06,.38,2.3),"354d59")
	var title:="M204  LIBRARY / STUDY LOUNGE" if not quiet else "M205  QUIET STUDY"
	sign(title,Vector3(plaque_x+(.045 if door_west else -.045),3.28,0),PI/2 if door_west else -PI/2)
	box(Vector3(0,2.5,-5.77),Vector3(3,.8,.05),"354d59")
	sign("REFERENCE / READING" if not quiet else "FOCUS / INDEPENDENT STUDY",Vector3(0,2.5,-5.73))
	# Distinct M204 research notice and M205 acoustic-focus wall treatment.
	if quiet:
		for x in [-6,-3,0,3,6]:box(Vector3(x,1.9,5.74),Vector3(1.9,1.1,.045),"678779")
		box(Vector3(6.3,.02,2.8),Vector3(3.5,.015,2.8),"718696")
	else:
		box(Vector3(-6.6,1.9,5.74),Vector3(2.4,1.2,.05),"486376")
		sign("COURSES / REFERENCE",Vector3(-6.6,2.1,5.70),PI)
	return true
