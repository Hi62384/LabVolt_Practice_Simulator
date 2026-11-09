extends Control
const SolarBoard = preload("res://scripts/breadboard_model.gd")
const SurfaceLayout = preload("res://scripts/pcb_design/surface_layout.gd")
const SurfaceGeometry = preload("res://scripts/package_editor/package_geometry.gd")
signal design_changed(board: Dictionary)
signal io_command_requested(id: String,command: Dictionary)
signal manual_input_requested(action: Dictionary)
signal code_requested(id: String)
var board: Dictionary=preload("res://scripts/breadboard_model.gd").empty()
var attached_resize_ports: Array = []
var resize_error := ""
var read_only := false
var live_manual_inputs := false
var held_manual_input := ""
var selected_type := "wire":
	set(value):
		if selected_type=="interact" and value!="interact":release_io_capture()
		selected_type=value
var selected: Array=[]
var currents := {}
var device_states := {}
var analyzer_enabled := false
static var use_analyzer_shapes := false
var measurements := {}
var capture=preload("res://scripts/analyzer/capture.gd").new()
var voltage_overlay := true
var current_overlay := true
var timing_visible := false:
	set(value):
		timing_visible=value
		if not get_meta("workspace_embedded",false):custom_minimum_size.y=590 if value else 500
var first := ""
var history: Array=[]
var future: Array=[]
var zoom := 1.0
var pan := Vector2.ZERO
var dragging := false
var moving := false
var move_start := Vector2.ZERO
var clipboard: Array=[]
var hovered := ""
var hovered_wire := -1
var io_adapter: RefCounted
const PCB=preload("res://scripts/pcb_design/design.gd")
var hidden_wire_index := -1
var board_surface: Node2D
var surface_layout := Vector2i.ZERO
var surface_nodes := {}
var surface_labels := true
const BoardModel = preload("res://scripts/breadboard_model.gd")
const LETTERS = BoardModel.BASE_HOLES+BoardModel.LOWER_HOLES+BoardModel.OUTER_RAILS
func hole_letters() -> String:
	return BoardModel.hole_letters(board)

func board_extent() -> Vector2:
	return Vector2((int(board.rows)-1)*23+65,780 if board.get("expanded",false) else 415)
func _ready() -> void:
	custom_minimum_size=Vector2(760,500);mouse_filter=MOUSE_FILTER_STOP;clip_contents=true
	io_adapter=preload("res://scripts/package_editor/io_surface_adapter.gd").new();io_adapter.setup(self)
	io_adapter.command_requested.connect(func(id,command):io_command_requested.emit(id,command))
func _process(_delta: float) -> void:
	refresh_io_surfaces()
func refresh_io_surfaces() -> void:
	if io_adapter==null or io_adapter.surface_script==null:return
	io_adapter.sync(surface_devices(),device_states,preload("res://scripts/breadboard_model.gd").io_inputs(board),selected_type=="interact" and is_visible_in_tree(),zoom)
func release_io_capture() -> void:
	_release_manual_input()
	if io_adapter!=null:io_adapter.release_all()

func _release_manual_input() -> void:
	if held_manual_input.is_empty():return
	var id := held_manual_input
	held_manual_input=""
	_apply_manual_input(id,"button",{"pressed":false,"hold":true})

func _apply_manual_input(id: String, type: String, action: Dictionary) -> void:
	action.merge({"op":"input","id":id})
	if live_manual_inputs:
		manual_input_requested.emit(action)
		return
	if not board.has("controls"):board.controls={}
	var control: Dictionary=board.controls.get(id,{})
	match type:
		"button":control.pressed=action.pressed
		"toggle":control.pressed=not control.get("pressed",false)
		"battery_adjustable","battery_generator","battery_generator_adjustable":
			for device in BoardModel.devices(board):
				if str(device.id)!=id:continue
				var source := preload("res://scripts/electronics_catalog.gd").simulation_entry(str(device.part.type))
				BoardModel.Sources.adjust(source,control,action)
				break
		_:
			var initial := .65 if type in ["photodiode","solar_panel"] else .5
			control.setting=clampf(float(control.get("setting",initial))+(-.05 if action.reverse else .05),0,1)
	board.controls[id]=control
	for part in board.parts:
		if "board/"+str(part.id)==id:part.merge(control,true)
	design_changed.emit(board)
	queue_redraw()

func _operate_manual_input(event: InputEventMouseButton, toggle_body_only := false) -> bool:
	if event.button_index==MOUSE_BUTTON_LEFT and not event.pressed and not held_manual_input.is_empty():
		_release_manual_input()
		return true
	if not event.pressed or event.button_index not in [MOUSE_BUTTON_LEFT,MOUSE_BUTTON_RIGHT,MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:return false
	var reverse := event.button_index in [MOUSE_BUTTON_RIGHT,MOUSE_BUTTON_WHEEL_DOWN]
	for control in exposed_controls():
		var type := BoardModel.manual_input_type(str(control.type))
		if type.is_empty():continue
		if toggle_body_only and type!="toggle":continue
		var radius: float=8*zoom if toggle_body_only else control.radius
		if control.center.distance_to(event.position)>radius:continue
		if type in ["button","toggle"]:
			if event.button_index!=MOUSE_BUTTON_LEFT:continue
			if type=="button":held_manual_input=str(control.id)
			_apply_manual_input(str(control.id),type,{"pressed":true,"hold":type=="button"})
		elif type in BoardModel.Sources.CONTROLS:
			var adjustment := "wave" if event.button_index==MOUSE_BUTTON_LEFT and type!="battery_adjustable" else "frequency" if event.shift_pressed and type=="battery_generator_adjustable" else "voltage"
			if type=="battery_generator" and adjustment!="wave":continue
			_apply_manual_input(str(control.id),type,{"source_adjust":adjustment,"reverse":reverse})
		else:
			_apply_manual_input(str(control.id),type,{"reverse":reverse})
		return true
	return false
func has_pending_io() -> bool:
	return io_adapter!=null and io_adapter.pending()
func acknowledge_io(id: String,input: Dictionary) -> void:
	if io_adapter!=null:io_adapter.acknowledge(id,input)
func _notification(what: int) -> void:
	if what==NOTIFICATION_WM_WINDOW_FOCUS_OUT:release_io_capture()
func at(hole: String) -> Vector2:
	if board.get("standalone",false) and board.parts.size()==1:
		var pins: Array=preload("res://scripts/breadboard_model.gd").pins(board.parts[0]);var index := pins.find(hole)
		if index>=0:
			var definition: Dictionary=board.definitions[board.parts[0].type]
			if PCB.active(definition):return PCB.map_point(definition,definition.pcb_design.pads[PCB.external_id(definition.pins[index],index)].position,pcb_rect(board.parts[0],definition))
			if definition.has("surface_layout"):
				var outline := pcb_rect(board.parts[0],definition)
				var point := Vector2(SurfaceGeometry.position(definition.pins[index]))
				return outline.position+outline.size*(point+Vector2(.5,.5))/Vector2(definition.footprint.width,definition.footprint.height)
			if SurfaceGeometry.explicit_pins(definition):
				var p := preload("res://scripts/package_editor/package_geometry.gd").position(definition.pins[index])
				return Vector2(32,32)+Vector2(p)*Vector2((size.x-64)/maxf(1,int(definition.footprint.width)-1),(size.y-150)/maxf(1,int(definition.footprint.height)-1))
			var half := ceili(pins.size()/2.0);var col := index%half
			return Vector2(60+(size.x-120)*(col+.5)/half,32 if index<half else size.y-32)
	var col := BoardModel.grid(hole).y
	return _grid_point(int(hole.substr(1))-1,col)*zoom+pan

func solar_rect(part: Dictionary) -> Rect2:
	var cells := SolarBoard.solar_body(part)
	var first := _grid_point(cells.position.x, cells.position.y)
	var last := _grid_point(cells.end.x - 1, cells.end.y - 1)
	var anchor := at(part.a) + (first - _grid_point(SolarBoard.grid(part.a).x, SolarBoard.grid(part.a).y)) * zoom
	return Rect2(anchor, (last - first) * zoom).grow(11.5 * zoom)

func draw_solar_cells(rect: Rect2, opacity: float) -> void:
	draw_rect(rect, Color("acbfce", opacity))
	var cell_size := rect.size * .5
	for y in 2:
		for x in 2:
			var cell := Rect2(rect.position + Vector2(x,y) * cell_size, cell_size).grow(-zoom)
			draw_rect(cell, Color("284c7a", opacity))
			for stripe in [0.25, 0.5, 0.75]:
				var left := cell.position + Vector2(zoom,cell.size.y * stripe)
				draw_line(left,left+Vector2(cell.size.x-2*zoom,0),Color("79a4c4",opacity),maxf(1,zoom*.5),true)

func _grid_point(row: int, col: int) -> Vector2:
	var bottom := 24 if board.get("expanded",false) else 12
	if col>=bottom:
		return Vector2(35+row*23,375+(col-bottom)*23+(365 if bottom==24 else 0))
	var local := posmod(col,12)
	return Vector2(35+row*23,45+local*23+(24 if local>=7 else 0)+(15 if local>=2 else 0)+(365 if col>=12 else 0))

func hole_at(point: Vector2) -> String:
	if board.get("standalone",false):
		for row in range(1,int(board.rows)+1):
			for col in hole_letters():
				var name := col+str(row)
				if at(name).distance_to(point)<9*zoom:return name
		return ""
	var local := (point-pan)/zoom
	var row := roundi((local.x-35)/23)
	if row<0 or row>=int(board.rows):return ""
	var letters := hole_letters()
	for col in letters.length():
		if _grid_point(row,col).distance_squared_to(local)<81:
			return letters[col]+str(row+1)
	return ""

func nearest_hole(point: Vector2) -> String:
	var local := (point-pan)/zoom
	var row := clampi(roundi((local.x-35)/23),0,int(board.rows)-1)
	var letters := hole_letters()
	var nearest := 0
	var distance := INF
	for col in letters.length():
		var candidate := absf(_grid_point(row,col).y-local.y)
		if candidate<distance:
			nearest=col
			distance=candidate
	return letters[nearest]+str(row+1)

func enable_cached_board() -> void:
	var background := ColorRect.new()
	background.color=Color("1b2d39")
	background.mouse_filter=Control.MOUSE_FILTER_IGNORE
	background.show_behind_parent=true
	add_child(background)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	board_surface=Node2D.new()
	board_surface.show_behind_parent=true
	add_child(board_surface)
	board_surface.draw.connect(_draw_cached_surface)

func _draw_cached_surface() -> void:
	var rows := surface_layout.x
	var columns := surface_layout.y
	if rows<=0:return
	var extent := board_extent()
	var origin := Vector2(8,12)
	board_surface.draw_style_box(style(Color("d9ded8")),Rect2(origin+Vector2(4,5),extent))
	board_surface.draw_style_box(style(Color("f0eee4")),Rect2(origin,extent))
	var trench_y := (_grid_point(0,6).y+_grid_point(0,7).y)*.5
	for y in ([trench_y,trench_y+365] if board.get("expanded",false) else [trench_y]):
		board_surface.draw_rect(Rect2(20,y-8,extent.x-24,16),Color("a6afa9"))
	var letters := hole_letters()
	for col in columns:
		if letters[col] not in BoardModel.RAIL_HOLES:continue
		for start in [0,rows/2]:
			board_surface.draw_line(_grid_point(start,col)+Vector2(0,-8),
				_grid_point(start+rows/2-1,col)+Vector2(0,-8),Color("bd594c") if letters[col] in "PWY" else Color("477fa4"),2,true)
	var font := ThemeDB.fallback_font
	for col in columns:
		var color := _hole_color(letters[col])
		var marker := _hole_texture(color)
		for row in rows:
			board_surface.draw_texture(marker,_grid_point(row,col)-Vector2(4,4))
		if surface_labels:
			var letter: String=letters[col]
			var width := font.get_string_size(letter,HORIZONTAL_ALIGNMENT_LEFT,-1,12).x
			var baseline := (font.get_ascent(12)-font.get_descent(12))*.5
			board_surface.draw_string(font,_grid_point(0,col)+Vector2(-17-width*.5,baseline),letter,HORIZONTAL_ALIGNMENT_LEFT,-1,12,Color("33454c"))
	if surface_labels:
		for row in range(1,rows+1):
			if row!=1 and row%5!=0:continue
			var label := str(row)
			var width := font.get_string_size(label,HORIZONTAL_ALIGNMENT_LEFT,-1,12).x
			board_surface.draw_string(font,_grid_point(row-1,0)+Vector2(-width*.5,-14),label,HORIZONTAL_ALIGNMENT_LEFT,-1,12,Color("33454c"))

var hole_textures := {}
func _hole_color(letter: String) -> Color:
	if letter in "PWY":return Color("cb766b")
	if letter in "NXZ":return Color("689cbe")
	return Color("b4bab5")

func _hole_texture(color: Color) -> Texture2D:
	if not hole_textures.has(color):
		var pixels := Image.create_empty(8,8,false,Image.FORMAT_RGBA8)
		for y in 8:
			for x in 8:
				var distance := Vector2(x+.5,y+.5).distance_to(Vector2(4,4))
				if distance<4.2:
					pixels.set_pixel(x,y,Color("14202b") if distance<2 else color)
		hole_textures[color]=ImageTexture.create_from_image(pixels)
	return hole_textures[color]

func _update_cached_surface() -> void:
	board_surface.position=pan
	board_surface.scale=Vector2.ONE*zoom
	var layout := Vector2i(int(board.rows),hole_letters().length())
	var labels := roundi(12*zoom)>=7
	if layout!=surface_layout or labels!=surface_labels:
		surface_layout=layout
		surface_labels=labels
		surface_nodes.clear()
		var letters := hole_letters()
		for row in layout.x:
			for col in layout.y:
				var hole: String=letters[col]+str(row+1)
				var node := BoardModel.node(hole,layout.x)
				if not surface_nodes.has(node):surface_nodes[node]=[]
				surface_nodes[node].append(hole)
		board_surface.queue_redraw()
	var active := first if not first.is_empty() else hovered
	if not active.is_empty():
		var node := BoardModel.node(active,layout.x)
		for hole in surface_nodes.get(node,[]):
			draw_arc(at(hole),6*zoom,0,TAU,12,Color("53a994"),maxf(1,zoom),true)
	if not first.is_empty():draw_arc(at(first),8*zoom,0,TAU,20,Color("ffdb75"),2,true)

func commit() -> void:
	history.append(board.duplicate(true));if history.size()>40:history.pop_front()
	future.clear()
func undo() -> void:
	if history.is_empty():return
	future.append(board.duplicate(true));board=history.pop_back();first="";design_changed.emit(board);queue_redraw()
func redo() -> void:
	if future.is_empty():return
	history.append(board.duplicate(true));board=future.pop_back();design_changed.emit(board);queue_redraw()
func _zoom_at(pointer: Vector2, factor: float, minimum: float, maximum: float) -> void:
	var anchor := (pointer-pan)/zoom
	zoom=clampf(zoom*factor,minimum,maximum)
	pan=pointer-anchor*zoom
	queue_redraw()

func _gui_input(event: InputEvent) -> void:
	if selected_type in ["probe+","probe-"] and not analyzer_enabled:return
	if analyzer_enabled and event is InputEventMouseButton and event.pressed and event.button_index==MOUSE_BUTTON_LEFT and selected_type in ["probe+","probe-"]:
		var hole := hole_at(event.position)
		if hole!="":
			var n := "board/"+preload("res://scripts/breadboard_model.gd").node(hole,int(board.rows))
			capture.probes(n if selected_type=="probe+" else capture.positive,n if selected_type=="probe-" else capture.negative)
			queue_redraw()
		accept_event();return
	if selected_type=="interact" and event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT and event.pressed:
		for control in exposed_controls():
			if control.type in ["lv_mcu","native_uno","native_pico","native_nano"] and control.center.distance_to(event.position)<=control.radius:
				code_requested.emit(str(control.id));accept_event();return
	if read_only:
		if event is InputEventMouseMotion:hovered=hole_at(event.position);queue_redraw()
		return
	if event is InputEventMouseButton and selected_type=="interact":
		if _operate_manual_input(event):accept_event();return
	if event is InputEventMouseButton:
		if event.button_index==MOUSE_BUTTON_MIDDLE:dragging=event.pressed
		if event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:
			_zoom_at(event.position,1.1 if event.button_index==MOUSE_BUTTON_WHEEL_UP else 1.0/1.1,.6,2)
			accept_event()
			return
		if event.pressed and event.button_index==MOUSE_BUTTON_RIGHT:first="";queue_redraw()
		if event.button_index==MOUSE_BUTTON_LEFT:
			if not event.pressed and moving:
				moving=false
				var shift: Vector2 = (event.position-move_start)/(23*zoom)
				if shift.length()>.5:transform_selected(roundi(shift.x),roundi(shift.y))
				return
			var hole := hole_at(event.position)
			if selected_type=="select" and event.pressed:
				for part in board.parts:
					if (native_rect(part).has_point(event.position) if part.type in ["native_uno","native_pico","native_nano"] else (at(part.a)+at(part.b)).distance_to(event.position*2)<40*zoom):
						if event.shift_pressed:
							if selected.has(part.id):selected.erase(part.id)
							else:selected.append(part.id)
						else:
							if not selected.has(part.id):selected=[part.id]
							moving=true;move_start=event.position
						queue_redraw();return
				if not event.shift_pressed:selected.clear();queue_redraw()
			elif selected_type=="interact":return
			elif event.pressed and hole!="":
				if selected_type=="remove":
					commit();board.parts=board.parts.filter(func(p):return hole not in preload("res://scripts/breadboard_model.gd").pins(p));board.wires=board.wires.filter(func(w):return hole not in w);design_changed.emit(board)
				elif first=="":first=hole
				elif first!=hole:
					commit()
					if selected_type=="wire":board.wires.append([first,hole])
					else:
						var part := {"id":str(Time.get_ticks_usec()),"type":selected_type,"a":first,"b":hole,"pressed":false}
						var definition: Dictionary=board.get("definitions",{}).get(selected_type,{})
						if SurfaceGeometry.explicit_pins(definition):
							part.pins=preload("res://scripts/package_editor/package_geometry.gd").holes_at(definition,first,int(board.rows))
							if part.pins.is_empty():first="";return
							part.a=part.pins[0];part.b=part.pins[-1]
						elif preload("res://scripts/breadboard_model.gd").catalog(board)[selected_type].pins.size()>2:
							part.pins=[]
							var count: int=preload("res://scripts/breadboard_model.gd").catalog(board)[selected_type].pins.size()
							for pin in count:
								var anchor: String=first if pin<(count+1)/2 else hole
								part.pins.append(anchor.left(1)+str(int(anchor.substr(1))+pin%((count+1)/2)))
						board.parts.append(part)
					first="";design_changed.emit(board)
				queue_redraw()
	elif event is InputEventMouseMotion:
		if dragging:pan+=event.relative
		hovered=hole_at(event.position);queue_redraw()
		hovered_wire=-1
		if hovered=="":
			for index in board.wires.size():
				var wire: Array=board.wires[index]
				if Geometry2D.get_closest_point_to_segment(event.position,at(wire[0]),at(wire[1])).distance_to(event.position)<6*zoom:hovered_wire=index;break
var physical_surface := false
var physical_pcb_surface := false

func _draw() -> void:
	if not physical_surface and (board_surface==null or board.get("standalone",false)):draw_rect(Rect2(Vector2.ZERO,size),Color("1b2d39"))
	if board_surface!=null:board_surface.visible=not board.get("standalone",false)
	var font := ThemeDB.fallback_font
	if board.get("standalone",false) and board.parts.size()==1:
		var part: Dictionary=board.parts[0];var definition: Dictionary=board.definitions[part.type]
		draw_pcb(part,definition,font)
		if physical_pcb_surface:return
		for i in definition.pins.size():
			var point := at(part.pins[i])
			var offset := Vector2(-120,16) if point.x>size.x*.5 else Vector2(4,16)
			draw_string(font,point+offset,"X%d · %s"%[i+1,definition.pins[i].name],HORIZONTAL_ALIGNMENT_LEFT,116,12,Color("f1e6bc"))
		if analyzer_enabled:draw_analyzer(font)
		return
	if board_surface!=null:
		_update_cached_surface()
	else:
		var extent := board_extent()*zoom
		var origin := Vector2(8,12)*zoom+pan
		if not physical_surface:draw_style_box(style(Color("d9ded8")),Rect2(origin+Vector2(4,5)*zoom,extent))
		draw_style_box(style(Color("f0eee4")),Rect2(origin,extent))
		var trench_y := (at("E1").y+at("F1").y)*.5
		draw_rect(Rect2(Vector2(origin.x+12*zoom,trench_y-8*zoom),Vector2(extent.x-24*zoom,16*zoom)),Color("a6afa9"))
		if board.get("expanded",false):
			draw_rect(Rect2(Vector2(origin.x+12*zoom,trench_y+365*zoom),Vector2(extent.x-24*zoom,16*zoom)),Color("a6afa9"))
		for rail in BoardModel.RAIL_HOLES:
			if rail not in hole_letters():continue
			for half in 2:
				var start := 1 if half==0 else int(board.rows)/2+1
				var finish := int(board.rows)/2 if half==0 else int(board.rows)
				draw_line(at(rail+str(start))+Vector2(0,-8)*zoom,at(rail+str(finish))+Vector2(0,-8)*zoom,Color("bd594c") if rail in "PWY" else Color("477fa4"),2*zoom,true)
		var active_hole := first if first!="" else hovered
		var active_node := preload("res://scripts/breadboard_model.gd").node(active_hole,int(board.rows))
		var label_size := roundi(12*zoom)
		var label_color := Color("33454c")
		for row in range(1,int(board.rows)+1):
			for col in hole_letters():
				var hole := col+str(row);var point := at(hole)
				if active_node!="" and preload("res://scripts/breadboard_model.gd").node(hole,int(board.rows))==active_node:draw_circle(point,8*zoom,Color("8dd6bf"))
				var color := _hole_color(col)
				draw_circle(point,4*zoom,color);draw_circle(point,2*zoom,Color("14202b"))
				if hole==first:draw_arc(point,8*zoom,0,TAU,20,Color("ffdb75"),2,true)
			if label_size>=7 and (row%5==0 or row==1):
				var number := str(row)
				var width := font.get_string_size(number,HORIZONTAL_ALIGNMENT_LEFT,-1,label_size).x
				var position := at("P"+number)+Vector2(-width*.5,-14*zoom)
				draw_string(font,position,number,HORIZONTAL_ALIGNMENT_LEFT,-1,label_size,label_color)
		if label_size>=7:
			var baseline := (font.get_ascent(label_size)-font.get_descent(label_size))*.5
			for col in hole_letters():
				var width := font.get_string_size(col,HORIZONTAL_ALIGNMENT_LEFT,-1,label_size).x
				var position := at(col+"1")+Vector2(-17*zoom-width*.5,baseline)
				draw_string(font,position,col,HORIZONTAL_ALIGNMENT_LEFT,-1,label_size,label_color)
	for index in board.wires.size():
		if index==hidden_wire_index:continue
		var wire: Array=board.wires[index]
		var key := preload("res://scripts/breadboard_model.gd").wire_key(wire)
		draw_line(at(wire[0]),at(wire[1]),Color.from_string(str(board.get("wire_colors",{}).get(key,"e3ab5c")),Color("e3ab5c")),3*zoom,true)
	var catalog := {} if board.parts.is_empty() else BoardModel.catalog(board)
	for part in board.parts:
		if _draw_workspace_part(part, catalog.get(part.type, {}), font): continue
		if part.type in ["native_uno","native_pico","native_nano"]:
			draw_native_board(part,font);continue
		var a := at(part.a);var b := at(part.b);var mid := (a+b)*.5
		draw_line(a,b,Color("b1bcc4"),2*zoom,true)
		for pin in part.get("pins",[]):draw_line(at(pin),mid,Color("b1bcc4"),2*zoom,true)
		var color := Color("72b8c1") if part.type.begins_with("c") else Color("c1a787")
		if selected.has(part.id):draw_rect(Rect2(mid-Vector2(16,11)*zoom,Vector2(32,22)*zoom),Color("ffdc82"),false,2)
		if part.get("pressed",false):color=Color("83e4a8")
		if catalog.get(part.type,{}).get("kind","")=="LED":
			draw_led(mid,9*zoom,Color(catalog[part.type].get("color","ff5149")),float(currents.get("board/"+str(part.id),0)))
			draw_arc(mid,9*zoom,PI,TAU,16,Color("f7b4a1"),2*zoom,true)
		elif str(part.type).begins_with("ic:") and board.definitions.get(part.type,{}).has("footprint"):
			draw_pcb(part,board.definitions[part.type],font)
		elif part.type.begins_with("ic:") or catalog.get(part.type,{}).get("kind","")=="logic":
			draw_style_box(style(Color("303b40")),Rect2(mid-Vector2(18,11)*zoom,Vector2(36,22)*zoom));draw_circle(mid-Vector2(12,5)*zoom,2*zoom,Color("d0d5cf"))
		elif part.type=="spi_display":
			draw_display("board/"+str(part.id),mid,zoom,font)
		elif part.type=="lv_mcu":
			draw_style_box(style(Color("247866")),Rect2(mid-Vector2(22,15)*zoom,Vector2(44,30)*zoom))
			draw_rect(Rect2(mid-Vector2(7,7)*zoom,Vector2(14,14)*zoom),Color("253037"))
			var labels: Array=catalog[part.type].pins
			for index in part.get("pins",[]).size():draw_string(font,at(part.pins[index])+Vector2(4,-4)*zoom,str(labels[index]),HORIZONTAL_ALIGNMENT_LEFT,-1,10,Color("244036"))
		elif part.type in ["pot10k","variable_cap","variable_inductor","photodiode"]:
			draw_circle(mid,12*zoom,Color("426c8d"))
			var angle := lerpf(PI*.75,PI*2.25,float(part.get("setting",.5)))
			draw_line(mid,mid+Vector2(cos(angle),sin(angle))*10*zoom,Color.WHITE,2*zoom,true)
		elif part.type=="solar_panel":
			var panel := Rect2(mid-Vector2(29,20)*zoom,Vector2(58,40)*zoom)
			if part.get("solar_footprint",false):
				panel = solar_rect(part)
				for pin in SolarBoard.pins(part):
					var point := at(pin)
					draw_line(point,point.clamp(panel.position,panel.end),Color("7b8b92"),maxf(1,2*zoom),true)
			draw_solar_cells(panel,1.0)
		elif part.type=="seven_segment":
			draw_style_box(style(Color("20272a")),Rect2(mid-Vector2(15,24)*zoom,Vector2(30,48)*zoom))
			var segments := [[Vector2(-8,-18),Vector2(8,-18)],[Vector2(9,-16),Vector2(9,-2)],[Vector2(9,2),Vector2(9,16)],[Vector2(-8,18),Vector2(8,18)],[Vector2(-9,2),Vector2(-9,16)],[Vector2(-9,-16),Vector2(-9,-2)],[Vector2(-8,0),Vector2(8,0)]]
			for index in 7:
				var amps := maxf(0,float(currents.get("board/"+str(part.id)+"/"+str(index),0)))
				draw_line(mid+segments[index][0]*zoom,mid+segments[index][1]*zoom,Color("4a2527").lerp(Color("ff5149"),clampf(amps/.01,0,1)),3*zoom,true)
			draw_circle(mid+Vector2(12,20)*zoom,2*zoom,Color("ff5149") if float(currents.get("board/"+str(part.id)+"/7",0))>.001 else Color("4a2527"))
		else:
			draw_style_box(style(color),Rect2(mid-Vector2(12,7)*zoom,Vector2(24,14)*zoom))
			if part.type.begins_with("r"):
				for stripe in [-6,0,6]:draw_line(mid+Vector2(stripe,-6)*zoom,mid+Vector2(stripe,6)*zoom,Color("694f36"),2*zoom,true)
			elif part.type=="diode":draw_line(mid+Vector2(7,-6)*zoom,mid+Vector2(7,6)*zoom,Color("e7e4d4"),3*zoom,true)
		var entry: Dictionary = catalog.get(part.type,{})
		draw_string(font,mid+Vector2(-15,-12)*zoom,entry.get("name",part.type),HORIZONTAL_ALIGNMENT_LEFT,-1,12,Color("263e46"))
		var pins := BoardModel.pins(part)
		if pins.size()==2:draw_polarity_labels(entry,at(pins[0]),at(pins[1]),font)
	if analyzer_enabled:draw_analyzer(font)
func _draw_workspace_part(_part: Dictionary, _definition: Dictionary, _font: Font) -> bool:
	return false

func draw_analyzer(font: Font) -> void:
	const Analysis=preload("res://scripts/analyzer/capture.gd")
	const Board=preload("res://scripts/breadboard_model.gd")
	var focus := hovered
	if focus=="" and hovered_wire>=0 and hovered_wire<board.wires.size():focus=str(board.wires[hovered_wire][0])
	if focus=="" and selected.size()==1:
		for part in board.parts:
			if selected.has(part.id):focus=str(part.a)
	var traced := Analysis.connected_nodes(board,Board.node(focus,int(board.rows))) if focus!="" else {}
	for wire in board.wires:
		if traced.has(Board.node(str(wire[0]),int(board.rows))):draw_line(at(wire[0]),at(wire[1]),Color("fff186"),6*zoom,true)
	for part in board.parts:
		var id := "board/"+str(part.id)
		if current_overlay and Board.pins(part).size()==2 and measurements.get("i",{}).has(id):
			var amps := float(measurements.i[id]);var a := at(part.a);var b := at(part.b)
			if absf(amps)>1e-9:
				var direction := (b-a).normalized()*signf(amps);var tip := (a+b)*.5+direction*14*zoom
				draw_line(tip-direction*22*zoom,tip,Color("55e9d8"),2,true)
				for side in [-1,1]:draw_line(tip,tip-direction.rotated(side*.55)*9*zoom,Color("55e9d8"),2,true)
			if selected.has(part.id):draw_string(font,(a+b)*.5+Vector2(0,25),"%.4f A"%amps,HORIZONTAL_ALIGNMENT_LEFT,-1,12,Color("123940"))
	if voltage_overlay and not board.get("standalone",false):
		for row in range(1,int(board.rows)+1):
			for col in hole_letters():
				var hole := col+str(row);var n := "board/"+Board.node(hole,int(board.rows))
				var measured := Analysis.differential(measurements,n,capture.negative)
				if measured.ok:
					var color := Color("f38970") if float(measured.value)>.05 else Color("72aaf3") if float(measured.value)<-.05 else Color("79d5ac")
					var point := at(hole)
					if use_analyzer_shapes and absf(float(measured.value)) > .05:
						var radius := 6 * zoom
						var sign_mark := Color("ffe071") if measured.value > 0 else Color("83ccff")
						draw_line(point - Vector2(radius, 0), point + Vector2(radius, 0), sign_mark, 2.5, true)
						if measured.value > 0:
							draw_line(point - Vector2(0, radius), point + Vector2(0, radius), sign_mark, 2.5, true)
					else:
						draw_arc(point,6*zoom,0,TAU,12,Color.WHITE if use_analyzer_shapes else color,2,true)
	var text := "Voltage relative to − probe. + positive, − negative, ○ near zero." if use_analyzer_shapes else "Hover nodes · select parts · probe +/− holes. Colors: + red / − blue / near-zero green, relative to − probe."
	if hovered!="":
		var measured := Analysis.differential(measurements,"board/"+Board.node(hovered,int(board.rows)),capture.negative)
		text=hovered+": "+("%.5f V relative to %s"%[measured.value,capture.negative] if measured.ok else measured.reason)
	elif hovered_wire>=0 and hovered_wire<board.wires.size():
		var wire: Array=board.wires[hovered_wire]
		var measured := Analysis.differential(measurements,"board/"+Board.node(str(wire[0]),int(board.rows)),capture.negative)
		text="Jumper %s ↔ %s: "%[wire[0],wire[1]]+("%.5f V relative to %s; ideal wire current is not resolved"%[measured.value,capture.negative] if measured.ok else measured.reason)
	elif selected.size()==1:
		var id := "board/"+str(selected[0])
		if measurements.get("i",{}).has(id) and measurements.get("drop",{}).has(id):
			var amps := float(measurements.i[id]);var volts := float(measurements.drop[id])
			text="Instantaneous A → B: %.5f A | ΔV %.5f V | absorbed power %.5f W"%[amps,volts,amps*volts]
			if absf(amps)>1e-9:text+=" | V/I %.5f Ω (operating point)"%(volts/amps)
		else:text="No aggregate branch reading for this multi-pin device; probe its pins."
	var messages := Analysis.diagnostics(board,measurements,device_states,selected)
	var panel_height := 174 if timing_visible else 84
	var top := size.y-panel_height
	draw_style_box(style(Color("10222c")),Rect2(Vector2(8,top),Vector2(size.x-16,panel_height-4)))
	draw_string(font,Vector2(16,top+18),text,HORIZONTAL_ALIGNMENT_LEFT,size.x-32,13,Color("b5efda"))
	draw_string(font,Vector2(16,top+37)," · ".join(messages) if not messages.is_empty() else "No selected-path diagnostic. Absence of a warning does not certify the circuit.",HORIZONTAL_ALIGNMENT_LEFT,size.x-32,12,Color("ffd997"))
	var measured := Analysis.differential(measurements,capture.positive,capture.negative)
	var probe_text := "+ %s   − %s: "%[capture.positive,capture.negative]
	probe_text+="%.5f V · threshold %.3f V: %s (voltage comparison; drive impedance unknown)"%[measured.value,capture.threshold,"HIGH" if float(measured.value)>=capture.threshold else "LOW"] if measured.ok else measured.reason
	draw_string(font,Vector2(16,top+56),probe_text,HORIZONTAL_ALIGNMENT_LEFT,size.x-32,12,Color("cbddee"))
	if timing_visible:draw_capture(font,Rect2(16,top+64,size.x-32,72))

func draw_capture(font: Font,rect: Rect2) -> void:
	var stats: Dictionary=capture.statistics()
	draw_rect(rect,Color("172f3c"))
	if not stats.has("min"):
		draw_string(font,rect.position+Vector2(6,22),"Select both probes. Waiting for two valid samples; floating/missing data leaves a gap.",HORIZONTAL_ALIGNMENT_LEFT,rect.size.x-12,12,Color("b5efda"));return
	var low := minf(float(stats.min),0);var high := maxf(float(stats.max),capture.threshold)
	if high-low<.1:high=low+.1
	var points := PackedVector2Array()
	for sample in capture.samples:
		points.append(rect.position+Vector2((float(sample.time)-float(capture.samples[0].time))/float(stats.duration)*rect.size.x,rect.size.y-4-(float(sample.value)-low)/(high-low)*(rect.size.y-8)))
	if points.size()>1:draw_polyline(points,Color("6fe8c6"),1.5,true)
	var info := "%.4f…%.4f V · %.4f s · max sample gap %.4f s · "%[stats.min,stats.max,stats.duration,stats.max_dt]
	info+="~%.4f Hz · PWM/high duty ~%.1f%%"%[stats.frequency,float(stats.duty)*100] if stats.timing else "Timing unresolved: need ≥2 cycles and ≥8 samples/period"
	draw_string(font,Vector2(rect.position.x,rect.end.y+17),info,HORIZONTAL_ALIGNMENT_LEFT,rect.size.x,12,Color("b5efda"))

func accept_measurements(result: Dictionary) -> void:
	measurements=result
	if analyzer_enabled:capture.ingest(result)

func inspection_text() -> String:
	if not analyzer_enabled:return ""
	const Board=preload("res://scripts/breadboard_model.gd")
	const Analysis=preload("res://scripts/analyzer/capture.gd")
	var lines: Array=[]
	var stats: Dictionary=capture.statistics()
	if stats.has("rms"):lines.append("Received capture: sampled mean %.5f V · sampled RMS %.5f V · %d points. These are estimates over captured timestamps, not a phasor measurement."%[stats.mean,stats.rms,stats.count])
	for part in board.parts:
		if not selected.has(part.id):continue
		var model: Dictionary=Board.catalog(board).get(str(part.type),{})
		lines.append("%s · %s · %s"%[part.id,model.get("name",part.type),model.get("rating","")])
		if model.has("value"):lines.append("Model parameter: %s %s"%[model.value,model.get("unit","")])
		var definition: Dictionary=board.get("definitions",{}).get(str(part.type),{})
		if definition.has("footprint"):lines.append("Footprint: %s × %s grid; body height %s mm; substrate %s mm"%[definition.footprint.width,definition.footprint.height,definition.footprint.get("body_height_mm","legacy default"),definition.footprint.get("thickness_mm","legacy default")])
		for index in Board.pins(part).size():
			var hole: String=Board.pins(part)[index]
			var measured := Analysis.differential(measurements,"board/"+Board.node(hole,int(board.rows)),capture.negative)
			var pin: Dictionary=definition.get("pins",[])[index] if index<definition.get("pins",[]).size() else {}
			lines.append("  %s [%s] → %s: %s · %s / %s"%[str(model.get("pins",[])[index]) if index<model.get("pins",[]).size() else str(index+1),pin.get("id","pin_%d"%(index+1)),hole,"%.5f V instantaneous"%measured.value if measured.ok else measured.reason,pin.get("role","unspecified"),pin.get("connector","component pin")])
		var state: Dictionary=device_states.get("board/"+str(part.id),{})
		if state.has("status"):lines.append("Backend: %s · line %s · elapsed %s s"%[state.status,state.get("line","unavailable"),state.get("time","unavailable")])
		if state.has("modes"):lines.append("GPIO modes (backend): "+str(state.modes))
		if state.has("outputs"):lines.append("GPIO drive (backend): "+str(state.outputs))
		if state.has("serial"):lines.append("Serial: "+" | ".join(state.serial.slice(maxi(0,state.serial.size()-4))))
		for device in Board.devices(board):
			if device.part.type!="lv_mcu" or (str(device.id)!="board/"+str(part.id) and not str(device.id).begins_with("board/"+str(part.id)+"/")):continue
			var snapshot: Dictionary=device_states.get(str(device.id),{})
			if not snapshot.has("powered"):continue
			lines.append("%s: %s · line %s (backend snapshot)"%[device.id,snapshot.get("status",""),snapshot.get("line","unavailable")])
			for pin in ["D0","D1","PWM"]:
				var driving: bool=snapshot.powered and snapshot.get("modes",{}).get(pin,"in")=="out" and snapshot.get("outputs",{}).has(pin)
				lines.append("  %s: %s"%[pin,"driving; commanded high fraction %.3f (LV backend 50 Hz)"%float(snapshot.outputs[pin]) if driving else "high impedance (LV model 1 TΩ input)"])
	return "\n".join(lines)
func style(color: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new();s.bg_color=color;s.set_corner_radius_all(3);return s

func transform_selected(dx: int,dy: int,rotate := false) -> void:
	if selected.is_empty():return
	var candidate: Dictionary=board.duplicate(true)
	for part in candidate.parts:
		if not selected.has(part.id):continue
		var a := Vector2i(int(str(part.a).substr(1))-1,LETTERS.find(str(part.a).left(1)))
		var b := Vector2i(int(str(part.b).substr(1))-1,LETTERS.find(str(part.b).left(1)))
		if rotate:
			var offset := b-a;b=a+Vector2i(-offset.y,offset.x)
			part.surface_rotation=fposmod(float(part.get("surface_rotation",0))+PI/2,TAU)
		else:a+=Vector2i(dx,dy);b+=Vector2i(dx,dy)
		for point in [a,b]:
			if point.x<0 or point.x>=int(board.rows) or point.y<0 or point.y>=hole_letters().length():return
		if part.has("pins"):
			var transformed: Array=[]
			var pivot := Vector2i(int(str(part.a).substr(1))-1,LETTERS.find(str(part.a).left(1)))
			for pin in part.pins:
				var point := Vector2i(int(str(pin).substr(1))-1,LETTERS.find(str(pin).left(1)))
				if rotate:var offset := point-pivot;point=pivot+Vector2i(-offset.y,offset.x)
				else:point+=Vector2i(dx,dy)
				if point.x<0 or point.x>=int(board.rows) or point.y<0 or point.y>=hole_letters().length():return
				transformed.append(LETTERS[point.y]+str(point.x+1))
			part.pins=transformed
		part.a=LETTERS[a.y]+str(a.x+1);part.b=LETTERS[b.y]+str(b.x+1)
	if preload("res://scripts/breadboard_model.gd").validate(candidate,{},true)!="":return
	commit();board=candidate;design_changed.emit(board);queue_redraw()
func delete_selected() -> void:
	if selected.is_empty():return
	commit();board.parts=board.parts.filter(func(p):return not selected.has(p.id));selected.clear();design_changed.emit(board);queue_redraw()
func resize_board(rows: int) -> bool:
	var candidate := board.duplicate(true);candidate.rows=rows
	resize_error = validate_board_layout(candidate)
	if not resize_error.is_empty():return false
	commit();board=candidate;first="";design_changed.emit(board);queue_redraw();return true

func validate_board_layout(candidate: Dictionary) -> String:
	var error := BoardModel.fit_external_ports(candidate, board.ports, attached_resize_ports)
	return BoardModel.validate(candidate, {}, true) if error.is_empty() else error

func copy_selected() -> void:
	clipboard=board.parts.filter(func(part):return selected.has(part.id)).duplicate(true)
func paste_selected() -> bool:
	if clipboard.is_empty():return false
	for dx in range(1,int(board.rows)):
		var candidate := board.duplicate(true);var new_ids: Array=[];var valid := true
		for source in clipboard:
			var part: Dictionary=source.duplicate(true);part.id=str(Time.get_ticks_usec())+"_"+str(new_ids.size());new_ids.append(part.id)
			for key in ["a","b"]:
				var row := int(str(part[key]).substr(1))+dx
				if row>int(board.rows):valid=false;break
				part[key]=str(part[key]).left(1)+str(row)
			if part.has("pins"):
				part.pins=part.pins.map(func(pin):return str(pin).left(1)+str(int(str(pin).substr(1))+dx))
			candidate.parts.append(part)
		if valid and preload("res://scripts/breadboard_model.gd").validate(candidate,{},true)=="":
			commit();board=candidate;selected=new_ids;design_changed.emit(board);queue_redraw();return true
	return false

func pcb_rect(part: Dictionary,definition: Dictionary) -> Rect2:
	if board.get("standalone",false):return Rect2(Vector2(12,12),size-Vector2(24,24))
	var grid_rect := preload("res://scripts/breadboard_model.gd").package_rect(part,definition)
	if not grid_rect.has_area() or grid_rect.position.y<0 or grid_rect.end.y>hole_letters().length():return Rect2()
	var first_hole := LETTERS[grid_rect.position.y]+str(grid_rect.position.x+1)
	var last_hole := LETTERS[grid_rect.end.y-1]+str(grid_rect.end.x)
	return Rect2(at(first_hole)-Vector2(8,8)*zoom,at(last_hole)-at(first_hole)+Vector2(16,16)*zoom)
func layout_point(hole: String,layout: Dictionary,rect: Rect2) -> Vector2:
	var col := LETTERS.find(hole.left(1));var row := int(hole.substr(1))-1
	var low := Vector2(INF,INF);var high := Vector2(-INF,-INF)
	for component in layout.parts:
		for pin in preload("res://scripts/breadboard_model.gd").pins(component):
			var point := Vector2(int(str(pin).substr(1))-1,LETTERS.find(str(pin).left(1)));low=low.min(point);high=high.max(point)
	for wire in layout.wires:
		for pin in wire:
			var point := Vector2(int(str(pin).substr(1))-1,LETTERS.find(str(pin).left(1)));low=low.min(point);high=high.max(point)
	if not low.is_finite():low=Vector2.ZERO;high=Vector2.ONE
	var fraction := Vector2(.5 if high.x==low.x else (row-low.x)/(high.x-low.x),.5 if high.y==low.y else (col-low.y)/(high.y-low.y))
	return rect.position+rect.size*Vector2(.12,.22)+fraction*rect.size*Vector2(.76,.56)
func draw_ic_package(part: Dictionary, definition: Dictionary, font: Font, opacity := 1.0) -> void:
	var footprint := pcb_rect(part, definition)
	if not footprint.has_area(): return
	var placement := SurfaceGeometry.placement(part, definition)
	var turns := int(definition.get("orientation_turns", 0)) + int(placement.get("turns", 0))
	var across := Vector2.RIGHT if turns % 2 == 0 else Vector2.DOWN
	var inset := across * minf(15.0 * zoom, footprint.size.dot(across) * .36)
	var chip := Rect2(footprint.position + inset, footprint.size - inset * 2)
	var pin_points: Array = preload("res://scripts/breadboard_model.gd").pins(part)
	var metal := Color("aebdc3", opacity)
	for hole in pin_points:
		var tip := at(str(hole))
		var shoulder := tip.clamp(chip.position, chip.end)
		if not tip.is_equal_approx(shoulder):
			draw_line(tip, shoulder, metal, maxf(1.0, 3.5 * zoom), true)
		draw_circle(tip, maxf(1.0, 2.1 * zoom), metal, true)
	var tint := Color(str(definition.footprint.get("color", "303b40")))
	tint.a = opacity
	draw_style_box(style(tint), chip)
	if not pin_points.is_empty():
		var first := at(str(pin_points[0])).clamp(chip.position, chip.end)
		var mark := first.lerp(chip.get_center(), .25)
		var ink := Color("e5eedb", opacity)
		match str(definition.get("orientation_marker", "dot")):
			"dot": draw_circle(mark, maxf(1.0, 1.8 * zoom), ink, true)
			"notch": draw_arc(mark, 3 * zoom, 0, PI, 12, ink, 2, true)
			"triangle":
				draw_colored_polygon(PackedVector2Array([mark + Vector2(0,-3)*zoom, mark + Vector2(-3,3)*zoom, mark + Vector2(3,3)*zoom]), ink)
	var label := str(definition.get("marking", ""))
	if label.is_empty(): label = str(definition.get("name", "IC"))
	var font_size := maxi(7, roundi(9 * zoom))
	if chip.size.x > 6 and chip.size.y >= font_size:
		var baseline := chip.get_center().y + font_size * .32
		draw_string(font, Vector2(chip.position.x + 3, baseline), label, HORIZONTAL_ALIGNMENT_CENTER, chip.size.x - 6, font_size, Color("e5eedb", opacity))

func draw_pcb(part: Dictionary,definition: Dictionary,font: Font) -> void:
	var is_ic: bool = definition.get("package", "IC") == "IC"
	if is_ic:
		draw_ic_package(part, definition, font)
		if definition.get("exposed", []).is_empty(): return
	var rect := pcb_rect(part,definition)
	if not is_ic:
		if PCB.active(definition):draw_routed_substrate(definition,rect)
		elif physical_pcb_surface:
			draw_rect(rect,Color(str(definition.footprint.get("color","24775b"))))
			draw_rect(rect.grow(-6),Color("d7ded0",.4),false,2)
		else:draw_style_box(style(Color(str(definition.footprint.get("color","24775b")))),rect)
		if board.get("standalone",false) and not PCB.active(definition):
			PCB.draw_grid(self,rect,definition.get("footprint",{}))
	var layout: Dictionary=definition.layout
	var mounting := _surface_mounting(part,definition)
	var component_scale := 3.0 if board.get("standalone",false) else 1.0
	for index in definition.pins.size():
		if definition.get("package","")!="PCB" or PCB.active(definition) or definition.has("surface_layout"):continue
		for child in layout.parts:
			var found := false
			for hole in preload("res://scripts/breadboard_model.gd").pins(child):
				if preload("res://scripts/breadboard_model.gd").node(str(hole),int(layout.rows))==str(definition.pins[index].node):
					var start := at(preload("res://scripts/breadboard_model.gd").pins(part)[index]);var finish := layout_point(str(hole),layout,rect)
					draw_polyline(PackedVector2Array([start,Vector2(start.x,finish.y),finish]),Color("a3ba79"),maxf(1,zoom*component_scale),true);found=true;break
			if found:break
	for wire in (layout.wires if definition.get("package","")=="PCB" and not PCB.active(definition) and not definition.has("surface_layout") else []):draw_line(layout_point(str(wire[0]),layout,rect),layout_point(str(wire[1]),layout,rect),Color("bbbd73"),maxf(1,zoom),true)
	if physical_pcb_surface:return
	for child in layout.parts:
		if not SurfaceLayout.visible(definition,str(child.id)):continue
		if definition.has("surface_layout"):
			_draw_mounted_part(definition,child,rect,"board/"+str(part.id)+"/",font,1,mounting)
			continue
		var a := pcb_child_point(definition,child,0,rect);var b := pcb_child_end_point(definition,child,rect);var center := pcb_child_center(definition,child,rect)
		draw_line(a,b,Color("bdc4bd"),zoom,true)
		if str(child.type).begins_with("ic:"):_draw_nested(board.get("definitions",{}).get(child.type,{}),_nested_rect(child,layout,rect,definition),"board/"+str(part.id)+"/"+str(child.id)+"/",font,1)
		elif child.type=="spi_display":draw_display("board/"+str(part.id)+"/"+str(child.id),center,zoom*.4*component_scale,font)
		elif str(child.type).begins_with("led"):
			_draw_package_led(center,3*zoom*component_scale,str(child.type),"board/"+str(part.id)+"/"+str(child.id))
		else:draw_rect(Rect2(center-Vector2(4,3)*zoom*component_scale,Vector2(8,6)*zoom*component_scale),Color("27322d") if str(child.type).begins_with("ic:") or child.type=="lv_mcu" else Color("c7b58a"))
		if BoardModel.pins(child).size()==2:
			draw_polarity_labels(preload("res://scripts/electronics_catalog.gd").simulation_entry(str(child.type)),a,b,font)
		if board.get("standalone",false):draw_string(font,center+Vector2(16,5),str(preload("res://scripts/breadboard_model.gd").catalog(board).get(child.type,{}).get("name",child.type)),HORIZONTAL_ALIGNMENT_LEFT,-1,14,Color("eff5df"))
	if is_ic: return
	for pin in preload("res://scripts/breadboard_model.gd").pins(part):draw_circle(at(pin),3*zoom,Color("e3ca78"))
	for index in definition.pins.size():
		var pin: Dictionary=definition.pins[index]
		var point := at(preload("res://scripts/breadboard_model.gd").pins(part)[index])
		var connector := str(pin.get("connector","male_header"))
		var radius := 4*zoom
		if connector=="female_header":draw_rect(Rect2(point-Vector2.ONE*radius,Vector2.ONE*radius*2),Color("d6c98b"));draw_circle(point,radius*.55,Color("15232a"))
		elif connector=="terminal_block":draw_rect(Rect2(point-Vector2.ONE*radius*1.3,Vector2.ONE*radius*2.6),Color("76bdb0"));draw_line(point-Vector2(radius,0),point+Vector2(radius,0),Color("203f46"),2)
		elif connector in ["through_hole","test_point"]:draw_arc(point,radius,0,TAU,16,Color("f1d27f"),2,true)
		else:draw_rect(Rect2(point-Vector2.ONE*radius*.6,Vector2.ONE*radius*1.2),Color("f1d27f"))
	var marker := str(definition.get("orientation_marker","dot"))
	var mark := rect.position+Vector2(9,22)*zoom
	if marker=="dot":draw_circle(mark,3*zoom,Color("e5eedb"))
	elif marker=="notch":draw_arc(mark,5*zoom,0,PI,12,Color("e5eedb"),2,true)
	elif marker=="triangle":draw_colored_polygon(PackedVector2Array([mark+Vector2(0,-4)*zoom,mark+Vector2(-4,4)*zoom,mark+Vector2(4,4)*zoom]),Color("e5eedb"))
	if str(definition.get("marking",""))!="":draw_string(font,rect.position+Vector2(6,rect.size.y/zoom-6)*zoom,str(definition.marking),HORIZONTAL_ALIGNMENT_LEFT,rect.size.x-12,11,Color("e5eedb"))
	draw_string(font,rect.position+Vector2(4,12)*zoom,str(definition.name),HORIZONTAL_ALIGNMENT_LEFT,rect.size.x-8,11,Color("e5eedb"))

func exposed_controls() -> Array:
	var result: Array=[]
	for part in board.parts:
		var input_type := BoardModel.manual_input_type(str(part.type))
		if not input_type.is_empty() or part.type in ["lv_mcu","native_uno","native_pico","native_nano"]:
			result.append({"id":"board/"+str(part.id),"type":input_type if not input_type.is_empty() else part.type,"center":native_rect(part).get_center() if part.type in ["native_uno","native_pico","native_nano"] else solar_rect(part).get_center() if part.get("solar_footprint",false) else (at(part.a)+at(part.b))*.5,"radius":20*zoom})
		var definition: Dictionary=board.get("definitions",{}).get(str(part.type),{})
		if not definition.has("layout") or not definition.has("footprint"):continue
		var rect := pcb_rect(part,definition)
		_collect_exposed(definition,rect,"board/"+str(part.id)+"/",result,0,_surface_mounting(part,definition))
	return result

func surface_devices() -> Array:
	var result: Array=[]
	for part in board.get("parts",[]):
		var definition: Dictionary=board.get("definitions",{}).get(str(part.type),{})
		if definition.has("layout"):_collect_surface(definition,pcb_rect(part,definition),"board/"+str(part.id)+"/",result,0,_surface_mounting(part,definition))
		elif part.get("solar_footprint",false):
			var bounds := solar_rect(part)
			result.append({"id":"board/"+str(part.id),"type":part.type,"center":bounds.get_center(),"pins":SolarBoard.pins(part).map(func(pin):return at(pin)),"rotation":float(part.get("surface_rotation",0)),"surface_size":bounds.size,"solar_footprint":true})
		else:result.append({"id":"board/"+str(part.id),"type":part.type,"center":(at(part.a)+at(part.b))*.5,"pins":preload("res://scripts/breadboard_model.gd").pins(part).map(func(pin):return at(pin)),"rotation":float(part.get("surface_rotation",0))})
	return result

func _collect_surface(definition: Dictionary,rect: Rect2,prefix: String,result: Array,depth: int,mounting := 0) -> void:
	if depth>=8 or not definition.has("layout"):return
	for child in definition.layout.parts:
		if not SurfaceLayout.visible(definition,str(child.id)):continue
		var id := prefix+str(child.id)
		var bounds := surface_bounds(definition,child,rect,mounting)
		var record: Dictionary = definition.get("surface_layout",{}).get(child.id,{})
		var turns := int(record.get("turns",0))+int(definition.get("orientation_turns",0))+mounting
		var rotation_angle := turns*PI/2 if not record.is_empty() else mounting*PI/2+float(child.get("surface_rotation",0))
		if str(child.type).begins_with("ic:"):
			_collect_surface(board.get("definitions",{}).get(child.type,{}),_nested_rect(child,definition.layout,rect,definition,mounting),id+"/",result,depth+1,turns)
		elif not record.is_empty():
			result.append({"id":id,"type":child.type,"center":bounds.get_center(),"pins":[],"rotation":rotation_angle,"surface_size":bounds.size})
		else:
			result.append({"id":id,"type":child.type,"center":pcb_child_center(definition,child,rect),"pins":pcb_child_pins(definition,child,rect),"rotation":rotation_angle})

func _nested_rect(child: Dictionary,layout: Dictionary,rect: Rect2,definition: Dictionary={},mounting := 0) -> Rect2:
	if definition.has("surface_layout"): return surface_bounds(definition,child,rect,mounting)
	var a := pcb_child_point(definition,child,0,rect) if not definition.is_empty() else layout_point(str(child.a),layout,rect)
	var b := pcb_child_end_point(definition,child,rect) if not definition.is_empty() else layout_point(str(child.b),layout,rect)
	var extent := Vector2(maxf(absf(a.x-b.x),rect.size.x*.24),maxf(absf(a.y-b.y),rect.size.y*.25))
	extent=extent.min(rect.size*.7)
	return Rect2((a+b)*.5-extent*.5,extent)

func _collect_exposed(definition: Dictionary,rect: Rect2,prefix: String,result: Array,depth: int,mounting := 0) -> void:
	if depth>=8 or not definition.has("layout"):return
	for child in definition.layout.parts:
		if not SurfaceLayout.visible(definition,str(child.id)):continue
		var id := prefix+str(child.id)
		var input_type := BoardModel.manual_input_type(str(child.type))
		if not input_type.is_empty() or child.type in ["lv_mcu","native_uno","native_pico","native_nano"]:
			var bounds := surface_bounds(definition,child,rect,mounting)
			var center := pcb_child_center(definition,child,rect) if bounds.size == Vector2.ZERO else bounds.get_center()
			var radius := maxf(maxf(8,8*zoom/pow(1.3,depth)),minf(bounds.size.x,bounds.size.y)*.5)
			result.append({"id":id,"type":input_type if not input_type.is_empty() else child.type,"center":center,"radius":radius,"surface_size":bounds.size})
		elif str(child.type).begins_with("ic:"):
			_collect_exposed(board.get("definitions",{}).get(child.type,{}),_nested_rect(child,definition.layout,rect,definition,mounting),id+"/",result,depth+1)

func _surface_mounting(part: Dictionary, definition: Dictionary) -> int:
	if not definition.has("surface_layout") or board.get("standalone",false): return 0
	return int(SurfaceGeometry.placement(part,definition).get("turns",0))

func surface_bounds(definition: Dictionary, child: Dictionary, outline: Rect2, mounting := 0) -> Rect2:
	var layout: Dictionary = definition.get("surface_layout",{})
	if not layout.has(child.id): return Rect2()
	return SurfaceLayout.view_rect(definition,layout[child.id],child.type,board.get("definitions",{}),outline,mounting)

func _draw_mounted_part(definition: Dictionary, child: Dictionary, outline: Rect2, prefix: String, font: Font, depth: int, mounting: int) -> void:
	var bounds := surface_bounds(definition,child,outline,mounting)
	var center := bounds.get_center()
	var type := str(child.type)
	var id := prefix+str(child.id)
	if type.begins_with("ic:"):
		_draw_nested(board.get("definitions",{}).get(type,{}),bounds,id+"/",font,depth)
		return
	if type in ["spi_display","seven_segment"]:
		var turn := int(definition.surface_layout[child.id].turns)+int(definition.get("orientation_turns",0))+mounting
		var dimensions := bounds.size if turn%2 == 0 else Vector2(bounds.size.y,bounds.size.x)
		draw_set_transform(center,turn*PI/2)
		if type == "spi_display": draw_display(id,Vector2.ZERO,minf(dimensions.x/136.0,dimensions.y/48.0),font)
		else: _draw_digit(id,dimensions,1.0)
		draw_set_transform(Vector2.ZERO)
		return
	if type.begins_with("led"):
		_draw_package_led(center,minf(bounds.size.x,bounds.size.y)*.31,type,id)
		return
	var body := bounds.grow(-minf(bounds.size.x,bounds.size.y)*.15)
	var input_type := BoardModel.manual_input_type(type)
	if not input_type.is_empty():
		var control: Dictionary=board.get("controls",{}).get(id,{})
		draw_style_box(style(SurfaceLayout.part_color(type)),body)
		var radius := minf(body.size.x,body.size.y)*.42
		if input_type in ["button","toggle"]:
			var pressed: bool=control.get("pressed",child.get("pressed",false))
			draw_circle(center,radius,Color("80d6a0") if pressed else Color("bd665b"),true,-1,true)
		else:
			var initial := .65 if input_type in ["photodiode","solar_panel"] else .5
			var setting := float(control.get("setting",child.get("setting",initial)))
			var direction := Vector2.UP.rotated(lerpf(-PI*.75,PI*.75,setting))
			draw_circle(center,radius,Color("6c8995"),true,-1,true)
			draw_line(center+direction*radius*.28,center+direction*radius*.86,Color("edf6fa"),1.5,true)
		return
	draw_style_box(style(SurfaceLayout.part_color(type)),body)
	if minf(body.size.x,body.size.y) > 14:
		draw_string(font,body.position+Vector2(3,11),str(child.id),HORIZONTAL_ALIGNMENT_LEFT,body.size.x-6,10,Color("e9eee0"))

func _draw_nested(definition: Dictionary,rect: Rect2,prefix: String,font: Font,depth: int) -> void:
	if depth>=8 or not definition.has("layout"):return
	if PCB.active(definition):draw_routed_substrate(definition,rect)
	else:draw_style_box(style(Color(str(definition.get("footprint",{}).get("color","24775b" if definition.get("package","")=="PCB" else "303b40")))),rect)
	for child in definition.layout.parts:
		if not SurfaceLayout.visible(definition,str(child.id)):continue
		if definition.has("surface_layout"):
			_draw_mounted_part(definition,child,rect,prefix,font,depth+1,0)
			continue
		var id := prefix+str(child.id)
		var center := pcb_child_center(definition,child,rect)
		if str(child.type).begins_with("ic:"):
			_draw_nested(board.get("definitions",{}).get(child.type,{}),_nested_rect(child,definition.layout,rect,definition),id+"/",font,depth+1)
		elif child.type=="spi_display":draw_display(id,center,minf(rect.size.x/160.,rect.size.y/60.)*.5,font)
		elif str(child.type).begins_with("led"):
			_draw_package_led(center,maxf(3,6*zoom/pow(1.3,depth)),str(child.type),id)
		else:
			draw_circle(center,maxf(3,6*zoom/pow(1.3,depth)),Color("c7b58a"))

func _draw_package_led(center: Vector2,radius: float,type: String,id: String) -> void:
	var model := preload("res://scripts/electronics_catalog.gd").simulation_entry(type)
	draw_led(center,radius,Color(str(model.get("color","ff493c"))),float(currents.get(id,0)))

func draw_polarity_labels(entry: Dictionary, first_pin: Vector2, second_pin: Vector2, font: Font, opacity := 1.0) -> void:
	var labels := preload("res://scripts/electronics_catalog.gd").polarity_labels(entry)
	if labels.is_empty():return
	var direction := (second_pin-first_pin).normalized()
	if direction.is_zero_approx():return
	var font_size := clampi(roundi(11*zoom),10,15)
	for index in 2:
		var pin := first_pin if index==0 else second_pin
		var outward := -direction if index==0 else direction
		var label: String = labels[index]
		var width := font.get_string_size(label,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size).x
		var center := pin+outward*8+Vector2(0,9)
		var baseline := center+Vector2(-width*.5,font_size*.35)
		draw_line(pin,pin.lerp(center,.62),Color("20343b",opacity),1.5,true)
		draw_string_outline(font,baseline,label,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size,4,Color("172b32",opacity))
		draw_string(font,baseline,label,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size,Color("fff2c9",opacity))

func draw_led(center: Vector2,radius: float,tint: Color,current: float,opacity := 1.0) -> void:
	var strength := log(1.0+maxf(current,0.0)/.006)
	if strength>0.0:
		var spread := radius*strength
		var alpha := (1.0-exp(-strength))*.25*opacity
		for layer in [1.6,1.1,.65,.3]:
			draw_circle(center,radius+spread*layer,Color(tint,alpha),true,-1,true)
	var core := tint.darkened(.72).lerp(tint,1.0-exp(-strength))
	core=core.lerp(Color.WHITE,.8*(1.0-exp(-strength*.28)))
	draw_circle(center,radius,Color(core,opacity),true,-1,true)

func _draw_digit(id: String, body_size: Vector2, opacity: float) -> void:
	draw_style_box(style(Color("20272a", opacity)), Rect2(-body_size * .5, body_size))
	var scale_factor := minf(body_size.x / 33.0, body_size.y / 48.0)
	var segments := [
		[Vector2(-8,-18),Vector2(8,-18)], [Vector2(9,-16),Vector2(9,-2)],
		[Vector2(9,2),Vector2(9,16)], [Vector2(-8,18),Vector2(8,18)],
		[Vector2(-9,2),Vector2(-9,16)], [Vector2(-9,-16),Vector2(-9,-2)],
		[Vector2(-8,0),Vector2(8,0)],
	]
	for index in segments.size():
		var amps := float(currents.get("%s/%d" % [id,index], 0.0))
		var color := Color("4a2527",opacity).lerp(Color("ff5149",opacity),clampf(amps/.01,0,1))
		draw_line(segments[index][0]*scale_factor, segments[index][1]*scale_factor,color,2.5*scale_factor,true)
	var dot_current := float(currents.get(id+"/7",0.0))
	draw_circle(Vector2(12,20)*scale_factor,2*scale_factor,Color("ff5149" if dot_current > .001 else "4a2527",opacity))

func draw_display(id: String,center: Vector2,scale_factor: float,font: Font, opacity := 1.0) -> void:
	var state: Dictionary=device_states.get(id,{})
	draw_style_box(style(Color("243932",opacity)),Rect2(center-Vector2(68,24)*scale_factor,Vector2(136,48)*scale_factor))
	draw_rect(Rect2(center-Vector2(62,19)*scale_factor,Vector2(124,38)*scale_factor),Color("a7c58b",opacity) if state.get("powered",false) else Color("3f5147",opacity))
	if not state.get("powered",false):return
	var cells: Array=state.get("cells",[])
	for row in 2:
		var text := ""
		for col in 16:text+=String.chr(int(cells[row*16+col])) if cells.size()==32 else " "
		draw_string(font,center+Vector2(-60,-3+row*16)*scale_factor,text,HORIZONTAL_ALIGNMENT_LEFT,124*scale_factor,maxi(6,roundi(11*scale_factor)),Color("203625"))

func native_rect(part: Dictionary) -> Rect2:
	var pins: Array=preload("res://scripts/breadboard_model.gd").pins(part)
	var rect := Rect2(at(str(pins[0])),Vector2.ONE)
	for pin in pins:rect=rect.expand(at(str(pin)))
	return rect.grow(9*zoom)
func draw_native_board(part: Dictionary,font: Font, opacity := 1.0) -> void:
	var rect := native_rect(part);var model: Dictionary=preload("res://scripts/breadboard_model.gd").catalog(board)[part.type]
	draw_style_box(style(Color("2866a2",opacity) if part.type=="native_nano" else Color("277f92",opacity) if part.type=="native_uno" else Color("288160",opacity)),rect)
	var center := rect.get_center();draw_rect(Rect2(center-Vector2(18,18)*zoom,Vector2(36,36)*zoom),Color("17252b",opacity))
	draw_rect(Rect2(Vector2(rect.position.x-6*zoom,center.y-13*zoom),Vector2(27,26)*zoom),Color("a2b4b8",opacity))
	draw_string(font,center+Vector2(-40,34)*zoom,model.name,HORIZONTAL_ALIGNMENT_LEFT,-1,12,Color("e4f4ea",opacity))
	for index in part.pins.size():
		var point := at(str(part.pins[index]));draw_circle(point,4*zoom,Color("dbbf74",opacity));draw_circle(point,2*zoom,Color("16242c",opacity))
		draw_string(font,point+Vector2(-6,15 if point.y<center.y else -8)*zoom,str(model.pins[index]),HORIZONTAL_ALIGNMENT_LEFT,-1,9,Color("eff8ee",opacity))
	if selected.has(part.id):draw_rect(rect,Color("ffdc82"),false,2)

func pcb_child_point(definition: Dictionary,child: Dictionary,index: int,rect: Rect2) -> Vector2:
	if PCB.active(definition):
		var id:=PCB.pad_id(str(child.id),index)
		return PCB.map_point(definition,definition.pcb_design.pads[id].position,rect)
	var pins: Array=preload("res://scripts/breadboard_model.gd").pins(child)
	return layout_point(str(pins[mini(index,pins.size()-1)]),definition.layout,rect)
func pcb_child_pins(definition: Dictionary,child: Dictionary,rect: Rect2) -> Array:
	var result: Array=[]
	for i in preload("res://scripts/breadboard_model.gd").pins(child).size():result.append(pcb_child_point(definition,child,i,rect))
	return result
func draw_routed_substrate(definition: Dictionary,rect: Rect2) -> void:
	var poly:=PackedVector2Array()
	for value in definition.pcb_design.outline:poly.append(PCB.map_point(definition,value,rect))
	draw_colored_polygon(poly,Color(str(definition.footprint.color)))
	if board.get("standalone",false):PCB.draw_grid(self,rect,definition.footprint,poly)
	for route in definition.pcb_design.routes:
		var points:=PackedVector2Array()
		for value in route.points:points.append(PCB.map_point(definition,value,rect))
		draw_polyline(points,Color("d4b477"),maxf(1,float(route.width)*rect.size.x/(float(definition.footprint.width)-1)),true)
	for pad in definition.pcb_design.pads.values():draw_circle(PCB.map_point(definition,pad.position,rect),maxf(2,float(definition.pcb_design.pad_radius)*rect.size.x/(float(definition.footprint.width)-1)),Color("dfc986"))

func pcb_child_end_point(definition: Dictionary,child: Dictionary,rect: Rect2) -> Vector2:
	if PCB.active(definition):return pcb_child_point(definition,child,preload("res://scripts/breadboard_model.gd").pins(child).size()-1,rect)
	return layout_point(str(child.b),definition.layout,rect)
func pcb_child_center(definition: Dictionary,child: Dictionary,rect: Rect2) -> Vector2:
	if not PCB.active(definition):return (layout_point(str(child.a),definition.layout,rect)+layout_point(str(child.b),definition.layout,rect))*.5
	var pins:=pcb_child_pins(definition,child,rect)
	var bounds:=Rect2(pins[0],Vector2.ZERO)
	for pin in pins:bounds=bounds.expand(pin)
	return bounds.get_center()
