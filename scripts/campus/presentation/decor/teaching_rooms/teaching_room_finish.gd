class_name TeachingRoomFinish
extends Node3D
## Registry-bound architectural finish. Existing desks, seats and devices stay authoritative.

const ROOMS := {
	"ac_lab":{"number":"M101","accent":"b49357","base":0.0,"west":-10.0,"east":10.0,"south":-4.0,"north":10.0,"door_east":true},
	"dc_lab":{"number":"M103","accent":"518681","base":0.0,"west":-10.0,"east":10.0,"south":13.0,"north":25.0,"door_east":true},
	"elm253_lecture":{"number":"M201","accent":"b49357","base":5.0,"west":-10.0,"east":10.0,"south":-3.0,"north":9.0,"door_east":true},
	"ety155_lecture":{"number":"M202","accent":"518681","base":5.0,"west":16.0,"east":36.0,"south":-3.0,"north":9.0,"door_east":false},
	"computer":{"number":"M203","accent":"677da0","base":5.0,"west":-10.0,"east":10.0,"south":13.0,"north":25.0,"door_east":true}
}
const WOOD := Color("aa8263")
const DARK := Color("2d4147")

var mounted: Dictionary={}
var materials := {}

func mount(room_id: String,campus: Node,registry: Object) -> bool:
	if not ROOMS.has(room_id) or not is_instance_valid(campus) or not is_instance_valid(registry):return false
	if mounted.has(room_id):return is_instance_valid(mounted[room_id])
	var room: Dictionary=registry.call("get_room",room_id)
	if room.is_empty() or str(room.get("number",""))!=str(ROOMS[room_id].number):return false
	var p: Dictionary=ROOMS[room_id]
	# Refuse stale profiles if the authoritative room shell moves or resizes.
	var low: Array=room.get("bounds_min",[]);var high: Array=room.get("bounds_max",[])
	if low.size()!=3 or high.size()!=3:return false
	if absf(float(low[0])-float(p.west))>.01 or absf(float(high[0])-float(p.east))>.01:return false
	if absf(float(low[1])-float(p.base))>.01 or absf(float(low[2])-float(p.south))>.01 or absf(float(high[2])-float(p.north))>.01:return false
	var root:=Node3D.new();root.name="TeachingFinish_"+room_id;campus.add_child(root)
	if room.get("kind") == "lecture":
		_lecture(root, campus, room, p)
		if not campus.call("register_content",room_id,root):root.queue_free();return false
		mounted[room_id]=root
		return true
	var accent:=Color(str(p.accent));var cx: float=(float(p.west)+float(p.east))*.5
	# Continuous dado and crown on solid south/north walls; 0.12 m inset clears shell.
	for z in [float(p.south)+.14,float(p.north)-.14]:
		_bar(root,Vector3(cx,float(p.base)+1.10,z),Vector3(19.2,.10,.055),WOOD)
		_bar(root,Vector3(cx,float(p.base)+3.70,z),Vector3(19.2,.08,.07),accent)
	# The far side wall has no doorway. A pilaster rhythm adds depth without floor clutter.
	var side_x: float=float(p.west)+.14 if bool(p.door_east) else float(p.east)-.14
	for i in range(5):
		var z: float=float(p.south)+1.05+float(i)*(float(p.north)-float(p.south)-2.1)/4.0
		_bar(root,Vector3(side_x,float(p.base)+2.28,z),Vector3(.065,2.28,.11),DARK)
		_bar(root,Vector3(side_x,float(p.base)+3.48,z),Vector3(.095,.10,.34),accent)
	# Ceiling housings and diffusers follow the classroom rows.
	for i in range(3 if room_id.ends_with("lab") else 4):
		var x: float=cx-5.4+float(i)*(5.4 if room_id.ends_with("lab") else 3.6)
		var z := (float(p.south) + float(p.north)) * .5
		_bar(root,Vector3(x,float(p.base)+3.94,z),Vector3(.27,.11,7.5),DARK)
		_bar(root,Vector3(x,float(p.base)+3.879,z),Vector3(.204,.023,7.39),Color("fff2d9"),true)
		for dz in [-2.2, 2.2]:
			preload("res://scripts/campus/presentation/fixture_light.gd").down(root,Vector3(x,float(p.base)+3.84,z+dz),.72,6.1)
	# Room number is the sole new text. No instructional floating labels.
	var sign:=Label3D.new();sign.text=str(p.number);sign.font_size=54;sign.pixel_size=.003;sign.modulate=accent
	var east: bool=bool(p.door_east);sign.position=Vector3(float(p.east)-.21 if east else float(p.west)+.21,float(p.base)+2.95,(float(p.south)+float(p.north))*.5+2.2);sign.rotation.y=PI/2 if east else -PI/2;root.add_child(sign)
	if not campus.call("register_content",room_id,root):root.queue_free();return false
	mounted[room_id]=root
	return true

func _lecture(root: Node3D, campus: Node, room: Dictionary, profile: Dictionary) -> void:
	var center: Vector3 = campus.registry.vector(room.center)
	var size: Vector3 = campus.registry.vector(room.size)
	var half_width := size.x * .5
	var half_depth := size.z * .5
	root.position = center
	var floor_color := Color("919496")
	var dado := Color("8295a0")
	var baseboard := Color("52636e")
	_bar(root, Vector3(0,.006,0), Vector3(size.x-.17,.012,size.z-.17), floor_color)
	for x in range(-8,9,2):
		_bar(root, Vector3(x,.013,0), Vector3(.014,.003,size.z-.18), baseboard)
		_bar(root, Vector3(x,3.969,0), Vector3(.024,.005,size.z-.18), Color("bcbec1"))
	for z in range(-4,5,2):
		_bar(root, Vector3(0,.013,z), Vector3(size.x-.18,.003,.014), baseboard)
		_bar(root, Vector3(0,3.969,z), Vector3(size.x-.18,.005,.024), Color("bcbec1"))
	_bar(root, Vector3(0,3.99,0), Vector3(size.x-.17,.035,size.z-.17), Color("e1e1df"))
	for z in [-half_depth+.11,half_depth-.11]:
		_bar(root,Vector3(0,.57,z),Vector3(size.x-.2,1.14,.025),dado)
		_bar(root,Vector3(0,1.16,z),Vector3(size.x-.2,.07,.045),WOOD)
		_bar(root,Vector3(0,.082,z),Vector3(size.x-.2,.15,.045),baseboard)
	var far_x := (-half_width+.11) if profile.door_east else (half_width-.11)
	_bar(root,Vector3(far_x,.57,0),Vector3(.025,1.14,size.z-.2),dado)
	_bar(root,Vector3(far_x,1.16,0),Vector3(.045,.07,size.z-.2),WOOD)
	_bar(root,Vector3(far_x,.082,0),Vector3(.045,.15,size.z-.2),baseboard)
	for x in [-6.0,0.0,6.0]:
		for z in [-3.0,2.6]:
			_bar(root,Vector3(x,3.933,z),Vector3(2.25,.065,.67),DARK)
			_bar(root,Vector3(x,3.89,z),Vector3(2.08,.03,.52),Color("fff5de"),true)
			preload("res://scripts/campus/presentation/fixture_light.gd").down(root,Vector3(x,3.84,z),.95,7.2)
	var desk_x := -4.45 if profile.door_east else 4.45
	var desk_z := -half_depth+2.15
	campus.box(root,Vector3(desk_x,.79,desk_z),Vector3(1.8,.08,.75),"aa8263")
	var desk := StaticBody3D.new()
	desk.position=Vector3(desk_x,.77,desk_z)
	desk.collision_layer=4
	desk.collision_mask=0
	desk.set_meta("role","lecture_desk")
	desk.set_meta("room",room.id)
	desk.set_meta("label","Open class setup")
	root.add_child(desk)
	var desk_hit := CollisionShape3D.new()
	var desk_shape := BoxShape3D.new()
	desk_shape.size=Vector3(1.82,.15,.77)
	desk_hit.shape=desk_shape
	desk.add_child(desk_hit)
	for x in [-.77,.77]:
		for z in [-.28,.28]:
			_bar(root,Vector3(desk_x+x,.37,desk_z+z),Vector3(.055,.74,.055),DARK)
	_bar(root,Vector3(desk_x,.99,desk_z-.18),Vector3(.39,.31,.065),DARK)
	_bar(root,Vector3(desk_x,.86,desk_z-.18),Vector3(.10,.12,.17),DARK)
	_bar(root,Vector3(0,3.73,-.5),Vector3(.45,.18,.31),DARK)
	var face_z := -half_depth+.14
	var clock := MeshInstance3D.new()
	var clock_face := CylinderMesh.new()
	clock_face.top_radius=.22
	clock_face.bottom_radius=.22
	clock_face.height=.06
	clock.mesh=clock_face
	clock.position=Vector3(0,3.62,face_z)
	clock.rotation.x=PI*.5
	root.add_child(clock)
	_bar(root,Vector3(0,3.67,face_z+.041),Vector3(.019,.13,.018),DARK)
	_bar(root,Vector3(.057,3.62,face_z+.041),Vector3(.12,.016,.018),DARK)
	_bar(root,Vector3(-5.9,2.75,face_z),Vector3(2.35,.80,.055),DARK)
	campus.sign_text(root,str(room.number),Vector3(-5.9,2.76,face_z+.04),0.0,46)
	_bar(root,Vector3(5.8,2.32,face_z),Vector3(2.25,1.08,.055),WOOD)
	_bar(root,Vector3(5.8,2.32,face_z+.03),Vector3(2.12,.95,.021),Color("dbe2df"))

func mount_approved(campus: Node,registry: Object,ids: Array) -> Dictionary:
	var result:={"mounted":[],"failed":[]}
	for id in ids:
		if mount(str(id),campus,registry):result.mounted.append(id)
		else:result.failed.append(id)
	return result

func _bar(parent: Node3D,at: Vector3,size: Vector3,color: Color,emissive := false) -> void:
	var mesh:=BoxMesh.new();mesh.size=size
	var key := color.to_html() + str(emissive)
	if not materials.has(key):
		var shared := StandardMaterial3D.new()
		shared.albedo_color = color
		shared.roughness = .83
		shared.emission_enabled = emissive
		shared.emission = color
		shared.emission_energy_multiplier = .42
		materials[key] = shared
	var material: StandardMaterial3D = materials[key]
	var instance:=MeshInstance3D.new();instance.mesh=mesh;instance.material_override=material;instance.position=at;instance.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;parent.add_child(instance)
