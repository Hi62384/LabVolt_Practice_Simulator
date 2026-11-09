class_name CircuitStudioRoom
extends Node3D

const Contract=preload("res://scripts/campus/facilities/circuit_studio/studio_contract.gd")
const Adapter=preload("res://scripts/campus/facilities/circuit_studio/interaction_adapter.gd")
var adapter: CircuitStudioInteractionAdapter
var materials: Dictionary={}
var station_anchors: Dictionary={}
var mounted:=false

func build(owner_game: Node) -> bool:
	if mounted:return true
	var room:=Contract.room_record()
	if not Contract.valid_room_record(room):return false
	adapter=Adapter.new();adapter.name="InteractionAdapter";add_child(adapter)
	if not adapter.configure(owner_game):return false
	name="CircuitStudioContent"
	set_meta("room_id",Contract.ROOM_ID)
	position=Vector3(0,5,0) # M208 is an upper-floor room; props remain simple room-local coordinates.
	_workbench(Vector3(25.8,.0,47.0))
	_pcb_drafting_desk(Vector3(22.8,0,43.0))
	_prototype_island(Vector3(29.8,.0,47.0))
	_firmware_desk(Vector3(26.0,.0,51.2))
	_storage_wall(Vector3(34.2,.0,47.8))
	_decor(Vector3(26,0,47))
	mounted=adapter.route_complete()
	return mounted

func interact(target: Node) -> bool:
	return is_instance_valid(adapter) and adapter.interact(target)

func is_ready() -> bool:return mounted and is_instance_valid(adapter) and adapter.route_complete()

func _workbench(origin: Vector3) -> void:
	# L-shaped electronics drafting desk: timber top, steel frame, cutting mat,
	# articulated display and component trays. The physical prop is the target.
	_box(origin+Vector3(0,.82,0),Vector3(4.8,.12,1.25),"wood")
	_box(origin+Vector3(-2.05,.4,0),Vector3(.14,.8,1.05),"steel")
	_box(origin+Vector3(2.05,.4,0),Vector3(.14,.8,1.05),"steel")
	_box(origin+Vector3(-1.05,.9,0),Vector3(1.45,.035,.72),"matte_green",false)
	_box(origin+Vector3(.9,1.47,.34),Vector3(1.25,.74,.08),"screen",false)
	_box(origin+Vector3(.9,1.1,.34),Vector3(.08,.55,.08),"steel",false)
	# PCB/circuit detail makes the usable surface identifiable without a text-box proxy.
	for x in [-1.55,-1.3,-1.05,-.8,-.55]:
		_box(origin+Vector3(x,.94,-.06),Vector3(.12,.035,.3),"copper",false)
	for x in [-.15,.15,.45]:_box(origin+Vector3(x,.92,-.25),Vector3(.22,.12,.12),"component",false)
	# IC package in a pin programming cradle, beside its configuration display.
	_box(origin+Vector3(-1.05,1.02,0),Vector3(.58,.18,.34),"component",false)
	for x in [-1.28,-1.13,-.98,-.83]:
		for z in [-.23,.23]:_box(origin+Vector3(x,.96,z),Vector3(.045,.04,.16),"copper",false)
	_station(origin+Vector3(.9,1.47,.28),Vector3(1.3,.8,.16),"ic_builder")

func _pcb_drafting_desk(origin: Vector3) -> void:
	_box(origin+Vector3(0,.82,0),Vector3(3.5,.12,1.5),"wood")
	for x in [-1.45,1.45]:_box(origin+Vector3(x,.4,0),Vector3(.15,.8,1.2),"steel")
	var board:=Vector3(0,.94,-.12)
	_box(origin+board,Vector3(1.65,.08,.95),"matte_green",false)
	for z in [-.28,0.,.28]:_box(origin+board+Vector3(0,.05,z),Vector3(1.35,.018,.025),"copper",false)
	for x in [-.62,.62]:
		_box(origin+board+Vector3(x,.1,0),Vector3(.12,.08,.65),"component",false)
		for z in [-.25,0.,.25]:_cylinder(origin+board+Vector3(x,.16,z),.028,.025,"copper")
	# Raised drafting screen and inspection magnifier establish board-design identity.
	_box(origin+Vector3(1.1,1.45,.48),Vector3(1.05,.7,.08),"screen",false)
	_cylinder(origin+Vector3(-1.15,1.3,.2),.045,.75,"steel")
	_cylinder(origin+Vector3(-1.15,1.7,.2),.28,.05,"instrument")
	_station(origin+board+Vector3(0,.12,0),Vector3(1.8,.3,1.05),"pcb_builder")

func _prototype_island(origin: Vector3) -> void:
	_box(origin+Vector3(0,.78,0),Vector3(3.1,.16,2.0),"dark_wood")
	for p in [Vector3(-1.25,.38,-.75),Vector3(1.25,.38,-.75),Vector3(-1.25,.38,.75),Vector3(1.25,.38,.75)]:_box(origin+p,Vector3(.12,.76,.12),"steel")
	_box(origin+Vector3(0,.9,0),Vector3(1.55,.06,1.15),"breadboard",false)
	for z in [-.35,0.,.35]:
		for x in [-.55,-.25,.05,.35,.65]:_cylinder(origin+Vector3(x,.97,z),.035,.12,"socket")
	# Bench instruments: scope body with screen, supply and soldering cradle.
	_box(origin+Vector3(-1.0,1.2,.55),Vector3(.62,.62,.38),"instrument",false)
	_box(origin+Vector3(-1.0,1.23,.34),Vector3(.42,.3,.025),"scope_glow",false)
	_box(origin+Vector3(.8,1.14,.6),Vector3(.65,.5,.45),"instrument",false)
	_cylinder(origin+Vector3(.75,1.18,.35),.07,.05,"copper")
	_station(origin+Vector3(0,.93,0),Vector3(1.65,.2,1.25),"prototype_bench")

func _firmware_desk(origin: Vector3) -> void:
	_box(origin+Vector3(0,.75,0),Vector3(3.3,.12,1.0),"wood")
	for x in [-1.35,1.35]:_box(origin+Vector3(x,.36,0),Vector3(.12,.72,.8),"steel")
	for x in [-.68,.68]:
		_box(origin+Vector3(x,1.38,.22),Vector3(1.15,.68,.07),"screen",false)
		_box(origin+Vector3(x,1.03,.22),Vector3(.06,.45,.06),"steel",false)
	_box(origin+Vector3(0,.86,-.18),Vector3(1.45,.05,.38),"keyboard",false)
	_station(origin+Vector3(-.68,1.38,.18),Vector3(1.2,.72,.14),"firmware_console")

func _storage_wall(origin: Vector3) -> void:
	_box(origin+Vector3(0,1.55,0),Vector3(.55,3.0,4.7),"cabinet")
	for y in [.45,1.05,1.65,2.25]:
		for z in [-1.8,-.9,0.,.9,1.8]:
			_box(origin+Vector3(-.31,y,z),Vector3(.08,.42,.68),"bin_blue" if int(y*10+z*10)%2==0 else "bin_amber",false)
	_station(origin+Vector3(-.38,1.15,0),Vector3(.2,2.5,4.4),"kit_library")

func _decor(origin: Vector3) -> void:
	# Acoustic slats, cable reels, plant, rug and warm task lighting dress the studio.
	for z in [43.0,45.0,49.0,51.0]:_box(Vector3(35.72,1.8,z),Vector3(.06,2.7,.09),"wood",false)
	for x in [22.5,26.,29.5,33.]:_box(Vector3(x,.02,47.2),Vector3(2.2,.025,1.4),"rug",false)
	for x in [23.5,28.,32.5]:
		_box(Vector3(x,3.65,47),Vector3(1.5,.07,.28),"warm_light",false)
	_cylinder(Vector3(33.4,.45,51.8),.42,.75,"planter")
	for offset in [Vector3(-.2,1.0,0),Vector3(.15,1.15,.1),Vector3(0,1.3,-.12)]:_cylinder(Vector3(33.4,0,51.8)+offset,.08,.65,"leaf")

func _station(pos: Vector3,size: Vector3,action: String) -> void:
	var body:=StaticBody3D.new();body.name=action.to_pascal_case();body.position=pos;body.collision_layer=4;body.collision_mask=0
	var collision:=CollisionShape3D.new();var shape:=BoxShape3D.new();shape.size=size;collision.shape=shape;body.add_child(collision);add_child(body)
	station_anchors[action]=body
	adapter.register_station(body,action)

func _box(pos: Vector3,size: Vector3,color: String,solid: bool=true) -> void:
	var mesh:=MeshInstance3D.new();var box:=BoxMesh.new();box.size=size;mesh.mesh=box;mesh.material_override=_material(color);mesh.position=pos;add_child(mesh)
	if solid:
		var body:=StaticBody3D.new();body.position=pos;body.collision_layer=1;body.collision_mask=0
		var collision:=CollisionShape3D.new();var shape:=BoxShape3D.new();shape.size=size;collision.shape=shape;body.add_child(collision);add_child(body)

func _cylinder(pos: Vector3,radius: float,height: float,color: String) -> void:
	var mesh:=MeshInstance3D.new();var cylinder:=CylinderMesh.new();cylinder.top_radius=radius;cylinder.bottom_radius=radius;cylinder.height=height;mesh.mesh=cylinder;mesh.material_override=_material(color);mesh.position=pos;add_child(mesh)

func _material(id: String) -> StandardMaterial3D:
	if materials.has(id):return materials[id]
	var colors:={"wood":"9a704b","dark_wood":"59463c","steel":"53636c","matte_green":"2d675b","screen":"172a35","copper":"d28a45","component":"26333d","breadboard":"d9d5c7","socket":"263238","instrument":"394853","scope_glow":"65d7c8","keyboard":"232a31","cabinet":"344c58","bin_blue":"4c7a8b","bin_amber":"bd824c","rug":"385e62","warm_light":"f5d89a","planter":"a46f4e","leaf":"4d825a"}
	var material:=StandardMaterial3D.new();material.albedo_color=Color(str(colors.get(id,"b8b8b8")));material.roughness=.68;material.metallic=.25 if id in ["steel","copper"] else .02
	if id in ["scope_glow","warm_light"]:material.emission_enabled=true;material.emission=material.albedo_color;material.emission_energy_multiplier=.8
	materials[id]=material;return material

