extends Control
const EquationLayout=preload("res://scripts/ui/paper_workspace/equations/layout.gd")
const EquationParser=preload("res://scripts/ui/paper_workspace/equations/parser.gd")
signal erase_ink(point: Vector2)
signal changed(item: Dictionary)
signal removed(id: String)
signal selected(item: Dictionary)
var items: Array=[]
var tool := "answer"
var writable := false
var selection := ""
var dragging := false
var drag_offset := Vector2.ZERO
var ink_color := Color("263743")
var text_defaults := {"font":"Sans","font_size":24,"angle":0.0,"equation":false}
var fonts := {}
var selection_actions: HBoxContainer
var resize_handle: Control
func _ready() -> void:
	for family in ["Sans","Serif","Mono"]:
		var font := SystemFont.new();font.font_names=[{"Sans":"Arial","Serif":"Georgia","Mono":"Consolas"}[family]];fonts[family]=font
	selection_actions=HBoxContainer.new();selection_actions.mouse_filter=Control.MOUSE_FILTER_STOP;selection_actions.hide();add_child(selection_actions)
	var edit := Button.new();edit.text="Edit";edit.tooltip_text="Edit selected text";selection_actions.add_child(edit);edit.pressed.connect(func():var item:=find_item(selection);if not item.is_empty():selected.emit(item))
	var resize := Button.new();resize.text="↗";resize.tooltip_text="Drag to resize selected text";selection_actions.add_child(resize)
	resize.gui_input.connect(func(event):
		if event is InputEventMouseMotion and event.button_mask & MOUSE_BUTTON_MASK_LEFT and not selection.is_empty():
			var item := find_item(selection)
			if not item.is_empty():update_selected("font_size",clampi(int(item.font_size+event.relative.x*0.3),10,96))
	)
func _process(_delta: float) -> void:
	if not is_instance_valid(selection_actions):return
	var item := find_item(selection)
	selection_actions.visible=writable and tool in ["text","equation"] and not item.is_empty() and not bool(item.get("baked",false))
	if selection_actions.visible:
		selection_actions.position=(item.position*size+Vector2(0,-52)).clamp(Vector2.ZERO,Vector2(maxf(0,size.x-130),maxf(0,size.y-42)))
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
			if dragging:changed.emit(find_item(selection).duplicate(true))
			dragging=false;return
		for i in range(items.size()-1,-1,-1):
			var item: Dictionary=items[i]
			var local: Vector2=(event.position-item.position*size).rotated(-float(item.angle))
			var box: Vector2=measure(item.text,int(item.font_size),fonts.get(item.font,ThemeDB.fallback_font),item.kind=="equation")
			box.x=maxf(box.x,float(item.get("box_width",box.x)))
			if Rect2(Vector2(-6,-6),box+Vector2(12,12)).has_point(local):
				if tool=="eraser":
					if bool(item.get("baked",false)):items.remove_at(i);removed.emit(item.id);queue_redraw()
					else:erase_ink.emit(event.position)
					accept_event();return
				if item.get("baked",false):continue
				selection=item.id;drag_offset=event.position-item.position*size;dragging=true;selected.emit(item);queue_redraw();accept_event();return
		if tool=="eraser":erase_ink.emit(event.position);accept_event();return
		if tool in ["text","equation"]:
			var equation := tool=="equation" or bool(text_defaults.get("equation",false))
			var item := {"id":str(Time.get_ticks_usec()),"kind":"equation" if equation else "text","text":"a/b" if equation else "Text","position":event.position/size,"angle":float(text_defaults.get("angle",0.0)),"font_size":int(text_defaults.get("font_size",24)),"font":str(text_defaults.get("font","Sans")),"color":ink_color.to_html(false),"bold":bool(text_defaults.get("bold",false)),"italic":bool(text_defaults.get("italic",false)),"align":str(text_defaults.get("align","left")),"opacity":float(text_defaults.get("opacity",1.0)),"box_width":float(text_defaults.get("box_width",280.0)),"baked":false}
			items.append(item);selection=item.id;changed.emit(item.duplicate(true));selected.emit(item);queue_redraw();accept_event()
	elif event is InputEventMouseMotion and tool=="eraser" and event.button_mask & MOUSE_BUTTON_MASK_LEFT:erase_ink.emit(event.position);accept_event()
	elif event is InputEventMouseMotion and dragging:
		var item := find_item(selection)
		if not item.is_empty():item.position=((event.position-drag_offset)/size).clamp(Vector2.ZERO,Vector2.ONE);queue_redraw()
func update_selected(key: String,value: Variant) -> void:
	var item := find_item(selection)
	if item.is_empty() or item.get("baked",false):return
	item[key]=value;changed.emit(item.duplicate(true));queue_redraw()
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
		var lines := text.split("\n",false)
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
	for index in text.split("\n",false).size():
		var line: String=text.split("\n",false)[index]
		draw_string(font,pos+Vector2(0,font.get_ascent(fs)+index*font.get_height(fs)),line,HORIZONTAL_ALIGNMENT_LEFT,-1,fs,color)
func _draw() -> void:
	for item in items:
		var font: Font=fonts.get(item.font,ThemeDB.fallback_font)
		if bool(item.get("bold",false)) or bool(item.get("italic",false)):
			var variant := FontVariation.new()
			variant.base_font=font
			variant.variation_embolden=0.7 if bool(item.get("bold",false)) else 0.0
			variant.variation_transform=Transform2D(Vector2(1,0),Vector2(-0.18,1),Vector2.ZERO) if bool(item.get("italic",false)) else Transform2D.IDENTITY
			font=variant
		draw_set_transform(item.position*size,float(item.angle))
		var color := Color(str(item.color));color.a*=clampf(float(item.get("opacity",1.0)),0.05,1.0)
		var extent := measure(item.text,int(item.font_size),font,item.kind=="equation")
		var box_width := maxf(extent.x,float(item.get("box_width",extent.x)))
		var origin := Vector2.ZERO
		if str(item.get("align","left"))=="center":origin.x=(box_width-extent.x)*0.5
		elif str(item.get("align","left"))=="right":origin.x=box_width-extent.x
		paint(item.text,origin,int(item.font_size),font,color,item.kind=="equation")
		if writable and item.id==selection and not item.get("baked",false) and tool in ["text","equation"]:draw_rect(Rect2(Vector2(-4,-4),Vector2(box_width,extent.y)+Vector2(8,8)),Color("3a8ca0"),false,1)
	draw_set_transform(Vector2.ZERO)
