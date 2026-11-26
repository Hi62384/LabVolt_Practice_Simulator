extends Control

const Document = preload("res://scripts/campus/items/decoration_document.gd")
signal finished(image: Image)
var brush := Color("e8fbec")
var radius := 4
var hardness := .8
var tool := "Brush"
var paint: Image
var texture: ImageTexture
var anchor := Vector2i.ZERO
var last := Vector2i.ZERO
var base: Image
var dragging := false

func load_pixels(data: String) -> void:
	paint=Document.decode(data)
	if paint==null:
		paint=Image.create_empty(Document.PIXELS,Document.PIXELS,false,Image.FORMAT_RGBA8)
	else:
		paint.convert(Image.FORMAT_RGBA8)
		paint.resize(Document.PIXELS,Document.PIXELS,Image.INTERPOLATE_BILINEAR)
	texture=ImageTexture.create_from_image(paint)
	queue_redraw()

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO,size),Color("122938"))
	for row in 8:
		for column in 8:
			if (row+column)%2==0:draw_rect(Rect2(Vector2(column,row)*size/8.0,size/8.0),Color("1d3647"))
	if texture!=null:draw_texture_rect(texture,Rect2(Vector2.ZERO,size),false)

func _gui_input(event: InputEvent) -> void:
	if paint==null:return
	if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT:
		var point:=_pixel(event.position)
		if event.pressed:
			anchor=point
			last=point
			dragging=true
			base=paint.duplicate()
			if tool=="Fill":_fill(point)
			elif tool in ["Brush","Eraser"]:_dab(point)
			_update()
		elif dragging:
			dragging=false
			finished.emit(paint.duplicate())
			base=null
		accept_event()
	elif event is InputEventMouseMotion and dragging:
		var point:=_pixel(event.position)
		if tool in ["Brush","Eraser"]:
			_line(last,point)
			last=point
		elif tool in ["Line","Rectangle","Ellipse"]:
			paint=base.duplicate()
			if tool=="Line":_line(anchor,point)
			elif tool=="Rectangle":
				var side:=Vector2i(point.x,anchor.y)
				var other:=Vector2i(anchor.x,point.y)
				_line(anchor,side)
				_line(side,point)
				_line(point,other)
				_line(other,anchor)
			else:
				var center: Vector2=Vector2(anchor+point)*.5
				var span: Vector2=Vector2((point-anchor).abs())*.5
				var prior:=Vector2i(center+Vector2(span.x,0))
				for index in range(1,81):
					var angle:=TAU*float(index)/80.0
					var next:=Vector2i(center+Vector2(cos(angle),sin(angle))*span)
					_line(prior,next)
					prior=next
		_update()
		accept_event()

func _pixel(point: Vector2) -> Vector2i:
	return Vector2i((point/size*float(Document.PIXELS)).clamp(Vector2.ZERO,Vector2.ONE*float(Document.PIXELS-1)))

func _line(from: Vector2i,to: Vector2i) -> void:
	var steps:=maxi(1,ceili(Vector2(from).distance_to(to)/maxf(1.0,float(radius)*.55)))
	for index in range(steps+1):_dab(Vector2i(Vector2(from).lerp(to,float(index)/float(steps))))

func _dab(at: Vector2i) -> void:
	for y in range(maxi(0,at.y-radius),mini(Document.PIXELS,at.y+radius+1)):
		for x in range(maxi(0,at.x-radius),mini(Document.PIXELS,at.x+radius+1)):
			var distance:=Vector2(x-at.x,y-at.y).length()/float(radius+1)
			if distance>=1.0:continue
			var strength:=brush.a*(1.0-smoothstep(hardness,1.0,distance)) if hardness<.999 else brush.a
			var existing:=paint.get_pixel(x,y)
			if tool=="Eraser":
				existing.a*=1.0-strength
				paint.set_pixel(x,y,existing)
			else:
				var stroke:=brush
				stroke.a=strength
				paint.set_pixel(x,y,existing.blend(stroke))

func _fill(at: Vector2i) -> void:
	var target:=paint.get_pixelv(at)
	var replacement:=target.blend(brush)
	if target.to_rgba32()==replacement.to_rgba32():return
	var todo: Array[Vector2i]=[at]
	while not todo.is_empty():
		var point: Vector2i=todo.pop_back()
		if not Rect2i(0,0,Document.PIXELS,Document.PIXELS).has_point(point) or paint.get_pixelv(point)!=target:continue
		paint.set_pixelv(point,replacement)
		for offset in [Vector2i.UP,Vector2i.DOWN,Vector2i.LEFT,Vector2i.RIGHT]:todo.append(point+offset)

func _update() -> void:
	texture.update(paint)
	queue_redraw()
