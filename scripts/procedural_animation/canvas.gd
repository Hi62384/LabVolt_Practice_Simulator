extends Control
## Reusable letterboxed drawing surface. May be mounted in a SubViewport.
const Document=preload("res://scripts/procedural_animation/document.gd")
const Playback=preload("res://scripts/procedural_animation/playback.gd")
const INK:=Color("e2edf4")
const ACCENT:=Color("46dfc1")
const TICK:=1./24.
signal frame_changed
var player:=Playback.new()
var accumulator:=0.
var plot_cache: Dictionary={}
var sync_key:=""
var font: Font

func _ready() -> void:
	mouse_filter=MOUSE_FILTER_IGNORE
	clip_contents=true
	font=ThemeDB.fallback_font
	resized.connect(queue_redraw)

func show_checkpoint(key: String,state: Dictionary) -> bool:
	if key!=sync_key:
		if not player.restore_checkpoint(state):return false
		plot_cache.clear()
		sync_key=key
	elif absf(player.clock-float(state.time))>.4:player.seek(float(state.time))
	queue_redraw()
	frame_changed.emit()
	return true

func _process(delta: float) -> void:
	if not is_visible_in_tree() or player.scene.is_empty() or not player.playing:return
	accumulator+=delta
	if accumulator<TICK:return
	player.advance(accumulator)
	accumulator=0.
	queue_redraw()
	frame_changed.emit()

func _draw() -> void:
	if player.scene.is_empty() or font==null:return
	var zoom:=minf(size.x/Document.SIZE.x,size.y/Document.SIZE.y)
	if zoom<=0.:return
	var offset:=(size-Document.SIZE*zoom)*.5
	var frame:=Transform2D(0.,Vector2.ONE*zoom,0.,offset)
	draw_set_transform_matrix(frame)
	draw_rect(Rect2(Vector2.ZERO,Document.SIZE),Color("0b2030"))
	draw_rect(Rect2(Vector2(1.,1.),Document.SIZE-Vector2(2.,2.)),Color("2d5969"),false,2.)
	draw_rect(Rect2(0,0,960,76),Color("103344"))
	draw_rect(Rect2(20,20,5,33),ACCENT)
	draw_string(font,Vector2(39,39),player.scene.title,HORIZONTAL_ALIGNMENT_LEFT,892.,32,INK)
	if not str(player.scene.get("subtitle","")).is_empty():
		draw_string(font,Vector2(40,63),player.scene.subtitle,HORIZONTAL_ALIGNMENT_LEFT,888.,19,Color("a8c7d7"))
	for x in range(32,960,48):
		for y in range(100,490,48):draw_circle(Vector2(x,y),1.,Color("214354"))
	for item in player.ordered:
		if item.type=="group":continue
		var pose:=_pose(item)
		if float(pose.alpha)<=0.:continue
		var transform: Transform2D=frame*pose.transform
		draw_set_transform_matrix(transform)
		_draw_object(item,float(pose.alpha))
	draw_set_transform_matrix(frame)
	var progress:=player.clock/float(player.scene.duration)
	draw_rect(Rect2(18,505,924,3),Color("254b5a"))
	draw_rect(Rect2(18,505,924*progress,3),ACCENT)

func _pose(item: Dictionary) -> Dictionary:
	var position:=Vector2(player.property(item,"x"),player.property(item,"y"))
	var scale_value:=clampf(player.property(item,"scale"),.02,8.)
	var alpha:=clampf(player.property(item,"alpha"),0.,1.)
	var transform:=Transform2D(deg_to_rad(player.property(item,"rotation")),Vector2.ONE*scale_value,0.,position)
	var parent: String=item.get("parent","")
	while not parent.is_empty():
		var group: Dictionary=player.objects[parent]
		var amount:=clampf(player.property(group,"scale"),.02,8.)
		transform=Transform2D(deg_to_rad(player.property(group,"rotation")),Vector2.ONE*amount,0.,Vector2(player.property(group,"x"),player.property(group,"y")))*transform
		alpha*=clampf(player.property(group,"alpha"),0.,1.)
		parent=group.get("parent","")
	return {"transform":transform,"alpha":alpha}

func _draw_object(item: Dictionary,alpha: float) -> void:
	var pen:=Color(item.get("color","e2edf4"))
	var fill:=Color(item.get("fill","00000000"))
	pen.a*=alpha
	fill.a*=alpha
	var stroke:=clampf(player.property(item,"stroke"),.5,20.)
	var dims:=Vector2(player.property(item,"width"),player.property(item,"height")).clamp(Vector2.ONE,Vector2(1920.,1040.))
	var radius:=clampf(player.property(item,"radius"),.5,500.)
	var progress:=clampf(player.property(item,"progress"),0.,1.)
	if item.id==player.highlight:
		draw_rect(Rect2(Vector2(-8,-14),Vector2(maxf(dims.x,radius*2.),maxf(dims.y,radius*2.))).grow(10.),Color("ffc67177"),false,3.)
	match str(item.type):
		"rectangle":
			var box:=Rect2(Vector2.ZERO,dims)
			if fill.a>0.:draw_rect(box,fill)
			draw_rect(box,pen,false,stroke)
		"circle":
			if fill.a>0.:draw_circle(Vector2.ZERO,radius,fill,true,-1.,true)
			draw_arc(Vector2.ZERO,radius,0.,TAU*progress,48,pen,stroke,true)
		"ellipse":
			var outline:=PackedVector2Array()
			for i in 49:
				var angle:=TAU*float(i)/48.*progress
				outline.append(Vector2(cos(angle),sin(angle))*dims*.5)
			if fill.a>0. and progress>=1.:draw_colored_polygon(outline.slice(0,-1),fill)
			draw_polyline(outline,pen,stroke,true)
		"line","arrow":
			var endpoint:=Vector2(player.property(item,"width"),player.property(item,"height"))
			_line(Vector2.ZERO,endpoint*progress,pen,stroke,item.get("dash",false),item.type=="arrow")
		"path","polygon":
			var points:=PackedVector2Array()
			for p in item.points:points.append(Vector2(p[0],p[1]))
			if item.type=="polygon":
				if fill.a>0.:draw_colored_polygon(points,fill)
				points.append(points[0])
			_trace(points,pen,stroke,progress,item.get("dash",false))
		"text","equation":
			var label:=_caption(str(item.get("text","")))
			draw_string(font,Vector2.ZERO,label.substr(0,ceili(label.length()*progress)),HORIZONTAL_ALIGNMENT_LEFT,dims.x,clampi(roundi(player.property(item,"font")),13,90),pen)
		"graph":_graph(item,dims,pen,stroke,progress)
		"particles":
			var count:=int(item.get("count",12))
			var phase:=player.clock*.4
			for i in count:
				var p:=Vector2(fposmod(float(i)/count+phase,1.)*dims.x,fposmod(i*.618,1.)*dims.y)
				draw_circle(p,minf(20.,radius),pen,true,-1.,true)

func _caption(text: String) -> String:
	for id in player.compiled.names:
		var slot: int=player.compiled.names.find(id)
		if text.contains("{"+id+"}"):text=text.replace("{"+id+"}","%.2f"%float(player.inputs[slot]))
	return text

func _line(from: Vector2,to: Vector2,ink: Color,width: float,dash: bool,arrow: bool) -> void:
	if from.is_equal_approx(to):return
	if dash:draw_dashed_line(from,to,ink,width,12.)
	else:draw_line(from,to,ink,width,true)
	if arrow:
		var heading:=(to-from).normalized()
		draw_colored_polygon(PackedVector2Array([to,to-heading.rotated(.44)*18,to-heading.rotated(-.44)*18]),ink)

func _trace(points: PackedVector2Array,ink: Color,width: float,progress: float,dash: bool) -> void:
	var work:=float(points.size()-1)*progress
	for i in mini(ceili(work),points.size()-1):
		_line(points[i],points[i].lerp(points[i+1],minf(1.,work-i)),ink,width,dash,false)

func _graph(item: Dictionary,dims: Vector2,pen: Color,stroke: float,progress: float) -> void:
	var x0:=player.property(item,"x_min")
	var x1:=player.property(item,"x_max")
	var y0:=player.property(item,"y_min")
	var y1:=player.property(item,"y_max")
	if x1-x0<.0001 or y1-y0<.0001:return
	draw_rect(Rect2(Vector2.ZERO,dims),Color("102f40"))
	for i in range(1,8):
		var gx:=dims.x*i/8.
		draw_line(Vector2(gx,0.),Vector2(gx,dims.y),Color("254c5b"))
	for j in range(1,5):
		var gy:=dims.y*j/5.
		draw_line(Vector2(0.,gy),Vector2(dims.x,gy),Color("254c5b"))
	var axes:=Vector2(clampf(-x0/(x1-x0),0.,1.),clampf(y1/(y1-y0),0.,1.))*dims
	draw_line(Vector2(0.,axes.y),Vector2(dims.x,axes.y),Color("87a5b1"),2.,true)
	draw_line(Vector2(axes.x,0.),Vector2(axes.x,dims.y),Color("87a5b1"),2.,true)
	var dynamic: bool=player.compiled.animated_plots.get(item.id,false)
	var key: Array=[player.revision,x0,x1,y0,y1,player.clock if dynamic else 0.]
	var cached: Dictionary=plot_cache.get(item.id,{})
	if cached.get("key")!=key:
		var values:=PackedFloat32Array()
		for i in 97:values.append(player.sample(item.id,lerpf(x0,x1,float(i)/96.)))
		cached={"key":key,"values":values}
		plot_cache[item.id]=cached
	var points: PackedFloat32Array=cached.values
	for i in mini(96,ceili(progress*96.)):
		var a:=float(points[i]);var b:=float(points[i+1])
		if not is_finite(a) or not is_finite(b) or a<y0 or a>y1 or b<y0 or b>y1:continue
		draw_line(Vector2(float(i)/96.,(y1-a)/(y1-y0))*dims,Vector2(float(i+1)/96.,(y1-b)/(y1-y0))*dims,pen,stroke,true)
	draw_string(font,Vector2(4,dims.y-8),"%.2f"%x0,HORIZONTAL_ALIGNMENT_LEFT,90.,16,INK)
	draw_string(font,Vector2(dims.x-72,dims.y-8),"%.2f"%x1,HORIZONTAL_ALIGNMENT_RIGHT,68.,16,INK)
