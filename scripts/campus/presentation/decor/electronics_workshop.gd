extends Node3D

const Signage = preload("res://scripts/campus/presentation/entrance_signage.gd")
const Light = preload("res://scripts/campus/presentation/fixture_light.gd")
const Plant = preload("res://scripts/campus/presentation/decor/potted_plant.gd")

const FRAME := "35495b"
const PANEL := "4b6273"
const WOOD := "b68e67"
const EDGE := "d7b089"
const DARK := "202e39"
const STEEL := "9aa9ac"
const MAT := "285848"
const MINT := "77c7ac"
const BRASS := "dcb069"

var materials: Dictionary = {}
var static_batches := preload("res://scripts/campus/performance/static_panel_batch.gd").new()

func batch_static_props() -> void:
	static_batches.apply(self)

func build_room() -> void:
	_floor()
	for z in [-3.824, 9.824]:
		_box(self, Vector3(26, 1.18, z), Vector3(19.7, .05, .04), "728da0")
		_box(self, Vector3(26, 3.78, z), Vector3(19.7, .06, .04), FRAME)
	_service_bench()
	build_storage_rack(self,Vector3(35.36, 0, 1.55))
	build_storage_rack(self,Vector3(35.36, 0, 6.4))
	Plant.mount(self, Vector3(17.18, 0, 7.35))
	Plant.mount(self, Vector3(34.83, 0, 8.95))
	Signage.mount(self, "SOLDERING  /  TEST & REPAIR", Vector3(30.1, 2.85, -3.73), 0, Vector2(4.8, .34), 39)

func build_station(at: Vector3, action: String, label: String) -> Node3D:
	var bench := Node3D.new()
	bench.name = action.to_pascal_case()
	bench.position = at
	add_child(bench)
	_box(bench, Vector3(0,.47,0), Vector3(2.58,.94,1.02), FRAME, true)
	_box(bench, Vector3(0,.058,-.51), Vector3(2.53,.1,.08), DARK)
	_box(bench, Vector3(0,.973,0), Vector3(2.82,.112,1.18), WOOD, true)
	_box(bench, Vector3(0,1.025,-.59), Vector3(2.82,.025,.025), EDGE)
	for x in [-1.05, 1.05]:
		_box(bench, Vector3(x,.6,-.527), Vector3(.37,.55,.035), PANEL)
		for y in [.47,.66]:
			_box(bench, Vector3(x,y,-.556), Vector3(.18,.025,.041), STEEL)
	var plaque := Signage.mount(bench, label, Vector3(0,.61,-.555), PI, Vector2(1.67,.31), 25)
	if action=="prototype_bench":
		plaque.pixel_size=.0043
		plaque.outline_size=0
	match action:
		"electronics_store":
			_register(bench, Vector3(-.83,1.03,.16))
			_kit_case(bench, Vector3(.13,1.03,.06), "587f91")
			_kit_case(bench, Vector3(.82,1.03,.16), "647c66")
		"prototype_bench":
			_esd_mat(bench, Vector3(.23,1.035,-.13))
			_instrument(bench, Vector3(-.86,1.03,.24), true)
			_breadboard(bench, Vector3(.23,1.059,-.1))
			_probe(bench, Vector3(.91,1.064,-.34), "ce6962")
		"ic_builder":
			_esd_mat(bench, Vector3(.23,1.035,-.13))
			_chip_socket(bench, Vector3(-.83,1.03,.15))
			_chips(bench, Vector3(.15,1.065,-.12))
			_box(bench, Vector3(.85,1.079,-.26), Vector3(.18,.032,.32), "d0b592")
		"pcb_builder":
			_esd_mat(bench, Vector3(.23,1.035,-.13))
			_board_vise(bench, Vector3(-.83,1.03,.15))
			_pcb(bench, Vector3(.20,1.061,-.10))
			_probe(bench, Vector3(.90,1.063,-.29), BRASS)
		"kit_library", "components_counter":
			for i in 3:
				_parts_bin(bench,Vector3(-.13+i*.32,1.03,-.08),["b59d71","77a08f","ad7772"][i])
			_box(bench, Vector3(-.82,1.06,.14), Vector3(.54,.06,.40), FRAME)
			for i in 3:
				_box(bench, Vector3(-.99+i*.17,1.14,.14), Vector3(.13,.12,.36), ["b59d71","77a08f","ad7772"][i])
	return bench

func _register(parent: Node3D, at: Vector3) -> void:
	_box(parent, at+Vector3(0,.055,0), Vector3(.48,.11,.34), DARK)
	_box(parent, at+Vector3(0,.18,.10), Vector3(.10,.16,.075), FRAME)
	_box(parent, at+Vector3(0,.31,.10), Vector3(.42,.20,.07), FRAME)
	_box(parent, at+Vector3(0,.31,.058), Vector3(.36,.145,.015), "203b47")
	for x in [-.10,0.0,.10]:
		_box(parent, at+Vector3(x,.317,.048), Vector3(.055,.016,.008), MINT)

func _kit_case(parent: Node3D, at: Vector3, tint: String) -> void:
	_box(parent, at+Vector3(0,.078,0), Vector3(.49,.156,.33), DARK)
	_box(parent, at+Vector3(0,.159,0), Vector3(.50,.075,.34), tint)
	for x in [-.15,.15]:
		_box(parent, at+Vector3(x,.133,-.174), Vector3(.05,.065,.022), BRASS)
	for x in [-.073,.073]:
		_box(parent, at+Vector3(x,.116,-.187), Vector3(.024,.035,.034), DARK)
	_box(parent, at+Vector3(0,.099,-.204), Vector3(.17,.024,.028), FRAME)

func _chip_socket(parent: Node3D, at: Vector3) -> void:
	_box(parent, at+Vector3(0,.05,0), Vector3(.51,.10,.38), "386254")
	_box(parent, at+Vector3(0,.12,0), Vector3(.34,.055,.22), DARK)
	for side in [-1,1]:
		for pin in 6:
			_box(parent, at+Vector3((pin-2.5)*.047,.151,side*.086), Vector3(.021,.008,.027), BRASS)
	_rod(parent, at+Vector3(.16,.135,.09), at+Vector3(.22,.24,-.11), .012, STEEL)
	_box(parent, at+Vector3(.22,.24,-.11), Vector3(.055,.038,.045), "cc9258")

func _board_vise(parent: Node3D, at: Vector3) -> void:
	_box(parent, at+Vector3(0,.035,0), Vector3(.49,.07,.32), DARK)
	for x in [-.17,.17]:
		_box(parent, at+Vector3(x,.125,0), Vector3(.10,.145,.21), "527d91")
		_box(parent, at+Vector3(x,.197,0), Vector3(.10,.035,.21), STEEL)
	_rod(parent, at+Vector3(-.22,.12,0), at+Vector3(-.34,.12,0), .023, STEEL)
	_rod(parent, at+Vector3(-.34,.12,-.08), at+Vector3(-.34,.12,.08), .013, STEEL)

func stock_counter(counter: Node3D) -> void:
	_box(counter, Vector3(0,.08,0), Vector3(2.81,.14,.76), DARK)
	_box(counter, Vector3(0,1.046,.455), Vector3(2.98,.029,.026), EDGE)
	_box(counter, Vector3(.31,1.10,-.19), Vector3(2.06,.105,.48), FRAME)
	_box(counter, Vector3(.31,1.34,-.34), Vector3(2.06,.47,.055), FRAME)
	for row in 2:
		for column in 6:
			var bin := Vector3(-.53+column*.336,1.13+row*.21,-.11-row*.12)
			_parts_bin(counter, bin, ["b59d71","77a08f","ad7772","b99a55","7b94ad","9d87a8"][column])
	for x in [-.92,-.46]:
		_box(counter, Vector3(x,1.066,.23), Vector3(.36,.018,.25), "547a75")
	_instrument(counter, Vector3(-1.01,1.06,-.18), false)
	for x in [-1.12,1.12]:
		_box(counter, Vector3(x,.54,.365), Vector3(.39,.57,.042), PANEL)

func _parts_bin(parent: Node3D, at: Vector3, stock: String) -> void:
	_box(parent, at, Vector3(.30,.042,.32), "49627e")
	for x in [-.137,.137]:
		_box(parent, at + Vector3(x,.076,0), Vector3(.027,.14,.32), "49627e")
	_box(parent, at+Vector3(0,.083,-.15), Vector3(.28,.15,.027), "546e89")
	_box(parent, at+Vector3(0,.042,.152), Vector3(.28,.075,.025), FRAME)
	_box(parent, at+Vector3(0,.056,.168), Vector3(.12,.026,.009), "ded1b9")
	for slot in 3:
		_box(parent, at+Vector3((slot-1)*.07,.051,-.012), Vector3(.047,.06,.12), stock)

func _floor() -> void:
	var tile := BoxMesh.new()
	tile.size = Vector3(.987,.01,.987)
	var batch := MultiMesh.new()
	batch.transform_format = MultiMesh.TRANSFORM_3D
	batch.use_colors = true
	batch.mesh = tile
	batch.instance_count = 280
	for x in 20:
		for z in 14:
			var index := x * 14 + z
			batch.set_instance_transform(index, Transform3D(Basis.IDENTITY, Vector3(16.5+x,.011,-3.5+z)))
			batch.set_instance_color(index, Color("a8b3c2") if (x * 7 + z * 13)%9 == 0 else Color("99a8ba"))
	var mesh := MultiMeshInstance3D.new()
	mesh.name = "WorkshopFloor"
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.roughness = .74
	mesh.material_override = material
	mesh.multimesh = batch
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mesh)

func _service_bench() -> void:
	var bench := Node3D.new()
	bench.name = "RepairBench"
	bench.position = Vector3(30.1,0,-3.19)
	add_child(bench)
	for x in [-2.77,0.0,2.77]:
		_box(bench, Vector3(x,.47,0), Vector3(.13,.94,.93), FRAME, true)
	_box(bench, Vector3(0,.97,0), Vector3(5.85,.12,1.05), WOOD, true)
	_box(bench, Vector3(-1.68,.68,0), Vector3(.81,.49,.82), PANEL, true)
	for y in [.55,.72,.86]:
		_box(bench, Vector3(-1.68,y,.431), Vector3(.66,.032,.035), STEEL)
	_box(bench, Vector3(0,1.93,-.64), Vector3(5.55,1.23,.11), FRAME)
	var peg := _box(bench, Vector3(0,1.93,-.574), Vector3(5.42,1.12,.04), "84939a")
	var holes := Image.create_empty(128, 32, false, Image.FORMAT_RGBA8)
	holes.fill(Color("939d9e"))
	for x in range(2,128,4):
		for y in range(2,32,4):
			holes.set_pixel(x,y,Color("465766"))
	var peg_mat := StandardMaterial3D.new()
	peg_mat.albedo_texture = ImageTexture.create_from_image(holes)
	var inset := MeshInstance3D.new()
	var face := QuadMesh.new()
	face.size = Vector2(5.4,1.1)
	inset.mesh = face
	inset.position = peg.position+Vector3(0,0,.022)
	inset.material_override = peg_mat
	bench.add_child(inset)
	for tool in 6:
		var x := -2.32+tool*.25
		var grip: String = ["a77357","b8a45a","60897e"][tool%3]
		_rod(bench, Vector3(x,1.58,-.505), Vector3(x+.045,1.98,-.505), .021, STEEL)
		_rod(bench, Vector3(x+.045,1.98,-.505), Vector3(x+.07,2.13,-.505), .052, grip)
	for i in 3:
		var x := .15+i*.66
		for ring in 2:
			var coil := TorusMesh.new()
			coil.inner_radius = .14+ring*.032
			coil.outer_radius = .19+ring*.032
			coil.rings = 24
			coil.ring_segments = 10
			_mesh(bench, coil, Vector3(x,1.99,-.48+ring*.018), ["ab6350","4e788b","323946"][i]).rotation.x=PI*.5
	_box(bench, Vector3(0,2.59,-.4), Vector3(4.1,.14,.28), DARK)
	_box(bench, Vector3(0,2.508,-.4), Vector3(3.99,.026,.216), "ffe1a7", false, .8)
	for x in [-1.35,1.35]:
		Light.down(bench, Vector3(x,2.482,-.33), .7, 3.1, Vector3(0,-1,.34), 51.0)
	_instrument(bench, Vector3(-2.05,1.03,0), false, 1.47)
	_esd_mat(bench, Vector3(0,1.035,.09))
	_pcb(bench, Vector3(.01,1.061,.09))
	_instrument(bench, Vector3(1.99,1.03,-.04), false, 1.57)

func build_storage_rack(parent: Node3D, at: Vector3, yaw := -PI*.5) -> void:
	var rack := Node3D.new()
	rack.name = "StockShelves"
	rack.position = at
	rack.rotation.y = yaw
	parent.add_child(rack)
	_box(rack, Vector3(0,1.09,-.3), Vector3(2.58,2.18,.13), FRAME, true)
	for x in [-1.23,1.23]:
		_box(rack, Vector3(x,1.11,0), Vector3(.12,2.22,.66), FRAME, true)
	for row in 4:
		var y := .12+row*.56
		_box(rack, Vector3(0,y,0), Vector3(2.56,.078,.66), PANEL, true)
		for column in 3:
			var x := -.79+column*.79
			var body := Vector3(x,y+.219,-.025)
			var color: String = "a9845a" if row >= 2 else ["668897","5c7589","708c89"][column]
			_box(rack, body, Vector3(.66,.35,.48), color, true)
			_box(rack, body+Vector3(0,.18,0), Vector3(.68,.048,.50), color)
			_box(rack, body+Vector3(0,.035,.248), Vector3(.23,.081,.016), "c4ba9e")
			_box(rack, body+Vector3(0,-.043,.249), Vector3(.19,.03,.021), DARK)

func _esd_mat(parent: Node3D, at: Vector3) -> void:
	_box(parent, at, Vector3(1.36,.018,.67), MAT)
	for index in range(-5,6):
		_box(parent, at+Vector3(index*.11,.01,0), Vector3(.004,.002,.60), "4b7c65")
	for index in range(-2,3):
		_box(parent, at+Vector3(0,.011,index*.115), Vector3(1.28,.002,.004), "4b7c65")
	_box(parent, at+Vector3(0,.012,-.314), Vector3(1.28,.002,.012), MINT)

func _instrument(parent: Node3D, at: Vector3, faces_south: bool, unit_scale := 1.0) -> void:
	var unit := Node3D.new()
	unit.position = at
	unit.rotation.y = PI if faces_south else 0.0
	unit.scale = Vector3.ONE*unit_scale
	parent.add_child(unit)
	_box(unit, Vector3(0,.155,0), Vector3(.63,.31,.42), FRAME)
	_box(unit, Vector3(0,.155,.218), Vector3(.602,.273,.028), "9eacad")
	_box(unit, Vector3(-.105,.19,.235), Vector3(.34,.16,.022), "142e30")
	for segment in 11:
		var ax := -.249+segment*.027
		var ay := .189+.038*sin(segment*.58)
		var by := .189+.038*sin((segment+1)*.58)
		_rod(unit, Vector3(ax,ay,.248), Vector3(ax+.027,by,.248), .004, MINT)
	for x in [.126,.23]:
		_rod(unit, Vector3(x,.18,.234), Vector3(x,.18,.267), .047, DARK)
	for i in 4:
		_rod(unit, Vector3(-.20+i*.13,.071,.233), Vector3(-.20+i*.13,.071,.26), .018, "bb554c" if i%2==0 else DARK)

func _breadboard(parent: Node3D, at: Vector3) -> void:
	_box(parent, at, Vector3(.71,.037,.36), "dddac9")
	var holes := Image.create_empty(170, 72, false, Image.FORMAT_RGBA8)
	holes.fill(Color("dddac9"))
	for column in 17:
		for row in [13,20,28,44,52,59]:
			holes.fill_rect(Rect2i(7+column*9,row,3,3), Color("6a7472"))
	var plate := QuadMesh.new()
	plate.size = Vector2(.695,.34)
	var surface := _mesh(parent, plate, at+Vector3(0,.020,0), "dddac9")
	surface.rotation.x = -PI*.5
	var finish := StandardMaterial3D.new()
	finish.albedo_texture = ImageTexture.create_from_image(holes)
	surface.material_override = finish
	for z in [-.154,.154]:
		_box(parent, at+Vector3(0,.021,z), Vector3(.62,.002,.008), "b96264" if z<0 else "4a729e")
	for i in 4:
		var x := -.18+i*.12
		_rod(parent, at+Vector3(x,.022,-.09), at+Vector3(x,.09,-.05), .008, "d68a55")
		_rod(parent, at+Vector3(x,.09,-.05), at+Vector3(x+.058,.085,.034), .008, "d68a55")
		_rod(parent, at+Vector3(x+.058,.085,.034), at+Vector3(x+.058,.022,.071), .008, "d68a55")

func _chips(parent: Node3D, at: Vector3) -> void:
	for i in 3:
		var center := at+Vector3((i-1)*.28,0,0)
		_box(parent, center, Vector3(.21,.057,.20), DARK)
		for pin in 4:
			for side in [-1,1]:
				_box(parent, center+Vector3((pin-1.5)*.045,-.009,side*.111), Vector3(.022,.018,.049), STEEL)
		_box(parent, center+Vector3(-.064,.029,.056), Vector3(.026,.004,.026), "c0c7c1")

func _pcb(parent: Node3D, at: Vector3) -> void:
	_box(parent, at, Vector3(.76,.033,.39), "2f8868")
	for trace in 7:
		var x := -.29+trace*.087
		var z := -.13+(trace%3)*.086
		_box(parent, at+Vector3(x,.0175,z), Vector3(.014,.003,.11), BRASS)
		_box(parent, at+Vector3(x+.034,.018,z+.051), Vector3(.076,.003,.012), BRASS)
	for x in [-.29,.29]:
		_box(parent, at+Vector3(x,.031,.065), Vector3(.09,.05,.12), DARK)
	_box(parent, at+Vector3(0,.035,-.076), Vector3(.19,.045,.11), DARK)

func _probe(parent: Node3D, at: Vector3, tint: String) -> void:
	_rod(parent, at, at+Vector3(.09,0,.28), .026, tint)
	_rod(parent, at+Vector3(.09,0,.28), at+Vector3(.12,0,.36), .008, STEEL)

func _rod(parent: Node3D, a: Vector3, b: Vector3, radius: float, tint: String) -> void:
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = radius
	cylinder.bottom_radius = radius
	cylinder.height = a.distance_to(b)
	cylinder.radial_segments = 12
	var node := _mesh(parent, cylinder, (a+b)*.5, tint)
	node.quaternion = Quaternion(Vector3.UP, (b-a).normalized())

func _box(parent: Node3D, at: Vector3, size: Vector3, tint: String, solid := false, emission := 0.0) -> MeshInstance3D:
	var box := BoxMesh.new()
	box.size = size
	var visual := _mesh(parent, box, at, tint, emission)
	if solid:
		var body := StaticBody3D.new()
		body.collision_mask = 0
		var collision := CollisionShape3D.new()
		var bounds := BoxShape3D.new()
		bounds.size = size
		collision.shape = bounds
		body.add_child(collision)
		visual.add_child(body)
	return visual

func _mesh(parent: Node3D, mesh: Mesh, at: Vector3, tint: String, emission := 0.0) -> MeshInstance3D:
	var key := "%s/%s" % [tint, emission]
	if not materials.has(key):
		var material := StandardMaterial3D.new()
		material.albedo_color = Color(tint)
		material.roughness = .63
		material.emission_enabled = emission > 0.0
		material.emission = Color(tint)
		material.emission_energy_multiplier = emission
		materials[key] = material
	var visual := MeshInstance3D.new()
	visual.mesh = mesh
	visual.position = at
	visual.material_override = materials[key]
	parent.add_child(visual)
	return visual

