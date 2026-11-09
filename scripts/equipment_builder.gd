extends Node3D
## Procedural equipment geometry retained and improved from the v0.1 project.
## Gameplay, UI, electrical state and networking live in separate modules.

const Catalog = preload("res://scripts/equipment_catalog.gd")
const PANEL_Z := -3.0
const SKIN_Z := 0.13
const JACKET_COLORS := [Color("ed645a"), Color("478bff"), Color("ffd53c"), Color("222938")]
const JACKET_NAMES := ["RED", "BLUE", "YELLOW", "BLACK"]
const BLACK_PANEL := Color("19232e")
const LIGHT_PANEL := Color("c8cdd1")
const PALE_PANEL := Color("b9c3c9")
const TEXT_LIGHT := Color("f3f5fa")
const TEXT_DARK := Color("182431")

var player: Node3D
var camera: Camera3D
var cables_root: Node3D
var terminal_bodies: Dictionary = {}     # id -> StaticBody3D
var terminal_ids: Array[String] = []
var control_bodies: Dictionary = {}      # special interaction bodies
var igbt_indicators: Array[StandardMaterial3D] = []
var switch_meshes: Dictionary = {}       # "R_0" -> {lever, led}
var needle_bodies: Dictionary = {}       # "AMP0" -> Node3D
var leads: Array[Dictionary] = []
var toggles: Dictionary = {}
var powered := false
var variable_level := 0.58
var dyn_load := 0.0
var supply_display: Label3D
var dynamo_display: Label3D
var chosen_color := 1
var pending_port := ""
var current_target: StaticBody3D
var readings: Dictionary = {}
var practice_task := 0
var show_hints := true
var mouse_sensitivity := 0.00225
var notice := "Power is OFF. Start by aiming at a socket and left-clicking."

var info_label: RichTextLabel
var control_label: RichTextLabel
var status_label: Label
var hover_label: Label
var crosshair: Label
var task_label: RichTextLabel
var warning_label: Label
var panel_materials: Dictionary = {}

func _reset_switches() -> void:
	toggles = {}
	for kind in ["R", "L", "C"]:
		var active: Array[bool] = []
		for i in range(9):
			active.append(false)
		toggles[kind] = active

func _mat(color: Color, metallic := 0.05, emission := false) -> StandardMaterial3D:
	var key := "%s_%0.2f_%s" % [color.to_html(), metallic, str(emission)]
	if panel_materials.has(key):
		return panel_materials[key]
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.metallic = metallic
	material.roughness = 0.51 if metallic > 0.5 else 0.8
	if emission:
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = 0.5
	panel_materials[key] = material
	return material

func _box(parent: Node3D, pos: Vector3, size: Vector3, color: Color, metallic := 0.1) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var inst := MeshInstance3D.new()
	inst.mesh = mesh
	inst.position = pos
	inst.material_override = _mat(color, metallic)
	parent.add_child(inst)
	return inst

func _cylinder(parent: Node3D, pos: Vector3, radius: float, height: float, color: Color, metallic := 0.1) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 18
	var inst := MeshInstance3D.new()
	inst.mesh = mesh
	inst.position = pos
	inst.material_override = _mat(color, metallic)
	parent.add_child(inst)
	return inst

func _sphere(parent: Node3D, pos: Vector3, radius: float, color: Color) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	var inst := MeshInstance3D.new()
	inst.mesh = mesh
	inst.position = pos
	inst.material_override = _mat(color, 0.2)
	parent.add_child(inst)
	return inst

func _line(parent: Node3D, a: Vector3, b: Vector3, radius: float, color: Color, metallic := 0.2) -> MeshInstance3D:
	var delta := b - a
	if delta.length() < 0.002:
		return null
	var inst := _cylinder(parent, (a + b) * 0.5, radius, delta.length(), color, metallic)
	inst.quaternion = Quaternion(Vector3.UP, delta.normalized())
	return inst

func _text3(parent: Node3D, text: String, pos: Vector3, height := 0.052, color := TEXT_DARK) -> Label3D:
	var label := Label3D.new()
	label.text = text
	label.font_size = 48
	label.pixel_size = height / 48.0
	label.modulate = color
	label.position = pos
	# Printed legends sit just in front of the solid face, not inside it.
	if parent.has_meta("printed_face_z"):
		label.position.z=maxf(label.position.z,float(parent.get_meta("printed_face_z"))+.003)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.outline_size = 0
	parent.add_child(label)
	return label

func _build_environment() -> void:
	var lighting := preload("res://assets/campus/lighting/campus_lighting_rig.tscn").instantiate()
	add_child(lighting)
	var soft_light := OmniLight3D.new()
	soft_light.position = Vector3(0, 3.9, 0.6)
	soft_light.light_energy = 0.7
	soft_light.omni_range = 12.0
	add_child(soft_light)
	_box(self, Vector3(0, -0.14, 0), Vector3(25, 0.08, 17), Color("6a717b"), 0.0)
	_box(self, Vector3(0, 2.3, -3.65), Vector3(15, 7, .20), Color("bdc4ca"), 0.0)
	_box(self, Vector3(0, 3.90, -3.5), Vector3(6.6, .43, .12), Color("747d87"), 0.0)

func _build_player() -> void:
	player = Node3D.new()
	player.name = "FirstPersonPlayer"
	add_child(player)
	player.position = Vector3(0, 0, 1.75)
	camera = Camera3D.new()
	camera.name = "Eyes"
	camera.position.y = 1.72
	camera.fov = 72.0
	camera.current = true
	player.add_child(camera)
	cables_root = Node3D.new()
	cables_root.name = "PatchLeads"
	add_child(cables_root)

func _make_module(title: String, x: float, y: float, width: float, height: float, shade: Color, dark := false) -> Node3D:
	var group := Node3D.new()
	group.name = title.replace(" ", "_") if title != "" else "InstrumentPanel"
	group.position = Vector3(x, y, PANEL_Z)
	group.set_meta("printed_face_z",.115+.050*.5)
	group.set_meta("printed_face_dark",dark)
	group.set_meta("terminal_legend_min_y",-height*.5+.05)
	add_child(group)
	_box(group, Vector3(0, 0, 0.035), Vector3(width, height, .11), Color("3d4751"), 0.4)
	_box(group, Vector3(0, 0, .115), Vector3(width - .032, height - .03, .050), shade, 0.25 if not dark else 0.05)
	_text3(group, title, Vector3(0, height * 0.5 - 0.085, .137), .047, TEXT_LIGHT if dark else TEXT_DARK)
	# Panel fasteners
	for corner_x in [-width * 0.5 + .075, width * .5 - .075]:
		for corner_y in [-height * .5 + .065, height * .5 - .065]:
			var screw := _cylinder(group, Vector3(corner_x,corner_y,.139), .013, .010, Color("a5a9ad"), .9)
			screw.rotation.x = PI * 0.5
	return group

func _socket(parent: Node3D, id: String, label: String, pos: Vector2, color: Color, legend_height := .031) -> void:
	var jack := StaticBody3D.new()
	jack.name = id
	jack.position = Vector3(pos.x, pos.y, SKIN_Z + .060)
	jack.set_meta("role", "socket")
	jack.set_meta("id", id)
	jack.set_meta("label", label)
	parent.add_child(jack)
	var shape := SphereShape3D.new()
	shape.radius = .062
	var collision := CollisionShape3D.new()
	collision.shape = shape
	jack.add_child(collision)
	var mount := _cylinder(jack,Vector3(0,0,-.032),.043,.050,color,.4)
	mount.rotation.x=PI*.5
	var rim := _cylinder(jack, Vector3.ZERO, .055, .035, color, .45)
	rim.rotation.x = PI * .5
	var sleeve := _cylinder(jack, Vector3(0,0,.023), .028, .043, Color("202a35"), 0.1)
	sleeve.rotation.x = PI * .5
	_sphere(jack, Vector3(0,0,.041), .011, Color("090d13"))
	var module_upper := String(parent.name).to_upper()
	var dark_panel: bool = parent.get_meta("printed_face_dark", false) or module_upper.begins_with("RESIST") or module_upper.begins_with("THREE-PHASE") or module_upper.begins_with("POWER") or module_upper.begins_with("SQUIRREL") or module_upper.begins_with("ELECTRO-")
	var legend_y := pos.y-.105
	if parent.has_meta("terminal_legend_min_y"):legend_y=maxf(legend_y,float(parent.get_meta("terminal_legend_min_y")))
	var legend := _text3(parent, label, Vector3(pos.x,legend_y,.138), legend_height, TEXT_LIGHT if dark_panel else TEXT_DARK)
	legend.set_meta("terminal_legend",true)
	terminal_bodies[id] = jack
	terminal_ids.append(id)

func _decorative_socket(parent: Node3D, label: String, pos: Vector2, color: Color, dark := true) -> void:
	var rim := _cylinder(parent, Vector3(pos.x,pos.y,SKIN_Z+.02), .037, .027, color, .4)
	rim.rotation.x = PI * .5
	var inside := _cylinder(parent, Vector3(pos.x,pos.y,SKIN_Z+.04), .016, .029, Color("16202c"), .1)
	inside.rotation.x = PI * .5
	_text3(parent, label, Vector3(pos.x,pos.y-.073,SKIN_Z+.002), .027, TEXT_LIGHT if dark else TEXT_DARK)

func _switch(parent: Node3D, kind: String, index: int, pos: Vector2) -> void:
	var toggle := StaticBody3D.new()
	toggle.name = "%s_switch_%d" % [kind,index+1]
	toggle.position = Vector3(pos.x,pos.y,SKIN_Z+.055)
	toggle.set_meta("role", "switch")
	toggle.set_meta("kind", kind)
	toggle.set_meta("index", index)
	toggle.set_meta("label", "%s load bank %d, element %d" % [kind,int(index/3)+1,index%3+1])
	parent.add_child(toggle)
	var collision := CollisionShape3D.new()
	var shape := SphereShape3D.new()
	shape.radius = .067
	collision.shape = shape
	toggle.add_child(collision)
	var mount := _cylinder(toggle,Vector3(0,0,-.026),.026,.048,Color("8c9197"),.7)
	mount.rotation.x=PI*.5
	var base := _cylinder(toggle, Vector3(0,0,0), .034, .030, Color("8c9197"), .7)
	base.rotation.x = PI * .5
	var lever_root := Node3D.new()
	lever_root.position.z = .020
	toggle.add_child(lever_root)
	_line(lever_root, Vector3.ZERO, Vector3(0,.075,.040), .013, Color("dfe2e2"), .8)
	_sphere(lever_root, Vector3(0,.075,.040), .018, Color("e3e6e8"))
	var lamp_mount := _cylinder(toggle,Vector3(.044,-.045,-.021),.014,.066,Color("303b42"))
	lamp_mount.rotation.x=PI*.5
	var indicator := _sphere(toggle,Vector3(.044,-.045,.01),.014,Color("526070"))
	switch_meshes["%s_%d" % [kind,index]] = {"handle": lever_root, "indicator": indicator}

func _control(parent: Node3D, id: String, label: String, pos: Vector2, color: Color, size := .075) -> void:
	var body := StaticBody3D.new()
	body.name = id
	body.position = Vector3(pos.x,pos.y,SKIN_Z+.058)
	body.set_meta("role", "control")
	body.set_meta("id", id)
	body.set_meta("label", label)
	parent.add_child(body)
	var coll := CollisionShape3D.new()
	var shape := SphereShape3D.new()
	shape.radius = size
	coll.shape = shape
	body.add_child(coll)
	var mount := _cylinder(body,Vector3(0,0,-.035),size*.52,.040,Color("303b42"),.5)
	mount.rotation.x=PI*.5
	var knob := _cylinder(body, Vector3.ZERO, size * .77, .062, color,.65)
	knob.rotation.x = PI*.5
	_line(body,Vector3(0,0,.038),Vector3(0,size*.48,.042),.009,Color("eef2f4"))
	control_bodies[id] = body

func _meter(parent: Node3D, name: String, pos: Vector2, width: float, height: float, desc: String) -> void:
	var group := Node3D.new()
	group.position = Vector3(pos.x,pos.y,0)
	parent.add_child(group)
	_box(group,Vector3(0,0,.14),Vector3(width+.025,height+.025,.045),Color("777d77"),.7)
	_box(group, Vector3(0,0,.153), Vector3(width,height,.035),Color("e4e4d8"),.05)
	_box(group, Vector3(0,-height*.32,.181), Vector3(width*.92,height*.25,.012),Color("29313d"),.15)
	_text3(group,desc,Vector3(0,height*.1,.184),.025,TEXT_DARK)
	for rib in range(7):
		_box(group,Vector3(0,-height*.40+rib*.012,.191),Vector3(width*.65,.004,.004),Color("626965"))
	for k in range(6):
		var angle := deg_to_rad(150 - k*24)
		var center := Vector3(0,-height*.32,.19)
		var tip := center + Vector3(cos(angle)*height*.63,sin(angle)*height*.63,0)
		var start := center + Vector3(cos(angle)*height*.54,sin(angle)*height*.54,0)
		_line(group,start,tip,.0028,Color("252c37"),0)
	var pivot := Node3D.new()
	pivot.position = Vector3(0,-height*.32,.194)
	group.add_child(pivot)
	_line(pivot,Vector3.ZERO,Vector3(0,height*.59,0),.0045,Color("e95f4d"),.2)
	_sphere(pivot,Vector3.ZERO,.014,Color("202a34"))
	needle_bodies[name] = pivot

func _build_station() -> void:
	# The outer workstation rack is photo-inspired. Dimensions and labeling are approximate.
	_box(self,Vector3(0,2.28,-3.09),Vector3(6.52,4.50,.19),Color("303741"),.55)
	for xpos in [-3.29,3.29]:
		_box(self,Vector3(xpos,2.335,-2.98),Vector3(.125,4.61,.18),Color("1e242c"),.6)
	for ypos in [.055,1.90,2.75,3.66,4.48]:
		_box(self,Vector3(0,ypos,-2.99),Vector3(6.50,.048,.14),Color("1e252e"),.4)
	_make_ammeters()
	_make_wattmeters()
	_make_voltmeters()
	_make_load("R",-2.11,LIGHT_PANEL, "VARIABLE RESISTANCE")
	_make_load("L",0.0,LIGHT_PANEL, "VARIABLE INDUCTANCE")
	_make_load("C",2.11,LIGHT_PANEL, "VARIABLE CAPACITANCE")
	_make_daq()
	_make_switch_board()
	_make_transformer()
	_make_supply()
	_make_dynamometer()
	_make_motor()

func _make_ammeters() -> void:
	var panel := _make_module("AC AMMETER",-2.11,4.07,2.04,.78,LIGHT_PANEL)
	for i in range(3):
		var x := -.64+i*.64
		_meter(panel,"AMP%d"%i,Vector2(x,.035),.45,.43,"A")
		var col: Color = [Color("bd393d"),Color("20242a"),Color("3879ba")][i]
		var suffixes := ["OUT","IN","2_5","8","25"] if i==1 else ["OUT","IN","2_5","8"]
		var values := ["±","0.5","2.5","8","25"]
		for j in range(suffixes.size()):
			var px := x-.23+j*.46/(suffixes.size()-1)
			_socket(panel,"AM%d_%s"%[i,suffixes[j]],values[j],Vector2(px,-.265),col)

func _make_wattmeters() -> void:
	var panel := _make_module("",0,4.07,2.04,.78,BLACK_PANEL,true)
	for i in range(2):
		var x := -.49+i*.98
		_meter(panel,"WATT%d"%i,Vector2(x,.12),.91,.42,"W")
		_socket(panel,"W%d_IN"%i,str(1+i*3),Vector2(x-.29,-.235),Color("bc3c3e"),.042)
		_socket(panel,"W%d_OUT"%i,str(2+i*3),Vector2(x,-.235),Color("252a30"),.042)
		_socket(panel,"W%d_VN"%i,str(3+i*3),Vector2(x+.29,-.235),Color("3678bc"),.042)
		terminal_ids.append("W%d_VP"%i)
	_text3(panel,"Three-Phase Wattmeter",Vector3(0,-.14,.15),.028,TEXT_LIGHT)
	_text3(panel,"FESTO",Vector3(.78,-.14,.15),.03,TEXT_LIGHT)

func _make_voltmeters() -> void:
	var panel := _make_module("AC VOLTMETER",2.11,4.07,2.04,.78,LIGHT_PANEL)
	for i in range(3):
		var x := -.64+i*.64
		_meter(panel,"VOLT%d"%i,Vector2(x,.035),.45,.43,"V")
		_socket(panel,"V%d_COM"%i,"±",Vector2(x-.16,-.265),Color("252a30"))
		_socket(panel,"V%d_150"%i,"100",Vector2(x,-.265),Color("e0c745"))
		_socket(panel,"V%d_300"%i,"250",Vector2(x+.16,-.265),Color("e0c745"))

func _make_load(kind: String,x: float,_color: Color,title: String) -> void:
	var p := _make_module(title,x,3.205,2.04,.88,LIGHT_PANEL)
	for bank in range(3):
		var bx := -.64+bank*.64
		var color: Color = [Color("c44348"),Color("24272b"),Color("4287c8")][bank]
		_socket(p,"%s%d_P"%[kind,bank],"",Vector2(bx,.23),color)
		_socket(p,"%s%d_N"%[kind,bank],"",Vector2(bx,-.23),color)
		for dx in [-.16,0,.16]:
			_line(p,Vector3(bx,.22,.145),Vector3(bx+dx,.13,.145),.002,TEXT_DARK)
			_line(p,Vector3(bx+dx,-.15,.145),Vector3(bx,-.23,.145),.002,TEXT_DARK)
		for j in range(3):
			var sx := bx+(j-1)*.16
			_switch(p,kind,bank*3+j,Vector2(sx,.065))
			var top := -.015
			var bottom := -.145
			if kind=="R":
				var last := Vector3(sx,top,.148)
				for k in range(1,11):
					var point := Vector3(sx+(.018 if k%2==0 else -.018),top-k*.012,.148)
					_line(p,last,point,.0025,TEXT_DARK)
					last=point
			elif kind=="L":
				for turn in range(4):
					var last := Vector3(sx,top-turn*.032,.148)
					for k in range(1,13):
						var angle := PI*k/12
						var point := Vector3(sx+sin(angle)*.027,top-turn*.032-(1-cos(angle))*.016,.148)
						_line(p,last,point,.0025,TEXT_DARK)
						last=point
			else:
				_line(p,Vector3(sx,top,.148),Vector3(sx,-.065,.148),.0025,TEXT_DARK)
				_line(p,Vector3(sx,-.092,.148),Vector3(sx,bottom,.148),.0025,TEXT_DARK)
				for yy in [-.065,-.092]:
					_line(p,Vector3(sx-.025,yy,.148),Vector3(sx+.025,yy,.148),.003,TEXT_DARK)
			_text3(p,Catalog.LOADS[kind].labels[j],Vector3(sx-.065,-.09,.151),.027,Color("090d12"))

	_text3(p,{"R":"RESISTANCE RATING","L":"INDUCTANCE RATING","C":"CAPACITANCE RATING"}[kind],Vector3(-.40,-.33,.145),.025,TEXT_DARK)
	_text3(p,"OTHER FUNCTIONS",Vector3(.65,-.33,.145),.022,TEXT_DARK)

func _face(parent: Node3D,asset: String,width: float,height: float,z: float=.141) -> void:
	var mesh := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size=Vector2(width,height)
	mesh.mesh=quad
	mesh.position.z=z
	var material := StandardMaterial3D.new()
	material.albedo_texture=load("res://assets/panels/"+asset+".svg")
	material.texture_filter=BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	material.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh.material_override=material
	parent.add_child(mesh)
func _small_port(parent: Node3D,id: String,px: float,py: float,color: Color,height: float=.82) -> void:
	_socket(parent,id,"",Vector2(px/1000-1.02,height*.5-py/1000),color)
	terminal_bodies[id].scale=Vector3.ONE*.62
	terminal_bodies[id].set_meta("label",id.replace("_"," "))
func _make_daq() -> void:
	var p := _make_module("",-2.11,2.33,2.04,.82,BLACK_PANEL,true)
	_face(p,"daq",2.04,.82)
	for i in range(4):
		var y := 185+i*125
		_small_port(p,"DAQ_E%d_N"%i,120,y,Color("202126"))
		_small_port(p,"DAQ_E%d_P"%i,250,y,Color("cc4145"))
		_small_port(p,"DAQ_I%d_N"%i,400,y,Color("202126"))
		_small_port(p,"DAQ_I%d_4"%i,550,y,Color("cc4145"))
		_small_port(p,"DAQ_I%d_40"%i,690,y,Color("cc4145"))
	for i in range(2):
		_small_port(p,"DAQ_AO%d"%i,880+i*135,200,Color("e8ce39"))
		_small_port(p,"DAQ_AO%d_N"%i,880+i*135,310,Color("e2ded0"))
	for i in range(3):
		_small_port(p,"DAQ_DI%d"%i,1200+i*150,200,Color("e8ce39"))
		_small_port(p,"DAQ_DI%d_N"%i,1200+i*150,310,Color("e2ded0") if i<2 else Color("39845b"))
	for i in range(8):_small_port(p,"DAQ_AI%d"%i,860+(i%4)*135,520+(i/4)*100,Color("e8ce39"))
	for i in range(2):_small_port(p,"DAQ_DO%d"%i,1420+i*100,520,Color("e8ce39"))
	terminal_bodies.DAQ_DI2_N.set_meta("label","DAQ signal common / DI2 return")
	_control(p,"daq","Read DAQ channels",Vector2(.79,.15),Color("879897"),.05)
func _make_switch_board() -> void:
	var p := _make_module("",0,2.33,2.04,.82,BLACK_PANEL,true)
	_face(p,"inverter",2.04,.82)
	for i in range(6):_small_port(p,"IGBT_GATE%d"%(i+1),275+(i%2)*130,280+(i/2)*100,Color("e8ce39"))
	_small_port(p,"IGBT_DISABLE",120,445,Color("e8ce39"))
	_small_port(p,"IGBT_SYNC",120,580,Color("e8ce39"))
	_small_port(p,"IGBT_COMMON",340,580,Color("e2ded0"))
	_small_port(p,"IGBT_1",620,170,Color("cc4145"))
	_small_port(p,"IGBT_2",620,530,Color("202126"))
	for i in range(3):_small_port(p,"IGBT_%d"%(i+3),1080+i*280,350,[Color("cc4145"),Color("202126"),Color("397cc3")][i])
	_small_port(p,"IGBT_EARTH",1360,650,Color("39845b"))
	for y in [.24,.14,.04]:
		var indicator := _sphere(p,Vector3(.79,y,.155),.012,Color("5f342d"))
		var material: StandardMaterial3D = indicator.material_override.duplicate()
		indicator.material_override = material
		igbt_indicators.append(material)
	_control(p,"igbt_damping","Damping switch",Vector2(-.22,-.27),Color("afbab8"),.035)
func _make_transformer() -> void:
	var p := _make_module("",2.11,2.33,2.04,.82,BLACK_PANEL,true)
	_face(p,"transformer",2.04,.82)
	for row in [[230,[[600,1],[1480,2]]],[430,[[180,3],[990,7],[1430,8],[1860,4]]],[620,[[550,5],[1030,9],[1510,6]]]]:
		for port in row[1]:_small_port(p,"TX_%d"%port[1],port[0],row[0],Color("ead143"))
func _make_supply() -> void:
	var p := _make_module("",-2.11,.95,2.04,1.85,BLACK_PANEL,true)
	_face(p,"supply",2.04,1.85)
	_control(p,"power","Power",Vector2(-.84,.575),Color("161b20"),.065)
	_control(p,"variable","Variable output",Vector2(-.55,-.145),Color("bfc5c5"),.235)
	_control(p,"supply_meter","Supply voltmeter selector",Vector2(.61,.555),Color("c5c9c4"),.095)
	supply_display=_text3(p,"OFF",Vector3(-.10,.545,.21),.038,Color("15352e"))
	for i in range(4):
		var col: Color=[Color("cb4245"),Color("202126"),Color("397bc4"),Color("eadf8f")][i]
		_small_port(p,"P_"+["A","B","C","N"][i],1180,940+i*140,col,1.85)
		_small_port(p,"PV_"+["A","B","C","N"][i],1440,940+i*140,col,1.85)
	for i in range(4):_small_port(p,["DC_7","DC_N7","DC_8","DC_N8"][i],1735,[940,1080,1270,1410][i],Color("cc4145") if i%2==0 else Color("202126"),1.85)
	for i in range(6):_control(p,"reset_%d"%i,"Reset",Vector2(.02+i*.125,-.68),Color("b7b9a9"),.032)
	_small_port(p,"EARTH",1850,1605,Color("39845b"),1.85)
	for i in range(2):_small_port(p,"LOW_%d"%i,380+i*180,1600,Color("a6b6ba"),1.85)
func _ring(parent: Node3D,pos: Vector3,inner: float,outer: float,color: Color) -> void:
	var mesh := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius=inner
	torus.outer_radius=outer
	torus.rings=48
	torus.ring_segments=12
	mesh.mesh=torus
	mesh.position=pos
	mesh.rotation.x=PI/2
	mesh.material_override=_mat(color,.8)
	parent.add_child(mesh)
func _machine(p: Node3D,motor: bool) -> void:
	# Recessed machine, shaft and two bearing assemblies behind a clear guard.
	for x in [-.97,.97]:_box(p,Vector3(x,0,.30),Vector3(.07,1.82,.35),Color("9daba9"),.8)
	_box(p,Vector3(0,-.89,.30),Vector3(2.02,.07,.35),Color("a1aaa4"),.8)
	var center := Vector3(-.15,.37,.24)
	var housing := _cylinder(p,center,.52,.18,Color("3f4947"),.8)
	housing.rotation.x=PI/2
	_ring(p,center+Vector3(0,0,.11),.44,.51,Color("c4a438") if motor else Color("78847f"))
	for i in range(4):
		var a := i*PI/2+.3
		_line(p,center+Vector3(cos(a)*.3,sin(a)*.3,.13),center+Vector3(cos(a)*.49,sin(a)*.49,.13),.035,Color("bea847") if motor else Color("8c9691"),.8)
	var rotor_disc := _cylinder(p,center+Vector3(0,0,.18),.265,.09,Color("b9beb5"),.85)
	rotor_disc.rotation.x=PI/2
	_ring(p,center+Vector3(0,0,.23),.23,.26,Color("979e96"))
	var shaft := _cylinder(p,center+Vector3(.05,-.07,.3),.045,.21,Color("d4c9ac"),.9)
	shaft.rotation.x=PI/2
	for y in [.55,.24]:
		_box(p,Vector3(.55,y,.28),Vector3(.28,.22,.14),Color("555e59"),.8)
		_ring(p,Vector3(.55,y,.40),.055,.095,Color("b9c5bf"))
		_ring(p,Vector3(.55,y,.41),.022,.048,Color("697770"))
		_sphere(p,Vector3(.55,y,.42),.022,Color("d4d7c6"))
	for i in range(4):
		var x := -.55+i*.25
		_line(p,Vector3(x,-.60,.25),Vector3(x+.08,-.22,.30),.012,[Color("97584c"),Color("a7a15e"),Color("4f7b9c"),Color("826549")][i])
	var glass := _box(p,Vector3(0,0,.48),Vector3(1.86,1.62,.008),Color(0.65,.83,.85,.08))
	var glass_mat := StandardMaterial3D.new()
	glass_mat.albedo_color=Color(.65,.83,.85,.055)
	glass_mat.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
	glass_mat.roughness=.2
	glass.material_override=glass_mat
	_face(p,"motor_guard" if motor else "dynamo_guard",2.04,1.85,.49)
func _make_dynamometer() -> void:
	var p := _make_module("",0,.95,2.04,1.85,BLACK_PANEL,true)
	_machine(p,false)
	_control(p,"dyn_load","Mechanical load",Vector2(.56,-.545),Color("c4c6b6"),.13)
	control_bodies.dyn_load.position.z=.54
	for i in range(2):
		_small_port(p,"DYN_%d"%i,330,1360+i*150,Color("dfc836"),1.85)
		terminal_bodies["DYN_%d"%i].position.z=.53
	_line(p,Vector3(-.30,-.56,.53),Vector3(.15,-.56,.53),.022,Color("c3c8b9"),.9)
	_control(p,"dyn_measure","Push while measuring",Vector2(.06,-.61),Color("333c35"),.08)
	control_bodies.dyn_measure.position.z=.56
	dynamo_display=_text3(p,"",Vector3(0,-.36,.55),.025,Color("e3eee0"))
func _make_motor() -> void:
	var p := _make_module("",2.11,.95,2.04,1.85,BLACK_PANEL,true)
	_machine(p,true)
	for i in range(3):
		var col: Color=[Color("cc4145"),Color("202126"),Color("397cc3")][i]
		_small_port(p,"M%d"%(i+1),640,1180+i*180,col,1.85)
		_small_port(p,"M%d"%(i+4),1340,1180+i*180,col,1.85)
		terminal_bodies["M%d"%(i+1)].position.z=.53
		terminal_bodies["M%d"%(i+4)].position.z=.53
