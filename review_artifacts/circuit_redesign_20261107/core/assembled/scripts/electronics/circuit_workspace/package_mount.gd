extends RefCounted
## Entry adapter only; package and routing models retain serialization authority.
static func mount(host: Node, parent: Control, kind: String, draft: Dictionary, leave: Callable=Callable()) -> Control:
	var root:=VBoxContainer.new();root.size_flags_horizontal=Control.SIZE_EXPAND_FILL;root.size_flags_vertical=Control.SIZE_EXPAND_FILL;parent.add_child(root)
	var tools:=HFlowContainer.new();root.add_child(tools)
	var notice:=Label.new();root.add_child(notice)
	var menu:=MenuButton.new();menu.text="Saved "+kind+" projects";tools.add_child(menu)
	var choices: Array=[]
	for id in host.profile.data.get("blueprints",{}):
		var bp: Dictionary=host.profile.data.blueprints[id]
		if str(bp.get("package","IC"))!=kind:continue
		for operation in (["Package","Copper","Standalone","Craft"] if kind=="PCB" else ["Package","Craft"]):
			choices.append({"id":str(id),"op":operation});menu.get_popup().add_item(operation+" · "+str(bp.name),choices.size()-1)
	menu.get_popup().id_pressed.connect(func(index):
		if index<0 or index>=choices.size():return
		var choice: Dictionary=choices[index]
		if choice.op=="Copper":
			host.open_pcb_routing(choice.id)
			if leave.is_valid():leave.call()
		elif choice.op=="Craft":notice.text=host.profile.obtain_ic(choice.id,true)
		elif choice.op=="Standalone":
			host.prepare_standalone(choice.id)
			if leave.is_valid():leave.call()
		else:
			var result: Dictionary=open_saved(host,choice.id);notice.text=str(result.get("error",""))
			if result.ok and leave.is_valid():leave.call()
	)
	var source:=Button.new();source.text="Edit source circuit";tools.add_child(source);source.pressed.connect(func():
		host.open("design",host.bench)
		if leave.is_valid():leave.call()
	)
	var editor=preload("res://scripts/electronics/ic_pcb_editor/package_editor.gd").new()
	editor.size_flags_horizontal=Control.SIZE_EXPAND_FILL;editor.size_flags_vertical=Control.SIZE_EXPAND_FILL
	root.add_child(editor)
	var kit: Dictionary=host.profile.data.kits[host.profile.data.equipped]
	editor.open_project(host.profile,kit.board,draft,kind)
	editor.theme=preload("res://scripts/ui/design_system/theme.gd").create()
	var property_panel: Control=editor.inspector.get_parent() as Control
	property_panel.hide()
	var properties:=Button.new();properties.text="Package properties";tools.add_child(properties);properties.pressed.connect(func():property_panel.visible=not property_panel.visible)
	editor.preview.selected.connect(func(_index):property_panel.show())
	var exposed:=MenuButton.new();exposed.text="Surface controls";tools.add_child(exposed)
	exposed.disabled=kind=="PCB"
	var ids: Array=[]
	var selected: Array=editor.model.draft.get("exposed",[]).duplicate()
	for part in kit.board.parts:
		if str(part.type) not in ["button","toggle","pot10k","led","led_green","led_blue","led_yellow","seven_segment","spi_display","lv_mcu","buzzer","speaker"] and not str(part.type).begins_with("ic:") and not str(part.type).begins_with("io_"):continue
		ids.append(str(part.id));exposed.get_popup().add_check_item(str(part.id)+" · "+str(part.type),ids.size()-1);exposed.get_popup().set_item_checked(ids.size()-1,str(part.id) in selected)
	exposed.get_popup().hide_on_checkable_item_selection=false
	exposed.get_popup().id_pressed.connect(func(index):
		if ids[index] in selected:selected.erase(ids[index])
		else:selected.append(ids[index])
		exposed.get_popup().set_item_checked(index,ids[index] in selected);editor.model.draft.exposed=selected.duplicate()
	)
	editor.saved.connect(func(message):notice.text=message)
	return editor

static func open_saved(host: Node, id: String) -> Dictionary:
	var bp: Dictionary=host.profile.data.get("blueprints",{}).get(id,{})
	if not bp.has("layout"):return {"ok":false,"error":"This definition has no saved source layout."}
	var model=preload("res://scripts/breadboard_model.gd")
	var board: Dictionary=model.empty()
	board.rows=int(bp.layout.rows);board.parts=bp.layout.parts.duplicate(true);board.wires=bp.layout.wires.duplicate(true);board.definitions=host.profile.data.blueprints.duplicate(true)
	board.programs={};board.io_controls={}
	for key in bp.get("programs",{}):board.programs["board/"+str(key)]=bp.programs[key].duplicate(true)
	for key in bp.get("io_controls",{}):board.io_controls["board/"+str(key)]=bp.io_controls[key].duplicate(true)
	for i in mini(4,bp.pins.size()):
		for row in range(1,int(board.rows)+1):
			for letter in "PNABCDEFGHIJ":
				if model.node(letter+str(row),int(board.rows))==str(bp.pins[i].node):board.ports[i]=letter+str(row)
	var error: String=model.validate(board,{},true)
	if error!="":return {"ok":false,"error":error}
	var previous: Dictionary=host.profile.data.duplicate(true)
	var key: String="edit_"+str(Time.get_ticks_usec())
	var items: Dictionary={}
	for part in board.parts:items[part.type]=int(items.get(part.type,0))+1
	host.profile.data.kits[key]={"name":str(bp.name)+" · edit","items":items,"board":board,"package_draft":bp.duplicate(true)};host.profile.data.equipped=key
	if host.profile.save()!=OK:host.profile.data=previous;return {"ok":false,"error":"Could not save source copy"}
	host.open("ics",host.bench)
	return {"ok":true}
