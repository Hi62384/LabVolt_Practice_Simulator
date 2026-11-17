extends Window
const Model=preload("res://scripts/campus/facilities/circuit_studio/assembly_model.gd")
const StudioTheme=preload("res://scripts/ui/design_system/theme.gd")
var game: Node
var profile: RefCounted
var body: VBoxContainer
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

func open_station(owner_game: Node) -> void:
	game=owner_game;profile=game.electronics.profile
	title="Invention Assembly Studio";borderless=true;theme=StudioTheme.create()
	var available:=Vector2i(game.get_viewport().get_visible_rect().size)
	size=Vector2i(maxi(680,mini(1080,available.x-50)),maxi(490,mini(780,available.y-70)))
	min_size=Vector2i(650,470)
	close_requested.connect(_close)
	game.release_mouse()
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
	if event is InputEventKey and event.pressed and event.keycode==KEY_ESCAPE:_close()

func _ui(title_text: String) -> void:
	for child in get_children():remove_child(child);child.queue_free()
	var panel:=PanelContainer.new();panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);add_child(panel)
	var column:=VBoxContainer.new();panel.add_child(column)
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
		var fabricate:=_button(actions,"Fabricate",_fabricate.bind(str(id)));fabricate.disabled=cost<0
		var place:=_button(actions,"Place copy",_place.bind(str(id)));place.disabled=cost<0 or int(profile.data.get("invention_copies",{}).get(id,0))<1
		_button(actions,"Remove blueprint",_remove.bind(str(id)))
	if ids.is_empty():_label(body,"No inventions saved yet.")

func _editor(message: String="") -> void:
	page="editor";_ui("EDIT INVENTION")
	notice.text=message
	_button(body,"Back to library",_library)
	var name_row:=_row(body);_label(name_row,"Name")
	name_field=LineEdit.new();name_field.text=str(draft.get("name",""));name_field.max_length=40;name_field.size_flags_horizontal=Control.SIZE_EXPAND_FILL;name_row.add_child(name_field)
	var controls:=_row(body)
	mode_a=_mode(controls,"A",str(draft.get("controls",{}).get("A","hold")))
	mode_b=_mode(controls,"B",str(draft.get("controls",{}).get("B","toggle")))
	var drives:=_row(body)
	drive_a=_drive_mode(drives,"A",str(draft.get("drive",{}).get("A","manual")))
	drive_b=_drive_mode(drives,"B",str(draft.get("drive",{}).get("B","manual")))
	var guide:=_label(body,"Part positions use a 0.3 m grid. Motors and servos respond to control A or B when powered by a battery pack.")
	guide.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	var preview:=preload("res://scripts/campus/facilities/circuit_studio/assembly_preview.gd").new()
	preview.design=draft.duplicate(true)
	preview.library=profile.data.get("inventions",{}).duplicate(true)
	preview.library["inv:preview"]=draft.duplicate(true)
	preview.pcbs=profile.data.get("blueprints",{})
	preview.custom_minimum_size=Vector2(260,220);body.add_child(preview)
	var part_list:=VBoxContainer.new();body.add_child(part_list)
	for index in draft.parts.size():
		var part: Dictionary=draft.parts[index]
		var row:=_row(part_list)
		var title: String=str(Model.PARTS.get(part.type,{}).get("name",part.type))
		_label(row,"%s  (%d, %d, %d)%s%s"%[title,int(part.x),int(part.y),int(part.z),"  · "+str(part.control) if str(part.get("control","")).length()>0 else "","  · "+str(part.get("ref","")) if part.type=="pcb" else ""])
		_button(row,"Remove",_remove_part.bind(index))
	_label(body,"ADD PART")
	var form:=_row(body)
	part_kind=OptionButton.new();form.add_child(part_kind)
	for key in Model.PARTS:part_kind.add_item(str(Model.PARTS[key].name));part_kind.set_item_metadata(part_kind.item_count-1,key)
	part_x=_axis(form,"X");part_y=_axis(form,"Y");part_y.min_value=0;part_z=_axis(form,"Z")
	var extra:=_row(body)
	_label(extra,"Control")
	part_control=OptionButton.new();extra.add_child(part_control)
	for value in ["None","A","B"]:part_control.add_item(value)
	_label(extra,"Blueprint")
	part_ref=OptionButton.new();part_ref.custom_minimum_size.x=230;extra.add_child(part_ref)
	part_kind.item_selected.connect(func(_index: int):_reference_options())
	part_ref.item_selected.connect(func(_index: int):_pin_options())
	pin_row=_row(body)
	_reference_options()
	_button(body,"Add part",_add_part)
	var error:=_draft_error()
	if error!="":_label(body,error)
	var save:=_button(body,"Save blueprint",_save);save.disabled=error!=""

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
	var kind:=str(part_kind.get_item_metadata(part_kind.selected))
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
	if str(part_kind.get_item_metadata(part_kind.selected))!="pcb" or part_ref.item_count==0:return
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
	_sync_fields()
	var kind:=str(part_kind.get_item_metadata(part_kind.selected))
	var ref: String=str(part_ref.get_item_metadata(part_ref.selected)) if kind in ["pcb","nested"] and part_ref.item_count>0 else ""
	if kind in ["pcb","nested"] and ref.is_empty():_editor("Save a compatible blueprint first.");return
	if draft.parts.size()>=Model.MAX_PARTS:_editor("A design holds at most 32 parts.");return
	var part: Dictionary={"type":kind,"x":int(part_x.value),"y":int(part_y.value),"z":int(part_z.value),"control":"" if part_control.selected==0 else "A" if part_control.selected==1 else "B","ref":ref}
	if kind=="pcb" and pin_choices.size()==4:
		part.pin_map={}
		for role in pin_choices:part.pin_map[role]=int(pin_choices[role].get_item_metadata(pin_choices[role].selected))
	draft.parts.append(part)
	_editor()

func _remove_part(index: int) -> void:
	_sync_fields();draft.parts.remove_at(index);_editor()

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
