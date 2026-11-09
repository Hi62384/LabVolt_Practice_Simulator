extends Node

const Board = preload("res://scripts/breadboard_model.gd")
const Widgets = preload("res://scripts/ui/design_system/widgets.gd")
const Tokens = preload("res://scripts/ui/design_system/tokens.gd")

var workspace: Control
var screen: Control
var confirmation: ColorRect
var previous_focus: Control
var install: Callable
var path: String
var entries: Dictionary
var current_id := ""
var dirty := false
var browser: VBoxContainer
var editor_opened := false
var browser_status: Label

func setup(owner: Control, screen_root: Control, identity: String, load_board: Callable) -> void:
	workspace = owner
	screen = screen_root
	install = load_board
	path = project_path(identity)
	entries = read_projects(identity)
	_update_title()

static func project_path(identity: String) -> String:
	return "user://circuit_projects_" + identity.sha256_text().left(24) + ".cfg"

static func read_projects(identity: String) -> Dictionary:
	var path := project_path(identity)
	var file := ConfigFile.new()
	for candidate in [path,path+".bak"]:
		if file.load(candidate) != OK: continue
		var saved: Variant = file.get_value("projects","items",{})
		if saved is Dictionary: return saved
	return {}

func mark_dirty() -> void:
	dirty = true
	_update_title()

func new_project() -> void:
	_guard(func():_load("",Board.empty()))

func save_project(after := Callable()) -> void:
	if current_id.is_empty():
		_name_dialog("Save project","",func(name: String):_save_named(name,after))
	else:
		_save_named(str(entries[current_id].name),after)

func open_projects() -> void:
	_close_browser()
	workspace.canvas.release_io_capture()
	workspace.hide()
	browser=VBoxContainer.new()
	browser.size_flags_vertical=Control.SIZE_EXPAND_FILL
	browser.add_theme_constant_override("separation",16)
	workspace.get_parent().add_child(browser)
	var heading := HBoxContainer.new()
	browser.add_child(heading)
	var intro := VBoxContainer.new()
	intro.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	heading.add_child(intro)
	intro.add_child(Widgets.text("Circuit Projects","TitleLabel"))
	intro.add_child(Widgets.text("Open a saved design or start with a blank board.","MutedLabel"))
	var create := Widgets.action("New circuit","plus",new_project,true)
	create.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	heading.add_child(create)
	var leave := Widgets.action("Back to editor" if editor_opened else "Close","back",leave_browser)
	leave.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	heading.add_child(leave)
	browser_status=Widgets.text("","MutedLabel")
	browser_status.hide()
	browser.add_child(browser_status)
	if entries.is_empty():
		var empty := CenterContainer.new()
		empty.size_flags_vertical=Control.SIZE_EXPAND_FILL
		browser.add_child(empty)
		var panel := PanelContainer.new()
		panel.add_theme_stylebox_override("panel", Tokens.surface(Tokens.SURFACE, Tokens.BORDER, 24))
		empty.add_child(panel)
		var copy := VBoxContainer.new()
		copy.add_theme_constant_override("separation",8)
		panel.add_child(copy)
		var title := Widgets.text("No saved circuits yet", "SubtitleLabel")
		title.autowrap_mode = TextServer.AUTOWRAP_OFF
		title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		copy.add_child(title)
		var detail := Widgets.text("Save a circuit to find it here.", "MutedLabel")
		detail.autowrap_mode = TextServer.AUTOWRAP_OFF
		detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		copy.add_child(detail)
		create.grab_focus()
		return
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL
	browser.add_child(scroll)
	var list := preload("res://scripts/ui/design_system/responsive_grid.gd").new()
	list.maximum_columns=3
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	var ids := entries.keys()
	ids.sort_custom(func(a,b):return int(entries[a].modified)>int(entries[b].modified))
	for id in ids:
		var entry: Dictionary = entries[id]
		var modified := Time.get_date_string_from_unix_time(int(entry.modified))
		var card := PanelContainer.new()
		card.theme_type_variation="CardPanel"
		card.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		list.add_child(card)
		var details := VBoxContainer.new()
		card.add_child(details)
		var thumb := TextureRect.new()
		thumb.custom_minimum_size.y=92
		thumb.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
		thumb.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		thumb.texture = thumbnail(entry.board)
		details.add_child(thumb)
		details.add_child(Widgets.text(str(entry.name),"SubtitleLabel"))
		details.add_child(Widgets.text("Edited "+modified,"MutedLabel"))
		var tools := HFlowContainer.new()
		details.add_child(tools)
		tools.add_child(Widgets.action("Edit circuit","folder",func():_guard(func():_load(id,entry.board)),true))
		tools.add_child(Widgets.action("Rename","edit",func():
			_name_dialog("Rename project",str(entry.name),func(name: String):_change(id,name,false))))
		tools.add_child(Widgets.action("Duplicate","plus",func():
			_change(id,str(entry.name).left(32)+" copy",true)))
		tools.add_child(Widgets.action("Delete","trash",func():_delete_dialog(id)))
	create.grab_focus()

func _close_browser() -> void:
	if is_instance_valid(browser):
		browser.hide()
		browser.queue_free()
	browser=null
	browser_status=null

func leave_browser() -> void:
	_close_browser()
	if editor_opened:workspace.show()
	else:workspace.invoke("close")

func _guard(next: Callable) -> void:
	if not dirty:
		next.call()
		return
	if is_instance_valid(confirmation):
		return
	var copy := _open_prompt()
	copy.add_child(Widgets.text("Save this circuit?", "SubtitleLabel"))
	copy.add_child(Widgets.text("Save your changes before leaving this circuit.", "MutedLabel"))
	var actions := HFlowContainer.new()
	copy.add_child(actions)
	var keep := Widgets.action("Keep editing", "back", close_confirmation)
	var discard := Widgets.action("Discard changes", "trash", func():
		close_confirmation()
		next.call())
	discard.theme_type_variation = "DangerButton"
	var save := Widgets.action("Save changes", "save", func():
		close_confirmation()
		save_project(next), true)
	var buttons: Array[Button] = [keep, discard, save]
	for button in buttons:
		actions.add_child(button)
	for index in buttons.size():
		var button := buttons[index]
		button.focus_next = button.get_path_to(buttons[(index + 1) % buttons.size()])
		button.focus_previous = button.get_path_to(buttons[posmod(index - 1, buttons.size())])
	keep.grab_focus()

func _open_prompt() -> VBoxContainer:
	previous_focus = get_viewport().gui_get_focus_owner()
	workspace.canvas.release_io_capture()
	workspace.set_meta("project_prompt_open", true)
	confirmation = ColorRect.new()
	confirmation.color = Color(0, 0, 0, .58)
	confirmation.mouse_filter = Control.MOUSE_FILTER_STOP
	screen.add_child(confirmation)
	var center := CenterContainer.new()
	confirmation.add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var panel := PanelContainer.new()
	panel.custom_minimum_size.x = clampf(screen.size.x - 56.0, 0.0, 500.0)
	panel.add_theme_stylebox_override("panel", Tokens.surface(Tokens.SURFACE))
	center.add_child(panel)
	var copy := VBoxContainer.new()
	copy.add_theme_constant_override("separation", 12)
	panel.add_child(copy)
	return copy

func close_confirmation() -> void:
	if not is_instance_valid(confirmation):
		return
	confirmation.hide()
	confirmation.queue_free()
	confirmation = null
	workspace.set_meta("project_prompt_open", false)
	if is_instance_valid(previous_focus) and previous_focus.is_visible_in_tree():
		previous_focus.grab_focus()
	previous_focus = null

func _name_dialog(title: String, initial: String, action: Callable) -> void:
	if is_instance_valid(confirmation):return
	var copy := _open_prompt()
	copy.add_child(Widgets.text(title,"SubtitleLabel"))
	var name_field := LineEdit.new()
	name_field.placeholder_text = "Project name"
	name_field.text = initial
	name_field.max_length = 40
	copy.add_child(name_field)
	var accept := func():
		var project_title := name_field.text.strip_edges()
		if project_title.is_empty():return
		close_confirmation()
		action.call(project_title)
	var actions := HBoxContainer.new()
	actions.alignment=BoxContainer.ALIGNMENT_END
	copy.add_child(actions)
	var cancel := Widgets.action("Cancel","close",close_confirmation)
	var save := Widgets.action("Save","save",accept,true)
	actions.add_child(cancel)
	actions.add_child(save)
	save.disabled = initial.strip_edges().is_empty()
	name_field.text_changed.connect(func(value):save.disabled=value.strip_edges().is_empty())
	name_field.text_submitted.connect(func(_value):accept.call())
	name_field.focus_next=name_field.get_path_to(cancel)
	name_field.focus_previous=name_field.get_path_to(save)
	cancel.focus_next=cancel.get_path_to(save)
	cancel.focus_previous=cancel.get_path_to(name_field)
	save.focus_next=save.get_path_to(name_field)
	save.focus_previous=save.get_path_to(cancel)
	name_field.grab_focus()

func _save_named(name: String, after: Callable) -> void:
	var next := entries.duplicate(true)
	var id := current_id if not current_id.is_empty() else Crypto.new().generate_random_bytes(12).hex_encode()
	next[id] = {"name":name,"modified":int(Time.get_unix_time_from_system()),"board":workspace.canvas.board.duplicate(true)}
	if not _write(next): return
	current_id = id
	dirty = false
	_update_title()
	workspace.notify("Project saved.")
	if after.is_valid(): after.call()

func _load(id: String, board: Dictionary) -> void:
	var error: String = install.call(board.duplicate(true))
	if not error.is_empty():
		if is_instance_valid(browser_status):
			browser_status.text=error
			browser_status.show()
		workspace.notify(error)
		return
	_close_browser()
	editor_opened=true
	workspace.show()
	workspace.canvas.fit_board()
	current_id = id
	dirty = false
	_update_title()
	workspace.notify("New circuit." if id.is_empty() else "Project opened.")

func _change(id: String, name: String, duplicate: bool) -> void:
	var next := entries.duplicate(true)
	var destination := Crypto.new().generate_random_bytes(12).hex_encode() if duplicate else id
	next[destination] = entries[id].duplicate(true)
	next[destination].name = name
	next[destination].modified = int(Time.get_unix_time_from_system())
	if _write(next): _update_title()
	open_projects()

func _delete_dialog(id: String) -> void:
	if is_instance_valid(confirmation):return
	var copy := _open_prompt()
	copy.add_child(Widgets.text("Delete project?","SubtitleLabel"))
	copy.add_child(Widgets.text("“%s” will be removed from your saved circuits." % entries[id].name,"MutedLabel"))
	copy.add_child(Widgets.text("IC and PCB blueprints keep their embedded circuit. You can save a new project from their details.","MutedLabel"))
	var actions := HBoxContainer.new()
	actions.alignment=BoxContainer.ALIGNMENT_END
	copy.add_child(actions)
	var keep := Widgets.action("Keep project","back",close_confirmation)
	var remove := Widgets.action("Delete project","trash",func():
		close_confirmation()
		var next := entries.duplicate(true)
		next.erase(id)
		if _write(next) and current_id == id:
			current_id = ""
			dirty = true
			_update_title()
		open_projects())
	remove.theme_type_variation="DangerButton"
	actions.add_child(keep)
	actions.add_child(remove)
	keep.focus_next=keep.get_path_to(remove)
	keep.focus_previous=keep.focus_next
	remove.focus_next=remove.get_path_to(keep)
	remove.focus_previous=remove.focus_next
	keep.grab_focus()

static func save_copy(identity: String, title: String, board: Dictionary) -> Error:
	var projects := read_projects(identity)
	var id := Crypto.new().generate_random_bytes(12).hex_encode()
	projects[id] = {"name":title.left(40),"modified":int(Time.get_unix_time_from_system()),"board":board.duplicate(true)}
	return _write_projects(project_path(identity),projects)

static func _write_projects(path: String, next: Dictionary) -> Error:
	var file := ConfigFile.new()
	file.set_value("projects","items",next)
	var error := file.save(path+".tmp")
	if error == OK and FileAccess.file_exists(path):
		error = DirAccess.copy_absolute(path,path+".bak")
	if error == OK: error = DirAccess.rename_absolute(path+".tmp",path)
	return error

func _write(next: Dictionary) -> bool:
	if _write_projects(path,next) != OK:
		workspace.notify("Project could not be saved.")
		return false
	entries = next
	return true

func _update_title() -> void:
	var name := str(entries[current_id].name) if not current_id.is_empty() else "Untitled circuit"
	workspace.project_name.text = name + ("  •" if dirty else "")

static func thumbnail(board: Dictionary) -> Texture2D:
	var image := Image.create_empty(112,64,false,Image.FORMAT_RGBA8)
	image.fill(Color("d8e2d9"))
	var rows := int(board.rows)
	var lanes := Board.hole_letters(board).length()
	for row in rows:
		for letter in lanes: image.set_pixelv(_pixel(Vector2i(row,letter),rows,lanes),Color("8a9a97"))
	for wire in board.wires:
		_line(image,_pixel(Board.grid(wire[0]),rows,lanes),_pixel(Board.grid(wire[1]),rows,lanes),Color("d49c59"))
	for part in board.parts:
		var a := _pixel(Board.grid(part.a),rows,lanes)
		var b := _pixel(Board.grid(part.b),rows,lanes)
		_line(image,a,b,Color("647879"))
		var middle := Vector2i((Vector2(a)+Vector2(b))*.5)
		image.fill_rect(Rect2i(middle-Vector2i(2,2),Vector2i(5,5)),Color("327666"))
	return ImageTexture.create_from_image(image)

static func _pixel(point: Vector2i, rows: int, lanes: int) -> Vector2i:
	var lane := clampi(point.y,0,lanes-1)
	var y := 6+roundi(lane*51.0/(lanes-1))
	return Vector2i(6+roundi(clampi(point.x,0,rows-1)*99.0/maxi(1,rows-1)),y)

static func _line(image: Image, a: Vector2i, b: Vector2i, tint: Color) -> void:
	var steps := maxi(1,ceili(Vector2(a).distance_to(Vector2(b))))
	for index in range(steps+1): image.set_pixelv(Vector2i(Vector2(a).lerp(Vector2(b),float(index)/steps).round()),tint)

