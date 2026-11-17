extends Node3D
## A single persistent campus shell. No mode owns or duplicates its geometry.
signal zone_activation_changed(room_id: String, active: bool)
signal elevator_control_requested(floor_id: int, button: int)
const Registry = preload("res://scripts/campus/world/room_registry.gd")
const Streamer = preload("res://scripts/campus/world/zone_streamer.gd")
const Signage = preload("res://scripts/campus/presentation/signage/campus_signage.gd")
const HallwayGeometry = preload("res://scripts/campus/presentation/navigation_safety/hallway_geometry.gd")
const HallwayFinish = preload("res://scripts/campus/presentation/hallway_finish.gd")
const ExteriorFinish = preload("res://scripts/campus/presentation/exterior_finish.gd")
var registry = Registry.new()
var streamer = Streamer.new()
var room_roots: Dictionary = {}
var anchors: Dictionary = {}
var materials: Dictionary = {}
var box_mesh := BoxMesh.new()
var shell_built := false
var build_usec := 0
var solid_count := 0
var elevator_geometry: Node3D
var viewer_actor: Node3D
var viewer_clock := 0.0
const WINDOW_ROOMS := ["elm253_lecture", "ety155_lecture", "clothing_store", "ac_lab", "dc_lab", "campus_store", "shop", "computer", "study"]
const OPEN_FOOD_ROOMS := ["tim_hortons", "subway"]
@export var enable_occlusion := true

func _ready() -> void:
	build()

func build() -> void:
	if shell_built: return
	shell_built=true
	var begin := Time.get_ticks_usec()
	get_viewport().use_occlusion_culling=enable_occlusion
	box_mesh.size=Vector3.ONE
	add_child(streamer)
	streamer.zone_activation_changed.connect(func(id: String, enabled: bool): zone_activation_changed.emit(id,enabled))
	_circulation()
	for room in registry.rooms.values():
		_room(room)
		_room_lighting(room)
	_close_hallway_voids()
	_stairs()
	HallwayFinish.apply(self)
	_elevator()
	var exterior_finish := ExteriorFinish.new()
	exterior_finish.name="ExteriorFinish"
	exterior_finish.mount(self)
	build_usec=Time.get_ticks_usec()-begin
	streamer.set_viewer_position(registry.vector(registry.data.entrance))

func material(color: String) -> StandardMaterial3D:
	if not materials.has(color):
		var item := StandardMaterial3D.new()
		item.albedo_color=Color(color)
		item.roughness=.9
		materials[color]=item
	return materials[color]

func _room_lighting(room: Dictionary) -> void:
	var id := str(room.id)
	if id.begins_with("circulation") or id in ["ac_lab", "dc_lab", "shop", "elm253_lecture", "ety155_lecture", "computer", "washroom_1", "washroom_2", "subway", "clothing_store"]:return
	var light_rig := Node3D.new()
	light_rig.name = str(room.number) + "InteriorLighting"
	light_rig.position = registry.vector(room.center)
	add_child(light_rig)
	var fixture_x: Array = [-2.0,2.0] if id=="study" else [-6.0,0.0,6.0]
	var fixture_z: Array = [0.0] if id=="study" else ([-1.5,1.5] if id=="computer_commons" else [-3.0,3.0])
	for x in fixture_x:
		for z in fixture_z:
			box(light_rig, Vector3(x,3.88,z), Vector3(2.3,.06,.32), "f4edda", false)
			preload("res://scripts/campus/presentation/fixture_light.gd").down(light_rig, Vector3(x,3.83,z),.88,6.6)
	register_content(id, light_rig)

func box(parent: Node3D, pos: Vector3, size: Vector3, color: String, solid: bool=true) -> Node3D:
	var node := MeshInstance3D.new()
	node.mesh=box_mesh
	node.material_override=material(color)
	node.position=pos
	node.scale=size
	node.visibility_range_end=150.0
	node.visibility_range_end_margin=8.0
	parent.add_child(node)
	if solid:
		var body := StaticBody3D.new()
		body.position=pos
		body.collision_layer=1
		body.collision_mask=0
		var collision := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size=size
		collision.shape=shape
		body.add_child(collision)
		parent.add_child(body)
		solid_count+=1
	return node

func sign_text(parent: Node3D, text: String, point: Vector3, yaw: float=0.0, font_size: int=56) -> Label3D:
	var label := Signage.create_label(text,point,yaw,font_size)
	parent.add_child(label)
	return label

func _room(room: Dictionary) -> void:
	var root := Node3D.new()
	root.name=str(room.id)
	add_child(root)
	room_roots[room.id]=root
	var center: Vector3=registry.vector(room.center)
	var size: Vector3=registry.vector(room.size)
	var west := center.x<13
	var door: Vector3=registry.vector(room.door)
	var xmin := center.x-size.x/2
	var xmax := center.x+size.x/2
	var zmin := center.z-size.z/2
	var zmax := center.z+size.z/2
	var wall_x := xmax if west else xmin
	var wall_color := "eeece4" if room.kind in ["lecture", "computer"] else "c6cbd6"
	box(root,center+Vector3(0,-.12,0),Vector3(size.x,.24,size.z),"71829b")
	box(root,center+Vector3(0,4.15,0),Vector3(size.x,.2,size.z),"d5d9e2")
	for z in [zmin,zmax]:
		if room.id=="computer_commons" and z==zmin:
			# The elevator already supplies the adjoining wall from x=16 to 24.
			_room_wall(root,Vector3(30,center.y+2.04,z),Vector3(12,4.08,.16),wall_color)
			continue
		if (room.id == "cafeteria" and z == zmax) or (room.id == "tim_hortons" and z == zmin):
			# Six-metre passage toward the corridor side of the joined dining area.
			_room_wall(root,Vector3(17,center.y+2.04,z),Vector3(2,4.08,.16),wall_color)
			_room_wall(root,Vector3(29,center.y+2.04,z),Vector3(14,4.08,.16),wall_color)
			_room_wall(root,Vector3(21,center.y+3.54,z),Vector3(6,1.08,.16),wall_color)
			continue
		if (room.id == "tim_hortons" and z == zmax) or (room.id == "subway" and z == zmin): continue
		_room_wall(root,Vector3(center.x,center.y+2.04,z),Vector3(size.x,4.08,.16),wall_color)
	_room_wall(root,Vector3(xmin if west else xmax,center.y+2.04,center.z),Vector3(.16,4.08,size.z),wall_color)
	var side := (size.z-float(room.door_width))/2
	if room.id not in OPEN_FOOD_ROOMS:
		for direction in [-1,1]:
			var midpoint: float = center.z+direction*(float(room.door_width)/2+side/2)
			if room.id in WINDOW_ROOMS and side > 1.4:
				_window_wall(root,wall_x,center.y,midpoint,side,wall_color)
			else:
				_room_wall(root,Vector3(wall_x,center.y+2.04,midpoint),Vector3(.16,4.08,side),wall_color)
		_room_wall(root,door+Vector3(0,3.5,0),Vector3(.16,1,float(room.door_width)),"3c5270")
		if room.id != "cafeteria": _add_door(root,door,float(room.door_width),west,str(room.id))
		Signage.add_room_number_faces(root,room,door,west)
	var marker := Marker3D.new()
	marker.name="ContentAnchor"
	marker.position=registry.vector(room.anchor)
	root.add_child(marker)
	anchors[room.id]=marker
func _window_wall(root: Node3D, x: float, y: float, z: float, length: float, color: String) -> void:
	var width := minf(2.2, length-.5)
	var edge := (length-width)*.5
	var face := x + (.09 if x < 13.0 else -.09)
	box(root,Vector3(face,y+.52,z),Vector3(.018,1.04,length),"4e697e",false)
	box(root,Vector3(face,y+3.47,z),Vector3(.018,1.22,length),"bdc4cd",false)
	box(root,Vector3(face,y+.09,z),Vector3(.035,.18,length),"314757",false)
	for direction in [-1,1]:
		box(root,Vector3(face,y+1.95,z+direction*(width+edge)*.5),Vector3(.018,1.82,edge),"bdc4cd",false)
	_room_wall(root,Vector3(x,y+.52,z),Vector3(.16,1.04,length),color)
	_room_wall(root,Vector3(x,y+3.46,z),Vector3(.16,1.24,length),color)
	for direction in [-1,1]:
		_room_wall(root,Vector3(x,y+1.95,z+direction*(width+edge)*.5),Vector3(.16,1.82,edge),color)
	var glass := MeshInstance3D.new()
	glass.mesh=box_mesh
	glass.position=Vector3(x,y+1.95,z)
	glass.scale=Vector3(.035,1.82,width)
	var glass_material := StandardMaterial3D.new()
	glass_material.albedo_color=Color(.55,.78,.85,.18)
	glass_material.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
	glass_material.roughness=.15
	glass_material.cull_mode=BaseMaterial3D.CULL_DISABLED
	glass.material_override=glass_material
	root.add_child(glass)
	var body := StaticBody3D.new()
	body.position=glass.position
	var shape := BoxShape3D.new()
	shape.size=Vector3(.12,1.82,width)
	var collision := CollisionShape3D.new()
	collision.shape=shape
	body.add_child(collision)
	root.add_child(body)
	for height in [1.04,2.86]:
		box(root,Vector3(x,y+height,z),Vector3(.22,.07,width+.12),"314757",false)

func _add_door(root: Node3D, point: Vector3, width: float, west: bool, id: String) -> void:
	var door := preload("res://scripts/campus/world/room_door.gd").new()
	door.name="Door_"+id
	door.position=point
	root.add_child(door)
	door.build(width,west,material("385568"),material("b9d3d2"))

func _room_wall(root: Node3D, point: Vector3, size: Vector3, color: String) -> void:
	box(root,point,size,color)
	if not enable_occlusion or minf(size.x,minf(size.y,size.z))<=.02:return
	# Inset each occluder inside the solid wall segment, leaving the doorway open.
	var occluder := OccluderInstance3D.new()
	var geometry := BoxOccluder3D.new()
	geometry.size=size-Vector3.ONE*.02
	occluder.occluder=geometry
	occluder.position=point
	root.add_child(occluder)

func _directory_text() -> String:
	var lines := PackedStringArray(["DIRECTORY"])
	for room in registry.directory():
		lines.append(str(room.number)+" · "+str(room.title))
	return "\n".join(lines)

func _circulation() -> void:
	# Bridge the cafeteria and both food areas into one continuous room.
	box(self,Vector3(26,-.12,26),Vector3(20,.24,2),"71829b")
	box(self,Vector3(26,4.15,26),Vector3(20,.2,2),"d5d9e2")
	box(self,Vector3(36,2.04,26),Vector3(.16,4.08,2),"c6cbd6")
	# Close the unused space between the shells and finish the six-metre passage.
	box(self,Vector3(17,2.04,26),Vector3(2,4.08,1.84),"c6cbd6")
	box(self,Vector3(29,2.04,26),Vector3(14,4.08,1.84),"c6cbd6")
	box(self,Vector3(21,3.54,26),Vector3(6,1.08,1.84),"c6cbd6")
	for x in [18.0,24.0]:
		box(self,Vector3(x,1.51,26),Vector3(.12,3.02,2.14),"36515d",false)
	box(self,Vector3(21,3.03,26),Vector3(6.12,.14,2.14),"36515d",false)
	# Continue the same two-tone wainscot and base trim over the partition.
	for z in [24.91,27.09]:
		for part in [[17.0,1.8],[29.0,13.8]]:
			box(self,Vector3(part[0],.66,z),Vector3(part[1],1.28,.025),"4e697e",false)
			box(self,Vector3(part[0],.09,z),Vector3(part[1],.18,.045),"314757",false)
	box(self,Vector3(15.91,.66,26),Vector3(.025,1.28,1.8),"4e697e",false)
	box(self,Vector3(15.89,.09,26),Vector3(.045,.18,1.8),"314757",false)
	box(self,Vector3(26,-.12,40),Vector3(20,.24,2),"71829b")
	box(self,Vector3(26,4.15,40),Vector3(20,.2,2),"d5d9e2")
	box(self,Vector3(36,2.04,40),Vector3(.16,4.08,2),"c6cbd6")
	# One continuous tile grid bridges the corridor and both food counters.
	var food_tiles: Array=[]
	for x in range(16,36):
		for z in range(13,53): food_tiles.append(Vector3(x+.5,.052,z+.5))
	preload("res://scripts/campus/performance/lit_tile_batches.gd").build(self,food_tiles,Vector3(.982,.012,.982),material("8492a0"))
	# Continuous ground corridor, lobby and outdoor entrance.
	box(self,Vector3(13,-.12,28.5),Vector3(6,.24,79),"626d7a")
	box(self,Vector3(13,-.12,-18),Vector3(46,.24,14),"687b50")
	for floor in [0,1]:
		var y := float(floor)*5
		if floor==1:
			box(self,Vector3(13,y-.12,23),Vector3(6,.24,54),"879996")
			box(self,Vector3(14.5,y-.12,56),Vector3(3,.24,12),"879996")
			box(self,Vector3(13,y-.12,65),Vector3(6,.24,6),"879996")
		box(self,Vector3(13,y+4.15,23),Vector3(6,.2,54),"d6e0da")
		if floor==1:
			box(self,Vector3(13,y+4.15,59),Vector3(6,.2,18),"d5d9e2")
		if floor==0:
			for x in [10.5,15.5]:box(self,Vector3(x,y+2,68),Vector3(1,4,.16),"a6b9b4")
			box(self,Vector3(13,y+3.6,68),Vector3(4,.8,.16),"34606a")
		else:box(self,Vector3(13,y+2,68),Vector3(6,4,.16),"a6b9b4")
		for x in [10.0,16.0]:
			if x==16.0:
				# The upper-floor computer commons owns this wall, including its
				# entrance at z=61. Keep the ground-floor wall unchanged.
				box(self,Vector3(x,y+2,56),Vector3(.16,4,4),"a6b9b4")
				if floor==0:
					box(self,Vector3(x,y+2,64),Vector3(.16,4,8),"a6b9b4")
			else:
				if floor==1:box(self,Vector3(x,y+2,63),Vector3(.16,4,10),"c6cbd6")
				else:
					box(self,Vector3(x,y+2,58.4),Vector3(.16,4,8.8),"c6cbd6")
					box(self,Vector3(x,y+2,66.6),Vector3(.16,4,2.8),"c6cbd6")
	# Preserve the play bounds while opening the skyline over a low masonry edge.
	for x in [-10.,36.]:
		box(self,Vector3(x,.24,-18),Vector3(.5,.48,14),"697d81")
		box(self,Vector3(x,1.24,-18),Vector3(.5,1.52,14),"697d81").hide()
	box(self,Vector3(13,.24,-25),Vector3(46,.48,.5),"697d81")
	box(self,Vector3(13,1.24,-25),Vector3(46,1.52,.5),"697d81").hide()
	for x in [0.,26.]: box(self,Vector3(x,1,-11),Vector3(20,2,.5),"36596b")
	for x in [10.,16.]:
		# Exterior glazing and entrance columns already cover the south seam.
		# Retain its collision while avoiding overlapping visible wall faces.
		var seam := box(self,Vector3(x,2.04,-10.53),Vector3(.16,4.08,.94),"b6bdc6")
		seam.hide()
		box(self,Vector3(x,2.04,-7.03),Vector3(.16,4.08,6.06),"b6bdc6")

func _close_hallway_voids() -> void:
	# Room shells intentionally own their doors. These sections cover only the
	# unsupported seams between shells, with matching visible/collision geometry.
	for closure in HallwayGeometry.edge_closures():
		box(self,closure.position,closure.size,HallwayGeometry.WALL_COLOR)
	# The staircase needs an open ceiling within the corridor, with continuous
	# outer walls around that opening and an enclosed band between storeys.
	for x in [10.0,16.0]:
		box(self,Vector3(x,4.5,59),Vector3(.16,1.04,18),HallwayGeometry.WALL_COLOR)
	box(self,Vector3(13,4.5,68),Vector3(6,1.04,.16),HallwayGeometry.WALL_COLOR)

func _stairs() -> void:
	# A single convex wedge provides smooth capsule movement; treads are visual only.
	var body := StaticBody3D.new()
	var shape := ConvexPolygonShape3D.new()
	shape.points=PackedVector3Array([Vector3(10,-.2,50),Vector3(13,-.2,50),Vector3(10,-.2,62),Vector3(13,-.2,62),Vector3(10,5,62),Vector3(13,5,62)])
	var collision := CollisionShape3D.new()
	collision.shape=shape
	body.add_child(collision)
	add_child(body)
	for i in range(30):
		var height := (i+1)*5.0/30
		box(self,Vector3(11.5,height/2,50+(i+.5)*.4),Vector3(3,height,.4),"7f9997",false)
	for x in [10.1,12.9]:
		var rail := box(self,Vector3(x,3.5,56),Vector3(.08,.08,13),"34606a",false)
		rail.rotation.x=-atan2(5,12)
	# Guard the exposed edge of the upper corridor. Both stair approaches stay open.
	box(self,Vector3(13,5.46,55.6),Vector3(.10,.92,11.2),"34606a")

func _elevator() -> void:
	elevator_geometry = preload("res://scripts/campus/elevator/elevator_geometry.gd").new()
	elevator_geometry.name = "ElevatorGeometry"
	add_child(elevator_geometry)
	elevator_geometry.mount(self)

func interact(target: Node, actor: Node3D) -> bool:
	if not is_instance_valid(target): return false
	if target.get_meta("role", "") == "campus_door":
		if is_instance_valid(actor) and actor.global_position.distance_to(target.global_position) <= 3.5:
			target.request_toggle()
		return true
	if target.get_meta("role", "") != "elevator_control": return false
	if not elevator_geometry.is_ancestor_of(target): return false
	if not is_instance_valid(actor) or actor.global_position.distance_to(target.global_position) > 3: return true
	elevator_control_requested.emit(int(target.get_meta("floor")), int(target.get_meta("button")))
	return true

func anchor(id: String) -> Transform3D:
	return registry.anchor(id)

func register_content(id: String, root: Node3D) -> bool:
	return streamer.register_content(id,root)

func request_room(id: String) -> void:
	streamer.request_room(id)

func set_viewer_position(point: Vector3) -> void:
	streamer.set_viewer_position(point)

func metrics() -> Dictionary:
	return {"shell_build_usec":build_usec,"solids":solid_count,"shared_materials":materials.size(),"rooms":room_roots.size(),"streaming":streamer.metrics()}

func set_viewer(actor: Node3D) -> void:
	viewer_actor=actor
	if is_instance_valid(actor): set_viewer_position(actor.global_position)

func _process(delta: float) -> void:
	viewer_clock+=delta
	if viewer_clock>=.15:
		viewer_clock=0.0
		if is_instance_valid(viewer_actor): set_viewer_position(viewer_actor.global_position)

func register_loader(id: String, loader: Callable) -> bool:
	return streamer.register_loader(id,loader)
