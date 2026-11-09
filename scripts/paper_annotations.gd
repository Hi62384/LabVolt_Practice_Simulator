extends Control
const EquationLayout=preload("res://scripts/ui/paper_workspace/equations/layout.gd")
const EquationParser=preload("res://scripts/ui/paper_workspace/equations/parser.gd")
signal erase_ink(point: Vector2)
signal changed(item: Dictionary)
signal removed(id: String)
signal selected(item: Dictionary)
signal edit_requested(item: Dictionary)
var items: Array=[]
var tool := "answer"
var writable := false
var selection := ""
var dragging := false
var drag_offset := Vector2.ZERO
var ink_color := Color("263743")
var text_defaults := {"font":"Sans","font_size":24,"angle":0.0,"equation":false}
var fonts := {}
var transform_drag := ""
var drag_start := {}
var inline_editor: TextEdit
var inline_item_id := ""
func _ready() -> void:
	for family in ["Sans","Serif","Mono"]:
		var font := SystemFont.new();font.font_names=[{"Sans":"Arial","Serif":"Georgia","Mono":"Consolas"}[family]];fonts[family]=font
func _bounds(item: Dictionary) -> Vector2:
	var extent := measure(item.text,int(item.font_size),fonts.get(item.font,ThemeDB.fallback_font),item.kind=="equation")
	return Vector2(maxf(extent.x,float(item.get("box_width",extent.x))),extent.y)

func _handles(bounds: Vector2) -> Dictionary:
	return {"left":Vector2(-4,bounds.y*.5),"right":Vector2(bounds.x+4,bounds.y*.5),
		"rotate":Vector2(bounds.x*.5,-28)}

func set_tool(value: String) -> void:
	tool=value;mouse_filter=Control.MOUSE_FILTER_STOP if writable and tool in ["text","equation","eraser"] else Control.MOUSE_FILTER_IGNORE
	queue_redraw()
func find_item(id: String) -> Dictionary:
	for item in items:
		if item.id==id:return item
	return {}
func _gui_input(event: InputEvent) -> void:
	if not writable:return
	if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT:
		if not event.pressed:
			if dragging or not transform_drag.is_empty():changed.emit(find_item(selection).duplicate(true))
			dragging=false
			transform_drag=""
			return
		var active := find_item(selection)
		if tool in ["text","equation"] and not active.is_empty() and not active.get("baked",false):
			var bounds := _bounds(active)
			var point: Vector2 = (event.position-Vector2(active.position)*size).rotated(-float(active.angle))
			var handles := _handles(bounds)
			for handle in handles:
				if point.distance_to(handles[handle])<=11:
					transform_drag=handle
					drag_start={"position":active.position,"angle":active.angle,"width":bounds.x,"pointer":event.position}
					accept_event()
					return
		for i in range(items.size()-1,-1,-1):
			var item: Dictionary=items[i]
			var local: Vector2=(event.position-item.position*size).rotated(-float(item.angle))
			var box: Vector2=measure(item.text,int(item.font_size),fonts.get(item.font,ThemeDB.fallback_font),item.kind=="equation")
			box.x=maxf(box.x,float(item.get("box_width",box.x)))
			if Rect2(Vector2(-6,-6),box+Vector2(12,12)).has_point(local):
				if tool=="eraser":
					items.remove_at(i);removed.emit(item.id);queue_redraw()
					accept_event();return
				if item.get("baked",false):continue
				selection=item.id
				drag_offset=event.position-item.position*size
				dragging=not event.double_click
				selected.emit(item)
				if event.double_click:edit_requested.emit(item)
				queue_redraw();accept_event();return
		if tool=="eraser":erase_ink.emit(event.position);accept_event();return
		if tool in ["text","equation"]:
			var equation := tool=="equation" or bool(text_defaults.get("equation",false))
			var item := {"id":str(Time.get_ticks_usec()),"kind":"equation" if equation else "text","text":"a/b" if equation else "Text","position":event.position/size,"angle":float(text_defaults.get("angle",0.0)),"font_size":int(text_defaults.get("font_size",24)),"font":str(text_defaults.get("font","Sans")),"color":ink_color.to_html(false),"bold":bool(text_defaults.get("bold",false)),"italic":bool(text_defaults.get("italic",false)),"align":str(text_defaults.get("align","left")),"opacity":float(text_defaults.get("opacity",1.0)),"box_width":float(text_defaults.get("box_width",280.0)),"baked":false}
			items.append(item);selection=item.id;changed.emit(item.duplicate(true));selected.emit(item);queue_redraw();accept_event()
	elif event is InputEventMouseMotion and tool=="eraser" and event.button_mask & MOUSE_BUTTON_MASK_LEFT:erase_ink.emit(event.position);accept_event()
	elif event is InputEventMouseMotion and not transform_drag.is_empty():
		var item := find_item(selection)
		if item.is_empty():return
		var angle := float(drag_start.angle)
		var origin: Vector2=Vector2(drag_start.position)*size
		var offset: Vector2 = (event.position-Vector2(drag_start.pointer)).rotated(-angle)
		if transform_drag=="rotate":
			var from: Vector2=Vector2(drag_start.pointer)-origin
			item.angle=wrapf(angle+from.angle_to(event.position-origin),-PI,PI)
		else:
			var left := transform_drag=="left"
			var width := clampf(float(drag_start.width)+offset.x*(-1 if left else 1),40,720)
			item.box_width=width
			if left:item.position=((origin+Vector2(float(drag_start.width)-width,0).rotated(angle))/size).clamp(Vector2.ZERO,Vector2.ONE)
		queue_redraw()
		accept_event()
	elif event is InputEventMouseMotion and dragging:
		var item := find_item(selection)
		if not item.is_empty():item.position=((event.position-drag_offset)/size).clamp(Vector2.ZERO,Vector2.ONE);queue_redraw()
func update_selected(key: String,value: Variant) -> void:
	var item := find_item(selection)
	if item.is_empty() or item.get("baked",false):return
	item[key]=value;changed.emit(item.duplicate(true));queue_redraw()

func edit_inline(item: Dictionary) -> void:
	if not writable or item.get("baked",false):return
	finish_inline_edit()
	inline_item_id=str(item.id)
	var editor := TextEdit.new()
	inline_editor=editor
	editor.text=str(item.text)
	editor.accessibility_name="Edit text on the page"
	editor.caret_blink=true
	editor.context_menu_enabled=true
	editor.add_theme_stylebox_override("normal",StyleBoxEmpty.new())
	editor.add_theme_stylebox_override("focus",StyleBoxEmpty.new())
	editor.add_theme_constant_override("line_spacing",0)
	editor.add_theme_color_override("font_selected_color",Color.WHITE)
	editor.add_theme_color_override("selection_color",Color("356d78"))
	add_child(editor)
	_layout_inline_editor()
	editor.text_changed.connect(_layout_inline_editor)
	editor.focus_exited.connect(func():finish_inline_edit())
	editor.gui_input.connect(func(event: InputEvent):
		if event is InputEventKey and event.pressed and (event.keycode==KEY_ESCAPE or (event.ctrl_pressed and event.keycode in [KEY_ENTER,KEY_KP_ENTER])):
			editor.accept_event()
			finish_inline_edit(event.keycode!=KEY_ESCAPE))
	editor.grab_focus()
	var pointer := editor.get_local_mouse_position()
	if Rect2(Vector2.ZERO,editor.size).has_point(pointer):
		var hit := editor.get_line_column_at_pos(Vector2i(pointer))
		if hit.y>=0:
			editor.set_caret_line(hit.y)
			editor.set_caret_column(hit.x)
	else:
		editor.set_caret_line(editor.get_line_count()-1)
		editor.set_caret_column(editor.get_line(editor.get_caret_line()).length())
	queue_redraw()

func _layout_inline_editor() -> void:
	var item := find_item(inline_item_id)
	if item.is_empty() or not is_instance_valid(inline_editor):return
	var font := _item_font(item)
	var font_size := int(item.font_size)
	var color := Color(str(item.color))
	color.a*=float(item.get("opacity",1.0))
	inline_editor.add_theme_font_override("font",font)
	inline_editor.add_theme_font_size_override("font_size",font_size)
	inline_editor.add_theme_color_override("font_color",color)
	inline_editor.add_theme_color_override("caret_color",Color("263743"))
	var extent := measure(inline_editor.text,font_size,font,false)
	var width := maxf(extent.x,float(item.get("box_width",extent.x)))
	var offset := Vector2(_alignment_offset(item,width,extent.x),0)
	inline_editor.rotation=float(item.angle)
	inline_editor.position=Vector2(item.position)*size+offset.rotated(inline_editor.rotation)
	inline_editor.size=Vector2(maxf(48,width-offset.x)+16,extent.y+font.get_height(font_size))

func finish_inline_edit(save := true) -> void:
	if not is_instance_valid(inline_editor):return
	var editor := inline_editor
	var item := find_item(inline_item_id)
	inline_editor=null
	inline_item_id=""
	var value := editor.text.left(256)
	editor.hide()
	editor.queue_free()
	if save and not item.is_empty() and not item.get("baked",false) and value!=str(item.text):
		item.text=value
		changed.emit(item.duplicate(true))
	queue_redraw()

func _item_font(item: Dictionary) -> Font:
	var font: Font=fonts.get(item.font,ThemeDB.fallback_font)
	if not item.get("bold",false) and not item.get("italic",false):return font
	var variant := FontVariation.new()
	variant.base_font=font
	variant.variation_embolden=0.7 if item.get("bold",false) else 0.0
	variant.variation_transform=Transform2D(Vector2(1,0),Vector2(-0.18,1),Vector2.ZERO) if item.get("italic",false) else Transform2D.IDENTITY
	return variant

func _alignment_offset(item: Dictionary, width: float, text_width: float) -> float:
	match item.get("align","left"):
		"center":return (width-text_width)*.5
		"right":return width-text_width
	return 0.0
static func split_operator(text: String,operator: String) -> int:
	var depth := 0
	for i in text.length():
		if text[i]=="(":depth+=1
		elif text[i]==")":depth-=1
		elif text[i]==operator and depth==0:return i
	return -1
static func unwrap(text: String) -> String:
	if text.begins_with("(") and text.ends_with(")"):
		var depth := 0
		for i in text.length()-1:
			if text[i]=="(":depth+=1
			elif text[i]==")":depth-=1
			if depth==0:return text
		return text.substr(1,text.length()-2)
	return text
static func equation_error(text: String) -> String:
	var parsed: Dictionary=EquationParser.new().parse(text)
	return str(parsed.get("error",""))
static func measure(text: String,fs: int,font: Font,equation: bool,depth := 0) -> Vector2:
	if equation:return EquationLayout.build(text,font,fs).size
	if equation and depth==0 and not equation_error(text).is_empty():equation=false
	if not equation or depth>12:
		var lines := text.split("\n")
		var width := 8.0
		for line in lines:width=maxf(width,font.get_string_size(line,HORIZONTAL_ALIGNMENT_LEFT,-1,fs).x)
		return Vector2(width,maxi(1,lines.size())*font.get_height(fs))
	var grouped := unwrap(text);if grouped!=text and split_operator(grouped,"/")<0 and split_operator(grouped,"^")<0 and split_operator(grouped,"_")<0:grouped=text
	text=grouped
	var index := split_operator(text,"/")
	if index>=0:
		var a := measure(text.left(index),fs,font,true,depth+1);var b := measure(text.substr(index+1),fs,font,true,depth+1)
		return Vector2(maxf(a.x,b.x)+12,a.y+b.y+10)
	index=split_operator(text,"^")
	if index>=0:
		var a := measure(text.left(index),fs,font,true,depth+1);var b := measure(text.substr(index+1),maxi(10,int(fs*.7)),font,true,depth+1)
		return Vector2(a.x+b.x,a.y+b.y*.5)
	index=split_operator(text,"_")
	if index>=0:
		var a := measure(text.left(index),fs,font,true,depth+1);var b := measure(text.substr(index+1),maxi(10,int(fs*.7)),font,true,depth+1)
		return Vector2(a.x+b.x,a.y+b.y*.5)
	return measure(text,fs,font,false)
func paint(text: String,pos: Vector2,fs: int,font: Font,color: Color,equation: bool,depth := 0) -> void:
	if equation:
		EquationLayout.draw(self,EquationLayout.build(text,font,fs),pos,font,color)
		return
	if equation and depth==0 and not equation_error(text).is_empty():equation=false
	if equation and depth<=12:
		var grouped := unwrap(text);if grouped!=text and split_operator(grouped,"/")<0 and split_operator(grouped,"^")<0 and split_operator(grouped,"_")<0:grouped=text
		text=grouped
		var index := split_operator(text,"/")
		if index>=0:
			var a := measure(text.left(index),fs,font,true,depth+1);var b := measure(text.substr(index+1),fs,font,true,depth+1);var width := maxf(a.x,b.x)+12
			paint(text.left(index),pos+Vector2((width-a.x)/2,0),fs,font,color,true,depth+1)
			draw_line(pos+Vector2(0,a.y+4),pos+Vector2(width,a.y+4),color,1.5,true)
			paint(text.substr(index+1),pos+Vector2((width-b.x)/2,a.y+10),fs,font,color,true,depth+1);return
		index=split_operator(text,"^")
		if index>=0:
			var a := measure(text.left(index),fs,font,true,depth+1);var b := measure(text.substr(index+1),maxi(10,int(fs*.7)),font,true,depth+1)
			paint(text.left(index),pos+Vector2(0,b.y*.5),fs,font,color,true,depth+1);paint(text.substr(index+1),pos+Vector2(a.x,0),maxi(10,int(fs*.7)),font,color,true,depth+1);return
		index=split_operator(text,"_")
		if index>=0:
			var a := measure(text.left(index),fs,font,true,depth+1);var b := measure(text.substr(index+1),maxi(10,int(fs*.7)),font,true,depth+1)
			paint(text.left(index),pos,fs,font,color,true,depth+1);paint(text.substr(index+1),pos+Vector2(a.x,a.y*.45),maxi(10,int(fs*.7)),font,color,true,depth+1);return
	var lines := text.split("\n")
	for index in lines.size():
		var line: String=lines[index]
		draw_string(font,pos+Vector2(0,font.get_ascent(fs)+index*font.get_height(fs)),line,HORIZONTAL_ALIGNMENT_LEFT,-1,fs,color)
func _draw() -> void:
	for item in items:
		if item.id==inline_item_id:continue
		var font := _item_font(item)
		draw_set_transform(item.position*size,float(item.angle))
		var color := Color(str(item.color));color.a*=clampf(float(item.get("opacity",1.0)),0.05,1.0)
		var extent := measure(item.text,int(item.font_size),font,item.kind=="equation")
		var box_width := maxf(extent.x,float(item.get("box_width",extent.x)))
		var origin := Vector2(_alignment_offset(item,box_width,extent.x),0)
		paint(item.text,origin,int(item.font_size),font,color,item.kind=="equation")
		if writable and item.id==selection and not item.get("baked",false) and tool in ["text","equation"]:
			var outline := Color("3a8ca0")
			var handles := _handles(Vector2(box_width,extent.y))
			draw_rect(Rect2(Vector2(-4,-4),Vector2(box_width,extent.y)+Vector2(8,8)),outline,false,1.5)
			draw_line(Vector2(box_width*.5,-4),handles.rotate,outline,2,true)
			draw_circle(handles.rotate,5,outline,true,-1,true)
			for handle in ["left","right"]:draw_rect(Rect2(handles[handle]-Vector2(5,5),Vector2(10,10)),outline)
	draw_set_transform(Vector2.ZERO)
