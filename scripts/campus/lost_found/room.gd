extends Node3D
## Practical counter and shelving for M109; all solid fixtures block movement.
var materials:={}
func build(game: Node) -> void:
 var room: Dictionary=game.campus.registry.get_room("lost_found")
 if room.is_empty():return
 var root:=Node3D.new();root.name="LostAndFoundFurnishings";game.campus.add_child(root)
 var tiles: Array=[]
 for x in range(20):
  for z in range(8):tiles.append(Vector3(-9.5+x,.012,60.5+z))
 preload("res://scripts/campus/performance/lit_tile_batches.gd").build(root,tiles,Vector3(.984,.012,.984),_mat("829097"))
 for z in [60.14,67.86]:
  _box(root,Vector3(0,.65,z),Vector3(19.7,1.25,.03),"4b6773")
  _box(root,Vector3(0,1.3,z),Vector3(19.7,.04,.05),"c4b59a")
  _box(root,Vector3(0,2.65,z),Vector3(19.7,2.65,.025),"e1e3df")
 _box(root,Vector3(-9.88,2,64),Vector3(.03,3.95,7.7),"53747a")
 # Shelving has a solid back and solid shelves; the center aisle stays clear.
 _solid(root,Vector3(-9.30,1.03,64),Vector3(.62,2.06,6.2),"35545c")
 for y in [.30,.77,1.24,1.71,2.08]:_box(root,Vector3(-8.91,y,64),Vector3(.24,.055,6.15),"c0aa88")
 for z in [61.3,62.55,63.8,65.05,66.3]:
  for y in [.49,.96,1.43]:
   _solid(root,Vector3(-8.91,y,z),Vector3(.27,.27,.75),"789198" if int(y*100)%2 else "b49470")
   _box(root,Vector3(-8.76,y,z),Vector3(.018,.065,.19),"e2d6b9")
 # Two low display tables hold recovered items within easy reach.
 for z in [62.35,65.65]:
  _solid(root,Vector3(-3.2,.42,z),Vector3(7.45,.76,1.0),"56747a")
  _box(root,Vector3(-3.2,.81,z),Vector3(7.5,.06,1.05),"c5ac87")
 # Low counters are deliberately outside the central path and have collisions.
 for z in [60.65,67.35]:
  _solid(root,Vector3(1.2,.47,z),Vector3(3.5,.94,.70),"56747a")
  _box(root,Vector3(1.2,.96,z),Vector3(3.65,.065,.78),"c5ac87")
  for x in [-.1,1.0,2.1]:_box(root,Vector3(x,.55,z+(.36 if z<64 else -.36)),Vector3(.80,.45,.025),"789397")
 _box(root,Vector3(-2,.025,64),Vector3(4,.015,2.2),"59797a")
 game.campus.register_content("lost_found",root)
 for child in root.get_children():
  if child is StaticBody3D:
   child.collision_layer=1 if root.visible else 0
   game.campus.zone_activation_changed.connect(func(id: String,active: bool):
    if id=="lost_found" and is_instance_valid(child):child.collision_layer=1 if active else 0)
func _mat(hex: String) -> StandardMaterial3D:
 if not materials.has(hex):
  var material:=StandardMaterial3D.new();material.albedo_color=Color(hex);material.roughness=.83;materials[hex]=material
 return materials[hex]
func _box(parent: Node3D,position: Vector3,size: Vector3,color: String) -> MeshInstance3D:
 var mesh:=BoxMesh.new();mesh.size=size
 var instance:=MeshInstance3D.new();instance.mesh=mesh;instance.position=position;instance.material_override=_mat(color);parent.add_child(instance)
 return instance
func _solid(parent: Node3D,position: Vector3,size: Vector3,color: String) -> void:
 var body:=StaticBody3D.new();body.position=position;body.collision_layer=1;body.collision_mask=0;parent.add_child(body)
 var hit:=CollisionShape3D.new();var shape:=BoxShape3D.new();shape.size=size;hit.shape=shape;body.add_child(hit)
 _box(body,Vector3.ZERO,size,color)
