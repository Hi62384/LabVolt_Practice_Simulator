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
var pin_row: HBoxContainer
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
	hide();queue_free()
	if is_instance_valid(game) and game.front.in_game:game.capture()

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
		_button(actions,"Remove blueprint",_remove.bind(str(id)))
	if ids.is_empty():_label(body,"No inventions saved yet.")

func _editor(message: String="") -> void:
	page="editor";_ui("EDIT INVENTION")
	notice.text=message
	var name_row:=_row(body)
	_button(name_row,"Library",_library)
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
	pin_row=_row(body)
	_reference_options()
	if selected_part>=0 and selected_part<draft.parts.size():
		var part: Dictionary=draft.parts[selected_part]
		part_x.value=part.x
		part_y.value=part.y
		part_z.value=part.z
		preview.placement_height=int(part_y.value)
		_label(inspector,"Selected  ·  "+str(Model.PARTS[part.type].name))
		_button(inspector,"Rotate %d°"%[int(part.get("turns",0))*90],_rotate_part.bind(selected_part))
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
	var test:=_button(actions,"Test",func():_sync_fields();_test_draft())
	var refresh:=func():
		var error:=_draft_error()
		validation.text=error
		save.disabled=not error.is_empty()
		test.disabled=save.disabled
	name_field.text_changed.connect(func(_value: String):refresh.call())
	for choice in [mode_a,mode_b,drive_a,drive_b]:
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
	test_clock=0.0
	test_switches={"A":false,"B":false}
	test_output={"A":0.0,"B":0.0}
	test_pcb=null
	var controls:=_row(body)
	for channel in ["A","B"]:
		var selected_channel:=String(channel)
		var button:=_button(controls,"Switch "+selected_channel,func():test_switches[selected_channel]=not test_switches[selected_channel])
		button.toggle_mode=true
		button.disabled=not test_parts.any(func(part):return part.type=="switch" and part.control==selected_channel)
	_button(controls,"Reset test",_test_draft)
	test_status=_label(body,"")
	if draft.drive.A=="manual" and draft.drive.B=="manual":return
	for part in test_parts:
		if part.type!="pcb" or not part.has("pin_map"):continue
		test_pcb=PCBRun.new()
		if not test_pcb.configure(part.ref,test_view.pcbs,part.pin_map):
			notice.text="The mounted PCB could not start."
			test_pcb=null
			return
		var inputs:=HFlowContainer.new()
		body.add_child(inputs)
		for entry in test_pcb.inputs:
			var id:=String(entry.id)
			if entry.kind=="button":
				var hold:=_button(inputs,entry.name,func():pass)
				hold.button_down.connect(func():test_pcb.input(id,true))
				hold.button_up.connect(func():test_pcb.input(id,false))
			elif entry.kind=="toggle":
				_button(inputs,entry.name,func():test_pcb.input(id,true))
		break

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
	var active_motors:=test_parts.filter(func(part):return part.type in ["dc_motor","servo"] and battery and channels.get(part.control,false)).size()
	test_status.text="Battery %s  ·  %d active motors  ·  PCB A %.2f V  ·  PCB B %.2f V"%["connected" if battery else "missing",active_motors,test_output.A,test_output.B]
	var error:=String(test_output.get("error",""))
	if not error.is_empty():test_status.text+="\n"+error

func _viewport_click(cell: Vector3i,index: int) -> void:
	if viewport_tool=="rotate":
		if index>=0:_rotate_part(index)
		return
	if viewport_tool=="select":
		if index>=0:
			_sync_fields()
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
	var ref:=str(part_ref.get_item_metadata(part_ref.selected))
	var bp: Dictionary=profile.data.get("blueprints",{}).get(ref,{})
	if bp.is_empty():return
	for role in ["power","ground","A","B"]:
		_label(pin_row,{"power":"5 V pin","ground":"Ground pin","A":"Output A","B":"Output B"}[role])
		var choice:=OptionButton.new();pin_row.add_child(choice);pin_choices[role]=choice
		if role in ["A","B"]:choice.add_item("Unused");choice.set_item_metadata(0,-1)
		for index in bp.pins.size():
			choice.add_item(str(bp.pins[index].get("name","Pin "+str(index+1))))
			choice.set_item_metadata(choice.item_count-1,index)
		var wanted: String={"power":"VCC","ground":"GND","A":"OUT_A","B":"OUT_B"}[role]
		for index in bp.pins.size():
			if str(bp.pins[index].get("name","")).to_upper()==wanted:choice.select(index+(1 if role in ["A","B"] else 0));break

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
	var part: Dictionary={"type":kind,"x":int(part_x.value),"y":int(part_y.value),"z":int(part_z.value),"control":"" if part_control.selected==0 else "A" if part_control.selected==1 else "B","ref":ref}
	if kind=="pcb" and pin_choices.size()==4:
		part.pin_map={}
		for role in pin_choices:part.pin_map[role]=int(pin_choices[role].get_item_metadata(pin_choices[role].selected))
	_track_edit()
	draft.parts.append(part)
	selected_part=draft.parts.size()-1
	_editor()

func _remove_part(index: int) -> void:
	_sync_fields()
	_track_edit()
	draft.parts.remove_at(index)
	selected_part=-1
	_editor()

func _draft_error() -> String:
	var test_id:=editing_id if editing_id!="" else "inv:draft"
	var designs: Dictionary=profile.data.get("inventions",{}).duplicate(true)
	var candidate: Dictionary=draft.duplicate(true)
	candidate.name=name_field.text.strip_edges()
	candidate.controls={"A":"toggle" if mode_a.selected==1 else "hold","B":"toggle" if mode_b.selected==1 else "hold"}
	candidate.drive={"A":["manual","pcb","both"][drive_a.selected],"B":["manual","pcb","both"][drive_b.selected]}
	designs[test_id]=candidate
	return Model.validate(test_id,designs,profile.data.get("blueprints",{}))

func _save() -> void:
	_sync_fields()
	var error:=_draft_error()
	if error!="":notice.text=error;return
	var revised: bool=editing_id!="" and int(profile.data.get("invention_copies",{}).get(editing_id,0))>0 and profile.data.get("inventions",{}).get(editing_id,{})!=draft
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
