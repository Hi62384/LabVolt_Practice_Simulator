extends Node3D
## M104-only finish candidate. Mount at registry center (26,0,19).
## Geometry is visual only; existing shell and seat authority remain untouched.
var mats := {}
func mat(hex: String) -> StandardMaterial3D:
	if mats.has(hex): return mats[hex]
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(hex)
	m.roughness = .86
	mats[hex] = m
	return m
func panel(at: Vector3, size: Vector3, hex: String) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	var item := MeshInstance3D.new()
	item.mesh = mesh
	item.position = at
	item.material_override = mat(hex)
	item.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(item)
func tiles(points: Array, size: Vector3, hex: String) -> void:
	var mesh := BoxMesh.new(); mesh.size = size
	var mm := MultiMesh.new(); mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh; mm.instance_count = points.size()
	for i in points.size(): mm.set_instance_transform(i, Transform3D(Basis.IDENTITY, points[i]))
	var item := MultiMeshInstance3D.new(); item.multimesh = mm
	item.material_override = mat(hex)
	item.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(item)
func label(text: String, at: Vector3, yaw: float, color: String, scale: float=.003) -> void:
	var sign := Label3D.new()
	sign.text = text
	sign.position = at
	sign.rotation.y = yaw
	sign.font_size = 40
	sign.pixel_size = scale
	sign.modulate = Color(color)
	sign.no_depth_test = false
	sign.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	add_child(sign)
func build() -> void:
	# Shell walls are at local +/-10 X and +/-6 Z. West door is x=-10,z=0.
	# Flooring remains visual and 8mm above the original collision plane.
	var floor_a: Array = []; var floor_b: Array = []
	for x in range(20):
		for z in range(12):
			(floor_a if (x+z)%4==0 else floor_b).append(Vector3(-9.5+x,.008,-5.5+z))
	tiles(floor_a,Vector3(.984,.012,.984),"67787b")
	tiles(floor_b,Vector3(.984,.012,.984),"718185")
	# Blue-gray wainscot, cream upper wall, and a continuous baseboard.
	for z in [-5.88,5.88]:
		panel(Vector3(0,1.0,z),Vector3(19.82,1.9,.035),"536d76")
		panel(Vector3(0,2.95,z),Vector3(19.82,1.99,.035),"d9ded6")
		panel(Vector3(0,.11,z-.03 if z>0 else z+.03),Vector3(19.82,.20,.07),"344f59")
	panel(Vector3(9.88,1,0),Vector3(.035,1.9,11.8),"536d76")
	panel(Vector3(9.88,2.95,0),Vector3(.035,1.99,11.8),"d9ded6")
	for z in [-3.65,3.65]:
		panel(Vector3(-9.88,1,z),Vector3(.035,1.9,4.55),"536d76")
		panel(Vector3(-9.88,2.95,z),Vector3(.035,1.99,4.55),"d9ded6")
		panel(Vector3(-9.83,.11,z),Vector3(.07,.20,4.55),"344f59")
	# Suspended grid below original 4.15m shell ceiling; no collision or lights.
	var ceiling_a: Array = []; var ceiling_b: Array = []
	for x in range(10):
		for z in range(6):
			(ceiling_b if (x+z)%3==0 else ceiling_a).append(Vector3(-9+x*2,3.96,-5+z*2))
	tiles(ceiling_a,Vector3(1.975,.025,1.975),"e3e7df")
	tiles(ceiling_b,Vector3(1.975,.025,1.975),"d7dedb")
	for x in range(11):panel(Vector3(-10+x*2,3.93,0),Vector3(.025,.035,12),"71858a")
	for z in range(7):panel(Vector3(0,3.93,-6+z*2),Vector3(20,.035,.025),"71858a")
	# Diffusers are emissive-looking surfaces only; lighting owner decides actual lights.
	var diffusers: Array = []
	for x in [-5,0,5]:
		for z in [-3,3]:diffusers.append(Vector3(x,3.925,z))
	tiles(diffusers,Vector3(1.08,.018,1.08),"eee9d6")
	# Physical sign backplates flush against the north wall and west doorway lintel.
	panel(Vector3(0,2.7,-5.79),Vector3(3.8,.48,.06),"344f59")
	label("FOOD SERVICE",Vector3(0,2.7,-5.747),0,"f0e9d9",.004)
	panel(Vector3(-9.79,3.28,0),Vector3(.06,.36,2.15),"344f59")
	label("M104  CAFETERIA",Vector3(-9.735,3.28,0),PI/2,"f0e9d9",.003)
	# Restrained information board and two food posters, flush on north wall.
	for x,text in [[-6,"TODAY'S MENU"],[-3,"EAT WELL"]]:
		panel(Vector3(x,1.96,-5.77),Vector3(1.5,1.15,.045),"344f59")
		label(text,Vector3(x,2.25,-5.735),0,"eee9d6",.0024)
