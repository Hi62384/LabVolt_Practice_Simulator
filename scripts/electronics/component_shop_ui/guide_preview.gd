extends "res://scripts/electronics/circuit_workspace/maker_canvas.gd"
## Render the mounted package and number the holes used by the solver.

var pin_names: Array = []
var mounted := {}

func configure(type_id: String, entry: Dictionary, definitions: Dictionary) -> void:
	pin_names = entry.get("pins", [])
	board = Board.empty()
	if definitions.has(type_id):
		board.definitions = definitions
	inventory_catalog = {type_id: entry}
	for anchor in ["D4", "A4", "B4", "F4"]:
		var trial := Placement.maker_candidate(board, inventory_catalog, {}, true, type_id, "D2", anchor, 0)
		if trial.get("error", "") == "" and trial.has("part"):
			board = trial.board
			mounted = trial.part
			break

func _ready() -> void:
	super._ready()
	read_only = true
	set_process(false)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	focus_mode = Control.FOCUS_NONE
	custom_minimum_size = Vector2(0, 260)

func fit_board() -> void:
	if mounted.is_empty() or size.x <= 36 or size.y <= 60:
		return
	zoom = 1.0
	pan = Vector2.ZERO
	var holes := Board.pins(mounted)
	var bounds := Rect2(at(str(holes[0])), Vector2.ONE)
	for hole in holes:
		bounds = bounds.expand(at(str(hole)))
	bounds = bounds.grow(40)
	zoom = minf(2.1, minf((size.x - 28) / bounds.size.x, (size.y - 36) / bounds.size.y))
	pan = size * .5 - bounds.get_center() * zoom
	fitted = true
	queue_redraw()

func _draw() -> void:
	if mounted.is_empty():
		draw_string(get_theme_default_font(), Vector2(12, 32), "See terminal order below.", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color("e8f3f2"))
		return
	super._draw()
	var font := get_theme_default_font()
	var holes := Board.pins(mounted)
	var middle_y := (at(str(holes[0])).y + at(str(holes[-1])).y) * .5
	for index in mini(holes.size(), pin_names.size()):
		var pin := at(str(holes[index]))
		var direction := -1.0 if pin.y <= middle_y else 1.0
		var tip := pin + Vector2(0, direction * 4)
		var label_at := pin + Vector2(0, direction * 30)
		var tint := Color("165a57")
		draw_line(label_at, tip, tint, 2.0, true)
		draw_colored_polygon(PackedVector2Array([pin, tip + Vector2(-3, 0), tip + Vector2(3, 0)]), tint)
		draw_circle(label_at, clampf(9.0 * zoom, 5.5, 11.0), tint, true, -1, true)
		var font_size := clampi(roundi(11.0 * zoom), 8, 13)
		draw_string(font, label_at + Vector2(-12, font_size * .34), str(index + 1), HORIZONTAL_ALIGNMENT_CENTER, 24, font_size, Color.WHITE)
