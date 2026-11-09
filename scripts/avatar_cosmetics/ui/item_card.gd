class_name CosmeticItemCard
extends Button

const Tokens = preload("res://scripts/ui/design_system/tokens.gd")
const WIDTH := 126

signal item_requested(definition: Dictionary)

var definition: Dictionary
var cache_key := ""
var thumbnail: TextureRect
var name_label: Label
var rarity_label: Label
var preview_frame: PanelContainer
var equipped_badge: PanelContainer
var _equipped := false
var _selected := false

func _ready() -> void:
	custom_minimum_size = Vector2(WIDTH, 152)
	size_flags_horizontal = SIZE_EXPAND_FILL
	pressed.connect(func(): item_requested.emit(definition))
	var column := VBoxContainer.new()
	column.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(column)
	column.set_anchors_and_offsets_preset(PRESET_FULL_RECT, PRESET_MODE_MINSIZE, 7)
	column.add_theme_constant_override("separation", 3)
	var stage := PanelContainer.new()
	preview_frame = stage
	stage.mouse_filter = MOUSE_FILTER_IGNORE
	stage.custom_minimum_size.y = 92
	stage.size_flags_vertical = SIZE_EXPAND_FILL
	stage.add_theme_stylebox_override("panel", Tokens.surface(Color("102634"), Color("284857"), 3))
	column.add_child(stage)
	thumbnail = TextureRect.new()
	thumbnail.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	thumbnail.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	thumbnail.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	thumbnail.mouse_filter = MOUSE_FILTER_IGNORE
	stage.add_child(thumbnail)
	name_label = Label.new()
	name_label.add_theme_font_size_override("font_size", 13)
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_label.mouse_filter = MOUSE_FILTER_IGNORE
	column.add_child(name_label)
	rarity_label = Label.new()
	rarity_label.add_theme_font_size_override("font_size", 11)
	rarity_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	rarity_label.mouse_filter = MOUSE_FILTER_IGNORE
	column.add_child(rarity_label)
	equipped_badge = PanelContainer.new()
	equipped_badge.mouse_filter = MOUSE_FILTER_IGNORE
	var badge_style := Tokens.surface(Tokens.ACCENT, Tokens.ACCENT, 0)
	badge_style.set_corner_radius_all(7)
	equipped_badge.add_theme_stylebox_override("panel", badge_style)
	add_child(equipped_badge)
	equipped_badge.set_anchors_preset(PRESET_TOP_RIGHT)
	equipped_badge.offset_left = -96
	equipped_badge.offset_right = -11
	equipped_badge.offset_top = 11
	equipped_badge.offset_bottom = 34
	equipped_badge.hide()
	var badge_text := Label.new()
	badge_text.text = "✓ EQUIPPED"
	badge_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	badge_text.add_theme_font_size_override("font_size", 11)
	badge_text.add_theme_color_override("font_color", Color("102c27"))
	badge_text.mouse_filter = MOUSE_FILTER_IGNORE
	equipped_badge.add_child(badge_text)

func bind(value: Dictionary, is_equipped: bool, is_selected: bool, fallback: Texture2D = null) -> void:
	definition = value
	name_label.text = str(value.get("name", value.get("id", "Unknown item")))
	thumbnail.texture = fallback
	_apply_selection(is_equipped, is_selected)

func update_selection(is_equipped: bool, is_selected: bool) -> void:
	if is_equipped != _equipped or is_selected != _selected:
		_apply_selection(is_equipped, is_selected)

func _apply_selection(is_equipped: bool, is_selected: bool) -> void:
	_equipped = is_equipped
	_selected = is_selected
	var rarity := str(definition.get("rarity", "common"))
	var tint := Tokens.rarity_color(rarity)
	var neutral := rarity.to_lower() == "common"
	rarity_label.text = rarity.capitalize()
	if definition.has("shop_tag"):
		rarity_label.text += " · " + str(definition.shop_tag)
	rarity_label.add_theme_color_override("font_color", tint)
	equipped_badge.visible = is_equipped
	preview_frame.add_theme_stylebox_override("panel", Tokens.surface(Color("0f2634").lerp(tint, .04 if neutral else .14), tint.darkened(.48), 3))
	for state in ["normal", "hover", "pressed", "hover_pressed"]:
		var fill_strength := .07 if neutral else .15
		var fill := Color("102634").lerp(tint, fill_strength + (.04 if is_selected else 0.0))
		if state == "hover":
			fill = fill.lightened(.03)
		var edge := tint if is_selected else tint.darkened(.36 if neutral else .16)
		var frame := Tokens.surface(fill, Tokens.ACCENT if is_equipped else edge, 6)
		frame.set_border_width_all(3 if is_equipped else 1)
		frame.border_width_left = 5 if is_equipped else 4
		add_theme_stylebox_override(state, frame)
	tooltip_text = name_label.text + (" · Equipped" if is_equipped else "")

func accept_thumbnail(key: String, texture: Texture2D) -> void:
	if key == cache_key:
		thumbnail.texture = texture
