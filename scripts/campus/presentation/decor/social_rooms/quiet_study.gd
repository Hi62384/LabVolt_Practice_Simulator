extends Node3D
var seat_anchors:={}
var mats:={}
func build(campus: Node3D) -> bool:
 var room: Dictionary=campus.registry.get_room("study")
 if room.is_empty():return false
 position=campus.registry.vector(room.center)
 # Durable tile and a restrained two-tone finish keep the room simple.
 var tiles: Array=[]
 for x in range(10):
  for z in range(8):tiles.append(Vector3(-4.5+x,.014,-3.5+z))
 preload("res://scripts/campus/performance/lit_tile_batches.gd").build(self,tiles,Vector3(.982,.012,.982),_material("8492a0"))
 for z in [-3.91,3.91]:
  _box(self,Vector3(0,.62,z),Vector3(9.8,1.20,.025),"4e697e")
  _box(self,Vector3(0,1.23,z),Vector3(9.8,.045,.04),"b6aa97")
  _box(self,Vector3(0,.08,z),Vector3(9.8,.15,.045),"314757")
 _box(self,Vector3(-4.91,.62,0),Vector3(.025,1.20,7.8),"4e697e")
 _box(self,Vector3(-4.91,1.23,0),Vector3(.04,.045,7.8),"b6aa97")
 _box(self,Vector3(-4.91,.08,0),Vector3(.045,.15,7.8),"314757")
 for index in 2:
  var at:=Vector3(-2.1+index*4.2,0,0)
  var table:=_body(at+Vector3(0,.73,0),Vector3(2.05,.10,1.25),"eef0ec","table")
  table.set_meta("label","Study table")
  for x in [-.86,.86]:
   for z in [-.50,.50]:_box(table,Vector3(x,-.35,z),Vector3(.055,.70,.055),"677982")
  var chairs: Array=[Vector3(0,0,-1.12),Vector3(0,0,1.12),Vector3(-1.43,0,0),Vector3(1.43,0,0)]
  for n in chairs.size():
   var spot: Vector3=at+chairs[n]
   var yaw:=PI if n==0 else 0.0 if n==1 else -PI/2 if n==2 else PI/2
   var game: Node=campus.get_parent()
   game._add_chair(position+spot,yaw)
   var chair: Node3D=game.chairs.back()
   chair.name="StudyRollingChair_%02d" % (index*4+n)
 if not campus.register_content("study",self):return false
 for child in get_children():
  if child is StaticBody3D:
   child.collision_layer=1 if visible else 0
   campus.zone_activation_changed.connect(func(id: String,active: bool):
    if id=="study" and is_instance_valid(child):child.collision_layer=1 if active else 0)
 return true
func _material(color: String) -> StandardMaterial3D:
 if not mats.has(color):
  var mat:=StandardMaterial3D.new();mat.albedo_color=Color(color);mat.roughness=.58;mats[color]=mat
 return mats[color]
func _box(parent: Node3D,pos: Vector3,size: Vector3,color: String) -> void:
 var mesh:=BoxMesh.new();mesh.size=size
 var node:=MeshInstance3D.new();node.position=pos;node.mesh=mesh;node.material_override=_material(color);parent.add_child(node)
func _body(pos: Vector3,size: Vector3,color: String,role: String) -> StaticBody3D:
 var body:=StaticBody3D.new();body.position=pos;body.collision_mask=0;body.set_meta("role",role);add_child(body)
 var hit:=CollisionShape3D.new();var shape:=BoxShape3D.new();shape.size=size;hit.shape=shape;body.add_child(hit)
 _box(body,Vector3.ZERO,size,color)
 return body
