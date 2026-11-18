extends VBoxContainer
const Complex=preload("res://scripts/mth255/complex_domain.gd")
var desktop: Control
var source: OptionButton
var topology: OptionButton
var values: Array[SpinBox]=[]
var results: Label
var diagram: Control
var project_picker: OptionButton

func build(parent: Control) -> void:
	desktop=parent
	var body:=HBoxContainer.new()
	body.size_flags_vertical=Control.SIZE_EXPAND_FILL
	add_child(body)
	var controls:=GridContainer.new()
	controls.columns=2
	controls.custom_minimum_size.x=270
	body.add_child(controls)
	source=_choice(controls,"Source",["DC","AC (RMS)"])
	topology=_choice(controls,"Arrangement",["Series","Parallel"])
	for entry in [["Voltage (V)",12.0,1000.0],["Frequency (Hz)",60.0,10000.0],["Resistance (Ω)",100.0,1000000.0],["Inductance (mH)",0.0,10000.0],["Capacitance (µF)",0.0,10000.0]]:
		var label:=Label.new();label.text=entry[0];controls.add_child(label)
		var spin:=SpinBox.new()
		spin.max_value=entry[2];spin.step=.01;spin.value=entry[1]
		controls.add_child(spin)
		values.append(spin)
		spin.value_changed.connect(func(_value):_calculate())
	source.item_selected.connect(func(_index):_calculate())
	topology.item_selected.connect(func(_index):_calculate())
	var side:=VBoxContainer.new()
	side.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	body.add_child(side)
	diagram=Control.new()
	diagram.custom_minimum_size=Vector2(230,134)
	diagram.size_flags_vertical=Control.SIZE_EXPAND_FILL
	side.add_child(diagram)
	diagram.draw.connect(_draw_circuit)
	diagram.resized.connect(diagram.queue_redraw)
	results=Label.new()
	results.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	side.add_child(results)
	var actions:=HBoxContainer.new()
	add_child(actions)
	actions.add_child(desktop._button("Calculate",_calculate))
	actions.add_child(desktop._button("Reset",func():_apply([0,0,12.0,60.0,100.0,0.0,0.0])))
	actions.add_child(desktop._button("Save project",func():desktop._name_dialog("Save circuit project","circuit.circuit",_save)))
	project_picker=OptionButton.new()
	actions.add_child(project_picker)
	actions.add_child(desktop._button("Open project",_open))
	refresh_projects()
	_calculate()

func _choice(parent: Control, label_text: String, names: Array) -> OptionButton:
	var label:=Label.new()
	label.text=label_text;parent.add_child(label)
	var choice:=OptionButton.new()
	for name in names:choice.add_item(name)
	parent.add_child(choice)
	return choice

func _calculate() -> void:
	var v:=values[0].value
	var omega:=TAU*values[1].value
	var resistance:=values[2].value
	var inductance:=values[3].value*.001
	var capacitance:=values[4].value*.000001
	var ac:=source.selected==1
	var parallel:=topology.selected==1
	var impedance:=Vector2(resistance,0)
	if ac and omega<=0.0:
		results.text="Enter an AC frequency above zero."
	elif not ac and not parallel and capacitance>0:
		results.text="Open circuit at DC steady state • 0 A"
	else:
		if ac:
			var x_l:=omega*inductance
			var x_c:=1.0/(omega*capacitance) if capacitance>0 else 0.0
			if parallel:
				var admittance:=Vector2(1.0/resistance if resistance>0 else 0.0, (1.0/x_c if x_c>0 else 0.0)-(1.0/x_l if x_l>0 else 0.0))
				impedance=Complex.divide(Vector2(1,0),admittance)
			else:impedance.y=x_l-x_c
		elif parallel and inductance>0:impedance=Vector2.ZERO
		var current:=Complex.divide(Vector2(v,0),impedance)
		if not impedance.is_finite():results.text="Open circuit • 0 A"
		elif not current.is_finite():results.text="Ideal short circuit • current is unbounded for a nonzero source."
		else:results.text="Z = %.3f %+.3fj Ω\nI = %.4f %+.4fj A\n|I| = %.4f A   ·   P = %.3f W" % [impedance.x,impedance.y,current.x,current.y,current.length(),v*current.x]
	diagram.queue_redraw()

func _draw_circuit() -> void:
	var color:=Color("73c6d4")
	var size_px:=diagram.size
	var frame:=Rect2(Vector2(25,25),size_px-Vector2(50,55))
	var labels:=["R"]
	if values[3].value>0:labels.append("L")
	if values[4].value>0:labels.append("C")
	var font:=get_theme_default_font()
	if topology.selected==0:
		diagram.draw_rect(frame,color,false,2.0)
		for i in labels.size():
			var x:=frame.position.x+frame.size.x*(i+1)/float(labels.size()+1)
			var tile:=Rect2(Vector2(x-16,frame.position.y-10),Vector2(32,22))
			diagram.draw_rect(tile,Color("1d3a50"))
			diagram.draw_string(font,tile.position+Vector2(10,16),labels[i],HORIZONTAL_ALIGNMENT_LEFT,-1,15)
	else:
		diagram.draw_line(frame.position,Vector2(frame.end.x,frame.position.y),color,2)
		diagram.draw_line(Vector2(frame.position.x,frame.end.y),frame.end,color,2)
		for i in labels.size():
			var x:=frame.position.x+frame.size.x*(i+1)/float(labels.size()+1)
			diagram.draw_line(Vector2(x,frame.position.y),Vector2(x,frame.end.y),color,2)
			var tile:=Rect2(Vector2(x-16,frame.get_center().y-10),Vector2(32,22))
			diagram.draw_rect(tile,Color("1d3a50"))
			diagram.draw_string(font,tile.position+Vector2(10,16),labels[i],HORIZONTAL_ALIGNMENT_LEFT,-1,15)
	diagram.draw_string(font,Vector2(frame.position.x,frame.end.y+23),"AC source" if source.selected==1 else "DC source",HORIZONTAL_ALIGNMENT_LEFT,-1,14,color)

func _save(name: String) -> void:
	if not name.ends_with(".circuit"):name+=".circuit"
	if not desktop._valid_path(name):return
	var numbers: Array=[source.selected,topology.selected]
	for spin in values:numbers.append(spin.value)
	desktop._send({"op":"save","path":name,"text":JSON.stringify({"type":"campus-circuit-1","values":numbers}),"version":int(desktop._file(name).get("version",0))})

func refresh_projects() -> void:
	var selected:=project_picker.get_item_text(project_picker.selected) if project_picker.selected>=0 else ""
	project_picker.clear()
	for row in desktop._file_rows():
		var path:=str(row.path)
		if path.ends_with(".circuit"):
			project_picker.add_item(path)
			if selected==path:project_picker.select(project_picker.item_count-1)

func _open() -> void:
	if project_picker.selected<0:return
	var path:=project_picker.get_item_text(project_picker.selected)
	var record: Variant=JSON.parse_string(str(desktop._file(path).get("text","")))
	if record is Dictionary and record.get("type")=="campus-circuit-1" and record.get("values") is Array:_apply(record.values)
	else:results.text="This file is not a Campus Circuit Lab project."

func _apply(numbers: Array) -> void:
	if numbers.size()!=7:return
	for value in numbers:
		if not (value is int or value is float) or not is_finite(float(value)):return
	source.select(clampi(int(numbers[0]),0,1))
	topology.select(clampi(int(numbers[1]),0,1))
	for index in values.size():values[index].set_value_no_signal(clampf(float(numbers[index+2]),0,values[index].max_value))
	_calculate()
