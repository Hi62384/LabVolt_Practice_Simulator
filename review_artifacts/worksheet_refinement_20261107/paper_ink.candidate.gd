extends Control
signal stroke_erased(index: int)
var eraser := false
signal stroke_finished(stroke: Dictionary)
var strokes: Array=[]
var current: Array=[]
var editable := true
var background := true
var pencil_color := Color("263743")
var pencil_width := 2.0
var pencil_hardness := 0.8
var pencil_opacity := 1.0
var eraser_radius := 12.0
var pressure_sum := 0.0
var pressure_samples := 0
func _ready() -> void:
	mouse_filter=Control.MOUSE_FILTER_STOP
func _gui_input(event: InputEvent) -> void:
	if not editable:return
	if eraser:
		if (event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT and event.pressed) or (event is InputEventMouseMotion and event.button_mask & MOUSE_BUTTON_MASK_LEFT):erase_at(event.position);accept_event()
		return
	if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT:
		if event.pressed:
			current=[(event.position/size).clamp(Vector2.ZERO,Vector2.ONE)]
			pressure_sum=0.0;pressure_samples=0
		else:finish()
		queue_redraw();accept_event()
	elif event is InputEventMouseMotion and event.button_mask & MOUSE_BUTTON_MASK_LEFT and not current.is_empty():
		var point: Vector2=(event.position/size).clamp(Vector2.ZERO,Vector2.ONE)
		if (point-current.back()).length()>.001:
			current.append(point)
			if event.pressure>0.0:
				pressure_sum+=clampf(event.pressure,0.05,1.0)
				pressure_samples+=1
		if current.size()>=250:
			finish();current=[point]
		queue_redraw();accept_event()
func finish() -> void:
	if current.is_empty():return
	var effective_width := pencil_width*(pressure_sum/pressure_samples if pressure_samples>0 else 1.0)
	var stroke := {"points":current.duplicate(),"color":pencil_color.to_html(false),"width":clampf(effective_width,1.0,32.0),"hardness":pencil_hardness,"opacity":pencil_opacity}
	pressure_sum=0.0;pressure_samples=0
	strokes.append(stroke);current.clear();stroke_finished.emit(stroke);queue_redraw()
func _draw() -> void:
	if background:draw_rect(Rect2(Vector2.ZERO,size),Color("fcfaf2"))
	for item in strokes+[{"points":current,"color":pencil_color.to_html(false),"width":pencil_width,"hardness":pencil_hardness,"opacity":pencil_opacity}]:
		var points: Array=item if item is Array else item.get("points",[])
		var color := Color("263743") if item is Array else Color(item.get("color","263743"))
		var width: float=2.0 if item is Array else float(item.get("width",2.))
		var hardness := clampf(float(item.get("hardness",1.0)),0.0,1.0)
		color.a*=clampf(float(item.get("opacity",1.0)),0.05,1.0)
		width*=size.x/780.
		if hardness<1.0 and points.size()>0:
			var halo := color;halo.a*=0.22*(1.0-hardness)
			for i in range(1,points.size()):draw_line(points[i-1]*size,points[i]*size,halo,width*(1.0+2.0*(1.0-hardness)),true)
		if points.size()==1:draw_circle(points[0]*size,width*.5,color)
		for i in range(1,points.size()):draw_line(points[i-1]*size,points[i]*size,color,width,true)

func erase_at(point: Vector2) -> void:
	for i in range(strokes.size()-1,-1,-1):
		var points: Array=strokes[i] if strokes[i] is Array else strokes[i].get("points",[])
		for j in points.size():
			var nearest: Vector2=points[j]*size if j==0 else Geometry2D.get_closest_point_to_segment(point,points[j-1]*size,points[j]*size)
			if point.distance_to(nearest)<eraser_radius:
				strokes.remove_at(i);stroke_erased.emit(i);queue_redraw();return
