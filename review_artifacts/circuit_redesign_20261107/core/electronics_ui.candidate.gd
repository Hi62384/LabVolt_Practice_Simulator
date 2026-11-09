extends CanvasLayer
const Catalog=preload("res://scripts/electronics_catalog.gd")
const Board=preload("res://scripts/breadboard_model.gd")
var game: Node
var shop_adapter=preload("res://scripts/electronics/component_shop_ui/shop_adapter.gd").new()
var profile=preload("res://scripts/electronics_profile.gd").new()
var screen: PanelContainer
var body: VBoxContainer
var status: Label
var canvas: Control
var active := false
var bench := -1
var creative := false
var current_page := "shop"
var page_scroll: ScrollContainer
var view_cache := {}
var board_view := {}
var shop_search := ""
var notebook_revision := -1
var notebook_id := -1
var designing := false
var design_preview=preload("res://scripts/dc_station.gd").new()
var preview_signature := ""
var preview_clock := 0.0
var analyzer_details: Label
var retired_io_canvases: Array=[]
var panel_generation := 0
var notebook_pending := false
var kit_name_drafts := {}
var kit_name_requests := {}
var kit_name_version := 0
var kit_name_delay := -1.0
var kit_name_saving := false
var kit_name_field: LineEdit
var kit_name_id := ""
var kit_name_character := ""
func build(owner_game: Node) -> void:
	game=owner_game;layer=45
	profile.open(game.characters.selected)
	load_view()
	game.session.restarted.connect(func():notebook_id=-1;notebook_revision=-1;panel_generation+=1;notebook_pending=false;_reset_kit_name_requests())
	game.school.updated.connect(save_notebook)
	game.characters.changed.connect(func():
		if not game.front.in_game:
			profile.open(game.characters.selected);notebook_id=-1;notebook_revision=-1;load_view()
	)
	screen=PanelContainer.new();screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);screen.offset_left=24;screen.offset_right=-24;screen.offset_top=24;screen.offset_bottom=-24;add_child(screen);screen.hide()
	var skin := StyleBoxFlat.new();skin.bg_color=Color("10222c");skin.set_corner_radius_all(12)
	for side in ["left","right","top","bottom"]:skin.set("content_margin_"+side,20)
	screen.add_theme_stylebox_override("panel",skin)
func button(parent: Node,text: String,callback: Callable) -> Button:
	var b := Button.new();b.text=text;b.custom_minimum_size.y=34;parent.add_child(b)
	var generation := panel_generation
	b.pressed.connect(func():
		if active and generation==panel_generation:callback.call()
	)
	return b
func label(parent: Node,text: String) -> Label:
	var l := Label.new();l.text=text
	if parent==body:l.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(l);return l
func close() -> void:
	remember_view()
	active=false
	_flush_kit_names()
	panel_generation+=1;notebook_pending=false
	retire_io_canvas();screen.hide()
	if game.front.in_game:game.capture()
	else:game.front.screen.show()
func open(page := "shop",index := -1) -> void:
	var name_editor_state := _kit_name_editor_state(page)
	_flush_kit_name_navigation(page,index)
	panel_generation+=1;notebook_pending=false
	remember_view();retire_io_canvas();active=true;current_page=page;bench=index;creative=game.school.mode=="Creative Freeplay";designing=page=="design"
	game.release_mouse();game.front.screen.hide();screen.show()
	for child in screen.get_children():screen.remove_child(child);child.queue_free()
	var column := VBoxContainer.new();screen.add_child(column)
	var bar := HBoxContainer.new();column.add_child(bar)
	var title := label(bar,"COMPONENTS" if page=="shop" else "ELECTRONICS STUDIO");title.add_theme_font_size_override("font_size",26);title.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	var economy: Dictionary=profile.get_meta("economy_display",{}) if profile.authority_submit.is_valid() else preload("res://scripts/economy/temporary_playtest/policy.gd").display_snapshot(true)
	label(bar,"Unlimited" if economy.get("unlimited_purchases",false) else "$%d"%profile.data.dollars);button(bar,"Close",close)
	status=label(column,"Creative access · ordinary inventory unchanged" if creative else "Kits are templates. Ownership is counted only in your master inventory.")
	var scroll := ScrollContainer.new();page_scroll=scroll;scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL;column.add_child(scroll)
	body=VBoxContainer.new();body.size_flags_horizontal=Control.SIZE_EXPAND_FILL;scroll.add_child(body)
	if page in ["board","design"]:
		scroll.remove_child(body);column.remove_child(scroll);scroll.queue_free();page_scroll=null
		body.size_flags_vertical=Control.SIZE_EXPAND_FILL;column.add_child(body)
		title.text="Circuit workspace";status.hide()
	if not profile.data.get("pending_trade",{}).is_empty() and page!="trade":
		label(body,"A trade is being saved. Reconnect to the same host if interrupted; your inventory stays reserved until its decision is recovered.");return
	match page:
		"inventory":game.hotbar.manager(body)
		"shop":shop()
		"kits":kits()
		"board", "design":breadboard()
		"notes":notes()
		"ics":custom_ics()
		"code":
			var ide=preload("res://scripts/firmware_ide.gd").new();body.add_child(ide);ide.build(self)
		"kit_world":game.kit_world.menu(body)
		"trade":game.electronics_trade.menu(body)
	_restore_kit_name_editor(name_editor_state)
	_show_kit_name_notice()
	restore_view.call_deferred(page,panel_generation)
func shop() -> void:
	var shop_economy: Dictionary=profile.get_meta("economy_display",{}) if profile.authority_submit.is_valid() else preload("res://scripts/economy/temporary_playtest/policy.gd").display_snapshot(true)
	shop_adapter.build(self,body,{"economy":shop_economy})
	button(body,"Circuit Analyzer · owned" if profile.data.get("analyzer",false) else "Unlock Circuit Analyzer · $75",func():var message: String=profile.buy_analyzer();open("shop",bench);status.text=message)
	label(body,"Assortment boxes · guaranteed contents · 20% bundle discount")
	for bundle in [{"name":"Resistor box","items":{"r1000":10,"r220":10,"r10000":10}},{"name":"Capacitor box","items":{"c0.1":4,"c1.0":4,"c10.0":4}},{"name":"Semiconductor starter","items":{"diode":6,"led":6}}]:
		var price := 0;var contents := ""
		for id in bundle.items:price+=int(Catalog.all()[id].price)*int(bundle.items[id]);contents+="%d × %s   "%[bundle.items[id],Catalog.all()[id].name]
		price=ceili(price*.8);label(body,contents)
		button(body,"%s · $%d"%[bundle.name,price],func():var message: String=profile.purchase_bundle(bundle.items,price);open("shop",bench);status.text=message)
	label(body,"Random assortments · game dollars only · each draw is independent")
	for box_name in profile.BOXES:
		var box: Dictionary=profile.BOXES[box_name];var odds: Array=[]
		for id in box.pool:odds.append("%s %d%%"%[Catalog.all()[id].name,box.pool[id]])
		var buy := button(body,"%s · %d items · $%d"%[box_name,box.draws,box.price],func():var message: String=profile.buy_box(box_name);open("shop",bench);status.text=message)
		buy.tooltip_text="Per-item probabilities: "+", ".join(odds)
		var details := label(body,", ".join(odds));details.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	label(body,"Laboratory accessories · saved to this character")
	for id in profile.COSMETICS:
		var cosmetic: Dictionary=profile.COSMETICS[id];var owned: bool=id in profile.data.get("cosmetics",[])
		button(body,cosmetic.name+(" · Wear" if owned else " · $%d"%cosmetic.price),func():
			if id not in profile.data.get("cosmetics",[]):var message: String=profile.buy_cosmetic(id);open("shop",bench);status.text=message;return
			if game.characters.selected=="":status.text="Create and select a character first.";return
			var config=JSON.parse_string(FileAccess.get_file_as_string(game.characters.ROOT.path_join(game.characters.selected).path_join("character.json")))
			if not config is Dictionary:status.text="Character settings could not be read";return
			config.merge(cosmetic.settings,true);var error: String=game.characters.save_character(game.characters.selected,config)
			if error!="":status.text=error;return
			game.characters.changed.emit();status.text="Accessory equipped and shared with the laboratory."
		)
	button(body,"Capacity +20 · $50",func():
		var message: String=profile.upgrade_capacity()
		open("shop",bench);status.text=message
	)
func kits() -> void:
	var choice := HBoxContainer.new();body.add_child(choice)
	for id in profile.data.kits:button(choice,profile.data.kits[id].name,func():profile.data.equipped=id;profile.save();open("kits",bench))
	button(choice,"New kit",func():
		var id := str(Time.get_ticks_usec());profile.data.kits[id]={"name":"Kit "+str(profile.data.kits.size()+1),"items":{},"board":Board.empty()};profile.data.equipped=id;profile.save();open("kits",bench)
	)
	button(choice,"Duplicate",func():var message: String=profile.duplicate_kit();open("kits",bench);status.text=message)
	button(choice,"Delete template",func():var message: String=profile.delete_kit();open("kits",bench);status.text=message)
	var kit: Dictionary=profile.data.kits[profile.data.equipped]
	var kit_id := str(profile.data.equipped)
	var generation := panel_generation
	var character := str(game.characters.selected)
	var name_field := LineEdit.new();name_field.text=_kit_name_text(kit_id);name_field.max_length=32;body.add_child(name_field)
	kit_name_field=name_field;kit_name_id=kit_id;kit_name_character=character
	name_field.text_changed.connect(func(v):_queue_kit_name(generation,character,kit_id,v))
	label(body,"Equipped · capacity %d · %s"%[profile.data.capacity,profile.kit_error(profile.data.equipped)])
	for type in profile.data.inventory:
		if not profile.catalog().has(type):continue
		var row := HBoxContainer.new();body.add_child(row)
		var text := label(row,"%s · owned %d · %d space each"%[profile.catalog()[type].name,profile.data.inventory[type],profile.catalog()[type].space]);text.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		var amount := SpinBox.new();amount.min_value=0;amount.max_value=profile.data.inventory[type];amount.value=kit.items.get(type,0);row.add_child(amount)
		amount.value_changed.connect(func(v):status.text=profile.set_quantity(type,int(v)))
func _queue_kit_name(generation: int,character: String,id: String,value: String) -> void:
	if not active or generation!=panel_generation or character!=str(game.characters.selected) or not profile.data.kits.has(id):return
	kit_name_version+=1
	if not kit_name_drafts.has(character):kit_name_drafts[character]={}
	kit_name_drafts[character][id]={"value":value.left(32),"version":kit_name_version,"submitted":false,"request":"","error":""}
	kit_name_delay=.5
	_show_kit_name_notice()
func _kit_name_text(id: String) -> String:
	var drafts: Dictionary=kit_name_drafts.get(str(game.characters.selected),{})
	return str(drafts.get(id,{}).get("value",profile.data.kits[id].name))
func _tick_kit_names(delta: float) -> void:
	if kit_name_delay<0 or kit_name_saving:return
	kit_name_delay-=delta
	if kit_name_delay<=0:_flush_kit_names()
func _flush_kit_names() -> void:
	if kit_name_saving:return
	kit_name_delay=-1.0
	var character := str(game.characters.selected)
	var drafts: Dictionary=kit_name_drafts.get(character,{})
	var sent := {}
	for id in drafts.keys():
		if drafts[id].submitted or not profile.data.kits.has(id):continue
		sent[id]=int(drafts[id].version)
		drafts[id].submitted=true;drafts[id].request="";drafts[id].error=""
		profile.data.kits[id].name=str(drafts[id].value)
	if sent.is_empty():return
	var authority_mode: bool=profile.authority_submit.is_valid()
	kit_name_saving=true
	var error: int=profile.save()
	kit_name_saving=false
	if error!=OK:
		for id in sent:
			if drafts.has(id) and int(drafts[id].version)==int(sent[id]):
				drafts[id].submitted=false;drafts[id].request=""
				drafts[id].error="Kit name could not be saved. Draft retained; edit or navigate to retry."
		_show_kit_name_notice()
	elif not authority_mode:
		for id in sent:
			if drafts.has(id) and int(drafts[id].version)==int(sent[id]):drafts.erase(id)
func kit_names_submitted(request_id: String,snapshot: Dictionary) -> void:
	var character := str(game.characters.selected)
	var drafts: Dictionary=kit_name_drafts.get(character,{})
	var versions := {}
	var kits: Dictionary=snapshot.get("kits",{})
	for id in drafts:
		if not kits.has(id) or str(kits[id].name)!=str(drafts[id].value):continue
		versions[id]=int(drafts[id].version)
		drafts[id].submitted=true;drafts[id].request=request_id
	if not versions.is_empty():kit_name_requests[request_id]={"character":character,"versions":versions}
	_show_kit_name_notice()
func kit_names_submission_failed(snapshot: Dictionary,message: String) -> void:
	var drafts: Dictionary=kit_name_drafts.get(str(game.characters.selected),{})
	var kits: Dictionary=snapshot.get("kits",{})
	for id in drafts:
		if not drafts[id].submitted or str(drafts[id].request)!="" or not kits.has(id) or str(kits[id].name)!=str(drafts[id].value):continue
		drafts[id].submitted=false
		drafts[id].error="Kit name rejected: "+message+". Draft retained; edit or navigate to retry."
	_show_kit_name_notice()
func kit_names_result(request_id: String,ok: bool,authoritative: Dictionary,message: String) -> void:
	var record: Dictionary=kit_name_requests.get(request_id,{})
	kit_name_requests.erase(request_id)
	if record.is_empty():return
	var selected := str(game.characters.selected)
	var character := str(record.character)
	var drafts: Dictionary=kit_name_drafts.get(character,{})
	var kits: Dictionary=authoritative.get("kits",{})
	for id in record.versions:
		if not drafts.has(id) or int(drafts[id].version)!=int(record.versions[id]) or str(drafts[id].request)!=request_id:continue
		if ok and kits.has(id) and str(kits[id].name)==str(drafts[id].value):
			drafts.erase(id)
		else:
			drafts[id].submitted=false;drafts[id].request=""
			drafts[id].error=("Host did not confirm kit name" if ok else "Kit name rejected: "+message)+". Draft retained; edit or navigate to retry."
	if character==selected:_show_kit_name_notice()
func _reset_kit_name_requests() -> void:
	kit_name_requests.clear();kit_name_delay=-1.0
	for character in kit_name_drafts:
		var drafts: Dictionary=kit_name_drafts[character]
		for id in drafts:
			if not drafts[id].submitted:continue
			drafts[id].submitted=false;drafts[id].request=""
			drafts[id].error="Inventory session changed. Draft retained; edit or navigate to retry."
func _show_kit_name_notice() -> void:
	if not is_instance_valid(status):return
	var drafts: Dictionary=kit_name_drafts.get(str(game.characters.selected),{})
	for id in drafts:
		if str(drafts[id].error)!="":status.text=str(drafts[id].error);return
	for id in drafts:
		if drafts[id].submitted:status.text="Kit name submitted; waiting for host.";return
	if not drafts.is_empty():status.text="Kit name draft; waiting to save."
func _kit_name_editor_state(page: String) -> Dictionary:
	if not active or current_page!="kits" or page!="kits" or not is_instance_valid(kit_name_field):return {}
	if kit_name_character!=str(game.characters.selected) or kit_name_id!=str(profile.data.equipped) or not kit_name_field.has_focus():return {}
	return {"character":kit_name_character,"id":kit_name_id,"caret":kit_name_field.caret_column,"start":kit_name_field.get_selection_from_column() if kit_name_field.has_selection() else kit_name_field.caret_column,"end":kit_name_field.get_selection_to_column() if kit_name_field.has_selection() else kit_name_field.caret_column,"selected":kit_name_field.has_selection()}
func _restore_kit_name_editor(state: Dictionary) -> void:
	if state.is_empty() or not active or current_page!="kits" or not is_instance_valid(kit_name_field):return
	if str(state.character)!=str(game.characters.selected) or str(state.id)!=kit_name_id:return
	kit_name_field.grab_focus()
	kit_name_field.caret_column=int(state.caret)
	if state.selected:kit_name_field.select(int(state.start),int(state.end))
	else:kit_name_field.deselect()
func _flush_kit_name_navigation(page: String,index: int) -> void:
	if not active:return
	if page==current_page and index==bench and (current_page!="kits" or kit_name_id==str(profile.data.equipped)):return
	active=false
	_flush_kit_names()
	active=true
func breadboard() -> void:
	var adapter=preload("res://scripts/electronics/circuit_workspace/host_adapter.gd").new()
	var workspace: Control=adapter.mount(self)
	workspace.set_meta("host_adapter",adapter)

func deploy() -> void:
	if not game.front.in_game:status.text="Start a laboratory and walk to a DC bench to deploy.";return
	if bench<0:
		bench=clampi(roundi(game.player.position.x/6)+1,0,2)
	var origin: Vector3=game.dc_lab.states[bench].get("board_position",Vector3.ZERO)
	if origin==Vector3.ZERO:origin=Vector3((bench-1)*6,0,8)+game.dc_lab.campus_offset
	if game.player.position.distance_to(origin)>4 and not game.dc_lab.states[bench].get("board_held",false):status.text="Walk to the board or DC bench first.";return
	var kit: Dictionary=profile.data.kits[profile.data.equipped]
	var error: String=profile.kit_error(profile.data.equipped)
	if error!="" and not creative:status.text=error;return
	var design_error: String=Board.validate(kit.board,kit.items,creative)
	if design_error!="":status.text=design_error;return
	game.electronics_trade.authority.request_world(bench,{"op":"board","design":kit.board})
	status.text="Deployment requested · B1–B4 connect this board to the instruments"
func notes() -> void:
	label(body,"Your notebook is the same paper you carry in the laboratory. Writing, drawings and the last page are saved with your character.")
	button(body,"Open my notebook",open_notebook)
	if profile.data.notebook!="":
		label(body,"Earlier typed notes · preserved from the previous notebook")
		var text := TextEdit.new();text.text=profile.data.notebook;text.custom_minimum_size=Vector2(500,250);body.add_child(text)
		text.text_changed.connect(func():profile.data.notebook=text.text.left(100000);profile.save())
func _notebook_current(generation: int,character: String,peer: int) -> bool:
	return active and current_page=="notes" and generation==panel_generation and character==str(game.characters.selected) and game.front.in_game and peer==multiplayer.get_unique_id()
func open_notebook() -> void:
	if notebook_pending or not active or current_page!="notes":return
	if not game.front.in_game:status.text="Start a laboratory to open your notebook.";return
	var peer := multiplayer.get_unique_id()
	var generation := panel_generation
	var character := str(game.characters.selected)
	notebook_pending=true
	for paper in game.school.papers.values():
		if paper.owner==peer and paper.get("notebook",false):close();game.paper_ui.open_sheet(int(paper.id));return
	game.school.request({"op":"notebook"})
	for attempt in 20:
		await get_tree().create_timer(.1).timeout
		if not _notebook_current(generation,character,peer):
			if generation==panel_generation:notebook_pending=false
			return
		for paper in game.school.papers.values():
			if paper.owner==peer and paper.get("notebook",false):close();game.paper_ui.open_sheet(int(paper.id));return
	notebook_pending=false
	status.text="Notebook could not be opened. Put down your held item and leave a hotbar slot free."

func remember_view() -> void:
	if not active:return
	if is_instance_valid(page_scroll):view_cache[current_page]=Vector2(page_scroll.scroll_horizontal,page_scroll.scroll_vertical)
	if current_page in ["board","design"] and is_instance_valid(canvas):board_view[profile.data.equipped]={"zoom":canvas.zoom,"pan":canvas.pan}
	var cfg := ConfigFile.new();cfg.set_value("view","scroll",view_cache);cfg.set_value("view","boards",board_view);cfg.set_value("view","shop_search",shop_search)
	if cfg.save(view_path()+".tmp")==OK:DirAccess.rename_absolute(view_path()+".tmp",view_path())
func restore_view(page: String,generation: int) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	if not active or generation!=panel_generation or page!=current_page or not is_instance_valid(page_scroll):return
	var offset: Vector2=view_cache.get(page,Vector2.ZERO)
	page_scroll.scroll_horizontal=int(offset.x);page_scroll.scroll_vertical=int(offset.y)

func save_notebook() -> void:
	for paper in game.school.papers.values():
		if paper.owner!=multiplayer.get_unique_id() or not paper.get("notebook",false):continue
		if notebook_id==int(paper.id) and notebook_revision==int(paper.revision):return
		notebook_id=int(paper.id);notebook_revision=int(paper.revision)
		preload("res://scripts/notebook_store.gd").write(game.characters.selected,{"page":paper.page,"strokes":paper.strokes,"annotations":paper.get("annotations",{})})

func custom_ics() -> void:
	var draft: Dictionary=profile.data.kits[profile.data.equipped].get("package_draft",{})
	button(body,"Open circuit designer · all parts and analyzer available",func():open("design",bench))
	button(body,"New empty circuit design",func():
		var before: Dictionary=profile.data.duplicate(true);var key := "design_"+str(Time.get_ticks_usec())
		profile.data.kits[key]={"name":"New circuit design","items":{},"board":Board.empty()};profile.data.equipped=key
		if profile.save()!=OK:profile.data=before;status.text="Could not save the new circuit design";return
		open("design",bench)
	)
	var form=preload("res://scripts/package_editor/package_form.gd").new();body.add_child(form);form.build(profile,draft)
	form.saved.connect(func(message):
		if message.begins_with("Blueprint saved:"):open("ics",bench)
		status.text=message
	)
	label(body,"Saved definitions stay unchanged. Saving an edited circuit creates a new revision identity.")
	var Custom=preload("res://scripts/custom_circuit.gd")
	for id in profile.data.get("blueprints",{}):
		var bp: Dictionary=profile.data.blueprints[id];var row := HBoxContainer.new();body.add_child(row)
		var text := label(row,bp.name+" · "+str(bp.pins.size())+" pins · owned "+str(profile.data.inventory.get(id,0)));text.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		button(row,"Inspect package",func():inspect_package(bp))
		if bp.has("layout"):button(row,"Edit a copy",func():edit_package(id))
		if bp.get("package","")=="PCB":
			button(row,"Outline / copper",func():open_pcb_routing(id))
			button(row,"Use standalone",func():prepare_standalone(id))
		button(row,"Buy $%d"%Custom.price(id,profile.data.blueprints),func():var message: String=profile.obtain_ic(id,false);open("ics",bench);status.text=message)
		button(row,"Craft from components",func():var message: String=profile.obtain_ic(id,true);open("ics",bench);status.text=message)
		var contents := "Materials: "
		for type in Custom.materials(id,profile.data.blueprints):contents+="%d × %s  "%[Custom.materials(id,profile.data.blueprints)[type],Catalog.simulation_entry(str(type)).get("name",type)]
		label(body,contents)

func view_path() -> String:return "user://electronics_view_"+game.characters.selected.sha256_text().left(24)+".cfg"
func load_view() -> void:
	view_cache={};board_view={};shop_search=""
	var cfg := ConfigFile.new()
	if cfg.load(view_path())!=OK:return
	var saved_search=cfg.get_value("view","shop_search","")
	if saved_search is String:shop_search=saved_search.left(100)
	var scroll=cfg.get_value("view","scroll",{});var boards=cfg.get_value("view","boards",{})
	if scroll is Dictionary:
		for key in scroll:
			if scroll[key] is Vector2 and scroll[key].is_finite():view_cache[key]=scroll[key]
	if boards is Dictionary:
		for key in boards:
			var item=boards[key]
			if item is Dictionary and item.get("pan") is Vector2 and item.pan.is_finite() and is_finite(float(item.get("zoom",1))):board_view[key]={"pan":item.pan,"zoom":clampf(float(item.get("zoom",1)),.6,2)}

func _process(_delta: float) -> void:
	_tick_kit_names(_delta)
	refresh_retired_io()
	if active and is_instance_valid(canvas) and is_instance_valid(analyzer_details):
		analyzer_details.text=canvas.inspection_text();analyzer_details.visible=canvas.analyzer_enabled and analyzer_details.text!=""
	if active and designing and is_instance_valid(canvas):
		var structural: Dictionary=canvas.board.duplicate(true);structural.erase("io_controls")
		var signature := str(structural)
		if signature!=preview_signature:
			preview_signature=signature;canvas.capture.samples.clear();design_preview=preload("res://scripts/dc_station.gd").new();design_preview.apply({"op":"board","design":canvas.board.duplicate(true)})
		preview_clock=minf(preview_clock+_delta,.02)
		while preview_clock>=.0005:
			design_preview.step(.0005);preview_clock-=.0005;canvas.accept_measurements(design_preview.result)
		canvas.accept_measurements(design_preview.result);canvas.currents=design_preview.result.get("i",{});canvas.device_states=design_preview.firmware_states;canvas.queue_redraw()
		return
	if not active or current_page!="board" or bench<0 or not is_instance_valid(canvas):return
	var state: Dictionary=game.dc_lab.states[bench]
	if state.get("board_owner",0)!=multiplayer.get_unique_id():return
	for part in canvas.board.parts:
		for live in state.get("board",{}).get("parts",[]):
			if str(part.id)==str(live.id):
				for key in ["pressed","setting"]:
					if live.has(key):part[key]=live[key]
	canvas.board.controls=state.get("board",{}).get("controls",{}).duplicate(true)
	var io_now: Dictionary=state.get("board",{}).get("io_controls",{}).duplicate(true)
	canvas.board.io_controls=io_now
	var kit: Dictionary=profile.data.kits.get(profile.data.equipped,{})
	if not kit.is_empty() and kit.board.get("io_controls",{})!=io_now:kit.board.io_controls=io_now.duplicate(true);profile.save()
	canvas.device_states=state.get("firmware",{})
	canvas.queue_redraw()
	canvas.accept_measurements(state.get("result",{}))
	var measured: Dictionary=state.get("result",{}).get("i",{})
	if measured!=canvas.currents:canvas.currents=measured;canvas.queue_redraw()

func prepare_standalone(id: String) -> void:
	if not creative and int(profile.data.inventory.get(id,0))<1:status.text="Buy or craft this PCB first.";return
	var design: Dictionary=Board.standalone(id,profile.data.blueprints)
	if design.is_empty():status.text="Invalid PCB definition";return
	var key := "standalone_"+id.trim_prefix("ic:")
	if not profile.data.kits.has(key):profile.data.kits[key]={"name":profile.data.blueprints[id].name,"items":{id:1},"board":design}
	profile.data.equipped=key
	if profile.save()!=OK:status.text="Could not save the PCB loadout";return
	open("board",bench)
func pcb_inspector() -> void:
	label(body,"STANDALONE PCB · Each X pin uses the name you assigned in the builder.")
	var tools := HFlowContainer.new();body.add_child(tools)
	button(tools,"Deploy at DC bench",deploy)
	button(tools,"Carry",func():
		if bench>=0:game.dc_lab.request(bench,{"op":"carry_board"});close()
	)
	button(tools,"Code",func():open("code",bench))
	button(tools,"Recall / disconnect",func():
		if bench>=0:game.dc_lab.request(bench,{"op":"recall"})
	)
	canvas=preload("res://scripts/breadboard_canvas.gd").new();canvas.board=profile.data.kits[profile.data.equipped].board.duplicate(true);canvas.read_only=true;body.add_child(canvas)
	wire_io_canvas(canvas)
	button(tools,"Interact with I/O",func():canvas.selected_type="interact")
	var analyzer := CheckButton.new();analyzer.text="Circuit Analyzer";analyzer.disabled=not (creative or profile.data.get("analyzer",false));tools.add_child(analyzer)
	analyzer.toggled.connect(func(on):canvas.analyzer_enabled=on;canvas.queue_redraw())
	analyzer_tools(tools,analyzer)
	label(body,"Use its named pins to connect leads. Operate switches and knobs directly on the PCB in the room. Disconnect leads before carrying or stowing it.")

func edit_package(id: String) -> void:
	if profile.data.blueprints.get(id,{}).has("pcb_design"):
		open_pcb_routing(id);return
	var bp: Dictionary=profile.data.blueprints.get(id,{})
	if not bp.has("layout"):status.text="This older definition has no saved physical layout.";return
	var design: Dictionary=Board.empty()
	design.rows=int(bp.layout.rows);design.parts=bp.layout.parts.duplicate(true);design.wires=bp.layout.wires.duplicate(true)
	design.definitions=profile.data.blueprints.duplicate(true);design.programs={}
	design.io_controls={}
	for key in bp.get("io_controls",{}):design.io_controls["board/"+str(key)]=bp.io_controls[key].duplicate(true)
	for key in bp.get("programs",{}):design.programs["board/"+str(key)]=bp.programs[key].duplicate(true)
	for i in mini(4,bp.pins.size()):
		for row in range(1,int(design.rows)+1):
			for letter in "PNABCDEFGHIJ":
				var hole := letter+str(row)
				if Board.node(hole,int(design.rows))==str(bp.pins[i].node):design.ports[i]=hole
	var key := "edit_"+str(Time.get_ticks_usec());var items := {}
	for part in design.parts:items[part.type]=int(items.get(part.type,0))+1
	profile.data.kits[key]={"name":str(bp.name)+" · edit","items":items,"board":design,"package_draft":bp.duplicate(true)}
	profile.data.equipped=key
	if profile.save()!=OK:status.text="Could not save the editable copy";return
	open("design",bench)
	status.text="Editing a copy. Save a new package in IC / PCB builder; existing owned copies stay unchanged."

func analyzer_tools(parent: Node,toggle: CheckButton) -> void:
	var tools := HFlowContainer.new();body.add_child(tools)
	for pair in [["+ probe","probe+"],["− probe","probe-"]]:
		var control := button(tools,pair[0],func():canvas.selected_type=pair[1])
		control.disabled=toggle.disabled
	var volts := CheckButton.new();volts.text="Node colors";volts.button_pressed=true;tools.add_child(volts)
	volts.toggled.connect(func(on):canvas.voltage_overlay=on;canvas.queue_redraw())
	var amps := CheckButton.new();amps.text="Current arrows";amps.button_pressed=true;tools.add_child(amps)
	amps.toggled.connect(func(on):canvas.current_overlay=on;canvas.queue_redraw())
	var timing := CheckButton.new();timing.text="Voltage / timing trace";tools.add_child(timing)
	timing.toggled.connect(func(on):canvas.timing_visible=on;canvas.queue_redraw())
	var hold := CheckButton.new();hold.text="Hold capture";tools.add_child(hold)
	hold.toggled.connect(func(on):canvas.capture.held=on)
	button(tools,"Clear capture",func():canvas.capture.samples.clear();canvas.queue_redraw())
	label(tools,"Logic threshold V")
	var threshold := SpinBox.new();threshold.min_value=-1000;threshold.max_value=1000;threshold.step=.1;threshold.value=2.5;tools.add_child(threshold)
	threshold.value_changed.connect(func(value):canvas.capture.threshold=value;canvas.queue_redraw())
	label(body,"Trace uses received solver timestamps only. Fast signals may alias in live network snapshots. HIGH/LOW is a configurable voltage comparison; high impedance requires backend drive-state data.")
	analyzer_details=label(body,"");analyzer_details.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART

func inspect_package(bp: Dictionary) -> void:
	var dialog := AcceptDialog.new();dialog.title=str(bp.get("name","Package"));screen.add_child(dialog)
	var scroll := ScrollContainer.new();scroll.custom_minimum_size=Vector2(700,420);dialog.add_child(scroll)
	var lines: Array=[str(bp.get("description",""))]
	var fp: Dictionary=bp.get("footprint",{})
	lines.append("%s · %d pins · footprint %s × %s grid"%[bp.get("package","IC"),bp.pins.size(),fp.get("width","legacy"),fp.get("height","legacy")])
	lines.append("IC body height: %s mm · PCB thickness: %s mm"%[fp.get("body_height_mm","legacy default"),fp.get("thickness_mm","legacy default")])
	lines.append("Marking: %s · marker: %s"%[bp.get("marking",""),bp.get("orientation_marker","dot")])
	for index in bp.pins.size():
		var pin: Dictionary=bp.pins[index]
		lines.append("X%d · %s [%s] → %s · grid %s · %s / %s"%[index+1,pin.name,pin.get("id","pin_%d"%(index+1)),pin.node,str(pin.get("position","legacy")),pin.get("role","unspecified"),pin.get("connector","male_header")])
	var text := label(scroll,"\n".join(lines));text.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	dialog.confirmed.connect(dialog.queue_free);dialog.canceled.connect(dialog.queue_free);dialog.popup_centered()

func wire_io_canvas(target: Control) -> void:
	var target_bench := bench;var target_kit: String=profile.data.equipped;var preview := designing
	target.set_meta("io_bench",target_bench);target.set_meta("io_kit",target_kit)
	var bound_epoch: int=int(game.dc_lab.states[target_bench].get("board_epoch",0)) if target_bench>=0 and target_bench<game.dc_lab.states.size() else -1
	target.set_meta("io_epoch",bound_epoch)
	target.code_requested.connect(func(_id):open("code",target_bench))
	var view_token := str(target.get_instance_id())
	target.set_meta("io_view_token",view_token)
	target.io_command_requested.connect(func(id,command):
		if preview:apply_preview_io(target,target_kit,id,command)
		elif target_bench>=0:game.dc_lab.request(target_bench,{"op":"input","id":id,"command":command,"board_epoch":bound_epoch,"view_token":view_token})
		else:
			if is_instance_valid(status):status.text="Deploy this circuit at a DC bench, or use the isolated designer to operate its inputs."
			target.acknowledge_io(id,Board.io_inputs(target.board).get(id,{}))
	)
func apply_preview_io(target: Control,kit_id: String,id: String,command: Dictionary) -> void:
	if not ResourceLoader.exists("res://scripts/io_devices/controls.gd"):return
	var controls=load("res://scripts/io_devices/controls.gd")
	var kind := ""
	for device in Board.devices(target.board):
		if str(device.id)==id:kind=str(device.part.type);break
	var old: Dictionary=Board.io_inputs(target.board).get(id,controls.defaults(kind))
	var changed: Dictionary=controls.apply(kind,old,command)
	if not changed.ok:
		target.acknowledge_io(id,old)
		if is_instance_valid(status):status.text=str(changed.error)
		return
	var before: Dictionary=profile.data.duplicate(true)
	var saved: Dictionary=target.board.get("io_controls",{}).duplicate(true);saved[id]=changed.state
	profile.data.kits[kit_id].board.io_controls=saved.duplicate(true)
	if profile.save()!=OK:
		profile.data=before;target.acknowledge_io(id,old)
		if is_instance_valid(status):status.text="Could not save this I/O input state"
		return
	target.board.io_controls=saved
	# This is the one isolated preview authority; changing input never reapplies the board.
	if target==canvas and not design_preview.board.is_empty():design_preview.board.io_controls=saved.duplicate(true)
	target.acknowledge_io(id,changed.state);target.queue_redraw()
func retire_io_canvas() -> void:
	if not is_instance_valid(canvas):canvas=null;return
	canvas.release_io_capture()
	if canvas.has_pending_io():
		var target: Control=canvas
		if target.get_parent()!=null:target.get_parent().remove_child(target)
		add_child(target);target.hide()
		retired_io_canvases.append({"canvas":target,"bench":int(target.get_meta("io_bench",-1)),"kit":str(target.get_meta("io_kit",""))})
	canvas=null
func refresh_retired_io() -> void:
	for entry in retired_io_canvases.duplicate():
		var target: Control=entry.canvas
		if not is_instance_valid(target):retired_io_canvases.erase(entry);continue
		if int(entry.bench)>=0 and int(entry.bench)<game.dc_lab.states.size():
			var state: Dictionary=game.dc_lab.states[int(entry.bench)]
			target.board.io_controls=state.get("board",{}).get("io_controls",{}).duplicate(true);target.device_states=state.get("firmware",{})
			if state.get("board_owner",0)==multiplayer.get_unique_id() and profile.data.kits.has(str(entry.kit)):
				var kit: Dictionary=profile.data.kits[str(entry.kit)]
				if kit.board.get("io_controls",{})!=target.board.io_controls:kit.board.io_controls=target.board.io_controls.duplicate(true);profile.save()
			target.refresh_io_surfaces()
		if not target.has_pending_io():target.queue_free();retired_io_canvases.erase(entry)
## Core calls this on input rejection too; same-revision snapshots alone cannot acknowledge rejection.
func acknowledge_io_input(index: int,id: String,control: Dictionary,epoch: int=-1,view := "") -> void:
	if is_instance_valid(canvas) and int(canvas.get_meta("io_bench",-1))==index and (epoch<0 or int(canvas.get_meta("io_epoch",-1))==epoch) and (view=="" or str(canvas.get_meta("io_view_token",""))==view):canvas.acknowledge_io(id,control)
	for entry in retired_io_canvases:
		if int(entry.bench)==index and is_instance_valid(entry.canvas) and (epoch<0 or int(entry.canvas.get_meta("io_epoch",-1))==epoch) and (view=="" or str(entry.canvas.get_meta("io_view_token",""))==view):entry.canvas.acknowledge_io(id,control)

func open_pcb_routing(id: String) -> void:
	var bp: Dictionary=profile.data.get("blueprints",{}).get(id,{})
	if bp.get("package","")!="PCB":return
	open("pcb_routing",bench)
	var editor=preload("res://scripts/pcb_design/editor.gd").new()
	body.add_child(editor);editor.build(profile,bp)
	editor.saved.connect(func(message: String):status.text=message)
