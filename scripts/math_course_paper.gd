extends "res://scripts/math_ui/math_paper_page.gd"
## Guided papers teach first, then present a short practice section and feedback.
func _ready() -> void:
 var stages: Array=paper.get("project",{}).get("lesson_stages",[])
 if not paper.get("lesson",false) or stages.is_empty():
  super._ready();return
 if page>=stages.size():
  var original_page:=page;page=page-stages.size()+1
  super._ready();page=original_page
  ink.strokes=paper.get("strokes",{}).get(str(page),[]).duplicate(true)
  if is_instance_valid(workspace):workspace.page=page
  return
 custom_minimum_size=PAPER_SIZE;size=PAPER_SIZE
 var background:=Panel.new();background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);background.mouse_filter=Control.MOUSE_FILTER_IGNORE
 var style:=StyleBoxFlat.new();style.bg_color=Color("fcfaf2");background.add_theme_stylebox_override("panel",style);add_child(background)
 var margin:=MarginContainer.new();margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
 for edge in ["left","right"]:margin.add_theme_constant_override("margin_"+edge,40)
 for edge in ["top","bottom"]:margin.add_theme_constant_override("margin_"+edge,30)
 add_child(margin);body=VBoxContainer.new();body.add_theme_constant_override("separation",18);margin.add_child(body)
 var skin:=Theme.new();skin.default_font_size=19;skin.set_color("font_color","Label",Color("263743"));theme=skin
 body.minimum_size_changed.connect(func():_resize.call_deferred())
 parser_owner=preload("res://scripts/mth147/parser.gd").new();parser=Callable(parser_owner,"parse")
 var stage: Dictionary=stages[page]
 _text(str(paper.project.get("course_id","MATHEMATICS"))+" / GUIDED LESSON",18)
 _text(str(paper.project.get("title","Mathematics")),28)
 _text(str(stage.get("title","Learning step")),23)
 _text(str(stage.get("text",stage.get("caption",""))),20)
 var problem: Dictionary=stage.get("problem",{})
 if not problem.is_empty() and str(problem.get("prompt",""))!=str(stage.get("text","")):_text(str(problem.get("prompt","")),19)
 var notation: Variant=stage.get("math",problem.get("ast",{}))
 if notation is Dictionary and not notation.is_empty() or notation is String and not notation.is_empty():_solution(notation)
 var descriptor: Variant=stage.get("diagram",problem.get("diagram",{}))
 if descriptor is Dictionary and not descriptor.is_empty():
  var view=load("res://scripts/mth255/impedance_view.gd").new() if descriptor.get("kind","")=="circuit" and ResourceLoader.exists("res://scripts/mth255/impedance_view.gd") else preload("res://scripts/math_ui/diagram_view.gd").new()
  body.add_child(view);view.configure(descriptor)
 _text("Teaching %d / %d · Practice questions follow the lesson."%[page+1,stages.size()],13)
 ink=preload("res://scripts/paper_ink.gd").new();ink.background=false;ink.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);ink.editable=writable
 ink.strokes=paper.get("strokes",{}).get(str(page),[]).duplicate(true);ink.stroke_finished.connect(func(stroke):stroke_added.emit(stroke));add_child(ink);set_drawing(false)
 _resize.call_deferred()
