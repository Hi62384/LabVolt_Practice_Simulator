extends VBoxContainer
const Chrome = preload("res://scripts/ui/circuit_editor_panels/chrome.gd")
signal saved(message: String)
const Document=preload("res://scripts/pcb_design/document.gd")
const Design=preload("res://scripts/pcb_design/design.gd")
var document=Document.new()
var view: Control
var status: Label
var feedback: Label
var help: Label
var route_list: OptionButton
var vertex_list: OptionButton
var vertex_x: SpinBox
var vertex_y: SpinBox
var outline_tools: Control
var trace_tools: Control
var component_tools: Control
var mode: OptionButton
var outline_group: PanelContainer
var copper_group: PanelContainer
func button(parent: Node,title: String,action: Callable) -> Button:
	return Chrome.action(parent,title,action)
func field_label(parent: Node,text: String) -> void:
	var label:=Label.new();label.text=text;parent.add_child(label)
func feedback_message(message: String) -> void:
	feedback.text=message
	feedback.modulate=Color("f5a4a0") if "rejected" in message or "Cannot" in message or "at least" in message or "up to" in message else Color("b4e5d1")
func refresh_vertex_controls() -> void:
	vertex_list.clear()
	var points: Array=document.blueprint.pcb_design.outline
	view.selected_vertex=clampi(view.selected_vertex,0,points.size()-1)
	for index in points.size():vertex_list.add_item("Point "+str(index+1))
	vertex_list.select(view.selected_vertex)
	vertex_x.value=float(points[view.selected_vertex][0]);vertex_y.value=float(points[view.selected_vertex][1])
	vertex_x.max_value=float(document.blueprint.footprint.width)-1
	vertex_y.max_value=float(document.blueprint.footprint.height)-1
func refresh() -> void:
	status.text=(document.error+"  " if document.error!="" else "")+str(Design.unrouted(document.blueprint))+" connections still need copper. Save creates a new board copy."
	route_list.clear()
	for index in document.blueprint.pcb_design.routes.size():
		var route: Dictionary=document.blueprint.pcb_design.routes[index]
		route_list.add_item("Trace "+str(index+1)+" · "+str(route.a)+" → "+str(route.b))
	refresh_vertex_controls();view.queue_redraw()
func change_mode(index: int) -> void:
	document.error=""
	view.set_outline_mode(index==0)
	outline_tools.visible=index==0;trace_tools.visible=index==1;component_tools.visible=index==1
	outline_group.visible=index==0;copper_group.visible=index==1
	help.text="Drag a numbered edge point to shape the board. Double-click an edge to add a point. Red edges cannot be placed. Wheel zooms; middle drag pans. Right click cancels a move." if index==0 else "Click a pad, optional bends, then a highlighted pad to route copper. Right click cancels. Wheel zooms; middle drag pans. Removing copper opens its circuit connection."
	feedback_message("Select an edge point to begin." if index==0 else "Select a copper pad to begin.")
	refresh()
func build(profile: RefCounted,bp: Dictionary) -> void:
	Chrome.setup(self)
	document.open(bp)
	var title:=Label.new();title.text="PCB DESIGN";title.add_theme_font_size_override("font_size",22);add_child(title)
	help=Label.new();help.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;add_child(help)
	var tools:=HFlowContainer.new();add_child(tools)
	mode=OptionButton.new();mode.add_item("Board outline");mode.add_item("Copper routing");tools.add_child(mode)
	button(tools,"Undo",func():view.cancel_outline_drag();document.undo();feedback_message("Previous edit restored");refresh())
	button(tools,"Redo",func():view.cancel_outline_drag();document.redo();feedback_message("Edit reapplied");refresh())
	button(tools,"Save board copy",func():
		var message: String=document.save_copy(profile)
		if message.begins_with("Blueprint saved: "):message="Board copy saved. Find it in the IC / PCB builder."
		saved.emit(message);feedback_message(message);refresh()
	)
	status=Label.new();status.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;add_child(status)
	outline_tools=HFlowContainer.new();add_child(outline_tools)
	vertex_list=OptionButton.new();outline_tools.add_child(vertex_list)
	field_label(outline_tools,"X")
	vertex_x=SpinBox.new();vertex_x.min_value=0;vertex_x.max_value=79;vertex_x.step=.05;vertex_x.custom_minimum_size.x=85;outline_tools.add_child(vertex_x)
	field_label(outline_tools,"Y")
	vertex_y=SpinBox.new();vertex_y.min_value=0;vertex_y.max_value=79;vertex_y.step=.05;vertex_y.custom_minimum_size.x=85;outline_tools.add_child(vertex_y)
	button(outline_tools,"Move point",func():view.move_selected([vertex_x.value,vertex_y.value]);refresh())
	button(outline_tools,"Add point after",func():view.add_vertex_after();refresh())
	button(outline_tools,"Remove point",func():view.remove_selected_vertex();refresh())
	field_label(outline_tools,"Snap")
	var snap:=OptionButton.new()
	for value in [.05,.1,.25,.5,1.0]:snap.add_item(str(value)+" grid")
	snap.select(2);outline_tools.add_child(snap)
	snap.item_selected.connect(func(index):view.snap_step=[.05,.1,.25,.5,1.0][index];vertex_x.step=view.snap_step;vertex_y.step=view.snap_step)
	var sizes:=CheckButton.new();sizes.text="Board size and thickness";add_child(sizes)
	var dimensions:=HFlowContainer.new();dimensions.visible=false;add_child(dimensions)
	sizes.toggled.connect(func(enabled):dimensions.visible=enabled)
	field_label(dimensions,"Width (grid)")
	var width:=SpinBox.new();width.min_value=2;width.max_value=80;width.value=document.blueprint.footprint.width;dimensions.add_child(width)
	field_label(dimensions,"Length (grid)")
	var height:=SpinBox.new();height.min_value=2;height.max_value=80;height.value=document.blueprint.footprint.height;dimensions.add_child(height)
	field_label(dimensions,"Thickness (mm)")
	var thickness:=SpinBox.new();thickness.min_value=.1;thickness.max_value=100;thickness.step=.1;thickness.value=document.blueprint.footprint.get("thickness_mm",1.6);dimensions.add_child(thickness)
	button(dimensions,"Apply size",func():document.resize(int(width.value),int(height.value),thickness.value);refresh())
	trace_tools=HFlowContainer.new();add_child(trace_tools)
	route_list=OptionButton.new();trace_tools.add_child(route_list)
	button(trace_tools,"Remove selected trace",func():document.remove_route(route_list.selected);refresh())
	component_tools=HFlowContainer.new();add_child(component_tools)
	var pads:=OptionButton.new()
	for id in document.blueprint.pcb_design.pads:pads.add_item(id)
	component_tools.add_child(pads)
	field_label(component_tools,"X")
	var x:=SpinBox.new();x.min_value=0;x.max_value=80;x.step=.05;component_tools.add_child(x)
	field_label(component_tools,"Y")
	var y:=SpinBox.new();y.min_value=0;y.max_value=80;y.step=.05;component_tools.add_child(y)
	pads.item_selected.connect(func(_i):var pos: Array=document.blueprint.pcb_design.pads[pads.text].position;x.value=pos[0];y.value=pos[1])
	if pads.item_count>0:
		var pos: Array=document.blueprint.pcb_design.pads[pads.text].position;x.value=pos[0];y.value=pos[1]
	button(component_tools,"Move component / land",func():document.move_pad(pads.text,[x.value,y.value]);refresh())
	button(component_tools,"Rotate component 90°",func():document.rotate_component(pads.text.substr(2,pads.text.rfind(":")-2) if pads.text.begins_with("p:") else "");refresh())
	feedback=Label.new();feedback.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;add_child(feedback)
	view=preload("res://scripts/pcb_design/route_canvas.gd").new();view.document=document;add_child(view)
	view.edited.connect(refresh)
	view.vertex_selected.connect(func(_index):refresh_vertex_controls())
	view.outline_feedback.connect(feedback_message)
	vertex_list.item_selected.connect(func(index):view.select_vertex(index))
	mode.item_selected.connect(change_mode)
	Chrome.labeled(mode,"Editing workflow")
	Chrome.labeled(vertex_list,"Outline point")
	Chrome.labeled(route_list,"Copper trace")
	Chrome.labeled(pads,"Component or land")
	Chrome.labeled(snap,"Outline snap · grid units")
	Chrome.section(self,"Board workflow", "circuit", tools, status)
	outline_group=Chrome.section(self,"Outline geometry", "settings", outline_tools, outline_tools)
	Chrome.section(self,"Board dimensions", "settings", sizes, dimensions)
	copper_group=Chrome.section(self,"Copper and placement", "component", trace_tools, component_tools)
	Chrome.section(self,"Edit feedback", "info", feedback, feedback)
	Chrome.finish(self)
	change_mode(0)
