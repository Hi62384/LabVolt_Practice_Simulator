extends Window
const Model=preload("res://scripts/campus/facilities/circuit_studio/assembly_model.gd")
const StudioTheme=preload("res://scripts/ui/design_system/theme.gd")
const PCBRun=preload("res://scripts/campus/facilities/circuit_studio/assembly_pcb_runtime.gd")
var game: Node
var profile: RefCounted
var body: VBoxContainer
var frame: VBoxContainer
var notice: Label
var draft: Dictionary={}
var editing_id: String=""
var page: String="library"
var name_field: LineEdit
var mode_a: OptionButton
var mode_b: OptionButton
var drive_a: OptionButton
var drive_b: OptionButton
var part_kind: OptionButton
var part_x: SpinBox
var part_y: SpinBox
var part_z: SpinBox
var part_control: OptionButton
var part_ref: OptionButton
var pin_row: VBoxContainer
var pin_choices: Dictionary={}
var selected_part := -1
var viewport_tool := "select"
var undo_stack: Array[Dictionary]=[]
var redo_stack: Array[Dictionary]=[]
var camera_state: Dictionary={}
var placement_kind := "wood_frame"
var test_view: Control
var test_status: Label
var test_pcb: RefCounted
var test_parts: Array=[]
var test_switches: Dictionary={}
var test_output: Dictionary={}
var test_clock := 0.0
var discard_prompt: ConfirmationDialog
var discard_action: Callable = Callable()
var remove_prompt: ConfirmationDialog
var remove_target := ""
var copies_prompt: ConfirmationDialog
var copies_target := ""
var validation_refresh: Callable = Callable()

func open_station(owner_game: Node) -> void:
	game=owner_game;profile=game.electronics.profile
	title="Invention Assembly Studio";borderless=true;theme=StudioTheme.create()
	var available:=Vector2i(game.get_viewport().get_visible_rect().size)
	size=Vector2i(maxi(680,mini(1080,available.x-50)),maxi(490,mini(780,available.y-70)))
	min_size=Vector2i(650,470)
	close_requested.connect(_close)
	game.release_mouse()
	game.invention_world.placement_finished.connect(func(_blueprint_id: String,message: String):
		if page=="library":notice.text=message)
	var authority=game.electronics_trade.authority
	if is_instance_valid(authority):
		authority.operation_result.connect(func(_operation: String,_result: Dictionary):
			if is_instance_valid(self) and page=="library":_library())
	_library()
	popup_centered()

func _close() -> void:
	if _has_unsaved_changes():
		_prompt_discard(_close_now)
	else:
		_close_now()

func _close_now() -> void:
	hide();queue_free()
	if is_instance_valid(game) and game.front.in_game:game.capture()

# Closing the editor or returning to the library must never silently erase a
# draft. Include changes visible in the inspector, not only applied changes.
func _has_unsaved_changes() -> bool:
	if page not in ["editor","test"]:return false
	if editing_id.is_empty():return true
	var stored: Dictionary=profile.data.get("inventions",{}).get(editing_id,{})
	if stored.is_empty():return true
	var candidate: Dictionary=draft.duplicate(true)
	if page=="editor" and is_instance_valid(name_field):
		candidate.name=name_field.text.strip_edges()
		candidate.controls={"A":"toggle" if mode_a.selected==1 else "hold","B":"toggle" if mode_b.selected==1 else "hold"}
		candidate.drive={"A":["manual","pcb","both"][drive_a.selected],"B":["manual","pcb","both"][drive_b.selected]}
		if selected_part>=0 and selected_part<candidate.parts.size() and is_instance_valid(part_kind) and part_kind.selected>=0:
			var part: Dictionary=candidate.parts[selected_part]
			part.x=int(part_x.value)
			part.y=int(part_y.value)
			part.z=int(part_z.value)
			part.control="" if part_control.selected==0 else "A" if part_control.selected==1 else "B"
			var palette_kind:=str(part_kind.get_item_metadata(part_kind.selected))
			if palette_kind==str(part.type):
				if part.type in ["pcb","nested"] and part_ref.selected>=0:
					part.ref=str(part_ref.get_item_metadata(part_ref.selected))
				if part.type=="pcb" and pin_choices.size()==4:
					part.pin_map={}
					for role in pin_choices:
						var choice: OptionButton=pin_choices[role]
						part.pin_map[role]=int(choice.get_item_metadata(choice.selected))
	# Saved older inventions may omit drive, implicitly meaning manual.
	if not stored.has("drive") and candidate.get("drive",{})=={"A":"manual","B":"manual"}:
		candidate.erase("drive")
	return candidate!=stored

func _prompt_discard(on_confirm: Callable) -> void:
	# A canceled exclusive window remains alive until its queued deletion.
	# Reuse it instead of creating a second exclusive child in the same frame.
	discard_action=on_confirm
	if is_instance_valid(discard_prompt) and not discard_prompt.is_queued_for_deletion():
		discard_prompt.popup_centered()
		return
	var prompt:=ConfirmationDialog.new()
	discard_prompt=prompt
	prompt.title="Discard unsaved invention changes?"
	prompt.dialog_text="Changes since the last saved blueprint will be lost. Discard them?"
	add_child(prompt)
	prompt.confirmed.connect(func():
		var action: Callable=discard_action
		discard_action=Callable()
		discard_prompt=null
		prompt.queue_free()
		if action.is_valid():action.call())
	# Keep the canceled dialog hidden and reusable, rather than leaving an
	# exclusive window queued for deletion while opening a new one.
	prompt.canceled.connect(func():discard_action=Callable();prompt.hide())
	prompt.popup_centered()

func _go_library() -> void:
	if _has_unsaved_changes():
		_prompt_discard(_library)
	else:
		_library()

func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:return
	if event.keycode==KEY_ESCAPE:
		if page=="editor" and viewport_tool!="select":
			_sync_fields()
			viewport_tool="select"
			_editor()
		else:_close()
	elif page=="editor":
		if event.keycode==KEY_DELETE and selected_part>=0:_remove_part(selected_part)
		elif event.ctrl_pressed and event.keycode==KEY_Z:_history(undo_stack,redo_stack)
		elif event.ctrl_pressed and event.keycode==KEY_Y:_history(redo_stack,undo_stack)

func _ui(title_text: String) -> void:
	for child in get_children():remove_child(child);child.queue_free()
	var panel:=PanelContainer.new();panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);add_child(panel)
	var column:=VBoxContainer.new();panel.add_child(column)
	frame=column
	var top:=HBoxContainer.new();column.add_child(top)
	var heading:=_label(top,title_text);heading.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	_button(top,"Close",_close)
	notice=_label(column,"");notice.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	var scroll:=ScrollContainer.new();scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL;column.add_child(scroll)
	body=VBoxContainer.new();body.size_flags_horizontal=Control.SIZE_EXPAND_FILL;scroll.add_child(body)

func _label(parent: Node,value: String) -> Label:
	var label:=Label.new();label.text=value;parent.add_child(label);return label

func _button(parent: Node,value: String,action: Callable) -> Button:
	var button:=Button.new();button.text=value;button.custom_minimum_size.y=35;parent.add_child(button);button.pressed.connect(action);return button

func _row(parent: Node) -> HBoxContainer:
	var row:=HBoxContainer.new();parent.add_child(row);return row

func _library() -> void:
	page="library";_ui("INVENTION ASSEMBLY STUDIO")
	selected_part=-1
	viewport_tool="select"
	undo_stack.clear()
	redo_stack.clear()
	camera_state={}
	test_pcb=null
	var description:=_label(body,"Build a reusable invention from structural, electrical and moving parts. Fabricate copies, then place one in the room.")
	description.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	_button(body,"New invention",func():editing_id="";draft=Model.empty();_editor())
	var designs: Dictionary=profile.data.get("inventions",{})
	var ids:=designs.keys();ids.sort()
	for id in ids:
		var error: String=Model.validate(str(id),designs,profile.data.get("blueprints",{}))
		var cost: int=Model.price(str(id),designs,profile.data.get("blueprints",{})) if error.is_empty() else -1
		var panel:=PanelContainer.new();body.add_child(panel)
		var column:=VBoxContainer.new();panel.add_child(column)
		_label(column,"%s · %d parts · %d copies · %s"%[designs[id].name,designs[id].parts.size(),int(profile.data.get("invention_copies",{}).get(id,0)),"$%d per copy"%cost if cost>=0 else error])
		var actions:=_row(column)
		_button(actions,"Edit",func():editing_id=str(id);draft=designs[id].duplicate(true);_editor())
		_button(actions,"Test",func():editing_id=str(id);draft=designs[id].duplicate(true);_test_draft()).disabled=cost<0
		_button(actions,"Duplicate",func():
			editing_id=""
			draft=designs[id].duplicate(true)
			draft.name=(str(draft.name).left(34)+" copy")
			_editor())
		var fabricate:=_button(actions,"Fabricate",_fabricate.bind(str(id)));fabricate.disabled=cost<0
		var place:=_button(actions,"Place copy",_place.bind(str(id)));place.disabled=cost<0 or int(profile.data.get("invention_copies",{}).get(id,0))<1
		if int(profile.data.get("invention_copies",{}).get(id,0))>0 and not game.session.online:
			_button(actions,"Discard copies",_discard_copies.bind(str(id)))
		_button(actions,"Remove blueprint",_request_remove.bind(str(id)))
	if ids.is_empty():_label(body,"No inventions saved yet.")

func _editor(message: String="") -> void:
	validation_refresh=Callable()
	page="editor";_ui("EDIT INVENTION")
	notice.text=message
	var guide:=_label(body,"Choose a part, then click the grid or Add part. Select a part to edit it; Save and Test include any changes in the inspector.")
	guide.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	var name_row:=_row(body)
	_button(name_row,"Library",_go_library)
	name_field=LineEdit.new();name_field.text=str(draft.get("name",""));name_field.max_length=40;name_field.size_flags_horizontal=Control.SIZE_EXPAND_FILL;name_row.add_child(name_field)
	name_field.placeholder_text="Invention name"
	var preview:=preload("res://scripts/campus/facilities/circuit_studio/assembly_preview.gd").new()
	preview.design=draft.duplicate(true)
	preview.library=profile.data.get("inventions",{}).duplicate(true)
	preview.library["inv:preview"]=draft.duplicate(true)
	preview.pcbs=profile.data.get("blueprints",{})
	if camera_state.is_empty():camera_state=preview.camera_state
	else:preview.camera_state=camera_state
	var layout:=_row(body)
	var library:=VBoxContainer.new()
	library.custom_minimum_size.x=175
	layout.add_child(library)
	var canvas:=VBoxContainer.new()
	canvas.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	layout.add_child(canvas)
	var inspector:=VBoxContainer.new()
	inspector.custom_minimum_size.x=190
	layout.add_child(inspector)
	var tools:=_row(canvas)
	var tool_group:=ButtonGroup.new()
	for tool in ["select","place","move","rotate"]:
		var button:=_button(tools,tool.capitalize(),func():viewport_tool=tool)
		button.toggle_mode=true
		button.button_group=tool_group
		button.button_pressed=viewport_tool==tool
	_button(tools,"Undo",_history.bind(undo_stack,redo_stack)).disabled=undo_stack.is_empty()
	_button(tools,"Redo",_history.bind(redo_stack,undo_stack)).disabled=redo_stack.is_empty()
	preview.custom_minimum_size=Vector2(250,275)
	preview.tooltip_text="Right drag to orbit. Middle drag to pan. Scroll to zoom."
	canvas.add_child(preview)
	_label(library,"PARTS LIBRARY")
	var lookup:=LineEdit.new()
	lookup.placeholder_text="Find parts"
	library.add_child(lookup)
	part_kind=OptionButton.new()
	library.add_child(part_kind)
	_fill_parts("")
	lookup.text_changed.connect(_fill_parts)
	_label(inspector,"PART INSPECTOR")
	var position:=GridContainer.new()
	position.columns=2
	inspector.add_child(position)
	part_x=_axis(position,"X");part_y=_axis(position,"Y");part_y.min_value=0;part_z=_axis(position,"Z")
	_label(inspector,"Control")
	part_control=OptionButton.new();inspector.add_child(part_control)
	for value in ["None","A","B"]:part_control.add_item(value)
	_label(inspector,"Blueprint")
	part_ref=OptionButton.new();part_ref.fit_to_longest_item=false;inspector.add_child(part_ref)
	part_kind.item_selected.connect(func(index: int):
		placement_kind=str(part_kind.get_item_metadata(index))
		_reference_options())
	part_ref.item_selected.connect(func(_index: int):_pin_options())
	# Keep PCB pin assignment beside the selected part instead of hiding the
	# mapping controls below the entire 3D assembly editor.
	pin_row=VBoxContainer.new()
	pin_row.add_theme_constant_override("separation",6)
	inspector.add_child(pin_row)
	_reference_options()
	if selected_part>=0 and selected_part<draft.parts.size():
		var part: Dictionary=draft.parts[selected_part]
		# The selected item's real properties must populate the inspector.
		# Otherwise edits silently target the next added part instead.
		for index in part_kind.item_count:
			if str(part_kind.get_item_metadata(index))==str(part.type):
				part_kind.select(index)
				placement_kind=str(part.type)
				break
		part_control.select(1 if part.get("control","")=="A" else 2 if part.get("control","")=="B" else 0)
		_reference_options()
		for index in part_ref.item_count:
			if str(part_ref.get_item_metadata(index))==str(part.get("ref","")):
				part_ref.select(index)
				break
		_pin_options()
		if part.type=="pcb" and part.has("pin_map"):
			for role in pin_choices:
				var choice: OptionButton=pin_choices[role]
				for index in choice.item_count:
					if int(choice.get_item_metadata(index))==int(part.pin_map.get(role,-1)):
						choice.select(index)
						break
		part_x.value=part.x
		part_y.value=part.y
		part_z.value=part.z
		preview.placement_height=int(part_y.value)
		_label(inspector,"Selected  ·  "+str(Model.PARTS[part.type].name))
		var apply:=_button(inspector,"Apply selected changes",_apply_selected)
		apply.tooltip_text="Apply position, control, PCB pins and an intentional part-type replacement from the library."
		var rotate:=_button(inspector,"Rotate %d°"%[int(part.get("turns",0))*90],_rotate_part.bind(selected_part))
		if part.type=="hinge":
			var forward:=Model.rotate_grid(Vector3i.FORWARD,int(part.get("turns",0)))
			rotate.tooltip_text="Moving side: %+d X, %+d Z. Mount a frame or servo on the opposite side."%[forward.x,forward.z]
		_button(inspector,"Delete selected",_remove_part.bind(selected_part))
	part_y.value_changed.connect(func(value: float):preview.placement_height=int(value))
	preview.cell_clicked.connect(_viewport_click)
	var add:=_button(library,"Add part",_add_part)
	lookup.text_changed.connect(func(_value: String):add.disabled=part_kind.item_count==0)
	var controls:=_row(body)
	mode_a=_mode(controls,"A",str(draft.get("controls",{}).get("A","hold")))
	drive_a=_drive_mode(controls,"A",str(draft.get("drive",{}).get("A","manual")))
	var second_controls:=_row(body)
	mode_b=_mode(second_controls,"B",str(draft.get("controls",{}).get("B","toggle")))
	drive_b=_drive_mode(second_controls,"B",str(draft.get("drive",{}).get("B","manual")))
	var actions:=_row(frame)
	var validation:=_label(actions,"")
	validation.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	validation.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	var save:=_button(actions,"Save blueprint",_save)
	var test:=_button(actions,"Test",_test_draft)
	var refresh:=func():
		var error:=_draft_error()
		validation.text=error
		save.disabled=not error.is_empty()
		test.disabled=save.disabled
	name_field.text_changed.connect(func(_value: String):refresh.call())
	for choice in [mode_a,mode_b,drive_a,drive_b,part_kind,part_control,part_ref]:
		choice.item_selected.connect(func(_index: int):refresh.call())
	for field in [part_x,part_y,part_z]:
		field.value_changed.connect(func(_value: float):refresh.call())
	validation_refresh=refresh
	for choice in pin_choices.values():
		choice.item_selected.connect(func(_index: int):refresh.call())
	refresh.call()

func _fill_parts(query: String) -> void:
	part_kind.clear()
	var needle:=query.strip_edges().to_lower()
	for key in Model.PARTS:
		var item: Dictionary=Model.PARTS[key]
		if not needle.is_empty() and not str(item.name+" "+item.group).to_lower().contains(needle):continue
		part_kind.add_item(str(item.name))
		part_kind.set_item_metadata(part_kind.item_count-1,key)
		part_kind.get_popup().set_item_tooltip(part_kind.item_count-1,str(item.group))
		if key==placement_kind:part_kind.select(part_kind.item_count-1)
	if is_instance_valid(part_ref) and is_instance_valid(pin_row):_reference_options()

func _test_draft() -> void:
	# A part inspector is staged while the user types. Testing should always
	# use those visible values, even when Apply has not been pressed separately.
	if page=="editor":
		_sync_fields()
		if not _commit_selected_changes():return
		var validation_error:=_draft_error()
		if not validation_error.is_empty():
			notice.text=validation_error
			return
	# Older saved designs may have no explicit drive map. Validation treats
	# those as manual; the live preview must use the same default.
	if not draft.has("drive"):draft.drive={"A":"manual","B":"manual"}
	page="test"
	_ui("TEST INVENTION")
	_button(body,"Back to editor",func():test_pcb=null;_editor())
	notice.text="This test uses a temporary copy of the draft."
	test_view=preload("res://scripts/campus/facilities/circuit_studio/assembly_preview.gd").new()
	test_view.design=draft
	test_view.library=profile.data.get("inventions",{}).duplicate(true)
	test_view.library["inv:preview"]=draft
	test_view.pcbs=profile.data.get("blueprints",{})
	test_view.custom_minimum_size=Vector2(260,360)
	body.add_child(test_view)
	test_parts=Model.flattened("inv:preview",test_view.library,test_view.pcbs)
	Model.connect_wheels(test_parts)
	test_clock=0.0
	test_switches={"A":false,"B":false}
	test_output={"A":0.0,"B":0.0}
	test_pcb=null
	var controls:=_row(body)
	for channel in ["A","B"]:
		var selected_channel:=String(channel)
		var hold_mode: bool=str(draft.controls.get(selected_channel,"hold"))=="hold"
		var button: Button
		if hold_mode:
			button=_button(controls,"Hold "+selected_channel,func():pass)
			button.button_down.connect(func():test_switches[selected_channel]=true)
			button.button_up.connect(func():test_switches[selected_channel]=false)
		else:
			button=_button(controls,"Switch "+selected_channel,func():test_switches[selected_channel]=not test_switches[selected_channel])
			button.toggle_mode=true
		button.disabled=not test_parts.any(func(part):return part.type=="switch" and part.control==selected_channel)
	_button(controls,"Reset test",_test_draft)
	for index: int in range(test_view.joints.size()):
		var joint: Dictionary=test_view.joints[index]
		if joint.control!="":continue
		var button:=_button(controls,"Hinge %d"%(index+1),func():joint.manual=not joint.manual)
		button.toggle_mode=true
	test_status=_label(body,"")
	if draft.drive.A=="manual" and draft.drive.B=="manual":return
	for part in test_parts:
		if part.type!="pcb" or not part.has("pin_map"):continue
		test_pcb=PCBRun.new()
		if not test_pcb.configure(part.ref,test_view.pcbs,part.pin_map):
			notice.text="The mounted PCB could not start."
			test_pcb=null
			return
		var inputs:=VBoxContainer.new()
		body.add_child(inputs)
		_test_pcb_controls(inputs)
		break

func _test_input(id: String,pressed: bool,reverse: bool=false,command: Dictionary={}) -> void:
	if not is_instance_valid(test_pcb):return
	if not test_pcb.input(id,pressed,reverse,command):
		notice.text="Could not apply that PCB input in the test."

func _test_pcb_controls(parent: VBoxContainer) -> void:
	# Use the same input commands as the mounted world panel. Previously only
	# buttons and toggles were testable, leaving sliders and serial inputs blind.
	for entry in test_pcb.inputs:
		var id:=str(entry.id)
		var kind:=str(entry.kind)
		var row:=_row(parent)
		_label(row,str(entry.name))
		if kind=="button":
			var hold:=_button(row,"Hold",func():pass)
			hold.button_down.connect(func():_test_input(id,true))
			hold.button_up.connect(func():_test_input(id,false))
		elif kind=="toggle":
			_button(row,"Toggle",func():_test_input(id,true))
		elif kind=="io_encoder":
			for steps in [-1,1]:
				_button(row,"−" if steps<0 else "+",func():_test_input(id,true,false,{"op":"turn","steps":steps}))
		elif kind=="io_selector":
			var selector:=OptionButton.new()
			row.add_child(selector)
			for index in 3:selector.add_item(str(index))
			selector.item_selected.connect(func(index: int):_test_input(id,true,false,{"op":"select","position":index}))
		elif kind=="io_keypad":
			for number in 12:
				var button:=_button(row,str(number+1),func():pass)
				button.button_down.connect(func():_test_input(id,true,false,{"op":"key","key":number,"pressed":true}))
				button.button_up.connect(func():_test_input(id,false,false,{"op":"key","key":number,"pressed":false}))
		elif kind in ["io_slider","io_joystick","xpt2046"]:
			var x_label:=_label(row,"Level" if kind=="io_slider" else "X")
			var x:=HSlider.new()
			x.min_value=0.0;x.max_value=1.0;x.step=.05;x.value=.5
			x.custom_minimum_size.x=130;row.add_child(x)
			var y:=HSlider.new()
			y.min_value=0.0;y.max_value=1.0;y.step=.05;y.value=.5
			if kind!="io_slider":
				_label(row,"Y")
				row.add_child(y)
			var touch_state: Dictionary={"active":false}
			var move:=func(_value: float):
				if kind=="io_slider":_test_input(id,true,false,{"op":"move","x":x.value})
				elif kind=="io_joystick":_test_input(id,true,false,{"op":"move","x":x.value,"y":y.value})
				elif touch_state.active:_test_input(id,true,false,{"op":"touch","x":x.value,"y":y.value,"pressed":true})
			# The preview must behave like a mounted world PCB while dragging.
			x.value_changed.connect(move)
			if kind!="io_slider":y.value_changed.connect(move)
			if kind=="io_joystick":
				var press:=_button(row,"Press on/off",func():pass)
				press.toggle_mode=true
				press.toggled.connect(func(pressed: bool):
					if pressed:_test_input(id,true,false,{"op":"press","pressed":true})
					else:
						_test_input(id,false,false,{"op":"release"})
						x.set_value_no_signal(.5)
						y.set_value_no_signal(.5))
			elif kind=="xpt2046":
				var touch:=_button(row,"Touch on/off",func():pass)
				touch.toggle_mode=true
				touch.toggled.connect(func(pressed: bool):
					touch_state.active=pressed
					if pressed:_test_input(id,true,false,{"op":"touch","x":x.value,"y":y.value,"pressed":true})
					else:_test_input(id,false,false,{"op":"release"}))
		else:
			_button(row,"−",func():_test_input(id,true,true))
			_button(row,"+",func():_test_input(id,true,false))

func _process(delta: float) -> void:
	if page!="test" or not is_instance_valid(test_status):return
	if is_instance_valid(test_pcb):
		test_clock+=delta
		var steps:=0
		while test_clock>=.05 and steps<4:
			test_output=test_pcb.tick(.05)
			test_clock-=.05
			steps+=1
	var battery:=test_parts.any(func(part):return part.type=="battery")
	var channels: Dictionary={}
	for channel in ["A","B"]:
		channels[channel]=String(test_output.get("error","")).is_empty() and Model.energized(draft.drive[channel],test_switches[channel],test_output[channel])
	test_view.preview_power(delta,channels,battery)
	var active_motors:=test_parts.filter(func(part):return part.type=="wheel" and battery and channels.get(part.get("motor_control",""),false)).size()
	active_motors+=test_view.joints.filter(func(joint):return joint.control!="" and battery and channels.get(joint.control,false)).size()
	test_status.text="Battery %s  ·  %d active motors  ·  PCB A %.2f V  ·  PCB B %.2f V"%["connected" if battery else "missing",active_motors,test_output.A,test_output.B]
	var error:=String(test_output.get("error",""))
	if not error.is_empty():test_status.text+="\n"+error

func _viewport_click(cell: Vector3i,index: int) -> void:
	if viewport_tool=="rotate":
		if index>=0:_rotate_part(index)
		return
	if viewport_tool=="select":
		# Keep staged inspector edits when changing selection or clicking
		# empty space. Leave invalid edits visible for correction.
		_sync_fields()
		if not _commit_selected_changes():return
		if selected_part!=index:
			selected_part=index
			_editor()
		return
	if absi(cell.x)>6 or absi(cell.z)>6:return
	for occupied_index in draft.parts.size():
		var part: Dictionary=draft.parts[occupied_index]
		if viewport_tool=="move" and occupied_index==selected_part:continue
		if Vector3i(part.x,part.y,part.z)==cell:
			notice.text="Another part occupies that grid cell."
			return
	part_x.value=cell.x
	part_y.value=cell.y
	part_z.value=cell.z
	if viewport_tool=="place":
		_add_part()
	elif selected_part>=0 and selected_part<draft.parts.size():
		_sync_fields()
		_track_edit()
		var part: Dictionary=draft.parts[selected_part]
		part.x=cell.x
		part.y=cell.y
		part.z=cell.z
		_editor()

func _rotate_part(index: int) -> void:
	_sync_fields()
	if not _commit_selected_changes():return
	_track_edit()
	var part: Dictionary=draft.parts[index]
	var turns:=posmod(int(part.get("turns",0))+1,4)
	if turns==0:part.erase("turns")
	else:part.turns=turns
	selected_part=index
	_editor()

func _track_edit() -> void:
	undo_stack.append(draft.duplicate(true))
	if undo_stack.size()>40:undo_stack.pop_front()
	redo_stack.clear()

func _history(source: Array[Dictionary],target: Array[Dictionary]) -> void:
	if source.is_empty():return
	_sync_fields()
	target.append(draft.duplicate(true))
	draft=source.pop_back()
	selected_part=-1
	_editor()

func _mode(parent: Node,label_text: String,selected: String) -> OptionButton:
	_label(parent,"Control "+label_text)
	var choice:=OptionButton.new();parent.add_child(choice)
	choice.add_item("Hold");choice.add_item("Toggle")
	choice.select(1 if selected=="toggle" else 0)
	return choice

func _drive_mode(parent: Node,label_text: String,selected: String) -> OptionButton:
	_label(parent,"Drive "+label_text)
	var choice:=OptionButton.new();parent.add_child(choice)
	for value in ["Manual","PCB output","Both"]:choice.add_item(value)
	choice.select(["manual","pcb","both"].find(selected))
	choice.tooltip_text="Manual uses the physical switch. PCB output activates above 2.5 V. Both requires the switch AND the PCB output."
	return choice

func _axis(parent: Node,label_text: String) -> SpinBox:
	_label(parent,label_text)
	var axis:=SpinBox.new();axis.min_value=-6;axis.max_value=6;axis.step=1;axis.custom_minimum_size.x=72;parent.add_child(axis)
	return axis

func _reference_options() -> void:
	part_ref.clear()
	var kind:=str(part_kind.get_item_metadata(part_kind.selected)) if part_kind.selected>=0 else ""
	var library: Dictionary=profile.data.get("blueprints",{}) if kind=="pcb" else profile.data.get("inventions",{}) if kind=="nested" else {}
	for id in library:
		if kind=="pcb" and str(library[id].get("package",""))!="PCB":continue
		if kind=="nested" and str(id)==editing_id:continue
		part_ref.add_item(str(library[id].get("name",id)));part_ref.set_item_metadata(part_ref.item_count-1,str(id))
	part_ref.disabled=kind not in ["pcb","nested"]
	_pin_options()

func _pin_options() -> void:
	for child in pin_row.get_children():pin_row.remove_child(child);child.queue_free()
	pin_choices.clear()
	if part_kind.selected<0 or str(part_kind.get_item_metadata(part_kind.selected))!="pcb" or part_ref.item_count==0:return
	_label(pin_row,"PCB PIN MAPPING")
	var ref:=str(part_ref.get_item_metadata(part_ref.selected))
	var bp: Dictionary=profile.data.get("blueprints",{}).get(ref,{})
	if bp.is_empty():return
	for role in ["power","ground","A","B"]:
		_label(pin_row,{"power":"5 V pin","ground":"Ground pin","A":"Output A","B":"Output B"}[role])
		var choice:=OptionButton.new()
		choice.fit_to_longest_item=false
		choice.custom_minimum_size.x=170
		pin_row.add_child(choice)
		pin_choices[role]=choice
		if role in ["A","B"]:choice.add_item("Unused");choice.set_item_metadata(0,-1)
		for index in bp.pins.size():
			choice.add_item(str(bp.pins[index].get("name","Pin "+str(index+1))))
			choice.set_item_metadata(choice.item_count-1,index)
		var wanted: String={"power":"VCC","ground":"GND","A":"OUT_A","B":"OUT_B"}[role]
		for index in bp.pins.size():
			if str(bp.pins[index].get("name","")).to_upper()==wanted:choice.select(index+(1 if role in ["A","B"] else 0));break
		# Rebuilt pin selectors must participate in the same live validation.
		if validation_refresh.is_valid():
			choice.item_selected.connect(func(_index: int):validation_refresh.call())

func _sync_fields() -> void:
	draft.name=name_field.text.strip_edges()
	draft.controls={"A":"toggle" if mode_a.selected==1 else "hold","B":"toggle" if mode_b.selected==1 else "hold"}
	draft.drive={"A":["manual","pcb","both"][drive_a.selected],"B":["manual","pcb","both"][drive_b.selected]}

func _add_part() -> void:
	if part_kind.selected<0:return
	_sync_fields()
	var kind:=str(part_kind.get_item_metadata(part_kind.selected))
	var ref: String=str(part_ref.get_item_metadata(part_ref.selected)) if kind in ["pcb","nested"] and part_ref.item_count>0 else ""
	if kind in ["pcb","nested"] and ref.is_empty():_editor("Save a compatible blueprint first.");return
	if draft.parts.size()>=Model.MAX_PARTS:_editor("A design holds at most 32 parts.");return
	for existing in draft.parts:
		if int(existing.x)==int(part_x.value) and int(existing.y)==int(part_y.value) and int(existing.z)==int(part_z.value):
			notice.text="Another part occupies that grid cell."
			return
	var part: Dictionary={"type":kind,"x":int(part_x.value),"y":int(part_y.value),"z":int(part_z.value),"control":"" if part_control.selected==0 else "A" if part_control.selected==1 else "B","ref":ref}
	if kind=="pcb" and pin_choices.size()==4:
		part.pin_map={}
		for role in pin_choices:part.pin_map[role]=int(pin_choices[role].get_item_metadata(pin_choices[role].selected))
	_track_edit()
	draft.parts.append(part)
	selected_part=draft.parts.size()-1
	_editor()

func _apply_selected() -> void:
	if selected_part<0 or selected_part>=draft.parts.size() or part_kind.selected<0:return
	_sync_fields()
	var before: Dictionary=draft.parts[selected_part].duplicate(true)
	if not _commit_selected_changes(true):return
	if before==draft.parts[selected_part]:
		notice.text="Selected part already has those settings."
		return
	_editor("Selected part updated.")

# Use the same inspector-to-model path for Apply, Save and Test. Previously
# Save/Test could silently discard pending coordinates, controls and PCB pins.
# Evaluate the visible inspector as a non-mutating draft. Save/Test feedback
# must agree with what the user sees before pressing Apply.
func _preview_selected_part(replace_type := false) -> Dictionary:
	if selected_part<0 or selected_part>=draft.parts.size() or not is_instance_valid(part_kind) or part_kind.selected<0:return {}
	var changed: Dictionary=draft.parts[selected_part].duplicate(true)
	var palette_kind:=str(part_kind.get_item_metadata(part_kind.selected))
	if replace_type:changed.type=palette_kind
	changed.x=int(part_x.value)
	changed.y=int(part_y.value)
	changed.z=int(part_z.value)
	changed.control="" if part_control.selected==0 else "A" if part_control.selected==1 else "B"
	# Browsing the placement palette alone must not replace a selected part.
	if replace_type or palette_kind==str(changed.type):
		if changed.type in ["pcb","nested"]:
			if part_ref.selected<0:return {"error":"Choose a blueprint for the selected part."}
			changed.ref=str(part_ref.get_item_metadata(part_ref.selected))
		else:changed.ref=""
		if changed.type=="pcb":
			if pin_choices.size()==4:
				changed.pin_map={}
				for role in pin_choices:
					var choice: OptionButton=pin_choices[role]
					if choice.selected<0:return {"error":"Configure PCB supply and output pins."}
					changed.pin_map[role]=int(choice.get_item_metadata(choice.selected))
		else:changed.erase("pin_map")
	return {"part":changed}

func _commit_selected_changes(replace_type := false) -> bool:
	var preview: Dictionary=_preview_selected_part(replace_type)
	if preview.is_empty():return true
	if preview.has("error"):
		notice.text=str(preview.error)
		return false
	var changed: Dictionary=preview.part
	if changed==draft.parts[selected_part]:return true
	for index in draft.parts.size():
		if index==selected_part:continue
		var other: Dictionary=draft.parts[index]
		if int(other.x)==int(changed.x) and int(other.y)==int(changed.y) and int(other.z)==int(changed.z):
			notice.text="Another part occupies that grid cell."
			return false
	_track_edit()
	draft.parts[selected_part]=changed
	return true

func _remove_part(index: int) -> void:
	_sync_fields()
	_track_edit()
	draft.parts.remove_at(index)
	selected_part=-1
	_editor()

func _draft_error() -> String:
	var designs: Dictionary=profile.data.get("inventions",{}).duplicate(true)
	var candidate: Dictionary=draft.duplicate(true)
	candidate.name=name_field.text.strip_edges()
	candidate.controls={"A":"toggle" if mode_a.selected==1 else "hold","B":"toggle" if mode_b.selected==1 else "hold"}
	candidate.drive={"A":["manual","pcb","both"][drive_a.selected],"B":["manual","pcb","both"][drive_b.selected]}
	if page=="editor":
		var staged: Dictionary=_preview_selected_part()
		if staged.has("error"):return str(staged.error)
		if staged.has("part"):candidate.parts[selected_part]=staged.part
	var frozen: Dictionary=Model.fabricated_dependencies(designs,profile.data.get("invention_copies",{}))
	var revised: bool=not editing_id.is_empty() and frozen.has(editing_id) and designs.get(editing_id,{})!=candidate
	var test_id: String="inv:draft" if editing_id.is_empty() or revised else editing_id
	designs[test_id]=candidate
	return Model.validate(test_id,designs,profile.data.get("blueprints",{}))

func _save() -> void:
	_sync_fields()
	if not _commit_selected_changes():return
	var error:=_draft_error()
	if error!="":notice.text=error;return
	var revised: bool=editing_id!="" and Model.fabricated_dependencies(profile.data.get("inventions",{}),profile.data.get("invention_copies",{})).has(editing_id) and profile.data.get("inventions",{}).get(editing_id,{})!=draft
	var id: String="inv:"+Crypto.new().generate_random_bytes(12).hex_encode() if editing_id=="" or revised else editing_id
	var before: Dictionary=profile.data.duplicate(true)
	if not profile.data.has("inventions"):profile.data.inventions={}
	profile.data.inventions[id]=draft.duplicate(true)
	if profile.save()!=OK:
		profile.data=before;notice.text="Could not save blueprint";return
	_library();notice.text="New revision saved. Existing copies keep their original design." if revised else "Blueprint saved. Fabricate a copy to place it."

func _fabricate(id: String) -> void:
	var message: String=profile.fabricate_invention(id)
	_library();notice.text=message

func _place(id: String) -> void:
	var message: String=game.invention_world.request_place(id)
	notice.text=message

func _can_discard(id: String) -> String:
	if game.session.online:return "Discarding fabricated copies is unavailable in hosted sessions."
	if int(profile.data.get("invention_copies",{}).get(id,0))<1:return "There are no fabricated copies to discard."
	for item in game.invention_world.placed.values():
		if str(item.get("id",""))==id:return "Retrieve all placed copies of this invention first."
	return ""

func _finish_discard(id: String) -> String:
	var error: String=_can_discard(id)
	if not error.is_empty():return error
	var before: Dictionary=profile.data.duplicate(true)
	profile.data.invention_copies.erase(id)
	if profile.save()!=OK:
		profile.data=before
		return "Could not save the copy discard; no copies were removed."
	return ""

func _discard_copies(id: String) -> void:
	var error: String=_can_discard(id)
	if not error.is_empty():
		notice.text=error
		return
	var count: int=int(profile.data.invention_copies[id])
	var name: String=str(profile.data.get("inventions",{}).get(id,{}).get("name",id))
	copies_target=id
	var description: String="Permanently discard %d fabricated copies of %s? The saved blueprint will remain."%[count,name]
	if is_instance_valid(copies_prompt) and not copies_prompt.is_queued_for_deletion():
		copies_prompt.dialog_text=description
		copies_prompt.popup_centered()
		return
	var confirm:=ConfirmationDialog.new()
	copies_prompt=confirm
	confirm.title="Discard fabricated copies?"
	confirm.dialog_text=description
	add_child(confirm)
	confirm.confirmed.connect(func():
		var target: String=copies_target
		copies_target=""
		copies_prompt=null
		confirm.queue_free()
		if target.is_empty():return
		var result: String=_finish_discard(target)
		if result.is_empty():
			_library()
			notice.text="Fabricated copies discarded. You can now remove this blueprint."
		else:notice.text=result)
	# Reuse the hidden modal after cancel. Deleting and immediately reopening an
	# exclusive child produces a Godot window error before the next frame.
	confirm.canceled.connect(func():copies_target="";confirm.hide())
	confirm.popup_centered()

func _request_remove(id: String) -> void:
	if not profile.data.get("inventions",{}).has(id):return
	remove_target=id
	var description: String="Permanently remove %s? This cannot be undone."%str(profile.data.inventions[id].get("name",id))
	if is_instance_valid(remove_prompt) and not remove_prompt.is_queued_for_deletion():
		remove_prompt.dialog_text=description
		remove_prompt.popup_centered()
		return
	var prompt:=ConfirmationDialog.new()
	remove_prompt=prompt
	prompt.title="Remove invention blueprint?"
	prompt.dialog_text=description
	add_child(prompt)
	prompt.confirmed.connect(func():
		var target: String=remove_target
		remove_target=""
		remove_prompt=null
		prompt.queue_free()
		if not target.is_empty():_remove(target))
	prompt.canceled.connect(func():remove_target="";prompt.hide())
	prompt.popup_centered()

func _remove(id: String) -> void:
	var before: Dictionary=profile.data.duplicate(true)
	if int(profile.data.get("invention_copies",{}).get(id,0))>0:
		notice.text="Use or clear fabricated copies before removing this blueprint.";return
	for other in profile.data.get("inventions",{}):
		if other==id:continue
		for part in profile.data.inventions[other].parts:
			if part.type=="nested" and part.ref==id:
				notice.text="Another blueprint includes this design.";return
	profile.data.inventions.erase(id)
	if profile.save()!=OK:profile.data=before;notice.text="Could not remove blueprint";return
	_library()
