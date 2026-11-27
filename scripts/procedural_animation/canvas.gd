extends Control
## Reusable letterboxed drawing surface. May be mounted in a SubViewport.
const Document=preload("res://scripts/procedural_animation/document.gd")
const Playback=preload("res://scripts/procedural_animation/playback.gd")
const ExpressionView=preload("res://scripts/math_ui/expression_view.gd")
const INK:=Color("e2edf4")
const ACCENT:=Color("46dfc1")
const TICK:=1./24.
signal frame_changed
var player:=Playback.new()
var accumulator:=0.
var plot_cache: Dictionary={}
var notation_cache: Dictionary={}
var sync_key:=""
var font: Font
var data_status:=""
var stage_clip:=Control.new()
var artwork:=Node2D.new()

func _ready() -> void:
	mouse_filter=MOUSE_FILTER_IGNORE
	clip_contents=true
	font=ThemeDB.fallback_font
	stage_clip.mouse_filter=MOUSE_FILTER_IGNORE
	stage_clip.clip_contents=true
	add_child(stage_clip)
	stage_clip.add_child(artwork)
	artwork.draw.connect(_draw_artwork)
	resized.connect(_redraw_frame)

func show_checkpoint(key: String,state: Dictionary) -> bool:
	var had_cues: bool=not player.scene.get("cues",[]).is_empty()
	if key!=sync_key:
		if not player.restore_checkpoint(state):return false
		plot_cache.clear()
		notation_cache.clear()
		sync_key=key
	elif absf(player.clock-float(state.time))>.4:player.seek(float(state.time))
	player.playing=bool(state.playing)
	if player.set_live_parameters(state.get("live_parameters",{})):plot_cache.clear()
	player.set_live_series(state.get("live_series",{}))
	var status:=str(state.get("data_status",""))
	var has_cues: bool=not player.scene.get("cues",[]).is_empty()
	if status!=data_status or had_cues!=has_cues:
		data_status=status
		_redraw_frame()
	else:_queue_frame()
	frame_changed.emit()
	return true

func _process(delta: float) -> void:
	if not is_visible_in_tree() or player.scene.is_empty() or not player.playing:return
	accumulator+=delta
	if accumulator<TICK:return
	player.advance(accumulator)
	accumulator=0.
	_queue_frame()
	frame_changed.emit()

func _redraw_frame() -> void:
	var zoom:=minf(size.x/Document.SIZE.x,size.y/Document.SIZE.y)
	var offset:=(size-Document.SIZE*zoom)*.5
	var footer:=503. if data_status.is_empty() else 480.
	if not player.scene.get("cues",[]).is_empty():footer-=23.
	stage_clip.position=offset+Vector2(0.,76.)*zoom
	stage_clip.size=Vector2(Document.SIZE.x,footer-76.)*zoom
	artwork.position=Vector2(0.,-76.)*zoom
	artwork.scale=Vector2.ONE*zoom
	_queue_frame()

func _queue_frame() -> void:
	queue_redraw()
	artwork.queue_redraw()

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
	var progress:=player.clock/float(player.scene.duration)
	if not data_status.is_empty():
		draw_rect(Rect2(17,480,926,24),Color("0b2030"))
		draw_string(font,Vector2(22,498),data_status,HORIZONTAL_ALIGNMENT_LEFT,916.,16,ACCENT)
	var cue_label:=player.cue_label()
	if not cue_label.is_empty():
		var y:=495. if data_status.is_empty() else 474.
		draw_string(font,Vector2(22.,y),cue_label,HORIZONTAL_ALIGNMENT_LEFT,916.,17,Color("ffc671"))
	draw_rect(Rect2(18,505,924,3),Color("254b5a"))
	draw_rect(Rect2(18,505,924*progress,3),ACCENT)
	for cue in player.scene.get("cues",[]):
		var marker_x:=18.+924.*float(cue.at)/float(player.scene.duration)
		draw_line(Vector2(marker_x,502.),Vector2(marker_x,512.),Color("ffc671"),2.,true)

func _draw_artwork() -> void:
	if player.scene.is_empty() or font==null:return
	var camera:=player.camera_transform()
	for item in player.ordered:
		if item.type in ["group","camera"] or not player.visible_at_time(item):continue
		var pose:=_pose(item)
		if float(pose.alpha)<=0.:continue
		artwork.draw_set_transform_matrix(camera*pose.transform)
		_draw_object(item,float(pose.alpha))

func _pose(item: Dictionary) -> Dictionary:
	var position:=Vector2(player.property(item,"x"),player.property(item,"y"))
	var scale_value:=clampf(player.property(item,"scale"),.02,8.)
	var alpha:=clampf(player.property(item,"alpha"),0.,1.)
	var transform:=Transform2D(deg_to_rad(player.property(item,"rotation")),Vector2.ONE*scale_value,0.,position)
	var parent: String=item.get("parent","")
	while not parent.is_empty():
		var group: Dictionary=player.objects[parent]
		if not player.visible_at_time(group):return {"transform":transform,"alpha":0.}
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
		artwork.draw_rect(Rect2(Vector2(-8,-14),Vector2(maxf(dims.x,radius*2.),maxf(dims.y,radius*2.))).grow(10.),Color("ffc67177"),false,3.)
	match str(item.type):
		"rectangle":
			var box:=Rect2(Vector2.ZERO,dims)
			if fill.a>0.:artwork.draw_rect(box,fill)
			artwork.draw_rect(box,pen,false,stroke)
		"circle":
			if fill.a>0.:artwork.draw_circle(Vector2.ZERO,radius,fill,true,-1.,true)
			artwork.draw_arc(Vector2.ZERO,radius,0.,TAU*progress,48,pen,stroke,true)
		"ellipse":
			var outline:=PackedVector2Array()
			for i in 49:
				var angle:=TAU*float(i)/48.*progress
				outline.append(Vector2(cos(angle),sin(angle))*dims*.5)
			if fill.a>0. and progress>=1.:artwork.draw_colored_polygon(outline.slice(0,-1),fill)
			artwork.draw_polyline(outline,pen,stroke,true)
		"line","arrow":
			var endpoint:=Vector2(player.property(item,"width"),player.property(item,"height"))
			_line(Vector2.ZERO,endpoint*progress,pen,stroke,item.get("dash",false),item.type=="arrow")
		"path","polygon":
			var points:=PackedVector2Array()
			for p in item.points:points.append(Vector2(p[0],p[1]))
			if item.type=="polygon":
				if fill.a>0.:artwork.draw_colored_polygon(points,fill)
				points.append(points[0])
			_trace(points,pen,stroke,progress,item.get("dash",false))
		"text","equation":
			var ast: Dictionary=player.compiled.notation.get(item.id,{})
			var font_size:=clampi(roundi(player.property(item,"font")),13,90)
			if ast.is_empty():
				var label:=_caption(str(item.get("text","")))
				artwork.draw_string(font,Vector2.ZERO,label.substr(0,ceili(label.length()*progress)),HORIZONTAL_ALIGNMENT_LEFT,dims.x,font_size,pen)
			else:_draw_notation(item.id,ast,font_size,dims.x,progress,pen)
		"graph":_graph(item,dims,pen,stroke,progress)
		"particles":
			var count:=int(item.get("count",12))
			var phase:=player.clock*.4
			for i in count:
				var p:=Vector2(fposmod(float(i)/count+phase,1.)*dims.x,fposmod(i*.618,1.)*dims.y)
				artwork.draw_circle(p,minf(20.,radius),pen,true,-1.,true)

func _draw_notation(id: String,ast: Dictionary,font_size: int,width: float,progress: float,ink: Color) -> void:
	const LAYOUT_FONT:=30
	if not notation_cache.has(id):
		var layout:=ExpressionView.new()
		layout.set_expression(ast,LAYOUT_FONT)
		notation_cache[id]={"operations":layout.operations,"width":layout.custom_minimum_size.x-24.}
		layout.free()
	var entry: Dictionary=notation_cache[id]
	var ratio:=minf(float(font_size)/LAYOUT_FONT,width/maxf(1.,float(entry.width)))
	var anchor:=Vector2(12.,12.+LAYOUT_FONT)
	var operations: Array=entry.operations
	for i in ceili(float(operations.size())*progress):
		var operation: Array=operations[i]
		if operation[0]=="text":
			artwork.draw_string(font,(operation[2]-anchor)*ratio,operation[1],HORIZONTAL_ALIGNMENT_LEFT,-1.,maxi(1,roundi(float(operation[3])*ratio)),ink)
		else:artwork.draw_line((operation[1]-anchor)*ratio,(operation[2]-anchor)*ratio,ink,maxf(1.,ratio*1.5),true)

func _caption(text: String) -> String:
	for id in player.compiled.names:
		var slot: int=player.compiled.names.find(id)
		if text.contains("{"+id+"}"):text=text.replace("{"+id+"}","%.2f"%float(player.inputs[slot]))
	return text

func _line(from: Vector2,to: Vector2,ink: Color,width: float,dash: bool,arrow: bool) -> void:
	if from.is_equal_approx(to):return
	if dash:artwork.draw_dashed_line(from,to,ink,width,12.)
	else:artwork.draw_line(from,to,ink,width,true)
	if arrow:
		var heading:=(to-from).normalized()
		artwork.draw_colored_polygon(PackedVector2Array([to,to-heading.rotated(.44)*18,to-heading.rotated(-.44)*18]),ink)

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
	var bounds:=Rect2(x0,y0,x1-x0,y1-y0)
	if item.get("equal_axes",item.has("x_function")):
		var units_per_pixel:=maxf(bounds.size.x/dims.x,bounds.size.y/dims.y)
		var equal_size:=dims*units_per_pixel
		bounds=Rect2(bounds.get_center()-equal_size*.5,equal_size)
	artwork.draw_rect(Rect2(Vector2.ZERO,dims),Color("102f40"))
	for i in range(1,8):
		var gx:=dims.x*i/8.
		artwork.draw_line(Vector2(gx,0.),Vector2(gx,dims.y),Color("254c5b"))
	for j in range(1,5):
		var gy:=dims.y*j/5.
		artwork.draw_line(Vector2(0.,gy),Vector2(dims.x,gy),Color("254c5b"))
	var axes:=Vector2(clampf(-bounds.position.x/bounds.size.x,0.,1.),clampf(bounds.end.y/bounds.size.y,0.,1.))*dims
	artwork.draw_line(Vector2(0.,axes.y),Vector2(dims.x,axes.y),Color("87a5b1"),2.,true)
	artwork.draw_line(Vector2(axes.x,0.),Vector2(axes.x,dims.y),Color("87a5b1"),2.,true)
	var points:=PackedVector2Array()
	if item.has("data_series"):
		points=player.live_series.get(item.data_series,PackedVector2Array())
		if points.is_empty():
			artwork.draw_string(font,Vector2(12.,30.),"Waiting for live data",HORIZONTAL_ALIGNMENT_LEFT,dims.x-24.,20,INK)
	else:
		points=_graph_points(item,x0,x1)
	_draw_plot(points,bounds,dims,pen,stroke,progress,item.get("plot_style","line")=="scatter")
	_draw_graph_limits(item,bounds,dims)

func _graph_points(item: Dictionary,x0: float,x1: float) -> PackedVector2Array:
	var minimum:=player.property(item,"u_min") if item.has("x_function") else x0
	var maximum:=player.property(item,"u_max") if item.has("x_function") else x1
	var dynamic: bool=player.compiled.animated_plots.get(item.id,false)
	var key: Array=[player.revision,minimum,maximum,player.clock if dynamic else 0.]
	var cached: Dictionary=plot_cache.get(item.id,{})
	if cached.get("key")==key:return cached.values
	var points:=PackedVector2Array()
	var fixed: Array=item.get("points",[])
	if not fixed.is_empty():
		for point in fixed:points.append(Vector2(point[0],point[1]))
	elif maximum>minimum:
		for i in 97:points.append(player.sample_point(item.id,lerpf(minimum,maximum,float(i)/96.)))
	plot_cache[item.id]={"key":key,"values":points}
	return points

func _draw_plot(points: PackedVector2Array,bounds: Rect2,dims: Vector2,pen: Color,stroke: float,progress: float,scatter: bool) -> void:
	var limit:=bounds.grow(.00001)
	var previous:=Vector2.INF
	var origin:=Vector2(bounds.position.x,bounds.end.y)
	var gain:=Vector2(dims.x/bounds.size.x,-dims.y/bounds.size.y)
	for i in mini(points.size(),ceili(progress*maxi(0,points.size()-1))+1):
		var point:=points[i]
		if not point.is_finite() or not limit.has_point(point):
			previous=Vector2.INF
			continue
		var pixel:=(point-origin)*gain
		if scatter:artwork.draw_circle(pixel,maxf(2.5,stroke),pen,true,-1.,true)
		elif previous.is_finite():artwork.draw_line(previous,pixel,pen,stroke,true)
		previous=pixel

func _draw_graph_limits(item: Dictionary,bounds: Rect2,dims: Vector2) -> void:
	artwork.draw_string(font,Vector2(4,dims.y-8),"%.2f"%bounds.position.x,HORIZONTAL_ALIGNMENT_LEFT,90.,16,INK)
	artwork.draw_string(font,Vector2(dims.x-72,dims.y-8),"%.2f"%bounds.end.x,HORIZONTAL_ALIGNMENT_RIGHT,68.,16,INK)
	if item.has("x_label") and dims.x>=240.:
		artwork.draw_string(font,Vector2(78.,dims.y-8),item.x_label,HORIZONTAL_ALIGNMENT_CENTER,dims.x-156.,16,INK)
	if item.has("y_label"):
		artwork.draw_string(font,Vector2(9.,21.),item.y_label,HORIZONTAL_ALIGNMENT_LEFT,dims.x-18.,16,INK)
