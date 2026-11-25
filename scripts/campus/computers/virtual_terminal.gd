extends VBoxContainer
const UI=preload("res://scripts/ui/design_system/widgets.gd")
const Interpreter=preload("res://scripts/campus/computers/campus_script.gd")
var desktop: Control
var transcript: RichTextLabel
var lines: Array[String]=[]
var entry: LineEdit
var folder := ""
var history: Array[String]=[]
var history_index:=0

func build(parent: Control) -> void:
	desktop=parent
	var mono := SystemFont.new()
	mono.font_names = PackedStringArray(["Consolas", "DejaVu Sans Mono"])
	transcript=RichTextLabel.new()
	transcript.add_theme_stylebox_override("normal",preload("res://scripts/ui/design_system/tokens.gd").surface(Color("031d2c"),Color("27596b"),10))
	transcript.add_theme_font_override("normal_font", mono)
	transcript.selection_enabled=true
	transcript.scroll_following=true
	transcript.size_flags_vertical=Control.SIZE_EXPAND_FILL
	transcript.custom_minimum_size.y=150
	add_child(transcript)
	_print("Campus Terminal\nType help for virtual workspace commands.",Color("91b4c6"))
	entry=LineEdit.new()
	entry.placeholder_text="Workspace command"
	entry.right_icon=UI.icon("code")
	entry.add_theme_font_override("font", mono)
	entry.caret_blink = true
	entry.max_length=160
	add_child(entry)
	entry.text_submitted.connect(_run)
	entry.gui_input.connect(_history_input)

func _history_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.ctrl_pressed and event.keycode == KEY_C and not entry.has_selection():
		entry.clear()
		entry.accept_event()
		return
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
		lines.clear()
		return
	_print("campus:/" + folder + "$ " + command,Color("84e8ad"))
	if command.begins_with("./"):
		_execute(_path(command.substr(2)))
		return
	match verb:
		"help":_print("Navigation   pwd, ls [folder], tree, cd <folder>\nFiles        mkdir, touch, cat, head, tail, wc, open, rm\nTransfers    cp <source> <destination>, mv, zip, unzip\nPrograms     run <file.campus>, ./file.campus\nOther        echo, date, clear\nQuote paths that contain spaces.")
		"pwd":_print("/"+folder)
		"date":_print(Time.get_datetime_string_from_system(false,true))
		"echo":_print(value)
		"ls","tree":
			var directory:=folder if value.is_empty() else _path(value)
			if not directory.is_empty() and not directory in desktop.snapshot.get("folders",[]):_print("Folder not found.");return
			var names:=PackedStringArray()
			for path in desktop.snapshot.get("folders",[]):
				if verb=="tree" and (directory.is_empty() or str(path).begins_with(directory+"/")):names.append(path+"/")
				elif verb=="ls" and desktop._parent_folder(path)==directory:names.append(path.get_file()+"/")
			for row in desktop._file_rows():
				if verb=="tree" and (directory.is_empty() or str(row.path).begins_with(directory+"/")):names.append(row.path)
				elif verb=="ls" and desktop._parent_folder(row.path)==directory:names.append(str(row.path).get_file())
			for path: String in desktop.snapshot.get("binary_files",{}):
				if verb=="tree" and (directory.is_empty() or path.begins_with(directory+"/")):names.append(path)
				elif verb=="ls" and desktop._parent_folder(path)==directory:names.append(path.get_file())
			names.sort()
			_print(("\n" if verb=="tree" else "  ").join(names.slice(0,300)) if not names.is_empty() else "(empty)")
		"cd":
			if value in ["","/"]:folder=""
			elif value=="..":folder=desktop._parent_folder(folder)
			else:
				var path:=_path(value)
				if path in desktop.snapshot.get("folders",[]):folder=path
				else:_print("Folder not found.")
		"run":_execute(_path(value))
		"cp","mv","zip","unzip":
			var arguments:=_arguments(value)
			if arguments.size()!=2:_print("Usage: %s <source> <destination>"%verb);return
			var source:=_path(arguments[0])
			var target:=_path(arguments[1])
			if not desktop._virtual_path_exists(source):_print("Source not found.");return
			if target in desktop.snapshot.get("folders",[]) and verb in ["cp","mv"]:target+="/"+source.get_file()
			if not desktop._valid_path(target):_print("Invalid destination.");return
			var operation: String={"cp":"copy","mv":"rename","zip":"zip","unzip":"extract"}[verb]
			if verb=="mv":
				desktop.pending_folder_source=source
				desktop.pending_folder_target=target
			desktop._send({"op":operation,"path":source,"new_path":target})
		"mkdir","touch","cat","head","tail","wc","open","rm":
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
				"head","tail","wc":
					if file.is_empty():_print("Open the text file in an editor first.");return
					var text:=str(file.text)
					var rows:=text.split("\n")
					if verb=="wc":_print("%d lines · %d bytes"%[rows.size(),text.to_utf8_buffer().size()])
					else:_print("\n".join(rows.slice(0,10) if verb=="head" else rows.slice(maxi(0,rows.size()-10))))
				"open":
					if not desktop._virtual_path_exists(path):_print("File not found.")
					else:desktop._open_workspace_file(path)
				"rm":
					if not desktop._virtual_path_exists(path):_print("File not found.")
					else:desktop._delete_path(path)
		_:_print("Command not found. Type help for available commands.")

func _path(value: String) -> String:
	value=value.strip_edges().trim_prefix("\"").trim_suffix("\"")
	if value.is_empty():return ""
	var parts:=PackedStringArray() if value.begins_with("/") or folder.is_empty() else folder.split("/")
	for component in value.split("/",false):
		if component==".":continue
		if component=="..":
			if not parts.is_empty():parts.resize(parts.size()-1)
		else:parts.append(component)
	return "/".join(parts)

func _arguments(value: String) -> PackedStringArray:
	var parts:=PackedStringArray()
	var word:=""
	var quoted:=false
	for character in value:
		if character=="\"":quoted=not quoted
		elif character==" " and not quoted:
			if not word.is_empty():parts.append(word);word=""
		else:word+=character
	if quoted:return PackedStringArray()
	if not word.is_empty():parts.append(word)
	return parts

func _execute(path: String) -> void:
	if path.get_extension().to_lower()!="campus":
		_print("Run a .campus program inside Campus OS.")
		return
	if not desktop._virtual_path_exists(path):_print("Program not found.");return
	desktop._run_workspace_script(path)

func run_program(path: String, text: String) -> void:
	_print("Running "+path,Color("84e8ad"))
	_print(Interpreter.new().run(text))

func _print(text: String,tint := Color("d9eaf4")) -> void:
	if lines.size()>=160:
		lines.pop_front()
		transcript.remove_paragraph(0)
	lines.append(text)
	transcript.push_color(tint)
	transcript.add_text(text)
	transcript.pop()
	transcript.newline()
