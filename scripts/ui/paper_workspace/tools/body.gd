extends Control
## Draws one lightweight stationery object. Hit targets live in case.gd.
const T = preload("res://scripts/ui/design_system/tokens.gd")
const TOOL_NAMES := ["pencil", "eraser", "text"]
var selected := "answer"

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(292, 332)

func _draw() -> void:
	var shadow := T.surface(Color("07131b", 0.42), Color("07131b", 0.0), 18)
	draw_style_box(shadow, Rect2(5, 8, 282, 320))
	var canvas := T.surface(Color("456575"), Color("9db2b7"), 16)
	canvas.set_corner_radius_all(26)
	draw_style_box(canvas, Rect2(0, 0, 282, 320))
	# Woven seams and a recessed zipper track.
	for i in range(10, 305, 8):
		draw_line(Vector2(11, i), Vector2(271, i), Color("b7c9c6", 0.055), 1)
	draw_line(Vector2(31, 20), Vector2(255, 20), Color("142a34"), 8, true)
	draw_line(Vector2(31, 20), Vector2(255, 20), Color("b9c7bc"), 2, true)
	for x in range(35, 252, 9):
		draw_line(Vector2(x, 16), Vector2(x + 2, 24), Color("e5dbb8"), 2, true)
	draw_style_box(T.surface(Color("e5d7b2"), Color("514e47"), 1), Rect2(241, 9, 23, 23))
	draw_line(Vector2(252, 23), Vector2(252, 35), Color("e5d7b2"), 5, true)
	draw_string(ThemeDB.fallback_font, Vector2(25, 57), "PENCIL CASE", HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color("e5eeeb"))
	for index in 3:
		var key: String = TOOL_NAMES[index]
		var slot := Rect2(16 + index * 88, 72, 78, 208)
		draw_style_box(T.surface(Color("203c4b"), Color("8da7ad") if key == selected else Color("264352"), 7), slot)
		if key == selected:
			draw_rect(slot.grow(2), Color("9be4d1"), false, 2)
		match key:
			"pencil": _pencil(slot)
			"eraser": _eraser(slot)
			"text": _text_block(slot)
		draw_string(ThemeDB.fallback_font, Vector2(slot.position.x + 10, 263), key.capitalize(), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("e8f1ef"))
	draw_line(Vector2(17, 297), Vector2(265, 297), Color("a7c1c0", 0.55), 2)
	draw_string(ThemeDB.fallback_font, Vector2(20, 313), "✦  SELECT A TOOL", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("e0ede6", 0.85))

func _pencil(slot: Rect2) -> void:
	var center := slot.position.x + 39
	draw_colored_polygon(PackedVector2Array([Vector2(center-11,92),Vector2(center+11,92),Vector2(center+11,214),Vector2(center,238),Vector2(center-11,214)]), Color("e4b862"))
	draw_rect(Rect2(center-11,92,22,15), Color("b9c6ba"))
	draw_rect(Rect2(center-11,107,22,8), Color("cf8993"))
	draw_line(Vector2(center-7,118), Vector2(center-7,211), Color("f8d88e"), 3)
	draw_colored_polygon(PackedVector2Array([Vector2(center-11,214),Vector2(center+11,214),Vector2(center,238)]), Color("e9d3a7"))
	draw_colored_polygon(PackedVector2Array([Vector2(center-4,229),Vector2(center+4,229),Vector2(center,238)]), Color("253038"))

func _eraser(slot: Rect2) -> void:
	var origin := slot.position + Vector2(13, 97)
	draw_style_box(T.surface(Color("f1d8ca"), Color("ae8a89"), 6), Rect2(origin, Vector2(52, 75)))
	draw_rect(Rect2(origin + Vector2(0, 44), Vector2(52, 20)), Color("c48392"))
	draw_line(origin + Vector2(5, 44), origin + Vector2(47, 44), Color("eadbda"), 2)

func _text_block(slot: Rect2) -> void:
	var origin := slot.position + Vector2(12, 91)
	draw_style_box(T.surface(Color("d9ded6"), Color("9ca8a6"), 6), Rect2(origin, Vector2(54, 80)))
	draw_string(ThemeDB.fallback_font, origin + Vector2(15, 58), "T", HORIZONTAL_ALIGNMENT_LEFT, -1, 49, Color("294653"))
