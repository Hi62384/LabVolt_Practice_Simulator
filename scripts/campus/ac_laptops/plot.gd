extends Control
var readings: Dictionary = {}
var connected: Array = []
var mode := "graph"
var frequency := 60.0
const COLORS := [Color("69d8c4"),Color("ffce70"),Color("80b7ff"),Color("f598a6"),Color("b4e27c"),Color("d8a5ff"),Color("ffac70"),Color("99dce8")]

# The measured RMS phasor and DC offset define the displayed sinusoidal model.
static func sample(channel: Dictionary, cycles: float) -> float:
 var phasor: Vector2=channel.value
 var phase:=TAU*cycles
 return sqrt(2.0)*(phasor.x*cos(phase)-phasor.y*sin(phase))+float(channel.dc)

func axis_limits() -> Dictionary:
 var limits:={"V":.001,"A":.001}
 for channel in connected:
  var kind:=str(channel.kind)
  if limits.has(kind):limits[kind]=maxf(float(limits[kind]),float(channel.value.length())*sqrt(2.0)+absf(float(channel.dc)))
 return limits

func _draw() -> void:
 var box := Rect2(75, 20, maxf(80,size.x-150), maxf(80,size.y-80))
 var text_color:=Color("c3d6dc")
 var font:=ThemeDB.fallback_font
 draw_rect(box,Color("102b39"),true)
 if connected.is_empty():
  draw_string(font,box.position+Vector2(15,30),"Connect a voltage or current channel to see it here.",HORIZONTAL_ALIGNMENT_LEFT,-1,14,Color.WHITE)
  return
 if mode=="graph":
  var limits:=axis_limits()
  var has_v:=connected.any(func(c):return c.kind=="V")
  var has_i:=connected.any(func(c):return c.kind=="A")
  for i in 5:
   var y:=box.position.y+box.size.y*i/4.0
   var factor:=1.0-float(i)*.5
   draw_line(Vector2(box.position.x,y),Vector2(box.end.x,y),Color("365565"),1)
   if has_v:draw_string(font,Vector2(0,y+4),"%.2f"%(float(limits.V)*factor/.86),HORIZONTAL_ALIGNMENT_RIGHT,68,12,text_color)
   if has_i:draw_string(font,Vector2(box.end.x+7,y+4),"%.3f"%(float(limits.A)*factor/.86),HORIZONTAL_ALIGNMENT_LEFT,67,12,text_color)
  var hz:=maxf(.001,frequency)
  for i in 9:
   var x:=box.position.x+box.size.x*i/8.0
   draw_line(Vector2(x,box.position.y),Vector2(x,box.end.y),Color("365565"),1)
   draw_string(font,Vector2(x-26,box.end.y+17),"%.1f"%(float(i)*.25/hz*1000.0),HORIZONTAL_ALIGNMENT_CENTER,52,11,text_color)
  draw_line(Vector2(box.position.x,box.get_center().y),Vector2(box.end.x,box.get_center().y),Color("8099a0"),1)
  for channel in connected:
   var points:=PackedVector2Array()
   var scale:float=limits[str(channel.kind)]
   for i in 161:
    var t:=float(i)/160.0
    points.append(Vector2(box.position.x+t*box.size.x,box.get_center().y-sample(channel,2.0*t)/scale*box.size.y*.43))
   draw_polyline(points,COLORS[int(channel.color)],2.0,true)
  var labels:="Time (ms) · %g Hz"%frequency
  if has_v:labels+="    Left axis: voltage (V)"
  if has_i:labels+="    Right axis: current (A)"
  draw_string(font,Vector2(box.position.x,box.end.y+37),labels,HORIZONTAL_ALIGNMENT_LEFT,-1,12,text_color)
 else:
  var center:=box.get_center();var radius:=minf(box.size.x,box.size.y)*.40
  for i in 4:
   var ring:=radius*(i+1)/4.0
   draw_arc(center,ring,0,TAU,64,Color("496775"),1,true)
   draw_string(font,center+Vector2(ring-15,-5),"%d%%"%((i+1)*25),HORIZONTAL_ALIGNMENT_LEFT,-1,11,text_color)
  draw_line(center-Vector2(radius,0),center+Vector2(radius,0),Color("92aab1"),1)
  draw_line(center-Vector2(0,radius),center+Vector2(0,radius),Color("92aab1"),1)
  for mark in [["0°",Vector2(radius+8,4)],["90°",Vector2(-12,-radius-8)],["180°",Vector2(-radius-38,4)],["-90°",Vector2(-14,radius+16)]]:
   draw_string(font,center+mark[1],mark[0],HORIZONTAL_ALIGNMENT_LEFT,-1,12,text_color)
  var max_v:=.0001;var max_i:=.0001
  for c in connected:
   if c.kind=="V":max_v=maxf(max_v,c.value.length())
   else:max_i=maxf(max_i,c.value.length())
  for c in connected:
   var p:Vector2=c.value;var scale:=max_v if c.kind=="V" else max_i
   var endpoint:=center+Vector2(p.x,-p.y)*radius/scale
   draw_line(center,endpoint,COLORS[int(c.color)],3,true)
   draw_circle(endpoint,4,COLORS[int(c.color)])
  draw_string(font,Vector2(box.position.x,box.end.y+37),"Rings show % of each quantity's maximum RMS magnitude",HORIZONTAL_ALIGNMENT_LEFT,-1,12,text_color)
