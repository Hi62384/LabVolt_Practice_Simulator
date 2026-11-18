extends VBoxContainer
const UI=preload("res://scripts/ui/design_system/widgets.gd")
var desktop: Control
var transcript: TextEdit
var entry: LineEdit
var folder := ""
var history: Array[String]=[]
var history_index:=0

func build(parent: Control) -> void:
	desktop=parent
	transcript=TextEdit.new()
	transcript.editable=false
	transcript.wrap_mode=TextEdit.LINE_WRAPPING_BOUNDARY
	transcript.size_flags_vertical=Control.SIZE_EXPAND_FILL
	transcript.custom_minimum_size.y=150
	add_child(transcript)
	transcript.text="Campus Terminal\nType help for virtual workspace commands."
	entry=LineEdit.new()
	entry.placeholder_text="Workspace command"
	entry.max_length=160
	add_child(entry)
	entry.text_submitted.connect(_run)
	entry.gui_input.connect(_history_input)

func _history_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.keycode not in [KEY_UP,KEY_DOWN]:return
	history_index=clampi(history_index+(-1 if event.keycode==KEY_UP else 1),0,history.size())
	entry.text=history[history_index] if history_index<history.size() else ""
	entry.caret_column=entry.text.length()
	entry.accept_event()

func _run(raw: String) -> void:
	var command:=raw.strip_edges()
	if command.is_empty():return
	var verb:=command.get_slice(" ",0).to_lower()
	var value:=command.substr(verb.length()).strip_edges()
	entry.clear()
	history.append(command)
	if history.size()>48:history.pop_front()
	history_index=history.size()
	if verb=="clear":
		transcript.clear()
		return
	_print("> "+command)
	match verb:
		"help":_print("help  clear  pwd  ls  cd  mkdir  touch  cat  echo  open  date")
		"pwd":_print("/"+folder)
		"date":_print(Time.get_datetime_string_from_system(false,true))
		"echo":_print(value)
		"ls":
			var names:=PackedStringArray()
			for path in desktop.snapshot.get("folders",[]):
				if desktop._parent_folder(path)==folder:names.append(path.get_file()+"/")
			for row in desktop._file_rows():
				if desktop._parent_folder(row.path)==folder:names.append(str(row.path).get_file())
			names.sort()
			_print("  ".join(names) if not names.is_empty() else "(empty)")
		"cd":
			if value in ["","/"]:folder=""
			elif value=="..":folder=desktop._parent_folder(folder)
			else:
				var path:=_path(value)
				if path in desktop.snapshot.get("folders",[]):folder=path
				else:_print("Folder not found.")
		"mkdir","touch","cat","open":
			var path:=_path(value)
			if not desktop._valid_path(path):
				_print("Use a valid virtual path.")
				return
			var file: Dictionary=desktop._file(path)
			match verb:
				"mkdir":
					if not desktop.snapshot.get("public_device",false):_print("Folders are unavailable on this device.")
					else:desktop._send({"op":"mkdir","path":path})
				"touch":
					if file.is_empty():desktop._send({"op":"save","path":path,"version":0,"text":""})
				"cat":
					_print("File not found." if file.is_empty() else str(file.text))
				"open":
					if file.is_empty():_print("File not found.")
					else:desktop._open_path(path)
		_:_print("Command not found. Type help for available commands.")

func _path(value: String) -> String:
	if value.is_empty():return ""
	if value.begins_with("/"):return value.substr(1)
	return value if folder.is_empty() else folder+"/"+value

func _print(text: String) -> void:
	transcript.text=(transcript.text+"\n"+text).right(10000)
	transcript.set_caret_line(transcript.get_line_count()-1)
