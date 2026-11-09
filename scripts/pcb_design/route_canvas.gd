extends Control
signal edited
signal vertex_selected(index: int)
signal outline_feedback(message: String)
const Design=preload("res://scripts/pcb_design/design.gd")
var document: RefCounted
var start_pad := ""
var bends: Array=[]
var zoom := 1.0
var pan := Vector2.ZERO
var panning := false
var outline_mode := false
var selected_vertex := 0
var snap_step := .25
var drag_index := -1
var drag_outline: Array=[]
var preview_error := ""
func _ready() -> void:
	custom_minimum_size=Vector2(900,420)
	focus_mode=Control.FOCUS_ALL
	mouse_default_cursor_shape=Control.CURSOR_CROSS
func rect() -> Rect2: return Rect2(Vector2(24,24)+pan,(size-Vector2(48,48))*zoom)
func grid_point(pixel: Vector2) -> Array:
	var bp: Dictionary=document.blueprint
	var value: Vector2=(pixel-rect().position)/rect().size*Vector2(float(bp.footprint.width)-1,float(bp.footprint.height)-1)
	return [snappedf(value.x,snap_step if outline_mode else .05),snappedf(value.y,snap_step if outline_mode else .05)]
func nearest(pixel: Vector2) -> String:
	var best := "";var distance := 12.0
	for id in document.blueprint.pcb_design.pads:
		var point: Vector2=Design.map_point(document.blueprint,document.blueprint.pcb_design.pads[id].position,rect())
		if point.distance_to(pixel)<distance:distance=point.distance_to(pixel);best=id
	return best
func set_outline_mode(enabled: bool) -> void:
	outline_mode=enabled;start_pad="";bends=[];cancel_outline_drag();queue_redraw()
func cancel_outline_drag() -> void:
	drag_index=-1;drag_outline=[];preview_error="";queue_redraw()
func nearest_vertex(pixel: Vector2) -> int:
	var best:=-1;var distance:=13.0
	for index in document.blueprint.pcb_design.outline.size():
		var position: Vector2=Design.map_point(document.blueprint,document.blueprint.pcb_design.outline[index],rect())
		if position.distance_to(pixel)<distance:best=index;distance=position.distance_to(pixel)
	return best
func select_vertex(index: int) -> void:
	selected_vertex=clampi(index,0,document.blueprint.pcb_design.outline.size()-1)
	vertex_selected.emit(selected_vertex);queue_redraw()
func move_selected(position: Array) -> bool:
	var points: Array=document.blueprint.pcb_design.outline.duplicate(true)
	points[selected_vertex]=position.duplicate()
	var ok: bool=document.set_outline(points)
	outline_feedback.emit("Point moved" if ok else "Move rejected: "+document.error)
	edited.emit();return ok
func add_vertex_after() -> bool:
	var points: Array=document.blueprint.pcb_design.outline.duplicate(true)
	if points.size()>=64:
		outline_feedback.emit("The board edge supports up to 64 points.");return false
	var a:=Design.v(points[selected_vertex]);var b:=Design.v(points[(selected_vertex+1)%points.size()])
	# Keep a new point exactly on its edge; snapping happens when it moves.
	var middle:=(a+b)*.5
	points.insert(selected_vertex+1,[middle.x,middle.y])
	var ok: bool=document.set_outline(points)
	if ok:select_vertex(selected_vertex+1)
	outline_feedback.emit("Point added. Drag its handle to shape the edge." if ok else "Point rejected: "+document.error)
	edited.emit();return ok
func remove_selected_vertex() -> bool:
	var points: Array=document.blueprint.pcb_design.outline.duplicate(true)
	if points.size()<=3:
		outline_feedback.emit("Keep at least three edge points.");return false
	points.remove_at(selected_vertex)
	var ok: bool=document.set_outline(points)
	if ok:select_vertex(mini(selected_vertex,points.size()-1))
	outline_feedback.emit("Point removed" if ok else "Removal rejected: "+document.error)
	edited.emit();return ok
func add_vertex_at(pixel: Vector2) -> bool:
	var points: Array=document.blueprint.pcb_design.outline.duplicate(true)
	if points.size()>=64:outline_feedback.emit("The board edge supports up to 64 points.");return false
	var best:=-1;var distance:=14.0;var projected:=Vector2.ZERO
	for index in points.size():
		var a: Vector2=Design.map_point(document.blueprint,points[index],rect())
		var b: Vector2=Design.map_point(document.blueprint,points[(index+1)%points.size()],rect())
		var candidate:=Geometry2D.get_closest_point_to_segment(pixel,a,b)
		if candidate.distance_to(pixel)<distance:best=index;distance=candidate.distance_to(pixel);projected=candidate
	if best<0:outline_feedback.emit("Double-click close to an edge to add a point.");return false
	var grid: Vector2=(projected-rect().position)/rect().size*Vector2(float(document.blueprint.footprint.width)-1,float(document.blueprint.footprint.height)-1)
	points.insert(best+1,[grid.x,grid.y])
	var ok: bool=document.set_outline(points)
	if ok:select_vertex(best+1)
	outline_feedback.emit("Point added" if ok else "Point rejected: "+document.error)
	edited.emit();return ok
func _notification(what: int) -> void:
	if what==NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		panning=false
		if drag_index>=0:cancel_outline_drag();outline_feedback.emit("Move cancelled")
func _outline_input(event: InputEvent) -> bool:
	if event is InputEventKey and event.pressed and event.keycode==KEY_ESCAPE:
		cancel_outline_drag();outline_feedback.emit("Move cancelled");accept_event();return true
	if event is InputEventMouseMotion:
		if drag_index>=0:
			drag_outline[drag_index]=grid_point(event.position)
			var candidate: Dictionary=document.blueprint.duplicate();candidate.pcb_design=document.blueprint.pcb_design.duplicate();candidate.pcb_design.outline=drag_outline
			preview_error=Design.validate(candidate,true)
			outline_feedback.emit("Release to place point" if preview_error=="" else "Cannot place here: "+preview_error)
			queue_redraw();accept_event();return true
		tooltip_text="Drag an edge point. Double-click an edge to add a point."
		return false
	if not event is InputEventMouseButton:return false
	if event.button_index==MOUSE_BUTTON_RIGHT and event.pressed:
		cancel_outline_drag();outline_feedback.emit("Move cancelled");accept_event();return true
	if event.button_index!=MOUSE_BUTTON_LEFT:return false
	if not event.pressed:
		if drag_index>=0:
			var changed: bool=drag_outline!=document.blueprint.pcb_design.outline
			var ok: bool=not changed or document.set_outline(drag_outline)
			outline_feedback.emit("Point moved" if ok else "Move rejected: "+document.error)
			cancel_outline_drag();vertex_selected.emit(selected_vertex);edited.emit()
		accept_event();return true
	var index:=nearest_vertex(event.position)
	if index>=0:
		select_vertex(index);drag_index=index;drag_outline=document.blueprint.pcb_design.outline.duplicate(true)
	elif event.double_click:add_vertex_at(event.position)
	else:outline_feedback.emit("Select a numbered edge point, or double-click an edge.")
	accept_event();return true
func _gui_input(event: InputEvent) -> void:
	if outline_mode and not panning and _outline_input(event):return
	if event is InputEventMouseMotion:
		if panning:pan+=event.relative;queue_redraw();accept_event()
		var hovered:=nearest(event.position)
		if not outline_mode:tooltip_text=hovered+" · intended net "+str(document.blueprint.pcb_design.pads[hovered].net) if hovered!="" else ""
		return
	if not event is InputEventMouseButton:return
	if event.button_index==MOUSE_BUTTON_MIDDLE:panning=event.pressed;accept_event();return
	if not event.pressed:return
	if event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:
		var old:=zoom
		zoom=clampf(zoom*(1.2 if event.button_index==MOUSE_BUTTON_WHEEL_UP else 1/1.2),.5,8)
		pan=event.position-Vector2(24,24)-(event.position-Vector2(24,24)-pan)*(zoom/old)
		queue_redraw();accept_event();return
	if event.button_index==MOUSE_BUTTON_RIGHT:start_pad="";bends=[];queue_redraw();return
	if event.button_index!=MOUSE_BUTTON_LEFT:return
	var id:=nearest(event.position)
	if start_pad.is_empty():
		if id!="":start_pad=id;bends=[document.blueprint.pcb_design.pads[id].position.duplicate()]
	elif id!="":
		var points:=bends.duplicate(true);points.append(document.blueprint.pcb_design.pads[id].position.duplicate())
		if document.add_route(start_pad,id,points):start_pad="";bends=[]
		edited.emit()
	elif bends.size()<15:bends.append(grid_point(event.position))
	queue_redraw();accept_event()
func _draw() -> void:
	if document==null or document.blueprint.is_empty():return
	var bp: Dictionary=document.blueprint
	var outline:=PackedVector2Array()
	var visible_outline: Array=drag_outline if drag_index>=0 else bp.pcb_design.outline
	for point in visible_outline:outline.append(Design.map_point(bp,point,rect()))
	var fill:=outline
	if preview_error!="":
		fill=PackedVector2Array()
		for point in bp.pcb_design.outline:fill.append(Design.map_point(bp,point,rect()))
	if not Geometry2D.triangulate_polygon(fill).is_empty():draw_colored_polygon(fill,Color(str(bp.footprint.get("color","24775b"))))
	var font:=ThemeDB.fallback_font
	for route in bp.pcb_design.routes:
		var points:=PackedVector2Array()
		for value in route.points:points.append(Design.map_point(bp,value,rect()))
		draw_polyline(points,Color("e0bd69"),maxf(2,float(route.width)*rect().size.x/(float(bp.footprint.width)-1)),true)
	for id in bp.pcb_design.pads:
		var point: Vector2=Design.map_point(bp,bp.pcb_design.pads[id].position,rect())
		var selected_net: String=bp.pcb_design.pads[start_pad].net if start_pad!="" else ""
		draw_circle(point,5,Color("fff3a0") if id==start_pad else Color("91e6e0") if selected_net!="" and bp.pcb_design.pads[id].net==selected_net else Color("cdb372"))
		if not outline_mode:draw_string(font,point+Vector2(6,-4),id+" ["+str(bp.pcb_design.pads[id].net)+"]",HORIZONTAL_ALIGNMENT_LEFT,160,12,Color("f1f7f1"))
	if bends.size()>1:
		var points:=PackedVector2Array()
		for value in bends:points.append(Design.map_point(bp,value,rect()))
		draw_polyline(points,Color("8fe2ef"),2,true)

	if outline_mode:
		var closed:=outline.duplicate();closed.append(outline[0])
		draw_polyline(closed,Color("f0837f") if preview_error!="" else Color("9ce8eb"),3,true)
		for index in outline.size():
			var selected: bool=index==selected_vertex
			draw_circle(outline[index],9 if selected else 7,Color("fff1ae") if selected else Color("d3edf0"))
			draw_circle(outline[index],3,Color("344956"))
			draw_string(font,outline[index]+Vector2(10,18),str(index+1),HORIZONTAL_ALIGNMENT_LEFT,40,15,Color("ffffff"))
