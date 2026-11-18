extends Control

const BACK := ["triceps","rear_deltoids","lats","trapezius","lower_back","hamstrings","glutes","calves"]
const REGIONS := {
	"biceps":[Vector3(9,17,3.3),Vector3(27,17,3.3)],
	"triceps":[Vector3(9,17,3.0),Vector3(27,17,3.0)],
	"forearms":[Vector3(6.7,24,2.4),Vector3(29.3,24,2.4)],
	"front_deltoids":[Vector3(11,12.4,2.6),Vector3(25,12.4,2.6)],
	"side_deltoids":[Vector3(8.9,12.9,2.25),Vector3(27.1,12.9,2.25)],
	"rear_deltoids":[Vector3(10.7,12.5,2.65),Vector3(25.3,12.5,2.65)],
	"chest":[Vector3(14.4,14.8,3.3),Vector3(21.6,14.8,3.3)],
	"lats":[Vector3(13.4,19.2,2.75),Vector3(22.6,19.2,2.75)],
	"trapezius":[Vector3(18,12.9,3.6)],
	"lower_back":[Vector3(16.4,22.8,2.4),Vector3(19.6,22.8,2.4)],
	"abdominals":[Vector3(18,19.1,2.8),Vector3(18,23,2.6)],
	"quadriceps":[Vector3(15,30.3,2.75),Vector3(21,30.3,2.75)],
	"hamstrings":[Vector3(15.1,31.3,2.3),Vector3(20.9,31.3,2.3)],
	"glutes":[Vector3(14.8,25,2.8),Vector3(21.2,25,2.8)],
	"calves":[Vector3(14.5,39,2.4),Vector3(21.5,39,2.4)]
}
var muscle := ""

func _ready() -> void:
	custom_minimum_size = Vector2(36,46)

func _draw() -> void:
	var shade := Color("8295a0")
	var highlight := Color("f2b966")
	draw_rect(Rect2(0,0,36,46),Color("293942"))
	draw_circle(Vector2(18,5),3.1,shade,true,-1,true)
	draw_colored_polygon(PackedVector2Array([Vector2(9,11),Vector2(15,8),Vector2(21,8),Vector2(27,11),Vector2(22,22),Vector2(24,27),Vector2(12,27),Vector2(14,22)]),shade)
	for side in [-1.0,1.0]:
		draw_line(Vector2(18+side*7,12),Vector2(18+side*11,25),shade,4.1,true)
		draw_line(Vector2(18+side*3,25),Vector2(18+side*3.5,43),shade,5.0,true)
	for point in REGIONS.get(muscle,[]):
		draw_circle(Vector2(point.x,point.y),point.z,highlight,true,-1,true)
	if muscle in BACK:
		draw_line(Vector2(18,9),Vector2(18,25),Color("526675"),1.05,true)
