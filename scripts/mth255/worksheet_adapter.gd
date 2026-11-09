extends VBoxContainer
## MTH255-only composition. The shared widget still owns all mathematics input.
const Circuit=preload("res://scripts/mth255/impedance_view.gd")
signal changed(state: Dictionary)
signal reference_requested(section: String)
signal model_parameters_changed(parameters: Dictionary)
signal demonstration_changed(data: Dictionary)
var workspace: Control
var unavailable: Label
var _complex_input=false
func configure(problem: Dictionary,editable: bool,policy: Dictionary={},parse_callable: Callable=Callable()) -> void:
	add_theme_constant_override("separation",12)
	for child in get_children():remove_child(child);child.queue_free()
	workspace=null;unavailable=null;_complex_input=problem.get("input",{}).get("kind","")=="complex"
	if not ResourceLoader.exists("res://scripts/math_ui/workspace.gd"):
		unavailable=Label.new();unavailable.text="The shared mathematics worksheet is unavailable. The host must finish course installation before starting this assessment.";unavailable.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;add_child(unavailable);return
	var data=problem.duplicate(true)
	var badge=preload("res://scripts/ui/design_system/widgets.gd").badge("Answer workspace" if editable else "Returned worksheet · read only","course")
	badge.theme=preload("res://scripts/ui/design_system/theme.gd").create();add_child(badge)
	if data.get("diagram",{}).get("kind","")=="circuit":
		var schematic := PanelContainer.new();schematic.theme=preload("res://scripts/ui/design_system/theme.gd").create();schematic.theme_type_variation="CardPanel";add_child(schematic)
		var circuit_scroll := ScrollContainer.new();circuit_scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_AUTO;schematic.add_child(circuit_scroll)
		var circuit=Circuit.new();circuit.configure(data.diagram);circuit.tooltip_text="Generated ideal impedance circuit · values are supplied by this question";circuit_scroll.add_child(circuit);data.erase("diagram")
	workspace=load("res://scripts/math_ui/workspace.gd").new();add_child(workspace)
	workspace.changed.connect(func(state):changed.emit(state))
	workspace.reference_requested.connect(func(section):reference_requested.emit(section))
	if workspace.has_signal("demonstration_parameters_changed"):workspace.connect("demonstration_parameters_changed",func(parameters):model_parameters_changed.emit(parameters))
	if workspace.has_signal("demonstration_changed"):workspace.connect("demonstration_changed",func(data):demonstration_changed.emit(data))
	workspace.configure(data,editable,policy,parse_callable)
func answer() -> Variant:
	if not is_instance_valid(workspace):return {}
	var result=workspace.answer()
	if _complex_input and result is Dictionary:
		result=result.duplicate(true);result.angle_unit=workspace.angle_unit.get_item_text(workspace.angle_unit.selected);result.form=workspace.complex_form.get_item_text(workspace.complex_form.selected)
	return result
func snapshot() -> Dictionary:
	if not is_instance_valid(workspace):return {"error":"Shared mathematics UI unavailable."}
	var state=workspace.snapshot();state.answer=answer();return state
func restore(state: Dictionary) -> bool:
	return workspace.restore(state) if is_instance_valid(workspace) else false
