extends RefCounted
## Instrument chrome only: all electrical commands stay with the caller.
const UI = preload("res://scripts/ui/design_system/widgets.gd")
const Grid = preload("res://scripts/ui/design_system/responsive_grid.gd")

static func section(parent: Node, title: String, detail: String, icon: String) -> VBoxContainer:
	var card := UI.card(title, detail, icon)
	parent.add_child(card)
	card.get_node("Content/Copy/Rarity").hide()
	var header := card.get_node("Content")
	card.remove_child(header)
	var stack := VBoxContainer.new()
	card.add_child(stack)
	stack.add_child(header)
	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stack.add_child(body)
	return body

static func grid(parent: Node, width := 290.0, count := 3) -> GridContainer:
	var grid := Grid.new()
	grid.minimum_card_width = width
	grid.maximum_columns = count
	parent.add_child(grid)
	return grid

static func page(tabs: TabContainer, title: String, icon: String) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.name = title
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tabs.add_child(scroll)
	tabs.set_tab_icon(tabs.get_tab_count()-1, UI.icon(icon))
	tabs.get_tab_bar().add_theme_constant_override("icon_max_width", 22)
	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(body)
	return body

static func number(parent: Node, caption: String, value: float, minimum: float, maximum: float, step: float) -> SpinBox:
	var field := VBoxContainer.new()
	parent.add_child(field)
	field.add_child(UI.text(caption))
	var spin := SpinBox.new()
	spin.min_value = minimum
	spin.max_value = maximum
	spin.step = step
	spin.set_value_no_signal(value)
	spin.custom_minimum_size.y = 44
	spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spin.tooltip_text = "%s · range %s to %s · step %s" % [caption, minimum, maximum, step]
	spin.get_line_edit().tooltip_text = spin.tooltip_text
	field.add_child(spin)
	var hint := "%s – %s · step %s · Enter to apply" % [minimum, maximum, step]
	var feedback := UI.text(hint, "MutedLabel")
	field.add_child(feedback)
	# Inspect syntax only; SpinBox retains its native parsing/clamping and callbacks.
	spin.get_line_edit().text_changed.connect(func(text: String):
		var expression := Expression.new()
		var valid := expression.parse(text) == OK
		feedback.text = hint if valid else "Enter a number or arithmetic expression within the range above."
		feedback.theme_type_variation = "MutedLabel" if valid else "ErrorLabel"
		spin.get_line_edit().theme_type_variation = "LineEdit" if valid else "ErrorLineEdit"
	)
	return spin

static func selector(parent: Node, caption: String) -> VBoxContainer:
	var field := VBoxContainer.new()
	parent.add_child(field)
	field.add_child(UI.text(caption))
	return field
