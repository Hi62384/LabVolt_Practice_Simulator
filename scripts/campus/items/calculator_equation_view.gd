extends Control

const Layout = preload("res://scripts/ui/paper_workspace/equations/layout.gd")
var expression := ""
var ink := Color("dcf5fb")
var plan: Dictionary={}
const PADDING := 4.0

func set_expression(value: String) -> void:
	expression=value
	tooltip_text=value
	var font:=get_theme_default_font()
	plan=Layout.build(expression,font,20) if not expression.is_empty() else {}
	custom_minimum_size.y=maxf(26.0,float(plan.get("size",Vector2.ZERO).y)+6.0)
	queue_redraw()

func _ready() -> void:
	clip_contents=true
	resized.connect(queue_redraw)
	set_expression(expression)

func _draw_scale() -> float:
	var bounds: Vector2=plan.size
	var available: Vector2=(size-Vector2.ONE*PADDING*2.0).max(Vector2.ONE)
	return minf(1.0,minf(available.x/maxf(bounds.x,1.0),available.y/maxf(bounds.y,1.0)))

func _draw() -> void:
	if plan.is_empty():return
	var zoom:=_draw_scale()
	draw_set_transform((size-Vector2(plan.size)*zoom)*.5,0.0,Vector2.ONE*zoom)
	Layout.draw(self,plan,Vector2.ZERO,get_theme_default_font(),ink)
