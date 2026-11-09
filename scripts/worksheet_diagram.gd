extends Control
var topic := 0
var course_id := "ELM253"
var descriptor := {}
var ink := Color("263c4a")
func _ready() -> void:
	custom_minimum_size=Vector2(620,215);mouse_filter=Control.MOUSE_FILTER_IGNORE
	if descriptor.get("kind","")=="netlist":custom_minimum_size.y=60+58*descriptor.get("parts",[]).size()
	if descriptor.get("kind","")=="legacy_ac":topic=int(descriptor.get("topic",topic))
func wire(points: Array) -> void:
	for i in range(points.size()-1):draw_line(points[i],points[i+1],ink,2,true)
func text(at: Vector2,value: String,size_value := 16) -> void:
	draw_string(ThemeDB.fallback_font,at,value,HORIZONTAL_ALIGNMENT_LEFT,-1,size_value,ink)
func symbol(at: Vector2,kind: String) -> void:
	if kind=="R":
		var points: Array=[at+Vector2(-40,0)]
		for i in 9:points.append(at+Vector2(-24+i*6,(-8 if i%2==0 else 8)))
		points.append(at+Vector2(40,0));wire(points)
	elif kind=="C":
		wire([at+Vector2(-40,0),at+Vector2(-6,0)]);wire([at+Vector2(6,0),at+Vector2(40,0)])
		for x in [-6,6]:wire([at+Vector2(x,-18),at+Vector2(x,18)])
	elif kind=="L":
		wire([at+Vector2(-40,0),at+Vector2(-25,0)]);wire([at+Vector2(25,0),at+Vector2(40,0)])
		for i in 5:draw_arc(at+Vector2(-20+i*10,0),5,PI,TAU,12,ink,2,true)
	else:
		draw_arc(at,19,0,TAU,40,ink,2,true);text(at+Vector2(-7,6),kind,18)
func _draw() -> void:
	draw_style_box(_box(),Rect2(Vector2.ZERO,size))
	if descriptor.get("kind","")=="netlist":
		_draw_netlist()
		return
	if course_id=="ETY155":
		text(Vector2(24,40),"Use the explicitly labelled nodes in the given circuit.",18)
		return
	var left := 65.;var right := 560.
	match topic:
		1:
			wire([Vector2(50,110),Vector2(330,110)]);wire([Vector2(60,185),Vector2(60,30)])
			var points: Array=[]
			for i in 241:points.append(Vector2(65+i,110-55*sin(i/240.*TAU)))
			wire(points);text(Vector2(80,32),"v(t) = Vpk sin(ωt)");text(Vector2(300,135),"t")
			wire([Vector2(390,165),Vector2(565,165)]);wire([Vector2(410,185),Vector2(410,35)]);wire([Vector2(410,165),Vector2(525,75)])
			text(Vector2(515,65),"V∠φ");text(Vector2(555,188),"Re");text(Vector2(380,35),"Im")
		5,6:
			for i in 3:
				var y: float=35+i*50;text(Vector2(30,y+6),["A","B","C"][i]);wire([Vector2(left,y),Vector2(260,y)]);symbol(Vector2(300,y),"R");wire([Vector2(340,y),Vector2(425,y),Vector2(425,85)])
			text(Vector2(430,91),"N / star point");text(Vector2(170,202),"Balanced wye: VL = √3 Vphase; IL = Iphase",14)
			if topic==6:
				for i in 3:
					var y: float=35+i*50
					wire([Vector2(260,y),Vector2(260,y+25)]);symbol(Vector2(300,y+25),"C");wire([Vector2(340,y+25),Vector2(340,y)])
		8:
			text(Vector2(78,40),"Primary 1–2");text(Vector2(350,40),"Secondary taps")
			wire([Vector2(80,75),Vector2(160,75)]);symbol(Vector2(200,75),"L");wire([Vector2(240,75),Vector2(280,75)])
			for y in [100,108]:wire([Vector2(160,y),Vector2(465,y)])
			symbol(Vector2(205,145),"L");symbol(Vector2(325,145),"L");symbol(Vector2(445,145),"L")
			wire([Vector2(245,145),Vector2(285,145)]);wire([Vector2(365,145),Vector2(405,145)])
			for pair in [[165,"3"],[265,"7"],[385,"8"],[485,"4"]]:draw_circle(Vector2(pair[0],145),4,ink);text(Vector2(pair[0]-4,178),pair[1])
			text(Vector2(160,202),"Vp / Vs = Np / Ns   •   Frequency is unchanged",14)
		7:
			draw_arc(Vector2(235,105),62,0,TAU,60,ink,2,true);draw_arc(Vector2(235,105),35,0,TAU,40,ink,2,true)
			for i in 3:wire([Vector2(70,65+i*40),Vector2(175,65+i*40)]);text(Vector2(40,71+i*40),["A","B","C"][i])
			wire([Vector2(270,105),Vector2(400,105)]);draw_rect(Rect2(400,65,140,80),ink,false,2);text(Vector2(420,112),"Brake / load")
			text(Vector2(168,202),"ns = 120f / poles     s = (ns − nr) / ns",16)
		9:
			wire([Vector2(90,40),Vector2(510,40)]);wire([Vector2(90,175),Vector2(510,175)])
			for x in [200,410]:
				for y in [70,145]:draw_rect(Rect2(x-10,y-15,20,30),ink,false,2)
				wire([Vector2(x,40),Vector2(x,55)]);wire([Vector2(x,85),Vector2(x,130)]);wire([Vector2(x,160),Vector2(x,175)])
			symbol(Vector2(305,107),"R");wire([Vector2(200,107),Vector2(265,107)]);wire([Vector2(345,107),Vector2(410,107)])
			text(Vector2(40,45),"DC+");text(Vector2(40,180),"DC−");text(Vector2(165,207),"Full bridge • alternate diagonal switch pairs",14)
		10:
			for i in 8:draw_arc(Vector2(210+i*22,100),24,-PI*.6,PI*.6,24,ink,2,true)
			wire([Vector2(105,120),Vector2(200,120)]);wire([Vector2(375,120),Vector2(510,120)])
			text(Vector2(215,42),"N turns • flux Φ");text(Vector2(195,195),"|e| = N |ΔΦ / Δt|     B = Φ / A")
		4:
			wire([Vector2(65,55),Vector2(110,55)]);symbol(Vector2(150,55),"R");text(Vector2(137,30),"R2")
			wire([Vector2(190,55),Vector2(220,55)]);symbol(Vector2(260,55),"L");wire([Vector2(300,55),Vector2(540,55)])
			for pair in [[400,"R"],[540,"C"]]:
				wire([Vector2(pair[0],55),Vector2(pair[0],75)]);draw_set_transform(Vector2(pair[0],115),PI/2);symbol(Vector2.ZERO,pair[1]);draw_set_transform(Vector2.ZERO);wire([Vector2(pair[0],155),Vector2(pair[0],175)])
			wire([Vector2(540,175),Vector2(65,175),Vector2(65,129)]);symbol(Vector2(65,110),"~");wire([Vector2(65,91),Vector2(65,55)])
			text(Vector2(145,204),"Ztotal = R2 + jXL + (R1 ∥ −jXC)",16)
		3:
			wire([Vector2(left,45),Vector2(right,45)]);wire([Vector2(left,170),Vector2(right,170)])
			for i in 3:
				var x: float=190+i*150
				wire([Vector2(x,45),Vector2(x,75)])
				draw_set_transform(Vector2(x,110),PI/2);symbol(Vector2.ZERO,["R","L","C"][i]);draw_set_transform(Vector2.ZERO)
				wire([Vector2(x,150),Vector2(x,170)]);text(Vector2(x+22,110),["R","L","C (if used)"][i],14)
			symbol(Vector2(left,107),"~");wire([Vector2(left,45),Vector2(left,88)]);wire([Vector2(left,126),Vector2(left,170)])
			text(Vector2(160,202),"Parallel branches share voltage • currents add as phasors",14)
		_:
			wire([Vector2(left,68),Vector2(150,68)]);symbol(Vector2(170,68),"A");wire([Vector2(190,68),Vector2(235,68)]);symbol(Vector2(275,68),"R");wire([Vector2(315,68),Vector2(360,68)])
			if topic==2:symbol(Vector2(400,68),"L");wire([Vector2(440,68),Vector2(right,68)])
			else:wire([Vector2(360,68),Vector2(right,68)])
			wire([Vector2(right,68),Vector2(right,175),Vector2(left,175),Vector2(left,126)])
			symbol(Vector2(left,107),"~");wire([Vector2(left,68),Vector2(left,88)])
			wire([Vector2(235,68),Vector2(235,130),Vector2(255,130)]);symbol(Vector2(275,130),"V");wire([Vector2(295,130),Vector2(315,130),Vector2(315,68)])
			text(Vector2(160,202),"Ammeter in series • voltmeter across the component",14)
func _box() -> StyleBoxFlat:
	var box := StyleBoxFlat.new();box.bg_color=Color("f4f3ed");box.border_color=Color("d2d6cf");box.set_border_width_all(1);return box

func _draw_netlist() -> void:
	text(Vector2(18,25),"Node-labelled circuit · repeated labels connect electrically",17)
	var parts: Array=descriptor.get("parts",[])
	for i in parts.size():
		var part: Dictionary=parts[i]
		var y := 62.0+58.0*i
		wire([Vector2(105,y),Vector2(265,y)])
		wire([Vector2(345,y),Vector2(510,y)])
		var kind := str(part.get("kind","R"))
		if kind in ["V","supply"]:
			symbol(Vector2(305,y),"V")
			wire([Vector2(265,y),Vector2(286,y)]);wire([Vector2(324,y),Vector2(345,y)])
			text(Vector2(274,y-8),"+",14);text(Vector2(331,y-8),"−",14)
		elif kind=="I":
			symbol(Vector2(305,y),"→")
			wire([Vector2(265,y),Vector2(286,y)]);wire([Vector2(324,y),Vector2(345,y)])
		else:symbol(Vector2(305,y),kind)
		for endpoint in [[105,str(part.get("a",""))],[510,str(part.get("b",""))]]:
			draw_circle(Vector2(endpoint[0],y),3,ink)
			text(Vector2(endpoint[0]-15,y-12),endpoint[1],17)
		text(Vector2(235,y+25),str(part.get("id",""))+" · "+preload("res://scripts/campus/courses/course_diagram.gd").display_value(part),18)
