extends Control
signal area_erased(point: Vector2, radius: Vector2)
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
	if size.x<=0 or size.y<=0:return
	var center := (point/size).clamp(Vector2.ZERO,Vector2.ONE)
	var radius := Vector2.ONE*eraser_radius/size
	var remaining := erase_area(strokes,center,radius)
	if remaining==strokes or remaining.size()>100:return
	strokes=remaining
	area_erased.emit(center,radius)
	queue_redraw()

static func erase_area(page: Array, center: Vector2, radius: Vector2) -> Array:
	var remaining := []
	for stroke in page:
		var points: Array=stroke if stroke is Array else stroke.get("points",[])
		if points.is_empty():continue
		if points.size()==1:
			if ((points[0]-center)/radius).length_squared()>=1:remaining.append(stroke)
			continue
		var run: Array=[]
		var pieces: Array=[]
		var removed := false
		for index in range(1,points.size()):
			var a: Vector2=points[index-1]
			var b: Vector2=points[index]
			var origin := (a-center)/radius
			var step := (b-a)/radius
			var length := step.length_squared()
			if length<.00000001:continue
			var along := origin.dot(step)
			var discriminant := along*along-length*(origin.length_squared()-1)
			var cuts: Array[float]=[0.0,1.0]
			if discriminant>0:
				var root := sqrt(discriminant)
				cuts.insert(1,clampf((-along-root)/length,0,1))
				cuts.insert(2,clampf((-along+root)/length,0,1))
			for part in range(1,cuts.size()):
				var lo := cuts[part-1]
				var hi := cuts[part]
				if is_equal_approx(lo,hi):continue
				if (origin+step*((lo+hi)*.5)).length_squared()<1:
					_append_run(pieces,stroke,run)
					removed=true
					run=[]
					continue
				var start := a.lerp(b,lo)
				if run.is_empty():run.append(start)
				run.append(a.lerp(b,hi))
		if removed:
			_append_run(pieces,stroke,run)
			remaining.append_array(pieces)
		else:remaining.append(stroke)
	return remaining

static func _append_run(result: Array, stroke: Variant, points: Array) -> void:
	if points.is_empty():return
	if stroke is Array:
		result.append(points)
	else:
		var fragment: Dictionary=stroke.duplicate()
		fragment.points=points
		result.append(fragment)
