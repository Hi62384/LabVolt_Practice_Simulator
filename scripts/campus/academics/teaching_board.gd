extends Node3D
## Read-only, event-driven presentation of the host-released teaching stage.
## The caller owns room visibility, phase, authority and student assessment state.
const ExpressionView = preload("res://scripts/math_ui/expression_view.gd")
const Graph = preload("res://scripts/math_ui/graph_canvas.gd")
const Diagram = preload("res://scripts/math_ui/diagram_view.gd")
const Table = preload("res://scripts/math_ui/table_editor.gd")
const Netlist = preload("res://scripts/campus/courses/course_diagram.gd")
const W := 1600
const H := 700
var viewport: SubViewport
var surface: MeshInstance3D
var column: VBoxContainer
var signature := ""
var active := false
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
	_label(_limited(course,36)+"  ·  "+_limited(heading,90),39,column,Color("8dddeb"))
	_label(_limited(status,180),26,column,Color("b9cbd5"))
	if phase == "lesson":_lesson(stage)
	else:_label(_limited(str(stage.get("text","")),1200),33,column)
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE

func _lesson(stage: Dictionary) -> void:
	_label("%d / %d  ·  %s"%[int(stage.get("index",0))+1,maxi(1,int(stage.get("count",1))),_limited(str(stage.get("title","Lesson")),100)],34,column,Color("ffd198"))
	var row := HBoxContainer.new()
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation",28)
	column.add_child(row)
	var words := VBoxContainer.new()
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	words.size_flags_stretch_ratio = 1.1
	words.add_theme_constant_override("separation",15)
	row.add_child(words)
	_label(_limited(str(stage.get("text",stage.get("caption",""))),1300),30,words)
	for field in ["formulas","worked"]:
		if not str(stage.get(field,"")).is_empty():_label(_limited(str(stage[field]),430),29,words,Color("e9d49e"))
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
		else:_label(_limited(notation,240),29,words)
	var visual: Variant = stage.get("diagram",problem.get("diagram",{}))
	if visual is Dictionary and not visual.is_empty():_visual(row,visual)
	var steps: Variant = stage.get("steps",[])
	if steps is Array:
		for item in steps.slice(0,4):
			if item is Dictionary:_label("• "+_limited(str(item.get("text","")),260),25,words)
			elif item is String:_label("• "+_limited(item,260),25,words)

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
