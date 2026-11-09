extends SceneTree
const Model = preload("res://scripts/math_ui/plot_model.gd")
const Notation = preload("res://scripts/math_ui/math_notation.gd")
const Workspace = preload("res://scripts/math_ui/workspace.gd")
const Codec = preload("res://scripts/math_ui/answer_codec.gd")
var failures:=0
var checks:=0
func check(condition: bool, message: String) -> void:
	checks+=1
	if not condition:failures+=1;push_error(message)
func _initialize() -> void:
	create_timer(20).timeout.connect(func():push_error("UI test deadline");quit(5))
	call_deferred("run")
func run() -> void:
	check(absf(Model.evaluate({"kind":"sin","amplitude":3,"period":8,"phase":1,"offset":2},3)-5)<1e-10,"sin peak")
	check(absf(Model.evaluate({"kind":"cos","amplitude":-2,"period":4,"offset":3},2)-5)<1e-10,"negative amplitude")
	check(absf(Model.evaluate({"kind":"exponential","amplitude":5,"rate":-0.2},5)-5/exp(1))<1e-10,"decay")
	check(absf(Model.evaluate({"kind":"log","base":2},8)-3)<1e-10,"arbitrary log base")
	check(is_nan(Model.evaluate({"kind":"log","base":1},2)),"invalid base")
	check(is_nan(Model.evaluate({"kind":"log","base":10},-2)),"invalid argument")
	check(Model.triangle_valid([{"x":0,"y":0},{"x":3,"y":0},{"x":0,"y":4}]),"3-4-5 triangle")
	check(not Model.triangle_valid([{"x":0,"y":0},{"x":3,"y":0},{"x":5,"y":0}]),"degenerate triangle")
	for i in range(100):
		var period:=float(i+1)
		var f:Dictionary={"kind":"sin","amplitude":2.5,"period":period,"phase":-0.3,"offset":1.0}
		check(absf(Model.evaluate(f,1.2)-Model.evaluate(f,1.2+period))<1e-10,"periodic samples")
	var w:=Workspace.new();root.add_child(w)
	w.configure({"id":"persist-1","input":{"kind":"rational"}},true)
	await process_frame
	w.fields.expression.set_value("(x+1)/(x-2)");w.fields.excluded.set_value("2, -3")
	check(w.answer().excluded==["2","-3"],"rational restrictions")
	w.page=3;w.drawing={"strokes":[{"x":12,"y":7}]}
	var saved:Dictionary=JSON.parse_string(JSON.stringify(w.snapshot()))
	w.configure({"id":"persist-1","input":{"kind":"rational"}},true)
	check(w.restore(saved),"restore same immutable question")
	check(w.page==3 and w.drawing.strokes[0].x==12,"page and existing ink preserved")
	check(w.answer().expression=="(x+1)/(x-2)","expression preserved")
	check(not w.restore({"question_id":"other"}),"cross-question state rejected")
	w.configure({"id":"complex","input":{"kind":"complex","form":"polar","angle_unit":"radians"}},true)
	w.fields.magnitude.set_value("2");w.fields.angle.set_value("pi/3")
	check(w.answer().form=="polar" and w.answer().angle_unit=="radians","complex output typed units")
	var cs:=w.snapshot();w.configure({"id":"complex","input":{"kind":"complex"}},true);w.restore(cs)
	check(w.answer().angle=="pi/3" and w.answer().angle_unit=="radians","complex reopen")
	w.configure({"id":"rootset","input":{"kind":"roots"}},true)
	w.roots_editors[0].real.set_value("1");w.roots_editors[0].imag.set_value("0");w._add_root();w.roots_editors[1].real.set_value("-1")
	var rs:=w.snapshot();w.configure({"id":"rootset","input":{"kind":"roots"}},true);w.restore(rs)
	check(w.answer().values.size()==2 and w.answer().values[1].real=="-1","root set persisted")
	w.configure({"id":"graph","input":{"kind":"graph"},"diagram":{"kind":"sinusoid","function":{"kind":"sin","period":8},"domain":[-4,12],"range":[-2,2]}},true)
	w.graph.size=Vector2(700,400)
	for p in [Vector2(-4,-2),Vector2(0,0),Vector2(12,2),Vector2(2.3,-0.7)]:
		check(w.graph.to_math(w.graph.to_pixel(p)).distance_to(p)<1e-5,"coordinate inverse")
	w.graph.add_point(2,1,"peak");w.graph.zoom(0.8,Vector2.ZERO)
	var gs:=w.snapshot();w.configure({"id":"graph","input":{"kind":"graph"}},true);w.restore(gs)
	check(w.answer().points[0].x==2 and w.answer().points[0].role=="peak","mathematical points persist")
	check(w.graph.domain==gs.view.domain,"zoom persists")
	w.configure({"id":"locked","input":{"kind":"graph"}},false,{"formula_allowed":false})
	w.graph.add_point(1,2)
	check(w.answer().points.is_empty() and w.reference_panel==null,"readonly and reference gate")
	w.configure({"id":"system","input":{"kind":"system","variables":["u","v"]}},true)
	w.classification.select(2);check(w.answer()=={"classification":"infinite"},"infinite system")
	w.configure({"id":"table","input":{"kind":"table","columns":["Value","Frequency"],"rows":[[3,2],[1,4]]}},true)
	w.table.sort_column(0);check(w.answer().rows[0][0]==1,"numeric table sort")
	var ts:=w.snapshot();w.configure({"id":"table","input":{"kind":"table","columns":["Value","Frequency"]}},true);w.restore(ts)
	check(w.answer().rows.size()==2,"table reopen")
	w.configure({"id":"matrix","input":{"kind":"matrix","rows":3,"columns":3}},true)
	check(w.answer().size()==3 and w.answer()[0].size()==3,"matrix dimensions")
	w.configure({"id":"options","input":{"kind":"choice"},"options":[{"id":"p","text":"Positive"},{"id":"n","text":"Negative"}]},true)
	check(w.fields._choice.item_count==3 and w.fields._choice.get_item_text(1)=="Positive","engine top-level choice options")
	w.fields._choice.item_selected.emit(2);var choice_saved:=w.snapshot()
	w.configure({"id":"options","input":{"kind":"choice"},"options":[{"id":"p","text":"Positive"},{"id":"n","text":"Negative"}]},true);w.restore(choice_saved)
	check(w.answer()=="n" and w.fields._choice.selected==2,"choice reopen")
	w.configure({"id":"infer","input":{"kind":"graph","mode":"function"}},true)
	check(not w.answer().has("function"),"incomplete function parameters not prefilled")
	for key in ["amplitude","period","phase","offset"]:w.graph_parameter_entries[key].text={"amplitude":"-2.5","period":"8","phase":"1.25","offset":"0"}[key]
	w.graph_function_kind.select(1)
	check(w.answer().function=={"kind":"cos","amplitude":-2.5,"period":8.0,"phase":1.25,"offset":0.0},"function inference structured parameters")
	var infer_saved:=w.snapshot();w.configure({"id":"infer","input":{"kind":"graph","mode":"function"}},true);w.restore(infer_saved)
	check(w.answer()==infer_saved.answer,"function inference reopen")
	w.configure({"id":"no-prefill","input":{"kind":"graph"},"diagram":{"kind":"sinusoid","points":[{"x":1,"y":2,"role":"peak"}]}},true)
	check(w.answer().points.is_empty(),"reference coordinates never prefill graded answers")
	w.graph_parameter_entries.period.text="6.25";check(w.answer().period==6.25,"required graph period submitted")
	w.configure({"id":"sets","input":{"kind":"solutions"}},true)
	check(w.answer()=="","unanswered set remains unanswered")
	w.fields.values.set_value("root(3,27), log(8,2), sqrt(5)")
	check(w.answer().values==["root(3,27)","log(8,2)","sqrt(5)"],"set separators preserve function arguments")
	w.fields.values.set_value("none");check(w.answer()=={"values":[]},"explicit empty set")
	w.configure({"id":"multiple-choice","input":{"kind":"multi_choice","options":[{"id":"a","text":"A"},{"id":"b","text":"B"}]}},true)
	check(w.answer()=="","unanswered multiselect remains unanswered")
	w.fields._select_a.toggled.emit(true);check(w.answer()==["a"],"multiselect ids")
	var e=load("res://scripts/math_ui/expression_editor.gd").new();root.add_child(e);await process_frame
	e.set_value({"op":"symbol","name":"x"});e.insert_template("a/b");check(e.value()=="(x/1)","fraction toolbar")
	e.selected_path=[1];e._edit_leaf("3");check(e.value()=="(x/3)","denominator editing")
	e.insert_template("Undo");check(e.value()=="(x/1)","structural undo")
	e.insert_template("Redo");check(e.value()=="(x/3)","structural redo")
	check(Notation.json_safe(gs) and not Notation.json_safe({"bad":NAN}),"bounded JSON state")
	check(Codec.decode(Codec.encode(gs).text,"graph").ok,"state envelope")
	check(not Codec.decode(Codec.encode(gs).text,"wrong").ok,"wrong question envelope")
	check(not Codec.encode({"answer":"a".repeat(70000)}).ok,"oversized envelope")
	var injected:=gs.duplicate(true);injected.answer_key=42
	check(not Codec.decode(JSON.stringify(injected),"graph").ok,"unexpected key envelope")
	w.configure({"id":"tri","input":{"kind":"triangle"}},true)
	w.triangle_editors[0].fields.A.text="30";w._add_triangle();w.triangle_editors[1].fields.A.text="150"
	var triangles:=w.snapshot();w.configure({"id":"tri","input":{"kind":"triangle"}},true);w.restore(triangles)
	check(w.answer().solutions.size()==2 and w.answer().solutions[1].A=="150","SSA alternative persists")
	w.configure({"id":"nested","input":{"kind":"structured","fields":[{"id":"modes","kind":"solutions"},{"id":"mean"}]}},true)
	w.fields.modes.set_value("2,3");check(w.answer().modes==["2","3"],"nested set answer")
	var formula:Dictionary={"id":"formula","input":{"kind":"expression"}}
	var formula_policy:Dictionary={"formula_allowed":true,"formula_sections":[{"id":"logarithms","title":"Logarithms","formulas":[{"text":"Inverse relationship","ast":{"op":"log","args":[{"op":"symbol","name":"x"},{"op":"num","value":"10"}]}}]}]}
	w.configure(formula,true,formula_policy)
	w.reference_choice.item_selected.emit(1)
	check(w.reference_panel.get_child_count()==2,"typeset formula navigation")
	var fs:=w.snapshot();w.configure(formula,true,formula_policy);w.restore(fs)
	check(w.reference_section=="logarithms" and w.reference_panel.get_child_count()==2,"reference reopen")
	w.configure(formula,true,{"formula_allowed":false});w.restore(fs)
	check(w.reference_section.is_empty() and w.reference_panel==null,"reference permission rechecked")
	w.configure({"id":"events","input":{"kind":"graph"}},true)
	w.graph.size=Vector2(640,400)
	var mouse:=InputEventMouseButton.new();mouse.button_index=MOUSE_BUTTON_LEFT;mouse.pressed=true;mouse.position=w.graph.to_pixel(Vector2(2,1));w.graph._gui_input(mouse)
	check(w.answer().points.size()==1 and absf(w.answer().points[0].x-2)<1e-6,"click places math point")
	var motion:=InputEventMouseMotion.new();motion.button_mask=MOUSE_BUTTON_MASK_LEFT;motion.position=w.graph.to_pixel(Vector2(3,2));w.graph._gui_input(motion)
	check(absf(w.answer().points[0].x-3)<1e-6,"drag updates math point")
	mouse.pressed=false;w.graph._gui_input(mouse)
	var key:=InputEventKey.new();key.pressed=true;key.keycode=KEY_DELETE;w.graph._gui_input(key)
	check(w.answer().points.is_empty(),"delete after mouse release")
	var old_domain:Array=w.graph.domain.duplicate();w.graph.panning=true
	motion.button_mask=0;motion.relative=Vector2(30,0);w.graph._gui_input(motion);w.graph.panning=false
	check(w.graph.domain!=old_domain,"pan updates scales")
	for i in range(200):
		var p:=Vector2(-9.9+i*0.1,-4.9+i*0.049)
		check(w.graph.to_math(w.graph.to_pixel(p)).distance_to(p)<1e-5,"pan coordinate roundtrip")
	e.set_value("x");e.insert_template("3×3")
	check(e.matrix_grid.get_child_count()==9,"matrix editable cells")
	e.matrix_grid.get_child(8).text_changed.emit("7")
	check(Notation.source(e.tree.rows[2][2])=="7","matrix cell edit")
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--parser="):
			var engine_parser=load(argument.trim_prefix("--parser=")).new()
			e.configure(Callable(engine_parser,"parse"))
			for expression in ["(x+1)/(x-2)","sqrt(8)","root(3,27)","log(8,2)","ln(3)","exp(2)","atan2(1,-1)","sin(pi/6)","factorial(5)","choose(6,2)"]:
				e.set_value("");e._edit_leaf(expression)
				check(e.tree.get("op")!="text" and engine_parser.parse(e.value()).ok,"shared bounded parser roundtrip "+expression)
			for token in ["a/b","xⁿ","√","ⁿ√","eⁿ","log","atan2","!","nCr"]:
				e.set_value({"op":"num","value":"3"});e.insert_template(token)
				check(engine_parser.parse(e.value()).ok,"shared parser accepts toolbar "+token)
			e.set_value("");e._edit_leaf("OS.execute('bad')")
			check(e.tree.op=="text","untrusted syntax never parsed as executable AST")
	var paper_page=load("res://scripts/math_ui/math_paper_page.gd").new()
	paper_page.paper={"owner_name":"UI test","project":{"course_id":"MTH147","title":"Test","questions":[{"id":"paper-q","prompt":"Enter an exact fraction","input":{"kind":"expression"}}]},"math_ui":{},"answers":{},"strokes":{}}
	paper_page.page=1;paper_page.writable=true;root.add_child(paper_page);await process_frame
	check(is_instance_valid(paper_page.workspace) and is_instance_valid(paper_page.ink),"physical page retains ink and math workspace")
	paper_page.set_drawing(true);check(paper_page.ink.mouse_filter==Control.MOUSE_FILTER_STOP,"pencil mode retained")
	paper_page.set_drawing(false);check(paper_page.ink.mouse_filter==Control.MOUSE_FILTER_IGNORE,"answer mode retained")
	paper_page.free()
	var draw_nodes:Array=[]
	for descriptor in [
		{"kind":"complex_plane","polar":true,"angle_unit":"radians","domain":[-4,4],"range":[-4,4],"points":[{"x":2,"y":2,"label":"z"}]},
		{"kind":"unit_circle","domain":[-1.5,1.5],"range":[-1.5,1.5],"points":[{"x":0.5,"y":sqrt(0.75),"label":"theta"}]},
		{"kind":"graph","function":{"kind":"sin","period":6},"curves":[{"kind":"cos","period":6}],"markers":[{"x":0,"label":"phase"}],"phasors":[{"magnitude":1,"angle":30}]}
	]:
		var plot=load("res://scripts/math_ui/graph_canvas.gd").new();root.add_child(plot);plot.size=Vector2(650,380);plot.configure(descriptor,false);draw_nodes.append(plot)
		if descriptor.kind in ["complex_plane","unit_circle"]:
			var dx:float=plot.to_pixel(Vector2(1,0)).distance_to(plot.to_pixel(Vector2.ZERO))
			var dy:float=plot.to_pixel(Vector2(0,1)).distance_to(plot.to_pixel(Vector2.ZERO))
			check(absf(dx-dy)<1e-4,"equal coordinate scales preserve angles/circles")
	var td=load("res://scripts/math_ui/diagram_view.gd").new();root.add_child(td);td.size=Vector2(650,380)
	td.configure({"kind":"triangle","vertices":[{"x":0,"y":0,"label":"A"},{"x":5,"y":0,"label":"B"},{"x":1,"y":3,"label":"C"}],"sides":{"c":5},"angles":{}},true)
	await process_frame;await process_frame
	check(draw_nodes[1].axis_labels[0].size()<=13,"unit-circle tick labels have bounded spacing")
	var clean_zero:=false
	for tick in draw_nodes[1].axis_labels[1]:
		if absf(float(tick.value))<1e-10:clean_zero=tick.label=="0"
	check(clean_zero,"axis zero is readable without floating-point artifact")
	var down:=InputEventMouseButton.new();down.button_index=MOUSE_BUTTON_LEFT;down.pressed=true;down.position=td.projected_vertices[2];td._gui_input(down)
	var drag:=InputEventMouseMotion.new();drag.button_mask=MOUSE_BUTTON_MASK_LEFT;drag.relative=Vector2(30,-15);td._gui_input(drag)
	check(td.descriptor.vertices[2].x>1 and td.descriptor.vertices[2].y>3,"triangle demonstration drag uses true coordinates")
	check(absf(td.descriptor.angles.A+td.descriptor.angles.B+td.descriptor.angles.C-180)<1e-4,"dragged triangle angles sum180 (Vector2 float precision)")
	for descriptor in [
		{"kind":"probability","mode":"dice","outcomes":[{"label":"7","weight":6,"favorable":true},{"label":"8","weight":5}]},
		{"kind":"probability","mode":"tree","outcomes":[],"nodes":{"a":[0.1,0.2],"b":[0.5,0.5]},"branches":[{"from":"a","to":"b","label":"1/2"}]},
		{"kind":"circuit","topology":"series","components":[{"id":"Z1","real":4,"imag":3},{"id":"Z2","real":2,"imag":-1}],"source":{"rms_volts":12}},
		{"kind":"circuit","topology":"parallel","components":[{"id":"Z1","real":4,"imag":3},{"id":"Z2","real":2,"imag":-1}],"source":{"rms_volts":12}}
	]:
		var d=load("res://scripts/math_ui/diagram_view.gd").new();root.add_child(d);d.size=Vector2(650,380);d.configure(descriptor);draw_nodes.append(d)
	for token in ["a/b","xⁿ","xₙ","√","ⁿ√","log","eⁿ","!","2×2","3×3","det"]:
		e.set_value({"op":"symbol","name":"x"});e.insert_template(token)
		check(e.preview.operations.size()>0 and e.preview.custom_minimum_size.y>0,"typesetter layout "+token)
		await process_frame
	await process_frame
	for node in draw_nodes:node.free()
	td.free()
	e.set_value({"op":"div","args":[{"op":"num","value":"1"},{"op":"num","value":"2"}]})
	check(e.entry.placeholder_text=="Edit fraction","plain fraction selection label")
	e._select([0]);check(e.entry.placeholder_text=="Edit numerator","plain numerator selection label")
	e._select([1]);check(e.entry.placeholder_text=="Edit denominator","plain denominator selection label")
	e.set_value({"op":"pow","args":[{"op":"symbol","name":"x"},{"op":"num","value":"2"}]});e._select([1]);check(e.entry.placeholder_text=="Edit exponent","plain exponent selection label")
	e.free();w.free()
	print("MATH_UI_RESULT checks=%d failures=%d"%[checks,failures])
	quit(1 if failures else 0)
