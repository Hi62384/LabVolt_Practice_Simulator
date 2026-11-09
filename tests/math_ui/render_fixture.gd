extends SceneTree
## Run graphically only under coordinator lease. Captures are file-based, no OS input.
const View = preload("res://scripts/math_ui/expression_view.gd")
const Editor = preload("res://scripts/math_ui/expression_editor.gd")
const Graph = preload("res://scripts/math_ui/graph_canvas.gd")
const Diagram = preload("res://scripts/math_ui/diagram_view.gd")
const Table = preload("res://scripts/math_ui/table_editor.gd")
var stage: VBoxContainer
var output:=""
var parser_owner: RefCounted
var parser: Callable
var capture_viewport:SubViewport
var layout_only:=false
func _initialize() -> void:call_deferred("run")
func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg=="--layout-only":layout_only=true
		if arg.begins_with("--output="):output=arg.trim_prefix("--output=")
		elif arg.begins_with("--parser="):parser_owner=load(arg.trim_prefix("--parser=")).new();parser=Callable(parser_owner,"parse")
	if not layout_only and (output.is_empty() or DisplayServer.get_name()=="headless"):push_error("Requires graphical driver and output path");quit(2);return
	if not layout_only:DirAccess.make_dir_recursive_absolute(output)
	root.size=Vector2i(1400,1000)
	capture_viewport=SubViewport.new();capture_viewport.size=Vector2i(1400,1000);capture_viewport.disable_3d=true;capture_viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(capture_viewport)
	var preview:=TextureRect.new();preview.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);preview.texture=capture_viewport.get_texture();preview.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED;root.add_child(preview)
	var background:=ColorRect.new();background.color=Color("0c1c27");background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);capture_viewport.add_child(background)
	var margin:=MarginContainer.new();margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for edge in ["left","right","top","bottom"]:margin.add_theme_constant_override("margin_"+edge,20)
	capture_viewport.add_child(margin);stage=VBoxContainer.new();margin.add_child(stage)
	var theme:=Theme.new();theme.default_font_size=18;stage.theme=theme
	get_root().get_tree().create_timer(45).timeout.connect(func():push_error("Fixture deadline");quit(3))
	await notation()
	if layout_only:print("NOTATION_LAYOUT_RESULT cards=7 bounds_assertions=14 passed=true no_capture=true");quit();return
	await graphs()
	await data_geometry()
	await paper()
	print("MATH_UI_RENDER_RESULT captures=4 graphical=true")
	quit()
func clear(title: String) -> void:
	for child in stage.get_children():stage.remove_child(child);child.queue_free()
	var label:=Label.new();label.text=title;label.add_theme_font_size_override("font_size",28);stage.add_child(label)
func label(parent: Node,text: String) -> void:
	var l:=Label.new();l.text=text;l.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;parent.add_child(l)
func expression(parent: Node,ast: Dictionary) -> void:
	var v:=View.new();parent.add_child(v);v.set_expression(ast)
func parsed(text: String) -> Dictionary:
	var result:Dictionary=parser.call(text) if parser.is_valid() else {}
	return result.ast if result.get("ok",false) else {"op":"text","value":text}
func capture(name: String) -> void:
	if layout_only:return
	for i in range(5):await process_frame
	await RenderingServer.frame_post_draw
	var img:=capture_viewport.get_texture().get_image()
	if img==null or img.is_empty():push_error("Empty capture");quit(4);return
	var error:=img.save_png(output.path_join(name+".png"))
	if error!=OK:push_error("Failed capture");quit(5);return
	print("CAPTURE "+name+" %dx%d"%[img.get_width(),img.get_height()])
func notation() -> void:
	clear("Shared mathematics notation · structured keyboard and typeset answers")
	var editor:=Editor.new();editor.configure(parser);stage.add_child(editor)
	editor.set_value(parsed("(3*x^2+sqrt(7))/(2*x-5)"))
	editor.preview.node_selected.emit([1]);editor.entry.text="2*x-5";editor.entry.text_changed.emit(editor.entry.text)
	for button in editor.get_child(0).get_children():
		if button.text=="Undo":button.pressed.emit()
	for button in editor.get_child(0).get_children():
		if button.text=="Redo":button.pressed.emit()
	assert(parser.call(editor.value()).get("ok",false),"Graphical notation callbacks must retain a valid shared AST")
	print("NATIVE_CALLBACKS node selection, text change, Undo and Redo completed")
	var grid:=GridContainer.new();grid.columns=3;grid.size_flags_horizontal=Control.SIZE_EXPAND_FILL;grid.add_theme_constant_override("h_separation",20);grid.add_theme_constant_override("v_separation",18);stage.add_child(grid)
	grid.resized.connect(func():grid.columns=clampi(int((grid.size.x+20)/380),1,3))
	for item in [["Exact radicals and rational powers","root(3,54)+sqrt(12)/sqrt(3)"],["Logarithm with a base","log(x^2+1,3)"],["Exponential and trigonometric functions","exp(-2*x)*sin(theta)"],["Nested fractions","(1/(x+2))/(3/(x-1))"]]:
		var box:=notation_card(grid,item[0]);expression(box,parsed(item[1]))
	var matrix:Dictionary={"op":"matrix","rows":[[parsed("2"),parsed("-1"),parsed("3")],[parsed("x"),parsed("sqrt(2)"),parsed("1/3")],[parsed("0"),parsed("4"),parsed("5")]]}
	var mbox:=notation_card(grid,"Matrix with exact entries");expression(mbox,matrix)
	var dbox:=notation_card(grid,"Determinant");matrix.op="determinant";expression(dbox,matrix)
	var polar_box:=notation_card(grid,"Polar form and subscript")
	expression(polar_box,{"op":"complex_polar","args":[parsed("sqrt(13)"),{"op":"subscript","args":[parsed("theta"),parsed("2")]}]})
	for i in range(5):await process_frame
	for card in grid.get_children():
		assert(card.get_global_rect().end.y<=980,"Every notation card must fit the fixed capture")
		assert(card.get_global_rect().end.x<=1380,"Notation columns must fit the capture width")
	await capture("ui_notation")
func notation_card(grid: GridContainer,title: String) -> VBoxContainer:
	var box:=VBoxContainer.new();box.custom_minimum_size.x=360;box.size_flags_horizontal=Control.SIZE_EXPAND_FILL;grid.add_child(box);label(box,title)
	return box
func plot(parent: Node,title: String,data: Dictionary) -> Control:
	var box:=VBoxContainer.new();box.size_flags_horizontal=Control.SIZE_EXPAND_FILL;parent.add_child(box);label(box,title)
	var graph:=Graph.new();graph.custom_minimum_size=Vector2(660,390);box.add_child(graph);graph.configure(data,false)
	return graph
func graphs() -> void:
	clear("Generated mathematical graphs · function data, coordinate tools and explicit units")
	var grid:=GridContainer.new();grid.columns=2;stage.add_child(grid)
	plot(grid,"Two waveforms and phasors",{"kind":"sinusoid","function":{"kind":"sin","label":"signal A","amplitude":2.3,"period":8,"phase":1,"offset":0},"curves":[{"kind":"cos","label":"signal B","amplitude":1.5,"period":8,"phase":1,"offset":0}],"domain":[-2,10],"range":[-3,3],"markers":[{"x":1,"label":"phase"},{"x":9,"label":"one period"}],"points":[{"x":3,"y":2.3,"role":"peak"},{"x":7,"y":-2.3,"role":"trough"},{"x":1,"y":0,"role":"intercept"}],"phasors":[{"magnitude":2.3,"angle":0},{"magnitude":1.5,"angle":90}],"x_label":"t (s)"})
	plot(grid,"Complex plane · Cartesian and polar grids",{"kind":"complex_plane","angle_unit":"radians","polar":true,"domain":[-4,4],"range":[-4,4],"points":[{"x":2,"y":2,"label":"z₁"},{"x":-2,"y":2,"label":"z₂"},{"x":-2,"y":-2,"label":"z₃"},{"x":2,"y":-2,"label":"z₄"}]})
	plot(grid,"Exponential growth / decay",{"kind":"graph","function":{"kind":"exponential","label":"growth","amplitude":1,"rate":0.5},"curves":[{"kind":"exponential","label":"decay","amplitude":5,"rate":-0.5}],"domain":[0,4],"range":[0,8]})
	plot(grid,"Logarithm and quadratic",{"kind":"graph","function":{"kind":"log","label":"log₂(x)","base":2},"curves":[{"kind":"quadratic","label":"(x−2)²−2","a":1,"b":-4,"c":2}],"domain":[-1,5],"range":[-4,6]})
	await capture("ui_graphs")
func data_geometry() -> void:
	clear("Geometry and data · true proportions, weighted outcomes and structured tables")
	var grid:=GridContainer.new();grid.columns=2;grid.add_theme_constant_override("h_separation",20);stage.add_child(grid)
	var triangle:=Diagram.new();triangle.custom_minimum_size=Vector2(650,340);grid.add_child(triangle)
	triangle.configure({"kind":"triangle","vertices":[{"x":0,"y":0,"label":"A"},{"x":5,"y":0,"label":"B"},{"x":1.4,"y":3.2,"label":"C"}],"given":["c"],"sides":{"c":5},"angles":{}},true)
	plot(grid,"Unit circle · radians",{"kind":"unit_circle","angle_unit":"radians","domain":[-1.4,1.4],"range":[-1.4,1.4],"points":[{"x":cos(PI/3),"y":sin(PI/3),"label":"θ"}]})
	var stats:=VBoxContainer.new();grid.add_child(stats);label(stats,"Measurement frequency table · highlighted quartile boundary")
	var table:=Table.new();stats.add_child(table);table.configure({"columns":["Reading","Frequency"],"rows":[[4.1,2],[4.3,5],[4.4,7],[4.6,3],[4.8,1]],"highlight":[2]},true)
	var probability:=Diagram.new();probability.custom_minimum_size=Vector2(650,300);grid.add_child(probability)
	probability.configure({"kind":"probability","mode":"coins","outcomes":[{"label":"0 heads","weight":1},{"label":"1 head","weight":4},{"label":"2 heads","weight":6,"favorable":true},{"label":"3 heads","weight":4,"favorable":true},{"label":"4 heads","weight":1,"favorable":true}]})
	await capture("ui_data_geometry")
func paper() -> void:
	clear("Physical mathematics worksheet · existing paper and pencil retained")
	var center:=CenterContainer.new();stage.add_child(center)
	var wrapper:=Control.new();wrapper.custom_minimum_size=Vector2(624,880);center.add_child(wrapper)
	var page=load("res://scripts/math_ui/math_paper_page.gd").new()
	page.paper={"owner_name":"Fixture student","project":{"course_id":"MTH147","title":"Procedural mathematics","questions":[{"id":"render-paper","prompt":"Express the answer exactly. The notation keyboard supports fractions, roots and powers.","input":{"kind":"expression"}}]},"strokes":{},"math_ui":{},"answers":{}}
	page.page=1;page.writable=true;wrapper.add_child(page);page.scale=Vector2(0.8,0.8)
	page.workspace.parser=parser;page.workspace.fields.answer.configure(parser);page.workspace.fields.answer.set_value(parsed("(sqrt(5)+1)/2"))
	await capture("ui_paper")
