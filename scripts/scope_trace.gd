extends Control
signal cursors_changed
const Settings = preload("res://scripts/dc_scope/settings.gd")
const Measure = preload("res://scripts/dc_scope/measurements.gd")
var samples: Array=[]
var settings := {}
var acquisition := {}
var cursor_a := .25
var cursor_b := .75
var dragging := 0
func _ready() -> void:
	custom_minimum_size=Vector2(400,240); mouse_filter=Control.MOUSE_FILTER_STOP; clip_contents=true
	tooltip_text="Left click/drag: cursor A. Right click/drag: cursor B. Shared time axis; each trace has its own volts/div and zero position."
func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index in [MOUSE_BUTTON_LEFT,MOUSE_BUTTON_RIGHT]:
			dragging=(1 if event.button_index==MOUSE_BUTTON_LEFT else 2) if event.pressed else 0
			if event.pressed: _move_cursor(event.position.x)
			accept_event()
	elif event is InputEventMouseMotion and dragging!=0: _move_cursor(event.position.x); accept_event()
func _move_cursor(x: float) -> void:
	if dragging==1: cursor_a=clampf(x/maxf(size.x,1.0),0,1)
	else: cursor_b=clampf(x/maxf(size.x,1.0),0,1)
	queue_redraw(); cursors_changed.emit()
func bounds() -> Vector2:
	var config := Settings.normalize(settings)
	var span := float(config.timebase)*10
	var start := float(samples[-1][0])-span if not samples.is_empty() else 0.0
	if acquisition.has("window_start"): start=float(acquisition.window_start)
	return Vector2(start,span)
func visible_samples() -> Array:
	var range := bounds()
	return Measure.window(samples,range.x,range.y)
func cursor_readings() -> Dictionary:
	var config := Settings.normalize(settings); var range := bounds()
	var result := {"dt":absf(cursor_b-cursor_a)*range.y,"a_time":range.x+cursor_a*range.y,"b_time":range.x+cursor_b*range.y,"channels":[]}
	for channel in 2:
		var a: Variant=_at_time(float(result.a_time),channel,config.channels[channel])
		var b: Variant=_at_time(float(result.b_time),channel,config.channels[channel])
		result.channels.append({"a":a,"b":b,"dv":float(b)-float(a) if a!=null and b!=null else null})
	return result
func _at_time(time: float, channel: int, setting: Dictionary) -> Variant:
	if not setting.enabled: return null
	for i in range(1,samples.size()):
		if float(samples[i-1][0])<=time and float(samples[i][0])>=time:
			var duration := float(samples[i][0])-float(samples[i-1][0])
			if duration<=0: continue
			var a := Measure.voltage(samples[i-1],channel,setting); var b := Measure.voltage(samples[i],channel,setting)
			if setting.coupling=="AC" and samples[i].size()<7:
				var dc := Measure.raw_mean(visible_samples(),channel)*float(setting.attenuation)
				a-=dc; b-=dc
			return lerpf(a,b,(time-float(samples[i-1][0]))/duration)
	return null
func channel_segments(index: int) -> PackedVector2Array:
	var config := Settings.normalize(settings); var channel: Dictionary=config.channels[index]
	var segments := PackedVector2Array()
	if not channel.enabled: return segments
	var range := bounds(); var rows := Measure.window(samples,range.x,range.y)
	var offset := 0.0
	if channel.coupling=="AC" and not rows.is_empty() and rows[0].size()<7:
		offset=Measure.raw_mean(rows,index)
	for i in range(1,rows.size()):
		var a := Measure.point(rows[i-1],index,channel,range.x,range.y,size,offset)
		var b := Measure.point(rows[i],index,channel,range.x,range.y,size,offset)
		# Clip segments rather than inventing saturated flat trace sections.
		if (a.y<0 and b.y<0) or (a.y>size.y and b.y>size.y): continue
		if a.y<0 or a.y>size.y:
			var edge := clampf(a.y,0,size.y); a=Vector2(lerpf(a.x,b.x,(edge-a.y)/(b.y-a.y)),edge)
		if b.y<0 or b.y>size.y:
			var edge := clampf(b.y,0,size.y); b=Vector2(lerpf(a.x,b.x,(edge-a.y)/(b.y-a.y)),edge)
		segments.append(a); segments.append(b)
	return segments
func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO,size),Color("101c28"))
	for i in range(11): draw_line(Vector2(size.x*i/10,0),Vector2(size.x*i/10,size.y),Color("283747"))
	for i in range(9): draw_line(Vector2(0,size.y*i/8),Vector2(size.x,size.y*i/8),Color("283747"))
	var config := Settings.normalize(settings)
	for index in 2:
		var channel: Dictionary=config.channels[index]
		if not channel.enabled: continue
		var color := Color("f0ca6b") if index==0 else Color("63d5d0")
		var zero := size.y*.5-float(channel.position)*size.y/8
		if zero>=0 and zero<=size.y:
			draw_line(Vector2(0,zero),Vector2(12,zero),color,2)
			draw_string(ThemeDB.fallback_font,Vector2(14,clampf(zero-3,14,size.y-4)),"CH%d · %.3f V/div · %.0f×"%[index+1,float(channel.scale),float(channel.attenuation)],HORIZONTAL_ALIGNMENT_LEFT,-1,13,color)
		var segments := channel_segments(index)
		if segments.size()>=2: draw_multiline(segments,color,1.5,true)
	var source: Dictionary=config.channels[int(config.source)]
	var trigger_y := size.y*.5-(float(config.trigger)/float(source.scale)+float(source.position))*size.y/8
	if source.enabled and trigger_y>=0 and trigger_y<=size.y: draw_dashed_line(Vector2(0,trigger_y),Vector2(size.x,trigger_y),Color("dd9977"),1,5)
	for x in [cursor_a,cursor_b]: draw_line(Vector2(x*size.x,0),Vector2(x*size.x,size.y),Color("b4b9cb"),1,true)
