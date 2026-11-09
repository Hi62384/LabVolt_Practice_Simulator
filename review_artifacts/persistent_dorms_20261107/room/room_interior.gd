extends Node3D
## Streamed visual interior. Public projection only; never stores inventory or files.
signal used(kind: String, room_id: String)
const Layout = preload("res://scripts/campus/dorms/world/dorm_layout.gd")
var room_id := ""
var targets := {}
var materials := {}
var lamps := {}

func build(contract: Dictionary, public_style: Dictionary = {}) -> void:
	room_id=str(contract.dorm_id)
	var c: Vector3=contract.center
	var outward := -1.0 if str(contract.side)=="west" else 1.0
	var wall := _color(public_style.get("wall","f2eee5"),"f2eee5")
	var floor_color := _color(public_style.get("floor","c6c1b5"),"c6c1b5")
	var bedding := _color(public_style.get("bedding","5b827d"),"5b827d")
	# Shell finish overlays the existing collision shell without altering door geometry.
	_box("FloorTiles",c+Vector3(0,.012,0),Vector3(6.55,.025,10.9),floor_color)
	for z in [-5.55,5.55]:
		_box("UpperWall",c+Vector3(0,2.55,z),Vector3(6.65,2.7,.04),wall)
		_box("LowerWall",c+Vector3(0,.68,z),Vector3(6.65,1.3,.045),"82919a")
		_box("WoodTrim",c+Vector3(0,1.35,z),Vector3(6.65,.09,.07),"76604c")
	_box("SuspendedCeiling",c+Vector3(0,3.95,0),Vector3(6.55,.05,10.9),"eeeae0")
	_box("CeilingPanel",c+Vector3(0,3.89,0),Vector3(.7,.035,1.6),"f4dfad")
	# Exterior-facing window only.
	var wx := c.x+outward*3.39
	_box("WindowGlass",Vector3(wx,2.25,c.z-.25),Vector3(.035,1.35,1.85),"9fb7bb")
	for z in [-1.0,.5]:_box("WindowFrame",Vector3(wx-outward*.04,2.25,c.z+z),Vector3(.11,1.48,.08),"ded8ca")
	for y in [1.55,2.95]:_box("WindowFrame",Vector3(wx-outward*.04,y,c.z-.25),Vector3(.11,.08,1.85),"ded8ca")
	_box("Blind",Vector3(wx-outward*.08,2.88,c.z-.25),Vector3(.06,.12,1.72),"e7e1d4")
	# A recognizable single bed; side circulation remains clear.
	var bx := c.x+outward*1.95
	_box("BedFrame",Vector3(bx,.35,c.z-3.55),Vector3(1.2,.27,2.2),"765b46")
	_box("Headboard",Vector3(bx,.65,c.z-4.62),Vector3(1.25,.72,.12),"6c5241")
	_box("Mattress",Vector3(bx,.58,c.z-3.55),Vector3(1.1,.22,2.05),"e8e2d5")
	_box("Duvet",Vector3(bx,.73,c.z-3.18),Vector3(1.12,.13,1.25),bedding)
	_box("Pillow",Vector3(bx,.74,c.z-4.3),Vector3(.76,.15,.4),"f7f1e5")
	_target("bed",Vector3(bx,.65,c.z-3.55),Vector3(1.2,.85,2.2),"Rest on bed")
	_box("Bedside",Vector3(bx-outward*.95,.55,c.z-4.2),Vector3(.52,1.05,.52),"876c54")
	_lamp("bedside_lamp",Vector3(bx-outward*.95,1.25,c.z-4.2))
	# Study surface leaves room for a worksheet; laptop occupies its rear edge.
	var dx := c.x-outward*1.65
	_box("StudyDesk",Vector3(dx,.76,c.z-2.25),Vector3(2.35,.1,1.1),"8b6b50")
	for x in [-1.05,1.05]:
		for z in [-.45,.45]:_box("DeskLeg",Vector3(dx+x,.38,c.z-2.25+z),Vector3(.1,.76,.1),"68513f")
	_box("LaptopBase",Vector3(dx,.84,c.z-2.55),Vector3(.68,.04,.48),"39464a")
	_box("LaptopScreen",Vector3(dx,1.12,c.z-2.82),Vector3(.68,.52,.045),"27383e")
	_target("computer",Vector3(dx,1.03,c.z-2.55),Vector3(.7,.62,.6),"Use study computer")
	_box("Notebook",Vector3(dx+.7,.84,c.z-2.12),Vector3(.4,.025,.31),"e8e1cc")
	_box("ChairSeat",Vector3(dx,.45,c.z-.95),Vector3(.65,.12,.58),"66787b")
	_box("ChairBack",Vector3(dx,.83,c.z-.65),Vector3(.65,.78,.09),"66787b")
	_target("study_chair",Vector3(dx,.55,c.z-.95),Vector3(.7,1.0,.65),"Sit at study desk")
	_lamp("desk_lamp",Vector3(dx-.85,1.05,c.z-2.65))
	# Wardrobe doors and handles remain visually separate from the solid cabinet.
	var vx := c.x+outward*2.3
	_box("Wardrobe",Vector3(vx,1.15,c.z+3.65),Vector3(1.35,2.25,1.0),"79624d")
	for offset in [-.32,.32]:
		_box("WardrobeDoor",Vector3(vx+offset,1.15,c.z+3.13),Vector3(.6,2.05,.045),"93775c")
		_box("WardrobeHandle",Vector3(vx+offset*.4,1.17,c.z+3.09),Vector3(.035,.16,.035),"d5bd8d")
	_target("wardrobe",Vector3(vx,1.2,c.z+3.1),Vector3(1.3,2.1,.18),"Change appearance")
	_box("StorageCabinet",Vector3(dx,.7,c.z+3.6),Vector3(1.25,1.35,.65),"81674f")
	_target("storage",Vector3(dx,.72,c.z+3.24),Vector3(1.2,1.3,.14),"Open personal storage")
	_box("Shelf",Vector3(dx,1.5,c.z+4.65),Vector3(1.6,.09,.34),"846b51")
	_box("Rug",Vector3(c.x,.025,c.z+.4),Vector3(2.1,.02,1.6),"9aada7")
	_box("PlantPot",Vector3(dx-.9,.26,c.z+4.75),Vector3(.37,.5,.37),"aa8268")
	_box("PlantLeaves",Vector3(dx-.9,.73,c.z+4.75),Vector3(.52,.57,.52),"63806c")
	# Existing tangible station props retain their anchors and routing.
	_target("kit_workshop",contract.workshop_anchor+Vector3(0,1,0),Vector3(.7,.5,.6),"Use open electronics kit")
	_target("loadout",contract.loadout_notes_anchor+Vector3(0,1,.35),Vector3(.7,.5,.4),"Organize backpack")
	_target("notes",contract.loadout_notes_anchor+Vector3(0,1,-.35),Vector3(.7,.5,.4),"Open notes")

func _color(value: Variant, fallback: String) -> String:
	var s := str(value).trim_prefix("#")
	return s if s.length()==6 and s.is_valid_hex_number() else fallback

func _material(hex: String) -> StandardMaterial3D:
	if not materials.has(hex):
		var m:=StandardMaterial3D.new();m.albedo_color=Color(hex);m.roughness=.88;materials[hex]=m
	return materials[hex]

func _box(label: String, pos: Vector3, size: Vector3, hex: String) -> void:
	var mesh:=MeshInstance3D.new();mesh.name=label;var box:=BoxMesh.new();box.size=size;mesh.mesh=box;mesh.material_override=_material(hex);mesh.position=pos;add_child(mesh)

func _target(kind: String, pos: Vector3, size: Vector3, label: String) -> void:
	var body:=StaticBody3D.new();body.name=kind;body.position=pos;body.collision_layer=4;body.collision_mask=0
	var shape:=CollisionShape3D.new();var box:=BoxShape3D.new();box.size=size;shape.shape=box;body.add_child(shape)
	body.set_meta("role","dorm_room_prop");body.set_meta("kind",kind);body.set_meta("room_id",room_id);body.set_meta("label",label);add_child(body);targets[kind]=body

func _lamp(kind: String, pos: Vector3) -> void:
	_box(kind+"Base",pos,Vector3(.18,.04,.18),"5c6260")
	_box(kind+"Stem",pos+Vector3(0,.2,0),Vector3(.045,.38,.045),"5c6260")
	_box(kind+"Shade",pos+Vector3(0,.42,0),Vector3(.31,.23,.31),"e8d1a0")
	var light:=OmniLight3D.new();light.position=pos+Vector3(0,.4,0);light.light_energy=.35;light.omni_range=2.8;light.visible=false;add_child(light);lamps[kind]=light
	_target(kind,pos+Vector3(0,.3,0),Vector3(.38,.6,.38),"Toggle lamp")

func toggle_lamp(kind: String) -> bool:
	if not lamps.has(kind):return false
	lamps[kind].visible=not lamps[kind].visible
	return true
