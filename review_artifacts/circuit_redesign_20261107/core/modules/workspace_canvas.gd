extends "res://scripts/breadboard_canvas.gd"
signal selection_updated(ids: Array)
var fitted:=false
var last_rows:=0
var placement_turns:=0
var selected_wire:=-1
var message:=""
var context: PopupMenu
var wire_context: PopupMenu
var wire_clipboard: Array=[]
const Placement=preload("res://scripts/electronics/circuit_workspace/placement.gd")

func _ready() -> void:
	super._ready()
	set_meta("workspace_embedded",true)
	custom_minimum_size=Vector2(280,240);focus_mode=Control.FOCUS_ALL
	resized.connect(func():if not fitted:fit_board())
	call_deferred("initial_fit")
	context=PopupMenu.new();add_child(context)
	wire_context=PopupMenu.new();add_child(wire_context)
	wire_context.id_pressed.connect(func(id):
		if id==1:copy_selected()
		elif id==2:delete_selected()
	)
	for title in ["Rotate","Copy","Duplicate","Delete","Fit selection"]:context.add_item(title)
	context.id_pressed.connect(func(id):
		match id:
			0:transform_selected(0,0,true)
			1:copy_selected()
			2:copy_selected();paste_selected()
			3:delete_selected()
			4:fit_selection()
	)

func initial_fit() -> void:
	if not fitted:fit_board()

func fit_board() -> void:
	if size.x<=0 or size.y<=0:return
	if board.get("standalone",false):fitted=true;queue_redraw();return
	var extent:=Vector2(73+maxi(0,int(board.rows)-1)*23,377)
	zoom=clampf(minf((size.x-48)/extent.x,(size.y-48)/extent.y),.15,4)
	pan=(size-extent*zoom)*.5
	fitted=true;last_rows=int(board.rows);queue_redraw()

func fit_selection() -> void:
	if board.get("standalone",false):fit_board();return
	var points: Array[Vector2]=[]
	for part in board.parts:
		if part.id in selected:
			for hole in preload("res://scripts/breadboard_model.gd").pins(part):points.append((at(hole)-pan)/zoom)
	if points.is_empty():return
	var bounds:=Rect2(points[0],Vector2.ONE)
	for point in points:bounds=bounds.expand(point)
	bounds=bounds.grow(35)
	zoom=clampf(minf(size.x/bounds.size.x,size.y/bounds.size.y),.15,4)
	pan=size*.5-bounds.get_center()*zoom;queue_redraw()

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_MIDDLE:
		dragging=event.pressed;accept_event();return
	if event is InputEventMouseMotion and dragging:
		pan+=event.relative;queue_redraw();accept_event();return
	if not read_only and event is InputEventMouseButton and event.pressed:
		if event.button_index==MOUSE_BUTTON_RIGHT and first=="" and selected_wire>=0 and selected_wire<board.wires.size():
			var wire: Array=board.wires[selected_wire]
			wire_context.clear();wire_context.add_item(str(wire[0])+" ↔ "+str(wire[1]),0);wire_context.set_item_disabled(0,true);wire_context.add_item("Copy",1);wire_context.add_item("Delete",2)
			wire_context.position=Vector2i(get_global_mouse_position());wire_context.popup();accept_event();return
		if event.button_index==MOUSE_BUTTON_RIGHT and first=="" and not selected.is_empty():
			context.position=Vector2i(get_global_mouse_position());context.popup();accept_event();return
		if event.button_index==MOUSE_BUTTON_LEFT and selected_type not in ["select","wire","remove","interact","probe+","probe-"]:
			var hole: String=hole_at(event.position)
			if first=="":first=hole
			else:
				var trial: Dictionary=Placement.candidate(board,selected_type,first,hole,placement_turns)
				message=str(trial.error)
				if message=="":
					commit();trial.part.id=str(Time.get_ticks_usec());board=trial.board;first="";design_changed.emit(board)
			queue_redraw();accept_event();return
		if event.button_index==MOUSE_BUTTON_LEFT and selected_type=="select" and hovered_wire>=0:
			selected_wire=hovered_wire;selected.clear();selection_updated.emit([]);queue_redraw();accept_event();return
	if event is InputEventMouseButton and event.pressed:
		grab_focus()
		if event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN] and selected_type!="interact":
			var anchor: Vector2=(event.position-pan)/zoom
			zoom=clampf(zoom*(1.12 if event.button_index==MOUSE_BUTTON_WHEEL_UP else 1/1.12),.15,4)
			pan=event.position-anchor*zoom;queue_redraw();accept_event();return
	var old_selection:=selected.duplicate()
	super._gui_input(event)
	if not selected.is_empty():selected_wire=-1
	if old_selection!=selected:selection_updated.emit(selected.duplicate())
	if int(board.rows)!=last_rows:fit_board()

func delete_selected() -> void:
	if read_only:return
	if selected_wire>=0 and selected_wire<board.wires.size():
		commit();board.wires.remove_at(selected_wire);selected_wire=-1;design_changed.emit(board);queue_redraw()
	else:super.delete_selected()
	selection_updated.emit(selected.duplicate())

func undo() -> void:
	if read_only:return
	super.undo();refresh_selection()

func redo() -> void:
	if read_only:return
	super.redo();refresh_selection()

func refresh_selection() -> void:
	var live: Array=board.parts.map(func(part):return part.id)
	selected=selected.filter(func(id):return id in live)
	selected_wire=-1;selection_updated.emit(selected.duplicate());queue_redraw()

func copy_selected() -> void:
	if selected_wire>=0 and selected_wire<board.wires.size():wire_clipboard=board.wires[selected_wire].duplicate();clipboard=[]
	else:wire_clipboard=[];super.copy_selected()

func paste_selected() -> bool:
	if read_only:return false
	if wire_clipboard.is_empty():
		var success: bool=super.paste_selected();selection_updated.emit(selected.duplicate());return success
	for offset in range(1,int(board.rows)):
		var wire: Array=[]
		for hole in wire_clipboard:wire.append(str(hole).left(1)+str(int(str(hole).substr(1))+offset))
		var candidate: Dictionary=board.duplicate(true);candidate.wires.append(wire)
		if preload("res://scripts/breadboard_model.gd").validate(candidate,{},true)=="":
			commit();board=candidate;selected_wire=board.wires.size()-1;design_changed.emit(board);queue_redraw();return true
	return false

func rotate_or_preview() -> void:
	if selected_type not in ["select","wire","remove","interact","probe+","probe-"]:
		placement_turns=posmod(placement_turns+1,4);queue_redraw()
	else:transform_selected(0,0,true)

func resize_board(rows: int) -> bool:
	if read_only:return false
	var changed: bool=super.resize_board(rows)
	if changed:fit_board()
	return changed

func _draw() -> void:
	super._draw()
	if first=="" and hovered!="" and selected_type not in ["wire","select","remove","interact","probe+","probe-"]:
		var other: String=("F" if hovered.left(1) in "PNABCDE" else "A")+hovered.substr(1)
		draw_placement(Placement.candidate(board,selected_type,hovered,other,placement_turns))
	if hovered!="":
		draw_arc(at(hovered),10*zoom,0,TAU,24,Color("8de4cc"),2,true)
	if first!="":
		draw_line(at(first),get_local_mouse_position(),Color("8de4cc"),2,true)
		if selected_type not in ["wire","select","remove","interact","probe+","probe-"]:
			var trial: Dictionary=Placement.candidate(board,selected_type,first,hovered,placement_turns)
			draw_placement(trial)
			var tint:=Color("8de4cc") if trial.error=="" else Color("ffb6b9")
			if trial.has("part"):
				for hole in preload("res://scripts/breadboard_model.gd").pins(trial.part):draw_circle(at(str(hole)),7*zoom,tint)
			var occupied: Dictionary={}
			for part in board.parts:
				for pin in preload("res://scripts/breadboard_model.gd").pins(part):occupied[str(pin)]=true
			for row in range(1,int(board.rows)+1):
				for col in LETTERS:
					var hole: String=col+str(row)
					if not occupied.has(hole):draw_arc(at(hole),5*zoom,0,TAU,12,Color("8de4cc",.25),1)
	if selected_wire>=0 and selected_wire<board.wires.size():
		var wire: Array=board.wires[selected_wire];draw_line(at(wire[0]),at(wire[1]),Color("8de4cc"),5,true)
	if moving:
		var offset: Vector2=get_local_mouse_position()-move_start
		var trial: Dictionary=Placement.translated(board,selected,roundi(offset.x/(23*zoom)),roundi(offset.y/(23*zoom)))
		var tint:=Color("8de4cc",.7) if trial.error=="" else Color("ffb6b9",.7)
		for part in board.parts:
			if part.id in selected:draw_line(at(part.a)+offset,at(part.b)+offset,tint,8*zoom,true)

func draw_placement(trial: Dictionary) -> void:
	var tint:=Color("8de4cc") if trial.error=="" else Color("ffb6b9")
	if trial.has("part"):
		var part: Dictionary=trial.part
		var center: Vector2=(at(part.a)+at(part.b))*.5
		for pin in preload("res://scripts/breadboard_model.gd").pins(part):
			draw_line(at(str(pin)),center,tint,2,true)
			draw_arc(at(str(pin)),7*zoom,0,TAU,16,tint,2,true)
		draw_rect(Rect2(center-Vector2(14,9)*zoom,Vector2(28,18)*zoom),tint,false,2)
	var label: String=str(preload("res://scripts/breadboard_model.gd").catalog(board).get(selected_type,{}).get("name",selected_type)) if trial.error=="" else str(trial.error)
	draw_string(ThemeDB.fallback_font,get_local_mouse_position()+Vector2(16,-14),label,HORIZONTAL_ALIGNMENT_LEFT,360,14,tint)
