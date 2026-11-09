extends RefCounted
static func create() -> Theme:
	var theme := Theme.new()
	theme.default_font_size=16
	for type in ["Label","Button","OptionButton","CheckBox","LineEdit","TabContainer"]:
		theme.set_color("font_color",type,Color("dce9ed"))
		theme.set_color("font_hover_color",type,Color("a1f4da"))
	for type in ["Button","OptionButton","LineEdit"]:
		for state in ["normal","hover","pressed","focus","disabled"]:
			var box := StyleBoxFlat.new(); box.bg_color=Color("224a50") if state in ["hover","pressed"] else Color("172d38")
			box.border_color=Color("80dfc5") if state=="focus" else Color("34505c"); box.set_border_width_all(1); box.set_corner_radius_all(6)
			box.content_margin_left=14; box.content_margin_right=14; box.content_margin_top=8; box.content_margin_bottom=8
			theme.set_stylebox(state,type,box)
	return theme
