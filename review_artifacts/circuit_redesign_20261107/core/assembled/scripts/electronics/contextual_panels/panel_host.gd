extends Control
## Mount under the core workspace. Uses its real panel/selection signals.
const UI = preload("res://scripts/ui/design_system/widgets.gd")
var workspace: Control
var context := {}
var actions := {}
var picker: PanelContainer
var inspector: PanelContainer
var analyzer: PanelContainer
var bench: PanelContainer
var status: PanelContainer

func configure(source: Control, data: Dictionary, callbacks: Dictionary) -> void:
	workspace=source;context=data;actions=callbacks
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter=Control.MOUSE_FILTER_IGNORE
	picker=_make("component_picker.gd")
	inspector=_make("selection_inspector.gd")
	analyzer=_make("analyzer_panel.gd")
	bench=_make("bench_connections.gd")
	status=_make("status_help.gd")
	status.show()
	picker.configure(context.get("profile",{}),context.get("catalog",{}),context.get("limits",{}),bool(context.get("creative",false)))
	picker.chosen.connect(func(type_id: String, instance_id: String):
		workspace.choose_component(type_id)
		if instance_id!="" and actions.get("record_instance",Callable()).is_valid():actions.record_instance.call(type_id,instance_id))
	inspector.action_requested.connect(_inspector_action)
	analyzer.bind_canvas(workspace.canvas,bool(context.get("analyzer_allowed",false)))
	analyzer.tool_changed.connect(func(tool: String):workspace.choose_component(tool))
	workspace.panel_requested.connect(_open_panel)
	workspace.selection_changed.connect(_selection_changed)
	resized.connect(_layout)
	_layout()

func _make(name: String) -> PanelContainer:
	var path := (get_script() as Script).resource_path.get_base_dir().path_join(name)
	var panel := load(path).new() as PanelContainer
	add_child(panel);panel.hide();return panel

func _layout() -> void:
	var width := minf(380,size.x*0.40)
	for panel in [picker,inspector,analyzer,bench]:
		if not is_instance_valid(panel):continue
		panel.size=Vector2(width,minf(570,size.y-100))
		panel.position=Vector2(maxf(0,size.x-width-12),64)
	if is_instance_valid(status):
		status.position=Vector2(12,maxf(0,size.y-56));status.size=Vector2(minf(320,size.x-24),44)

func _open_panel(kind: String) -> void:
	for panel in [picker,inspector,bench]:
		if is_instance_valid(panel):panel.hide()
	if is_instance_valid(analyzer):analyzer.close_panel()
	match kind:
		"components":picker.open_picker()
		"analyzer":analyzer.open_panel()
		"bench":
			bench.configure(workspace.canvas.board.get("ports",[]),int(workspace.canvas.board.get("rows",10)),actions.get("validate_port",Callable()),actions.get("apply_port",Callable()))
			bench.open_panel()
		"projects":
			if actions.get("open_projects",Callable()).is_valid():actions.open_projects.call()

func _selection_changed(ids: Array) -> void:
	if ids.size()!=1:inspector.bind_selection({});return
	for part in workspace.canvas.board.get("parts",[]):
		if str(part.get("id",""))==str(ids[0]):
			var definition: Dictionary=context.get("catalog",{}).get(str(part.get("type","")),{})
			inspector.bind_selection(part,definition,actions.get("validate_property",Callable()))
			return
	inspector.bind_selection({})

func _inspector_action(op: String, payload: Dictionary) -> void:
	match op:
		"rotate":workspace.canvas.transform_selected(0,0,true)
		"remove":workspace.canvas.delete_selected();inspector.bind_selection({})
		"copy":workspace.canvas.copy_selected()
		"code":workspace.canvas.code_requested.emit(str(payload.get("id","")))
		"clear_selection":workspace.canvas.selected.clear();workspace.canvas.queue_redraw()
		"property":
			if actions.get("apply_property",Callable()).is_valid():
				var result: Dictionary=actions.apply_property.call(payload)
				if not result.get("ok",false):set_status("invalid",str(result.get("error","Could not update component")))

func set_status(code: String, detail: String) -> void:
	if is_instance_valid(status):status.set_status(code,detail)

func refresh_measurement() -> void:
	if is_instance_valid(analyzer):analyzer.refresh_reading()
