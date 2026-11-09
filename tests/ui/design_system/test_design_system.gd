extends SceneTree
## Deferred engine test. Not executed while the user is playtesting.
const UI = preload("res://scripts/ui/design_system/widgets.gd")
const Skin = preload("res://scripts/ui/design_system/theme.gd")
const Grid = preload("res://scripts/ui/design_system/responsive_grid.gd")
const Dialog = preload("res://scripts/ui/design_system/dialog.gd")

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var host := Control.new()
	host.theme = Skin.create()
	root.add_child(host)
	var clicks := [0]
	var action := UI.action("Buy components", "cart", func(): clicks[0] += 1, true)
	host.add_child(action)
	action.pressed.emit()
	assert(clicks[0] == 1)
	assert(action.text == "Buy components" and action.custom_minimum_size.y >= 44)
	assert(UI.icon("not-a-resource-path") == UI.icon("component"))
	var field := UI.field("Quantity", "5", "Whole components only")
	host.add_child(field)
	UI.field_error(field, "Enter a whole number")
	assert(field.get_node("Input").theme_type_variation == "ErrorLineEdit")
	assert(field.get_node("Feedback").text == "Enter a whole number")
	UI.field_error(field, "")
	assert(field.get_node("Feedback").text == "Whole components only")
	var card := UI.card("Resistor", "220 Ω", "resistor", "Rare")
	host.add_child(card)
	assert(card.get_node("Content/Copy/Rarity").text == "Rare")
	assert(card.get_node("Content/Icon").get_theme_stylebox("panel").border_color == preload("res://scripts/ui/design_system/tokens.gd").rarity_color("Rare"))
	var grid := Grid.new()
	host.add_child(grid)
	grid.size.x = 1000
	grid._reflow()
	assert(grid.columns == 3)
	grid.size.x = 280
	grid._reflow()
	assert(grid.columns == 1)
	var modal := Dialog.new()
	host.add_child(modal)
	modal.configure("Review", "No gameplay calls")
	modal.body.add_child(UI.field("Name", "Your name"))
	var dismissals := [0]
	modal.dismissed.connect(func(): dismissals[0] += 1)
	modal.open()
	assert(modal.visible)
	modal.dismiss()
	modal.dismiss()
	assert(dismissals[0] == 1)
	host.queue_free()
	print("Design system engine contracts passed")
	quit()
