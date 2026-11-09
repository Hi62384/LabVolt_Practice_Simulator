extends VBoxContainer

const Projects = preload("res://scripts/electronics/circuit_workspace/projects.gd")
const Converter = preload("res://scripts/electronics/ic_pcb_editor/converter.gd")
const Upgrade = preload("res://scripts/electronics/ic_pcb_editor/upgrade.gd")
const Custom = preload("res://scripts/custom_circuit.gd")
const Board = preload("res://scripts/breadboard_model.gd")
const UI = preload("res://scripts/ui/design_system/widgets.gd")
const SourceCanvas = preload("res://scripts/electronics/ic_pcb_editor/source_canvas.gd")
const PackagePreview = preload("res://scripts/electronics/ic_pcb_editor/package_preview.gd")
const View3D = preload("res://scripts/electronics/ic_pcb_editor/package_view_3d.gd")

var game: Node
var profile: RefCounted
var close_station: Callable
var model = Converter.new()
var kind := "IC"
var surface_mode := false
var selected_surface := ""
var pcb_width: SpinBox
var pcb_length: SpinBox
var pcb_size: Label
var previews := {}
var page: String
var active_id := ""
var active_source := ""
var source_entry := {}
var pending := ""
var pending_proposal := {}
var replace_hole := -1
var selected_pin := -1
var notice: Label
var footer: HBoxContainer
var area: HBoxContainer
var source_preview: Control
var package_preview: Control
var view_3d: Control
var mappings: VBoxContainer
var pin_list: VBoxContainer
var main_action: Button
var external_pins_tab: Button
var surface_components_tab: Button

func setup(owner: Node, leave: Callable, package_kind := "IC") -> void:
	kind = package_kind
	model.set_kind(kind)
	game = owner
	profile = game.electronics.profile
	close_station = leave
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation",12)
	game.electronics_trade.authority.operation_result.connect(_result)
	library()

func _clear(node: Node) -> void:
	for child in node.get_children():
		node.remove_child(child)
		child.queue_free()

func _screen(name: String, title: String, hint: String) -> void:
	page = name
	_clear(self)
	source_preview = null
	package_preview = null
	view_3d = null
	pcb_width = null
	pcb_length = null
	pcb_size = null
	main_action = null
	var bar := HBoxContainer.new()
	add_child(bar)
	var heading := UI.text(title,"TitleLabel")
	bar.add_child(heading)
	bar.add_child(UI.action("Close","close",close_station))
	if not hint.is_empty(): add_child(UI.text(hint,"MutedLabel"))
	area = HBoxContainer.new()
	area.size_flags_vertical = Control.SIZE_EXPAND_FILL
	area.add_theme_constant_override("separation",12)
	add_child(area)
	notice = UI.text("","MutedLabel")
	add_child(notice)
	footer = HBoxContainer.new()
	add_child(footer)

func _nav(back: Callable, label: String = "", next: Callable = Callable()) -> Button:
	footer.add_child(UI.action("Back","back",back))
	var space := Control.new()
	space.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(space)
	if label.is_empty(): return null
	var button := UI.action(label,"forward",next,true)
	footer.add_child(button)
	return button

func _scroll(parent: Control, width: int = 0) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size.x = width
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL if width == 0 else Control.SIZE_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(scroll)
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(column)
	return column

func _grid(parent: VBoxContainer) -> HFlowContainer:
	var grid := HFlowContainer.new()
	grid.add_theme_constant_override("h_separation",12)
	grid.add_theme_constant_override("v_separation",12)
	parent.add_child(grid)
	return grid

func _card(grid: HFlowContainer, title: String, details: String, image: Texture2D, click: Callable) -> void:
	var card := VBoxContainer.new()
	grid.add_child(card)
	var button := UI.action(title,"",click)
	button.icon = image
	button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	button.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
	button.add_theme_constant_override("icon_max_width",140)
	button.custom_minimum_size = Vector2(205,116)
	button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	card.add_child(button)
	var detail := UI.text(details,"MutedLabel")
	detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	card.add_child(detail)

func _creative() -> bool:
	return game.school.mode == "Creative Freeplay"

func _name(id: String) -> String:
	return str(profile.data.get("ic_library",{}).get(id,{}).get("name",profile.data.blueprints[id].name))

func _dimensions(bp: Dictionary) -> String:
	var f: Dictionary = bp.get("footprint",{})
	if f.is_empty(): return "Legacy footprint"
	return "%d × %d grid" % [bp.get("width_intervals",f.width),bp.get("length_positions",f.height)]

func library(message: String = "") -> void:
	_screen("library",kind+" Builder","My "+kind+" blueprints")
	notice.text = message
	var column := _scroll(area)
	column.add_child(UI.action("New "+kind,"plus",func():
		model = Converter.new()
		model.set_kind(kind)
		surface_mode = false
		active_source = ""
		source_entry = {}
		sources(),true))
	var grid := _grid(column)
	var definitions: Dictionary = profile.data.get("blueprints",{})
	for id in definitions:
		var bp: Dictionary = definitions[id]
		if bp.get("package","IC") != kind or profile.data.get("ic_library",{}).get(id,{}).get("archived",false): continue
		var detail := "%d pins · %s · $%d" % [bp.pins.size(),_dimensions(bp),Custom.price(id,definitions)]
		_card(grid,_name(id),detail,_chip_image(bp),details.bind(id))
	if grid.get_child_count() == 0: column.add_child(UI.text("Save a circuit in Custom Circuit Maker to create your first "+kind+"."))

func sources() -> void:
	_screen("source",("1 / 4" if kind == "PCB" else "1 / 3")+"   Choose a source circuit","Select a saved Custom Circuit Maker project.")
	var column := _scroll(area,440)
	var grid := _grid(column)
	var entries := Projects.read_projects(str(game.characters.selected))
	for id in entries:
		var entry: Variant = entries[id]
		if not entry is Dictionary or not entry.get("board") is Dictionary: continue
		var source: Dictionary = entry.board
		var error := Converter.source_error(source,profile.data.get("blueprints",{}))
		var image: Texture2D = Projects.thumbnail(source) if error.is_empty() else null
		var date := Time.get_date_string_from_unix_time(int(entry.get("modified",0)))
		var detail := "%d components · %s" % [source.get("parts",[]).size(),date] if error.is_empty() else "Cannot package this circuit"
		_card(grid,str(entry.get("name","Untitled")),detail,image,_select_source.bind(id,entry))
	if grid.get_child_count() == 0: column.add_child(UI.text("No saved circuits. Save one in Custom Circuit Maker first."))
	var preview := VBoxContainer.new()
	preview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	area.add_child(preview)
	preview.add_child(UI.text("Circuit preview","SubtitleLabel"))
	source_preview = _board_view(preview,model.board,false) if not model.board.is_empty() else null
	main_action = _nav(func():
		if model.parent_revision.is_empty(): library()
		else: details(model.parent_revision), "Next", holes)
	main_action.disabled = model.board.is_empty()

func _select_source(id: String, entry: Dictionary) -> void:
	var previous: String = model.parent_revision
	if previous.is_empty():
		var error: String = model.select_source(id,entry,profile.data.get("blueprints",{}))
		if not error.is_empty(): notice.text = error; return
	else:
		var revised = Converter.new()
		revised.set_kind(kind)
		var error: String = revised.select_source(id,entry,profile.data.get("blueprints",{}))
		if not error.is_empty(): notice.text = error; return
		for connection in model.connections:
			if Board.node(connection.hole,int(revised.board.rows)).is_empty():
				notice.text = "%s is outside the replacement board. Use a larger circuit." % connection.hole
				return
		for part_id in model.surface.keys():
			var prior_type: String = model.surface_type(part_id)
			if not revised.board.parts.any(func(part):return part.id == part_id and part.type == prior_type):
				model.surface.erase(part_id)
		model.board = revised.board
		model.source_id = revised.source_id
		model.source_revision = revised.source_revision
	active_source = id
	source_entry = entry
	sources()

func _board_view(parent: Node, board: Dictionary, picking: bool) -> Control:
	var view := SourceCanvas.new()
	view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	view.board = board.duplicate(true)
	view.inventory_catalog = Board.catalog(board)
	view.picking = picking
	parent.add_child(view)
	view.custom_minimum_size = Vector2(240,160)
	return view

func _locked() -> bool:
	return not _creative() and not model.parent_revision.is_empty() and Upgrade.locked(profile.data,model.parent_revision)

func holes() -> void:
	replace_hole = -1
	var pcb := kind == "PCB"
	_screen("holes",("2 / 4   Choose pins and surface parts" if pcb else "2 / 3   Choose external holes"),
		"Middle-drag to pan and use the wheel to zoom.")
	var workspace := VBoxContainer.new()
	workspace.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	area.add_child(workspace)
	if pcb:
		var tabs := HBoxContainer.new()
		workspace.add_child(tabs)
		external_pins_tab = UI.action("External Pins","",_surface_mode.bind(false),not surface_mode)
		surface_components_tab = UI.action("Surface Components","",_surface_mode.bind(true),surface_mode)
		tabs.add_child(external_pins_tab)
		tabs.add_child(surface_components_tab)
	source_preview = _board_view(workspace,model.board,true)
	source_preview.picking_surface = pcb and surface_mode
	source_preview.surface_chosen.connect(_toggle_surface)
	source_preview.hole_chosen.connect(func(hole: String):
		if _locked() and replace_hole < 0:
			notice.text = "Use Change hole to remap an existing physical pin."
			return
		var error: String = model.choose_hole(hole,replace_hole)
		if not error.is_empty(): notice.text = error; return
		replace_hole = -1
		_refresh_holes()
		var index: int = model.connection_index(hole)
		var name_field := pin_list.get_child(index).get_child(1) as LineEdit
		name_field.grab_focus()
		name_field.select_all())
	pin_list = _scroll(area,350)
	main_action = _nav(sources,"Next",designer)
	_refresh_holes()

func _surface_mode(enabled: bool) -> void:
	surface_mode = enabled
	external_pins_tab.theme_type_variation = "Button" if enabled else "PrimaryButton"
	surface_components_tab.theme_type_variation = "PrimaryButton" if enabled else "Button"
	source_preview.picking_surface = enabled
	replace_hole = -1
	_refresh_holes()

func _part_name(id: String) -> String:
	var type: String = model.surface_type(id)
	return str(Board.catalog(model.board).get(type,{}).get("name",type))

func _toggle_surface(id: String) -> void:
	model.prepare_package()
	var changed: bool = model.toggle_surface(id,not _locked())
	_refresh_holes()
	if not changed: notice.text = "This part does not fit. Remove a surface part or use a larger board."

func _refresh_holes() -> void:
	_clear(pin_list)
	source_preview.surface_selection = model.surface
	if kind == "PCB" and surface_mode:
		pin_list.add_child(UI.text("Visible on PCB · %d" % model.surface.size(),"SubtitleLabel"))
		pin_list.add_child(UI.text("Click an installed component to show or hide that instance."))
		for id in model.surface:
			pin_list.add_child(UI.action("%s · %s  ×" % [id,_part_name(id)],"",_toggle_surface.bind(id)))
		_mark_holes()
		_check_holes()
		return
	for index in model.connections.size():
		var connection: Dictionary = model.connections[index]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation",6)
		pin_list.add_child(row)
		var hole_label := UI.text("%s · %s" % [connection.hole,Board.node(connection.hole,int(model.board.rows))])
		hole_label.autowrap_mode=TextServer.AUTOWRAP_OFF
		hole_label.size_flags_horizontal=Control.SIZE_FILL
		hole_label.vertical_alignment=VERTICAL_ALIGNMENT_CENTER
		row.add_child(hole_label)
		var name_field := LineEdit.new()
		name_field.text = connection.name
		name_field.max_length = 24
		name_field.custom_minimum_size.x = 72
		name_field.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		row.add_child(name_field)
		name_field.text_changed.connect(func(value):
			connection.name = value
			_mark_holes()
			_check_holes())
		var change := UI.action("","refresh",func():
			replace_hole = index
			source_preview.active_hole_marker = connection.hole
			source_preview.queue_redraw()
			notice.text = "Click the replacement hole for %s." % connection.name)
		_pin_row_action(row,change,"Change hole")
		if not _locked():
			var remove := UI.action("","trash",func():
				model.connections.remove_at(index)
				replace_hole = -1
				_refresh_holes())
			_pin_row_action(row,remove,"Remove pin")
	_mark_holes()
	_check_holes()

func _pin_row_action(row: HBoxContainer, button: Button, title: String) -> void:
	button.accessibility_name=title
	button.tooltip_text=title
	button.custom_minimum_size=Vector2(42,36)
	button.icon_alignment=HORIZONTAL_ALIGNMENT_CENTER
	button.size_flags_vertical=Control.SIZE_SHRINK_CENTER
	row.add_child(button)

func _mark_holes() -> void:
	source_preview.markers.clear()
	for connection in model.connections: source_preview.markers[connection.hole] = connection.name
	source_preview.active_hole_marker = model.connections[replace_hole].hole if replace_hole >= 0 else ""
	source_preview.queue_redraw()

func _check_holes() -> void:
	notice.text = model.pin_error()
	main_action.disabled = not notice.text.is_empty()

func designer() -> void:
	var pcb := kind == "PCB"
	model.prepare_package()
	selected_pin = -1
	var title := "3 / 4   Design the PCB" if pcb else "3 / 3   Design package and map pins"
	_screen("design",title,"Drag mounted components or press R to rotate 90°." if pcb else "Each grid interval is 2.54 mm.")
	selected_surface = ""
	var visual := VBoxContainer.new()
	visual.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	area.add_child(visual)
	package_preview = _package_view(visual,true)
	package_preview.edit_surface = pcb
	package_preview.surface_selected.connect(func(id: String):
		selected_surface = id
		_refresh_mapping())
	package_preview.surface_move.connect(func(id: String, point: Vector2i, rotation: int):
		if not model.surface_transform(id,point,rotation,not _locked()):
			notice.text = "Keep each component inside the board and clear of other parts and pins."
		else:
			notice.text = ""
			_refresh_package())
	package_preview.selected.connect(func(index):selected_pin=index;_refresh_mapping())
	package_preview.moved.connect(func(index,point):
		if _locked(): return
		if not model.move_pin(index,point):
			notice.text = "Choose an unused grid cell along either side of the chip."
		else: notice.text = ""; _refresh_package())
	var tools := HBoxContainer.new()
	visual.add_child(tools)
	var rotate := UI.action("Rotate 90°","",func():
		model.turns = (model.turns+1)%4
		model.sync()
		_refresh_package())
	rotate.disabled = _locked()
	if not pcb: tools.add_child(rotate)
	if pcb:
		tools.add_child(UI.action("Rotate part 90°","",func():package_preview.rotate_surface()))
		var fit := UI.action("Fit to Components","",func():
			var minimum: Vector2i = model.surface_minimum()
			model.resize_package(minimum.x,minimum.y)
			_refresh_package())
		fit.disabled = _locked()
		tools.add_child(fit)
	tools.add_child(UI.action("2D / 3D preview","",func():
		if not is_instance_valid(view_3d):
			view_3d = View3D.new()
			view_3d.model = model
			view_3d.size_flags_vertical = Control.SIZE_EXPAND_FILL
			visual.add_child(view_3d)
			visual.move_child(view_3d,0)
			view_3d.refresh()
		else: view_3d.visible = not view_3d.visible
		package_preview.visible = not view_3d.visible))
	var settings := _scroll(area,300)
	if _locked(): settings.add_child(UI.text("Manufactured package · Physical dimensions and pin positions are locked.","MutedLabel"))
	if not pcb: _field(settings,kind+" name",str(model.draft.name),40,func(value):model.draft.name=value)
	var dimensions := HBoxContainer.new()
	settings.add_child(dimensions)
	var width_column := VBoxContainer.new()
	width_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dimensions.add_child(width_column)
	var length_column := VBoxContainer.new()
	length_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dimensions.add_child(length_column)
	var width := _number(width_column,"Width · intervals",1 if pcb else mini(2, model.width),39,model.width)
	var length := _number(length_column,"Length · positions",model.left_count(),40,model.length)
	if pcb:
		pcb_width = width
		pcb_length = length
		pcb_size = UI.text("","MutedLabel")
		settings.add_child(pcb_size)
		_refresh_package()
	for field in [width,length]: field.editable = not _locked()
	width.value_changed.connect(func(value):model.resize_package(int(value),model.length);_refresh_package())
	length.value_changed.connect(func(value):model.resize_package(model.width,int(value));_refresh_package())
	mappings = VBoxContainer.new()
	settings.add_child(mappings)
	_refresh_mapping()
	var appearance := VBoxContainer.new()
	var appearance_button := UI.action("Package appearance","",func():appearance.visible=not appearance.visible)
	if not pcb: settings.add_child(appearance_button)
	settings.add_child(appearance)
	appearance.visible = pcb
	if not pcb: _field(appearance,"Description",str(model.draft.description),200,func(value):model.draft.description=value)
	if not pcb: _field(appearance,"Surface marking",str(model.draft.marking),24,func(value):model.draft.marking=value;_refresh_package())
	var dimension_key := "thickness_mm" if pcb else "body_height_mm"
	var height := _number(appearance,"Thickness in mm" if pcb else "Body height in mm",.5,20,model.draft.footprint[dimension_key],.1)
	height.editable = not _locked()
	height.value_changed.connect(func(value):model.draft.footprint[dimension_key]=value;_refresh_package())
	appearance.add_child(UI.text("Board color" if pcb else "Body color","MutedLabel"))
	var color := ColorPickerButton.new()
	color.color = Color(str(model.draft.footprint.color))
	color.custom_minimum_size.y = 35
	appearance.add_child(color)
	color.color_changed.connect(func(value: Color):model.draft.footprint.color=value.to_html(false);_refresh_package())
	if pcb: main_action = _nav(holes,"Next",_pcb_review)
	else: main_action = _nav(holes,"Save IC Blueprint" if model.parent_revision.is_empty() else "Review Update",_save)

func _pcb_review() -> void:
	_screen("review","4 / 4   Save PCB Blueprint","Review the board before saving.")
	package_preview = _package_view(area,false)
	var column := _scroll(area,330)
	_field(column,"PCB name",str(model.draft.name),40,func(value):model.draft.name=value)
	_field(column,"Description",str(model.draft.description),200,func(value):model.draft.description=value)
	column.add_child(UI.text("%d external pins · %d mounted parts" % [model.pins.size(),model.surface.size()]))
	var result: Dictionary = model.prepare_blueprint(profile)
	if result.has("id"):
		column.add_child(UI.text("$%d per copy" % Custom.price(result.id,result.definitions),"SubtitleLabel"))
	_nav(designer,"Save PCB Blueprint" if model.parent_revision.is_empty() else "Review Update",_save)

func _package_view(parent: Control, interactive: bool) -> Control:
	var preview := PackagePreview.new()
	preview.model = model
	preview.chip_style = kind == "IC"
	preview.interactive = interactive
	preview.allow_drag = interactive and not _locked()
	preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
	preview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(preview)
	return preview

func _refresh_package() -> void:
	if is_instance_valid(pcb_size):
		var minimum: Vector2i = model.surface_minimum()
		_set_board_dimension(pcb_width, minimum.x, model.width)
		_set_board_dimension(pcb_length, minimum.y, model.length)
		pcb_size.text = "%.2f × %.2f mm · Minimum %d × %d grid" % [(model.width+1)*2.54,model.length*2.54,minimum.x,minimum.y]
	if is_instance_valid(package_preview): package_preview.queue_redraw()
	if is_instance_valid(view_3d): view_3d.refresh()

func _set_board_dimension(field: SpinBox, minimum: int, value: int) -> void:
	# Raising a Range minimum can emit value_changed and resize the board mid-refresh.
	field.set_block_signals(true)
	field.min_value = minimum
	field.set_value_no_signal(value)
	field.set_block_signals(false)

func _refresh_mapping() -> void:
	_clear(mappings)
	if kind == "PCB" and package_preview.edit_surface:
		mappings.add_child(UI.text("Select a mounted component." if selected_surface.is_empty() else _part_name(selected_surface),"MutedLabel"))
		return
	if selected_pin < 0:
		mappings.add_child(UI.text("Select a physical pin to inspect or remap its connection.","MutedLabel"))
		return
	var pin: Dictionary = model.pins[selected_pin]
	mappings.add_child(UI.text("Pin %d · %s · node %s" % [pin.number,pin.source_hole,pin.node],"SubtitleLabel"))
	var choice := OptionButton.new()
	for connection in model.connections:
		choice.add_item("%s · %s" % [connection.name,connection.hole])
	choice.select(model.connection_index(pin.source_hole))
	mappings.add_child(choice)
	choice.item_selected.connect(func(index: int):
		model.remap(selected_pin,model.connections[index].hole)
		_refresh_package()
		_refresh_mapping())
	mappings.add_child(UI.action("Show source hole","",func():
		var dialog := AcceptDialog.new()
		dialog.title = "Pin %d · %s" % [pin.number,pin.name]
		add_child(dialog)
		var view := _board_view(dialog,model.board,false)
		view.custom_minimum_size = Vector2(660,340)
		view.markers = {pin.source_hole:pin.name}
		view.active_hole_marker = pin.source_hole
		dialog.confirmed.connect(dialog.queue_free)
		dialog.canceled.connect(dialog.queue_free)
		dialog.popup_centered()))

func _field(parent: Control, title: String, value: String, limit: int, changed: Callable) -> void:
	parent.add_child(UI.text(title,"MutedLabel"))
	var field := LineEdit.new()
	field.text = value
	field.max_length = limit
	parent.add_child(field)
	field.text_changed.connect(changed)

func _number(parent: Control, title: String, low: float, high: float, value: float, step := 1.0) -> SpinBox:
	parent.add_child(UI.text(title,"MutedLabel"))
	var field := SpinBox.new()
	field.min_value = low
	field.max_value = high
	field.step = step
	field.value = value
	parent.add_child(field)
	return field

func details(id: String, message: String = "") -> void:
	if not profile.data.get("blueprints",{}).has(id): library(); return
	active_id = id
	var bp: Dictionary = profile.data.blueprints[id]
	_screen("detail",_name(id),"%d pins · %s · Revision %d" % [bp.pins.size(),_dimensions(bp),int(bp.get("revision",1))])
	notice.text = message
	var visual := VBoxContainer.new()
	visual.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	area.add_child(visual)
	var view_model = Converter.new()
	var error: String = view_model.restore(id,bp,profile.data.blueprints)
	if error.is_empty():
		var preview := PackagePreview.new()
		preview.model = view_model
		preview.chip_style = kind == "IC"
		preview.interactive = false
		preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
		visual.add_child(preview)
	else:
		var image := TextureRect.new()
		image.texture = _chip_image(bp)
		image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		image.size_flags_vertical = Control.SIZE_EXPAND_FILL
		visual.add_child(image)
	var column := _scroll(area,330)
	if not str(bp.get("description","")).is_empty(): column.add_child(UI.text(str(bp.description)))
	var cost := Custom.price(id,profile.data.blueprints)
	column.add_child(UI.text("%d internal components · $%d each" % [bp.parts.size(),cost],"SubtitleLabel"))
	column.add_child(UI.text("Owned  %d" % int(profile.data.inventory.get(id,0))))
	if _creative(): column.add_child(UI.text("Available in Creative Mode without buying copies.","MutedLabel"))
	else:
		var quantity := _number(column,"Copies",1,100,1)
		var buy := UI.action("Buy · $%d" % cost,"",func():_buy(id,int(quantity.value)),true)
		column.add_child(buy)
		quantity.value_changed.connect(func(value):buy.text="Buy · $%d" % (cost*int(value)))
		buy.disabled = not pending.is_empty()
	if kind == "PCB" and (_creative() or int(profile.data.inventory.get(id,0)) > 0):
		column.add_child(UI.action("Open as standalone PCB","",func():
			close_station.call()
			game.electronics.prepare_standalone(id)))
	if kind == "PCB" and bp.has("pcb_design"):
		column.add_child(UI.action("Open copper routing","",func():
			close_station.call()
			game.electronics.open_pcb_routing(id)))
	var identity := str(game.characters.selected)
	var project_id := str(bp.get("source_circuit_id",""))
	var project: Dictionary = Projects.read_projects(identity).get(project_id,{})
	if bp.has("layout"):
		if project.is_empty():
			column.add_child(UI.text("The source circuit is embedded in this blueprint.","MutedLabel"))
		column.add_child(UI.action("Save embedded circuit as project","save",func():
			var board := Converter.embedded_source(bp,profile.data.blueprints)
			var saved := Projects.save_copy(identity,_name(id),board)
			notice.text = "Circuit saved to Circuit Maker." if saved == OK else "The embedded circuit could not be saved."))
	if error.is_empty():
		if not project.is_empty() and JSON.stringify(project.board,"",true,true).sha256_text()!=str(bp.get("source_revision","")):
			column.add_child(UI.action("Use latest saved source","refresh",func():
				_edit(id,false)
				if model.parent_revision==id:_select_source(project_id,project)))
		var linked_update := _linked_blueprint_update(bp)
		if not linked_update.is_empty():
			column.add_child(UI.action("Update linked components","refresh",func():
				model=view_model
				linked_update.parent_revision=id
				linked_update.revision=int(bp.get("revision",1))+1
				var revision_id := "ic:"+JSON.stringify(linked_update,"",true,true).sha256_text().left(24)
				pending_proposal={"id":revision_id,"blueprint":linked_update}
				upgrade_review()))
		column.add_child(UI.action("Inspect internal circuit","",func():_inspect(id,view_model)))
		column.add_child(UI.action("Edit blueprint","edit",_edit.bind(id,false)))
		column.add_child(UI.action("Duplicate as New Blueprint","plus",_edit.bind(id,true)))
	else: column.add_child(UI.text(error,"MutedLabel"))
	column.add_child(UI.action("Rename","edit",_rename.bind(id)))
	column.add_child(UI.action("Delete from library","trash",_archive.bind(id)))
	_nav(library)

func _linked_blueprint_update(blueprint: Dictionary) -> Dictionary:
	var library: Dictionary=profile.data.blueprints
	var revised := blueprint.duplicate(true)
	var changed := false
	for part in revised.parts+revised.get("layout",{}).get("parts",[]):
		var old := str(part.type)
		var latest := Upgrade.current(profile.data,old)
		if latest==old or not library.has(latest) or not library.has(old):continue
		if Upgrade.interface_signature(library[old])!=Upgrade.interface_signature(library[latest]):continue
		part.type=latest
		changed=true
	return revised if changed else {}

func _inspect(id: String, view_model: Converter) -> void:
	_screen("inspect","Internal circuit",_name(id))
	var view = _board_view(area,view_model.board,false)
	for index in view_model.connections.size():
		var connection: Dictionary = view_model.connections[index]
		view.markers[connection.hole] = ("X%d" if kind=="PCB" else "Pin %d") % (index+1)
	_nav(details.bind(id))

func _edit(id: String, copy: bool) -> void:
	model = Converter.new()
	var error: String = model.restore(id,profile.data.blueprints[id],profile.data.blueprints)
	if not error.is_empty(): notice.text=error; return
	model.draft.name = _name(id)
	if copy:
		model.parent_revision = ""
		model.draft.name = str(model.draft.name).left(32)+" copy"
	holes()
	footer.add_child(UI.action("Open source in Circuit Maker","",func():
		var board: Dictionary = model.board
		close_station.call()
		game.electronics.open("design")
		var adapter = game.electronics.workspace.get_meta("host_adapter")
		adapter.projects._load("",board)
		adapter.projects.mark_dirty()))

func _rename(id: String) -> void:
	var dialog := ConfirmationDialog.new()
	dialog.title = "Rename "+kind+" blueprint"
	add_child(dialog)
	var name_field := LineEdit.new()
	name_field.text = _name(id)
	name_field.max_length = 40
	name_field.custom_minimum_size.x = 340
	dialog.add_child(name_field)
	dialog.confirmed.connect(func():
		dialog.queue_free()
		var value := name_field.text.strip_edges()
		if not value.is_empty(): _metadata(id,{"name":value}))
	dialog.canceled.connect(dialog.queue_free)
	dialog.popup_centered()
	name_field.grab_focus()
	name_field.select_all()

func _archive(id: String) -> void:
	var dialog := ConfirmationDialog.new()
	dialog.title = "Delete blueprint from library?"
	dialog.dialog_text = "Existing copies and circuits retain their saved revision."
	dialog.ok_button_text = "Delete"
	add_child(dialog)
	dialog.confirmed.connect(func():dialog.queue_free();_metadata(id,{"archived":true}))
	dialog.canceled.connect(dialog.queue_free)
	dialog.popup_centered()

func _metadata(id: String, changes: Dictionary) -> void:
	if not pending.is_empty(): return
	var old: Dictionary = profile.data.duplicate(true)
	if not profile.data.has("ic_library"): profile.data.ic_library = {}
	var entry: Dictionary = profile.data.ic_library.get(id,{})
	entry.merge(changes,true)
	profile.data.ic_library[id] = entry
	if profile.authority_submit.is_valid(): pending = "metadata"
	if profile.save() != OK:
		profile.data = old
		pending = ""
		notice.text = "Could not save the blueprint library."
	elif pending.is_empty():
		if changes.get("archived",false): library("Blueprint removed from the library.")
		else: details(id,"Blueprint renamed.")

func _buy(id: String, count: int) -> void:
	if not pending.is_empty(): return
	if profile.authority_submit.is_valid(): pending = "buy"
	var message: String = profile.buy(id,count)
	if pending.is_empty(): details(id,message)
	else: notice.text = message

func _save() -> void:
	if not pending.is_empty(): return
	var result: Dictionary = model.prepare_blueprint(profile)
	if result.has("error"): notice.text = result.error; return
	var id: String = result.id
	if not model.parent_revision.is_empty():
		pending_proposal = {"id":id,"blueprint":result.definitions[id]}
		upgrade_review()
		return
	var previous: Dictionary = profile.data.duplicate(true)
	profile.data.blueprints = result.definitions
	active_id = id
	if profile.authority_submit.is_valid(): pending = "metadata"
	if profile.save() != OK:
		profile.data = previous
		pending = ""
		notice.text = "Could not save the "+kind+" blueprint."
	elif pending.is_empty(): details(id,"Blueprint saved.")

func upgrade_review(message: String = "") -> void:
	_screen("upgrade","Update custom "+kind,str(pending_proposal.blueprint.name))
	notice.text = message
	var column := _scroll(area)
	var reserves: Dictionary = game.electronics_trade.authority.local_craft_reservations().get("counts",{})
	var check := Upgrade.quote(profile.data,model.parent_revision,pending_proposal.id,pending_proposal.blueprint,reserves,_creative())
	var back: Callable = _pcb_review if kind == "PCB" else designer
	if not check.error.is_empty(): notice.text = check.error; _nav(back); return
	column.add_child(UI.text("%d owned copies" % check.count,"SubtitleLabel"))
	if check.replacements.size()>1:
		column.add_child(UI.text("%d dependent designs and their owned copies will also update." % (check.replacements.size()-1)))
	var old: Dictionary = profile.data.blueprints[model.parent_revision]
	for index in mini(old.pins.size(),model.pins.size()):
		if old.pins[index].name != model.pins[index].name or old.pins[index].node != model.pins[index].node:
			column.add_child(UI.text("Pin %d changes from %s (%s) to %s (%s)." % [index+1,old.pins[index].name,old.pins[index].node,model.pins[index].name,model.pins[index].node]))
	var catalog: Dictionary = profile.catalog()
	for type in check.needed:
		column.add_child(UI.text("%s    Needed %d · Available %d · Missing %d" % [catalog.get(type,{}).get("name",type),check.needed[type],check.available[type],check.missing.get(type,0)]))
	for type in check.returned:
		column.add_child(UI.text("Returns %d × %s" % [check.returned[type],catalog.get(type,{}).get("name",type)]))
	if check.needed.is_empty() and check.returned.is_empty(): column.add_child(UI.text("No additional components required."))
	main_action = _nav(back,"Apply Update",_submit_upgrade.bind("apply"))
	footer.get_child(0).text = "Cancel"
	main_action.disabled = not check.missing.is_empty() or not pending.is_empty()
	if not check.missing.is_empty():
		var buy := UI.action("Buy Missing Components · $%d" % check.cost,"",_submit_upgrade.bind("purchase"))
		buy.disabled = not pending.is_empty()
		footer.add_child(buy)

func _submit_upgrade(action: String) -> void:
	if not pending.is_empty(): return
	var authority = game.electronics_trade.authority
	var reservations: Dictionary = authority.local_craft_reservations().get("counts",{})
	var deployment := {"counts":reservations.duplicate(),"instance_ids":authority.local_craft_reservations().get("instance_ids",[]),"boards":{}}
	if not game.session.online:
		for index in game.dc_lab.benches.size():
			var station = game.dc_lab.benches[index]
			if station.board_owner == 1 and not station.board.is_empty():
				deployment.boards[index]=station.board
	for type in profile.data.get("dorm",{}).get("storage",{}):
		deployment.counts[type] = maxi(0,int(deployment.counts.get(type,0))-int(profile.data.dorm.storage[type]))
	if profile.authority_submit.is_valid(): pending = action
	var message: String = profile.upgrade_ic(model.parent_revision,pending_proposal.id,pending_proposal.blueprint,action,_creative(),deployment)
	if pending.is_empty():
		if profile.operation_succeeded and action == "apply":
			for slot in profile.upgraded_boards:
				game.dc_lab.upgrade_deployed_circuit(slot,profile.upgraded_boards[slot])
			details(pending_proposal.id,message)
		else: upgrade_review(message)
	else: notice.text = message

func _result(operation: String, result: Dictionary) -> void:
	if pending.is_empty(): return
	if operation != pending and not (operation == "ic_upgrade" and pending in ["apply","purchase"]): return
	var action := pending
	pending = ""
	var message := str(result.get("message",result.get("error","Saved.")))
	if operation == "ic_upgrade":
		if result.get("ok",false) and action == "apply": details(pending_proposal.id,message)
		else: upgrade_review(message)
	elif result.get("ok",false) and profile.data.get("ic_library",{}).get(active_id,{}).get("archived",false): library(message)
	elif result.get("ok",false): details(active_id,message)
	else: notice.text = message

func _chip_image(bp: Dictionary) -> Texture2D:
	if kind == "PCB":
		var key := hash(bp)
		if not previews.has(key):
			previews[key] = PackagePreview.board_image(bp,profile.data.blueprints)
		return previews[key]
	var image := Image.create_empty(120,74,false,Image.FORMAT_RGBA8)
	image.fill(Color("152c3b"))
	var body := Color.from_string(str(bp.get("footprint",{}).get("color","364759")),Color("364759"))
	image.fill_rect(Rect2i(29,13,62,48),body.darkened(.35))
	image.fill_rect(Rect2i(32,15,56,43),body.lightened(.15))
	image.fill_rect(Rect2i(38,21,5,5),Color("d9e1dc"))
	var left := ceili(bp.pins.size()*.5)
	for index in bp.pins.size():
		var x := 19 if index < left else 87
		var y := 18+roundi(37.0*(index % left)/maxi(1,left-1))
		image.fill_rect(Rect2i(x,y,14,3),Color("b9c8d5"))
	return ImageTexture.create_from_image(image)

