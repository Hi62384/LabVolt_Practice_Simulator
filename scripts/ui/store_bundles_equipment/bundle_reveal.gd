extends ColorRect

const UI = preload("res://scripts/ui/design_system/widgets.gd")
const Bundles = preload("res://scripts/ui/store_bundles_equipment/module.gd")
const Art = preload("res://scripts/electronics/component_shop_ui/component_art.gd")
const Catalog = preload("res://scripts/electronics_catalog.gd")

var _picture: TextureRect
var _crate: Button
var _hint: Label
var _contents: VBoxContainer
var _motion: Tween
var _rattles := 0

func build(receipt: Dictionary, dismiss: Callable) -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	color = Color(0.03, 0.07, 0.10, 0.8)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size.x = 350
	center.add_child(panel)
	_contents = VBoxContainer.new()
	_contents.add_theme_constant_override("separation", 8)
	panel.add_child(_contents)

	var header := HBoxContainer.new()
	_contents.add_child(header)
	var title := UI.text(str(receipt.name), "Title")
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var close := UI.action("Close", "", dismiss)
	header.add_child(close)

	_crate = Button.new()
	_crate.flat = true
	_crate.accessibility_name = "Rattle bundle"
	_crate.custom_minimum_size.y = 132
	_contents.add_child(_crate)
	_picture = TextureRect.new()
	_picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_picture.texture = Bundles.bundle_art(receipt.name)
	_picture.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_crate.add_child(_picture)
	_picture.resized.connect(func(): _picture.pivot_offset = _picture.size * 0.5)

	_hint = UI.text("Click the box to rattle it · 0 / 3")
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_contents.add_child(_hint)
	for direction in ["left", "right", "top", "bottom", "next", "previous"]:
		var property: String = "focus_" + direction if direction in ["next", "previous"] else "focus_neighbor_" + direction
		close.set(property, close.get_path_to(_crate))
		_crate.set(property, _crate.get_path_to(close))
	_crate.pressed.connect(_rattle.bind(receipt, close))
	_crate.grab_focus()
	_sway()

func _sway() -> void:
	_motion = create_tween().set_loops().set_trans(Tween.TRANS_SINE)
	_motion.tween_property(_picture, "rotation", 0.035, 0.55)
	_motion.tween_property(_picture, "rotation", -0.035, 0.55)

func _rattle(receipt: Dictionary, close: Button) -> void:
	_rattles += 1
	_hint.text = "Click the box to rattle it · %d / 3" % _rattles
	if _rattles == 3:
		_crate.disabled = true
		close.grab_focus()
	_motion.kill()
	_motion = create_tween().set_trans(Tween.TRANS_SINE)
	_motion.tween_property(_picture, "rotation", -0.14, 0.06)
	_motion.tween_property(_picture, "rotation", 0.14, 0.08)
	_motion.tween_property(_picture, "rotation", 0.0, 0.09)
	if _rattles == 3:
		_motion.tween_callback(_reveal.bind(receipt, close))
	else:
		_motion.tween_callback(_sway)

func _reveal(receipt: Dictionary, close: Button) -> void:
	_picture.texture = Bundles.bundle_art(receipt.name, true)
	_hint.text = "Added to your components"
	var list := ScrollContainer.new()
	list.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	list.custom_minimum_size.y = minf(receipt.items.size() * 35, maxf(64, size.y - 270))
	_contents.add_child(list)
	var rows := VBoxContainer.new()
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_child(rows)
	var catalog := Catalog.all()
	for id in receipt.items:
		var entry: Dictionary = catalog.get(id, {})
		var row := HBoxContainer.new()
		rows.add_child(row)
		var icon := TextureRect.new()
		icon.custom_minimum_size = Vector2(32, 32)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.texture = Art.texture(entry)
		row.add_child(icon)
		var label := UI.text(str(entry.get("name", id)))
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)
		row.add_child(UI.text("×%d" % int(receipt.items[id])))
	for direction in ["left", "right", "top", "bottom", "next", "previous"]:
		var property: String = "focus_" + direction if direction in ["next", "previous"] else "focus_neighbor_" + direction
		close.set(property, NodePath("."))
