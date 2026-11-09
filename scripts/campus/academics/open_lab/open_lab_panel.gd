extends RefCounted
const INK := Color("e8f1f5")
const MUTED := Color("a8bac6")

static func mount(parent: VBoxContainer, practice: Callable, tutorial: Callable, close: Callable) -> void:
	var title := Label.new()
	title.text="LAB INSTRUCTOR"
	title.add_theme_font_size_override("font_size",25)
	title.add_theme_color_override("font_color",INK)
	parent.add_child(title)
	_add_action(parent,"Practice Sheet","Choose a lab week and difficulty, or let the instructor pick a week.",practice)
	_add_action(parent,"Equipment Tutorial","Learn the equipment and try a guided demonstration.",tutorial)
	var dismiss := Button.new()
	dismiss.text="Close"
	dismiss.focus_mode=Control.FOCUS_ALL
	dismiss.pressed.connect(close)
	parent.add_child(dismiss)

static func _add_action(parent: VBoxContainer, heading: String, detail: String, callback: Callable) -> void:
	var card := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color=Color("233949")
	style.set_corner_radius_all(8)
	style.set_content_margin_all(12)
	card.add_theme_stylebox_override("panel",style)
	parent.add_child(card)
	var body := VBoxContainer.new()
	card.add_child(body)
	var action := Button.new()
	action.text=heading
	action.custom_minimum_size.y=42
	action.focus_mode=Control.FOCUS_ALL
	action.pressed.connect(callback)
	body.add_child(action)
	var description := Label.new()
	description.text=detail
	description.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	description.add_theme_color_override("font_color",MUTED)
	body.add_child(description)
