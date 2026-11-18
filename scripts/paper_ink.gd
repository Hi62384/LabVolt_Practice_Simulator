extends Control
signal area_erased(point: Vector2, radius: Vector2, from: Vector2)
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
		if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT and event.pressed:
			erase_at(event.position);accept_event()
		elif event is InputEventMouseMotion and event.button_mask & MOUSE_BUTTON_MASK_LEFT:
			erase_at(event.position,event.position-event.relative);accept_event()
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
		if hardness<1.0 and not points.is_empty():
			var halo := color;halo.a*=0.22*(1.0-hardness)
			_draw_round_stroke(points,halo,width*(1.0+2.0*(1.0-hardness)))
		_draw_round_stroke(points,color,width)

func _draw_round_stroke(points: Array, color: Color, width: float) -> void:
	for i in range(1,points.size()):
		draw_line(points[i-1]*size,points[i]*size,color,width,true)
	for point in points:
		draw_circle(point*size,width*.5,color,true,-1,true)

func erase_at(point: Vector2, previous := Vector2.INF) -> void:
	if size.x<=0 or size.y<=0:return
	var center := (point/size).clamp(Vector2.ZERO,Vector2.ONE)
	var radius := Vector2.ONE*eraser_radius/size
	var from := center if not previous.is_finite() else (previous/size).clamp(Vector2.ZERO,Vector2.ONE)
	var remaining := erase_area(strokes,center,radius,from)
	if remaining==strokes:return
	strokes=remaining
	area_erased.emit(center,radius,from)
	queue_redraw()

static func erase_area(page: Array, center: Vector2, radius: Vector2, previous := Vector2.INF) -> Array:
	var sweep_start := center if not previous.is_finite() else previous
	var remaining := []
	for stroke in page:
		var points: Array=stroke if stroke is Array else stroke.get("points",[])
		if points.is_empty():continue
		var width := 2.0 if stroke is Array else float(stroke.get("width",2.0))
		var horizontal := width / 1560.0
		var brush := radius+Vector2(horizontal,horizontal*radius.y/radius.x)
		var sweep := (center-sweep_start)/brush
		var low := center.min(sweep_start)-brush
		var high := center.max(sweep_start)+brush
		if points.size()==1:
			if not _inside_eraser((points[0]-sweep_start)/brush,sweep):remaining.append(stroke)
			continue
		var run: Array=[]
		var pieces: Array=[]
		var removed := false
		for index in range(1,points.size()):
			var a: Vector2=points[index-1]
			var b: Vector2=points[index]
			if maxf(a.x,b.x)<low.x or minf(a.x,b.x)>high.x or maxf(a.y,b.y)<low.y or minf(a.y,b.y)>high.y:
				if run.is_empty():run.append(a)
				run.append(b)
				continue
			var origin := (a-sweep_start)/brush
			var step := (b-a)/brush
			if step.length_squared()<.00000001:
				if _inside_eraser(origin,sweep):
					_append_run(pieces,stroke,run)
					removed=true
					run=[]
				continue
			var cuts: Array[float]=[0.0,1.0]
			_add_circle_intersections(cuts,origin,step)
			if not sweep.is_zero_approx():
				_add_circle_intersections(cuts,origin-sweep,step)
				var normal := sweep.normalized().orthogonal()
				var across := normal.dot(step)
				if not is_zero_approx(across):
					var distance := normal.dot(origin)
					cuts.append(clampf((1.0-distance)/across,0,1))
					cuts.append(clampf((-1.0-distance)/across,0,1))
			cuts.sort()
			for part in range(1,cuts.size()):
				var lo := cuts[part-1]
				var hi := cuts[part]
				if is_equal_approx(lo,hi):continue
				if _inside_eraser(origin+step*((lo+hi)*.5),sweep):
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

static func _inside_eraser(point: Vector2, sweep: Vector2) -> bool:
	var nearest := Vector2.ZERO if sweep.is_zero_approx() else Geometry2D.get_closest_point_to_segment(point,Vector2.ZERO,sweep)
	return point.distance_squared_to(nearest)<1.0

static func _add_circle_intersections(cuts: Array[float],origin: Vector2,step: Vector2) -> void:
	var length := step.length_squared()
	var along := origin.dot(step)
	var discriminant := along*along-length*(origin.length_squared()-1.0)
	if discriminant<=0:return
	var root := sqrt(discriminant)
	cuts.append(clampf((-along-root)/length,0,1))
	cuts.append(clampf((-along+root)/length,0,1))

static func _append_run(result: Array, stroke: Variant, points: Array) -> void:
	if points.is_empty():return
	if stroke is Array:
		result.append(points)
	else:
		var fragment: Dictionary=stroke.duplicate()
		fragment.points=points
		result.append(fragment)
