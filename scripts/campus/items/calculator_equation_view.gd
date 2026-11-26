extends Control

const Layout = preload("res://scripts/ui/paper_workspace/equations/layout.gd")
var expression := ""
var ink := Color("dcf5fb")
var plan: Dictionary={}

func set_expression(value: String) -> void:
	expression=value
	var font:=get_theme_default_font()
	plan=Layout.build(expression,font,20) if not expression.is_empty() else {}
	custom_minimum_size.y=maxf(26.0,float(plan.get("size",Vector2.ZERO).y)+6.0)
	queue_redraw()

func _ready() -> void:
	clip_contents=true
	set_expression("")

func _draw() -> void:
	if plan.is_empty():return
	var fonts:=get_theme_default_font()
	var width: float=plan.size.x
	Layout.draw(self,plan,Vector2(maxf(0.0,size.x-width)*.5,3),fonts,ink)
