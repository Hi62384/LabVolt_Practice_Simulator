extends Node3D
## Physical classroom screen, populated only from the currently released stage.
var viewport: SubViewport
var surface: MeshInstance3D
var column: VBoxContainer
var signature := ""
func _ready() -> void:
 viewport=SubViewport.new();viewport.size=Vector2i(1400,600);viewport.render_target_update_mode=SubViewport.UPDATE_DISABLED;add_child(viewport)
 var background:=ColorRect.new();background.color=Color("112431");background.size=Vector2(1400,600);viewport.add_child(background)
 var margin:=MarginContainer.new();margin.position=Vector2(26,18);margin.size=Vector2(1348,564)
 viewport.add_child(margin);column=VBoxContainer.new();column.add_theme_constant_override("separation",10);margin.add_child(column)
 surface=MeshInstance3D.new();var quad:=QuadMesh.new();quad.size=Vector2(5.55,2.38);surface.mesh=quad
 var material:=StandardMaterial3D.new();material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED;material.albedo_texture=viewport.get_texture();material.cull_mode=BaseMaterial3D.CULL_DISABLED
 surface.material_override=material;add_child(surface)
func text(value: String,fs: int,parent: Node) -> void:
 var label:=Label.new();label.text=value;label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;label.add_theme_font_size_override("font_size",fs);label.add_theme_color_override("font_color",Color("e7f2fa"));parent.add_child(label)
func show_stage(course: String,stage: Dictionary) -> void:
 visible=true
 var key:=JSON.stringify(stage)
 if key==signature:return
 signature=key
 for child in column.get_children():column.remove_child(child);child.queue_free()
 text(course+"  ·  "+str(stage.get("title","Mathematics")),30,column)
 var row:=HBoxContainer.new();row.size_flags_vertical=Control.SIZE_EXPAND_FILL;row.add_theme_constant_override("separation",24);column.add_child(row)
 var explanation:=VBoxContainer.new();explanation.size_flags_horizontal=Control.SIZE_EXPAND_FILL;row.add_child(explanation)
 text(str(stage.get("text",stage.get("caption",""))),23,explanation)
 var problem:Dictionary=stage.get("problem",{})
 var notation: Variant=stage.get("math",problem.get("ast",{}))
 var ast: Dictionary={}
 if notation is Dictionary:ast=notation
 elif notation is String and not notation.is_empty():
  var parsed: Dictionary=preload("res://scripts/mth147/math_core.gd").parse(notation)
  if parsed.get("ok",false):ast=parsed.ast
  else:text(notation,25,explanation)
 if not ast.is_empty():
  var expression=preload("res://scripts/math_ui/expression_view.gd").new();explanation.add_child(expression);expression.set_expression(ast)
 var raw_diagram: Variant=stage.get("diagram",problem.get("diagram",{}))
 var diagram: Dictionary=raw_diagram if raw_diagram is Dictionary else {}
 if not diagram.is_empty():
  var view=load("res://scripts/mth255/impedance_view.gd").new() if diagram.get("kind","")=="circuit" and ResourceLoader.exists("res://scripts/mth255/impedance_view.gd") else preload("res://scripts/math_ui/diagram_view.gd").new();view.custom_minimum_size=Vector2(650,400);row.add_child(view);view.configure(diagram)
 viewport.render_target_update_mode=SubViewport.UPDATE_ONCE
