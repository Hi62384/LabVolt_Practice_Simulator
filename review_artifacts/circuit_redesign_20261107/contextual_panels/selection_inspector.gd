extends PanelContainer
signal action_requested(operation: String, payload: Dictionary)
const UI = preload("res://scripts/ui/design_system/widgets.gd")
const Values = preload("res://scripts/electronics/component_values/values.gd")
var content: VBoxContainer
var validator := Callable()
var selected := {}

func _ready() -> void:
	custom_minimum_size.x=260
	content=VBoxContainer.new();add_child(content)
	hide()

func bind_selection(part: Dictionary, definition: Dictionary = {}, edit_validator: Callable = Callable()) -> void:
	selected=part.duplicate(true);validator=edit_validator
	for child in content.get_children():content.remove_child(child);child.queue_free()
	if part.is_empty():hide();return
	show()
	var kind := str(part.get("type",""))
	content.add_child(UI.header(str(definition.get("name",kind)),"Selected component",clear_selection))
	if part.has("a") and part.has("b"):
		content.add_child(UI.badge("%s ↔ %s"%[part.a,part.b],"circuit"))
	var properties := Values.fields(definition)
	for key in properties:
		var spec: Dictionary=properties[key]
		if not part.has(key) and not definition.has(key):continue
		var raw: Variant=part.get(key,definition.get(key))
		var display := Values.format_value(float(raw),str(spec.get("unit",""))) if raw is float or raw is int else str(raw)
		var field := UI.field(str(spec.get("label",key)),display,str(spec.get("help","")))
		field.get_node("Input").text=display
		content.add_child(field)
		field.get_node("Input").text_submitted.connect(func(value: String):_submit_property(key,value,field))
	var actions := HFlowContainer.new();content.add_child(actions)
	actions.add_child(UI.action("Rotate","refresh",func():action_requested.emit("rotate",{"id":part.get("id","")})))
	actions.add_child(UI.action("Copy","plus",func():action_requested.emit("copy",{"id":part.get("id","")})))
	actions.add_child(UI.action("Remove","trash",func():action_requested.emit("remove",{"id":part.get("id","")})))
	if kind in ["lv_mcu","native_uno","native_nano","native_pico"]:
		actions.add_child(UI.action("Edit code","code",func():action_requested.emit("code",{"id":part.get("id","")})))
	if definition.has("pins"):
		var advanced := VBoxContainer.new();advanced.visible=false;content.add_child(advanced)
		advanced.add_child(UI.text("Pins: "+", ".join(definition.pins.map(func(pin):return str(pin))),"MutedLabel"))
		actions.add_child(UI.action("Pin details","info",func():advanced.visible=not advanced.visible))

func _submit_property(key: String, raw: String, field: VBoxContainer) -> void:
	if not validator.is_valid():UI.field_error(field,"Editing unavailable here.");return
	var result: Dictionary=validator.call(selected.duplicate(true),key,raw)
	if not result.get("ok",false):UI.field_error(field,str(result.get("error","Invalid value")));return
	UI.field_error(field,"")
	action_requested.emit("property",{"id":selected.get("id",""),"key":key,"value":result.value})

func clear_selection() -> void:
	selected={};hide();action_requested.emit("clear_selection",{})
