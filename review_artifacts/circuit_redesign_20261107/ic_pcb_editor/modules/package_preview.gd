extends Control
signal selected(index: int)
signal moved(index: int,point: Vector2i)
signal add_requested(point: Vector2i)
var model: RefCounted
var selected_index:=-1
var dragging:=false
var preview_point:=Vector2i.ZERO

func _rect() -> Rect2:
	var width:=float(model.draft.footprint.width);var height:=float(model.draft.footprint.height)
	var side:=minf((size.x-80.0)/width,(size.y-80.0)/height)
	return Rect2((size-Vector2(width,height)*side)/2,Vector2(width,height)*side)

func _point(index: int) -> Vector2:
	var rect:=_rect();var pin: Dictionary=model.pins[index]
	return rect.position+(Vector2(float(pin.position.x)+.5,float(pin.position.y)+.5)/Vector2(float(model.draft.footprint.width),float(model.draft.footprint.height)))*rect.size

func _grid(point: Vector2) -> Vector2i:
	var rect:=_rect();var q:=(point-rect.position)/rect.size
	return Vector2i(clampi(int(floor(q.x*float(model.draft.footprint.width))),0,int(model.draft.footprint.width)-1),clampi(int(floor(q.y*float(model.draft.footprint.height))),0,int(model.draft.footprint.height)-1))

func _draw() -> void:
	if model==null:return
	var rect:=_rect();draw_rect(rect,Color(str(model.draft.footprint.get("color","24775b"))))
	for x in range(1,int(model.draft.footprint.width)):
		var px:=rect.position.x+rect.size.x*x/float(model.draft.footprint.width)
		draw_line(Vector2(px,rect.position.y),Vector2(px,rect.end.y),Color(1,1,1,.13),1)
	for y in range(1,int(model.draft.footprint.height)):
		var py:=rect.position.y+rect.size.y*y/float(model.draft.footprint.height)
		draw_line(Vector2(rect.position.x,py),Vector2(rect.end.x,py),Color(1,1,1,.13),1)
	for i in model.pins.size():
		var p:=_point(i) if not (dragging and i==selected_index) else rect.position+(Vector2(preview_point)+Vector2(.5,.5))/Vector2(float(model.draft.footprint.width),float(model.draft.footprint.height))*rect.size
		draw_circle(p,12,Color("efc784") if i==selected_index else Color("c9d8d7"))
		draw_circle(p,5,Color("253941"))

func _gui_input(event: InputEvent) -> void:
	if model==null:return
	if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT:
		if event.pressed:
			for i in model.pins.size():
				if _point(i).distance_to(event.position)<18:selected_index=i;selected.emit(i);dragging=true;preview_point=_grid(event.position);queue_redraw();accept_event();return
			if _rect().has_point(event.position):add_requested.emit(_grid(event.position));accept_event()
		elif dragging:
			dragging=false;moved.emit(selected_index,preview_point);queue_redraw();accept_event()
	elif event is InputEventMouseMotion and dragging:
		preview_point=_grid(event.position);queue_redraw();accept_event()
