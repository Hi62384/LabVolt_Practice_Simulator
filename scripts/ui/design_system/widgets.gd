extends RefCounted
const API_VERSION := 1
const T = preload("res://scripts/ui/design_system/tokens.gd")
const UISkin = preload("res://scripts/ui/design_system/theme.gd")
# Explicit allowlist: UI keys cannot become arbitrary resource paths.
const ICONS := {
	"resistor": "res://assets/ui/design_system/icons/resistor.svg",
	"capacitor": "res://assets/ui/design_system/icons/capacitor.svg",
	"inductor": "res://assets/ui/design_system/icons/inductor.svg",
	"diode": "res://assets/ui/design_system/icons/diode.svg",
	"chip": "res://assets/ui/design_system/icons/chip.svg",
	"led": "res://assets/ui/design_system/icons/led.svg",
	"switch": "res://assets/ui/design_system/icons/switch.svg",
	"component": "res://assets/ui/design_system/icons/component.svg",
	"cart": "res://assets/ui/design_system/icons/cart.svg",
	"search": "res://assets/ui/design_system/icons/search.svg",
	"close": "res://assets/ui/design_system/icons/close.svg",
	"back": "res://assets/ui/design_system/icons/back.svg",
	"check": "res://assets/ui/design_system/icons/check.svg",
	"warning": "res://assets/ui/design_system/icons/warning.svg",
	"info": "res://assets/ui/design_system/icons/info.svg",
	"settings": "res://assets/ui/design_system/icons/settings.svg",
	"inventory": "res://assets/ui/design_system/icons/inventory.svg",
	"circuit": "res://assets/ui/design_system/icons/circuit.svg",
	"mode_select": "res://assets/ui/design_system/icons/mode-select.svg",
	"mode_wire": "res://assets/ui/design_system/icons/mode-wire.svg",
	"mode_place": "res://assets/ui/design_system/icons/mode-place.svg",
	"mode_operate": "res://assets/ui/design_system/icons/mode-operate.svg",
	"wave_dc": "res://assets/ui/design_system/icons/wave-dc.svg",
	"wave_ac": "res://assets/ui/design_system/icons/wave-ac.svg",
	"wave_square": "res://assets/ui/design_system/icons/wave-square.svg",
	"wave_triangle": "res://assets/ui/design_system/icons/wave-triangle.svg",
	"meter_volts": "res://assets/ui/design_system/icons/meter-volts.svg",
	"meter_amps": "res://assets/ui/design_system/icons/meter-amps.svg",
	"meter_ohms": "res://assets/ui/design_system/icons/meter-ohms.svg",
	"course": "res://assets/ui/design_system/icons/course.svg",
	"home": "res://assets/ui/design_system/icons/home.svg",
	"palette": "res://assets/ui/design_system/icons/palette.svg",
	"network": "res://assets/ui/design_system/icons/network.svg",
	"play": "res://assets/ui/design_system/icons/play.svg",
	"plus": "res://assets/ui/design_system/icons/plus.svg",
	"minus": "res://assets/ui/design_system/icons/minus.svg",
	"save": "res://assets/ui/design_system/icons/save.svg",
	"lock": "res://assets/ui/design_system/icons/lock.svg",
	"chat": "res://assets/ui/design_system/icons/chat.svg",
	"user": "res://assets/ui/design_system/icons/user.svg",
	"map": "res://assets/ui/design_system/icons/map.svg",
	"clock": "res://assets/ui/design_system/icons/clock.svg",
	"trade": "res://assets/ui/design_system/icons/trade.svg",
	"meter": "res://assets/ui/design_system/icons/meter.svg",
	"scope": "res://assets/ui/design_system/icons/scope.svg",
	"code": "res://assets/ui/design_system/icons/code.svg",
	"folder": "res://assets/ui/design_system/icons/folder.svg",
	"upload": "res://assets/ui/design_system/icons/upload.svg",
	"download": "res://assets/ui/design_system/icons/download.svg",
	"refresh": "res://assets/ui/design_system/icons/refresh.svg",
	"trash": "res://assets/ui/design_system/icons/trash.svg",
	"volume": "res://assets/ui/design_system/icons/volume.svg",
	"keyboard": "res://assets/ui/design_system/icons/keyboard.svg",
}

static var _icon_cache: Dictionary={}
static func icon(key: String) -> Texture2D:
	var path: String=ICONS.get(key, ICONS.component)
	if _icon_cache.has(path):return _icon_cache[path]
	# Raw SVG decoding also works on a direct source launch before editor import.
	var image := Image.new()
	var error := image.load_svg_from_string(FileAccess.get_file_as_string(path))
	if error!=OK:return null
	var texture := ImageTexture.create_from_image(image)
	_icon_cache[path]=texture
	return texture

static func action(label: String, icon_key: String, callback: Callable, primary: bool = false) -> Button:
	var button := Button.new()
	button.text = label
	button.icon = icon(icon_key)
	button.expand_icon = true
	button.add_theme_constant_override("icon_max_width", 22)
	button.custom_minimum_size.y = T.HIT_HEIGHT
	button.theme_type_variation = "PrimaryButton" if primary else "Button"
	button.focus_mode = Control.FOCUS_ALL
	button.tooltip_text = label
	if callback.is_valid():
		button.pressed.connect(callback)
	return button

static func text(value: String, variant: String = "Label") -> Label:
	var label := Label.new()
	label.text = value
	label.theme_type_variation = variant
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

static func header(title: String, subtitle: String, close_callback: Callable) -> VBoxContainer:
	var root := VBoxContainer.new()
	var row := HBoxContainer.new()
	root.add_child(row)
	row.add_child(text(title, "TitleLabel"))
	row.add_child(action("Close", "close", close_callback))
	if not subtitle.is_empty():
		root.add_child(text(subtitle, "MutedLabel"))
	return root

static func card(title: String, detail: String, icon_key: String, rarity: String = "Common") -> PanelContainer:
	var root := PanelContainer.new()
	root.theme_type_variation = "CardPanel"
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_theme_stylebox_override("panel", UISkin.card_style(rarity))
	var row := HBoxContainer.new()
	row.name = "Content"
	root.add_child(row)
	var tile := PanelContainer.new()
	tile.name = "Icon"
	tile.custom_minimum_size = Vector2(56, 56)
	tile.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	tile.add_theme_stylebox_override("panel", T.surface(T.rarity_color(rarity).lerp(T.SURFACE, 0.83), T.rarity_color(rarity), 12))
	row.add_child(tile)
	var picture := TextureRect.new()
	picture.texture = icon(icon_key)
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tile.add_child(picture)
	var copy := VBoxContainer.new()
	copy.name = "Copy"
	copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(copy)
	var heading := text(title, "SubtitleLabel")
	heading.name = "Title"
	copy.add_child(heading)
	var description := text(detail, "MutedLabel")
	description.name = "Detail"
	copy.add_child(description)
	var rarity_label := text(rarity, "MutedLabel")
	rarity_label.name = "Rarity"
	rarity_label.add_theme_color_override("font_color", T.rarity_color(rarity))
	copy.add_child(rarity_label)
	return root

static func field(label: String, placeholder: String, hint: String = "") -> VBoxContainer:
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 6)
	var heading := text(label)
	heading.name = "Label"
	root.add_child(heading)
	var input := LineEdit.new()
	input.name = "Input"
	input.placeholder_text = placeholder
	input.custom_minimum_size.y = T.HIT_HEIGHT
	input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	input.tooltip_text = label + (" · " + hint if not hint.is_empty() else "")
	root.add_child(input)
	var feedback := text(hint, "MutedLabel")
	feedback.name = "Feedback"
	feedback.visible = not hint.is_empty()
	root.add_child(feedback)
	root.set_meta("hint", hint)
	return root

static func field_error(root: VBoxContainer, message: String) -> void:
	var input := root.get_node("Input") as LineEdit
	var feedback := root.get_node("Feedback") as Label
	input.theme_type_variation = "LineEdit" if message.is_empty() else "ErrorLineEdit"
	feedback.theme_type_variation = "MutedLabel" if message.is_empty() else "ErrorLabel"
	feedback.text = str(root.get_meta("hint", "")) if message.is_empty() else message
	feedback.visible = not feedback.text.is_empty()

static func badge(value: String, icon_key: String = "info") -> HBoxContainer:
	var row := HBoxContainer.new()
	var picture := TextureRect.new()
	picture.texture = icon(icon_key)
	picture.custom_minimum_size = Vector2(22, 22)
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(picture)
	row.add_child(text(value, "MutedLabel"))
	return row

static func style_button(button: Button, icon_key: String = "component", primary: bool = false) -> void:
	## Opt-in migration helper: preserve every existing signal and callback.
	button.icon = icon(icon_key)
	button.expand_icon = true
	button.add_theme_constant_override("icon_max_width", 22)
	button.custom_minimum_size.y = maxf(button.custom_minimum_size.y, T.HIT_HEIGHT)
	button.focus_mode = Control.FOCUS_ALL
	if primary: button.theme_type_variation = "PrimaryButton"

static func action_icon(label: String) -> String:
	## Presentation hint only. Caller can always supply an explicit icon key.
	var value := label.to_lower()
	for pair in [["close", "close"], ["cancel", "back"], ["back", "back"], ["save", "save"], ["upload", "save"], ["buy", "cart"], ["purchase", "cart"], ["find", "search"], ["search", "search"], ["settings", "settings"], ["host", "network"], ["join", "network"], ["start", "play"], ["run", "play"], ["validate", "check"], ["remove", "minus"], ["add", "plus"], ["kit", "inventory"], ["course", "course"]]:
		if pair[0] in value: return pair[1]
	return "component"

static func section(title: String, subtitle: String = "", icon_key: String = "component") -> PanelContainer:
	## Caller adds controls to named Body; no model or navigation ownership.
	var panel := PanelContainer.new()
	panel.theme_type_variation = "CardPanel"
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var body := VBoxContainer.new()
	body.name = "Body"
	panel.add_child(body)
	body.add_child(badge(title, icon_key))
	if not subtitle.is_empty(): body.add_child(text(subtitle, "MutedLabel"))
	return panel

static func status(message: String, severity: String = "info") -> HBoxContainer:
	var row := badge(message, "warning" if severity == "error" else "check" if severity == "success" else "info")
	var label := row.get_child(1) as Label
	label.theme_type_variation = "ErrorLabel" if severity == "error" else "MutedLabel"
	if severity == "success": label.add_theme_color_override("font_color", T.ACCENT)
	return row

static func empty_state(title: String, detail: String, icon_key: String = "inventory") -> PanelContainer:
	return section(title, detail, icon_key)
