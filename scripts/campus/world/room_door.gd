extends StaticBody3D

var opened := false
var hinges: Array[Node3D] = []
var swing := 1.0
var motion: Tween

func build(width: float, west: bool, frame: Material, glass: Material) -> void:
	collision_layer=4
	collision_mask=0
	set_meta("role","campus_door")
	set_meta("label","Open / close door")
	swing=1.0 if west else -1.0
	for side in [-1.0,1.0]:
		var hinge := Node3D.new()
		hinge.position=Vector3(0,0,side*width*.5)
		add_child(hinge)
		hinges.append(hinge)
		var leaf := StaticBody3D.new()
		leaf.position=Vector3(0,1.47,-side*width*.25)
		leaf.collision_layer=5
		leaf.collision_mask=0
		leaf.set_meta("role","campus_door")
		leaf.set_meta("label","Open / close door")
		leaf.set_script(preload("res://scripts/campus/world/room_door_leaf.gd"))
		leaf.door=self
		hinge.add_child(leaf)
		var shape := BoxShape3D.new()
		shape.size=Vector3(.1,2.94,width*.5-.02)
		var collision := CollisionShape3D.new()
		collision.shape=shape
		leaf.add_child(collision)
		# Solid rails frame a genuine translucent window, with hardware on both faces.
		var leaf_width := width*.5-.02
		var metal := StandardMaterial3D.new()
		metal.albedo_color=Color("a8b9bd");metal.metallic=.7;metal.roughness=.32
		var window_mat := StandardMaterial3D.new()
		window_mat.albedo_color=Color(.44,.67,.72,.28)
		window_mat.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
		window_mat.roughness=.22;window_mat.cull_mode=BaseMaterial3D.CULL_DISABLED
		_door_part(leaf,Vector3(0,-.92,0),Vector3(.1,1.10,leaf_width),frame)
		_door_part(leaf,Vector3(0,1.26,0),Vector3(.1,.42,leaf_width),frame)
		for edge in [-1.0,1.0]:
			_door_part(leaf,Vector3(0,.34,edge*(leaf_width*.5-.065)),Vector3(.1,1.52,.13),frame)
		_door_part(leaf,Vector3(0,.34,0),Vector3(.025,1.52,leaf_width-.24),window_mat)
		for face in [-1.0,1.0]:
			_door_part(leaf,Vector3(face*.065,-1.20,0),Vector3(.025,.22,leaf_width-.12),metal)
			_door_part(leaf,Vector3(face*.105,-.30,-side*(leaf_width*.5-.19)),Vector3(.08,.39,.045),metal)

func _door_part(parent: Node3D, at: Vector3, size: Vector3, material: Material) -> void:
	var part := MeshInstance3D.new()
	var cube := BoxMesh.new();cube.size=size
	part.mesh=cube;part.material_override=material;part.position=at
	part.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(part)

func request_toggle() -> void:
	if multiplayer.multiplayer_peer == null:
		_set_open(not opened)
	elif multiplayer.is_server():
		_set_open(not opened)
		_sync.rpc(opened)
	else:
		_request.rpc_id(1)

@rpc("any_peer", "call_remote", "reliable")
func _request() -> void:
	if not multiplayer.is_server(): return
	_set_open(not opened)
	_sync.rpc(opened)

@rpc("authority", "call_remote", "reliable")
func _sync(value: bool) -> void:
	_set_open(value)

func _set_open(value: bool) -> void:
	opened=value
	if is_instance_valid(motion): motion.kill()
	motion=create_tween().set_parallel(true).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	for i in range(hinges.size()):
		var target: float = (1.0 if i==0 else -1.0)*swing*PI*.5 if value else 0.0
		motion.tween_property(hinges[i],"rotation:y",target,.65)
