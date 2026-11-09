extends Control
const Model = preload("res://scripts/math_ui/plot_model.gd")
const Notation = preload("res://scripts/math_ui/math_notation.gd")
signal changed(state: Dictionary)
var descriptor: Dictionary = {}
var domain: Array = [-10.0,10.0]
var bounds: Array = [-5.0,5.0]
var points: Array = []
var paths: Array = []
var curve_names: Array[String]=[]
var axis_labels:Dictionary={0:[],1:[]}
var editable := true
var polar := false
var selected := -1
var panning := false
var role := "critical"
var font: Font = ThemeDB.fallback_font
const COLORS = [Color("52d4e4"),Color("ffa65a"),Color("bf9bff"),Color("8de69b")]

func _init() -> void:
	custom_minimum_size = Vector2(600,360)
	clip_contents = true
	focus_mode = Control.FOCUS_ALL
	resized.connect(_rebuild)

func configure(value: Dictionary, can_edit: bool = true) -> void:
	descriptor = value.duplicate(true)
	editable = can_edit
	domain = descriptor.get("domain",[-10.0,10.0]).duplicate()
	bounds = descriptor.get("range",[-5.0,5.0]).duplicate()
	if not Model.valid_bounds(domain): domain = [-10.0,10.0]
	if not Model.valid_bounds(bounds): bounds = [-5.0,5.0]
	polar = bool(descriptor.get("polar",false))
	# Diagram coordinates are reference data, never prefilled student answers.
	points = [] if editable else descriptor.get("points",[]).slice(0,256).duplicate(true)
	_rebuild()

func plot_rect() -> Rect2:
	return Rect2(Vector2(52,22),Vector2(maxf(100,size.x-75),maxf(100,size.y-62)))

func to_pixel(p: Vector2) -> Vector2:
	var r := plot_rect()
	return r.position + Vector2((p.x-float(domain[0]))/(float(domain[1])-float(domain[0]))*r.size.x,(float(bounds[1])-p.y)/(float(bounds[1])-float(bounds[0]))*r.size.y)

func to_math(p: Vector2) -> Vector2:
	var r := plot_rect()
	return Vector2(float(domain[0])+(p.x-r.position.x)/r.size.x*(float(domain[1])-float(domain[0])),float(bounds[1])-(p.y-r.position.y)/r.size.y*(float(bounds[1])-float(bounds[0])))

func snapshot() -> Dictionary:
	return {"points":points.duplicate(true),"domain":domain.duplicate(),"range":bounds.duplicate(),"polar":polar}

func restore(state: Dictionary) -> void:
	if Model.valid_bounds(state.get("domain",[])): domain = state.domain.duplicate()
	if Model.valid_bounds(state.get("range",[])): bounds = state.range.duplicate()
	polar = bool(state.get("polar",false))
	points.clear()
	for point in state.get("points",[]).slice(0,256):
		if point is Dictionary and is_finite(float(point.get("x",NAN))) and is_finite(float(point.get("y",NAN))): points.append(point.duplicate(true))
	_rebuild()

func answer() -> Dictionary:
	return {"points":points.duplicate(true)}

func add_point(x: float, y: float, point_role: String = "critical") -> void:
	if not editable or points.size() >= 256 or not is_finite(x) or not is_finite(y): return
	points.append({"x":x,"y":y,"role":point_role})
	selected = points.size()-1
	queue_redraw()
	changed.emit(snapshot())

func zoom(factor: float, center: Vector2) -> void:
	if not is_finite(factor) or factor<=0:return
	var next_x := [center.x+(float(domain[0])-center.x)*factor,center.x+(float(domain[1])-center.x)*factor]
	var next_y := [center.y+(float(bounds[0])-center.y)*factor,center.y+(float(bounds[1])-center.y)*factor]
	if not Model.valid_bounds(next_x) or not Model.valid_bounds(next_y): return
	domain = next_x
	bounds = next_y
	_rebuild()
	changed.emit(snapshot())

func _rebuild() -> void:
	if descriptor.get("kind") in ["complex_plane","unit_circle"]:
		# Equal units preserve true angles and radial circles while retaining all data.
		var rect:=plot_rect()
		var width:=float(domain[1])-float(domain[0])
		var height:=float(bounds[1])-float(bounds[0])
		var scale_value:=minf(rect.size.x/width,rect.size.y/height)
		var center:=Vector2((float(domain[0])+float(domain[1]))/2,(float(bounds[0])+float(bounds[1]))/2)
		domain=[center.x-rect.size.x/scale_value/2,center.x+rect.size.x/scale_value/2]
		bounds=[center.y-rect.size.y/scale_value/2,center.y+rect.size.y/scale_value/2]
	paths.clear()
	curve_names.clear()
	var curves: Array = descriptor.get("curves",[]).duplicate(true)
	if descriptor.has("function"): curves.push_front(descriptor.function)
	for f in curves.slice(0,8):
		curve_names.append(str(f.get("label",f.get("kind","curve"))))
		var chunks: Array = []
		var line := PackedVector2Array()
		if f.get("kind")=="samples":
			for sample in f.get("points",[]).slice(0,2048):
				var p:=to_pixel(Vector2(float(sample.get("x",NAN)),float(sample.get("y",NAN)))) if sample is Dictionary else Vector2(NAN,NAN)
				if not is_finite(p.x) or not is_finite(p.y) or not plot_rect().grow(0.01).has_point(p):
					if line.size()>1:chunks.append(line)
					line=PackedVector2Array()
				else:line.append(p)
			if line.size()>1:chunks.append(line)
			paths.append(chunks)
			continue
		var sample_count:=512
		if f.get("kind") in ["sin","cos"] and absf(float(f.get("period",0)))>1e-12:
			sample_count=maxi(128,int(ceil((float(domain[1])-float(domain[0]))/absf(float(f.period))*48)))
			if sample_count>2048:
				curve_names[-1]+=" · zoom to resolve"
				paths.append([])
				continue
		for i in range(sample_count+1):
			var x := lerpf(float(domain[0]),float(domain[1]),float(i)/sample_count)
			var y := Model.evaluate(f,x)
			var p := to_pixel(Vector2(x,y))
			if not is_finite(y) or not plot_rect().grow(0.01).has_point(p) or (line.size()>0 and absf(p.y-line[-1].y)>plot_rect().size.y):
				if line.size()>1: chunks.append(line)
				line = PackedVector2Array()
			else: line.append(p)
		if line.size()>1: chunks.append(line)
		paths.append(chunks)
	queue_redraw()

func _draw() -> void:
	axis_labels={0:[],1:[]}
	draw_rect(Rect2(Vector2.ZERO,size),Color("112431"))
	var r := plot_rect()
	draw_rect(r,Color("1a3442"))
	for axis in range(2):
		var limits: Array = domain if axis == 0 else bounds
		var tick_count:=clampi(int((r.size.x/70.0) if axis==0 else (r.size.y/35.0)),2,12)
		var raw_step:=(float(limits[1])-float(limits[0]))/tick_count
		var step := pow(10.0,floor(log(raw_step)/log(10.0)))
		var ratio:=raw_step/step
		step*=1 if ratio<=1 else 2 if ratio<=2 else 5 if ratio<=5 else 10
		var tick := ceilf(float(limits[0])/step)*step
		for i in range(40):
			if tick>float(limits[1])+step*0.01: break
			# Remove accumulated floating-point noise relative to this axis scale.
			tick=roundf(tick/step)*step
			if absf(tick)<step*0.000001:tick=0.0
			axis_labels[axis].append({"value":tick,"label":Notation.number(tick)})
			var p := to_pixel(Vector2(tick,0) if axis==0 else Vector2(0,tick))
			var a := Vector2(p.x,r.position.y) if axis==0 else Vector2(r.position.x,p.y)
			var b := Vector2(p.x,r.end.y) if axis==0 else Vector2(r.end.x,p.y)
			draw_line(a,b,Color("34515e"),1)
			draw_string(font,Vector2(p.x-12,r.end.y+20) if axis==0 else Vector2(3,p.y+5),Notation.number(tick),HORIZONTAL_ALIGNMENT_LEFT,-1,13,Color("bdd1db"))
			tick+=step
	var zero := to_pixel(Vector2.ZERO)
	if zero.x>=r.position.x and zero.x<=r.end.x: draw_line(Vector2(zero.x,r.position.y),Vector2(zero.x,r.end.y),Color.WHITE,1.5)
	if zero.y>=r.position.y and zero.y<=r.end.y: draw_line(Vector2(r.position.x,zero.y),Vector2(r.end.x,zero.y),Color.WHITE,1.5)
	if polar or descriptor.get("kind") == "unit_circle":
		var max_radius := minf(maxf(absf(float(domain[0])),absf(float(domain[1]))),maxf(absf(float(bounds[0])),absf(float(bounds[1]))))
		for radius in range(1,mini(12,int(max_radius)+1)):
			var ring := PackedVector2Array()
			for i in range(97): ring.append(to_pixel(Vector2(cos(i*TAU/96),sin(i*TAU/96))*radius))
			draw_polyline(ring,Color("527180"),1,true)
		for i in range(12): draw_line(zero,to_pixel(Vector2(cos(i*TAU/12),sin(i*TAU/12))*max_radius),Color("34515e"),1,true)
	for i in range(paths.size()):
		for line in paths[i]: draw_polyline(line,COLORS[i%COLORS.size()],2,true)
		if i<4:draw_string(font,Vector2(70+i*140,16),curve_names[i],HORIZONTAL_ALIGNMENT_LEFT,-1,13,COLORS[i%4])
	var phasors:Array=descriptor.get("phasors",[]).slice(0,8)
	if not phasors.is_empty():
		var inset:=r.end-Vector2(78,r.size.y-78)
		draw_circle(inset,55,Color("193341"))
		draw_circle(inset,55,Color("9bb8c7"),false,1,true)
		var max_mag:=0.001
		for phasor in phasors:max_mag=maxf(max_mag,absf(float(phasor.get("magnitude",1))))
		for i in range(phasors.size()):
			var p:Dictionary=phasors[i]
			var angle:=float(p.get("angle",0))
			if p.get("angle_unit","degrees")!="radians":angle=deg_to_rad(angle)
			var tip:=inset+Vector2(cos(angle),-sin(angle))*55*float(p.get("magnitude",1))/max_mag
			draw_line(inset,tip,COLORS[i%4],2,true);draw_circle(tip,3,COLORS[i%4])
	for marker in descriptor.get("markers",[]).slice(0,32):
		var x := to_pixel(Vector2(float(marker.get("x",0)),0)).x
		if x<r.position.x or x>r.end.x:continue
		draw_line(Vector2(x,r.position.y),Vector2(x,r.end.y),Color("e7b45c"),1)
		draw_string(font,Vector2(x+3,r.position.y+15),str(marker.get("label","period")),HORIZONTAL_ALIGNMENT_LEFT,-1,13,Color("e7b45c"))
	for i in range(points.size()):
		var point: Dictionary = points[i]
		var p := to_pixel(Vector2(float(point.x),float(point.y)))
		if not r.has_point(p): continue
		if descriptor.get("kind") in ["complex_plane","unit_circle"]: draw_line(zero,p,COLORS[i%4],2,true)
		draw_circle(p,6,Color("ffffff") if i==selected else COLORS[i%4])
		var label := str(point.get("label",point.get("role","")))
		if descriptor.get("kind") == "complex_plane":
			var v := Vector2(float(point.x),float(point.y))
			var radians:bool=descriptor.get("angle_unit","degrees")=="radians"
			label += " (%s, %s)"%[Notation.number(v.x),Notation.number(v.y)]
			if i==selected or (selected<0 and i==0):
				var detail:="%s + j(%s)  |z|=%s  ∠ %s%s"%[Notation.number(v.x),Notation.number(v.y),Notation.number(v.length()),Notation.number(v.angle() if radians else rad_to_deg(v.angle()))," rad" if radians else "°"]
				draw_string(font,Vector2(r.position.x,size.y-2),detail,HORIZONTAL_ALIGNMENT_LEFT,-1,13,COLORS[i%4])
		elif descriptor.get("kind")=="unit_circle":
			var angle:=atan2(float(point.y),float(point.x))
			label+=" %s%s"%[Notation.number(angle if descriptor.get("angle_unit")=="radians" else rad_to_deg(angle))," rad" if descriptor.get("angle_unit")=="radians" else "°"]
		draw_string(font,p+Vector2(9,-8),label,HORIZONTAL_ALIGNMENT_LEFT,-1,14,COLORS[i%4])
	draw_string(font,Vector2(r.end.x-20,size.y-3),str(descriptor.get("x_label","Re" if descriptor.get("kind")=="complex_plane" else "x")),HORIZONTAL_ALIGNMENT_LEFT,-1,15,Color.WHITE)
	draw_string(font,Vector2(4,16),str(descriptor.get("y_label","Im" if descriptor.get("kind")=="complex_plane" else "y")),HORIZONTAL_ALIGNMENT_LEFT,-1,15,Color.WHITE)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN] and event.pressed:
			zoom(0.8 if event.button_index==MOUSE_BUTTON_WHEEL_UP else 1.25,to_math(event.position))
			accept_event()
		elif event.button_index==MOUSE_BUTTON_MIDDLE:
			panning=event.pressed
		elif event.button_index==MOUSE_BUTTON_LEFT:
			if not event.pressed: return
			grab_focus()
			if not plot_rect().has_point(event.position): return
			selected=-1
			for i in range(points.size()):
				if to_pixel(Vector2(float(points[i].x),float(points[i].y))).distance_to(event.position)<12: selected=i; break
			if selected<0 and editable:
				var p := to_math(event.position)
				add_point(p.x,p.y,role)
			queue_redraw()
			accept_event()
	elif event is InputEventMouseMotion:
		if panning:
			var delta := to_math(Vector2.ZERO)-to_math(event.relative)
			var next_x:=[float(domain[0])+delta.x,float(domain[1])+delta.x]
			var next_y:=[float(bounds[0])+delta.y,float(bounds[1])+delta.y]
			if not Model.valid_bounds(next_x) or not Model.valid_bounds(next_y):return
			domain=next_x
			bounds=next_y
			_rebuild()
			changed.emit(snapshot())
		elif editable and selected>=0 and event.button_mask&MOUSE_BUTTON_MASK_LEFT:
			var p := to_math(event.position)
			points[selected].x=p.x; points[selected].y=p.y
			queue_redraw()
			changed.emit(snapshot())
	elif event is InputEventKey and event.pressed and event.keycode==KEY_DELETE and editable and selected>=0:
		points.remove_at(selected);selected=-1;queue_redraw();changed.emit(snapshot())
