extends Node3D
## M103-only presentation layer. The shell, doors, bench collisions and devices stay authoritative.
const ROOM_ID := "dc_lab"
const FLOOR := Color("8999ad")
const FLOOR_ALT := Color("93a2b4")
const WALL_BLUE := Color("587587")
const WALL_WHITE := Color("dcdfe5")
const FRAME := Color("344d59")
const WOOD := Color("a98868")
const Signage = preload("res://scripts/campus/presentation/entrance_signage.gd")
const Plant = preload("res://scripts/campus/presentation/decor/potted_plant.gd")
var root: Node3D

func mount(campus: Node3D, registry: Object) -> bool:
	if is_instance_valid(root): return true
	if not is_instance_valid(campus) or not is_instance_valid(registry): return false
	var room: Dictionary=registry.call("get_room",ROOM_ID)
	if room.is_empty() or str(room.get("number",""))!="M103": return false
	var low: Array=room.get("bounds_min",[])
	var high: Array=room.get("bounds_max",[])
	if low.size()!=3 or high.size()!=3: return false
	if absf(float(low[0])+10.0)>.01 or absf(float(high[0])-10.0)>.01 or absf(float(low[2])-13.0)>.01 or absf(float(high[2])-25.0)>.01: return false
	root=Node3D.new();root.name="M103RoomFinish";campus.add_child(root)
	# 1 mm overlay avoids replacing the solid floor or changing navigation and collision.
	for variant in range(2):
		var points: Array[Vector3]=[]
		for x in range(20):
			for z in range(12):
				if int((x*7+z*3)%9<2)==variant: points.append(Vector3(-9.5+x,.003,13.5+z))
		var tiles:=MultiMesh.new();tiles.transform_format=MultiMesh.TRANSFORM_3D
		var tile_mesh:=BoxMesh.new();tile_mesh.size=Vector3(.994,.006,.994);tiles.mesh=tile_mesh
		tiles.instance_count=points.size()
		for i in points.size(): tiles.set_instance_transform(i,Transform3D(Basis.IDENTITY,points[i]))
		var layer:=MultiMeshInstance3D.new();layer.multimesh=tiles
		var floor_mat:=StandardMaterial3D.new();floor_mat.albedo_color=FLOOR_ALT if variant==1 else FLOOR;floor_mat.roughness=.92
		layer.material_override=floor_mat;layer.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;root.add_child(layer)
	# All wall details sit within the room shell; the east entrance stays open.
	for z in [13.105,24.895]:
		_box(Vector3(0,2.62,z),Vector3(19.68,2.57,.025),WALL_WHITE)
		_box(Vector3(0,.72,z+.025 if z<19 else z-.025),Vector3(19.68,1.38,.035),WALL_BLUE)
		_box(Vector3(0,1.43,z+.04 if z<19 else z-.04),Vector3(19.68,.045,.05),FRAME)
	_box(Vector3(-9.895,2.62,19),Vector3(.025,2.57,11.68),WALL_WHITE)
	_box(Vector3(-9.86,.72,19),Vector3(.035,1.38,11.68),WALL_BLUE)
	# Ceiling panels and matching rectangular fixtures are meshes only.
	for x in range(8):
		for z in range(5):
			_box(Vector3(-8.75+x*2.5,4.028,14.2+z*2.4),Vector3(2.46,.018,2.36),WALL_WHITE)
	for x in [-6.0,0.0,6.0]:
		for z in [16.4,21.0]:
			_box(Vector3(x,3.936,z),Vector3(4.38,.108,.30),FRAME)
			_box(Vector3(x,3.871,z),Vector3(4.29,.024,.22),Color("fff3df"),true)
			preload("res://scripts/campus/presentation/fixture_light.gd").ceiling_omni(root, Vector3(x,3.84,z),1.35,7.2,false)
	for x in [-6.8, -2.8, 1.2, 5.2]:
		_box(Vector3(x,2.66,24.78),Vector3(.25,.25,.17),FRAME)
		_box(Vector3(x,2.524,24.765),Vector3(.20,.024,.13),Color("fff3df"),true)
	# Benches are already solid, correctly mapped to electrical and cable geometry.
	# Modest edging and rear modesty rails make their existing proportions legible.
	for x in [-6.0,0.0,6.0]:
		_box(Vector3(x,.81,23.475),Vector3(4.72,.052,.025),FRAME)
		_box(Vector3(x,.81,24.745),Vector3(4.72,.052,.025),FRAME)
		_box(Vector3(x,2.0,24.81),Vector3(3.25,.72,.07),FRAME)
		for i in range(6):
			var hook_x: float = x - 1.25 + i * .5
			_box(Vector3(hook_x,2.13,24.755),Vector3(.055,.055,.11),WOOD)
			_box(Vector3(hook_x,1.94,24.74),Vector3(.035,.32,.038),Color("c3c8ca"))
	_reference_board(Vector3(-5.5,2.13,13.20),"DC LAB / BENCH SAFETY","Turn outputs off before changing leads.\nCheck polarity and set the current limit.")
	_reference_board(Vector3(0,2.13,13.20),"DIGITAL MULTIMETER","Voltage: connect across the load.\nCurrent: insert the meter in series.")
	_reference_board(Vector3(5.5,2.13,13.20),"OSCILLOSCOPE","Use a shared reference.\nAdjust the timebase to show the waveform.")
	for z in [16.2,19.5]:
		_equipment_shelf(z)
	Signage.mount(root,"LAB EQUIPMENT",Vector3(-9.82,2.72,17.85),PI*.5,Vector2(3.15,.40),36)
	Plant.mount(root,Vector3(-9.2,0,21.45))
	Plant.mount(root,Vector3(8.95,0,14.15))
	if not campus.has_method("register_content") or not campus.call("register_content",ROOM_ID,root):
		root.queue_free();root=null;return false
	return true

func _equipment_shelf(z: float) -> void:
	_box(Vector3(-9.76,1.05,z),Vector3(.12,2.1,2.65),FRAME,false,true)
	for dz in [-1.28,1.28]:
		_box(Vector3(-9.46,1.05,z+dz),Vector3(.70,2.1,.09),FRAME,false,true)
	for level in 4:
		var y := .18+level*.50
		_box(Vector3(-9.46,y,z),Vector3(.70,.075,2.63),FRAME,false,true)
		for slot in 4:
			var at := Vector3(-9.48,y+.16,z-.96+slot*.64)
			var tint: Color = [Color("6c8c98"),Color("8a8f78"),Color("ad8b66"),Color("667c91")][(level+slot)%4]
			_box(at,Vector3(.46,.235,.48),tint)
			_box(at+Vector3(.236,.04,0),Vector3(.014,.062,.20),Color("ded6ba"))

func _reference_board(at: Vector3, title: String, detail: String) -> void:
	_box(at,Vector3(3.85,1.06,.064),FRAME)
	_box(at+Vector3(0,0,.039),Vector3(3.69,.91,.027),Color("d9ded7"))
	_sign(title,at+Vector3(0,.25,.062),0,.0033)
	_sign(detail,at+Vector3(0,-.12,.062),0,.0023)

func _sign(value: String,at: Vector3,yaw: float,pixel: float) -> void:
	var label:=Label3D.new();label.text=value;label.position=at;label.rotation.y=yaw
	label.font_size=44;label.pixel_size=pixel;label.modulate=FRAME;root.add_child(label)

func _box(at: Vector3,size: Vector3,tint: Color,emissive: bool=false,solid: bool=false) -> void:
	var mesh:=BoxMesh.new();mesh.size=size
	var mat:=StandardMaterial3D.new();mat.albedo_color=tint;mat.roughness=.85
	if emissive:mat.emission_enabled=true;mat.emission=tint;mat.emission_energy_multiplier=.5
	var node:=MeshInstance3D.new();node.mesh=mesh;node.position=at;node.material_override=mat
	node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;root.add_child(node)
	if solid:
		var body := StaticBody3D.new()
		body.collision_mask=0
		var hit := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size=size
		hit.shape=shape
		body.add_child(hit)
		node.add_child(body)
