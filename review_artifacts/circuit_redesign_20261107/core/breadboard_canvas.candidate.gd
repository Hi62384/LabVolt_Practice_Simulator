extends Control
signal design_changed(board: Dictionary)
signal io_command_requested(id: String,command: Dictionary)
signal code_requested(id: String)
var board: Dictionary=preload("res://scripts/breadboard_model.gd").empty()
var read_only := false
var selected_type := "wire":
	set(value):
		if selected_type=="interact" and value!="interact":release_io_capture()
		selected_type=value
var selected: Array=[]
var currents := {}
var device_states := {}
var analyzer_enabled := false
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
const LETTERS = "PNABCDEFGHIJ"
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
	if io_adapter!=null:io_adapter.release_all()
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
			if preload("res://scripts/package_editor/package_geometry.gd").explicit_pins(definition):
				var p := preload("res://scripts/package_editor/package_geometry.gd").position(definition.pins[index])
				return Vector2(32,32)+Vector2(p)*Vector2((size.x-64)/maxf(1,int(definition.footprint.width)-1),(size.y-150)/maxf(1,int(definition.footprint.height)-1))
			var half := ceili(pins.size()/2.0);var col := index%half
			return Vector2(60+(size.x-120)*(col+.5)/half,32 if index<half else size.y-32)
	var col := LETTERS.find(hole.left(1));var row := int(hole.substr(1))-1
	return Vector2(35+row*23,45+col*23+(24 if col>=7 else 0)+(15 if col>=2 else 0))*zoom+pan
func hole_at(point: Vector2) -> String:
	for row in range(1,int(board.rows)+1):
		for col in LETTERS:
			var name := col+str(row)
			if at(name).distance_to(point)<9*zoom:return name
	return ""
func commit() -> void:
	history.append(board.duplicate(true));if history.size()>40:history.pop_front()
	future.clear()
func undo() -> void:
	if history.is_empty():return
	future.append(board.duplicate(true));board=history.pop_back();first="";design_changed.emit(board);queue_redraw()
func redo() -> void:
	if future.is_empty():return
	history.append(board.duplicate(true));board=future.pop_back();design_changed.emit(board);queue_redraw()
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
		for control in exposed_controls():
			if control.center.distance_to(event.position)>control.radius:continue
			if not board.has("controls"):board.controls={}
			var state: Dictionary=board.controls.get(control.id,{})
			if control.type=="pot10k" and event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:state.setting=clampf(float(state.get("setting",.5))+(.05 if event.button_index==MOUSE_BUTTON_WHEEL_UP else -.05),0,1)
			elif control.type=="button" and event.button_index==MOUSE_BUTTON_LEFT:state.pressed=event.pressed
			elif control.type=="toggle" and event.pressed and event.button_index==MOUSE_BUTTON_LEFT:state.pressed=not state.get("pressed",false)
			else:continue
			board.controls[control.id]=state
			for part in board.parts:
				if "board/"+str(part.id)==control.id:part.merge(state,true)
			design_changed.emit(board);queue_redraw();return
	if event is InputEventMouseButton:
		if event.button_index==MOUSE_BUTTON_MIDDLE:dragging=event.pressed
		if event.pressed and selected_type=="interact" and event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:
			for part in board.parts:
				if part.type=="pot10k" and (at(part.a)+at(part.b)).distance_to(event.position*2)<40*zoom:
					part.setting=clampf(float(part.get("setting",.5))+(.05 if event.button_index==MOUSE_BUTTON_WHEEL_UP else -.05),0,1);design_changed.emit(board);queue_redraw();return
		if event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:zoom=clampf(zoom*(1.1 if event.button_index==MOUSE_BUTTON_WHEEL_UP else .9),.6,2);queue_redraw()
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
			elif selected_type=="interact":
				for part in board.parts:
					if part.type in ["button","toggle"] and (at(part.a)+at(part.b)).distance_to(event.position*2)<40*zoom:
						if part.type=="button":part.pressed=event.pressed
						elif event.pressed:part.pressed=not part.get("pressed",false)
						design_changed.emit(board);queue_redraw();return
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
						if preload("res://scripts/package_editor/package_geometry.gd").explicit_pins(definition):
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
func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO,size),Color("1b2d39"))
	var font := ThemeDB.fallback_font
	if board.get("standalone",false) and board.parts.size()==1:
		var part: Dictionary=board.parts[0];var definition: Dictionary=board.definitions[part.type]
		draw_pcb(part,definition,font)
		for i in definition.pins.size():
			var point := at(part.pins[i])
			var offset := Vector2(-120,16) if point.x>size.x*.5 else Vector2(4,16)
			draw_string(font,point+offset,"X%d · %s"%[i+1,definition.pins[i].name],HORIZONTAL_ALIGNMENT_LEFT,116,12,Color("f1e6bc"))
		if analyzer_enabled:draw_analyzer(font)
		return
	var extent := Vector2((int(board.rows)-1)*23+65,365)*zoom
	var origin := Vector2(8,12)*zoom+pan
	draw_style_box(style(Color("d9ded8")),Rect2(origin+Vector2(4,5)*zoom,extent))
	draw_style_box(style(Color("f0eee4")),Rect2(origin,extent))
	var trench_y := (at("E1").y+at("F1").y)*.5
	draw_rect(Rect2(Vector2(origin.x+12*zoom,trench_y-8*zoom),Vector2(extent.x-24*zoom,16*zoom)),Color("a6afa9"))
	for rail in ["P","N"]:
		for half in 2:
			var start := 1 if half==0 else int(board.rows)/2+1
			var finish := int(board.rows)/2 if half==0 else int(board.rows)
			draw_line(at(rail+str(start))+Vector2(0,-8)*zoom,at(rail+str(finish))+Vector2(0,-8)*zoom,Color("bd594c") if rail=="P" else Color("477fa4"),2*zoom,true)
	var active_hole := first if first!="" else hovered
	var active_node := preload("res://scripts/breadboard_model.gd").node(active_hole,int(board.rows))
	for row in range(1,int(board.rows)+1):
		for col in LETTERS:
			var hole := col+str(row);var point := at(hole)
			if active_node!="" and preload("res://scripts/breadboard_model.gd").node(hole,int(board.rows))==active_node:draw_circle(point,8*zoom,Color("8dd6bf"))
			var color := Color("b4bab5") if col not in "PN" else Color("cb766b") if col=="P" else Color("689cbe")
			draw_circle(point,4*zoom,color);draw_circle(point,2*zoom,Color("14202b"))
			if hole==first:draw_arc(point,8*zoom,0,TAU,20,Color("ffdb75"),2,true)
		if row%5==0 or row==1:draw_string(font,at("P"+str(row))+Vector2(-5,-16),str(row),HORIZONTAL_ALIGNMENT_LEFT,-1,12,Color("33454c"))
	for col in LETTERS:draw_string(font,at(col+"1")+Vector2(-23,4),col,HORIZONTAL_ALIGNMENT_LEFT,-1,12,Color("33454c"))
	for wire in board.wires:draw_line(at(wire[0]),at(wire[1]),Color("e3ab5c"),3*zoom,true)
	var catalog := preload("res://scripts/breadboard_model.gd").catalog(board)
	for part in board.parts:
		if part.type in ["native_uno","native_pico","native_nano"]:
			draw_native_board(part,font);continue
		var a := at(part.a);var b := at(part.b);var mid := (a+b)*.5
		draw_line(a,b,Color("b1bcc4"),2*zoom,true)
		for pin in part.get("pins",[]):draw_line(at(pin),mid,Color("b1bcc4"),2*zoom,true)
		var color := Color("72b8c1") if part.type.begins_with("c") else Color("c1a787")
		if catalog.get(part.type,{}).get("kind","")=="LED":color=Color("331b20").lerp(Color(catalog[part.type].get("color","ff5149")),clampf(float(currents.get("board/"+str(part.id),0))/.015,0,1))
		if selected.has(part.id):draw_rect(Rect2(mid-Vector2(16,11)*zoom,Vector2(32,22)*zoom),Color("ffdc82"),false,2)
		if part.get("pressed",false):color=Color("83e4a8")
		if catalog.get(part.type,{}).get("kind","")=="LED":
			draw_circle(mid,9*zoom,color);draw_arc(mid,9*zoom,PI,TAU,16,Color("f7b4a1"),2*zoom,true)
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
		elif part.type=="pot10k":
			draw_circle(mid,12*zoom,Color("426c8d"))
			var angle := lerpf(PI*.75,PI*2.25,float(part.get("setting",.5)))
			draw_line(mid,mid+Vector2(cos(angle),sin(angle))*10*zoom,Color.WHITE,2*zoom,true)
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
		draw_string(font,mid+Vector2(-15,-12)*zoom,catalog.get(part.type,{}).get("name",part.type),HORIZONTAL_ALIGNMENT_LEFT,-1,12,Color("263e46"))
	if analyzer_enabled:draw_analyzer(font)
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
			for col in LETTERS:
				var hole := col+str(row);var n := "board/"+Board.node(hole,int(board.rows))
				var measured := Analysis.differential(measurements,n,capture.negative)
				if measured.ok:
					var color := Color("f38970") if float(measured.value)>.05 else Color("72aaf3") if float(measured.value)<-.05 else Color("79d5ac")
					draw_arc(at(hole),6*zoom,0,TAU,12,color,2,true)
	var text := "Hover nodes · select parts · probe +/− holes. Colors: + red / − blue / near-zero green, relative to − probe."
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
			if point.x<0 or point.x>=int(board.rows) or point.y<0 or point.y>=LETTERS.length():return
		if part.has("pins"):
			var transformed: Array=[]
			var pivot := Vector2i(int(str(part.a).substr(1))-1,LETTERS.find(str(part.a).left(1)))
			for pin in part.pins:
				var point := Vector2i(int(str(pin).substr(1))-1,LETTERS.find(str(pin).left(1)))
				if rotate:var offset := point-pivot;point=pivot+Vector2i(-offset.y,offset.x)
				else:point+=Vector2i(dx,dy)
				if point.x<0 or point.x>=int(board.rows) or point.y<0 or point.y>=LETTERS.length():return
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
	if preload("res://scripts/breadboard_model.gd").validate(candidate,{},true)!="":return false
	commit();board=candidate;first="";design_changed.emit(board);queue_redraw();return true

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
	var first_hole := LETTERS[grid_rect.position.y]+str(grid_rect.position.x+1)
	var last_hole := LETTERS[mini(grid_rect.end.y-1,11)]+str(grid_rect.end.x)
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
func draw_pcb(part: Dictionary,definition: Dictionary,font: Font) -> void:
	var rect := pcb_rect(part,definition)
	if PCB.active(definition):draw_routed_substrate(definition,rect)
	else:draw_style_box(style(Color(str(definition.footprint.get("color","24775b" if definition.get("package","")=="PCB" else "303b40")))),rect)
	var layout: Dictionary=definition.layout
	var component_scale := 3.0 if board.get("standalone",false) else 1.0
	for index in definition.pins.size():
		if definition.get("package","")!="PCB" or PCB.active(definition):continue
		for child in layout.parts:
			var found := false
			for hole in preload("res://scripts/breadboard_model.gd").pins(child):
				if preload("res://scripts/breadboard_model.gd").node(str(hole),int(layout.rows))==str(definition.pins[index].node):
					var start := at(preload("res://scripts/breadboard_model.gd").pins(part)[index]);var finish := layout_point(str(hole),layout,rect)
					draw_polyline(PackedVector2Array([start,Vector2(start.x,finish.y),finish]),Color("a3ba79"),maxf(1,zoom*component_scale),true);found=true;break
			if found:break
	for wire in (layout.wires if definition.get("package","")=="PCB" and not PCB.active(definition) else []):draw_line(layout_point(str(wire[0]),layout,rect),layout_point(str(wire[1]),layout,rect),Color("bbbd73"),maxf(1,zoom),true)
	for child in layout.parts:
		if definition.get("package","")!="PCB" and str(child.id) not in definition.get("exposed",[]):continue
		var a := pcb_child_point(definition,child,0,rect);var b := pcb_child_end_point(definition,child,rect);var center := pcb_child_center(definition,child,rect)
		draw_line(a,b,Color("bdc4bd"),zoom,true)
		var lit := float(currents.get("board/"+str(part.id)+"/"+str(child.id),0))>.001
		if str(child.type).begins_with("ic:"):_draw_nested(board.get("definitions",{}).get(child.type,{}),_nested_rect(child,layout,rect,definition),"board/"+str(part.id)+"/"+str(child.id)+"/",font,1)
		elif child.type=="spi_display":draw_display("board/"+str(part.id)+"/"+str(child.id),center,zoom*.4*component_scale,font)
		elif str(child.type).begins_with("led"):draw_circle(center,3*zoom*component_scale,Color("ff705c") if lit else Color("74392e"))
		else:draw_rect(Rect2(center-Vector2(4,3)*zoom*component_scale,Vector2(8,6)*zoom*component_scale),Color("27322d") if str(child.type).begins_with("ic:") or child.type=="lv_mcu" else Color("c7b58a"))
		if board.get("standalone",false):draw_string(font,center+Vector2(16,5),str(preload("res://scripts/breadboard_model.gd").catalog(board).get(child.type,{}).get("name",child.type)),HORIZONTAL_ALIGNMENT_LEFT,-1,14,Color("eff5df"))
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
		if part.type in ["button","toggle","pot10k","lv_mcu","native_uno","native_pico","native_nano"]:result.append({"id":"board/"+str(part.id),"type":part.type,"center":native_rect(part).get_center() if part.type in ["native_uno","native_pico","native_nano"] else (at(part.a)+at(part.b))*.5,"radius":20*zoom})
		var definition: Dictionary=board.get("definitions",{}).get(str(part.type),{})
		if not definition.has("layout") or not definition.has("footprint"):continue
		var rect := pcb_rect(part,definition)
		_collect_exposed(definition,rect,"board/"+str(part.id)+"/",result,0)
	return result

func surface_devices() -> Array:
	var result: Array=[]
	for part in board.get("parts",[]):
		var definition: Dictionary=board.get("definitions",{}).get(str(part.type),{})
		if definition.has("layout"):_collect_surface(definition,pcb_rect(part,definition),"board/"+str(part.id)+"/",result,0,float(part.get("surface_rotation",0)))
		else:result.append({"id":"board/"+str(part.id),"type":part.type,"center":(at(part.a)+at(part.b))*.5,"pins":preload("res://scripts/breadboard_model.gd").pins(part).map(func(pin):return at(pin)),"rotation":float(part.get("surface_rotation",0))})
	return result

func _collect_surface(definition: Dictionary,rect: Rect2,prefix: String,result: Array,depth: int,rotation_angle := 0.0) -> void:
	if depth>=8 or not definition.has("layout"):return
	for child in definition.layout.parts:
		if definition.get("package","")!="PCB" and str(child.id) not in definition.get("exposed",[]):continue
		if str(child.type).begins_with("ic:"):_collect_surface(board.get("definitions",{}).get(child.type,{}),_nested_rect(child,definition.layout,rect,definition),prefix+str(child.id)+"/",result,depth+1,rotation_angle+float(child.get("surface_rotation",0)))
		else:result.append({"id":prefix+str(child.id),"type":child.type,"center":pcb_child_center(definition,child,rect),"pins":pcb_child_pins(definition,child,rect),"rotation":rotation_angle+float(child.get("surface_rotation",0))})

func _nested_rect(child: Dictionary,layout: Dictionary,rect: Rect2,definition: Dictionary={}) -> Rect2:
	var a := pcb_child_point(definition,child,0,rect) if not definition.is_empty() else layout_point(str(child.a),layout,rect)
	var b := pcb_child_end_point(definition,child,rect) if not definition.is_empty() else layout_point(str(child.b),layout,rect)
	var extent := Vector2(maxf(absf(a.x-b.x),rect.size.x*.24),maxf(absf(a.y-b.y),rect.size.y*.25))
	extent=extent.min(rect.size*.7)
	return Rect2((a+b)*.5-extent*.5,extent)

func _collect_exposed(definition: Dictionary,rect: Rect2,prefix: String,result: Array,depth: int) -> void:
	if depth>=8 or not definition.has("layout"):return
	for child in definition.layout.parts:
		if definition.get("package","")!="PCB" and str(child.id) not in definition.get("exposed",[]):continue
		var id := prefix+str(child.id)
		if child.type in ["button","toggle","pot10k","lv_mcu","native_uno","native_pico","native_nano"]:
			result.append({"id":id,"type":child.type,"center":pcb_child_center(definition,child,rect),"radius":maxf(4,8*zoom/pow(1.3,depth))})
		elif str(child.type).begins_with("ic:"):
			_collect_exposed(board.get("definitions",{}).get(child.type,{}),_nested_rect(child,definition.layout,rect,definition),id+"/",result,depth+1)

func _draw_nested(definition: Dictionary,rect: Rect2,prefix: String,font: Font,depth: int) -> void:
	if depth>=8 or not definition.has("layout"):return
	if PCB.active(definition):draw_routed_substrate(definition,rect)
	else:draw_style_box(style(Color(str(definition.get("footprint",{}).get("color","24775b" if definition.get("package","")=="PCB" else "303b40")))),rect)
	for child in definition.layout.parts:
		if definition.get("package","")!="PCB" and str(child.id) not in definition.get("exposed",[]):continue
		var id := prefix+str(child.id)
		var center := pcb_child_center(definition,child,rect)
		if str(child.type).begins_with("ic:"):
			_draw_nested(board.get("definitions",{}).get(child.type,{}),_nested_rect(child,definition.layout,rect,definition),id+"/",font,depth+1)
		elif child.type=="spi_display":draw_display(id,center,minf(rect.size.x/160.,rect.size.y/60.)*.5,font)
		else:
			var color := Color("c7b58a")
			if str(child.type).begins_with("led"):color=Color("ff705c") if float(currents.get(id,0))>.001 else Color("74392e")
			draw_circle(center,maxf(3,6*zoom/pow(1.3,depth)),color)

func draw_display(id: String,center: Vector2,scale_factor: float,font: Font) -> void:
	var state: Dictionary=device_states.get(id,{})
	draw_style_box(style(Color("243932")),Rect2(center-Vector2(68,24)*scale_factor,Vector2(136,48)*scale_factor))
	draw_rect(Rect2(center-Vector2(62,19)*scale_factor,Vector2(124,38)*scale_factor),Color("a7c58b") if state.get("powered",false) else Color("3f5147"))
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
func draw_native_board(part: Dictionary,font: Font) -> void:
	var rect := native_rect(part);var model: Dictionary=preload("res://scripts/breadboard_model.gd").catalog(board)[part.type]
	draw_style_box(style(Color("2866a2") if part.type=="native_nano" else Color("277f92") if part.type=="native_uno" else Color("288160")),rect)
	var center := rect.get_center();draw_rect(Rect2(center-Vector2(18,18)*zoom,Vector2(36,36)*zoom),Color("17252b"))
	draw_rect(Rect2(Vector2(rect.position.x-6*zoom,center.y-13*zoom),Vector2(27,26)*zoom),Color("a2b4b8"))
	draw_string(font,center+Vector2(-40,34)*zoom,model.name,HORIZONTAL_ALIGNMENT_LEFT,-1,12,Color("e4f4ea"))
	for index in part.pins.size():
		var point := at(str(part.pins[index]));draw_circle(point,4*zoom,Color("dbbf74"));draw_circle(point,2*zoom,Color("16242c"))
		draw_string(font,point+Vector2(-6,15 if point.y<center.y else -8)*zoom,str(model.pins[index]),HORIZONTAL_ALIGNMENT_LEFT,-1,9,Color("eff8ee"))
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
