extends Node3D
## Registry-guarded M203 fitout. Mount once; caller owns classroom session logic.

const STATION_SCRIPT = preload("res://scripts/campus/presentation/decor/computer_rooms/computer_station.gd")
const COLUMNS := [-7.2,-3.6,0.0,3.6,7.2]
const ROWS := [16.2,18.4,20.6,22.8]
const EXPECTED_MIN := Vector3(-10,5,13)
const EXPECTED_MAX := Vector3(10,9,25)
var stations: Dictionary = {}
var mounted := false
var root: Node3D
var materials: Dictionary = {}
var meshes: Dictionary = {}

func mount(campus: Node3D,registry: Object) -> bool:
	if mounted:return is_instance_valid(root)
	if not is_instance_valid(campus) or not is_instance_valid(registry):return false
	var room: Dictionary=registry.call("get_room","computer")
	if str(room.get("number",""))!="M203":return false
	if registry.vector(room.bounds_min) != EXPECTED_MIN or registry.vector(room.bounds_max) != EXPECTED_MAX:return false
	root=Node3D.new();root.name="M203ComputerClassroom";campus.add_child(root)
	_build_finish()
	_build_teaching_area()
	for row in ROWS.size():
		for column in COLUMNS.size():
			var id:="m203_r%d_c%d" % [row,column]
			var station=STATION_SCRIPT.new();root.add_child(station)
			station.position=Vector3(COLUMNS[column],5,ROWS[row]);station.configure(id)
			stations[id]=station
	if not campus.has_method("register_content") or not campus.call("register_content","computer",root):
		root.queue_free();root=null;stations.clear();return false
	mounted=true
	return true

func _build_finish() -> void:
	# The shell already supplies walls, floor, door and windows. These are thin interior skins.
	_box(Vector3(0,5.016,19),Vector3(19.5,.022,11.5),"tile")
	for x in range(1,10):
		_box(Vector3(-10+2*x,5.029,19),Vector3(.012,.003,11.5),"grout")
	for z in range(1,6):
		_box(Vector3(0,5.029,13+2*z),Vector3(19.5,.003,.012),"grout")
	# Lower blue-gray wall fields leave the east doorway entirely untouched.
	for z in [13.12,24.88]:
		_box(Vector3(0,5.56,z),Vector3(19.45,1.05,.025),"wall")
		_box(Vector3(0,6.12,z),Vector3(19.45,.07,.045),"wood")
		_box(Vector3(0,5.09,z),Vector3(19.45,.12,.055),"wood")
	_box(Vector3(-9.87,5.56,19),Vector3(.025,1.05,11.5),"wall")
	_box(Vector3(-9.85,6.12,19),Vector3(.045,.07,11.5),"wood")
	# Suspended ceiling appearance and slim light strips are non-colliding geometry.
	for x in [-6.0,-2.0,2.0,6.0]:
		for z in [16.2,20.0,23.0]:
			_box(Vector3(x,8.91,z),Vector3(2.8,.035,.78),"ceiling")
			_box(Vector3(x,8.88,z),Vector3(2.2,.018,.38),"light")
			preload("res://scripts/campus/presentation/fixture_light.gd").down(root,Vector3(x,8.84,z),.82,6.2)
	for x in [-8.0,-4.0,0.0,4.0,8.0]:
		_box(Vector3(x,8.93,19),Vector3(.018,.02,11.5),"grout")
	for z in [15.0,17.0,19.0,21.0,23.0]:
		_box(Vector3(0,8.93,z),Vector3(19.5,.02,.018),"grout")
	# Wall-mounted decor uses the solid west side and stays above chair clearance.
	for i in range(3):
		_box(Vector3(-9.83,7.32,16.2+i*3.0),Vector3(.025,.83,1.60),"poster")
		_box(Vector3(-9.79,7.32,16.2+i*3.0),Vector3(.012,.68,1.45),"paper")

func _build_teaching_area() -> void:
	# The existing academic board is placed at the south wall by school_world.
	# A teaching-display adapter mounts at this marker and mirrors that content.
	var display:=Marker3D.new();display.name="TeachingDisplayMount";display.position=Vector3(0,7.2,13.23);root.add_child(display)
	var desk:=StaticBody3D.new();desk.name="InstructorDesk";desk.set_meta("role","table");desk.set_meta("label","Instructor workstation");desk.position=Vector3(0,5,14.7);root.add_child(desk)
	var shape:=BoxShape3D.new();shape.size=Vector3(1.85,.08,.68)
	var hit:=CollisionShape3D.new();hit.shape=shape;hit.position.y=.75;desk.add_child(hit)
	_box(Vector3(0,5.75,14.7),shape.size,"wood")
	for x in [-.84,.84]:
		for z in [14.42,14.98]:_box(Vector3(x,5.37,z),Vector3(.055,.74,.055),"steel")
	_box(Vector3(.30,6.13,14.58),Vector3(.45,.30,.035),"dark")
	_box(Vector3(.30,6.13,14.605),Vector3(.40,.25,.005),"screen")
	_box(Vector3(.30,5.84,14.58),Vector3(.05,.18,.05),"steel")
	_box(Vector3(-.05,5.80,14.81),Vector3(.42,.018,.15),"dark")
	# Modest speakers flank the teaching area without covering the board.
	for x in [-4.4,4.4]:_box(Vector3(x,7.60,13.20),Vector3(.23,.45,.18),"dark")

func _box(at: Vector3,size: Vector3,key: String) -> void:
	var colors:={"tile":"8898ac","grout":"6c7d8e","wall":"58768a","wood":"bd936d","ceiling":"485a69","light":"fff4dd","poster":"345361","paper":"e5e7df","steel":"596771","dark":"26333d","screen":"35566b"}
	var mesh_key:=str(size)
	if not meshes.has(mesh_key):
		var mesh:=BoxMesh.new();mesh.size=size;meshes[mesh_key]=mesh
	if not materials.has(key):
		var material:=StandardMaterial3D.new();material.albedo_color=Color(str(colors[key]));material.roughness=.9
		if key == "light":
			material.emission_enabled = true
			material.emission = material.albedo_color
			material.emission_energy_multiplier = .40
		materials[key]=material
	var part:=MeshInstance3D.new();part.mesh=meshes[mesh_key];part.material_override=materials[key]
	part.position=at;part.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;root.add_child(part)
