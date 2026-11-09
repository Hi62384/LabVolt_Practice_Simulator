class_name CosmeticParameterPanel
extends ScrollContainer
const CatalogAdapter = preload("res://scripts/avatar_cosmetics/ui/catalog_adapter.gd")
const Tokens = preload("res://scripts/ui/design_system/tokens.gd")

signal parameter_changed(key: String, value: Variant)

var _content: VBoxContainer

func _ready() -> void:
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_content = VBoxContainer.new()
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_theme_constant_override("separation", 8)
	add_child(_content)

func show_schema(definition: Dictionary, values: Dictionary) -> void:
	if _content == null:
		return
	for child in _content.get_children():
		_content.remove_child(child)
		child.queue_free()
	var schema := CatalogAdapter.supported_parameters(definition)
	visible = not schema.is_empty()
	for key in schema:
		var caption := str(key).replace("_", " ").capitalize()
		if definition.get("category") == "hair":
			if key == "color": caption = "Color 1 · Base"
			if key == "highlight": caption = "Color 2 · Highlights"
			if key == "tip_color": caption = "Color 3 · Tips"
		_add_field(str(key), caption, schema[key], values.get(key, schema[key].get("default")))
	scroll_vertical = 0

func _add_field(key: String, caption: String, spec: Dictionary, current: Variant) -> void:
	var title := Label.new()
	title.text = caption
	title.theme_type_variation = &"MutedLabel"
	_content.add_child(title)
	match str(spec.type):
		"float", "int":
			var slider := HSlider.new()
			slider.min_value = float(spec.min)
			slider.max_value = float(spec.max)
			slider.step = 1.0 if spec.type == "int" else float(spec.get("step", 0.01))
			slider.value = float(current)
			title.text += "  ·  %.2f" % slider.value
			slider.custom_minimum_size.y = 32
			slider.value_changed.connect(func(value: float):
				title.text = caption + "  ·  %.2f" % value
				parameter_changed.emit(key, int(value) if spec.type == "int" else value))
			_content.add_child(slider)
		"bool":
			var toggle := CheckButton.new()
			toggle.button_pressed = bool(current)
			toggle.toggled.connect(func(value: bool): parameter_changed.emit(key, value))
			_content.add_child(toggle)
		"enum":
			if key == "length":
				_add_length_slider(title, spec.values, current)
				return
			var choices := OptionButton.new()
			for option in spec.values:
				choices.add_item(str(option).capitalize())
				choices.set_item_metadata(choices.item_count - 1, option)
				if option == current:
					choices.select(choices.item_count - 1)
			choices.item_selected.connect(func(index: int): parameter_changed.emit(key, choices.get_item_metadata(index)))
			_content.add_child(choices)
		"color":
			var picker := ColorPickerButton.new()
			picker.edit_alpha = false
			picker.color = Color.from_string(str(current), Color.WHITE)
			picker.custom_minimum_size.y = Tokens.HIT_HEIGHT
			picker.accessibility_name = title.text
			_content.add_child(picker)
			var swatch := PanelContainer.new()
			swatch.mouse_filter = Control.MOUSE_FILTER_IGNORE
			picker.add_child(swatch)
			swatch.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			swatch.offset_left = 5
			swatch.offset_top = 5
			swatch.offset_right = -5
			swatch.offset_bottom = -5
			var hex := Label.new()
			hex.mouse_filter = Control.MOUSE_FILTER_IGNORE
			hex.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			swatch.add_child(hex)
			_update_swatch(swatch, hex, picker.color)
			picker.color_changed.connect(func(value: Color):
				_update_swatch(swatch, hex, value)
				parameter_changed.emit(key, value.to_html(false)))

func _update_swatch(swatch: PanelContainer, label: Label, value: Color) -> void:
	swatch.add_theme_stylebox_override("panel", Tokens.surface(value, value, 2))
	label.text = "#" + value.to_html(false).to_upper()
	label.add_theme_color_override("font_color", Color.BLACK if value.srgb_to_linear().get_luminance() > .179 else Color.WHITE)

func _add_length_slider(title: Label, values: Array, current: Variant) -> void:
	var slider := HSlider.new()
	slider.custom_minimum_size.y = 32
	slider.max_value = values.size() - 1
	slider.step = 1
	slider.tick_count = values.size()
	slider.ticks_on_borders = true
	slider.value = maxi(0, values.find(current))
	slider.accessibility_name = "Length"
	title.text = "Length · " + str(values[int(slider.value)]).capitalize()
	slider.value_changed.connect(func(value: float):
		var length: String = values[int(value)]
		title.text = "Length · " + length.capitalize()
		parameter_changed.emit("length", length))
	_content.add_child(slider)
