extends RefCounted
const T = preload("res://scripts/ui/design_system/tokens.gd")

static func create() -> Theme:
	var theme := Theme.new()
	theme.default_font_size = T.BODY_SIZE
	for type in ["Label", "Button", "OptionButton", "CheckBox", "CheckButton", "LineEdit", "TextEdit", "ItemList", "Tree", "TabBar", "PopupMenu", "RichTextLabel"]:
		theme.set_color("font_color", type, T.INK)
		theme.set_color("font_hover_color", type, T.INK)
		theme.set_color("font_pressed_color", type, T.INK)
		theme.set_color("font_focus_color", type, T.INK)
		theme.set_color("font_disabled_color", type, Color("94aab7"))
		theme.set_font_size("font_size", type, T.BODY_SIZE)
	for type in ["HBoxContainer", "VBoxContainer"]:
		theme.set_constant("separation", type, T.SPACING)
	for axis in ["h_separation", "v_separation"]:
		for type in ["GridContainer", "HFlowContainer", "VFlowContainer"]:
			theme.set_constant(axis, type, T.SPACING)
	theme.set_stylebox("panel", "PanelContainer", T.surface(T.SURFACE))
	theme.set_stylebox("panel", "PopupMenu", T.surface(T.SURFACE))
	theme.set_type_variation("CardPanel", "PanelContainer")
	theme.set_stylebox("panel", "CardPanel", T.card_style())
	for type in ["Button", "OptionButton"]:
		_button(theme, type, false, false)
	for variant in ["PrimaryButton", "QuietButton", "DangerButton"]:
		theme.set_type_variation(variant, "Button")
		_button(theme, variant, variant == "PrimaryButton", variant == "DangerButton")
	for type in ["LineEdit", "TextEdit"]:
		theme.set_stylebox("normal", type, T.surface(Color("0d202c")))
		theme.set_stylebox("read_only", type, T.surface(T.SURFACE))
		theme.set_stylebox("focus", type, _focus(T.ACCENT))
		theme.set_color("font_placeholder_color", type, T.MUTED)
		theme.set_color("caret_color", type, T.ACCENT)
		theme.set_color("selection_color", type, Color("356d78"))
	theme.set_type_variation("ErrorLineEdit", "LineEdit")
	theme.set_stylebox("normal", "ErrorLineEdit", T.surface(Color("352a38"), T.ERROR))
	theme.set_stylebox("focus", "ErrorLineEdit", _focus(T.ERROR))
	for type in ["ItemList", "Tree"]:
		theme.set_stylebox("panel", type, T.surface(Color("0d202c")))
		theme.set_stylebox("selected", type, T.surface(Color("315967"), T.ACCENT, 4))
		theme.set_stylebox("selected_focus", type, T.surface(Color("315967"), T.ACCENT, 4))
		theme.set_stylebox("cursor", type, _focus(T.ACCENT))
		theme.set_color("font_selected_color", type, T.INK)
	theme.set_stylebox("panel", "TabContainer", T.surface(T.SURFACE))
	for type in ["VScrollBar", "HScrollBar"]:
		var track := StyleBoxFlat.new()
		track.bg_color=Color("142832")
		track.set_corner_radius_all(5)
		track.content_margin_left=3
		track.content_margin_right=3
		track.content_margin_top=3
		track.content_margin_bottom=3
		theme.set_stylebox("scroll",type,track)
		for state in ["grabber","grabber_highlight","grabber_pressed"]:
			var grip := StyleBoxFlat.new()
			grip.bg_color=Color("548e92") if state=="grabber" else Color("80c7ba") if state=="grabber_highlight" else Color("a1e3d0")
			grip.set_corner_radius_all(5)
			theme.set_stylebox(state,type,grip)
	for state in ["tab_selected", "tab_unselected", "tab_hovered", "tab_disabled"]:
		theme.set_stylebox(state, "TabBar", T.surface(T.RAISED if state == "tab_selected" else T.SURFACE, T.ACCENT if state == "tab_selected" else T.BORDER, 12))
	theme.set_color("font_selected_color", "TabBar", T.INK)
	theme.set_color("font_unselected_color", "TabBar", T.MUTED)
	for spec in [["TitleLabel", T.TITLE_SIZE, T.INK], ["SubtitleLabel", 19, T.INK], ["MutedLabel", 14, T.MUTED], ["ErrorLabel", 14, T.ERROR]]:
		theme.set_type_variation(spec[0], "Label")
		theme.set_font_size("font_size", spec[0], spec[1])
		theme.set_color("font_color", spec[0], spec[2])
	return theme

static func _focus(color: Color) -> StyleBoxFlat:
	var box := T.surface(Color.TRANSPARENT, color, 0)
	box.draw_center = false
	box.set_border_width_all(2)
	return box

static func _button(theme: Theme, type: String, primary: bool, danger: bool) -> void:
	var normal := Color("285c59") if primary else T.RAISED
	if danger:
		normal = Color("693c49")
	for state in ["normal", "hover", "pressed", "disabled", "hover_pressed"]:
		var fill: Color = normal
		if state == "hover": fill = normal.lightened(0.13)
		if state in ["pressed", "hover_pressed"]: fill = normal.darkened(0.12)
		if state == "disabled": fill = Color("243642")
		theme.set_stylebox(state, type, T.surface(fill, T.ACCENT if primary and state != "disabled" else T.BORDER, 12))
	theme.set_stylebox("focus", type, _focus(T.ACCENT))
	theme.set_constant("h_separation", type, 10)
	theme.set_constant("outline_size", type, 0)
	theme.set_color("icon_normal_color", type, T.INK)
	theme.set_color("icon_disabled_color", type, Color("94aab7"))

static func card_style(rarity: String = "Common", selected: bool = false) -> StyleBoxFlat:
	return T.card_style(rarity, selected)
