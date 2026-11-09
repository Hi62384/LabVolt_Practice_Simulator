extends RefCounted
## Layout composition only. Visual primitives remain owned by design_system.
const UI = preload("res://scripts/ui/design_system/widgets.gd")

static func section(parent: Node, title: String, detail: String, icon: String) -> VBoxContainer:
	var card := UI.card(title, detail, icon)
	card.get_node("Content/Copy/Rarity").hide()
	parent.add_child(card)
	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.get_node("Content/Copy").add_child(body)
	return body

static func page(tabs: TabContainer, title: String, icon: String) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.name = title
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	tabs.add_child(scroll)
	tabs.set_tab_icon(tabs.get_tab_count() - 1, UI.icon(icon))
	tabs.get_tab_bar().add_theme_constant_override("icon_max_width", 20)
	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(body)
	return body

static func field(parent: Node, title: String, control: Control) -> void:
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(UI.text(title, "MutedLabel"))
	control.custom_minimum_size.y = 44
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	control.tooltip_text = title
	box.add_child(control)
	parent.add_child(box)

static func flow(parent: Node) -> HFlowContainer:
	var row := HFlowContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(row)
	return row
