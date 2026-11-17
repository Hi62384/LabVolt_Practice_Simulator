extends Window
const StudioTheme=preload("res://scripts/ui/design_system/theme.gd")
var game: Node
var key: String
var held: Dictionary={}
var hold_clock:=0.0
var voltage: Label

func open_board(owner_game: Node,invention_key: String) -> void:
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
		if entry.kind=="button":
			var hold:=Button.new();hold.text="Hold";row.add_child(hold)
			hold.button_down.connect(_begin_hold.bind(id,{}))
			hold.button_up.connect(_end_hold.bind(id))
		elif entry.kind=="toggle":
			var toggle:=Button.new();toggle.text="Toggle";row.add_child(toggle)
			toggle.pressed.connect(_submit.bind(id,{}))
		elif entry.kind=="io_encoder":
			for steps in [-1,1]:
				var turn:=Button.new();turn.text="−" if steps<0 else "+";row.add_child(turn)
				turn.pressed.connect(_submit.bind(id,{"op":"turn","steps":steps}))
		elif entry.kind=="io_selector":
			var select:=OptionButton.new();row.add_child(select)
			for position in 3:select.add_item(str(position))
			select.item_selected.connect(func(position: int):_submit(id,{"op":"select","position":position}))
		elif entry.kind=="io_keypad":
			var keys:=HFlowContainer.new();controls.add_child(keys)
			for number in 12:
				var key_button:=Button.new();key_button.text=str(number+1);keys.add_child(key_button)
				key_button.button_down.connect(_begin_hold.bind(id,{"op":"key","key":number,"pressed":true}))
				key_button.button_up.connect(_end_hold.bind(id,{"key":number}))
		elif entry.kind in ["io_slider","io_joystick","xpt2046"]:
			var x:=HSlider.new();x.min_value=0;x.max_value=1;x.step=.05;x.value=.5;x.custom_minimum_size.x=130;row.add_child(x)
			var y:=HSlider.new();y.min_value=0;y.max_value=1;y.step=.05;y.value=.5;y.custom_minimum_size.x=130
			if entry.kind!="io_slider":row.add_child(y)
			var move:=func(_changed: bool):
				if entry.kind=="io_slider":_submit(id,{"op":"move","x":x.value})
				elif entry.kind=="io_joystick":_submit(id,{"op":"move","x":x.value,"y":y.value})
			x.drag_ended.connect(move)
			if entry.kind!="io_slider":y.drag_ended.connect(move)
			if entry.kind in ["io_joystick","xpt2046"]:
				var press:=Button.new();press.text="Press" if entry.kind=="io_joystick" else "Touch";row.add_child(press)
				press.button_down.connect(func():_begin_hold(id,{"op":"press","pressed":true} if entry.kind=="io_joystick" else {"op":"touch","x":x.value,"y":y.value,"pressed":true}))
				press.button_up.connect(_end_hold.bind(id))
		else:
			for reverse in [true,false]:
				var adjust:=Button.new();adjust.text="−" if reverse else "+";row.add_child(adjust)
				adjust.pressed.connect(_adjust.bind(id,reverse))
	if item.get("pcb_inputs",[]).is_empty():
		var label:=Label.new();label.text="This PCB has no manual inputs. Its circuit and firmware run while placed.";controls.add_child(label)
	_update_voltage()
	popup_centered()

func _update_voltage() -> void:
	if not is_instance_valid(voltage):return
	var item: Dictionary=game.invention_world.placed.get(key,{})
	if item.is_empty():voltage.text="PCB is no longer placed.";return
	if not str(item.get("pcb_error","")).is_empty():voltage.text="Circuit error: "+str(item.pcb_error).left(100);return
	voltage.text="5 V supply · A %.2f V · B %.2f V"%[float(item.pcb_voltage.A),float(item.pcb_voltage.B)]

func _submit(id: String,command: Dictionary) -> void:
	game.invention_world.request_pcb_input(key,id,true,false,command)

func _adjust(id: String,reverse: bool) -> void:
	game.invention_world.request_pcb_input(key,id,true,reverse)

func _begin_hold(id: String,command: Dictionary) -> void:
	var token:=id+":"+str(command.get("key",""))
	if held.has(token):return
	held[token]={"id":id,"command":command.duplicate(true)}
	hold_clock=0.0
	game.invention_world.request_pcb_input(key,id,true,false,command)

func _end_hold(id: String,command: Dictionary={}) -> void:
	var token:=id+":"+str(command.get("key",""))
	if not held.has(token):return
	var release: Dictionary=held[token].command.duplicate(true)
	if str(release.get("op",""))=="touch":release={"op":"release"}
	elif release.has("pressed"):release.pressed=false
	game.invention_world.request_pcb_input(key,id,false,false,release)
	held.erase(token)

func _process(delta: float) -> void:
	if not is_instance_valid(game):return
	_update_voltage()
	if held.is_empty():return
	hold_clock+=delta
	if hold_clock>=.25:
		hold_clock=0.0
		for entry in held.values():game.invention_world.request_pcb_input(key,str(entry.id),true,false,entry.command)

func _close() -> void:
	if is_instance_valid(game):
		for entry in held.values():_end_hold(str(entry.id),entry.command)
	hide();queue_free()
	if is_instance_valid(game) and game.front.in_game:game.capture()

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode==KEY_ESCAPE:_close()
