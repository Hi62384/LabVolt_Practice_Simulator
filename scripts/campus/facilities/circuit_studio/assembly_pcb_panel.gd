extends Window
const StudioTheme=preload("res://scripts/ui/design_system/theme.gd")
var game: Node
var key: String
var held: Dictionary={}
var control_widgets: Dictionary={}
var pending_control_until: Dictionary={}
var hold_clock:=0.0
var voltage: Label

func open_board(owner_game: Node,invention_key: String,show_window: bool=true) -> void:
	game=owner_game;key=invention_key
	title="Mounted PCB";borderless=true;theme=StudioTheme.create()
	size=Vector2i(560,420);min_size=Vector2i(480,320)
	close_requested.connect(_close)
	game.release_mouse()
	var panel:=PanelContainer.new();panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);add_child(panel)
	var column:=VBoxContainer.new();panel.add_child(column)
	var top:=HBoxContainer.new();column.add_child(top)
	var heading:=Label.new();heading.text="LIVE MOUNTED PCB";heading.size_flags_horizontal=Control.SIZE_EXPAND_FILL;top.add_child(heading)
	var close_button:=Button.new();close_button.text="Close";top.add_child(close_button);close_button.pressed.connect(_close)
	voltage=Label.new();column.add_child(voltage)
	var scroll:=ScrollContainer.new();scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL;column.add_child(scroll)
	var controls:=VBoxContainer.new();scroll.add_child(controls)
	var item: Dictionary=game.invention_world.placed.get(key,{})
	for entry in item.get("pcb_inputs",[]):
		var row:=HBoxContainer.new();controls.add_child(row)
		var label:=Label.new();label.text=str(entry.name);label.size_flags_horizontal=Control.SIZE_EXPAND_FILL;row.add_child(label)
		var id:=str(entry.id)
		var widget: Dictionary={"kind":str(entry.kind)}
		if entry.kind=="button":
			var hold:=Button.new();hold.text="Hold";row.add_child(hold)
			hold.button_down.connect(_begin_hold.bind(id,{}))
			hold.button_up.connect(_end_hold.bind(id))
		elif entry.kind=="toggle":
			var toggle:=Button.new();toggle.text="Toggle";row.add_child(toggle)
			toggle.pressed.connect(_submit.bind(id,{}))
			widget.toggle=toggle
		elif entry.kind=="io_encoder":
			for steps in [-1,1]:
				var turn:=Button.new();turn.text="−" if steps<0 else "+";row.add_child(turn)
				turn.pressed.connect(_submit.bind(id,{"op":"turn","steps":steps}))
		elif entry.kind=="io_selector":
			var select:=OptionButton.new();row.add_child(select)
			for position in 3:select.add_item(str(position))
			select.item_selected.connect(_selector_changed.bind(id))
			widget.selector=select
		elif entry.kind=="io_keypad":
			var keys:=HFlowContainer.new();controls.add_child(keys)
			for number in 12:
				var key_button:=Button.new();key_button.text=["1","2","3","4","5","6","7","8","9","*","0","#"][number];keys.add_child(key_button)
				key_button.button_down.connect(_begin_hold.bind(id,{"op":"key","key":number,"pressed":true}))
				key_button.button_up.connect(_end_hold.bind(id,{"key":number}))
		elif entry.kind in ["io_slider","io_joystick","xpt2046"]:
			var x_label:=Label.new();x_label.text="Level" if entry.kind=="io_slider" else "X";row.add_child(x_label)
			var x:=HSlider.new();x.min_value=0;x.max_value=1;x.step=.05;x.value=.5;x.custom_minimum_size.x=130;row.add_child(x)
			# A one-axis slider must not allocate an unparented second Control.
			# Nodes are not RefCounted and would leak on every panel opening.
			var y: HSlider=null
			widget.x=x
			if entry.kind!="io_slider":
				y=HSlider.new();y.min_value=0;y.max_value=1;y.step=.05;y.value=.5;y.custom_minimum_size.x=130
				widget.y=y
				var y_label:=Label.new();y_label.text="Y";row.add_child(y_label)
				row.add_child(y)
			# Bind each row's device and sliders explicitly. Loop-local closures
			# may otherwise end up observing another device's moving values.
			x.value_changed.connect(_axes_changed.bind(str(entry.kind),id,x,y))
			if entry.kind!="io_slider":y.value_changed.connect(_axes_changed.bind(str(entry.kind),id,x,y))
			if entry.kind=="io_joystick":
				# A single pointer must be able to hold the push-button while moving
				# both joystick axes. Release recenters the spring-loaded stick.
				var press:=Button.new();press.text="Press on/off";press.toggle_mode=true;row.add_child(press)
				widget.press=press
				press.toggled.connect(func(pressed: bool):
					if pressed:_begin_hold(id,{"op":"press","pressed":true})
					else:
						_end_hold(id)
						x.set_value_no_signal(.5)
						y.set_value_no_signal(.5))
			elif entry.kind=="xpt2046":
				# A mouse cannot drag the coordinate sliders while holding a button.
				# Toggle contact on/off so one pointer can perform touch gestures.
				var touch:=Button.new();touch.text="Touch on/off";touch.toggle_mode=true;row.add_child(touch)
				widget.press=touch
				touch.toggled.connect(func(pressed: bool):
					if pressed:_begin_hold(id,{"op":"touch","x":x.value,"y":y.value,"pressed":true})
					else:_end_hold(id))
		elif entry.kind in ["battery_adjustable","battery_generator","battery_generator_adjustable"]:
			var settings: Array=["wave"] if entry.kind=="battery_generator" else ["voltage"] if entry.kind=="battery_adjustable" else ["voltage","frequency","wave"]
			for setting in settings:
				var setting_row:=row if settings.size()==1 else HBoxContainer.new()
				if settings.size()!=1:controls.add_child(setting_row)
				var setting_name: String={"voltage":"Voltage","frequency":"Frequency","wave":"Waveform"}[setting]
				for reverse in [true,false]:
					var adjust:=Button.new()
					adjust.text=setting_name+(" −" if reverse else " +")
					adjust.tooltip_text={"voltage":"Change output by 0.5 V","frequency":"Change frequency by 1 Hz","wave":"Cycle waveform"}[setting]
					setting_row.add_child(adjust)
					adjust.pressed.connect(_adjust.bind(id,reverse,setting))
			var source_readout:=Label.new();source_readout.text="";controls.add_child(source_readout)
			widget.readout=source_readout
		else:
			for reverse in [true,false]:
				var adjust:=Button.new();adjust.text="−" if reverse else "+";row.add_child(adjust)
				adjust.pressed.connect(_adjust.bind(id,reverse))
		control_widgets[id]=widget
	if item.get("pcb_inputs",[]).is_empty():
		var label:=Label.new();label.text="This PCB has no manual inputs. Its circuit and firmware run while placed.";controls.add_child(label)
	_update_voltage()
	_sync_controls()
	# Headless test fixtures can exercise real controls without creating
	# a renderer-backed subwindow; normal gameplay always opens the window.
	if show_window:popup_centered()

func _update_voltage() -> void:
	if not is_instance_valid(voltage):return
	var item: Dictionary=game.invention_world.placed.get(key,{})
	if item.is_empty():voltage.text="PCB is no longer placed.";return
	if not str(item.get("pcb_error","")).is_empty():voltage.text="Circuit error: "+str(item.pcb_error).left(100);return
	voltage.text="5 V supply · A %.2f V · B %.2f V"%[float(item.pcb_voltage.A),float(item.pcb_voltage.B)]

func _mark_pending(id: String) -> void:
	pending_control_until[id]=Time.get_ticks_msec()+350

func _selector_changed(position: int,id: String) -> void:
	_submit(id,{"op":"select","position":position})

func _sync_controls() -> void:
	if not is_instance_valid(game):return
	var item: Dictionary=game.invention_world.placed.get(key,{})
	var states: Dictionary=item.get("pcb_controls",{})
	var now:=Time.get_ticks_msec()
	for id in control_widgets:
		if not states.get(id) is Dictionary or states[id].is_empty():continue
		if now<int(pending_control_until.get(id,0)):continue
		var state: Dictionary=states[id]
		var widget: Dictionary=control_widgets[id]
		if widget.has("selector"):
			var select: OptionButton=widget.selector
			var position:=clampi(int(state.get("position",0)),0,select.item_count-1)
			if select.selected!=position:select.select(position)
		if widget.has("x") and not held.has(str(id)+":"):
			var slider: HSlider=widget.x
			slider.set_value_no_signal(clampf(float(state.get("x",state.get("setting",.5))),0.0,1.0))
			if widget.kind!="io_slider":
				var vertical: HSlider=widget.y
				vertical.set_value_no_signal(clampf(float(state.get("y",.5)),0.0,1.0))
		if widget.has("press") and not held.has(str(id)+":"):
			widget.press.set_pressed_no_signal(bool(state.get("pressed",false)))
		if widget.has("toggle"):widget.toggle.text="On" if state.get("pressed",false) else "Off"
		if widget.has("readout"):
			var v: float=float(state.get("source_voltage",5.0))
			var hz: float=float(state.get("source_frequency",60.0))
			widget.readout.text="%.1f V · %.1f Hz · wave %d"%[v,hz,int(state.get("source_wave",0))] if widget.kind!="battery_adjustable" else "%.1f V DC"%v

func _submit(id: String,command: Dictionary) -> void:
	_mark_pending(id)
	game.invention_world.request_pcb_input(key,id,true,false,command)

func _adjust(id: String,reverse: bool,source_adjust: String="") -> void:
	_mark_pending(id)
	var command: Dictionary={"source_adjust":source_adjust} if not source_adjust.is_empty() else {}
	game.invention_world.request_pcb_input(key,id,true,reverse,command)

func _begin_hold(id: String,command: Dictionary) -> void:
	var token:=id+":"+str(command.get("key",""))
	if held.has(token):return
	held[token]={"id":id,"command":command.duplicate(true)}
	_mark_pending(id)
	hold_clock=0.0
	game.invention_world.request_pcb_input(key,id,true,false,command)

func _axes_changed(_value: float,kind: String,id: String,x: HSlider,y: HSlider) -> void:
	match kind:
		"io_slider":_submit(id,{"op":"move","x":x.value})
		"io_joystick":_submit(id,{"op":"move","x":x.value,"y":y.value})
		"xpt2046":_move_touch(id,x.value,y.value)

func _move_touch(id: String,x: float,y: float) -> void:
	var token:=id+":"
	if not held.has(token):return
	var command: Dictionary={"op":"touch","x":x,"y":y,"pressed":true}
	var active: Dictionary=held[token]
	active.command=command.duplicate(true)
	held[token]=active
	hold_clock=0.0
	game.invention_world.request_pcb_input(key,id,true,false,command)

func _end_hold(id: String,command: Dictionary={}) -> void:
	var token:=id+":"+str(command.get("key",""))
	if not held.has(token):return
	var release: Dictionary=held[token].command.duplicate(true)
	if str(release.get("op","")) in ["touch","press"]:release={"op":"release"}
	elif release.has("pressed"):release.pressed=false
	game.invention_world.request_pcb_input(key,id,false,false,release)
	_mark_pending(id)
	held.erase(token)

func _process(delta: float) -> void:
	if not is_instance_valid(game):return
	_update_voltage()
	_sync_controls()
	if held.is_empty():return
	hold_clock+=delta
	if hold_clock>=.25:
		hold_clock=0.0
		for entry in held.values():game.invention_world.request_pcb_input(key,str(entry.id),true,false,entry.command)

func _release_held_inputs() -> void:
	# A different PCB can replace this panel with queue_free() instead of Close.
	# Release the old hardware inputs on either path, including teardown.
	if is_instance_valid(game) and is_instance_valid(game.invention_world):
		for entry in held.values():_end_hold(str(entry.id),entry.command)
	held.clear()

func _notification(what: int) -> void:
	if what==NOTIFICATION_PREDELETE:_release_held_inputs()

func _close() -> void:
	_release_held_inputs()
	hide();queue_free()
	if is_instance_valid(game) and game.front.in_game:game.capture()

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode==KEY_ESCAPE:_close()
