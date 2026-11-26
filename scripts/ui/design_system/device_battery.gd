extends HBoxContainer

const Tokens=preload("res://scripts/ui/design_system/tokens.gd")
var meter: ProgressBar
var readout: Label
var last_percent: int=-1

func _ready() -> void:
	add_theme_constant_override("separation",6)
	meter=ProgressBar.new()
	meter.custom_minimum_size=Vector2(40,12)
	meter.size_flags_vertical=SIZE_SHRINK_CENTER
	meter.show_percentage=false
	meter.add_theme_stylebox_override("background",Tokens.surface(Color("122735"),Color("527589"),1))
	add_child(meter)
	readout=Label.new()
	readout.custom_minimum_size.x=38
	readout.horizontal_alignment=HORIZONTAL_ALIGNMENT_RIGHT
	readout.add_theme_font_size_override("font_size",13)
	add_child(readout)

func update_charge(percent: int) -> void:
	if percent==last_percent:return
	last_percent=percent
	meter.value=percent
	var color:=Color("86ddbd") if percent>20 else Color("ffaf91")
	meter.add_theme_stylebox_override("fill",Tokens.surface(color,color,0))
	readout.text="%d%%"%percent
	tooltip_text="Battery · "+readout.text
