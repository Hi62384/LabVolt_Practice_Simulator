extends Node3D
## M101 shell and furniture finish. Never traverses or mutates AC equipment.

const Fixtures = preload("res://scripts/campus/presentation/fixture_light.gd")
const ROOM := "ac_lab"
const PROFILE := {"west":-10.0,"east":10.0,"south":-4.0,"north":10.0,"base":0.0,"number":"M101"}
const C := {"tile":Color("8693a7"),"tile_alt":Color("909caf"),"wall":Color("dedfe4"),"dado":Color("547187"),"navy":Color("334d60"),"white":Color("f0f1eb"),"wood":Color("bc946e"),"steel":Color("53666e"),"notice":Color("e5ba6c"),"diffuser":Color("fff2de")}
var roots: Dictionary = {}
var meshes: Dictionary = {}
var materials: Dictionary = {}

func mount(campus: Node3D, registry: Object) -> bool:
	if not is_instance_valid(campus) or not is_instance_valid(registry): return false
	if roots.has(ROOM): return is_instance_valid(roots[ROOM])
	var room: Dictionary = registry.call("get_room", ROOM)
	if room.is_empty() or str(room.get("number", "")) != PROFILE.number: return false
	var low: Array = room.get("bounds_min", []); var high: Array = room.get("bounds_max", [])
	if low.size()!=3 or high.size()!=3: return false
	if absf(float(low[0])-PROFILE.west)>.01 or absf(float(high[0])-PROFILE.east)>.01 or absf(float(low[2])-PROFILE.south)>.01 or absf(float(high[2])-PROFILE.north)>.01 or absf(float(low[1])-PROFILE.base)>.01: return false
	var root := Node3D.new(); root.name = "M101Environment"; campus.add_child(root)
	_build_floor(root)
	_build_walls(root)
	_build_ceiling(root)
	_build_furniture_finish(root)
	_build_teaching_details(root)
	if not campus.call("register_content", ROOM, root): root.queue_free(); return false
	roots[ROOM] = root
	return true

func _material(key: String) -> StandardMaterial3D:
	if materials.has(key): return materials[key]
	var mat := StandardMaterial3D.new(); mat.albedo_color=C[key]; mat.roughness=.94; mat.metallic=0.0
	if key == "diffuser":
		mat.emission_enabled = true
		mat.emission = C[key]
		mat.emission_energy_multiplier = .48
	materials[key]=mat
	return mat

func _box(parent: Node3D, name: String, at: Vector3, size: Vector3, key: String) -> MeshInstance3D:
	var mesh_key := str(size)
	if not meshes.has(mesh_key):
		var mesh := BoxMesh.new(); mesh.size=size; meshes[mesh_key]=mesh
	var node := MeshInstance3D.new(); node.name=name; node.mesh=meshes[mesh_key]; node.material_override=_material(key); node.position=at
	node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF; parent.add_child(node)
	return node

func _build_floor(root: Node3D) -> void:
	# Existing shell top is Y=0; legacy seams top at .0045. Tiles begin at .006.
	var positions := {"tile": [], "tile_alt": []}
	for ix in range(20):
		for iz in range(14):
			positions["tile_alt" if (ix+iz)%7==0 else "tile"].append(Vector3(-9.5+ix,.012,-3.5+iz))
	var tile := BoxMesh.new()
	tile.size = Vector3(.984,.012,.984)
	for key in positions:
		var batch := MultiMesh.new()
		batch.transform_format = MultiMesh.TRANSFORM_3D
		batch.mesh = tile
		batch.instance_count = positions[key].size()
		for index in batch.instance_count:
			batch.set_instance_transform(index, Transform3D(Basis.IDENTITY, positions[key][index]))
		var mesh := MultiMeshInstance3D.new()
		mesh.multimesh = batch
		mesh.material_override = _material(key)
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mesh)
	# Thin, noncolliding work-zone boundary. Existing tables and walking routes stay fixed.
	for x in [-6.0,0.0,6.0]:
		_box(root,"WorkBoundary",Vector3(x,.028,-1.63),Vector3(4.8,.004,.031),"notice")

func _build_walls(root: Node3D) -> void:
	for z in [-3.88,9.88]:
		_box(root,"LowerWall",Vector3(0,.62,z),Vector3(19.72,1.22,.035),"dado")
		_box(root,"UpperWall",Vector3(0,2.59,z),Vector3(19.72,2.70,.035),"wall")
		_box(root,"Baseboard",Vector3(0,.08,z+(.032 if z<0 else -.032)),Vector3(19.72,.15,.045),"navy")
		_box(root,"ChairRail",Vector3(0,1.26,z+(.033 if z<0 else -.033)),Vector3(19.72,.045,.048),"white")
	for x in [-9.88]:
		_box(root,"SideLowerWall",Vector3(x,.62,3),Vector3(.035,1.22,13.72),"dado")
		_box(root,"SideUpperWall",Vector3(x,2.59,3),Vector3(.035,2.70,13.72),"wall")
		_box(root,"SideBaseboard",Vector3(x+.032,.08,3),Vector3(.045,.15,13.72),"navy")
	# East doorway remains fully open. Solid side segments stop before its centre opening.
	for z in [-2.08,8.08]:
		_box(root,"DoorSideLower",Vector3(9.88,.62,z),Vector3(.035,1.22,3.6),"dado")
		_box(root,"DoorSideUpper",Vector3(9.88,2.59,z),Vector3(.035,2.70,3.6),"wall")

func _build_ceiling(root: Node3D) -> void:
	# Flush under the existing Y=4.05 shell, with a slim suspended strip in each bay.
	for x in range(-9,10,3):
		_box(root,"CeilingRunner",Vector3(float(x),4.017,3),Vector3(.025,.025,13.7),"steel")
	for z in range(-3,10,2):
		_box(root,"CeilingCrossbar",Vector3(0,4.017,float(z)),Vector3(19.7,.025,.025),"steel")
	for x in [-6.0,0.0,6.0]:
		for z in [0.0,6.0]:
			_box(root,"LightFrame",Vector3(x,3.94,z),Vector3(4.4,.11,.31),"navy")
			_box(root,"LightDiffuser",Vector3(x,3.876,z),Vector3(4.31,.025,.24),"diffuser")
			Fixtures.down(root, Vector3(x,3.82,z), 1.25, 7.2)

func _build_furniture_finish(root: Node3D) -> void:
	# Top skins follow the exact legacy desk positions; no existing table collision changes.
	for x in [-6.5,6.5]:
		for z in [1.5,6.0]:
			_box(root,"BenchTopEdge",Vector3(x,.897,z),Vector3(3.04,.030,1.24),"wood")
			for dx in [-1.35,1.35]:
				_box(root,"BenchFrame",Vector3(x+dx,.69,z),Vector3(.045,.055,1.03),"steel")
	for x in [-6.0,0.0,6.0]:
		_box(root,"StationBenchEdge",Vector3(x,.786,-2.9),Vector3(5.02,.026,1.22),"wood")
		for dx in [-2.25,2.25]:
			_box(root,"StationBrace",Vector3(x+dx,.55,-2.9),Vector3(.045,.045,.95),"steel")

func _build_teaching_details(root: Node3D) -> void:
	# The working lesson board is owned by SchoolWorld.
	_box(root,"NoticePanel",Vector3(-8.25,2.10,9.82),Vector3(1.82,.36,.034),"notice")
	_label(root,"SafetyNotice","ISOLATE POWER BEFORE WIRING",Vector3(-8.25,2.10,9.79),.0029,29)
	_box(root,"RoomSign",Vector3(0,3.63,9.82),Vector3(5.2,.34,.048),"navy")
	_label(root,"RoomTitle","M101 — AC ELECTRICAL LABORATORY",Vector3(0,3.63,9.78),.0042,34)
	for x in [-6.9, 6.9]:
		var at := Vector3(x, 2.87, 9.77)
		var size := Vector3(.47, .25, .25)
		_box(root,"WallSconce",at,size,"steel")
		_box(root,"SconceDiffuser",at + Vector3(0,-.13,-.015),Vector3(.40,.032,.195),"diffuser")
		var body := StaticBody3D.new()
		body.position = at
		root.add_child(body)
		var collision := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = size
		collision.shape = shape
		body.add_child(collision)
		Fixtures.down(root, at + Vector3(0,-.18,-.09), .85, 3.65, Vector3(0,-.93,.36).normalized())

func _label(parent: Node3D, name: String, value: String, at: Vector3, pixel: float, size: int) -> void:
	var label := Label3D.new(); label.name=name; label.text=value; label.position=at; label.rotation.y=PI; label.pixel_size=pixel; label.font_size=size; label.modulate=C.white; label.shaded=true; parent.add_child(label)
