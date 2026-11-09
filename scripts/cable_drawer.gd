extends Node3D
var tray: Node3D
var front: AnimatableBody3D
var bags: Array[StaticBody3D] = []
var opened := false
var motion: Tween

func build(game: Node) -> void:
	position=Vector3(0,.40,-2.72)
	game._box(self,Vector3(0,.205,-.02),Vector3(2.72,.025,.98),Color("685c4c"))
	tray=Node3D.new()
	add_child(tray)
	game._box(tray,Vector3(0,0,0),Vector3(2.6,.035,.90),Color("a18c70"))
	for x in [-1.29,1.29]:
		game._box(tray,Vector3(x,.08,0),Vector3(.035,.18,.90),Color("8d7a61"))
	front = AnimatableBody3D.new()
	front.sync_to_physics = false
	front.position=Vector3(0,.06,.51)
	front.set_meta("role","drawer")
	front.set_meta("label","Cable drawer")
	tray.add_child(front)
	game._box(front,Vector3.ZERO,Vector3(2.66,.24,.06),Color("8d7a61"))
	game._line(front,Vector3(-.22,0,.075),Vector3(.22,0,.075),.019,Color("abb0aa"),.8)
	var hit := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size=Vector3(2.66,.24,.10)
	hit.shape=shape
	front.add_child(hit)
	var tray_collision := CollisionShape3D.new()
	var tray_shape := BoxShape3D.new()
	tray_shape.size = Vector3(2.60,.045,.90)
	tray_collision.shape = tray_shape
	tray_collision.position = Vector3(0,-.06,-.51)
	front.add_child(tray_collision)
	for i in range(4):
		var bag := StaticBody3D.new()
		bag.position=Vector3(-.96+i*.64,.065,.01)
		bag.set_meta("role","rack")
		bag.set_meta("color",i)
		bag.set_meta("label",["Red","Blue","Yellow","Black"][i]+" cables")
		tray.add_child(bag)
		bags.append(bag)
		var plastic: MeshInstance3D = game._box(bag,Vector3.ZERO,Vector3(.55,.09,.65),Color("c4d4d5"))
		var material := StandardMaterial3D.new()
		material.albedo_color=Color(.78,.88,.9,.22)
		material.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
		material.roughness=.23
		plastic.material_override=material
		game._box(bag,Vector3(0,.047,-.29),Vector3(.52,.008,.015),Color("c4d4d5"))
		for loop in range(3):
			for segment in range(24):
				var a := TAU*segment/24
				var b := TAU*(segment+1)/24
				var radius := .16+loop*.012
				game._line(bag,Vector3(cos(a)*radius,.012+loop*.008,sin(a)*radius),Vector3(cos(b)*radius,.012+loop*.008,sin(b)*radius),.009,game.JACKET_COLORS[i])
		var collision := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size=Vector3(.56,.12,.66)
		collision.shape=box
		bag.add_child(collision)
		bag.collision_layer=0

func sync(value: bool) -> void:
	if value==opened:
		return
	opened=value
	if motion:
		motion.kill()
	motion=create_tween().set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	motion.tween_property(tray,"position:z",.85 if opened else 0.0,.28).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	for bag in bags:
		bag.collision_layer=1 if opened else 0
