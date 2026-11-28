extends Container

var columns := 7
var cell_size := Vector2(32,26)
var gap := Vector2(5,5)

func _get_minimum_size() -> Vector2:
	var rows:=ceili(float(get_child_count())/columns)
	return Vector2(columns,rows)*cell_size+Vector2(columns-1,maxi(0,rows-1))*gap

func _notification(what: int) -> void:
	if what!=NOTIFICATION_SORT_CHILDREN:return
	var rows:=ceili(float(get_child_count())/columns)
	if rows==0:return
	var cell:=(size-Vector2(columns-1,rows-1)*gap)/Vector2(columns,rows)
	for index in get_child_count():
		var key:=get_child(index) as Control
		if not key.visible:continue
		var width: int=key.get_meta("keypad_span",1)
		var origin:=Vector2(index%columns,floorf(float(index)/columns))*(cell+gap)
		fit_child_in_rect(key,Rect2(origin,Vector2(cell.x*width+gap.x*(width-1),cell.y)))
