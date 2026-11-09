extends Control
## Semantic ideal-impedance schematic for MTH255 mathematical demonstrations.
## All values and topology come from the generated problem descriptor.
var descriptor: Dictionary={}
func configure(data: Dictionary) -> void:
	descriptor=data.duplicate(true);custom_minimum_size=Vector2(680,330);queue_redraw()
func _wire(a: Vector2,b: Vector2) -> void:
	draw_line(a,b,Color("b8dce5"),2,true)
func _text(at: Vector2,value: String,size: int=16) -> void:
	draw_string(ThemeDB.fallback_font,at,value,HORIZONTAL_ALIGNMENT_LEFT,-1,size,Color("edf5ff"))
func _impedance(center: Vector2,data: Dictionary) -> void:
	var box=Rect2(center-Vector2(42,18),Vector2(84,36));draw_rect(box,Color("244958"));draw_rect(box,Color("80d3dd"),false,2)
	_text(center+Vector2(-20,5),str(data.get("id","Z")))
	_text(center+Vector2(-78,44),"%s + j(%s) ohm"%[data.get("real",0),data.get("imag",0)],14)
func _draw() -> void:
	if descriptor.get("kind","")!="circuit" or descriptor.get("components",[]).size() not in [2,3]:return
	if descriptor.get("topology","")=="series_parallel":
		_series_parallel();return
	var width=maxf(size.x,620);var left=70.0;var right=width-75;var top=70.0;var bottom=215.0;var source=Vector2(left,145)
	draw_circle(source,24,Color("1a3446"));draw_arc(source,24,0,TAU,48,Color("80d3dd"),2,true)
	_text(source+Vector2(-6,7),"~",22);_text(Vector2(18,245),"RMS source: %s V ∠0°"%descriptor.get("source",{}).get("rms_volts",0),14)
	_wire(Vector2(left,121),Vector2(left,top));_wire(Vector2(left,169),Vector2(left,bottom))
	var components=descriptor.components
	if descriptor.get("topology")=="parallel":
		var c1=Vector2(width*0.47,top);var c2=Vector2(width*0.47,145)
		_wire(Vector2(left,top),c1-Vector2(42,0));_wire(c1+Vector2(42,0),Vector2(right,top));_wire(Vector2(right,top),Vector2(right,bottom));_wire(Vector2(left,bottom),Vector2(right,bottom))
		var branch=left+100;_wire(Vector2(branch,top),Vector2(branch,145));_wire(Vector2(branch,145),c2-Vector2(42,0));_wire(c2+Vector2(42,0),Vector2(right,145))
		_impedance(c1,components[0]);_impedance(c2,components[1])
	else:
		var c1=Vector2(width*0.38,top);var c2=Vector2(width*0.73,top)
		_wire(Vector2(left,top),c1-Vector2(42,0));_wire(c1+Vector2(42,0),c2-Vector2(42,0));_wire(c2+Vector2(42,0),Vector2(right,top));_wire(Vector2(right,top),Vector2(right,bottom));_wire(Vector2(right,bottom),Vector2(left,bottom))
		_impedance(c1,components[0]);_impedance(c2,components[1])
	_text(Vector2(18,28),"Ideal sinusoidal steady-state impedance network",18)

func _series_parallel() -> void:
	var width=maxf(size.x,680);var left=65.0;var right=width-45;var branch=width*0.52;var z1=Vector2(width*0.30,65);var z2=Vector2(width*0.74,115);var z3=Vector2(width*0.74,220);var source=Vector2(left,165)
	_text(Vector2(18,28),"Ideal RMS phasor network: Z1 in series with Z2 || Z3",18)
	draw_circle(source,24,Color("1a3446"));draw_arc(source,24,0,TAU,48,Color("80d3dd"),2,true);_text(source+Vector2(-6,7),"~",22)
	_wire(Vector2(left,141),Vector2(left,65));_wire(Vector2(left,65),z1-Vector2(42,0));_wire(z1+Vector2(42,0),Vector2(branch,65));_wire(Vector2(branch,65),Vector2(branch,220))
	for center in [z2,z3]:
		_wire(Vector2(branch,center.y),center-Vector2(42,0));_wire(center+Vector2(42,0),Vector2(right,center.y))
	_wire(Vector2(right,115),Vector2(right,280));_wire(Vector2(right,280),Vector2(left,280));_wire(Vector2(left,280),Vector2(left,189))
	_impedance(z1,descriptor.components[0]);_impedance(z2,descriptor.components[1]);_impedance(z3,descriptor.components[2])
	_text(Vector2(18,315),"Source %s V ∠0°, RMS. Each Z is an ideal impedance at the common frequency."%descriptor.source.rms_volts,14)
