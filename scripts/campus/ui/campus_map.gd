extends Control
signal room_selected(room_id: String)
var rooms: Array=[]
var floor_index := 0
var hit_boxes := {}
func _ready() -> void:
	custom_minimum_size=Vector2(280,330)
	size_flags_horizontal=Control.SIZE_EXPAND_FILL
	tooltip_text="Select a room to set walking directions. Use the room list for keyboard navigation."
	mouse_filter=Control.MOUSE_FILTER_STOP
func _draw() -> void:
	hit_boxes.clear()
	draw_rect(Rect2(Vector2.ZERO,size),Color("101e2a"))
	var scale_factor := minf(size.x/52.0,size.y/100.0)
	var origin := Vector2(size.x*.5,65)
	draw_rect(Rect2(origin+Vector2(0,-10)*scale_factor,Vector2(6,78)*scale_factor),Color("365566"))
	for room in rooms:
		if int(room.get("floor",0))!=floor_index: continue
		var center: Array=room.get("center",[0,0,0]); var dimensions: Array=room.get("size",[8,4,8])
		var point := origin+Vector2(float(center[0])-10,float(center[2]))*scale_factor
		var rect := Rect2(point-Vector2(float(dimensions[0]),float(dimensions[2]))*scale_factor*.5,Vector2(float(dimensions[0]),float(dimensions[2]))*scale_factor)
		hit_boxes[str(room.id)]=rect
		draw_rect(rect,Color("244a55")); draw_rect(rect,Color("80dfc5"),false,1)
		draw_string(ThemeDB.fallback_font,rect.position+Vector2(4,16),str(room.get("number","")),HORIZONTAL_ALIGNMENT_LEFT,-1,13,Color.WHITE)
	draw_string(ThemeDB.fallback_font,Vector2(14,24),"Floor %d · select a room for directions"%(floor_index+1),HORIZONTAL_ALIGNMENT_LEFT,-1,15,Color("80dfc5"))
func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index==MOUSE_BUTTON_LEFT:
		for id in hit_boxes:
			if hit_boxes[id].has_point(event.position): room_selected.emit(id); accept_event(); break
