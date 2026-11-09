extends PanelContainer
signal action_requested(operation: String, payload: Dictionary)
const UI = preload("res://scripts/ui/design_system/widgets.gd")
const Debug = preload("res://scripts/electronics/circuit_workspace/debug_instruments.gd")
const Values = preload("res://scripts/electronics/component_values/values.gd")
var content: VBoxContainer
var validator := Callable()
var selected := {}

func _ready() -> void:
	custom_minimum_size.x=260
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	content=VBoxContainer.new()
	content.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	scroll.add_child(content)
	hide()

func bind_selection(part: Dictionary, definition: Dictionary = {}, edit_validator: Callable = Callable(), read_only_nominal := false) -> void:
	selected=part.duplicate(true);validator=edit_validator
	for child in content.get_children():content.remove_child(child);child.queue_free()
	if part.is_empty():hide();return
	show()
	var kind := str(part.get("type",""))
	content.add_child(UI.header(str(definition.get("name",kind)),"Selected component",clear_selection))
	var picture := TextureRect.new()
	picture.custom_minimum_size = Vector2(0,80)
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	picture.texture = preload("res://scripts/electronics/component_shop_ui/catalog_presentation.gd").preview(definition)
	content.add_child(picture)
	var specification := UI.text(str(definition.get("rating","")),"MutedLabel")
	specification.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(specification)
	if part.has("a") and part.has("b"):
		var labels := preload("res://scripts/electronics_catalog.gd").polarity_labels(definition)
		var pins := preload("res://scripts/breadboard_model.gd").pins(part)
		if not labels.is_empty() and pins.size()==2:
			for index in 2:
				content.add_child(UI.text("%s · %s" % [definition.pins[index],pins[index]]))
		else:
			content.add_child(UI.badge("%s ↔ %s"%[part.a,part.b],"circuit"))
	var properties := Values.fields(definition)
	var debug_settings := Debug.settings(kind)
	for key in debug_settings:
		var value: Variant=part.get("debug",{}).get(key,debug_settings[key])
		if Debug.CHOICES.has(key):
			_add_debug_choice(key,value)
			continue
		var field := UI.field(key.capitalize(),str(value))
		field.get_node("Input").text=str(value)
		content.add_child(field)
		field.get_node("Input").text_submitted.connect(func(value: String):_submit_property(key,value,field))
	for key in properties:
		var spec: Dictionary=properties[key]
		if not part.has(key) and not definition.has(key):continue
		var raw: Variant=part.get(key,definition.get(key))
		var read_only_field: bool = read_only_nominal and (key=="value" or (key=="frequency" and definition.get("kind","")=="portable_source"))
		if read_only_field:raw=definition.get(key,raw)
		var display := Values.format_value(float(raw),str(spec.get("unit",""))) if raw is float or raw is int else str(raw)
		if read_only_field:
			content.add_child(UI.text("%s · %s" % [spec.get("label",key),display]))
			continue
		var field := UI.field(str(spec.get("label",key)),display,str(spec.get("help","")))
		field.get_node("Input").text=display
		content.add_child(field)
		field.get_node("Input").text_submitted.connect(func(value: String):_submit_property(key,value,field))
	var actions := HFlowContainer.new();content.add_child(actions)
	actions.add_child(UI.action("Rotate","refresh",func():action_requested.emit("rotate",{"id":part.get("id","")})))
	actions.add_child(UI.action("Copy","plus",func():action_requested.emit("copy",{"id":part.get("id","")})))
	actions.add_child(UI.action("Delete Component","trash",func():action_requested.emit("remove",{"id":part.get("id","")})))
	if kind in ["lv_mcu","native_uno","native_nano","native_pico"]:
		actions.add_child(UI.action("Edit code","code",func():action_requested.emit("code",{"id":part.get("id","")})))
	if definition.has("pins"):
		var advanced := VBoxContainer.new();advanced.visible=false;content.add_child(advanced)
		advanced.add_child(UI.text("Pins: "+", ".join(definition.pins.map(func(pin):return str(pin))),"MutedLabel"))
		actions.add_child(UI.action("Pin details","info",func():advanced.visible=not advanced.visible))

func _add_debug_choice(key: String, value: Variant) -> void:
	var title := "Waveform" if key=="wave" else "Measurement"
	content.add_child(UI.text(title))
	var picker := OptionButton.new()
	picker.accessibility_name=title
	picker.custom_minimum_size.y=44
	picker.disabled=not validator.is_valid()
	var parsed := Debug.parse_field(key,value)
	var choices: Dictionary=Debug.CHOICES[key]
	for option in choices:
		var details: Array=choices[option]
		picker.add_icon_item(UI.icon(details[1]),details[0])
		var index := picker.item_count-1
		picker.set_item_metadata(index,option)
		if parsed.ok and parsed.value==option:picker.select(index)
	content.add_child(picker)
	var feedback := UI.text("","ErrorLabel")
	feedback.hide()
	content.add_child(feedback)
	picker.item_selected.connect(func(index: int):
		var result: Dictionary=validator.call(selected.duplicate(true),key,str(picker.get_item_metadata(index)))
		if not result.get("ok",false):
			feedback.text=str(result.get("error","Invalid value"))
			feedback.show()
			return
		feedback.hide()
		action_requested.emit("property",{"id":selected.get("id",""),"key":key,"value":result.value}))

func _submit_property(key: String, raw: String, field: VBoxContainer) -> void:
	if not validator.is_valid():UI.field_error(field,"Editing unavailable here.");return
	var result: Dictionary=validator.call(selected.duplicate(true),key,raw)
	if not result.get("ok",false):UI.field_error(field,str(result.get("error","Invalid value")));return
	UI.field_error(field,"")
	action_requested.emit("property",{"id":selected.get("id",""),"key":key,"value":result.value})

func clear_selection() -> void:
	selected={};hide();action_requested.emit("clear_selection",{})
