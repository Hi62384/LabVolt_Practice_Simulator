extends Node3D
## Read-only, event-driven presentation of the host-released teaching stage.
## The caller owns room visibility, phase, authority and student assessment state.
const ExpressionView = preload("res://scripts/math_ui/expression_view.gd")
const Graph = preload("res://scripts/math_ui/graph_canvas.gd")
const Diagram = preload("res://scripts/math_ui/diagram_view.gd")
const Table = preload("res://scripts/math_ui/table_editor.gd")
const Netlist = preload("res://scripts/campus/courses/course_diagram.gd")
const MotionCanvas=preload("res://scripts/procedural_animation/canvas.gd")
const W := 1600
const H := 700
var viewport: SubViewport
var surface: MeshInstance3D
var column: VBoxContainer
var signature := ""
var active := false
var event_mode := false
var animation_canvas: Control
var illustration: Control
var lesson_row: HBoxContainer
var lesson_words: VBoxContainer
signal diagram_action_requested(action: String, data: Dictionary)

func _ready() -> void:
	viewport = SubViewport.new()
	viewport.size = Vector2i(W,H)
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(viewport)
	var background := ColorRect.new()
	background.color = Color("112431")
	background.size = Vector2(W,H)
	viewport.add_child(background)
	var margin := MarginContainer.new()
	margin.position = Vector2(42,28)
	margin.size = Vector2(W-84,H-56)
	viewport.add_child(margin)
	column = VBoxContainer.new()
	column.add_theme_constant_override("separation",14)
	margin.add_child(column)
	surface = MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(5.55,2.43)
	surface.mesh = quad
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_texture = viewport.get_texture()
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	surface.material_override = material
	add_child(surface)

func set_room_active(value: bool) -> void:
	active = value
	visible = value
	if not value:
		viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		signature = ""
		if is_instance_valid(animation_canvas):animation_canvas.hide()

func show_public_content(content: Dictionary) -> void:
	# Adapter entry point for a classroom display such as M203. The caller must
	# supply only the host-released stage; student desktop/file state is excluded.
	var stage: Dictionary = content.get("stage",{}) if content.get("stage",{}) is Dictionary else {}
	show_content(str(content.get("course_id","")),str(content.get("phase","")),str(content.get("heading","")),stage,str(content.get("status","")))

func show_content(course: String, phase: String, heading: String, stage: Dictionary, status: String) -> void:
	if not active:return
	# A change in the released stage or phase is the only reason to redraw.
	var key := JSON.stringify([course,phase,heading,stage,status])
	if key == signature:return
	signature = key
	for child in column.get_children():
		column.remove_child(child)
		child.queue_free()
	animation_canvas=null
	illustration=null
	_label(_limited(course,36)+"  ·  "+_limited(heading,90),50 if event_mode else 52,column,Color("8dddeb"))
	_label(_limited(status,180),36 if event_mode else 40,column,Color("b9cbd5"))
	if phase == "lesson":_lesson(stage)
	else:_label(_limited(str(stage.get("text","")),1200),33,column)
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE

func _lesson(stage: Dictionary) -> void:
	_label("%d / %d  ·  %s"%[int(stage.get("index",0))+1,maxi(1,int(stage.get("count",1))),_limited(str(stage.get("title","Lesson")),100)],46 if event_mode else 54,column,Color("ffd198"))
	var history: Variant=stage.get("board_history",[])
	if event_mode and history is Array and not history.is_empty():
		var trail:=VBoxContainer.new();trail.add_theme_constant_override("separation",4);column.add_child(trail)
		for entry in history.slice(maxi(0,history.size()-2),history.size()):
			if not entry is Dictionary:continue
			var note:=str(entry.get("title",""))
			if not str(entry.get("formula","")).is_empty():note+=" · "+str(entry.formula)
			_label(_limited(note,62),40,trail,Color("b6d5dd"))
	var row := HBoxContainer.new()
	lesson_row=row
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation",28)
	column.add_child(row)
	var words := VBoxContainer.new()
	lesson_words=words
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	words.size_flags_stretch_ratio = 1.1
	words.add_theme_constant_override("separation",15)
	row.add_child(words)
	var summary := str(stage.get("text",stage.get("caption",""))).strip_edges()
	if event_mode:
		_label(_limited(summary,1300),50,words)
		for field in ["formulas","worked"]:
			if not str(stage.get(field,"")).is_empty(): _label(_limited(str(stage[field]),430),29,words,Color("e9d49e"))
	else:
		var worked := str(stage.get("worked","")).strip_edges()
		var source := worked if not worked.is_empty() else summary
		var sentences := source.split(". ",false)
		var lines := mini(2, sentences.size())
		for index in lines:
			var line := str(sentences[index]).strip_edges()
			if index < sentences.size() - 1 and not line.ends_with("."): line += "."
			_label(_limited(line,125),48,words,Color("e9d49e") if not worked.is_empty() else Color("e7f2fa"))
		var formula := str(stage.get("formulas","")).strip_edges()
		if worked.is_empty() and not formula.is_empty() and not formula.begins_with(str(sentences[0]) if not sentences.is_empty() else summary):
			_label(_limited(formula.get_slice(". ",0),100),43,words,Color("e9d49e"))
	var problem: Dictionary = stage.get("problem",{}) if stage.get("problem",{}) is Dictionary else {}
	var notation: Variant = stage.get("math",problem.get("ast",{}))
	if notation is Dictionary and not notation.is_empty():
		var expression := ExpressionView.new()
		words.add_child(expression)
		expression.set_expression(notation)
	elif notation is String and not notation.is_empty():
		var parsed: Dictionary = preload("res://scripts/mth147/math_core.gd").parse(notation)
		if parsed.get("ok",false):
			var expression := ExpressionView.new()
			words.add_child(expression)
			expression.set_expression(parsed.ast)
		else:_label(_limited(notation,180 if not event_mode else 240),48 if not event_mode else 29,words)
	var visual: Variant = stage.get("diagram",problem.get("diagram",{}))
	if visual is Dictionary and not visual.is_empty():
		illustration=VBoxContainer.new()
		row.add_child(illustration)
		_visual(illustration,visual)
	if not event_mode:
		animation_canvas=MotionCanvas.new()
		animation_canvas.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		animation_canvas.size_flags_stretch_ratio=1.6
		animation_canvas.custom_minimum_size=Vector2(720,1)
		animation_canvas.hide()
		row.add_child(animation_canvas)
		animation_canvas.frame_changed.connect(func():
			if active and is_instance_valid(animation_canvas):viewport.render_target_update_mode=SubViewport.UPDATE_ONCE)
	var steps: Variant = stage.get("steps",[])
	if steps is Array:
		for item in steps.slice(0,2 if not event_mode else 4):
			if item is Dictionary:_label("• "+_limited(str(item.get("text","")),85 if not event_mode else 260),40 if not event_mode else 25,words)
			elif item is String:_label("• "+_limited(item,85 if not event_mode else 260),40 if not event_mode else 25,words)

func show_animation(key: String,state: Dictionary) -> void:
	if not active or not is_instance_valid(animation_canvas):return
	var show_canvas: bool=not state.is_empty() and animation_canvas.show_checkpoint(key,state)
	animation_canvas.visible=show_canvas
	if is_instance_valid(illustration):illustration.visible=not show_canvas
	var layout: String=animation_canvas.player.scene.get("layout","right") if show_canvas else "right"
	lesson_words.visible=layout!="full"
	for item in column.get_children():
		if item!=lesson_row:item.visible=layout!="full"
	lesson_row.move_child(animation_canvas,0 if layout=="left" else lesson_row.get_child_count()-1)
	viewport.render_target_update_mode=SubViewport.UPDATE_ONCE

func _visual(parent: Node, data: Dictionary) -> void:
	data = _bounded_diagram(data)
	var kind := str(data.get("kind",data.get("type","")))
	if kind in ["graph","complex_plane","unit_circle"]:
		var graph := Graph.new()
		graph.custom_minimum_size = Vector2(700,430)
		parent.add_child(graph)
		graph.configure(data,false)
	elif kind in ["triangle","probability","circuit"]:
		var diagram := Diagram.new()
		diagram.custom_minimum_size = Vector2(700,430)
		parent.add_child(diagram)
		diagram.configure(data,false)
	elif kind == "netlist":
		var circuit := Netlist.new()
		parent.add_child(circuit)
		circuit.configure(data)
	elif kind in ["statistics","table"]:
		var table := Table.new()
		table.custom_minimum_size = Vector2(700,430)
		parent.add_child(table)
		table.configure(data,false)
	elif kind == "image":
		var path := str(data.get("path",data.get("asset","")))
		# Only project resources may be displayed; no arbitrary local or remote URLs.
		if path.begins_with("res://assets/") and ResourceLoader.exists(path):
			var resource := load(path)
			if resource is Texture2D:
				var picture := TextureRect.new()
				picture.texture = resource
				picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
				picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
				picture.custom_minimum_size = Vector2(700,430)
				parent.add_child(picture)
	else:
		_label(_limited(str(data.get("caption",data.get("label",""))),160),24,parent)

func _bounded_diagram(source: Dictionary) -> Dictionary:
	var data := source.duplicate(true)
	for key in ["parts","components","rows","outcomes","vertices"]:
		if data.get(key) is Array:data[key]=data[key].slice(0,24)
	if data.get("curves") is Array:
		data.curves=data.curves.slice(0,8)
		for i in data.curves.size():
			if data.curves[i] is Dictionary and data.curves[i].get("points") is Array:
				data.curves[i].points=data.curves[i].points.slice(0,256)
	if data.get("points") is Array:data.points=data.points.slice(0,256)
	return data

func request_diagram_action(action: String, data: Dictionary) -> void:
	# Forward only explicit supported interaction requests to an authority adapter.
	if active and action in ["point","highlight","reset"]:diagram_action_requested.emit(action,data.duplicate(true))

func _label(value: String, size: int, parent: Node, color: Color=Color("e7f2fa")) -> Label:
	var label := Label.new()
	label.text = value
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size",size)
	label.add_theme_color_override("font_color",color)
	parent.add_child(label)
	return label

func _limited(value: String, length: int) -> String:
	return value.substr(0,length)+( "…" if value.length()>length else "")
