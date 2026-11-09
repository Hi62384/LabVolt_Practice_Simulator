extends RefCounted
## Presentation-only tokens. No global theme mutation or gameplay dependencies.
const INK := Color("edf6fa")
const MUTED := Color("b6cad4")
const SURFACE := Color("142b38")
const RAISED := Color("1d3b4a")
const BORDER := Color("547383")
const ACCENT := Color("8de4cc")
const ERROR := Color("ffb6b9")
const SPACING := 12
const HIT_HEIGHT := 44
const RADIUS := 12
const BODY_SIZE := 16
const TITLE_SIZE := 28

static func rarity_color(rarity: String) -> Color:
	match rarity.strip_edges().to_lower():
		"uncommon": return Color("94ed58")
		"rare": return Color("5ab9ff")
		"epic": return Color("dc94ff")
		"legendary": return Color("ffcc57")
		"custom": return Color("55efd5")
		_: return Color("c5c9ce")

static func surface(fill: Color, edge: Color = BORDER, padding: int = 16) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = edge
	box.set_border_width_all(1)
	box.set_corner_radius_all(RADIUS)
	box.set_content_margin_all(padding)
	return box

static func card_style(rarity: String = "Common", selected: bool = false) -> StyleBoxFlat:
	var box := surface(RAISED, ACCENT if selected else BORDER)
	box.border_width_left = 4
	if not selected:
		box.border_color = rarity_color(rarity).lerp(RAISED, 0.18)
	return box
