extends Control
## Additive review fixture, deliberately not connected to Main or live game state.
const UI = preload("res://scripts/ui/design_system/widgets.gd")
const UISkin = preload("res://scripts/ui/design_system/theme.gd")
const Grid = preload("res://scripts/ui/design_system/responsive_grid.gd")
const Dialog = preload("res://scripts/ui/design_system/dialog.gd")
var dialog
var feedback: Label

func _ready() -> void:
	theme = UISkin.create()
	var backdrop := ColorRect.new()
	backdrop.color = Color("091b28")
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(backdrop)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	add_child(margin)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	margin.add_child(scroll)
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(column)
	column.add_child(UI.header("Components", "Find a part, choose its rating, then add it to your kit.", func(): feedback.text = "Close requested (fixture only)"))
	column.add_child(UI.badge("Playtest purchasing · host validates every request", "cart"))
	var search := UI.field("Find a component", "Name or category", "Search within this station")
	column.add_child(search)
	var grid := Grid.new()
	column.add_child(grid)
	for entry in [["Resistor", "220 Ω · ±1% · 0.25 W", "resistor", "Common"], ["Capacitor", "10 μF · 50 V", "capacitor", "Uncommon"], ["Controller", "Programmable board", "chip", "Rare"], ["Custom circuit", "Your reusable design", "circuit", "Custom"]]:
		var card := UI.card(entry[0], entry[1], entry[2], entry[3])
		grid.add_child(card)
		var copy := card.get_node("Content/Copy")
		copy.add_child(UI.action("Choose rating", "plus", _show_dialog, true))
		card.set_meta("search", str(entry[0]).to_lower())
	search.get_node("Input").text_changed.connect(func(value: String):
		for card in grid.get_children(): card.visible = value.to_lower() in str(card.get_meta("search"))
	)
	var states := HFlowContainer.new()
	column.add_child(states)
	states.add_child(UI.action("Primary action", "check", func(): feedback.text = "Primary action selected", true))
	var selected := UI.action("Selected filter", "inventory", Callable())
	selected.toggle_mode = true
	selected.button_pressed = true
	states.add_child(selected)
	var disabled := UI.action("Waiting for host", "lock", Callable())
	disabled.disabled = true
	states.add_child(disabled)
	feedback = UI.text("Review fixture only · no purchases or saves are performed.", "MutedLabel")
	column.add_child(feedback)
	dialog = Dialog.new()
	add_child(dialog)
	dialog.configure("Choose resistor rating", "Values and purchase validation belong to the component service.")
	var rating := UI.field("Resistance · Ω", "e.g. 220", "Use the existing component value parser")
	dialog.body.add_child(rating)
	var quantity := UI.field("Quantity", "e.g. 5", "Whole components only")
	dialog.body.add_child(quantity)
	UI.field_error(quantity, "Enter a whole quantity to continue.")
	dialog.actions.add_child(UI.action("Cancel", "back", dialog.dismiss))
	var confirm := UI.action("Add to kit", "cart", Callable(), true)
	confirm.disabled = true
	dialog.actions.add_child(confirm)

func _show_dialog() -> void:
	dialog.open()
