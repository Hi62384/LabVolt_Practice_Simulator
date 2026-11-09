extends Control
## Same renderer in 2D and a physical-board SubViewport. Never mutates electrical state.
signal command_requested(command: Dictionary)
const Controls=preload("res://scripts/io_devices/controls.gd")
var kind := ""
var live := {}
var control := {}
var interact := false
var held_key := -1
var dragging := false
var encoder_drag := 0.0
var pending: Array=[]
var awaiting_revision := -1

func present(device_kind: String,state: Dictionary,input: Dictionary={}) -> void:
	if device_kind=="hd44780_20x4":device_kind="hd44780"
	var incoming: Dictionary=input if not input.is_empty() else state.get("control",{})
	if kind!=device_kind or live!=state or control!=incoming:
		kind=device_kind;live=state.duplicate(true);control=incoming.duplicate(true)
		queue_redraw()
	if awaiting_revision>=0 and int(control.get("revision",0))>awaiting_revision:awaiting_revision=-1
	pump()

## Serialize each local gesture behind host acknowledgments; releases survive latency.
func submit(command: Dictionary) -> void:
	if not pending.is_empty() and command.get("op","")=="move" and pending[-1].get("op","")=="move":pending[-1]=command.duplicate(true)
	else:pending.append(command.duplicate(true))
	pump()

func pump() -> void:
	if awaiting_revision>=0 or pending.is_empty():return
	var command: Dictionary=pending.pop_front()
	awaiting_revision=int(control.get("revision",0));command.revision=awaiting_revision
	command_requested.emit(command)

## Call for a rejected request as well, carrying the current authoritative controls.
func acknowledge(input: Dictionary) -> void:
	control=input.duplicate(true);awaiting_revision=-1;queue_redraw();pump()

func _gui_input(event: InputEvent) -> void:
	if not interact:return
	var point := Vector2.ZERO
	if event is InputEventMouse:point=event.position/size
	var revision := int(control.get("revision",0))
	if event is InputEventMouseButton:
		if event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN] and event.pressed and kind=="io_encoder":
			submit({"op":"turn","steps":1 if event.button_index==MOUSE_BUTTON_WHEEL_UP else -1,"revision":revision});accept_event()
		elif event.button_index==MOUSE_BUTTON_MIDDLE and kind=="io_joystick":
			submit({"op":"press","pressed":event.pressed,"revision":revision});accept_event()
		elif event.button_index==MOUSE_BUTTON_LEFT:
			if kind=="io_keypad":
				if event.pressed:held_key=clampi(int(point.y*4),0,3)*3+clampi(int(point.x*3),0,2)
				if held_key>=0:submit({"op":"key","key":held_key,"pressed":event.pressed,"revision":revision})
				if not event.pressed:held_key=-1
			else:
				dragging=event.pressed
				if kind=="io_encoder":encoder_drag=0.
				var command := Controls.pointer(kind,point,event.pressed,revision)
				if not command.is_empty():submit(command)
			accept_event()
	elif event is InputEventMouseMotion and dragging and kind in ["io_slider","io_joystick","xpt2046"]:
		submit(Controls.pointer(kind,point,true,revision));accept_event()
	elif event is InputEventMouseMotion and dragging and kind=="io_encoder":
		encoder_drag-=event.relative.y
		var steps := clampi(int(encoder_drag/10.),-16,16)
		if steps!=0:
			encoder_drag-=steps*10.;submit({"op":"turn","steps":steps,"revision":revision})
		accept_event()

## Call on lost capture, stow, disconnect or leaving interact mode.
func release_capture() -> void:
	var revision := int(control.get("revision",0))
	if kind=="io_keypad" and held_key>=0:submit({"op":"key","key":held_key,"pressed":false,"revision":revision})
	elif kind in ["io_joystick","xpt2046"]:submit({"op":"release","revision":revision})
	held_key=-1;dragging=false

func _draw() -> void:
	var scale_to := size/Vector2(256,256)
	draw_set_transform(Vector2.ZERO,0,scale_to)
	draw_style_box(panel(),Rect2(0,0,256,256))
	var white := Color("d8dfdf")
	if preload("res://scripts/commercial_devices/catalog.gd").supports(kind):
		preload("res://scripts/commercial_devices/display_surface.gd").draw(self,kind,live)
		return
	match kind:
		"spi_display":
			var powered: bool=live.get("powered",false)
			draw_rect(Rect2(12,18,232,220),Color("a7c58b") if powered else Color("3f5147"))
			var cells: Array=live.get("cells",[])
			if powered and cells.size()==32:
				for row in 2:
					var line := ""
					for col in 16:line+=String.chr(int(cells[row*16+col]))
					draw_string(ThemeDB.fallback_font,Vector2(18,106+row*88),line,HORIZONTAL_ALIGNMENT_LEFT,220,20,Color("203625"))
		"seven_segment":
			var levels: Array=live.get("levels",[0.,0.,0.,0.,0.,0.,0.,0.])
			var segments := [
				[Vector2(84,40),Vector2(164,40)], [Vector2(176,50),Vector2(176,114)],
				[Vector2(176,140),Vector2(176,204)], [Vector2(84,216),Vector2(164,216)],
				[Vector2(72,140),Vector2(72,204)], [Vector2(72,50),Vector2(72,114)],
				[Vector2(84,128),Vector2(164,128)],
			]
			for segment in segments.size():
				draw_line(segments[segment][0],segments[segment][1],Color("4a2527").lerp(Color("ff5149"),float(levels[segment])),12,true)
			draw_circle(Vector2(205,216),8,Color("4a2527").lerp(Color("ff5149"),float(levels[7])))
		"io_keypad":
			for key in 12:
				var rect := Rect2((key%3)*85+5,(key/3)*64+4,75,55)
				draw_rect(rect,Color("c17643") if int(control.get("keys",0))&(1<<key) else Color("3e5159"))
				draw_string(ThemeDB.fallback_font,rect.position+Vector2(26,36),str(["1","2","3","4","5","6","7","8","9","*","0","#"][key]),HORIZONTAL_ALIGNMENT_LEFT,-1,24,white)
		"io_encoder":
			draw_circle(Vector2(128,128),75,Color("63757c"))
			var angle := float(control.get("detent",0))*TAU/24.
			draw_line(Vector2(128,128),Vector2(128,128)+Vector2(sin(angle),-cos(angle))*65,white,8)
		"io_slider":
			draw_line(Vector2(24,128),Vector2(232,128),Color("0c1218"),14)
			draw_rect(Rect2(16+208*float(control.get("x",.5)),93,16,70),white)
		"io_joystick":
			draw_circle(Vector2(128,128),100,Color("101c25"))
			draw_circle(Vector2(48+160*float(control.get("x",.5)),48+160*float(control.get("y",.5))),30,Color("e18e50") if control.get("pressed",false) else white)
		"io_selector":
			for position in 3:draw_rect(Rect2(8+position*83,95,73,65),Color("e18e50") if position==int(control.get("position",0)) else Color("44535a"))
		"io_rgb":
			var levels: Array=live.get("levels",[0.,0.,0.])
			draw_circle(Vector2(128,128),75,Color(float(levels[0]),float(levels[1]),float(levels[2])))
		"io_bar","io_matrix":
			var levels: Array=live.get("levels",[])
			for index in (16 if kind=="io_matrix" else 4):
				var level := float(levels[index]) if index<levels.size() else 0.
				var center := Vector2(38+(index%4)*60,38+(index/4)*60) if kind=="io_matrix" else Vector2(38+index*60,128)
				draw_circle(center,23,Color(.1+.9*level,.03+level*.15,.02))
		"io_pixels":
			var pixels: Array=live.get("pixels",[])
			for index in 8:
				var color := Color("101318")
				if live.get("powered",false) and pixels.size()==24:color=Color(float(pixels[index*3])/255.,float(pixels[index*3+1])/255.,float(pixels[index*3+2])/255.)
				draw_rect(Rect2(6+(index%4)*62,65+(index/4)*68,55,55),color)
		"io_graphic":
			var cells: Array=live.get("cells",[])
			for y in 16:
				for x in 16:
					var on: bool=live.get("powered",false) and cells.size()==32 and (int(cells[y*2+x/8])&(128>>(x%8)))!=0
					draw_rect(Rect2(8+x*15,8+y*15,13,13),Color("8ee8da") if on else Color("08151c"))
		"io_motor","io_vibration","io_servo":
			draw_circle(Vector2(128,128),70,Color("657a80"))
			var angle := deg_to_rad(float(live.get("angle",90))) if kind=="io_servo" else float(live.get("angle",0))
			draw_line(Vector2(128,128),Vector2(128,128)+Vector2(cos(angle),sin(angle))*80,Color("efb76d"),12)
			if kind=="io_vibration":draw_circle(Vector2(128,128)+Vector2(cos(angle),sin(angle))*50,16,white)
		"io_relay":
			draw_line(Vector2(35,128),Vector2(200,190) if live.get("closed",false) else Vector2(200,65),white,10)
			for point in [Vector2(35,128),Vector2(210,65),Vector2(210,190)]:draw_circle(point,12,Color("e18e50"))
		"io_bridge":
			draw_string(ThemeDB.fallback_font,Vector2(32,130),"DRIVER ON" if live.get("powered",false) else "NO POWER",HORIZONTAL_ALIGNMENT_LEFT,-1,22,white)

func panel() -> StyleBoxFlat:
	var style := StyleBoxFlat.new();style.bg_color=Color("26343d");style.corner_radius_top_left=12;style.corner_radius_top_right=12;style.corner_radius_bottom_left=12;style.corner_radius_bottom_right=12
	return style
