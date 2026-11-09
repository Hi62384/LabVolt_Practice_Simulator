extends RefCounted
## Editor layout only. Signals, documents, authority and canvas drawing stay with owners.
const UI = preload("res://scripts/ui/design_system/widgets.gd")
const EditorTheme = preload("res://scripts/ui/design_system/theme.gd")

static func setup(root: Control) -> void:
	root.theme = EditorTheme.create()
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_theme_constant_override("separation", 16)

static func heading(root: Node, title: String, detail: String, icon: String) -> void:
	root.add_child(UI.badge(title, icon))
	var copy := UI.text(detail, "MutedLabel")
	root.add_child(copy)

static func action(parent: Node, title: String, callback: Callable) -> Button:
	var icon := UI.action_icon(title)
	if "Compile" in title: icon = "chip"
	elif "Stop" in title: icon = "close"
	elif "Reset" in title or "Redo" in title: icon = "back"
	elif "point" in title or "component" in title or "trace" in title: icon = "circuit"
	var result := UI.action(title, icon, callback, title.begins_with("Save") or title.begins_with("Upload") or title == "Compile source")
	parent.add_child(result)
	return result

static func section(root: Node, title: String, icon: String, first: Node, last: Node) -> PanelContainer:
	# Move whole controls, preserving identities, callbacks and child-index contracts.
	var start := first.get_index()
	var nodes := root.get_children().slice(start, last.get_index() + 1)
	var panel := PanelContainer.new()
	panel.theme_type_variation = "CardPanel"
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(panel)
	root.move_child(panel, start)
	var content := VBoxContainer.new()
	panel.add_child(content)
	content.add_child(UI.badge(title, icon))
	for node in nodes:
		root.remove_child(node)
		content.add_child(node)
	return panel

static func labeled(control: Control, title: String) -> void:
	var parent := control.get_parent()
	var position := control.get_index()
	parent.remove_child(control)
	var field := VBoxContainer.new()
	field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(field)
	parent.move_child(field, position)
	field.add_child(UI.text(title, "MutedLabel"))
	field.add_child(control)
	control.tooltip_text = title

static func finish(root: Node) -> void:
	for child in root.get_children():
		# CodeEdit keeps the engine's monospace font and syntax colors.
		if child is CodeEdit: continue
		if child is LineEdit:
			child.custom_minimum_size.y = maxf(44, child.custom_minimum_size.y)
			child.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		elif child is OptionButton or child is CheckButton or child is SpinBox:
			child.custom_minimum_size.y = maxf(44, child.custom_minimum_size.y)
			child.focus_mode = Control.FOCUS_ALL
		elif child is Label:
			child.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		# Custom canvases own their draw/input semantics and are deliberately skipped.
		if child.get_script() == null or child is Container:
			finish(child)
