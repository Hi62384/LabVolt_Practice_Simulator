extends Control

const Labels=["None","Minimal","Low","Medium","High","Extra high","Maximum"]
const Efforts=["none","minimal","low","medium","high","xhigh","max"]
const Colors=[Color("7ee3c6"),Color("7baeea"),Color("f1c476"),Color("c4a9ee")]
var points:=[]
var highlighted:=""
var title:=""

func configure(series: Array, effort: String, heading: String) -> void:
	points=series
	highlighted=effort
	title=heading
	tooltip_text=title
	for row in points:tooltip_text+="\n%s · %s · %.1f%%"%[row.model,row.reasoning_effort,row.score_percent]
	queue_redraw()

func _ready() -> void:
	custom_minimum_size.y=126
	mouse_filter=Control.MOUSE_FILTER_IGNORE

func _draw() -> void:
	var font:=get_theme_default_font()
	var box:=Rect2(38,12,maxf(1.,size.x-51.),maxf(1.,size.y-36.))
	for percent in [0,50,100]:
		var y:=box.end.y-box.size.y*float(percent)/100.
		draw_line(Vector2(box.position.x,y),Vector2(box.end.x,y),Color("345462"))
		draw_string(font,Vector2(1,y+5),"%d%%"%percent,HORIZONTAL_ALIGNMENT_LEFT,-1,11,Color("aac5d0"))
	var x_delta:=box.size.x/6.
	for i in Efforts.size():
		var x:=box.position.x+i*x_delta
		if highlighted==Efforts[i]:draw_line(Vector2(x,box.position.y),Vector2(x,box.end.y),Color("518b91"),2.)
		draw_string(font,Vector2(x-x_delta*.5,box.end.y+15),Labels[i],HORIZONTAL_ALIGNMENT_CENTER,x_delta,10,Color("aac5d0"))
	var assigned:=[]
	for record in points:
		var index:=Efforts.find(record.reasoning_effort)
		if index<0:continue
		if record.model not in assigned:assigned.append(record.model)
		var x:=box.position.x+index*x_delta
		var y:=box.end.y-box.size.y*float(record.score_percent)/100.
		draw_circle(Vector2(x,y),4.,Colors[assigned.find(record.model)%Colors.size()])
	if points.is_empty():draw_string(font,Vector2(47,box.get_center().y),"No measured points in this benchmark",HORIZONTAL_ALIGNMENT_LEFT,-1,13,Color("c6dce4"))
