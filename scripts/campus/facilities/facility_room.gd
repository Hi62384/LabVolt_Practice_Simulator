extends Node3D
## Furniture only. Pass the central registry room dictionary; owns no room shells.
var stations := {}
var materials := {}
var room_id:=""
var venue:=""
var placed_food:={}
static var meshes:={}
static var shapes:={}

static func vector(value: Variant) -> Vector3:
	if value is Vector3:return value
	if value is Array and value.size()==3:return Vector3(float(value[0]),float(value[1]),float(value[2]))
	return Vector3.ZERO

func build(room: Dictionary, menu: Dictionary) -> Dictionary:
	if not stations.is_empty():return stations.duplicate(true)
	room_id=str(room.get("id",""))
	if room_id.is_empty():return {}
	venue=room_id if room_id in ["tim_hortons","subway"] else str(room.get("kind",""))
	if not venue in ["tim_hortons","subway","gym","student_commons"]:return {}
	position=vector(room.get("anchor",room.get("center",[])))
	if venue=="gym":_gym()
	elif venue=="student_commons":_commons()
	else:_restaurant(menu)
	return stations.duplicate(true)

func material(color: Color) -> StandardMaterial3D:
	var key:=color.to_html()
	if not materials.has(key):
		var mat:=StandardMaterial3D.new()
		mat.albedo_color=color;mat.roughness=0.85
		materials[key]=mat
	return materials[key]

func box(at: Vector3,size: Vector3,color: Color,collision: bool=true) -> MeshInstance3D:
	var node:=MeshInstance3D.new()
	if not meshes.has(size):
		var mesh:=BoxMesh.new();mesh.size=size;meshes[size]=mesh
	node.mesh=meshes[size];node.material_override=material(color);node.position=at
	node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.visibility_range_end=32
	add_child(node)
	if collision:
		var body:=StaticBody3D.new();body.collision_layer=1;body.collision_mask=0
		if not shapes.has(size):
			var cube:=BoxShape3D.new();cube.size=size;shapes[size]=cube
		var shape:=CollisionShape3D.new()
		shape.shape=shapes[size];body.add_child(shape);node.add_child(body)
	return node

func label(at: Vector3,text: String,width: float=0.007) -> void:
	var node:=Label3D.new();node.text=text;node.position=at;node.pixel_size=width
	node.font_size=32;node.outline_size=3;node.modulate=Color.WHITE
	node.no_depth_test=false;node.visibility_range_end=22
	add_child(node)

func station(key: String,kind: String,at: Vector3) -> void:
	stations[room_id+"/"+key]={"room_id":room_id,"kind":kind,"position":position+at}

func _restaurant(menu: Dictionary) -> void:
	var accent:=Color("a82f37") if venue=="tim_hortons" else Color("167849")
	box(Vector3(0,0.55,-2.5),Vector3(6,1.1,0.8),accent)
	box(Vector3(0,1.13,-2.5),Vector3(6.2,0.1,1),Color("dfcba7"))
	box(Vector3(0,1.65,-2.8),Vector3(1.1,0.8,0.12),Color("16323c"),false)
	label(Vector3(0,2.45,-2.7),"Tim Hortons" if venue=="tim_hortons" else "Subway",0.009)
	var text:="ORDER HERE • GAME DOLLARS\n"
	for id in menu:
		if menu[id].venue==venue:text+="%s  $%d\n"%[menu[id].name,menu[id].price]
	label(Vector3(-1.8,1.95,-2.4),text,0.0035)
	label(Vector3(1.7,1.9,-2.4),"Cashier terminal\nChoose • Pay • Enjoy",0.0035)
	station("counter","counter:"+venue,Vector3(0,0,-1.2))
	var toon := preload("res://scripts/toon_character.gd")
	var cashier := toon.build(toon.preset(0))
	cashier.name = "Cashier"
	cashier.position = Vector3(0,0,-3.37)
	add_child(cashier)
	var target := StaticBody3D.new()
	target.collision_layer = 4
	target.collision_mask = 0
	target.set_meta("role", "restaurant_cashier")
	target.set_meta("station", room_id+"/counter")
	cashier.add_child(target)
	var hit := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(.66,.86,.45)
	hit.shape = shape
	hit.position.y = 1.32
	target.add_child(hit)
	for i in 4:
		var at:=Vector3(-4.5+(i%2)*4.2,0,1+(i/2)*2.7)
		var table := box(at+Vector3(0,0.75,0),Vector3(1.5,0.1,1),Color("dfcba7"))
		table.get_child(0).set_meta("role","table")
		box(at+Vector3(0,0.36,0),Vector3(0.12,0.72,0.12),Color("383f45"))
		for prop in [
			box(at+Vector3(0,0.42,0.95),Vector3(0.65,0.12,0.65),accent),
			box(at+Vector3(0,0.85,1.22),Vector3(0.65,0.8,0.1),accent)]:
			prop.get_child(0).set_meta("role", "facility_seat")
			prop.get_child(0).set_meta("station", "%s/seat_%d" % [room_id,i])
		station("seat_%d"%i,"seat",at+Vector3(0,0,0.9))
		stations["%s/seat_%d" % [room_id,i]].merge({"seat_position":position+at+Vector3(0,0,.95),"seat_yaw":0.0})

func _commons() -> void:
	for x in [-5.5,0.0,5.5]:
		_commons_prop("dining_table",Vector3(x,0,0),0.0,{"oak":"b89165","metal":"303e46"},Vector3(1.5,.8,1))
		for z in [-2.0,2.0]:
			for offset in [-.65,.65]:
				var at := Vector3(x+offset,0,z)
				_commons_prop("lounge_chair",at,0.0 if z>0 else PI,{"blue":"406975","oak":"896744"},Vector3(.85,.88,.85))
				station("lounge_%s_%s_%s" % [x,z,offset],"seat",at)
	for x in [-6.0,0.0,6.0]:
		_commons_prop("bookcase",Vector3(x,0,5.62),PI,{"oak":"b89165","red":"8c4b4b","sage":"607a66","blue":"4d6782","cream":"ddd0b6"},Vector3(1.0,1.9,.42))

func _commons_prop(model: String, at: Vector3, yaw: float, palette: Dictionary, size: Vector3) -> void:
	var root := StaticBody3D.new()
	if model=="dining_table":root.set_meta("role","table")
	root.position=at
	root.rotation.y=yaw
	add_child(root)
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size=size
	collision.shape=shape
	collision.position.y=size.y*.5
	root.add_child(collision)
	for region in palette:
		var visual := MeshInstance3D.new()
		visual.mesh=load("res://assets/campus/decor/social_rooms/meshes/%s__%s.obj" % [model,region])
		visual.material_override=material(Color(palette[region]))
		root.add_child(visual)

func _gym() -> void:
	var metal:=Color("414c59");var pad:=Color("194d5c")
	var kinds:=["pushup","pullup","benchpress","squat","curl"]
	for i in kinds.size():
		var at:=Vector3(-5+(i%3)*4.5,0,-2+(i/3)*4.8)
		var kind: String=kinds[i]
		if kind=="pushup":box(at+Vector3(0,0.04,0),Vector3(1.1,0.08,2.2),pad,false)
		elif kind in ["pullup","squat"]:
			for x in [-0.9,0.9]:box(at+Vector3(x,1.3,0),Vector3(0.12,2.6,0.12),metal)
			box(at+Vector3(0,2.6,0),Vector3(2,0.12,0.12),metal)
			if kind=="squat":pass # M105 motion adapter owns the moving bar and plates.
		elif kind=="benchpress":
			box(at+Vector3(0,0.52,0),Vector3(0.6,0.15,1.9),pad)
			# M105 motion adapter owns the moving bar and plates.
			for x in [-0.9,0.9]:box(at+Vector3(x,0.6,-0.8),Vector3(0.12,1.2,0.12),metal)
		else:
			box(at+Vector3(0,0.65,-0.5),Vector3(2.4,0.12,0.6),metal)
			# M105 motion adapter owns the moving dumbbell.
		# Compact HUD presents station context; no floating station labels.
		# Interact from the free aisle; minigames never teleport into collision geometry.
		station(kind,kind,at+Vector3(0,0,1.5))
		var target := StaticBody3D.new()
		target.collision_layer = 4
		target.collision_mask = 0
		target.set_meta("role", "gym_equipment")
		target.set_meta("station", room_id+"/"+kind)
		target.position = at
		add_child(target)
		var hit := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		match kind:
			"pushup":
				shape.size = Vector3(1.1,.10,2.2)
				hit.position.y = .055
			"pullup", "squat":
				shape.size = Vector3(2,.16,.19)
				hit.position.y = 2.6
				for x in [-.9,.9]:
					var upright := CollisionShape3D.new()
					var post := BoxShape3D.new()
					post.size = Vector3(.17,2.6,.18)
					upright.shape = post
					upright.position = Vector3(x,1.3,0)
					target.add_child(upright)
			"benchpress":
				shape.size = Vector3(.66,.20,1.96)
				hit.position.y = .52
			"curl":
				shape.size = Vector3(2.46,.25,.66)
				hit.position = Vector3(0,.72,-.5)
		hit.shape = shape
		target.add_child(hit)
	# Wall sign is provided by the numbered campus signage; no floating directions.

func nearest(point: Vector3,max_distance: float=2.5) -> String:
	var best:="";var distance:=max_distance
	for key in stations:
		var d: float=point.distance_to(stations[key].position)
		if d<=distance:best=key;distance=d
	return best

func sync_food(peer: int,held: Dictionary) -> void:
	if placed_food.has(peer):
		if is_instance_valid(placed_food[peer]):placed_food[peer].queue_free()
		placed_food.erase(peer)
	var id:=str(held.get("station",""))
	if held.is_empty() or not stations.has(id):return
	var item:=str(held.get("item",""))
	var prop := preload("res://scripts/campus/facilities/food_visual.gd").placed(item,int(held.servings),peer,"order")
	add_child(prop)
	prop.global_position=stations[id].position+Vector3(0,.8,-.9)
	placed_food[peer]=prop
