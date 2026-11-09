extends Control
const Model = preload("res://scripts/math_ui/plot_model.gd")
const Notation = preload("res://scripts/math_ui/math_notation.gd")
var descriptor: Dictionary = {}
var font: Font = ThemeDB.fallback_font
var error := ""
var can_manipulate:=false
var projected_vertices: Array[Vector2]=[]
var geometry_scale:=1.0
var selected_vertex:=-1
signal demonstration_changed(data: Dictionary)

func _init() -> void:
	custom_minimum_size = Vector2(540,300)
	resized.connect(queue_redraw)

func configure(data: Dictionary, interactive_demo: bool=false) -> void:
	descriptor=data.duplicate(true)
	can_manipulate=interactive_demo
	error=""
	if data.get("kind")=="triangle" and not Model.triangle_valid(data.get("vertices",[])): error="Invalid triangle coordinates"
	if data.get("kind")=="probability":
		custom_minimum_size.y=maxf(300,ceilf(mini(120,data.get("outcomes",[]).size())/5.0)*64+52)
	if data.get("kind")=="circuit" and data.get("topology")=="parallel":custom_minimum_size.y=maxf(300,data.get("components",[]).size()*65+90)
	queue_redraw()

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO,size),Color("112431"))
	if not error.is_empty():
		draw_string(font,Vector2(20,40),error,HORIZONTAL_ALIGNMENT_LEFT,-1,20,Color("ffa65a"))
		return
	if descriptor.get("kind")=="triangle": _triangle()
	elif descriptor.get("kind")=="probability": _probability()
	elif descriptor.get("kind")=="circuit": _circuit()

func _triangle() -> void:
	var verts: Array=descriptor.vertices
	var low:=Vector2(INF,INF)
	var high:=Vector2(-INF,-INF)
	for v in verts:
		low=low.min(Vector2(float(v.x),float(v.y)))
		high=high.max(Vector2(float(v.x),float(v.y)))
	var extent:=high-low
	var scale_value:=minf((size.x-140)/maxf(extent.x,0.001),(size.y-110)/maxf(extent.y,0.001))
	geometry_scale=scale_value
	var center:=(high+low)/2
	var projected: Array[Vector2]=[]
	for v in verts:
		var p:=(Vector2(float(v.x),float(v.y))-center)*scale_value
		projected.append(size/2+Vector2(p.x,-p.y))
	projected_vertices=projected
	for i in range(3):
		var p:=projected[i]
		var q:=projected[(i+1)%3]
		draw_line(p,q,Color("52d4e4"),3,true)
		draw_circle(p,4,Color.WHITE)
		var label:=str(verts[i].get("label",["A","B","C"][i]))
		var angle:Variant=descriptor.get("angles",{}).get(label,null)
		var given:Array=descriptor.get("given",[])
		if angle!=null and (given.is_empty() or label in given): label+=" = "+Notation.number(float(angle))+"°"
		draw_string(font,p+Vector2(7,-12),label,HORIZONTAL_ALIGNMENT_LEFT,-1,19,Color.WHITE)
		var key:String=["c","a","b"][i]
		var side:Variant=descriptor.get("sides",{}).get(key,null)
		var side_label:=key
		if side!=null and (given.is_empty() or key in given): side_label+=" = "+Notation.number(float(side))
		draw_string(font,(p+q)/2+Vector2(8,20),side_label,HORIZONTAL_ALIGNMENT_LEFT,-1,18,Color("ffd198"))
	# Euclidean coordinates share one uniform scale; triangle proportions remain true.
	if can_manipulate:draw_string(font,Vector2(12,size.y-12),"Drag a vertex · teaching demonstration",HORIZONTAL_ALIGNMENT_LEFT,-1,14,Color("c8d8e2"))

func _circuit() -> void:
	var components:Array=descriptor.get("components",[]).slice(0,6)
	var parallel:bool=descriptor.get("topology")=="parallel"
	var left:=Vector2(70,size.y/2)
	var right:=Vector2(size.x-55,size.y/2)
	draw_circle(left,23,Color("52d4e4"),false,2,true)
	draw_string(font,left+Vector2(-8,7),"~",HORIZONTAL_ALIGNMENT_LEFT,-1,25,Color.WHITE)
	var source:Dictionary=descriptor.get("source",{})
	draw_string(font,Vector2(12,30),"Ideal phasor model · %s V RMS ∠ %s°"%[str(source.get("rms_volts","?")),str(source.get("phase_degrees",0))],HORIZONTAL_ALIGNMENT_LEFT,-1,18,Color.WHITE)
	if not parallel:draw_line(left+Vector2(23,0),right,Color("52d4e4"),2)
	for i in range(components.size()):
		var c:Dictionary=components[i]
		var pos:=Vector2((left.x+right.x)/2-65,65+i*65) if parallel else Vector2(115+i*(size.x-145)/maxi(1,components.size()),size.y/2-22)
		var box:=Rect2(pos,Vector2(120,44))
		if parallel:
			draw_line(Vector2(105,box.get_center().y),box.position+Vector2(0,22),Color("52d4e4"),2)
			draw_line(box.position+Vector2(120,22),Vector2(right.x,box.get_center().y),Color("52d4e4"),2)
		else:
			draw_line(Vector2(pos.x-15,pos.y+22),Vector2(pos.x,pos.y+22),Color("52d4e4"),2)
		draw_rect(box,Color("2c5264"));draw_string(font,pos+Vector2(5,18),str(c.get("id","Z")),HORIZONTAL_ALIGNMENT_LEFT,-1,15,Color.WHITE)
		draw_string(font,pos+Vector2(5,36),"%s + j(%s) Ω"%[str(c.get("real",0)),str(c.get("imag",0))],HORIZONTAL_ALIGNMENT_LEFT,-1,15,Color.WHITE)
	if parallel:
		draw_line(Vector2(105,87),Vector2(105,maxf(left.y,87+maxi(0,components.size()-1)*65)),Color("52d4e4"),2)
		draw_line(Vector2(right.x,87),Vector2(right.x,maxf(left.y,87+maxi(0,components.size()-1)*65)),Color("52d4e4"),2)
	draw_line(left+Vector2(23,0),Vector2(105,left.y),Color("52d4e4"),2)
	draw_polyline(PackedVector2Array([left-Vector2(23,0),Vector2(left.x-23,size.y-25),Vector2(right.x,size.y-25),right]),Color("52d4e4"),2,true)

func _gui_input(event: InputEvent) -> void:
	if not can_manipulate or descriptor.get("kind")!="triangle":return
	if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT:
		selected_vertex=-1
		if event.pressed:
			for i in range(projected_vertices.size()):
				if event.position.distance_to(projected_vertices[i])<16:selected_vertex=i;accept_event();break
	elif event is InputEventMouseMotion and selected_vertex>=0 and event.button_mask&MOUSE_BUTTON_MASK_LEFT:
		var old:Dictionary=descriptor.vertices[selected_vertex].duplicate(true)
		descriptor.vertices[selected_vertex].x+=event.relative.x/geometry_scale
		descriptor.vertices[selected_vertex].y-=event.relative.y/geometry_scale
		if not Model.triangle_valid(descriptor.vertices):descriptor.vertices[selected_vertex]=old;return
		var v:Array[Vector2]=[]
		for vertex in descriptor.vertices:v.append(Vector2(float(vertex.x),float(vertex.y)))
		descriptor.sides={"a":v[1].distance_to(v[2]),"b":v[0].distance_to(v[2]),"c":v[0].distance_to(v[1])}
		descriptor.angles={}
		for i in range(3):descriptor.angles[["A","B","C"][i]]=rad_to_deg(acos(clampf((v[(i+1)%3]-v[i]).normalized().dot((v[(i+2)%3]-v[i]).normalized()),-1,1)))
		queue_redraw();demonstration_changed.emit(descriptor.duplicate(true));accept_event()

func _probability() -> void:
	var outcomes:Array=descriptor.get("outcomes",[]).slice(0,120)
	var columns:=maxi(1,int((size.x-32)/92))
	var mode:=str(descriptor.get("mode","outcomes"))
	draw_string(font,Vector2(16,25),mode.capitalize()+" · highlighted outcomes are favorable",HORIZONTAL_ALIGNMENT_LEFT,-1,18,Color.WHITE)
	for i in range(outcomes.size()):
		var item:Dictionary=outcomes[i] if outcomes[i] is Dictionary else {"label":str(outcomes[i])}
		var pos:=Vector2(16+(i%columns)*92,42+(i/columns)*64)
		var color:=Color("246c64") if item.get("favorable",false) else Color("304c60")
		draw_rect(Rect2(pos,Vector2(84,57)),color)
		draw_string(font,pos+Vector2(8,26),str(item.get("label","?")),HORIZONTAL_ALIGNMENT_LEFT,-1,17,Color.WHITE)
		if item.has("weight"):draw_string(font,pos+Vector2(8,46),"weight %s"%str(item.weight),HORIZONTAL_ALIGNMENT_LEFT,-1,12,Color("c8d8e2"))
	if mode=="tree":
		var nodes:Dictionary=descriptor.get("nodes",{})
		for edge in descriptor.get("branches",[]).slice(0,64):
			if nodes.has(str(edge.get("from"))) and nodes.has(str(edge.get("to"))):
				var a:Array=nodes[str(edge.from)]
				var b:Array=nodes[str(edge.to)]
				var p:=Vector2(float(a[0]),float(a[1]))*size
				var q:=Vector2(float(b[0]),float(b[1]))*size
				draw_line(p,q,Color("52d4e4"),2,true)
				draw_string(font,(p+q)/2,str(edge.get("label","")),HORIZONTAL_ALIGNMENT_LEFT,-1,17,Color.WHITE)
