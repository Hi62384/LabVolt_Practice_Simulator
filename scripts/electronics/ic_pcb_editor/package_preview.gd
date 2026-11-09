extends Control
const Surface = preload("res://scripts/pcb_design/surface_layout.gd")
const Board = preload("res://scripts/breadboard_model.gd")
const Artwork = preload("res://scripts/electronics/component_shop_ui/catalog_presentation.gd")
const Geometry = preload("res://scripts/package_editor/package_geometry.gd")
signal selected(index: int)
signal moved(index: int,point: Vector2i)
signal surface_selected(id: String)
signal surface_move(id: String, point: Vector2i, rotation: int)
signal add_requested(point: Vector2i)
var model: RefCounted
var selected_index:=-1
var dragging:=false
var chip_style := false
var interactive := true
var allow_drag := true
var preview_point:=Vector2i.ZERO
var edit_surface := false
var surface_id := ""
var surface_drag := false
var drag_offset := Vector2i.ZERO
var artwork := {}

func _ready() -> void:
	focus_mode = Control.FOCUS_CLICK

func _board_data() -> Dictionary:
	return {"footprint":model.draft.footprint,"orientation_turns":model.turns,"width_intervals":model.width,"length_positions":model.length}

func rotate_surface() -> void:
	if edit_surface and model.surface.has(surface_id):
		var part: Dictionary = model.surface[surface_id]
		surface_move.emit(surface_id,Vector2i(part.x,part.y),(int(part.turns)+1)%4)
		queue_redraw()

static func board_image(bp: Dictionary, definitions: Dictionary) -> Texture2D:
	var image := Image.create_empty(156,92,false,Image.FORMAT_RGBA8)
	image.fill(Color("152c3b"))
	var fp: Dictionary = bp.get("footprint",{"width":4,"height":3})
	var dimensions := Vector2(fp.width,fp.height)
	var side := minf(126.0/dimensions.x,70.0/dimensions.y)
	var outline := Rect2((Vector2(156,92)-dimensions*side)*.5,dimensions*side)
	var mask := Color.from_string(str(fp.get("color","24775b")),Color("24775b"))
	image.fill_rect(Rect2i(outline),mask)
	for pin in bp.pins:
		var center := outline.position+(Vector2(Geometry.position(pin))+Vector2(.5,.5))*side
		image.fill_rect(Rect2i(Vector2i(center)-Vector2i(2,2),Vector2i(4,4)),Color("d9bc81"))
	for part in bp.parts:
		if not bp.get("surface_layout",{}).has(part.id): continue
		var body := Surface.view_rect(bp,bp.surface_layout[part.id],part.type,definitions,outline).grow(-.5)
		image.fill_rect(Rect2i(Vector2i(body.position),Vector2i(body.size).max(Vector2i.ONE)),Surface.part_color(part.type))
	return ImageTexture.create_from_image(image)

func _rect() -> Rect2:
	var width:=float(model.draft.footprint.width);var height:=float(model.draft.footprint.height)
	var side:=maxf(1.0,minf((size.x-100.0)/width,(size.y-96.0)/height))
	return Rect2((size-Vector2(width,height)*side)/2,Vector2(width,height)*side)

func _point(index: int) -> Vector2:
	var rect:=_rect();var pin: Dictionary=model.pins[index]
	return rect.position+(Vector2(float(pin.position.x)+.5,float(pin.position.y)+.5)/Vector2(float(model.draft.footprint.width),float(model.draft.footprint.height)))*rect.size

func _grid(point: Vector2) -> Vector2i:
	var rect:=_rect();var q:=(point-rect.position)/rect.size
	return Vector2i(clampi(int(floor(q.x*float(model.draft.footprint.width))),0,int(model.draft.footprint.width)-1),clampi(int(floor(q.y*float(model.draft.footprint.height))),0,int(model.draft.footprint.height)-1))

func _draw() -> void:
	if model==null:return
	var rect := _rect()
	var cell := rect.size.x / float(model.draft.footprint.width)
	var tint := Color(str(model.draft.footprint.get("color","24775b")))
	var chip := rect
	if chip_style:
		var inset: Vector2 = model.chip_body_inset() * cell
		chip = Rect2(rect.position + inset, rect.size - inset * 2)
		draw_rect(rect, Color("172d3a"))
		var body := StyleBoxFlat.new()
		body.bg_color = tint
		body.border_color = tint.lightened(.26)
		body.set_border_width_all(2)
		body.set_corner_radius_all(10)
		body.shadow_color = Color(0,0,0,.44)
		body.shadow_size = 7
		draw_style_box(body,chip)
		if not model.pins.is_empty():
			var mark_point := _point(0).clamp(chip.position, chip.end)
			draw_circle(mark_point.lerp(chip.get_center(), .24), minf(5, cell * .12), Color("d3dce5"), true)
		var marking := str(model.draft.get("marking",""))
		if not marking.is_empty():
			draw_string(get_theme_default_font(),chip.position+Vector2(4,chip.size.y*.5+7),marking,HORIZONTAL_ALIGNMENT_CENTER,maxf(1,chip.size.x-8),20,Color("dce5e9"))
	else: draw_rect(rect,tint)
	preload("res://scripts/pcb_design/design.gd").draw_grid(self,rect,model.draft.footprint)
	for i in model.pins.size():
		var p:=_point(i) if not (dragging and i==selected_index) else rect.position+(Vector2(preview_point)+Vector2(.5,.5))/Vector2(float(model.draft.footprint.width),float(model.draft.footprint.height))*rect.size
		var radius := minf(12,cell*.29)
		var color := Color("efc784") if i==selected_index else Color("c9d8d7")
		if chip_style:
			if dragging and i == selected_index and model.pins.any(func(pin):return pin.id != model.pins[i].id and Vector2i(int(pin.position.x),int(pin.position.y)) == preview_point):
				color = Color("e76b75")
			var shoulder := p.clamp(chip.position, chip.end)
			if not p.is_equal_approx(shoulder):
				draw_line(p,shoulder,color,maxf(2,radius*.66),true)
			draw_circle(p,radius,color,true)
			if cell >= 24:
				draw_string(get_theme_default_font(),p+Vector2(-6,4),str(i+1),HORIZONTAL_ALIGNMENT_CENTER,12,10,Color("21323a"))
		else:
			draw_circle(p,12,color)
			draw_circle(p,5,Color("253941"))

	if model.draft.package == "PCB":
		var bp := _board_data()
		for id in model.surface:
			var record: Dictionary = model.surface[id]
			var valid := true
			if surface_drag and id == surface_id:
				record = {"x":preview_point.x,"y":preview_point.y,"turns":record.turns}
				valid = model.can_place_surface(id,preview_point,record.turns,false)
			var type: String = model.surface_type(id)
			var body := Surface.view_rect(bp,record,type,model.board.definitions,rect).grow(-2)
			draw_rect(body,Color("12252d",.65) if valid else Color("9e3e4b"))
			if id == surface_id: draw_rect(body,Color("e7c884"),false,1.5)
			if not artwork.has(type): artwork[type] = Artwork.preview(Board.catalog(model.board).get(type,{}))
			var icon: Texture2D = artwork[type]
			var turns := int(record.turns)+int(model.turns)
			var dimensions := body.size if turns%2==0 else Vector2(body.size.y,body.size.x)
			if icon != null:
				draw_set_transform(body.get_center(),turns*PI/2)
				draw_texture_rect(icon,Rect2(-dimensions*.5,dimensions),false)
				draw_set_transform(Vector2.ZERO)
			if body.size.x > 43 and body.size.y > 32:
				draw_string(get_theme_default_font(),body.position+Vector2(4,13),id,
					HORIZONTAL_ALIGNMENT_LEFT,body.size.x-8,11,Color("f3f3e4"))

func _surface_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_R:
		rotate_surface()
		accept_event()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			grab_focus()
			var bp := _board_data()
			surface_id = ""
			for id in model.surface:
				var record: Dictionary = model.surface[id]
				if Surface.view_rect(bp,record,model.surface_type(id),model.board.definitions,_rect()).has_point(event.position):
					surface_id = id
					preview_point = Vector2i(record.x,record.y)
					drag_offset = model._to_canonical(_grid(event.position))-preview_point
					surface_drag = true
					break
			surface_selected.emit(surface_id)
		elif surface_drag:
			surface_drag = false
			if model.can_place_surface(surface_id,preview_point,int(model.surface[surface_id].turns),false):
				surface_move.emit(surface_id,preview_point,int(model.surface[surface_id].turns))
		queue_redraw()
		accept_event()
	elif event is InputEventMouseMotion and surface_drag:
		preview_point = model._to_canonical(_grid(event.position))-drag_offset
		queue_redraw()
		accept_event()

func _gui_input(event: InputEvent) -> void:
	if model==null or not interactive:return
	if edit_surface:
		_surface_input(event)
		return
	if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT:
		if event.pressed:
			for i in model.pins.size():
				if _point(i).distance_to(event.position)<minf(18,_rect().size.x/float(model.draft.footprint.width)*.45):selected_index=i;selected.emit(i);dragging=allow_drag;preview_point=_grid(event.position);queue_redraw();accept_event();return
			if _rect().has_point(event.position):add_requested.emit(_grid(event.position));accept_event()
		elif dragging:
			dragging=false;moved.emit(selected_index,preview_point);queue_redraw();accept_event()
	elif event is InputEventMouseMotion and dragging:
		preview_point=_grid(event.position);queue_redraw();accept_event()
