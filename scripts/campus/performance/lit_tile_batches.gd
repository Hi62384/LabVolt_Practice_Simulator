extends RefCounted
## Keep tile batches small enough for local lights and frustum culling in Compatibility.
static func build(parent: Node3D,points: Array,size: Vector3,material: Material,cell_size := 5.0) -> Array:
 var sections:={}
 for point in points:
  var key:=Vector2i(floori(point.x/cell_size),floori(point.z/cell_size))
  if not sections.has(key):sections[key]=[]
  sections[key].append(point)
 var tile:=BoxMesh.new();tile.size=size
 var result:=[]
 for key in sections:
  var group: Array=sections[key]
  var center: Vector3=group[0]
  var batch:=MultiMesh.new();batch.transform_format=MultiMesh.TRANSFORM_3D;batch.mesh=tile;batch.instance_count=group.size()
  for i in group.size():batch.set_instance_transform(i,Transform3D(Basis.IDENTITY,group[i]-center))
  var node:=MultiMeshInstance3D.new();node.position=center;node.multimesh=batch;node.material_override=material
  node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;parent.add_child(node);result.append(node)
 return result
