extends Node3D
## M103 geometry only. Bind live state/actions in the separate electrical adapter.
const MODEL_ROOT := "res://review_artifacts/m103_dc_rebuild_20261107/physical_models/"
const COLORS := {"red":Color("d84943"),"black":Color("253139"),"yellow":Color("e2c451"),"cyan":Color("47b5bd")}
var port_targets: Dictionary = {}
var control_mounts: Dictionary = {}
var display_mounts: Dictionary = {}
var _devices: Dictionary = {}
var _port_rows: Dictionary = {}
static var _socket_mesh: Mesh
static var _button_mesh: Mesh
static var _knob_mesh: Mesh
static var _surround_mesh: Mesh
static var _insulators := {}

func build(index: int) -> void:
	var file := FileAccess.open(MODEL_ROOT+"ports.json",FileAccess.READ)
	assert(file!=null)
	var data: Dictionary=JSON.parse_string(file.get_as_text())
	file.close()
	assert(data.get("schema",0)==1)
	_socket_mesh=load(MODEL_ROOT+"meshes/socket.obj")
	_button_mesh=load(MODEL_ROOT+"meshes/button.obj")
	_knob_mesh=load(MODEL_ROOT+"meshes/knob.obj")
	if _surround_mesh==null:_surround_mesh=_annulus()
	for key in ["psu","meter","generator","scope","deck"]:
		var spec: Dictionary=data.devices[key]
		var root := Node3D.new();root.name=key;root.position=_vec(spec.origin);add_child(root)
		var case := MeshInstance3D.new();case.name="Enclosure";case.mesh=load(MODEL_ROOT+"meshes/"+("patchdeck" if key=="deck" else key)+".obj");root.add_child(case)
		_devices[key]=root
	for entry in data.ports:
		_make_port(index,entry)
	_make_mounts(index)

func _make_port(index: int,entry: Dictionary) -> void:
	var id := str(entry.id)
	assert(not port_targets.has(id))
	var parent: Node3D=_devices[str(entry.device)]
	var p := _vec(entry.xyz)
	assert(absf(p.z-float(entry.face_z))<.00001)
	var target := StaticBody3D.new();target.name="Port_"+id;target.position=p
	target.set_meta("role","dc_port");target.set_meta("dc_station",index)
	target.set_meta("dc_port",id);target.set_meta("label",entry.label)
	parent.add_child(target)
	var hit := CollisionShape3D.new();var shape := SphereShape3D.new();shape.radius=.028
	hit.shape=shape;hit.position=Vector3(0,0,.014);target.add_child(hit)
	var socket := MeshInstance3D.new();socket.name="MountedSocket";socket.mesh=_socket_mesh;target.add_child(socket)
	# The annular insulator is seated at the panel face. Its centre, pick target,
	# and lead anchor all derive from this target's transform.
	var surround := MeshInstance3D.new();surround.name="InsulatorSurround"
	surround.mesh=_surround_mesh
	var color_name := str(entry.color)
	if not _insulators.has(color_name):
		var material := StandardMaterial3D.new()
		material.albedo_color=COLORS[color_name];material.roughness=.8
		_insulators[color_name]=material
	surround.material_override=_insulators[color_name];target.add_child(surround)
	var label := Label3D.new();label.name="PrintedLegend";label.text=str(entry.label)
	label.position=Vector3(.08,0,.003);label.font_size=48;label.pixel_size=.00057
	label.modulate=Color("e8ede5");target.add_child(label)
	port_targets[id]=target;_port_rows[id]=entry

func port_positions() -> Dictionary:
	var anchors := {}
	for id in port_targets:
		var body: Node3D=port_targets[id]
		anchors[id]=body.to_global(Vector3(0,0,.023))
	return anchors

func socket_surface_position(id: String) -> Vector3:
	return port_targets[id].to_global(Vector3(0,0,.023))

func _make_mounts(index: int) -> void:
	for channel in 3:
		var x := (channel-1)*.45
		_display("psu_ch%d"%(channel+1),"psu",Vector3(x,.16,.007),Vector2(.36,.18))
		_control("psu_ch%d_voltage"%(channel+1),"psu",Vector3(x-.08,-.08,.007),true)
		_control("psu_ch%d_limit"%(channel+1),"psu",Vector3(x+.08,-.08,.007),true)
		_control("psu_ch%d_enable"%(channel+1),"psu",Vector3(x,-.15,.007),false)
	_control("psu_master","psu",Vector3(-.61,.30,.007),false)
	_display("meter","meter",Vector3(-.19,.025,.007),Vector2(.56,.145))
	_control("meter_mode","meter",Vector3(.37,.055,.007),true)
	_control("meter_range","meter",Vector3(.37,-.055,.007),false)
	_control("meter_fuse","meter",Vector3(.15,.08,.007),false)
	_display("generator","generator",Vector3(-.18,.045,.007),Vector2(.52,.12))
	for i in 3:
		_control(["generator_frequency","generator_amplitude","generator_offset"][i],"generator",Vector3(.13+i*.12,-.015,.007),true)
	_control("generator_wave","generator",Vector3(-.43,-.10,.007),false)
	_control("generator_output","generator",Vector3(.43,.10,.007),false)
	_display("scope_trace","scope",Vector3(-.20,.08,.007),Vector2(.84,.44))
	for i in 2:
		_control("scope_ch%d_scale"%(i+1),"scope",Vector3(.40,.17-i*.18,.007),true)
	_control("scope_timebase","scope",Vector3(.40,-.18,.007),true)
	_control("scope_trigger","scope",Vector3(.57,.10,.007),true)
	_control("scope_run","scope",Vector3(.57,-.09,.007),false)
	for i in 4:
		_control("is%d_enable"%(i+1),"deck",Vector3(-1.65+i*.50,.025,.007),false)

func _display(id: String,device: String,at: Vector3,size: Vector2) -> void:
	var mount := Node3D.new();mount.name="Display_"+id;mount.position=at
	mount.set_meta("display_id",id);mount.set_meta("width",size.x);mount.set_meta("height",size.y)
	_devices[device].add_child(mount);display_mounts[id]=mount

func _control(id: String,device: String,at: Vector3,knob: bool) -> void:
	var target := StaticBody3D.new();target.name="Control_"+id;target.position=at
	target.set_meta("role","dc_instrument_control")
	target.set_meta("control_id",id);target.set_meta("label",id.replace("_"," "))
	_devices[device].add_child(target)
	var hit := CollisionShape3D.new()
	if knob:
		var shape := SphereShape3D.new();shape.radius=.039;hit.shape=shape
	else:
		var shape := BoxShape3D.new();shape.size=Vector3(.068,.034,.04);hit.shape=shape
	hit.position.z=.02;target.add_child(hit)
	var visual := MeshInstance3D.new();visual.name="ControlGeometry"
	visual.mesh=_knob_mesh if knob else _button_mesh;target.add_child(visual)
	control_mounts[id]=target

static func _annulus() -> ArrayMesh:
	var vertices := PackedVector3Array();var normals := PackedVector3Array()
	for i in 16:
		var a := TAU*i/16.0;var b := TAU*(i+1)/16.0
		for sample in [[.038,a],[.027,b],[.027,a],[.038,a],[.038,b],[.027,b]]:
			var radius: float=sample[0];var angle: float=sample[1]
			vertices.append(Vector3(cos(angle)*radius,sin(angle)*radius,.002))
			normals.append(Vector3.BACK)
	var arrays := [];arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=vertices;arrays[Mesh.ARRAY_NORMAL]=normals
	var mesh := ArrayMesh.new();mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	return mesh

static func _vec(value: Array) -> Vector3:
	return Vector3(float(value[0]),float(value[1]),float(value[2]))
