extends Control

const COLORS := [Color("72ebd4"),Color("ffce72"),Color("aaaaff"),Color("fa91ba"),Color("91cafe"),Color("bce589")]
var data: Array[PackedVector3Array]=[]
var kind:=0
var extent:=10.0

func _ready() -> void:
	custom_minimum_size.y=200
	clip_contents=true
	resized.connect(queue_redraw)

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO,size),Color("0b2334"))
	var center:=size*.5
	var radial:=minf(size.x,size.y)*.44
	var lighter:=Color("406471")
	var grid:=Color("284454")
	if kind==1:
		for i in range(1,6):draw_arc(center,radial*i/5.0,0,TAU,48,grid,1,true)
		for index in 12:
			var angle:=TAU*index/12.0
			draw_line(center,center+Vector2.from_angle(angle)*radial,grid,1,true)
	elif kind==2:
		for index in range(-5,6):
			var lane:=extent*index/5.0
			draw_line(_point(Vector3(-extent,lane,0)),_point(Vector3(extent,lane,0)),grid,1,true)
			draw_line(_point(Vector3(lane,-extent,0)),_point(Vector3(lane,extent,0)),grid,1,true)
		draw_line(_point(Vector3(0,0,-extent)),_point(Vector3(0,0,extent)),lighter,1,true)
	else:
		for idx in range(-5,6):
			var x:=center.x+radial*idx/5.0
			var y:=center.y+radial*idx/5.0
			draw_line(Vector2(x,0),Vector2(x,size.y),lighter if idx==0 else grid,1)
			draw_line(Vector2(0,y),Vector2(size.x,y),lighter if idx==0 else grid,1)
	for index in data.size():
		var line:=PackedVector2Array()
		for vertex in data[index]:
			var point:=_point(vertex)
			if not vertex.is_finite() or (not line.is_empty() and point.distance_to(line[-1])>radial*.75):
				if line.size()>1:draw_polyline(line,COLORS[index%COLORS.size()],1.6,true)
				line.clear()
			if vertex.is_finite():line.append(point)
		if line.size()>1:draw_polyline(line,COLORS[index%COLORS.size()],1.6,true)

func _point(point: Vector3) -> Vector2:
	var scale_factor:=minf(size.x,size.y)*.44/extent
	if kind==2:return size*.5+Vector2((point.x-point.y)*.46,(point.x+point.y)*.19-point.z*.6)*scale_factor
	return size*.5+Vector2(point.x,-point.y)*scale_factor
