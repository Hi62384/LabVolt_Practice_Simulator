extends "res://scripts/electronics/circuit_workspace/maker_canvas.gd"

signal hole_chosen(hole: String)
signal surface_chosen(id: String)
var markers := {}
var active_hole_marker := ""
var surface_selection := {}
var picking := false
var picking_surface := false

func _ready() -> void:
	read_only = true
	selected_type = "select"
	super._ready()

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var hole := hole_at(event.position)
		if picking_surface:
			for part in board.parts:
				if _body_at(part,event.position):
					surface_chosen.emit(part.id)
					break
		elif picking and not hole.is_empty(): hole_chosen.emit(hole)
		accept_event()
		return
	super._gui_input(event)

func _draw() -> void:
	super._draw()
	for part in board.parts:
		if surface_selection.has(part.id):
			var polygon := _body_polygon(part)
			polygon.append(polygon[0])
			draw_polyline(polygon,Color("ebad55"),2.5,true)
	for hole in markers:
		var point := at(hole)
		var tint := Color("c77f27") if hole == active_hole_marker else Color("287966")
		draw_arc(point,8*zoom,0,TAU,24,tint,2.5,true)
		var offset := Vector2(-5,-10)
		draw_string_outline(get_theme_default_font(),point+offset,str(markers[hole]),HORIZONTAL_ALIGNMENT_LEFT,-1,12,4,Color("10262b"))
		draw_string(get_theme_default_font(),point+offset,str(markers[hole]),HORIZONTAL_ALIGNMENT_LEFT,-1,12,Color("e8fff1"))

