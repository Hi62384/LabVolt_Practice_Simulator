extends "res://scripts/electronics/circuit_workspace/workspace_canvas.gd"

const Board = preload("res://scripts/breadboard_model.gd")
const Bands = preload("res://scripts/electronics/component_shop_ui/resistor_bands.gd")
const Units = preload("res://scripts/dc_scope/units.gd")
const NATIVE_BOARDS = ["native_uno", "native_pico", "native_nano"]
const Artwork = preload("res://scripts/electronics/component_shop_ui/catalog_presentation.gd")
signal feedback(message: String)
signal grabbed_component(type_id: String, instance_id: String)

signal lab_lead_placed(port: String, hole: String)
var physical_kit := false
var inventory_catalog: Dictionary
var stock_limits: Dictionary
var unlimited := false
var input_position := Vector2.ZERO
var placement: Dictionary
var available_art: Dictionary
var wire_color := Color("ed5555")
var grabbed_part := ""
var grabbed_hole := ""
var drag_preview := {}

func _ready() -> void:
	maker = true
	super._ready()
	enable_cached_board()

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		input_position = event.position
		if moving:
			drag_preview=_component_drag_trial(input_position)
			queue_redraw()
			accept_event()
			return
		if not dragging:
			var hole := hole_at(input_position)
			if hole!=hovered:
				hovered=hole
				_update_placement()
				queue_redraw()
			elif (selected_type=="wire" or hidden_wire_index>=0) and not first.is_empty() and hole.is_empty():
				queue_redraw()
			return
	if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT and not event.pressed and moving:
		_finish_component_drag(event.position)
		accept_event()
		return
	if not event is InputEventMouseButton or not event.pressed or event.button_index not in [MOUSE_BUTTON_LEFT,MOUSE_BUTTON_RIGHT]:
		super._gui_input(event)
		return
	if read_only or (event.button_index==MOUSE_BUTTON_LEFT and selected_type in ["probe+","probe-"]):
		super._gui_input(event)
		return
	grab_focus()
	input_position = event.position
	var hole := hole_at(input_position)
	if event.button_index == MOUSE_BUTTON_RIGHT:
		if moving:moving=false
		elif not selected_lab_lead.is_empty():selected_lab_lead=""
		elif not grabbed_hole.is_empty():
			cancel_grab()
		elif not first.is_empty():
			first = ""
		elif _disconnect_lab_lead_at(input_position):
			pass
		elif selected_type=="interact" and _operate_manual_input(event):
			accept_event()
			return
		elif not _delete_component_at(input_position) and not _delete_wire_at(input_position) and not hole.is_empty():
			_delete_component_at(input_position,hole)
		_update_placement()
		queue_redraw()
		accept_event()
		return
	if not selected_lab_lead.is_empty() and not hole.is_empty():
		if hole!=lab_leads.get(selected_lab_lead,{}).get("hole",""):
			lab_lead_placed.emit(selected_lab_lead,hole)
		selected_lab_lead=""
		queue_redraw()
		accept_event()
		return
	if not hole.is_empty() and grabbed_hole.is_empty() and not event.shift_pressed:
		for port in lab_leads:
			if lab_leads[port].get("hole","")==hole:
				selected_lab_lead=port
				first=""
				hovered=hole
				placement={}
				queue_redraw()
				accept_event()
				return
	if selected_type=="interact" and grabbed_hole.is_empty() and _operate_manual_input(event,true):
		accept_event()
		return
	if not hole.is_empty() and (_finish_grab(hole) or (not event.shift_pressed and _start_grab(hole))):
		hovered=hole
		_update_placement()
		queue_redraw()
		accept_event()
		return
	if selected_type=="interact":
		super._gui_input(event)
		return
	match selected_type:
		"select":
			selected.clear()
			for index in range(board.parts.size()-1,-1,-1):
				var part: Dictionary = board.parts[index]
				if _body_at(part,input_position):
					selected = [part.id]
					moving = true
					move_start = input_position
					drag_preview = {}
					break
			selection_updated.emit(selected.duplicate())
		"wire":
			if not hole.is_empty():
				if first.is_empty(): first = hole
				elif hole != first: _connect_wire(hole)
		"place":
			feedback.emit("Choose a component from the inventory.")
		_:
			if not hole.is_empty(): _click_part(hole)
	hovered = hole
	_update_placement()
	queue_redraw()
	accept_event()

func _component_drag_trial(pointer: Vector2) -> Dictionary:
	if selected.size()!=1:return {}
	for index in board.parts.size():
		var part: Dictionary=board.parts[index]
		if part.id!=selected[0]:continue
		var anchor := str(part.a)
		var destination := at(anchor)+pointer-move_start
		if not Rect2(Vector2(8,12)*zoom+pan,board_extent()*zoom).has_point(destination):
			return {"error":"Move inside the breadboard."}
		var shift := Board.grid(nearest_hole(destination))-Board.grid(anchor)
		if shift==Vector2i.ZERO:return {}
		var trial := Placement.translated(board,selected,shift.x,shift.y)
		if not trial.has("board"):return trial
		trial.part=trial.board.parts[index]
		if trial.error.is_empty():
			var others: Array=trial.board.parts.duplicate()
			others.remove_at(index)
			trial.error=_body_overlap(trial.part,others)
		return trial
	return {}

func _finish_component_drag(pointer: Vector2) -> void:
	moving=false
	var trial := _component_drag_trial(pointer)
	if not trial.is_empty():
		if trial.error.is_empty():
			commit()
			board=trial.board
			design_changed.emit(board)
		else:
			feedback.emit(trial.error)
	queue_redraw()

func _start_grab(hole: String) -> bool:
	if not first.is_empty():return false
	if selected_type=="wire" and _grab_wire_end(hole):return true
	var placing_part := selected_type=="place" or inventory_catalog.has(selected_type)
	for part in board.parts:
		var pins := Board.pins(part)
		if hole not in pins or (pins.size()!=2 and not placing_part):continue
		grabbed_part=str(part.id)
		grabbed_hole=hole
		grabbed_component.emit(str(part.type),str(board.get("instance_ids",{}).get(grabbed_part,"")))
		return true
	return _grab_wire_end(hole)

func _grab_wire_end(hole: String) -> bool:
	for index in range(board.wires.size()-1,-1,-1):
		var wire: Array=board.wires[index]
		if hole not in wire:continue
		hidden_wire_index=index
		grabbed_hole=hole
		first=str(wire[1] if wire[0]==hole else wire[0])
		return true
	return false

func cancel_grab() -> void:
	if grabbed_hole.is_empty():return
	var was_part := not grabbed_part.is_empty()
	hidden_wire_index=-1
	grabbed_hole=""
	grabbed_part=""
	first=""
	placement={}
	if was_part:grabbed_component.emit("","")
	queue_redraw()

func _finish_grab(hole: String) -> bool:
	if grabbed_hole.is_empty():return false
	if hole==grabbed_hole:
		cancel_grab()
		return true
	if hidden_wire_index>=0:
		var next := board.duplicate(true)
		var wire: Array=next.wires[hidden_wire_index]
		var old_key := Board.wire_key(wire)
		if hole in wire:
			feedback.emit("Choose a hole other than the fixed end.")
			return true
		wire[wire.find(grabbed_hole)]=hole
		var new_key := Board.wire_key(wire)
		for index in next.wires.size():
			if index!=hidden_wire_index and Board.wire_key(next.wires[index])==new_key:
				feedback.emit("Those holes already have a jumper.")
				return true
		var error := Board.validate(next,{},true)
		if not error.is_empty():
			feedback.emit(error)
			return true
		var colors: Dictionary=next.get("wire_colors",{})
		if colors.has(old_key):
			var color: Variant=colors[old_key]
			colors.erase(old_key)
			colors[new_key]=color
		_commit_grab(next)
	else:
		var trial := _grab_trial(hole)
		if not trial.error.is_empty():feedback.emit(trial.error)
		else:_commit_grab(trial.board)
	return true

func _commit_grab(candidate: Dictionary) -> void:
	commit()
	cancel_grab()
	board=candidate
	design_changed.emit(board)

func _grab_trial(hole: String) -> Dictionary:
	var next := board.duplicate(true)
	var index := -1
	for i in next.parts.size():
		if str(next.parts[i].id)==grabbed_part:
			index=i
			break
	if index<0:return {"error":"That component is no longer on the board."}
	var part: Dictionary=next.parts[index]
	var error := ""
	if Placement.uses_footprint(board,inventory_catalog,str(part.type)):
		var delta := Board.grid(hole)-Board.grid(grabbed_hole)
		var move := Placement.translated(board,[part.id],delta.x,delta.y)
		error=move.error
		if not move.has("board"):return {"error":error}
		next=move.board
		part=next.parts[index]
	else:
		if hole in Board.pins(part):
			return {"error":"Choose a hole other than the fixed end."}
		var end := "a" if str(part.a)==grabbed_hole else "b"
		part[end]=hole
		if part.has("pins"):
			part.pins[part.pins.find(grabbed_hole)]=hole
		error=Board.validate(next,{},true)
	if error.is_empty():
		var others: Array=next.parts.duplicate()
		others.remove_at(index)
		error=_body_overlap(part,others)
	return {"error":error,"board":next,"part":part}

func undo() -> void:
	cancel_grab()
	super.undo()

func redo() -> void:
	cancel_grab()
	super.redo()

func take_all() -> void:
	cancel_grab()
	first=""
	placement={}
	selected.clear()
	selected_wire=-1
	if board.parts.is_empty() and board.wires.is_empty():
		refresh_selection()
		queue_redraw()
		return
	commit()
	board.parts=[]
	board.wires=[]
	for key in ["wire_colors","instance_ids","controls","io_controls","programs"]:board.erase(key)
	design_changed.emit(board)
	refresh_selection()
	queue_redraw()

func _connect_wire(hole: String) -> void:
	for wire in board.wires:
		if first in wire and hole in wire:
			feedback.emit("Those holes already have a jumper.")
			return
	if board.wires.size() >= 96:
		feedback.emit("The board has reached its jumper limit.")
		return
	commit()
	var wire := [first,hole]
	board.wires.append(wire)
	var colors := {}
	for current in board.wires:
		var key := Board.wire_key(current)
		if board.get("wire_colors",{}).has(key):colors[key]=board.wire_colors[key]
	colors[Board.wire_key(wire)]=wire_color.to_html(false)
	board.wire_colors=colors
	first = ""
	design_changed.emit(board)

func _wire_at(point: Vector2) -> int:
	var closest := -1
	var distance := maxf(4,3.0*zoom)
	for index in range(board.wires.size()-1,-1,-1):
		var wire: Array = board.wires[index]
		var candidate := Geometry2D.get_closest_point_to_segment(point, at(wire[0]), at(wire[1])).distance_to(point)
		if candidate < distance:
			closest = index
			distance = candidate
	return closest

func _delete_wire_at(point: Vector2) -> bool:
	var index := _wire_at(point)
	if index < 0: return false
	commit()
	if board.has("wire_colors"):board.wire_colors.erase(Board.wire_key(board.wires[index]))
	board.wires.remove_at(index)
	selected_wire = -1
	design_changed.emit(board)
	return true

func _delete_component_at(point: Vector2, pin := "") -> bool:
	for index in range(board.parts.size() - 1, -1, -1):
		var part: Dictionary = board.parts[index]
		var hit := _body_at(part,point) if pin.is_empty() else pin in Board.pins(part)
		if not hit:
			continue
		selected_wire = -1
		selected = [part.id]
		delete_selected()
		return true
	return false

func _click_part(hole: String) -> void:
	if not Placement.uses_footprint(board, inventory_catalog, selected_type) and first.is_empty():
		if _pin_taken(hole):
			feedback.emit("Choose an unoccupied component hole.")
			return
		first = hole
		return
	var trial := _trial(hole)
	if not trial.get("error","").is_empty():
		feedback.emit(trial.error)
		return
	commit()
	trial.part.id = str(Time.get_ticks_usec())
	board = trial.board
	first = ""
	design_changed.emit(board)

func _pin_taken(hole: String) -> bool:
	for part in board.parts:
		if hole in Board.pins(part): return true
	return false

func _trial(hole: String) -> Dictionary:
	var trial := Placement.maker_candidate(board, inventory_catalog, stock_limits, unlimited, selected_type, first, hole, placement_turns)
	if trial.error.is_empty():
		trial.error = _body_overlap(trial.part, board.parts)
	return trial

func _body_overlap(part: Dictionary, others: Array) -> String:
	var body := _body_polygon(part)
	for other in others:
		if not Geometry2D.intersect_polygons(body, _body_polygon(other)).is_empty():
			return "The component body overlaps another part."
	return ""

func _body_polygon(part: Dictionary) -> PackedVector2Array:
	var definition: Dictionary = board.get("definitions", {}).get(part.type, {})
	var bounds := _body_bounds(part)
	if definition.has("footprint") or part.type in NATIVE_BOARDS:
		var footprint := pcb_rect(part, definition) if definition.has("footprint") else native_rect(part)
		bounds = {"center": footprint.get_center(), "size": footprint.size, "angle": 0.0}
	var half: Vector2 = bounds.size * .5
	var points := PackedVector2Array()
	for corner in [Vector2(-half.x, -half.y), Vector2(half.x, -half.y), half, Vector2(-half.x, half.y)]:
		points.append(bounds.center + corner.rotated(bounds.angle))
	return points

func _update_placement() -> void:
	placement = {}
	if hidden_wire_index>=0:return
	if not grabbed_part.is_empty():
		if not hovered.is_empty():placement=_grab_trial(hovered)
		return
	if hovered.is_empty() or not inventory_catalog.has(selected_type): return
	if not Placement.uses_footprint(board, inventory_catalog, selected_type) and first.is_empty(): return
	placement = _trial(hovered)

func rotate_or_preview() -> void:
	if inventory_catalog.has(selected_type):
		if not Placement.uses_footprint(board, inventory_catalog, selected_type):
			placement_turns = posmod(placement_turns+2,4)
		else:
			placement_turns = posmod(placement_turns+1,4)
		_update_placement()
		queue_redraw()
	elif selected_type == "select" and not selected.is_empty():
		var part: Dictionary
		for item in board.parts:
			if item.id == selected[0]:
				part = item
				break
		var other := board.duplicate(true)
		other.parts = other.parts.filter(func(item):return item.id != part.id)
		var turns := posmod(roundi(float(part.get("surface_rotation",0.0))/(PI*.5))+1,4)
		var paired := not Placement.uses_footprint(board, inventory_catalog, part.type)
		var trial: Dictionary
		if paired:
			trial = Placement.maker_candidate(other,inventory_catalog,stock_limits,unlimited,part.type,part.a,part.b,2)
		else:
			trial = Placement.maker_candidate(other,inventory_catalog,stock_limits,unlimited,part.type,"",part.a,turns)
		if trial.error.is_empty(): trial.error = _body_overlap(trial.part, other.parts)
		if not trial.get("error","").is_empty():
			feedback.emit(trial.error)
			return
		commit()
		part.merge({"a":trial.part.a,"b":trial.part.b,"surface_rotation":trial.part.get("surface_rotation",0.0)},true)
		if trial.part.has("pins"): part.pins = trial.part.pins
		design_changed.emit(board)
		queue_redraw()

func _body_at(part: Dictionary, point: Vector2) -> bool:
	for pin in Board.pins(part):
		if point.distance_to(at(pin)) <= 5 * zoom: return false
	var definition: Dictionary = board.get("definitions",{}).get(part.type,{})
	if definition.has("footprint"): return pcb_rect(part,definition).has_point(point)
	if part.type in NATIVE_BOARDS: return native_rect(part).has_point(point)
	var bounds := _body_bounds(part)
	if inventory_catalog.get(part.type, {}).get("kind") == "LED":
		return point.distance_to(bounds.center) <= _led_radius(bounds.size)
	return Rect2(-bounds.size*.5,bounds.size).has_point((point-bounds.center).rotated(-bounds.angle))

func _body_bounds(part: Dictionary) -> Dictionary:
	if part.get("solar_footprint",false):
		var rect := solar_rect(part)
		return {"center":rect.get_center(),"angle":0.0,"size":rect.size}
	var pins := Board.pins(part)
	var a := at(part.a)
	var b := at(part.b)
	if pins.size() == 2:
		return {"center":(a+b)*.5,"angle":(b-a).angle(),"size":Vector2(minf(24.0*zoom,a.distance_to(b)*.67),13.0*zoom)}
	var angle := float(part.get("surface_rotation",0.0))
	var extent := Rect2(at(pins[0]).rotated(-angle),Vector2.ZERO)
	for pin in pins: extent = extent.expand(at(pin).rotated(-angle))
	return {"center":extent.get_center().rotated(angle),"angle":angle,"size":Vector2(extent.size.x+13*zoom,maxf(14*zoom,extent.size.y-13*zoom))}

func _led_radius(body_size: Vector2) -> float:
	return minf(body_size.x * .34, body_size.y * .48)

func _draw_workspace_part(part: Dictionary, entry: Dictionary, font: Font) -> bool:
	if str(part.id)==grabbed_part and placement.has("part"):return true
	var definition: Dictionary = board.get("definitions",{}).get(part.type,{})
	if definition.has("footprint"):
		draw_pcb(part,definition,font)
		if part.id in selected: draw_rect(pcb_rect(part,definition).grow(3),Color("ffc66b"),false,2)
	elif part.type in NATIVE_BOARDS:
		draw_native_board(part, font)
	else:
		_draw_part(part,entry,false)
	return true

func _draw_part(part: Dictionary, entry: Dictionary, ghost: bool) -> void:
	var bounds := _body_bounds(part)
	var center: Vector2 = bounds.center
	var width: Vector2 = bounds.size
	var angle: float = bounds.angle
	var kind := str(entry.get("kind",""))
	var tint := Color.WHITE
	tint.a = .65 if ghost else 1.0
	var leads := Color("7b8b92",tint.a)
	if Board.pins(part).size() == 2 and not part.get("solar_footprint",false):
		draw_line(at(part.a),at(part.b),leads,maxf(1,1.7*zoom),true)
	else:
		for pin in Board.pins(part):
			var delta := (at(pin)-center).rotated(-angle)
			var edge := Vector2(clampf(delta.x,-width.x*.5,width.x*.5),clampf(delta.y,-width.y*.5,width.y*.5))
			draw_line(at(pin),center+edge.rotated(angle),leads,maxf(1.0,2*zoom),true)
	draw_set_transform(center,angle)
	var rect := Rect2(-width*.5,width)
	if part.type == "spi_display":
		draw_display("board/"+str(part.id), Vector2.ZERO, minf(width.x/136, width.y/48), get_theme_default_font(), tint.a)
		if part.id in selected: draw_rect(rect.grow(3),Color("ffc66b"),false,2)
		draw_set_transform(Vector2.ZERO)
		return
	if part.type == "seven_segment":
		_draw_digit("board/"+str(part.id), width, tint.a)
		if part.id in selected: draw_rect(rect.grow(3),Color("ffc66b"),false,2)
		draw_set_transform(Vector2.ZERO)
		return
	if part.id in selected and kind != "debug_meter": draw_rect(rect.grow(3),Color("ffc66b"),false,2)
	match kind:
		"toggle":
			var closed: bool=board.get("controls",{}).get("board/"+str(part.id),{}).get("pressed",part.get("pressed",false))
			var color := Color("82e3a8",tint.a) if closed else Color("ffc294",tint.a)
			draw_style_box(style(Color("334a52",tint.a)),rect)
			var tip := Vector2(width.x*(.36 if closed else -.36),-width.y*.27)
			draw_line(Vector2.ZERO,tip,color,maxf(2.0,2.2*zoom),true)
			draw_circle(tip,maxf(1.5,2*zoom),color)
			if selected_type=="interact" and not ghost:
				draw_set_transform(Vector2.ZERO)
				var label := "ON" if closed else "OFF"
				var font := get_theme_default_font()
				var font_size := maxi(9,roundi(9*zoom))
				var label_width := font.get_string_size(label,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size).x
				var baseline := center+Vector2(-label_width*.5,-maxf(width.x,width.y)*.5-3)
				draw_rect(Rect2(baseline+Vector2(-3,-font_size),Vector2(label_width+6,font_size+3)),Color("263a42"))
				draw_string(font,baseline,label,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size,color)
		"pot","variable_cap","variable_inductor","photodiode":
			draw_style_box(style(Color("334a52",tint.a)),rect)
			var radius := maxf(3*zoom,width.y*.52)
			draw_circle(Vector2.ZERO,radius,Color("6c8995",tint.a),true,-1,true)
			var setting := float(board.get("controls",{}).get("board/"+str(part.id),{}).get("setting",part.get("setting",.65 if kind=="photodiode" else .5)))
			var direction := Vector2.UP.rotated(lerpf(-PI*.75,PI*.75,setting))
			draw_line(direction*radius*.28,direction*radius*.86,Color("edf6fa",tint.a),maxf(1.0,1.7*zoom),true)
		"solar_panel":
			draw_solar_cells(rect,tint.a)
		"debug_meter","debug_source":
			var text := "SRC" if kind=="debug_source" else "DMM"
			if kind=="debug_meter" and bool(measurements.get("ok",false)) and not ghost:
				var values: Dictionary = measurements.get("v",{})
				var a := "board/"+Board.node(str(part.a),int(board.rows))
				var b := "board/"+Board.node(str(part.b),int(board.rows))
				var volts := float(values.get(a,0))-float(values.get(b,0))
				var mode := str(part.get("debug",{}).get("mode","Volts"))
				match mode:
					"Amps": text = Units.format_value(float(currents.get("board/"+str(part.id),0)), "A")
					"Ohms": text = Units.format_value(volts/.001, "Ω")
					_: text = Units.format_value(volts, "V")
			var font := get_theme_default_font()
			var font_size := maxi(8,roundi(10*zoom))
			var text_width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
			var padding := maxf(0, (text_width + 8 - width.x)*.5)
			rect = rect.grow_individual(padding, 0, padding, 0)
			draw_style_box(style(Color("1a4253",tint.a)),rect)
			if part.id in selected and kind == "debug_meter": draw_rect(rect.grow(3),Color("ffc66b"),false,2)
			draw_string(font,Vector2(-text_width*.5,4),text,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size,Color("c6ecdb",tint.a))
		"LED":
			var radius := _led_radius(width)
			var current := float(currents.get("board/"+str(part.id),0)) if not ghost else 0.0
			draw_led(Vector2.ZERO,radius,Color(entry.get("color","ff5149")),current,tint.a)
			draw_line(Vector2(radius*.63,-radius*.64),Vector2(radius*.63,radius*.64),Color("f9d8c9",tint.a),maxf(1,zoom),true)
			draw_arc(Vector2.ZERO,radius*.81,PI,TAU,16,Color("ffe1d0",tint.a*.7),1,true)
		"R":
			draw_style_box(style(Color("c7ad89",tint.a)),rect)
			var band_count := 0
			for band in Bands.bands(float(entry.get("value",0)),float(entry.get("resistance_tolerance",.05))):
				var x := width.x*(-.29+band_count*.15)
				draw_rect(Rect2(Vector2(x,-width.y*.47),Vector2(width.x*.08,width.y*.94)),Color(band.color,tint.a))
				band_count += 1
		"D":
			draw_style_box(style(Color("3b414c",tint.a)),rect)
			draw_rect(Rect2(Vector2(width.x*.23,-width.y*.49),Vector2(width.x*.11,width.y*.98)),Color("e6dfbd",tint.a))
		_:
			var icon_key := str(part.type)
			if not available_art.has(icon_key): available_art[icon_key] = Artwork.preview(entry)
			var color := Color("334a52",tint.a) if Board.pins(part).size() > 2 else Color("4a7888",tint.a)
			if part.get("pressed",false): color = Color("80d6a0",tint.a)
			draw_style_box(style(color),rect)
			if Board.pins(part).size() > 2:
				draw_circle(Vector2(-width.x*.35,-width.y*.23),maxf(1.0,zoom),Color("e1e8d8",tint.a))
			elif available_art[icon_key] != null:
				draw_texture_rect(available_art[icon_key],rect.grow(4*zoom),false,tint)
	draw_set_transform(Vector2.ZERO)
	var pins := Board.pins(part)
	if pins.size()==2:draw_polarity_labels(entry,at(pins[0]),at(pins[1]),get_theme_default_font(),tint.a)
	if kind=="portable_source" and not ghost and (part.id in selected or (selected_type=="interact" and center.distance_to(input_position)<20*zoom)):
		var control: Dictionary=board.get("controls",{}).get("board/"+str(part.id),{})
		var readout := Board.Sources.readout(entry,control)
		draw_string(get_theme_default_font(),center+Vector2(12,-12)*zoom,readout,HORIZONTAL_ALIGNMENT_LEFT,-1,maxi(11,roundi(12*zoom)),Color("263743"))

func _draw() -> void:
	super._draw()
	if (selected_type=="wire" or hidden_wire_index>=0) and not first.is_empty():
		var tint := Color("c99142")
		if hidden_wire_index>=0 and hidden_wire_index<board.wires.size():
			var key := Board.wire_key(board.wires[hidden_wire_index])
			tint=Color.from_string(str(board.get("wire_colors",{}).get(key,"e3ab5c")),Color("e3ab5c"))
		draw_line(at(first),at(hovered) if not hovered.is_empty() else input_position,tint,maxf(1.5,2.3*zoom),true)
	var preview := drag_preview if moving else placement
	if preview.has("part"):
		var part: Dictionary = preview.part
		var tint := Color("429c78") if preview.error.is_empty() else Color("de6e70")
		var definition: Dictionary = board.get("definitions",{}).get(part.type,{})
		if definition.has("footprint"):
			var footprint := pcb_rect(part,definition)
			if definition.has("surface_layout") and not footprint.has_area(): return
			if definition.get("package", "IC") == "IC":
				draw_ic_package(part, definition, get_theme_default_font(), .65)
			elif definition.has("surface_layout"):
				draw_pcb(part,definition,get_theme_default_font())
			else:
				draw_style_box(style(Color(str(definition.footprint.get("color", "334a52")), .58)), footprint)
				draw_string(get_theme_default_font(), footprint.position + Vector2(5,15), str(definition.get("name","Package")), HORIZONTAL_ALIGNMENT_LEFT, maxf(1, footprint.size.x-10), 12)
		elif part.type in NATIVE_BOARDS:
			draw_native_board(part,get_theme_default_font(),.65)
		else: _draw_part(part,inventory_catalog.get(part.type,{}),true)
		for pin in Board.pins(part): draw_arc(at(pin),7*zoom,0,TAU,16,tint,2,true)
	if not hovered.is_empty() and selected_type != "select":
		var valid := str(placement.get("error", "")).is_empty()
		draw_arc(at(hovered),8*zoom,0,TAU,16,Color("4b9e97") if valid else Color("cf535b"),2,true)

