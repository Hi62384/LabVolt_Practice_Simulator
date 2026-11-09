extends SceneTree
const P=preload("res://scripts/mth255/provider.gd")
const Widget=preload("res://scripts/mth255/worksheet_adapter.gd")
var failures=0
func check(ok: bool,message: String) -> void:
	if not ok:failures+=1;print("FAIL "+message)
func text(value: Variant) -> String:
	return value if value is String else JSON.stringify(value)
func significant(value: float) -> String:
	var places=3-int(floor(log(value)/log(10)));var scale=pow(10,places);var rounded=round(value*scale)/scale;var out=String.num(rounded,maxi(0,places))
	if out.contains("."):
		while out.get_slice(".",1).length()<places:out+="0"
	return out
func fill(widget: Control,p: Dictionary) -> void:
	var w=widget.workspace;var key=p.answer;var kind=p.input.kind
	if p.expected_form=="system_points":
		for i in range(2):
			w.fields["x"+str(i+1)].set_value(text(key.points[i].x));w.fields["y"+str(i+1)].set_value(text(key.points[i].y))
	elif kind in ["graph","complex_plane"]:
		for point in key.points:w.graph.add_point(point.x,point.y,"point")
	elif kind=="statistics_table":w.table.configure({"columns":p.input.columns,"rows":key.rows},true)
	elif kind=="complex_roots":
		while w.roots_editors.size()<key.values.size():w._add_root()
		for i in range(key.values.size()):w.roots_editors[i].real.set_value(text(key.values[i].real));w.roots_editors[i].imag.set_value(text(key.values[i].imag))
	else:
		for field in key:
			if not w.fields.has(field):check(false,"missing widget field "+p.generator_id+"."+field);continue
			var value=key[field]
			if value is Array:
				var parts=[]
				for entry in value:parts.append(text(entry))
				w.fields[field].set_value("{"+",".join(parts)+"}")
			elif p.rubric.get("field_forms",{}).has(field):w.fields[field].set_value(significant(value))
			else:w.fields[field].set_value(text(value))
func _initialize() -> void:
	var provider=P.new();provider._core();var tested=0
	var parse_callable=func(source):return provider.core.parse(source)
	for group in provider.TOPICS:
		for topic in group:
			for d in range(5):
				var problem=provider.generate_problem(topic,d,455+d)
				if problem.has("error"):check(false,"generation "+topic+" "+str(problem));continue
				var public_problem=provider.public_problem(problem);var widget=Widget.new();root.add_child(widget);widget.configure(public_problem,true,{"formula_allowed":false},parse_callable)
				check(is_instance_valid(widget.workspace),"shared workspace mounted "+topic)
				check(not provider.check(problem,widget.answer()).correct,"no initial answer prefill "+topic)
				if is_instance_valid(widget.workspace.graph):check(widget.workspace.graph.points.is_empty() or topic=="complex_convert","no reference points in student graph "+topic)
				fill(widget,problem);var submitted=widget.answer();var marked=provider.check(problem,submitted)
				check(marked.correct,"widget answer "+topic+" d"+str(d)+" "+str(submitted)+" "+str(marked))
				var saved=JSON.parse_string(JSON.stringify(widget.snapshot()));var restored=Widget.new();root.add_child(restored);restored.configure(public_problem,true,{"formula_allowed":false},parse_callable)
				check(restored.restore(saved),"widget restore "+topic);check(provider.check(problem,restored.answer()).correct,"restored answer "+topic)
				if topic in ["impedance","impedance_network"]:check(widget.get_child(0) is Control and widget.get_child_count()==2,"course circuit view composition")
				widget.free();restored.free();tested+=1

	var reference=provider.formula_reference();var reference_widget=Widget.new();root.add_child(reference_widget);var question=provider.public_problem(provider.generate_problem("j_power",0,44))
	reference_widget.configure(question,false,{"formula_allowed":true,"formula_sections":reference.sections},parse_callable)
	var formula_count=0
	for i in range(reference.sections.size()):
		reference_widget.workspace.reference_choice.item_selected.emit(i+1)
		formula_count+=reference.sections[i].formulas.size()
		check(reference_widget.workspace.reference_panel.get_child_count()>=reference.sections[i].formulas.size()*2,"typeset formula section "+str(i))
	var reference_state=JSON.parse_string(JSON.stringify(reference_widget.snapshot()));var denied=Widget.new();root.add_child(denied);denied.configure(question,false,{"formula_allowed":false,"formula_sections":reference.sections},parse_callable)
	check(denied.restore(reference_state) and denied.workspace.reference_section.is_empty() and not is_instance_valid(denied.workspace.reference_choice),"host denies restored formula access")
	check(formula_count==45,"all 45 structured formula definitions")
	reference_widget.free();denied.free()
	print("MTH255_SHARED_WIDGETS cases=%d failures=%d"%[tested,failures]);quit(0 if failures==0 else 1)
