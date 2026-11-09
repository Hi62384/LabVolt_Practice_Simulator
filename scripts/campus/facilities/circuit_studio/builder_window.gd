extends Window
const StudioTheme=preload("res://scripts/ui/design_system/theme.gd")
const Tokens=preload("res://scripts/ui/design_system/tokens.gd")
var game: Node
var kind: String
var content: VBoxContainer

func open_station(owner_game: Node,package_kind: String) -> void:
	game=owner_game;kind=package_kind
	title = kind+" Builder"
	borderless = true
	var available := Vector2i(game.get_viewport().get_visible_rect().size)
	size = Vector2i(mini(1100, available.x - 60), mini(760, available.y - 85))
	min_size = Vector2i(700, 480)
	theme = StudioTheme.create()
	close_requested.connect(_close)
	game.release_mouse()
	_rebuild()
	popup_centered()

func _rebuild() -> void:
	for child in get_children():remove_child(child);child.queue_free()
	var surface := PanelContainer.new()
	add_child(surface)
	surface.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var background := Tokens.surface(Color("122a3a"), Tokens.BORDER, 8)
	background.set_content_margin_all(16)
	surface.add_theme_stylebox_override("panel", background)
	content = VBoxContainer.new()
	surface.add_child(content)
	var converter := preload("res://scripts/electronics/ic_pcb_editor/converter_ui.gd").new()
	content.add_child(converter)
	converter.setup(game,_close,kind)

func _close() -> void:
	hide();queue_free()
	if is_instance_valid(game) and game.front.in_game:game.capture()
