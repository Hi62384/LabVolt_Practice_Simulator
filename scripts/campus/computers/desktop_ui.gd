extends Control
## One local player's virtual computer. All persistent operations go through ComputerSessions.
signal closed

var session: Node
var game: Node
var snapshot: Dictionary = {}
var current_path := ""
var drafts: Dictionary = {}
var pending_new := false
var pending_rename := ""
var pending_folder_source := ""
var pending_folder_target := ""
var pending_paper_id := 0
var active_app := "Files"
var file_list: ItemList
var editor: TextEdit
var path_field: LineEdit
var status_label: Label
var title_label: Label
var content: VBoxContainer
var discard_dialog: ConfirmationDialog
var power_button: Button
var retry_documents_button: Button
var last_activity_signal := 0
var folder_button: Button
var delete_button: Button
var _rendering := false
var _portable_pending := false
var laptop_display_filter: ColorRect
var browser_surface: VBoxContainer
var app_window_title: Label
var start_panel: PanelContainer
var start_button: Button
var app_window: PanelContainer
var workspace: Control
var windows := {}
var clock_label: Label
var desktop_status: Label
var app_names := ["Files", "Text editor", "Code editor", "Course work", "Calculator", "Browser", "Run code"]
var app_icons := {"Files":"▤", "Text editor":"✎", "Code editor":"‹›", "Course work":"▣", "Calculator":"＋", "Browser":"◎", "Run code":"▶"}

func build(source: Node, owner_game: Node = null) -> void:
	session = source
	game = owner_game
	theme = preload("res://scripts/ui/design_system/theme.gd").create()
	for type in ["Button","OptionButton","LineEdit","TextEdit","Label","PopupMenu","ItemList"]:
		theme.set_font_size("font_size",type,14)
		for state in theme.get_stylebox_list(type):
			var style := theme.get_stylebox(state,type)
			style.content_margin_top=4.0
			style.content_margin_bottom=4.0
			style.content_margin_left=8.0
			style.content_margin_right=8.0
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	if not session.desktop_changed.is_connected(_on_desktop_changed):
		session.desktop_changed.connect(_on_desktop_changed)
	if not session.operation_failed.is_connected(_on_operation_failed):
		session.operation_failed.connect(_on_operation_failed)
	_build_shell()

func _build_shell() -> void:
	var backdrop := TextureRect.new()
	var wallpaper := GradientTexture2D.new()
	var gradient := Gradient.new()
	gradient.colors=PackedColorArray([Color("0e2334"),Color("225869"),Color("385680")])
	gradient.offsets=PackedFloat32Array([0,.62,1])
	wallpaper.gradient=gradient
	wallpaper.fill_from=Vector2(0,1)
	wallpaper.fill_to=Vector2(1,0)
	backdrop.texture=wallpaper
	backdrop.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
	backdrop.mouse_filter=Control.MOUSE_FILTER_IGNORE
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(backdrop)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 22)
	add_child(margin)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 12)
	margin.add_child(root)
	var header := HBoxContainer.new()
	root.add_child(header)
	title_label = Label.new()
	title_label.text = "CAMPUS COMPUTER  ·  DESKTOP"
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_label.add_theme_font_size_override("font_size", 21)
	title_label.add_theme_color_override("font_color",Color("b0eadc"))
	header.add_child(title_label)
	desktop_status=Label.new()
	header.add_child(desktop_status)
	retry_documents_button = _button("Retry documents", func():session.retry_local_documents())
	retry_documents_button.visible = false
	header.add_child(retry_documents_button)
	power_button = _button("Power off", _power_off)
	power_button.visible = false
	header.add_child(power_button)
	header.add_child(_button("Leave computer  Esc", _request_exit))
	workspace=Control.new()
	workspace.clip_contents=true
	workspace.size_flags_vertical=Control.SIZE_EXPAND_FILL
	root.add_child(workspace)
	workspace.resized.connect(_fit_windows)
	var shortcuts := VBoxContainer.new()
	shortcuts.position=Vector2(4,8)
	workspace.add_child(shortcuts)
	for name in ["Files","Text editor","Course work","Calculator","Browser"]:
		var shortcut := _button(str(app_icons[name])+"  "+name,func():_switch_app(name))
		shortcut.alignment=HORIZONTAL_ALIGNMENT_LEFT
		shortcuts.add_child(shortcut)
	var taskbar := HBoxContainer.new()
	taskbar.add_theme_constant_override("separation", 8)
	taskbar.add_theme_stylebox_override("panel", preload("res://scripts/ui/design_system/tokens.gd").surface(Color("102936"), Color("385a68"), 10))
	root.add_child(taskbar)
	start_button = _button("⊞  Start", _toggle_start)
	taskbar.add_child(start_button)
	for name in app_names:
		var app_name: String = str(name)
		var app_button := _button(str(app_icons.get(name, "•")) + "  " + name, func(): _switch_app(app_name))
		app_button.custom_minimum_size.x = 54
		taskbar.add_child(app_button)
	clock_label = Label.new()
	clock_label.horizontal_alignment=HORIZONTAL_ALIGNMENT_RIGHT
	clock_label.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	taskbar.add_child(clock_label)
	var clock_tick := Timer.new()
	clock_tick.wait_time=1.0
	clock_tick.autostart=true
	clock_tick.timeout.connect(_update_clock)
	add_child(clock_tick)
	_update_clock()
	start_panel = PanelContainer.new()
	start_panel.hide()
	start_panel.position = Vector2(22, maxf(80, get_viewport_rect().size.y - 430))
	start_panel.custom_minimum_size = Vector2(320, 390)
	start_panel.add_theme_stylebox_override("panel", preload("res://scripts/ui/design_system/tokens.gd").surface(Color("142d3b"), Color("62a697"), 14))
	add_child(start_panel)
	var start_list := VBoxContainer.new()
	start_panel.add_child(start_list)
	var start_heading := Label.new()
	start_heading.text = "CAMPUS PROGRAMS"
	start_heading.add_theme_font_size_override("font_size", 18)
	start_list.add_child(start_heading)
	for name in app_names:
		var app_name: String = str(name)
		var launch := _button(str(app_icons.get(name, "•")) + "     " + name, func(): _switch_app(app_name); start_panel.hide())
		launch.custom_minimum_size.y = 42
		start_list.add_child(launch)
	discard_dialog = ConfirmationDialog.new()
	discard_dialog.title = "Leave computer?"
	discard_dialog.dialog_text = "Unsaved editor changes will be lost. Save the files you want to keep before leaving."
	discard_dialog.ok_button_text = "Discard and leave"
	discard_dialog.confirmed.connect(_exit_now)
	add_child(discard_dialog)
	# The filter is confined to this desktop canvas and never changes the
	# player's global rendering settings. It does not intercept UI input.
	laptop_display_filter = ColorRect.new()
	laptop_display_filter.mouse_filter = Control.MOUSE_FILTER_IGNORE
	laptop_display_filter.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var shader := Shader.new()
	shader.code = "shader_type canvas_item;\nuniform sampler2D screen_texture : hint_screen_texture, filter_nearest;\nuniform float display_scale = 1.0;\nvoid fragment() { vec2 pixels = max(vec2(1.0), 1.0 / SCREEN_PIXEL_SIZE * display_scale); vec2 uv = (floor(SCREEN_UV * pixels) + vec2(0.5)) / pixels; COLOR = texture(screen_texture, uv); }"
	var filter_material := ShaderMaterial.new()
	filter_material.shader = shader
	laptop_display_filter.material = filter_material
	laptop_display_filter.visible = false
	add_child(laptop_display_filter)
	_switch_app("Files")

func _button(label: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = label
	button.custom_minimum_size = Vector2(54, 28)
	button.pressed.connect(action)
	return button

func _update_clock() -> void:
	if is_instance_valid(clock_label):clock_label.text=Time.get_time_string_from_system().left(5)

func _window_key(name: String) -> String:
	return "Editor" if name in ["Files","Text editor","Code editor"] else name

func _create_window(key: String,name: String) -> Dictionary:
	var window := PanelContainer.new()
	window.set_meta("desktop_app",key)
	window.clip_contents=true
	window.add_theme_stylebox_override("panel",preload("res://scripts/ui/design_system/tokens.gd").surface(Color("132735"),Color("4b7180"),8))
	workspace.add_child(window)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation",4)
	window.add_child(column)
	var bar := HBoxContainer.new()
	column.add_child(bar)
	var title := Label.new()
	title.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	title.mouse_filter=Control.MOUSE_FILTER_STOP
	title.mouse_default_cursor_shape=Control.CURSOR_MOVE
	title.gui_input.connect(func(event: InputEvent):_window_drag(key,event))
	bar.add_child(title)
	for spec in [["—","Minimize",func():_minimize_window(key)],["□","Maximize or restore",func():_toggle_maximize(key)],["×","Close",func():_close_window(key)]]:
		var control := Button.new()
		control.text=spec[0]
		control.tooltip_text=spec[1]
		control.accessibility_name=spec[1]
		control.custom_minimum_size=Vector2(34,26)
		control.pressed.connect(spec[2])
		bar.add_child(control)
	var area := VBoxContainer.new()
	area.size_flags_vertical=Control.SIZE_EXPAND_FILL
	column.add_child(area)
	var message := Label.new()
	message.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	message.add_theme_font_size_override("font_size",12)
	column.add_child(message)
	var base := Vector2(830,575) if name in ["Files","Text editor","Code editor","Browser","Course work"] else Vector2(455,460)
	var offset := float(windows.size()%5)*24.0
	window.position=Vector2(maxf(155.0,workspace.size.x-base.x-12) if name=="Calculator" else 150+offset,12+offset)
	var state := {"shell":window,"title":title,"content":area,"status":message,"app":name,"built":false,"maximized":false,"base_size":base,"restore":Rect2(window.position,base)}
	windows[key]=state
	_fit_windows()
	return state

func _fit_windows() -> void:
	if workspace.size.x<32 or workspace.size.y<32:return
	for state in windows.values():
		var window: PanelContainer=state.shell
		if state.maximized:
			window.position=Vector2.ZERO
			window.size=workspace.size
		else:
			var preferred: Vector2=state.base_size
			window.size=preferred.min(workspace.size)
			window.position=window.position.clamp(Vector2.ZERO,(workspace.size-window.size).max(Vector2.ZERO))

func _window_drag(key: String,event: InputEvent) -> void:
	var state: Dictionary=windows.get(key,{})
	if state.is_empty():return
	if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT and event.pressed:
		_focus_window(key)
		if event.double_click:_toggle_maximize(key)
	elif event is InputEventMouseMotion and event.button_mask & MOUSE_BUTTON_MASK_LEFT and not state.maximized:
		var window: PanelContainer=state.shell
		window.position=(window.position+event.relative).clamp(Vector2.ZERO,(workspace.size-window.size).max(Vector2.ZERO))

func _toggle_maximize(key: String) -> void:
	var state: Dictionary=windows[key]
	var window: PanelContainer=state.shell
	if state.maximized:
		window.position=state.restore.position
	else:
		state.restore=Rect2(window.position,window.size)
	state.maximized=not state.maximized
	_fit_windows()

func _minimize_window(key: String) -> void:
	windows[key].shell.hide()
	if app_window==windows[key].shell:_focus_last_window()

func _close_window(key: String) -> void:
	if not windows.has(key):return
	var state: Dictionary=windows[key]
	if key=="Editor":_capture_draft()
	if key=="Browser" and is_instance_valid(browser_surface):
		browser_surface.close_session()
		browser_surface=null
	var focused: bool=app_window==state.shell
	state.shell.hide()
	state.shell.queue_free()
	windows.erase(key)
	if focused:_focus_last_window()

func _focus_last_window() -> void:
	for i in range(workspace.get_child_count()-1,-1,-1):
		var candidate: Control=workspace.get_child(i)
		if candidate.has_meta("desktop_app") and candidate.visible:
			_focus_window(candidate.get_meta("desktop_app"))
			return
	app_window=null
	status_label=desktop_status
	_bind_editor({})

func _bind_editor(state: Dictionary) -> void:
	file_list=state.get("file_list")
	editor=state.get("editor")
	path_field=state.get("path_field")
	folder_button=state.get("folder_button")
	delete_button=state.get("delete_button")

func _focus_window(key: String) -> void:
	if not windows.has(key):return
	var state: Dictionary=windows[key]
	app_window=state.shell
	app_window.show()
	app_window.move_to_front()
	active_app=state.app
	app_window_title=state.title
	content=state.content
	status_label=state.status
	_bind_editor(state)

func _clear_content() -> void:
	for child in content.get_children():
		content.remove_child(child)
		child.queue_free()
	_bind_editor({})

func _switch_app(name: String) -> void:
	_capture_draft()
	var key := _window_key(name)
	var state: Dictionary=windows[key] if windows.has(key) else _create_window(key,name)
	var rebuild: bool=not state.built or state.app!=name or name=="Course work"
	state.app=name
	_focus_window(key)
	app_window_title.text=str(app_icons.get(name,"•"))+"  "+name
	if is_instance_valid(start_panel):start_panel.hide()
	if not rebuild:
		if key=="Editor":
			_refresh_file_list()
			_load_editor()
		return
	_clear_content()
	state.built=true
	if name == "Files" or name == "Text editor" or name == "Code editor":
		_build_files(name)
		state.merge({"file_list":file_list,"editor":editor,"path_field":path_field,"folder_button":folder_button,"delete_button":delete_button},true)
	elif name == "Course work":
		_build_course_work()
	elif name == "Calculator":
		var calculator := preload("res://scripts/scientific_calculator.gd").new()
		calculator.size_flags_horizontal=Control.SIZE_SHRINK_CENTER
		content.add_child(calculator)
		status_label.text="Calculator · expressions stay on this computer."
	elif name == "Browser":
		browser_surface=preload("res://scripts/campus/computers/browser_surface.gd").new()
		browser_surface.game=game
		browser_surface.size_flags_vertical=Control.SIZE_EXPAND_FILL;content.add_child(browser_surface)
		var files: Array=[]
		for row in _file_rows():
			if row is Dictionary:
				var text_value:=str(row.get("text",""))
				files.append({"kind":"virtual_file","name":str(row.get("path","")),"bytes":text_value.to_utf8_buffer().size()})
		browser_surface.configure("computer",str(snapshot.get("station","")),str(snapshot.get("lease","")),files)
		browser_surface.attachment_loader=_browser_attachment
		browser_surface.assistant_virtual_save=_browser_save_answer
		status_label.text="Campus browser · embedded Chromium." if browser_surface.call("renderer_available") else "Embedded browser unavailable on this device."
	else:
		var message := Label.new()
		message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		message.text = "Code execution is not available yet. You can edit and save source files."
		content.add_child(message)
		status_label.text = message.text

func _toggle_start() -> void:
	if is_instance_valid(start_panel): start_panel.visible = not start_panel.visible

func _build_files(name: String) -> void:
	var toolbar := HFlowContainer.new()
	content.add_child(toolbar)
	toolbar.add_child(_button("New", _new_file))
	folder_button=_button("New folder", _new_folder)
	folder_button.visible=bool(snapshot.get("public_device",false));toolbar.add_child(folder_button)
	toolbar.add_child(_button("Open", _open_selected))
	toolbar.add_child(_button("Save  Ctrl+S", _save_file))
	var rename := _button("Rename", _rename_file)
	rename.disabled = not _supports_rename()
	rename.tooltip_text = "Rename is unavailable in this computer session." if rename.disabled else "Rename the selected virtual file."
	toolbar.add_child(rename)
	delete_button=_button("Delete", _delete_selected)
	delete_button.visible=bool(snapshot.get("public_device",false));toolbar.add_child(delete_button)
	var path_row := HBoxContainer.new()
	content.add_child(path_row)
	var path_label := Label.new()
	path_label.text = "Virtual file:"
	path_row.add_child(path_label)
	path_field = LineEdit.new()
	path_field.placeholder_text = "notes.txt or program.py"
	path_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	path_field.text = current_path
	path_row.add_child(path_field)
	var split := HSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(split)
	file_list = ItemList.new()
	file_list.custom_minimum_size.x = 210
	file_list.item_activated.connect(func(_index: int): _open_selected())
	split.add_child(file_list)
	editor = TextEdit.new()
	editor.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	editor.wrap_mode = TextEdit.LINE_WRAPPING_NONE if name == "Code editor" else TextEdit.LINE_WRAPPING_BOUNDARY
	editor.text_changed.connect(_on_text_changed)
	split.add_child(editor)
	_refresh_file_list()
	_load_editor()
	if name == "Code editor":
		status_label.text = "Code editor · saved files only; execution is unavailable."

func _file_rows() -> Array:
	var files: Variant = snapshot.get("files", [])
	if files is Array:
		return files
	if files is Dictionary:
		var rows: Array = []
		for key in files.keys():
			var row: Variant = files[key]
			if row is Dictionary:
				var copy: Dictionary = row.duplicate()
				copy["path"] = str(key)
				rows.append(copy)
		return rows
	return []

func _file(path: String) -> Dictionary:
	for value in _file_rows():
		if value is Dictionary and str(value.get("path", "")) == path:
			return value
	return {}

func _refresh_file_list() -> void:
	if file_list == null:
		return
	file_list.clear()
	for folder in snapshot.get("folders",[]):
		file_list.add_item("[Folder] " + str(folder))
		file_list.set_item_metadata(file_list.item_count-1,{"path":str(folder),"folder":true})
	for value in _file_rows():
		if value is Dictionary:
			file_list.add_item(str(value.get("path", "")))
			file_list.set_item_metadata(file_list.item_count-1,{"path":str(value.get("path","")),"folder":false})

func _selected_entry() -> Dictionary:
	if file_list==null or file_list.get_selected_items().is_empty():return {}
	var metadata: Variant=file_list.get_item_metadata(file_list.get_selected_items()[0])
	return metadata if metadata is Dictionary else {}

func _new_folder() -> void:
	if path_field==null:return
	var path:=path_field.text.strip_edges()
	if not _valid_path(path):status_label.text="Enter a valid folder path.";return
	_send({"op":"mkdir","path":path})

func _delete_selected() -> void:
	var selected:=_selected_entry()
	if selected.is_empty():status_label.text="Select a file or folder to delete.";return
	var path:=str(selected.path)
	_capture_draft()
	for draft in drafts:
		if str(draft)==path or str(draft).begins_with(path+"/"):
			status_label.text="Save or discard changes before deleting.";return
	_send({"op":"delete","path":path})
	if current_path==path or current_path.begins_with(path+"/"):
		current_path="";_load_editor()

func _load_editor() -> void:
	if editor == null:
		return
	_rendering = true
	var file := _file(current_path)
	editor.text = str(drafts.get(current_path, file.get("text", "")))
	_rendering = false
	if path_field != null:
		path_field.text = current_path
	if visible:
		editor.grab_focus()

func _capture_draft() -> void:
	if editor != null:
		if editor.text != str(_file(current_path).get("text", "")):
			drafts[current_path] = editor.text
		else:
			drafts.erase(current_path)

func _on_text_changed() -> void:
	if not _rendering:
		_capture_draft()
		status_label.text = "Unsaved changes" if drafts.has(current_path) else "Saved"

func _new_file() -> void:
	_capture_draft()
	current_path = ""
	pending_new = true
	if editor != null:
		_rendering = true
		editor.text = ""
		_rendering = false
	if path_field != null:
		path_field.text = ""
		path_field.grab_focus()
	status_label.text = "Enter a virtual filename, then Save."

func _open_selected() -> void:
	var selected:=_selected_entry()
	if selected.is_empty():
		return
	if selected.get("folder",false):
		path_field.text=str(selected.path)+"/"
		status_label.text="Folder selected. Enter a file or folder name after the slash."
		return
	_capture_draft()
	current_path = str(selected.path)
	pending_new = false
	_load_editor()
	_send({"op": "editor", "path": current_path, "cursor": 0})
	status_label.text = "Opened " + current_path

func _valid_path(value: String) -> bool:
	if value.is_empty() or value.length() > 96 or value.begins_with("/") or value.contains("\\") or value.contains(":"):
		return false
	if value.split("/").size() > 4:
		return false
	for part in value.split("/"):
		if part.is_empty() or part == "." or part == ".." or part.length() > 32:
			return false
		for character in part:
			if not character in "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_.-":
				return false
	return true

func _save_file() -> void:
	if editor == null or path_field == null:
		return
	var path := path_field.text.strip_edges()
	if not _valid_path(path):
		status_label.text = "Use a relative virtual filename up to 96 characters."
		return
	if path != current_path and not pending_new:
		status_label.text = "Use Rename to change an existing filename."
		return
	if pending_new and not _file(path).is_empty():
		status_label.text = "That virtual file already exists."
		return
	var version := int(_file(path).get("version", 0))
	current_path = path
	drafts.erase("")
	drafts[path] = editor.text
	_send({"op": "save", "path": path, "text": editor.text, "version": version})
	status_label.text = "Saving " + path + "…"

func _rename_file() -> void:
	if not _supports_rename():
		status_label.text = "Rename is unavailable in this computer session."
		return
	if path_field == null:
		return
	var selected:=_selected_entry()
	var folder_selected:=bool(selected.get("folder",false))
	var old_path:=str(selected.get("path","")) if folder_selected else current_path
	if old_path.is_empty():return
	var new_path := path_field.text.strip_edges()
	if not _valid_path(new_path) or new_path == old_path or not _file(new_path).is_empty():
		status_label.text = "Choose a distinct valid virtual filename."
		return
	_capture_draft()
	if folder_selected:
		pending_folder_source=old_path;pending_folder_target=new_path
	else:pending_rename = new_path
	_send({"op": "rename", "path": old_path, "new_path": new_path})
	status_label.text = "Renaming " + old_path + "…"

func _supports_rename() -> bool:
	return session != null and session.has_method("supports_operation") and bool(session.call("supports_operation", "rename"))

func _build_course_work() -> void:
	var heading := Label.new()
	heading.text = "Course work"
	heading.add_theme_font_size_override("font_size", 19)
	content.add_child(heading)
	var materials: Variant = snapshot.get("materials", [])
	if materials is Array and not materials.is_empty():
		for item in materials:
			var label := Label.new()
			label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			label.text = str(item.get("title", "Material")) + "\n" + str(item.get("text", "")) if item is Dictionary else str(item)
			content.add_child(label)
	else:
		var label := Label.new()
		label.text = "The instructor's current lesson and assignment remain available through the classroom teaching and paper interfaces."
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		content.add_child(label)
	if game != null and game.school.phase == "lesson" and game.school.has_method("teaching_stage"):
		var stage: Dictionary = game.school.teaching_stage()
		var lesson := Label.new()
		lesson.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		lesson.text = str(stage.get("title", "Current lesson")) + "\n" + str(stage.get("text", stage.get("caption", "")))
		content.add_child(lesson)
	var papers: Variant = snapshot.get("papers", [])
	if papers is Array:
		for paper in papers:
			if paper is Dictionary:
				var label := Label.new()
				var project: Dictionary = paper.get("project", {})
				label.text = str(project.get("title", "Assignment")) + (" · Marked" if not paper.get("mark", {}).is_empty() else " · In progress")
				content.add_child(label)
				var paper_id := int(paper.get("id", 0))
				if paper_id > 0:
					content.add_child(_button("Open in paper workspace", func(): _open_paper(paper_id)))
					if not bool(paper.get("lesson", false)) and paper.get("mark", {}).is_empty() and str(project.get("kind", "")) == "lecture":
						content.add_child(_button("Submit lecture assignment", func(): _send({"op": "submit", "paper": paper_id})))

func _open_paper(id: int) -> void:
	if not drafts.is_empty():
		status_label.text = "Save or discard unsaved changes before opening the paper workspace."
		return
	pending_paper_id = id
	_exit_now()

func _send(payload: Dictionary) -> void:
	if session == null or snapshot.is_empty():
		return
	payload["lease"] = snapshot.get("lease", "")
	payload["revision"] = snapshot.get("revision", 0)
	var tiers: Dictionary = preload("res://scripts/campus/computers/laptop_inventory.gd").TIERS
	var tier: String = str(snapshot.get("tier", ""))
	var delay: int = int(tiers.get(tier, {}).get("delay_ms", 0))
	if delay > 0 and payload.get("op", "") in ["save", "mkdir", "delete", "rename", "answer", "submit", "refresh"]:
		if _portable_pending:
			status_label.text = "The laptop is still processing the previous action."
			return
		_portable_pending = true
		status_label.text = "Processing…"
		await get_tree().create_timer(float(delay) / 1000.0).timeout
		_portable_pending = false
		if not is_inside_tree() or snapshot.is_empty() or snapshot.get("lease") != payload.lease or snapshot.get("revision") != payload.revision:
			return
	session.request(payload)

func _on_operation_failed(message: String) -> void:
	pending_rename = ""
	pending_folder_source="";pending_folder_target=""
	status_label.text = message

func _request_exit() -> void:
	_capture_draft()
	if not drafts.is_empty():
		discard_dialog.popup_centered()
		return
	_exit_now()

func request_close() -> void:
	_request_exit()

func _exit_now() -> void:
	if is_instance_valid(browser_surface):browser_surface.close_session()
	_send({"op": "exit"})

func _power_off() -> void:
	if is_instance_valid(browser_surface):browser_surface.close_session()
	_send({"op":"power", "station":str(snapshot.get("station",""))})

func _browser_attachment(kind: String,id: String,lease: String,item: Dictionary) -> PackedByteArray:
	if not is_instance_valid(browser_surface) or kind!="computer" or id!=str(snapshot.get("station","")) or lease!=str(snapshot.get("lease","")) or not visible:return PackedByteArray()
	if item.get("kind","")!="virtual_file":return PackedByteArray()
	var file: Dictionary=_file(str(item.get("name","")))
	if file.is_empty():return PackedByteArray()
	var data:=str(file.get("text","")).to_utf8_buffer()
	return data if data.size()<=browser_surface.MAX_ATTACHMENT_BYTES and data.size()==int(item.get("bytes",-1)) else PackedByteArray()

func _browser_save_answer(answer: String) -> void:
	if not visible or snapshot.is_empty() or answer.is_empty():return
	var stem:="assistant_"+Time.get_datetime_string_from_system().replace(":","").replace("-","").replace("T","_")
	var path:=stem+".txt"
	var suffix:=1
	while not _file(path).is_empty() and suffix<100:
		path=stem+"_"+str(suffix)+".txt";suffix+=1
	if not _file(path).is_empty():status_label.text="No free name for the assistant answer.";return
	_send({"op":"save","path":path,"text":answer.left(1600),"version":0})
	status_label.text="Saving assistant answer as "+path+"…"

func _on_desktop_changed(value: Dictionary) -> void:
	if value.is_empty():
		for key in windows.keys():_close_window(key)
		var was_visible := visible
		visible = false
		snapshot.clear()
		drafts.clear()
		current_path = ""
		pending_new = false
		pending_rename = ""
		pending_folder_source="";pending_folder_target=""
		if discard_dialog != null:
			discard_dialog.hide()
		if game != null and was_visible:
			game.capture()
		elif game == null and was_visible:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		closed.emit()
		if pending_paper_id > 0 and game != null:
			var id := pending_paper_id
			pending_paper_id = 0
			game.paper_ui.open_sheet(id)
		return
	var prior_lease: Variant = snapshot.get("lease")
	if prior_lease!=value.get("lease") and is_instance_valid(browser_surface):_close_window("Browser")
	_capture_draft()
	snapshot = value.duplicate(true)
	var tiers: Dictionary = preload("res://scripts/campus/computers/laptop_inventory.gd").TIERS
	var scale: float = float(tiers.get(str(snapshot.get("tier", "")), {}).get("display_scale", 1.0))
	laptop_display_filter.visible = scale < 1.0
	(laptop_display_filter.material as ShaderMaterial).set_shader_parameter("display_scale", scale)
	if power_button != null:power_button.visible=bool(snapshot.get("public_device",false))
	if retry_documents_button != null:retry_documents_button.visible=not str(snapshot.get("local_error","")).is_empty()
	if folder_button != null:folder_button.visible=bool(snapshot.get("public_device",false))
	if delete_button != null:delete_button.visible=bool(snapshot.get("public_device",false))
	for path in drafts.keys():
		if not _file(str(path)).is_empty() and str(drafts[path]) == str(_file(str(path)).get("text", "")):
			drafts.erase(path)
	if prior_lease != snapshot.get("lease"):
		drafts.clear()
		current_path = str(snapshot.get("editor", {}).get("path", ""))
	elif not pending_folder_target.is_empty() and pending_folder_target in snapshot.get("folders",[]):
		if current_path.begins_with(pending_folder_source+"/"):current_path=pending_folder_target+current_path.substr(pending_folder_source.length())
		pending_folder_source="";pending_folder_target=""
	elif not pending_rename.is_empty() and not _file(pending_rename).is_empty():
		var old_path := current_path
		current_path = pending_rename
		if drafts.has(old_path):
			drafts[current_path] = drafts[old_path]
			drafts.erase(old_path)
		status_label.text = "Renamed to " + current_path
		pending_rename = ""
	elif pending_new and not current_path.is_empty() and not _file(current_path).is_empty():
		pending_new = false
		drafts.erase(current_path)
		status_label.text = "Saved " + current_path
	var was_visible := visible
	visible = true
	if game != null and not was_visible:
		game.release_mouse()
	elif game == null and not was_visible:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if windows.is_empty():_switch_app("Files")
	_refresh_file_list()
	_load_editor()
	if snapshot.has("local_error"):status_label.text=str(snapshot.local_error)

func _input(event: InputEvent) -> void:
	if not visible:
		return
	if snapshot.get("public_device",false) and (event is InputEventKey or event is InputEventMouseButton or event is InputEventMouseMotion):
		var now:=Time.get_ticks_msec()
		if now-last_activity_signal>=4000:
			last_activity_signal=now
			_send({"op":"activity"})
	if event is InputEventMouseButton and event.pressed and event.button_index==MOUSE_BUTTON_LEFT:
		var hovered:=get_viewport().gui_get_hovered_control()
		while is_instance_valid(hovered) and hovered!=workspace:
			if hovered.has_meta("desktop_app"):
				if app_window!=hovered:
					_capture_draft()
					_focus_window(hovered.get_meta("desktop_app"))
				break
			hovered=hovered.get_parent_control()
	if not event is InputEventKey or not event.pressed or event.echo:return
	if discard_dialog != null and discard_dialog.visible:
		return
	if event.keycode == KEY_ESCAPE:
		_request_exit()
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_S and event.ctrl_pressed:
		_save_file()
		get_viewport().set_input_as_handled()
