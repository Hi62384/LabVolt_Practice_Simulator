extends Node3D
## M108-only presentation. The facility room retains all authoritative stations and collisions.
const ROOM_ID := "subway"
var mats := {}
var cubes := {}

func _mat(hex: String, transparent: bool = false) -> StandardMaterial3D:
	var key := hex + ("_glass" if transparent else "")
	if mats.has(key): return mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(hex)
	m.roughness = .78
	if hex == "f8f6df" or hex == "f7e9ab":
		m.emission_enabled = true
		m.emission = m.albedo_color
		m.emission_energy_multiplier = 2.0
	if transparent:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.albedo_color.a = .13
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		m.roughness = .18
	mats[key] = m
	return m

func _box(at: Vector3, size: Vector3, color: String, name_: String = "", glass: bool = false) -> void:
	var key := str(size)
	if not cubes.has(key):
		var mesh := BoxMesh.new()
		mesh.size = size
		cubes[key] = mesh
	var n := MeshInstance3D.new()
	n.name = name_ if name_ != "" else "Finish"
	n.mesh = cubes[key]
	n.material_override = _mat(color, glass)
	n.position = at
	n.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	n.visibility_range_end = 35
	add_child(n)

func _sign(at: Vector3, value: String, size: float = .004, color: String = "ffffff") -> void:
	var n := Label3D.new()
	n.text = value
	n.font_size = 40
	n.pixel_size = size
	n.outline_size = 5
	n.modulate = Color(color)
	n.position = at
	n.no_depth_test = false
	n.visibility_range_end = 24
	add_child(n)

func build(_menu: Dictionary) -> void:
	# All coordinates are room local. Keep the west door at x=-10 and the
	# four service seats at the existing facility positions.
	var floor_mesh := PlaneMesh.new()
	floor_mesh.size = Vector2(20,12)
	var finish := ShaderMaterial.new()
	finish.shader = preload("res://scripts/campus/presentation/decor/social_rooms/ceramic_floor.gdshader")
	var floor_surface := MeshInstance3D.new()
	floor_surface.name = "CeramicTileFloor"
	floor_surface.mesh = floor_mesh
	floor_surface.material_override = finish
	floor_surface.position.y = .018
	floor_surface.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(floor_surface)
	# Rear wall and ceiling are inset to avoid touching the campus shell or door.
	_box(Vector3(0,3.86,0),Vector3(19.5,.065,11.6),"d9dcd5","Suspended ceiling")
	for x in range(-8,9,2):
		_box(Vector3(float(x),3.817,0),Vector3(.015,.008,11.45),"abb5b5","Ceiling grid")
	for z in range(-5,6,2):
		_box(Vector3(0,3.817,float(z)),Vector3(19.35,.008,.015),"abb5b5","Ceiling grid")
	for x in [-6.0,0.0,6.0]:
		for z in [-3.3,2.6]:
			_box(Vector3(x,3.78,z),Vector3(1.55,.045,.42),"f8f6df","Rectangular ceiling light")
			var fixture := preload("res://scripts/campus/presentation/fixture_light.gd").down(self,Vector3(x,3.73,z),1.12,6.5)
			fixture.distance_fade_enabled=true
	# Existing service counter collision is 6 x .8 at z=-2.5. The
	# visual shell is directly supported by that exact footprint.
	_box(Vector3(0,.56,-2.5),Vector3(6.03,1.1,.82),"167849","Long green counter")
	for x in [-2.72,-2.2,-1.68,-1.16,-.64,-.12,.4,.92,1.44,1.96,2.48]:
		_box(Vector3(x,.54,-2.07),Vector3(.025,.83,.025),"2d9560","Counter front detail")
	_box(Vector3(0,1.135,-2.5),Vector3(6.22,.105,1.02),"dfcba7","Continuous countertop")
	_box(Vector3(-1.45,1.19,-2.5),Vector3(2.95,.055,.74),"a4a9a3","Preparation well")
	# Narrow posts support the glass; the rear remains open for staff.
	for x in [-2.9,.02]:
		for z in [-2.78,-2.16]:
			_box(Vector3(x,1.36,z),Vector3(.024,.34,.024),"6d8980","Glass support")
	_box(Vector3(-1.45,1.54,-2.45),Vector3(2.94,.018,.65),"d7f4e9","Sneeze guard top",true)
	_box(Vector3(-1.45,1.37,-2.119),Vector3(2.94,.334,.012),"d7f4e9","Sneeze guard front",true)
	# Bread rests on the counter, register and pickup remain to the east.
	_box(Vector3(.45,1.19,-2.52),Vector3(.82,.045,.62),"47534c","Bread tray")
	for i in 3:
		_box(Vector3(.22+i*.21,1.25,-2.52),Vector3(.17,.09,.41),"d5a46b","Bread loaf")
	_box(Vector3(1.42,1.25,-2.79),Vector3(.65,.13,.38),"26383a","Register base")
	_box(Vector3(1.42,1.57,-2.88),Vector3(.58,.47,.07),"243f46","Register screen")
	_box(Vector3(1.84,1.19,-2.35),Vector3(.36,.019,.38),"ece7d7","Pickup mat")
	for x in [1.75,1.90,2.04]:
		_box(Vector3(x,1.3,-2.56),Vector3(.07,.22,.07),"e9c749","Condiment bottle")
	# Shelves and stock sit against the rear wall; staff aisle remains open.
	for y in [.42,1.36,2.12]:
		_box(Vector3(0,y,-5.48),Vector3(5.8,.09,.48),"b9a27c","Rear storage shelf")
	for x in [-2.55,-1.6,1.6,2.55]:
		_box(Vector3(x,.86,-5.47),Vector3(.46,.77,.31),"b8a26f","Bread and stock")
	_box(Vector3(0,3.64,-4.40),Vector3(6.74,.22,2.66),"194e35","Counter canopy")
	_box(Vector3(0,3.512,-4.40),Vector3(6.60,.045,2.56),"c2aa7c","Canopy underside")
	for x in [-2.45,-.8,.8,2.45]:
		_box(Vector3(x,3.48,-3.44),Vector3(.23,.024,.23),"f8f6df","Canopy lamp")
	_box(Vector3(-5.7,2.8,-5.68),Vector3(3.6,.84,.12),"167849","Wall logo backing")
	_sign(Vector3(-5.7,2.8,-5.60),"SUBWAY",.012,"fff4b3")
	_box(Vector3(5.45,2.72,-5.68),Vector3(2.5,1.15,.12),"e8debd","Sandwich poster backing")
	_box(Vector3(-1.95,1.7,-2.045),Vector3(.9,.24,.02),"f3ce42","Order sign backing")
	_sign(Vector3(-1.95,1.7,-2.027),"ORDER",.0035,"184b37")
	_box(Vector3(2.38,1.7,-2.045),Vector3(.9,.24,.02),"f3ce42","Pickup sign backing")
	_sign(Vector3(2.38,1.7,-2.027),"PICKUP",.0035,"184b37")
	# Green pendants mounted from the ceiling above the counter.
	for x in [-2.2,0.0,2.2]:
		_box(Vector3(x,3.48,-2.5),Vector3(.025,.7,.025),"424b43","Pendant cable")
		_box(Vector3(x,3.13,-2.5),Vector3(.48,.23,.48),"167849","Green pendant shade")
		_box(Vector3(x,2.995,-2.5),Vector3(.32,.025,.32),"f7e9ab","Pendant diffuser")
	# Match the four existing seat centers; varied table settings are cosmetic.
	for i in 4:
		var at := Vector3(-4.5+(i%2)*4.2,0,1+(i/2)*2.7)
		_box(at+Vector3(0,.76,0),Vector3(1.53,.11,1.04),"dfd6bc","Light table top")
		_box(at+Vector3(0,.37,0),Vector3(.12,.72,.12),"475354","Table pedestal")
		_box(at+Vector3(0,.09,0),Vector3(.55,.05,.55),"475354","Table foot")
		_box(at+Vector3(0,.44,.95),Vector3(.66,.14,.65),"188452","Green chair seat")
		_box(at+Vector3(0,.86,1.23),Vector3(.68,.79,.1),"188452","Green chair back")
		for dx in [-.25,.25]:
			for dz in [.7,1.2]:
				_box(at+Vector3(dx,.23,dz),Vector3(.045,.44,.045),"4c5752","Chair leg")
		if i % 2 == 0:
			_box(at+Vector3(.24,.845,-.12),Vector3(.38,.025,.24),"424b44","Table tray")
			_box(at+Vector3(.24,.885,-.12),Vector3(.28,.06,.13),"c99d62","Sandwich on tray")
			_box(at+Vector3(-.28,.84,.14),Vector3(.12,.13,.12),"e7eee8","Drink cup")
		else:
			_box(at+Vector3(-.25,.83,-.12),Vector3(.21,.01,.18),"f1eee1","Napkins")
	# Modest bins and planter stay off the west entrance and order lane.
	for bin in [[6.7,"485b55"],[7.35,"318466"]]:
		var x: float = bin[0]
		var color: String = bin[1]
		_box(Vector3(x,.43,-5.47),Vector3(.45,.85,.43),color,"Waste or recycling")
		_box(Vector3(x,.87,-5.47),Vector3(.5,.045,.48),"303d38","Bin rim")
	_box(Vector3(7.45,1.25,-5.65),Vector3(1.65,.09,.35),"b9a27c","Mounted tray return shelf")
	_box(Vector3(7.45,1.34,-5.65),Vector3(.9,.06,.28),"687b72","Returned trays")
	_sign(Vector3(7.45,1.66,-5.58),"TRAY RETURN",.0034,"285e48")
	_box(Vector3(8.2,.38,4.7),Vector3(.62,.72,.62),"b9baaa","Planter")
	_box(Vector3(8.2,.93,4.7),Vector3(.37,.47,.38),"438159","Plant foliage")

