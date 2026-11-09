extends "res://scripts/board_components_3d.gd"
const Substrate = preload("res://scripts/pcb_design/substrate.gd")
## Inherits all existing device IDs, live state and renderer adapters.
func build_packages(game: Node,canvas: Control) -> void:
 for layer in package_layers(canvas):
  if preload("res://scripts/pcb_design/design.gd").active(layer.bp):
   Substrate.build(self,canvas,layer.bp,layer.rect,float(layer.base),float(layer.height));continue
  var bp: Dictionary=layer.bp;var rect: Rect2=layer.rect;var center := board_point(rect.get_center(),.015+float(layer.base))
  var size := Vector3(rect.size.x/1000.*1.88,float(layer.height),rect.size.y/440.*.78)
  if size.y>0:
   var standalone: bool=canvas.board.get("standalone",false) and bp.get("package","")=="PCB"
   game._box(self,center+Vector3(0,size.y*.5,0),size,Color("a59160") if standalone else Color(str(bp.footprint.get("color","303b40"))))
   # Lift the live canvas texture with the substrate, including genuine displays.
   var face := MeshInstance3D.new();var plane := PlaneMesh.new();plane.size=Vector2(size.x,size.z);face.mesh=plane
   face.position=center+Vector3(0,size.y+.0005,0)
   var mat := Substrate.surface_material(canvas.get_viewport().get_texture(),standalone)
   mat.uv1_scale=Vector3(rect.size.x/1000.,rect.size.y/440.,1);mat.uv1_offset=Vector3(rect.position.x/1000.,rect.position.y/440.,0)
   face.material_override=mat;add_child(face)
  var top := .017+float(layer.base)+size.y
  var marking := str(bp.get("marking",""))
  if not marking.is_empty():label(marking,board_point(rect.position+Vector2(rect.size.x*.5,24),top),.011)
  var marker := str(bp.get("orientation_marker","dot"))
  # Absent metadata preserves the legacy flat canvas; explicit marker opts in.
  if bp.has("orientation_marker") and marker!="none":
   var point := board_point(rect.position+Vector2(10,10),top)
   if marker=="dot":game._cylinder(self,point,.004,.001,Color("e4dab3"))
   elif marker=="notch":game._box(self,point,Vector3(.018,.002,.005),Color("d5c69b"))
   else:
    game._line(self,point+Vector3(-.005,0,.005),point+Vector3(0,0,-.005),.001,Color("e4dab3"))
    game._line(self,point+Vector3(0,0,-.005),point+Vector3(.005,0,.005),.001,Color("e4dab3"))
    game._line(self,point+Vector3(.005,0,.005),point+Vector3(-.005,0,.005),.001,Color("e4dab3"))

