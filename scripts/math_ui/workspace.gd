extends VBoxContainer
const UI = preload("res://scripts/ui/design_system/widgets.gd")
## Mount inside the existing paper/whiteboard. Authority, marks and ownership stay outside.
const Editor = preload("res://scripts/math_ui/expression_editor.gd")
const View = preload("res://scripts/math_ui/expression_view.gd")
const Graph = preload("res://scripts/math_ui/graph_canvas.gd")
const Diagram = preload("res://scripts/math_ui/diagram_view.gd")
const Table = preload("res://scripts/math_ui/table_editor.gd")
const Notation = preload("res://scripts/math_ui/math_notation.gd")
signal changed(state: Dictionary)
signal reference_requested(section: String)
signal demonstration_changed(data: Dictionary)
signal demonstration_parameters_changed(parameters: Dictionary)
var problem: Dictionary={}
var policy: Dictionary={}
var editable:=false
var parser: Callable
var fields: Dictionary={}
var field_kinds: Dictionary={}
var field_labels: Dictionary={}
var graph: Control
var graph_parameter_entries:Dictionary={}
var graph_function_kind:OptionButton
var table: Control
var reference_panel: VBoxContainer
var save_notice: Label
var reference_choice: OptionButton
var page:=0
var drawing: Variant={}
var restoring:=false
var kind:="expression"
var values: Dictionary={}
var reference_section:=""
var complex_form: OptionButton
var angle_unit: OptionButton
var classification: OptionButton
var roots_container: VBoxContainer
var roots_editors: Array=[]
var triangle_container: VBoxContainer
var triangle_editors: Array=[]
var demonstration_timer: Timer
var animation_time:=0.0

func configure(data: Dictionary, can_edit: bool, access: Dictionary={}, parse_callable: Callable=Callable()) -> void:
	add_theme_constant_override("separation",10)
	problem=data.duplicate(true)
	editable=can_edit
	policy=access.duplicate(true)
	parser=parse_callable
	if is_instance_valid(demonstration_timer):demonstration_timer.stop()
	demonstration_timer=null
	values.clear();fields.clear();field_kinds.clear();field_labels.clear();roots_editors.clear();triangle_editors.clear()
	graph=null;table=null;reference_panel=null;reference_choice=null;complex_form=null;angle_unit=null;classification=null;graph_function_kind=null;graph_parameter_entries.clear()
	for child in get_children(): remove_child(child);child.queue_free()
	var title:=Label.new();title.text=str(data.get("prompt","Mathematics"));title.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;add_child(title)
	var toolbar := HFlowContainer.new();toolbar.theme=preload("res://scripts/ui/design_system/theme.gd").create();add_child(toolbar)
	toolbar.add_child(preload("res://scripts/ui/design_system/widgets.gd").badge("Answer entry" if editable else "Review · read only","course"))
	save_notice=Label.new();save_notice.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;save_notice.add_theme_color_override("font_color",Color("e8a362"));save_notice.hide();add_child(save_notice)
	if data.get("ast") is Dictionary and data.ast.has("op"):
		var notation:=View.new();add_child(notation);notation.set_expression(data.ast)
	var spec:Dictionary=data.get("input",{}).duplicate(true)
	if not spec.has("options") and data.has("options"):spec.options=data.options.duplicate(true)
	kind=str(spec.get("kind",data.get("expected_form","expression")))
	if kind=="complex_roots":kind="roots"
	if data.get("diagram") is Dictionary and not data.diagram.is_empty(): _diagram(data.diagram)
	match kind:
		"graph", "complex_plane", "unit_circle":
			if not is_instance_valid(graph): _diagram({"kind":kind,"domain":[-10,10],"range":[-5,5]})
			if kind=="graph":_graph_answer_input(spec)
		"complex": _complex_input(spec)
		"roots":
			roots_container=VBoxContainer.new();add_child(roots_container)
			_add_root()
			var add:=Button.new();add.text="Add root";add.disabled=not editable;add.pressed.connect(_add_root);add_child(add)
		"triangle":
			triangle_container=VBoxContainer.new();add_child(triangle_container)
			_add_triangle()
			var add:=Button.new();add.text="Add alternate triangle (SSA)";add.disabled=not editable;add.pressed.connect(_add_triangle);add_child(add)
		"solutions", "restrictions", "multiple": _field("values","Solutions / excluded values (comma separated)")
		"system":
			classification=OptionButton.new()
			for label in ["Unique solution","No solution","Infinitely many solutions"]: classification.add_item(label)
			classification.disabled=not editable;classification.item_selected.connect(func(_i):_notify());add_child(classification)
			for key in spec.get("variables",spec.get("symbols",["x","y","z"])): _field(str(key),str(key))
		"rational": _field("expression","Expression");_field("excluded","Excluded values (comma separated)")
		"division": _field("quotient","Quotient");_field("remainder","Remainder")
		"matrix", "determinant", "table", "statistics_table":
			table=Table.new();add_child(table);table.configure(spec,editable);table.changed.connect(func(_v):_notify())
		"structured", "statistics":
			var definitions:Array=spec.get("fields",[])
			if definitions.is_empty(): definitions=[{"id":"answer","label":"Answer"}]
			for item in definitions:
				if item is String: _field(item,item)
				elif item is Dictionary:
					var id:=str(item.get("id","answer"))
					field_kinds[id]=str(item.get("kind","expression"))
					_field(id,str(item.get("label",id)) + (" (comma separated; blank = empty set)" if field_kinds[id] in ["solutions","multiple","restrictions"] else ""))
		"choice":
			var options:=OptionButton.new();options.add_item("Choose…",-1)
			for option in spec.get("options",[]): options.add_item(str(option.get("label",option.get("text",option.get("id","")))) if option is Dictionary else str(option))
			options.disabled=not editable
			options.item_selected.connect(func(index):var list:Array=spec.get("options",[]);values.choice=(str(list[index-1].get("id","")) if list[index-1] is Dictionary else str(list[index-1])) if index>0 else "";_notify())
			add_child(options);fields["_choice"]=options
		"multi_choice":
			values.selections=[]
			values.selections_touched=false
			for option in spec.get("options",data.get("options",[])):
				var id:=str(option.get("id","")) if option is Dictionary else str(option)
				var button:=CheckBox.new();button.text=str(option.get("label",option.get("text",id))) if option is Dictionary else id;button.disabled=not editable;add_child(button);fields["_select_"+id]=button
				button.toggled.connect(func(checked):
					values.selections_touched=true
					if checked and id not in values.selections:values.selections.append(id)
					elif not checked:values.selections.erase(id)
					_notify())
			var none:=Button.new();none.text="No options apply";none.disabled=not editable;add_child(none)
			none.pressed.connect(func():values.selections=[];values.selections_touched=true;_notify())
		_: _field("answer",str(spec.get("unit","Answer")))
	if policy.get("formula_allowed",false): _reference()

func _field(id: String, label_text: String, parent: Node=null) -> Control:
	var target:Node=self if parent==null else parent
	var label:=Label.new();label.text=label_text;target.add_child(label)
	var editor:=Editor.new();editor.configure(parser,editable);target.add_child(editor)
	editor.changed.connect(func(_text):_notify())
	fields[id]=editor
	field_labels[id]=label
	return editor

func _complex_input(spec: Dictionary) -> void:
	complex_form=OptionButton.new()
	for name in ["rectangular","polar","exponential"]: complex_form.add_item(name)
	complex_form.disabled=not editable
	add_child(complex_form)
	var requested:=str(spec.get("form","rectangular"))
	complex_form.select(maxi(0,["rectangular","polar","exponential"].find(requested)))
	angle_unit=OptionButton.new();angle_unit.add_item("degrees");angle_unit.add_item("radians");angle_unit.disabled=not editable;add_child(angle_unit)
	angle_unit.select(1 if spec.get("angle_unit")=="radians" else 0)
	angle_unit.item_selected.connect(func(_i):_notify())
	_field("real","Real part");_field("imag","Imaginary coefficient j")
	_field("magnitude","Magnitude");_field("angle","Angle")
	complex_form.item_selected.connect(func(_i):_complex_visibility();_notify())
	_complex_visibility()

func _complex_visibility() -> void:
	if not is_instance_valid(complex_form):return
	var rectangular:bool=complex_form.selected==0
	for key in ["real","imag","magnitude","angle"]:
		if fields.has(key):
			fields[key].visible=rectangular if key in ["real","imag"] else not rectangular
			field_labels[key].visible=fields[key].visible
	angle_unit.visible=not rectangular

func _graph_answer_input(spec: Dictionary) -> void:
	var definitions:Array=spec.get("fields",[])
	if spec.get("mode","")=="function":
		graph_function_kind=OptionButton.new();graph_function_kind.add_item("sin");graph_function_kind.add_item("cos");graph_function_kind.disabled=not editable;add_child(graph_function_kind)
		graph_function_kind.item_selected.connect(func(_i):_notify())
		if definitions.is_empty():definitions=[{"id":"amplitude"},{"id":"period"},{"id":"phase"},{"id":"offset"}]
		var instruction:=Label.new();instruction.text="Function parameters: enter finite decimal values; phase and period use the x-axis units.";instruction.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;add_child(instruction)
	else:
		if not definitions.any(func(item):return (str(item.get("id","")) if item is Dictionary else str(item))=="period"):definitions.append({"id":"period","label":"Period in x-axis units"})
	for item in definitions:
		var id:=str(item.get("id","")) if item is Dictionary else str(item)
		var row:=HBoxContainer.new();add_child(row)
		var label:=Label.new();label.text=str(item.get("label",id)) if item is Dictionary else id;row.add_child(label)
		var entry:=LineEdit.new();entry.max_length=64;entry.placeholder_text="Decimal value";entry.editable=editable;row.add_child(entry);graph_parameter_entries[id]=entry
		entry.text_changed.connect(func(_text):_notify())

func _add_root() -> void:
	if roots_editors.size()>=16: return
	var row:=HBoxContainer.new();roots_container.add_child(row)
	var real:=Editor.new();real.configure(parser,editable);row.add_child(real)
	var imag:=Editor.new();imag.configure(parser,editable);row.add_child(imag)
	real.changed.connect(func(_v):_notify());imag.changed.connect(func(_v):_notify())
	var item:Dictionary={"real":real,"imag":imag,"row":row}
	roots_editors.append(item)
	var remove:=Button.new();remove.text="Remove root";remove.disabled=not editable;row.add_child(remove)
	remove.pressed.connect(func():roots_editors.erase(item);row.queue_free();_notify())
	_notify()

func _add_triangle() -> void:
	if triangle_editors.size()>=2:return
	var column:=VBoxContainer.new();triangle_container.add_child(column)
	var group:Dictionary={"column":column,"fields":{}}
	var title:=Label.new();title.text="Triangle %d · a opposite A, b opposite B, c opposite C"%(triangle_editors.size()+1);column.add_child(title)
	for key in ["A","B","C","a","b","c"]:
		var row:=HBoxContainer.new();column.add_child(row)
		var label:=Label.new();label.text=key+(" (degrees)" if key==key.to_upper() else " (side)");row.add_child(label)
		var entry:=LineEdit.new();entry.max_length=128;entry.editable=editable;entry.size_flags_horizontal=Control.SIZE_EXPAND_FILL;row.add_child(entry)
		entry.text_changed.connect(func(_v):_notify());group.fields[key]=entry
	var remove:=Button.new();remove.text="Remove this triangle";remove.disabled=not editable;column.add_child(remove)
	remove.pressed.connect(func():triangle_editors.erase(group);column.queue_free();_notify())
	triangle_editors.append(group)
	_notify()

func _diagram(data: Dictionary) -> void:
	var diagram_kind:=str(data.get("kind","graph"))
	if diagram_kind in ["triangle","probability","circuit"]:
		var d:=Diagram.new();add_child(d);d.configure(data,bool(policy.get("demonstration",false)))
		d.demonstration_changed.connect(func(updated):demonstration_changed.emit(updated))
		return
	if diagram_kind in ["statistics","table"]:
		var t:=Table.new();add_child(t);t.configure(data,bool(policy.get("demonstration",false)))
		t.changed.connect(func(rows):demonstration_changed.emit({"kind":diagram_kind,"columns":t.columns,"rows":rows}))
		return
	graph=Graph.new();add_child(graph)
	var demo_plot:bool=policy.get("demonstration",false) and diagram_kind in ["complex_plane","unit_circle"]
	graph.configure(data,(editable and kind in ["graph","complex_plane","unit_circle"]) or demo_plot)
	if demo_plot:graph.points=data.get("points",[]).duplicate(true)
	graph.changed.connect(func(state):
		if demo_plot:demonstration_changed.emit(state)
		else:_notify())
	var tools:=HFlowContainer.new();add_child(tools)
	for label in ["Zoom +","Zoom −","Reset view","Cartesian / polar"]:
		var b:=UI.action(label,"settings",Callable());b.theme=preload("res://scripts/ui/design_system/theme.gd").create();tools.add_child(b)
		b.pressed.connect(func():
			match label:
				"Zoom +":graph.zoom(0.8,graph.to_math(graph.plot_rect().get_center()))
				"Zoom −":graph.zoom(1.25,graph.to_math(graph.plot_rect().get_center()))
				"Reset view":graph.restore({"points":graph.points.duplicate(true),"domain":data.get("domain",[-10,10]),"range":data.get("range",[-5,5]),"polar":data.get("polar",false)});_notify()
				_:graph.polar=not graph.polar;graph.queue_redraw();_notify()
		)
	if graph.editable:
		var x:=SpinBox.new();x.min_value=-1e9;x.max_value=1e9;x.step=0.01;x.prefix="x / Re: ";tools.add_child(x)
		var y:=SpinBox.new();y.min_value=-1e9;y.max_value=1e9;y.step=0.01;y.prefix="y / Im: ";tools.add_child(y)
		var point_role:=OptionButton.new()
		for name in ["critical","peak","trough","intercept","root","vector"]: point_role.add_item(name)
		tools.add_child(point_role)
		point_role.item_selected.connect(func(i):graph.role=point_role.get_item_text(i))
		var add:=UI.action("Place point","plus",func():graph.add_point(x.value,y.value,point_role.get_item_text(point_role.selected)));tools.add_child(add)
		var clear:=UI.action("Clear points","minus",func():graph.points.clear();graph.queue_redraw();_notify());tools.add_child(clear)
		if diagram_kind in ["complex_plane","unit_circle"]:
			var magnitude:=SpinBox.new();magnitude.min_value=0;magnitude.max_value=1e9;magnitude.step=0.01;magnitude.prefix="Magnitude: ";tools.add_child(magnitude)
			var angle:=SpinBox.new();angle.min_value=-1e9;angle.max_value=1e9;angle.step=0.01;angle.prefix="Angle: ";tools.add_child(angle)
			var units:=OptionButton.new();units.add_item("degrees");units.add_item("radians");units.select(1 if data.get("angle_unit")=="radians" else 0);tools.add_child(units)
			var place:=Button.new();place.text="Place polar vector";tools.add_child(place)
			place.pressed.connect(func():var theta:float=deg_to_rad(angle.value) if units.selected==0 else angle.value;graph.add_point(magnitude.value*cos(theta),magnitude.value*sin(theta),"vector"))
	if policy.get("demonstration",false): _demonstration(data)

func _demonstration(data: Dictionary) -> void:
	if not data.has("function"): return
	var controls:=HFlowContainer.new();add_child(controls)
	for key in ["amplitude","period","phase","offset","rate","base"]:
		if not data.function.has(key): continue
		var spin:=SpinBox.new();spin.min_value=0.01 if key in ["period","base"] else -1000.0;spin.max_value=1000;spin.step=0.1;spin.value=float(data.function[key]);spin.prefix=key+": ";controls.add_child(spin)
		spin.value_changed.connect(func(value):graph.descriptor.function[key]=value;graph._rebuild();demonstration_changed.emit(graph.descriptor.duplicate(true)))
	if float(data.function.get("period",0))>0:
		var frequency:=SpinBox.new();frequency.min_value=0.000001;frequency.max_value=1000000;frequency.step=0.001;frequency.value=1.0/float(data.function.period);frequency.prefix="Frequency (cycles / x unit): ";controls.add_child(frequency)
		frequency.value_changed.connect(func(value):graph.descriptor.function.period=1.0/value;graph._rebuild();demonstration_changed.emit(graph.descriptor.duplicate(true)))
	var teaching_parameters:Dictionary={}
	for parameter in data.get("controls",[]).slice(0,12):
		var id:=str(parameter.get("id",""))
		var control:=SpinBox.new();control.min_value=float(parameter.get("min",0));control.max_value=float(parameter.get("max",1000));control.step=float(parameter.get("step",0.1));control.value=float(parameter.get("value",1));control.prefix=str(parameter.get("label",id))+": ";controls.add_child(control)
		teaching_parameters[id]=control.value
		control.value_changed.connect(func(value):teaching_parameters[id]=value;demonstration_parameters_changed.emit(teaching_parameters.duplicate(true)))
	var play:=UI.action("Play / pause marker","play",Callable());controls.add_child(play)
	demonstration_timer=Timer.new();demonstration_timer.wait_time=0.05;add_child(demonstration_timer)
	demonstration_timer.timeout.connect(func():
		animation_time=fmod(animation_time+0.05,1.0)
		var x:=lerpf(float(graph.domain[0]),float(graph.domain[1]),animation_time)
		var y:float=load("res://scripts/math_ui/plot_model.gd").evaluate(graph.descriptor.function,x)
		if is_finite(y): graph.points=[{"x":x,"y":y,"role":"time"}];graph.queue_redraw())
	play.pressed.connect(func():
		if demonstration_timer.is_stopped():demonstration_timer.start()
		else:demonstration_timer.stop()
	)

func _reference() -> void:
	var sections:Array=policy.get("formula_sections",[])
	if sections.is_empty(): return
	var choice:=OptionButton.new();choice.add_item("Formula reference…")
	reference_choice=choice
	for section in sections: choice.add_item(str(section.get("title",section.get("id",""))))
	add_child(choice)
	reference_panel=VBoxContainer.new();add_child(reference_panel)
	choice.item_selected.connect(func(index):
		for child in reference_panel.get_children():reference_panel.remove_child(child);child.queue_free()
		if index<=0 or not policy.get("formula_allowed",false):return
		var section:Dictionary=sections[index-1]
		reference_section=str(section.get("id",""));reference_requested.emit(reference_section)
		for formula in section.get("formulas",[]):
			var label:=Label.new();label.text=str(formula.get("text",""));label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;reference_panel.add_child(label)
			if formula.get("ast") is Dictionary:
				var view:=View.new();reference_panel.add_child(view);view.set_expression(formula.ast)
		_notify()
	)

func _list(text: String) -> Array:
	var result:=[]
	var value:=text.strip_edges().trim_prefix("{").trim_suffix("}")
	if value.to_lower() in ["none","empty","no solution",""]:return result
	var depth:=0
	var start:=0
	for i in range(mini(value.length(),512)):
		if value[i] in "([{":depth+=1
		elif value[i] in ")]}":depth=maxi(0,depth-1)
		elif value[i] in ",;" and depth==0:
			result.append(value.substr(start,i-start).strip_edges());start=i+1
	result.append(value.substr(start).strip_edges())
	return result

func answer() -> Variant:
	var result:Dictionary={}
	for key in fields:
		if not str(key).begins_with("_"):
			var value:String=fields[key].value()
			result[key]=_list(value) if field_kinds.get(key) in ["solutions","multiple","restrictions"] and not value.strip_edges().is_empty() else value
	match kind:
		"complex":
			var form:=complex_form.get_item_text(complex_form.selected)
			if form=="rectangular":return {"real":result.real,"imag":result.imag}
			return {"magnitude":result.magnitude,"angle":result.angle,"form":form,"angle_unit":angle_unit.get_item_text(angle_unit.selected)}
		"roots":
			var roots:=[]
			for root_item in roots_editors:roots.append({"real":root_item.real.value(),"imag":root_item.imag.value()})
			return {"values":roots}
		"triangle":
			var triangles:=[]
			for item in triangle_editors:
				var triangle:Dictionary={}
				for key in item.fields:triangle[key]=item.fields[key].text
				triangles.append(triangle)
			return {"solutions":triangles}
		"solutions", "restrictions", "multiple":return {"values":_list(result.get("values",""))} if not str(result.get("values","")).strip_edges().is_empty() else ""
		"system":
			if classification.selected>0:return {"classification":"none" if classification.selected==1 else "infinite"}
		"rational":result.excluded=_list(result.get("excluded","")) if not str(result.get("excluded","")).strip_edges().is_empty() else "";return result
		"graph", "complex_plane", "unit_circle":
			var graph_answer:Dictionary=graph.answer()
			var parameters:Dictionary={}
			for key in graph_parameter_entries:
				var text:String=graph_parameter_entries[key].text
				if text.is_valid_float() and is_finite(float(text)):parameters[key]=float(text)
			if parameters.has("period"):graph_answer.period=parameters.period
			if is_instance_valid(graph_function_kind) and parameters.size()==graph_parameter_entries.size():
				parameters.kind=graph_function_kind.get_item_text(graph_function_kind.selected)
				graph_answer.function=parameters
			return graph_answer
		"matrix", "determinant":return table.rows.duplicate(true)
		"table", "statistics_table":return {"rows":table.rows.duplicate(true)}
		"choice":return values.get("choice","")
		"multi_choice":return values.get("selections",[]).duplicate() if values.get("selections_touched",false) else ""
		"structured", "statistics", "division":return result
		_:return result.get("answer","")
	return result

func snapshot() -> Dictionary:
	var inputs:Dictionary={}
	for key in fields:
		if not str(key).begins_with("_"):inputs[key]=fields[key].tree.duplicate(true)
	inputs._graph_parameters={}
	for key in graph_parameter_entries:inputs._graph_parameters[key]=graph_parameter_entries[key].text
	inputs._graph_function_kind=graph_function_kind.selected if is_instance_valid(graph_function_kind) else 0
	return {"version":1,"question_id":str(problem.get("id","")),"answer":answer(),"inputs":inputs,"page":page,"drawing":drawing,"view":graph.snapshot() if is_instance_valid(graph) else {},"reference_section":reference_section,"complex_form":complex_form.selected if is_instance_valid(complex_form) else 0,"angle_unit":angle_unit.selected if is_instance_valid(angle_unit) else 0,"classification":classification.selected if is_instance_valid(classification) else 0}

func restore(state: Dictionary) -> bool:
	if str(state.get("question_id",""))!=str(problem.get("id","")) or not Notation.json_safe(state):return false
	restoring=true
	page=maxi(0,int(state.get("page",0)));drawing=state.get("drawing",{}).duplicate(true) if state.get("drawing",{}) is Dictionary or state.get("drawing",{}) is Array else state.get("drawing")
	for key in state.get("inputs",{}):
		if fields.has(key):fields[key].set_value(state.inputs[key])
	for key in state.get("inputs",{}).get("_graph_parameters",{}):
		if graph_parameter_entries.has(key):graph_parameter_entries[key].text=str(state.inputs._graph_parameters[key])
	if is_instance_valid(graph_function_kind):graph_function_kind.select(clampi(int(state.get("inputs",{}).get("_graph_function_kind",0)),0,1))
	if is_instance_valid(graph):graph.restore(state.get("view",{}))
	if is_instance_valid(table):table.configure({"columns":table.columns,"rows":state.get("answer",{}).get("rows",[]) if state.get("answer") is Dictionary else state.get("answer",[])},editable)
	if is_instance_valid(complex_form):complex_form.select(clampi(int(state.get("complex_form",0)),0,2));angle_unit.select(clampi(int(state.get("angle_unit",0)),0,1));_complex_visibility()
	if is_instance_valid(classification):classification.select(clampi(int(state.get("classification",0)),0,2))
	if kind=="roots":
		for item in roots_editors:item.row.queue_free()
		roots_editors.clear()
		for item in state.get("answer",{}).get("values",[]).slice(0,16):
			_add_root();roots_editors[-1].real.set_value(item.get("real",""));roots_editors[-1].imag.set_value(item.get("imag",""))
	if kind=="triangle":
		for item in triangle_editors:item.column.queue_free()
		triangle_editors.clear()
		for item in state.get("answer",{}).get("solutions",[]).slice(0,2):
			_add_triangle()
			for key in triangle_editors[-1].fields:triangle_editors[-1].fields[key].text=str(item.get(key,""))
	if kind=="choice":
		values.choice=state.get("answer","")
		var options:Array=problem.get("input",{}).get("options",problem.get("options",[]))
		for i in range(options.size()):
			if (str(options[i].get("id","")) if options[i] is Dictionary else str(options[i]))==str(values.choice):fields._choice.select(i+1)
	if kind=="multi_choice":
		values.selections=state.answer.duplicate() if state.get("answer") is Array else []
		values.selections_touched=state.get("answer") is Array
		for key in fields:
			if str(key).begins_with("_select_"):fields[key].set_pressed_no_signal(str(key).trim_prefix("_select_") in values.selections)
	reference_section=str(state.get("reference_section","")) if policy.get("formula_allowed",false) else ""
	if is_instance_valid(reference_choice) and not reference_section.is_empty():
		var sections:Array=policy.get("formula_sections",[])
		for i in range(sections.size()):
			if str(sections[i].get("id",""))==reference_section:
				reference_choice.select(i+1)
				reference_choice.item_selected.emit(i+1)
	restoring=false
	return true

func _notify() -> void:
	if not restoring and editable:changed.emit(snapshot())

func save_error(message: String) -> void:
	if is_instance_valid(save_notice):save_notice.text="Could not save this mathematics page: "+message;save_notice.show()
