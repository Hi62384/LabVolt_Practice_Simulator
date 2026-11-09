extends Control
## Drop-in math branch for paper_ui; all legacy paper paths stay in worksheet_page.
const Adapter = preload("res://scripts/math_ui/paper_adapter.gd")
const View = preload("res://scripts/math_ui/expression_view.gd")
signal answer_changed(key: String,value: String)
signal stroke_added(stroke: Dictionary)
var paper: Dictionary={}
var page:=0
var writable:=false
var ink: Control
var body: VBoxContainer
var workspace: Control
const PAPER_SIZE=Vector2(780,1100)
var parser: Callable
var parser_owner: RefCounted

func _ready() -> void:
	custom_minimum_size=PAPER_SIZE;size=PAPER_SIZE
	var background:=Panel.new();background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);background.mouse_filter=Control.MOUSE_FILTER_IGNORE
	var style:=StyleBoxFlat.new();style.bg_color=Color("fcfaf2");background.add_theme_stylebox_override("panel",style);add_child(background)
	var margin:=MarginContainer.new();margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for edge in ["left","right"]:margin.add_theme_constant_override("margin_"+edge,40)
	for edge in ["top","bottom"]:margin.add_theme_constant_override("margin_"+edge,30)
	add_child(margin)
	body=VBoxContainer.new();body.add_theme_constant_override("separation",12);margin.add_child(body)
	body.minimum_size_changed.connect(func():_resize.call_deferred())
	var page_theme:=Theme.new();page_theme.default_font_size=17
	for type in ["Label","LineEdit","OptionButton","Button"]:page_theme.set_color("font_color",type,Color("263743"))
	for type in ["LineEdit","OptionButton","Button"]:
		for state in ["normal","hover","pressed","focus","disabled"]:
			var box:=StyleBoxFlat.new();box.bg_color=Color("dceaf0") if state in ["hover","pressed"] else Color("eef3f4");box.border_color=Color("83a3b2");box.set_border_width_all(1);box.set_corner_radius_all(4);box.set_content_margin_all(7);page_theme.set_stylebox(state,type,box)
		for state in ["font_color","font_hover_color","font_pressed_color","font_focus_color","font_uneditable_color"]:page_theme.set_color(state,type,Color("263743"))
		page_theme.set_color("font_placeholder_color",type,Color("647980"))
	page_theme.set_color("caret_color","LineEdit",Color("263743"))
	theme=page_theme
	# Shared parser is loaded only when integrated; this lane supplies no duplicate parser.
	if ResourceLoader.exists("res://scripts/mth147/parser.gd"):
		parser_owner=load("res://scripts/mth147/parser.gd").new()
		parser=Callable(parser_owner,"parse")
	var project:Dictionary=paper.get("project",{})
	var questions:Array=project.get("questions",project.get("problems",[]))
	_text(str(project.get("course_id","MATHEMATICS"))+" · "+str(project.get("title","Mathematics worksheet")),26)
	_text(str(paper.get("owner_name","Student"))+" · "+("Practice" if paper.get("lesson",false) else "Assessment"),15)
	if page==0:
		_text("MATHEMATICS · LECTURE / STUDY",20)
		_text(str(project.get("description",project.get("theory","Complete each question using the notation keyboard or coordinate tools. Your written working remains on the paper."))))
		_text("%d questions · answers and graph coordinates are saved with this paper. Use the page arrows to continue."%questions.size())
	elif page<=questions.size():
		var index:=page-1
		var problem:Dictionary=questions[index]
		_text("Question %d of %d"%[page,questions.size()],18)
		workspace=Adapter.mount(body,problem,paper.get("math_ui",{}).get(str(index),{}),writable,paper.get("math_policy",{"formula_allowed":false}),parser,func(_id,_answer,envelope):answer_changed.emit(str(index),envelope))
		workspace.page=page
		if paper.get("math_ui",{}).get(str(index),{}).is_empty() and paper.get("answers",{}).has(str(index)):
			_seed_answer(workspace,paper.answers[str(index)])
	else:
		var mark:Dictionary=paper.get("mark",{})
		if mark.is_empty():_text("Submit your paper to receive marked work and explanations.",21)
		else:
			_text("%.1f%%"%float(mark.get("score",0)),32)
			for feedback in mark.get("feedback",[]):
				_text(str(feedback.get("prompt","Question"))+" · "+str(feedback.get("reason",feedback.get("explanation",""))))
				if feedback.has("earned"):_text("Marks: %s / %s"%[feedback.earned,feedback.get("total","?")])
				if feedback.has("expected"):_solution(feedback.expected)
				for step in feedback.get("steps",[]):
					if step is Dictionary:
						_text(str(step.get("text","")))
						if step.get("math") is Dictionary:_solution(step.math)
					else:_text(str(step))
	_text("MATH / LABVOLT · %d / %d"%[page+1,questions.size()+2],12)
	ink=preload("res://scripts/paper_ink.gd").new();ink.background=false;ink.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);ink.editable=writable;ink.strokes=paper.get("strokes",{}).get(str(page),[]).duplicate(true);ink.stroke_finished.connect(func(stroke):stroke_added.emit(stroke));add_child(ink);set_drawing(false)
	_resize.call_deferred()

func _text(value: String,fs: int=17) -> void:
	var label:=Label.new();label.text=value;label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;label.add_theme_font_size_override("font_size",fs);body.add_child(label)

func _solution(value: Variant) -> void:
	var ast:Dictionary={}
	if value is Dictionary and value.has("op"):ast=value
	elif (value is String or value is int or value is float) and parser.is_valid():
		var parsed:Dictionary=parser.call(str(value))
		if parsed.get("ok",false):ast=parsed.ast
	if not ast.is_empty():
		var view:=View.new();body.add_child(view);view.set_expression(ast)
	elif value is Dictionary:
		for key in value:_text(str(key)+":");_solution(value[key])
	elif value is Array:
		for item in value:_solution(item)
	else:_text(str(value))

func _seed_answer(widget: Control, answer_value: Variant) -> void:
	# Compatibility with a persisted structured answer before widget-state migration.
	if answer_value is Dictionary:
		for key in answer_value:
			if widget.fields.has(key):widget.fields[key].set_value(answer_value[key])
	elif widget.fields.has("answer"):widget.fields.answer.set_value(answer_value)

func _resize() -> void:
	if not is_instance_valid(body):return
	var height:=maxf(PAPER_SIZE.y,body.get_combined_minimum_size().y+70)
	custom_minimum_size.y=height;size.y=height

func set_drawing(enabled: bool) -> void:
	if is_instance_valid(ink):ink.mouse_filter=Control.MOUSE_FILTER_STOP if enabled and ink.editable else Control.MOUSE_FILTER_IGNORE

func fit_preview(viewport: SubViewport) -> void:
	# Called by the physical paper display after mounting this last-viewed page.
	await get_tree().process_frame
	await get_tree().process_frame
	_resize()
	var factor:=minf(float(viewport.size.x)/maxf(1,size.x),float(viewport.size.y)/maxf(1,size.y))
	scale=Vector2.ONE*factor
	position.x=(viewport.size.x-size.x*factor)/2
	viewport.render_target_update_mode=SubViewport.UPDATE_ONCE
