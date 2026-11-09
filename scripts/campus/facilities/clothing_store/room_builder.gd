class_name ClothingStoreRoomBuilder
extends Node3D
## Authored geometry uses local primitives so the room is bounded, deterministic and offline-safe.

const ROOM_ID := "clothing_store"
const BOUNDS := AABB(Vector3(-9.0, 0.0, -8.0), Vector3(18.0, 4.2, 16.0))
const DOOR_LOCAL := Vector3(0, 0, 8)
var materials: Dictionary = {}
var garment_meshes: Dictionary = {}
const INTERACTIONS := {
	"catalog": Vector3(-5.7, 0, 2.2),
	"mirror": Vector3(7.55, 0, 0.2),
	"checkout": Vector3(4.9, 0, 4.45),
}

func _ready() -> void:
	_build_shell()
	_build_checkout()
	_build_displays()
	_build_lounge()
	_build_fitting_rooms()
	_build_lighting()

func registry_record(world_origin: Vector3) -> Dictionary:
	return {"id": ROOM_ID, "title": "Harbor Outfitters", "kind": "clothing_store", "origin": _v(world_origin), "bounds_min": _v(world_origin + BOUNDS.position), "bounds_max": _v(world_origin + BOUNDS.end), "door": _v(world_origin + DOOR_LOCAL), "interactions": {"catalog": _v(world_origin + INTERACTIONS.catalog), "mirror": _v(world_origin + INTERACTIONS.mirror), "checkout": _v(world_origin + INTERACTIONS.checkout)}}

func _build_shell() -> void:
	_box("Floor", Vector3(18, .16, 16), Vector3(0, -.08, 0), Color("d8c7ad"), .72)
	_box("BackWall", Vector3(18, 4.2, .18), Vector3(0, 2.1, -8), Color("27434a"), .48)
	_box("LeftWall", Vector3(.18, 4.2, 16), Vector3(-9, 2.1, 0), Color("eee7dc"), .8)
	_box("RightWall", Vector3(.18, 4.2, 16), Vector3(9, 2.1, 0), Color("eee7dc"), .8)
	_box("EntryHeader", Vector3(18, .65, .18), Vector3(0, 3.87, 8), Color("27434a"), .42)
	_box("EntryLeft", Vector3(6.8, 3.55, .18), Vector3(-5.6, 1.78, 8), Color("eee7dc"), .8)
	_box("EntryRight", Vector3(6.8, 3.55, .18), Vector3(5.6, 1.78, 8), Color("eee7dc"), .8)
	_box("Runner", Vector3(2.7, .025, 6.6), Vector3(0, .02, 4.1), Color("a8494f"), .9)
	_box("TileFloor",Vector3(17.75,.012,15.75),Vector3(0,.006,0),Color("b8b7ac"))
	for x in range(-8,9,2):
		_box("TileJoint",Vector3(.012,.004,15.75),Vector3(x,.013,0),Color("8e9290"))
	for z in range(-7,8,2):
		_box("TileJoint",Vector3(17.75,.004,.012),Vector3(0,.013,z),Color("8e9290"))
	_box("FeatureWall",Vector3(5.9,3.5,.06),Vector3(5.78,1.78,7.86),Color("27434a"))
	# Framed full-length mirror; reflective surface is intentionally unique per instance.
	_box("MirrorFrame", Vector3(.12, 3.25, 2.2), Vector3(8.82, 1.75, .2), Color("d4a94f"), .28)
	_box("Mirror", Vector3(.13, 2.9, 1.84), Vector3(8.74, 1.72, .2), Color("93b4bd"), .12, .72)

func _build_checkout() -> void:
	_box("Checkout", Vector3(4.8, 1.05, 1.25), Vector3(5.3, .525, 5.9), Color("6f4934"), .58)
	_box("CounterTop", Vector3(5.05, .12, 1.48), Vector3(5.3, 1.09, 5.9), Color("e6d8c0"), .4)
	_box("Register", Vector3(.72, .48, .62), Vector3(5.8, 1.39, 5.8), Color("26333a"), .34)
	_box("BagStand", Vector3(.55, .65, .32), Vector3(4.45, 1.42, 5.84), Color("b65b51"), .62)
	_shop_target(Vector3(5.3, 1.12, 5.12), Vector3(4.85, 1.55, .15), "", "Shop Harbor Outfitters")
	_box("BrandPanel", Vector3(5.05, .82, .09), Vector3(5.78, 2.85, 7.79), Color("27434a"))
	var brand := Label3D.new()
	brand.text = "M207  ·  HARBOR OUTFITTERS"
	brand.font_size = 72
	brand.pixel_size = .0034
	brand.modulate = Color("f5dfb5")
	brand.position = Vector3(5.78, 2.85, 7.72)
	brand.rotation.y = PI
	add_child(brand)
	_box("Lighthouse",Vector3(.13,.4,.035),Vector3(5.78,3.47,7.71),Color("f5dfb5"))
	_box("LanternRoom",Vector3(.24,.10,.04),Vector3(5.78,3.7,7.71),Color("f5dfb5"))
	for x in [4.05,6.64,7.04]:
		_box("FoldedCounterStock",Vector3(.29,.1,.31),Vector3(x,1.20,5.68),Color("667985"))

func _build_displays() -> void:
	for side: float in [-1.0, 1.0]:
		var x: float = side * 5.8
		for z in [-4.7, -1.8, 1.1]:
			_box("RackPost", Vector3(.12, 2.05, .12), Vector3(x - 1.25, 1.05, z), Color("b88b4a"), .25)
			_box("RackPost", Vector3(.12, 2.05, .12), Vector3(x + 1.25, 1.05, z), Color("b88b4a"), .25)
			_box("RackBar", Vector3(2.40, .1, .1), Vector3(x, 1.9, z), Color("c7b38c"), .2, .35)
			_box("RackBase", Vector3(2.9, .12, .62), Vector3(x, .12, z), Color("5b3e31"), .55)
			var category := ("tops" if z < -3 else "hoodies" if z < 0 else "jackets") if side < 0 else ("bottoms" if z < -3 else "shoes" if z < 0 else "head")
			for hanger in [-.9, -.45, 0.0, .45, .9]:
				var palette := [Color("4f7880"), Color("a75559"), Color("c7a062"), Color("5d5269"), Color("e4d7c3")]
				var tint: Color = palette[roundi((hanger + .9) / .45)]
				if category=="shoes":
					_box("ShoeShelf",Vector3(.44,.055,.48),Vector3(x+hanger,1.07,z),Color("aa8263"))
					for dx in [-.095,.095]:
						_box("ShoeSole",Vector3(.15,.045,.31),Vector3(x+hanger+dx,1.12,z),Color("e3d9cb"))
						_box("ShoeUpper",Vector3(.14,.12,.27),Vector3(x+hanger+dx,1.18,z-.02),tint)
				elif category=="head":
					_box("HatShelf",Vector3(.44,.055,.48),Vector3(x+hanger,1.07,z),Color("aa8263"))
					_cylinder("CapCrown",.136,.15,Vector3(x+hanger,1.17,z),tint)
					_box("CapVisor",Vector3(.19,.026,.15),Vector3(x+hanger,1.11,z+.13),tint)
				else:
					_cylinder("HangerHook",.018,.17,Vector3(x+hanger,1.82,z),Color("c7b38c"))
					_garment(Vector3(x + hanger, 1.32, z),tint,category,-side*1.33)
			var product := "headwear" if category=="head" else category
			_shop_target(Vector3(x, 1.25, z), Vector3(2.66, 1.54, .62), category, product.capitalize())
	_box("FeaturedTable",Vector3(2.54,.14,1.44),Vector3(0,.83,-1.55),Color("ad8057"))
	for x in [-1.06,1.06]:
		for z in [-2.07,-1.03]:
			_box("DisplayLeg",Vector3(.11,.78,.11),Vector3(x,.39,z),Color("604839"))
	for x in [-.79,0.0,.79]:
		for stack in range(3):
			_box("FoldedSweater",Vector3(.57,.064,.44),Vector3(x,.934+stack*.06,-1.68),[Color("a75559"),Color("e4d7c3"),Color("4f7880")][stack])
	_shop_target(Vector3(0,.98,-1.55),Vector3(2.58,.46,1.49),"accessories","Accessories table")
	# Two mannequin plinths create a focal display without loading/networking avatar meshes.
	for x in [-2.3, 2.3]:
		var skin := Color("ece4d7")
		_cylinder("Plinth", .70, .19, Vector3(x, .095, -5.6), Color("d4a94f"))
		_sphere("MannequinHead", Vector3(.18,.24,.17), Vector3(x, 1.96, -5.6), skin)
		_cylinder("MannequinNeck", .09, .15, Vector3(x, 1.73, -5.6), skin)
		_garment(Vector3(x, 1.34, -5.6), Color("2f6571") if x < 0 else Color("884b68"),"hoodies" if x<0 else "jackets",0.0,.16)
		for side in [-1.0,1.0]:
			_sphere("MannequinForearm",Vector3(.07,.23,.073),Vector3(x+side*.39,1.20,-5.6),skin).rotation.z=side*.18
			_sphere("MannequinLeg",Vector3(.13,.43,.14),Vector3(x+side*.125,.65,-5.6),Color("414554"))
			_sphere("MannequinShoe",Vector3(.108,.07,.18),Vector3(x+side*.125,.25,-5.54),Color("292d37"))

func _build_lounge() -> void:
	_box("BenchSeat", Vector3(3.4, .35, 1.2), Vector3(-3.2, .62, 5.8), Color("315c63"), .8)
	_box("BenchBack", Vector3(3.4, 1.05, .28), Vector3(-3.2, 1.17, 6.3), Color("315c63"), .8)
	for x in [-4.6, -1.8]: _box("BenchLeg", Vector3(.18, .55, .8), Vector3(x, .28, 5.8), Color("b88b4a"), .32)
	for z in [-6.8, -3.8, -.8, 2.2]:
		_box("Shelf", Vector3(3.2, .12, .72), Vector3(-7.2, 2.65, z), Color("8d6040"), .55)
		for x in [-8.05, -7.45, -6.85, -6.25]: _box("FoldedStock", Vector3(.48, .22, .55), Vector3(x, 2.82, z), Color("d2a64b") if int(z) % 2 == 0 else Color("a75559"), .82)

func _build_fitting_rooms() -> void:
	for x in [5.0, 6.7, 8.4]:
		_box("FittingPartition", Vector3(.11, 2.65, 1.75), Vector3(x, 1.33, -6.97), Color("a87955"))
	for x in [5.85, 7.55]:
		_box("CurtainRail", Vector3(1.65, .07, .09), Vector3(x, 2.58, -6.09), Color("c7b38c"), .23, .35)
		for fold in range(5):
			_box("CurtainFold", Vector3(.13, 2.34, .08), Vector3(x + .22 + fold * .11, 1.36, -6.08 + (fold % 2) * .035), Color("a75559"))
		_box("FittingMirror", Vector3(.83, 1.92, .08), Vector3(x, 1.45, -7.81), Color("93b4bd"), .12, .72)
		_cylinder("FittingStool",.22,.46,Vector3(x+.42,.23,-7.37),Color("ad8057"))
		_box("ClothingHook",Vector3(.09,.14,.13),Vector3(x-.43,1.94,-7.76),Color("c7b38c"))

func _shop_target(at: Vector3, size: Vector3, category: String, label: String) -> void:
	var target := StaticBody3D.new()
	target.position = at
	target.collision_layer = 4
	target.collision_mask = 0
	target.set_meta("role", "clothing_shop")
	target.set_meta("shop_category", category)
	target.set_meta("label", label)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	target.add_child(shape)
	add_child(target)

func _build_lighting() -> void:
	for x in [-5.5, 0.0, 5.5]:
		_box("Track", Vector3(.1, .09, 12.2), Vector3(x, 3.92, .2), Color("302c29"), .42)
		for z in [-4.5, 1.0, 5.2]:
			_cylinder("TrackHead", .19, .23, Vector3(x, 3.75, z), Color("453a32"))
			var light := OmniLight3D.new(); light.name = "WarmTrackLight"; light.position = Vector3(x, 3.65, z); light.omni_range = 5.2; light.light_energy = .62; light.light_color = Color("ffe0ad"); add_child(light)

func _material(color: Color, roughness: float, metallic := 0.0) -> StandardMaterial3D:
	var key := [color,roughness,metallic]
	if materials.has(key):return materials[key]
	var material := StandardMaterial3D.new(); material.albedo_color = color; material.roughness = roughness; material.metallic = metallic
	materials[key]=material
	return material

func _box(label: String, size: Vector3, at: Vector3, color: Color, roughness := .7, metallic := 0.0) -> MeshInstance3D:
	var node := MeshInstance3D.new(); node.name = label; var mesh := BoxMesh.new(); mesh.size = size; mesh.material = _material(color, roughness, metallic); node.mesh = mesh; node.position = at; add_child(node)
	if label in ["Checkout", "RackBase", "RackPost", "BenchSeat", "BenchBack", "FittingPartition", "FeaturedTable", "DisplayLeg"]:
		var body := StaticBody3D.new(); body.name = label + "Collision"; body.position = at
		var shape := CollisionShape3D.new(); var box := BoxShape3D.new(); box.size = size; shape.shape = box; body.add_child(shape); add_child(body)
	return node

func _cylinder(label: String, radius: float, height: float, at: Vector3, color: Color) -> void:
	var node := MeshInstance3D.new(); node.name = label; var mesh := CylinderMesh.new(); mesh.top_radius = radius; mesh.bottom_radius = radius; mesh.height = height; mesh.material = _material(color, .55); node.mesh = mesh; node.position = at; add_child(node)
	if label in ["Plinth","FittingStool"]:
		var body := StaticBody3D.new(); body.name = label+"Collision"; body.position = at
		var shape := CollisionShape3D.new(); var cylinder := CylinderShape3D.new(); cylinder.radius = radius; cylinder.height = height; shape.shape = cylinder; body.add_child(shape); add_child(body)

func _sphere(label: String, radii: Vector3, at: Vector3, color: Color) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = label
	var mesh := SphereMesh.new()
	mesh.material = _material(color, .75)
	node.mesh = mesh
	node.scale = radii * 2.0
	node.position = at
	add_child(node)
	return node

static func _v(value: Vector3) -> Array: return [value.x, value.y, value.z]

func _garment(at: Vector3, color: Color, style: String, yaw := 0.0, depth := .045) -> void:
	var node := MeshInstance3D.new()
	node.name = "TailoredGarment"
	var key := "%s:%.3f" % [style,depth]
	if not garment_meshes.has(key):garment_meshes[key]=_garment_mesh(style,depth)
	node.mesh = garment_meshes[key]
	node.material_override = _material(color,.78)
	node.position = at
	node.rotation.y = yaw
	add_child(node)
	if style=="hoodies":
		var hood := _sphere("Hood",Vector3(.15,.10,.12),at+Vector3(0,.38,-depth*.7).rotated(Vector3.UP,yaw),color)
		hood.rotation.y = yaw
		var pocket := _box("PouchPocket",Vector3(.32,.17,.03),at+Vector3(0,-.23,depth+.015).rotated(Vector3.UP,yaw),color.darkened(.12))
		pocket.rotation.y = yaw
	elif style=="jackets":
		var zipper := _box("JacketZipper",Vector3(.019,.71,.018),at+Vector3(0,-.08,depth+.01).rotated(Vector3.UP,yaw),Color("bdb4a5"))
		zipper.rotation.y = yaw

func _garment_mesh(style: String, depth: float) -> ArrayMesh:
	var outline := PackedVector2Array([Vector2(-.15,.45), Vector2(-.35,.35), Vector2(-.48,.08), Vector2(-.31,0), Vector2(-.22,.18), Vector2(-.25,-.48), Vector2(.25,-.48), Vector2(.22,.18), Vector2(.31,0), Vector2(.48,.08), Vector2(.35,.35), Vector2(.15,.45), Vector2(.09,.31), Vector2(-.09,.31)])
	if style=="bottoms":
		outline=PackedVector2Array([Vector2(-.25,.41),Vector2(-.23,-.48),Vector2(-.055,-.48),Vector2(0,-.02),Vector2(.055,-.48),Vector2(.23,-.48),Vector2(.25,.41)])
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var triangles := Geometry2D.triangulate_polygon(outline)
	for side in [-1.0, 1.0]:
		var normal := Vector3(0,0,side)
		for i in range(0, triangles.size(), 3):
			var a := outline[triangles[i]]
			var b := outline[triangles[i+1]]
			var c := outline[triangles[i+2]]
			_garment_face(surface,Vector3(a.x,a.y,side*depth),Vector3(b.x,b.y,side*depth),Vector3(c.x,c.y,side*depth),normal)
	var clockwise := Geometry2D.is_polygon_clockwise(outline)
	for i in outline.size():
		var a := outline[i]
		var b := outline[(i+1)%outline.size()]
		var edge := (b-a).normalized()
		var normal := Vector3(edge.y,-edge.x,0)*(-1.0 if clockwise else 1.0)
		var front_a := Vector3(a.x,a.y,depth)
		var front_b := Vector3(b.x,b.y,depth)
		var back_a := Vector3(a.x,a.y,-depth)
		var back_b := Vector3(b.x,b.y,-depth)
		_garment_face(surface,front_a,front_b,back_b,normal)
		_garment_face(surface,front_a,back_b,back_a,normal)
	return surface.commit()

func _garment_face(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, normal: Vector3) -> void:
	var vertices := [a,b,c] if (b-a).cross(c-a).dot(normal)<0 else [a,c,b]
	for point in vertices:
		surface.set_normal(normal)
		surface.add_vertex(point)
