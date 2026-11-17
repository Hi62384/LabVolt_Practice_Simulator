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
var app_list: ItemList
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
var app_names := ["Files", "Text editor", "Code editor", "Course work", "Calculator", "Browser", "Run code"]
var app_icons := {"Files":"▤", "Text editor":"✎", "Code editor":"‹›", "Course work":"▣", "Calculator":"＋", "Browser":"◎", "Run code":"▶"}

func build(source: Node, owner_game: Node = null) -> void:
	session = source
	game = owner_game
	theme = preload("res://scripts/ui/design_system/theme.gd").create()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	if not session.desktop_changed.is_connected(_on_desktop_changed):
		session.desktop_changed.connect(_on_desktop_changed)
	if not session.operation_failed.is_connected(_on_operation_failed):
		session.operation_failed.connect(_on_operation_failed)
	_build_shell()

func _build_shell() -> void:
	var backdrop := ColorRect.new()
	backdrop.color = Color("0b202d")
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
	retry_documents_button = _button("Retry documents", func():session.retry_local_documents())
	retry_documents_button.visible = false
	header.add_child(retry_documents_button)
	power_button = _button("Power off", _power_off)
	power_button.visible = false
	header.add_child(power_button)
	header.add_child(_button("Leave computer  Esc", _request_exit))
	var window := PanelContainer.new()
	app_window = window
	window.size_flags_vertical = Control.SIZE_EXPAND_FILL
	window.add_theme_stylebox_override("panel", preload("res://scripts/ui/design_system/tokens.gd").surface(Color("132735"), Color("4b7180"), 12))
	root.add_child(window)
	var window_column := VBoxContainer.new()
	window_column.add_theme_constant_override("separation", 0)
	window.add_child(window_column)
	var window_bar := HBoxContainer.new()
	window_bar.add_theme_constant_override("separation", 10)
	window_bar.add_theme_stylebox_override("panel", preload("res://scripts/ui/design_system/tokens.gd").surface(Color("1d3948"), Color("4b7180"), 9))
	window_column.add_child(window_bar)
	app_window_title = Label.new()
	app_window_title.text = "Files"
	app_window_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	app_window_title.add_theme_font_size_override("font_size", 17)
	window_bar.add_child(app_window_title)
	window_bar.add_child(_button("—", func(): window.hide()))
	window_bar.add_child(_button("□", func(): window.show()))
	window_bar.add_child(_button("×", func(): window.hide()))
	var inner := MarginContainer.new()
	inner.size_flags_vertical = Control.SIZE_EXPAND_FILL
	for side in ["left", "top", "right", "bottom"]: inner.add_theme_constant_override("margin_" + side, 12)
	window_column.add_child(inner)
	var body := VBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	inner.add_child(body)
	app_list = ItemList.new()
	app_list.hide()
	for name in app_names:
		app_list.add_item(name)
	app_list.item_selected.connect(func(index: int): _switch_app(app_list.get_item_text(index)))
	content = VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(content)
	status_label = Label.new()
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(status_label)
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
	var clock := Label.new()
	clock.text = "CAMPUS"
	clock.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	clock.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	taskbar.add_child(clock)
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
	app_list.select(0)
	_switch_app("Files")

func _button(label: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = label
	button.custom_minimum_size = Vector2(100, 38)
	button.pressed.connect(action)
	return button

func _clear_content() -> void:
	if is_instance_valid(browser_surface):browser_surface.close_session();browser_surface=null
	for child in content.get_children():
		content.remove_child(child)
		child.queue_free()
	file_list = null
	editor = null
	path_field = null
	folder_button = null
	delete_button = null

func _switch_app(name: String) -> void:
	_capture_draft()
	active_app = name
	if is_instance_valid(app_window): app_window.show()
	if is_instance_valid(app_window_title): app_window_title.text = str(app_icons.get(name, "•")) + "  " + name
	for child in get_children():
		if child is PanelContainer and child == start_panel: start_panel.hide()
	_clear_content()
	if name == "Files" or name == "Text editor" or name == "Code editor":
		_build_files(name)
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
		if is_instance_valid(browser_surface):browser_surface.close_session()
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
	if prior_lease!=value.get("lease") and is_instance_valid(browser_surface):browser_surface.close_session()
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
	if active_app == "Browser" and prior_lease != snapshot.get("lease"):
		_switch_app("Browser")
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
	if not event is InputEventKey or not event.pressed or event.echo:return
	if discard_dialog != null and discard_dialog.visible:
		return
	if event.keycode == KEY_ESCAPE:
		_request_exit()
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_S and event.ctrl_pressed:
		_save_file()
		get_viewport().set_input_as_handled()
