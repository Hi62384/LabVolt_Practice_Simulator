extends SceneTree
## The guide must be accessible in the actual Circuit Maker selection inspector,
## not only from the separate component shop.
const Board=preload("res://scripts/breadboard_model.gd")
const Catalog=preload("res://scripts/electronics_catalog.gd")
const Workspace=preload("res://scripts/electronics/circuit_workspace/workspace.gd")
const Panels=preload("res://scripts/electronics/contextual_panels/panel_host.gd")
const Guide=preload("res://scripts/electronics/component_shop_ui/guide_content.gd")

func _initialize() -> void:call_deferred("_run")

func _run() -> void:
	var catalogue: Dictionary=Catalog.all()
	var led: Dictionary=catalogue.get("led",{})
	assert(not led.is_empty() and not Guide.lesson(led).is_empty(),
		"The advertised LED must provide meaningful component instructions")
	var board: Dictionary=Board.empty()
	board.parts=[{"id":"test_led","type":"led","a":"A1","b":"F1"}]
	assert(Board.validate(board,{},true)=="")
	var workspace:=Workspace.new()
	root.add_child(workspace)
	workspace.configure_maker(board,{},catalogue,{},true)
	var panels:=Panels.new()
	workspace.sidebar.add_child(panels)
	panels.configure(workspace,{"catalog":catalogue,"profile":{},"creative":true,"limits":{}},{})
	await process_frame
	workspace.canvas.selected=["test_led"]
	workspace.canvas.refresh_selection()
	await process_frame
	assert(panels.inspector.visible and not panels.picker.visible,
		"Selecting a component body must show the inspector instead of the parts picker")
	var guide_buttons: Array=panels.inspector.find_children("*","Button",true,false).filter(
		func(button):return button.text=="Guide")
	assert(guide_buttons.size()==1,
		"Selected component must expose a Guide action inside Circuit Maker")
	var hidden_sections: Array=panels.inspector.content.get_children().filter(
		func(node):return node is VBoxContainer and not node.visible and node.get_child_count()>0)
	assert(not hidden_sections.is_empty(),"Component guide instructions must be mounted in the inspector")
	guide_buttons[0].pressed.emit()
	assert(hidden_sections[0].visible,
		"Guide button did not reveal the in-editor component instructions")
	assert(hidden_sections[0].get_child_count()>=Guide.lesson(led).size(),
		"Guide content is truncated or missing")
	workspace.queue_free()
	await process_frame
	print("COMPONENT_GUIDE_IN_BUILDER PASS")
	quit()
