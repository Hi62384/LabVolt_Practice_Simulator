extends Control
const Model=preload("res://scripts/campus/facilities/circuit_studio/assembly_model.gd")
var design: Dictionary={}
var library: Dictionary={}
var pcbs: Dictionary={}

func _draw() -> void:
	var area:=Rect2(Vector2.ZERO,size)
	draw_rect(area,Color("152b38"),true)
	var scale:=minf((size.x-24.0)/13.0,(size.y-32.0)/13.0)
	var center:=size*.5
	for index in range(-6,7):
		var coordinate:=float(index)*scale
		draw_line(center+Vector2(coordinate,-6*scale),center+Vector2(coordinate,6*scale),Color("315263"),1)
		draw_line(center+Vector2(-6*scale,coordinate),center+Vector2(6*scale,coordinate),Color("315263"),1)
	var parts: Array=[]
	if library.has("inv:preview") and Model.validate("inv:preview",library,pcbs)=="":parts=Model.flattened("inv:preview",library,pcbs)
	else:parts=design.get("parts",[])
	parts.sort_custom(func(a: Dictionary,b: Dictionary):return int(a.get("y",0))<int(b.get("y",0)))
	for part in parts:
		var kind:=str(part.get("type",""))
		var point:=center+Vector2(float(part.get("x",0)),-float(part.get("z",0)))*scale
		var color:=Color(str(Model.PARTS.get(kind,{}).get("color","aaaaaa")))
		draw_rect(Rect2(point-Vector2.ONE*scale*.42,Vector2.ONE*scale*.84),color,true)
		draw_rect(Rect2(point-Vector2.ONE*scale*.42,Vector2.ONE*scale*.84),Color("e4ebe8"),false,1)
		draw_string(ThemeDB.fallback_font,point+Vector2(-scale*.32,scale*.18),kind.left(2).to_upper(),HORIZONTAL_ALIGNMENT_LEFT,-1,maxi(9,int(scale*.42)),Color("14202a"))
