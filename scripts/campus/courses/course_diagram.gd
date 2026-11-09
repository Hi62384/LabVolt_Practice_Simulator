extends Control
## Readable, original node-labelled circuit strip. Each component has an explicit
## a->b direction; equal node names denote ideal connectivity. This avoids
## guessing breadboard positions from source images and scales in a ScrollContainer.
var descriptor: Dictionary={}
var ink := Color("dceaf4")
func configure(value: Dictionary) -> void:
	descriptor=value.duplicate(true)
	custom_minimum_size=Vector2(900,90+maxi(1,descriptor.get("parts",[]).size())*76)
	queue_redraw()
func _ready() -> void:
	mouse_filter=Control.MOUSE_FILTER_IGNORE
	configure(descriptor)
func label_at(point: Vector2,value: String,font_size: int=20) -> void:
	draw_string(ThemeDB.fallback_font,point,value,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size,ink)
static func display_value(part: Dictionary) -> String:
	if part.value is String:return str(part.value)+" "+str(part.get("unit",""))
	var unit := str(part.get("unit","Ω" if part.kind=="R" else "V" if part.kind=="V" else "A"))
	var value := float(part.value)
	if unit=="F":value*=1e6;unit="µF"
	elif unit=="A" and absf(value)<1:value*=1000;unit="mA"
	elif unit=="Ω" and absf(value)>=1000:value/=1000;unit="kΩ"
	return String.num(value,6)+" "+unit
func _draw() -> void:
	draw_style_box(_panel(),Rect2(Vector2.ZERO,size))
	label_at(Vector2(24,32),"CIRCUIT • Matching node labels are electrically connected",22)
	label_at(Vector2(24,59),"Reference terminal directions: voltage V(a)-V(b); current a → b",18)
	var y := 106.0
	for p in descriptor.get("parts",[]):
		label_at(Vector2(24,y+7),str(p.id),20)
		label_at(Vector2(150,y+7),str(p.a),20)
		draw_circle(Vector2(245,y),5,Color("47d4c3"))
		draw_line(Vector2(245,y),Vector2(350,y),ink,2,true)
		draw_line(Vector2(450,y),Vector2(555,y),ink,2,true)
		if p.kind=="R":
			draw_rect(Rect2(350,y-14,100,28),ink,false,2)
		elif p.kind=="L":
			for i in range(5):draw_arc(Vector2(360+i*20,y),10,PI,TAU,16,ink,2,true)
		elif p.kind=="C":
			draw_line(Vector2(350,y),Vector2(395,y),ink,2,true);draw_line(Vector2(405,y),Vector2(450,y),ink,2,true)
			draw_line(Vector2(395,y-18),Vector2(395,y+18),ink,2,true);draw_line(Vector2(405,y-18),Vector2(405,y+18),ink,2,true)
		else:
			draw_arc(Vector2(400,y),25,0,TAU,48,ink,2,true)
			if p.kind=="I":
				draw_line(Vector2(385,y),Vector2(415,y),ink,2,true)
				draw_line(Vector2(415,y),Vector2(408,y-6),ink,2,true)
				draw_line(Vector2(415,y),Vector2(408,y+6),ink,2,true)
			else:label_at(Vector2(391,y+7),str(p.kind),20)
			label_at(Vector2(345,y-25),"+" if p.kind=="V" else "a",18)
			label_at(Vector2(445,y-25),"-" if p.kind=="V" else "b",18)
		draw_circle(Vector2(555,y),5,Color("47d4c3"))
		label_at(Vector2(585,y+7),str(p.b),20)
		label_at(Vector2(675,y+7),display_value(p),20)
		y+=76
func _panel() -> StyleBoxFlat:
	var panel := StyleBoxFlat.new();panel.bg_color=Color("122432")
	panel.corner_radius_top_left=12;panel.corner_radius_top_right=12
	panel.corner_radius_bottom_left=12;panel.corner_radius_bottom_right=12
	return panel
