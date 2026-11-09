extends Node3D
## M103-only presentation layer. The shell, doors, bench collisions and devices stay authoritative.
const ROOM_ID := "dc_lab"
const FLOOR := Color("a8b5b4")
const FLOOR_ALT := Color("b3bfbd")
const WALL_BLUE := Color("718b99")
const WALL_WHITE := Color("e1e7e3")
const FRAME := Color("344d59")
const WOOD := Color("a98868")
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
			_box(Vector3(x,3.996,z),Vector3(1.72,.055,.48),FRAME)
			_box(Vector3(x,3.961,z),Vector3(1.57,.018,.34),Color("f1eddc"),true)
	# Benches are already solid, correctly mapped to electrical and cable geometry.
	# Modest edging and rear modesty rails make their existing proportions legible.
	for x in [-6.0,0.0,6.0]:
		_box(Vector3(x,.81,21.205),Vector3(4.72,.052,.025),FRAME)
		_box(Vector3(x,.81,22.795),Vector3(4.72,.052,.025),FRAME)
		_chair(x,20.35)
	# Two low cabinets occupy the southwest wall, clear of the east entrance and aisles.
	for z in [15.0,17.1]: _cabinet(-8.85,z)
	_sign("DC ELECTRICAL LAB  ·  M103",Vector3(-8.9,2.76,13.17),0.0,.004)
	_sign("POWER  ·  MEASURE  ·  VERIFY",Vector3(-8.5,2.37,24.82),PI,.003)
	if not campus.has_method("register_content") or not campus.call("register_content",ROOM_ID,root):
		root.queue_free();root=null;return false
	return true

func _chair(x: float,z: float) -> void:
	_box(Vector3(x,.48,z),Vector3(.64,.09,.59),Color("4d6975"))
	_box(Vector3(x,.83,z-.27),Vector3(.64,.75,.09),Color("4d6975"))
	for dx in [-.23,.23]:
		for dz in [-.20,.20]: _box(Vector3(x+dx,.22,z+dz),Vector3(.055,.43,.055),FRAME)

func _cabinet(x: float,z: float) -> void:
	_box(Vector3(x,.72,z),Vector3(1.26,1.43,.62),FRAME)
	_box(Vector3(x,.74,z+.318),Vector3(1.14,1.31,.027),Color("d0d9d5"))
	_box(Vector3(x,.74,z+.338),Vector3(.018,1.23,.012),FRAME)
	for dx in [-.09,.09]: _box(Vector3(x+dx,.82,z+.365),Vector3(.025,.17,.03),WOOD)

func _sign(value: String,at: Vector3,yaw: float,pixel: float) -> void:
	var label:=Label3D.new();label.text=value;label.position=at;label.rotation.y=yaw
	label.font_size=44;label.pixel_size=pixel;label.modulate=FRAME;root.add_child(label)

func _box(at: Vector3,size: Vector3,tint: Color,emissive: bool=false) -> void:
	var mesh:=BoxMesh.new();mesh.size=size
	var mat:=StandardMaterial3D.new();mat.albedo_color=tint;mat.roughness=.85
	if emissive:mat.emission_enabled=true;mat.emission=tint;mat.emission_energy_multiplier=.5
	var node:=MeshInstance3D.new();node.mesh=mesh;node.position=at;node.material_override=mat
	node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;root.add_child(node)
