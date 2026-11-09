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
var _rendering := false

func build(source: Node, owner_game: Node = null) -> void:
	session = source
	game = owner_game
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
	backdrop.color = Color("0b1624")
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
	title_label.text = "CAMPUS COMPUTER"
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_label.add_theme_font_size_override("font_size", 22)
	header.add_child(title_label)
	header.add_child(_button("Leave computer  Esc", _request_exit))
	var body := HSplitContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(body)
	app_list = ItemList.new()
	app_list.custom_minimum_size.x = 155
	for name in ["Files", "Text editor", "Code editor", "Course work", "Browser", "Run code"]:
		app_list.add_item(name)
	app_list.item_selected.connect(func(index: int): _switch_app(app_list.get_item_text(index)))
	body.add_child(app_list)
	content = VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(content)
	status_label = Label.new()
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(status_label)
	discard_dialog = ConfirmationDialog.new()
	discard_dialog.title = "Leave computer?"
	discard_dialog.dialog_text = "Unsaved editor changes will be lost. Save the files you want to keep before leaving."
	discard_dialog.ok_button_text = "Discard and leave"
	discard_dialog.confirmed.connect(_exit_now)
	add_child(discard_dialog)
	app_list.select(0)
	_switch_app("Files")

func _button(label: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = label
	button.custom_minimum_size = Vector2(100, 38)
	button.pressed.connect(action)
	return button

func _clear_content() -> void:
	for child in content.get_children():
		content.remove_child(child)
		child.queue_free()
	file_list = null
	editor = null
	path_field = null

func _switch_app(name: String) -> void:
	_capture_draft()
	active_app = name
	_clear_content()
	if name == "Files" or name == "Text editor" or name == "Code editor":
		_build_files(name)
	elif name == "Course work":
		_build_course_work()
	else:
		var message := Label.new()
		message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		message.text = "Campus browser is not available yet." if name == "Browser" else "Code execution is not available yet. You can edit and save source files."
		content.add_child(message)
		status_label.text = message.text

func _build_files(name: String) -> void:
	var toolbar := HFlowContainer.new()
	content.add_child(toolbar)
	toolbar.add_child(_button("New", _new_file))
	toolbar.add_child(_button("Open", _open_selected))
	toolbar.add_child(_button("Save  Ctrl+S", _save_file))
	var rename := _button("Rename", _rename_file)
	rename.disabled = not _supports_rename()
	rename.tooltip_text = "Rename is unavailable in this computer session." if rename.disabled else "Rename the selected virtual file."
	toolbar.add_child(rename)
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
	for value in _file_rows():
		if value is Dictionary:
			file_list.add_item(str(value.get("path", "")))

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
	if file_list == null or file_list.get_selected_items().is_empty():
		return
	_capture_draft()
	current_path = file_list.get_item_text(file_list.get_selected_items()[0])
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
	if current_path.is_empty() or path_field == null:
		return
	var new_path := path_field.text.strip_edges()
	if not _valid_path(new_path) or new_path == current_path or not _file(new_path).is_empty():
		status_label.text = "Choose a distinct valid virtual filename."
		return
	_capture_draft()
	var old_path := current_path
	_send({"op": "rename", "path": old_path, "new_path": new_path})
	pending_rename = new_path
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
	session.request(payload)

func _on_operation_failed(message: String) -> void:
	pending_rename = ""
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
	_send({"op": "exit"})

func _on_desktop_changed(value: Dictionary) -> void:
	if value.is_empty():
		var was_visible := visible
		visible = false
		snapshot.clear()
		drafts.clear()
		current_path = ""
		pending_new = false
		pending_rename = ""
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
	_capture_draft()
	snapshot = value.duplicate(true)
	for path in drafts.keys():
		if not _file(str(path)).is_empty() and str(drafts[path]) == str(_file(str(path)).get("text", "")):
			drafts.erase(path)
	if prior_lease != snapshot.get("lease"):
		drafts.clear()
		current_path = str(snapshot.get("editor", {}).get("path", ""))
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
	_refresh_file_list()
	_load_editor()

func _input(event: InputEvent) -> void:
	if not visible or not event is InputEventKey or not event.pressed or event.echo:
		return
	if discard_dialog != null and discard_dialog.visible:
		return
	if event.keycode == KEY_ESCAPE:
		_request_exit()
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_S and event.ctrl_pressed:
		_save_file()
		get_viewport().set_input_as_handled()
