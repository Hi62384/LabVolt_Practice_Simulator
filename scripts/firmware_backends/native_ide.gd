extends VBoxContainer
const Chrome = preload("res://scripts/ui/circuit_editor_panels/chrome.gd")
## Integrator attaches to an actually placed native board, never a decorative
## board selector. Upload/control signals must go to the host authority.
signal upload_requested(firmware: Dictionary,sources: Dictionary)
signal control_requested(controls: Dictionary)
signal save_requested(firmware: Dictionary,sources: Dictionary)
signal draft_requested(sources: Dictionary)
const Document=preload("res://scripts/firmware_backends/program_document.gd")
var serial_history: Array=[]
var last_serial_key := ""
var board := ""
var source_tabs: TabContainer
var image: CodeEdit
var vector_offset: SpinBox
var status: Label
var debug_output: TextEdit
var serial_input: LineEdit
var editors: Dictionary={}
var compiler: Node
var compile_button: Button
var diagnostic_list: ItemList
var diagnostics: Array=[]
var source_map: Array=[]
var compiled_source_hash := ""
var compiled_image_hash := ""
var autosave_left := -1.0

func build(board_id: String,firmware: Dictionary={},sources: Dictionary={}) -> void:
	board=board_id
	apply_studio_theme();add_theme_constant_override("separation",8)
	if board not in ["uno","nano","pico"]:
		var unsupported := Label.new();unsupported.text="Unsupported native firmware board";add_child(unsupported);return
	var heading := Label.new();heading.add_theme_font_size_override("font_size",22);heading.text=("Arduino Nano classic · AVR8js" if board=="nano" else "Arduino Uno R3 · AVR8js" if board=="uno" else "Raspberry Pi Pico · RP2040js")+" · source and firmware studio";add_child(heading)
	var help := Label.new();help.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	help.text="Compile locally through the isolated host toolchain, inspect diagnostics, then validate and upload the image. Uno supports Arduino-core C/C++ (explicit forward declarations may be needed in .ino files). Pico compilation is a bare-metal C/C++ workflow, not general SDK or MicroPython compatibility. Imported images remain supported. Source breakpoints require a matching compiler line map; CPU stepping uses byte PCs."
	add_child(help)
	var guide := CheckButton.new();guide.text="Workflow and compatibility guide";add_child(guide);move_child(guide,help.get_index());help.visible=false;guide.toggled.connect(func(on):help.visible=on)
	var pin_help := Label.new();pin_help.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;pin_help.text=preload("res://scripts/firmware_backends/pin_metadata.gd").summary(board);add_child(pin_help)
	source_tabs=TabContainer.new();source_tabs.custom_minimum_size.y=320;add_child(source_tabs)
	var initial := sources.duplicate(true)
	if initial.is_empty():initial["sketch.ino" if board in ["uno","nano"] else "main.cpp"]=template_source(board)
	for name in initial:
		if editors.size()>=16:break
		add_source(str(name),str(initial[name]))
	var add_bar := HFlowContainer.new();add_child(add_bar)
	var file_name := LineEdit.new();file_name.custom_minimum_size.x=240;file_name.placeholder_text="library.h";add_bar.add_child(file_name)
	button(add_bar,"Add source",func():
		if editors.size()>=16 or not source_name_ok(file_name.text) or editors.has(file_name.text):status.text="Use a unique simple filename (up to 16 source files).";return
		add_source(file_name.text,"")
	)
	var search := HFlowContainer.new();add_child(search)
	var find := LineEdit.new();find.custom_minimum_size.x=210;find.placeholder_text="Find in active source";search.add_child(find)
	var replace := LineEdit.new();replace.custom_minimum_size.x=210;replace.placeholder_text="Replace with";search.add_child(replace)
	button(search,"Find next",func():
		var active := active_editor()
		if active==null or find.text.is_empty():return
		var hit := active.search(find.text,0,active.get_caret_line(),active.get_caret_column()+1)
		if hit.x>=0:active.select(hit.y,hit.x,hit.y,hit.x+find.text.length());active.set_caret_line(hit.y);active.set_caret_column(hit.x)
	)
	button(search,"Replace all",func():
		var active := active_editor()
		if active!=null and not find.text.is_empty():active.text=active.text.replace(find.text,replace.text)
	)
	var compile_bar := HFlowContainer.new();add_child(compile_bar)
	compile_button=Chrome.action(compile_bar,"Compile source",compile_sources)
	button(compile_bar,"Cancel compile",func():if compiler!=null:compiler.cancel())
	button(compile_bar,"Import source…",choose_sources)
	button(compile_bar,"Remove active source",remove_active_source)
	button(compile_bar,"Breakpoint at source line",breakpoint_at_source)
	diagnostic_list=ItemList.new();diagnostic_list.custom_minimum_size.y=100;diagnostic_list.item_selected.connect(select_diagnostic);add_child(diagnostic_list)
	compiler=preload("res://scripts/firmware_toolchain/compile_service.gd").new();add_child(compiler);compiler.finished.connect(compile_finished)
	var label := Label.new();label.text="Compiled Intel HEX" if board in ["uno","nano"] else "Compiled flash binary · base64";add_child(label)
	image=CodeEdit.new();image.custom_minimum_size.y=150;image.text=str(firmware.get("image",""));image.gutters_draw_line_numbers=true;add_child(image)
	if board=="pico":
		var row := HFlowContainer.new();add_child(row);var explanation := Label.new();explanation.text="Vector table byte offset in raw flash (usually 256)";row.add_child(explanation)
		vector_offset=SpinBox.new();vector_offset.min_value=0;vector_offset.max_value=2097144;vector_offset.step=4;vector_offset.value=int(firmware.get("vector_offset",256));row.add_child(vector_offset)
	var actions := HFlowContainer.new();add_child(actions)
	button(actions,"Import image…",choose_image)
	button(actions,"Validate image",func():validate_program())
	button(actions,"Save source draft",func():
		var files := source_files()
		if not preload("res://scripts/inventory_authority/firmware_schema.gd").files(files,false):status.text="Invalid source project";return
		draft_requested.emit(files)
	)
	button(actions,"Save program",func():
		if validate_program():save_requested.emit(program(),source_files())
	)
	button(actions,"Upload compiled image",func():
		if validate_program():upload_requested.emit(program(),source_files())
	)
	button(actions,"Run",func():control_requested.emit({"run":true,"resume":true}))
	button(actions,"Stop",func():control_requested.emit({"run":false}))
	button(actions,"Reset",func():control_requested.emit({"reset":true}))
	button(actions,"Step instruction",func():control_requested.emit({"run":true,"step":true}))
	var debug_bar := HFlowContainer.new();add_child(debug_bar)
	var address := LineEdit.new();address.placeholder_text="Byte PC (decimal or 0xhex)";address.custom_minimum_size.x=250;debug_bar.add_child(address)
	button(debug_bar,"Set breakpoint",func():
		var text := address.text.strip_edges();var number := -1
		if text.begins_with("0x") and text.substr(2).is_valid_hex_number():number=text.hex_to_int()
		elif text.is_valid_int():number=text.to_int()
		if number<0 or number>0xffffffff:status.text="Invalid byte PC";return
		control_requested.emit({"breakpoints":[number]})
	)
	button(debug_bar,"Clear breakpoints",func():control_requested.emit({"breakpoints":[]}))
	serial_input=LineEdit.new();serial_input.custom_minimum_size.x=160;serial_input.placeholder_text="UART0 byte 0–255";debug_bar.add_child(serial_input)
	button(debug_bar,"Send byte",func():
		if not serial_input.text.is_valid_int() or int(serial_input.text) not in range(256):status.text="Enter a byte 0–255";return
		control_requested.emit({"uart_rx":[{"port":0,"value":int(serial_input.text)}]})
	)
	status=Label.new();status.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;status.text="Host state not attached";add_child(status)
	debug_output=TextEdit.new();debug_output.editable=false;debug_output.custom_minimum_size.y=140;add_child(debug_output)
	Chrome.labeled(file_name,"New source filename")
	Chrome.labeled(find,"Find in active source")
	Chrome.labeled(replace,"Replacement text")
	Chrome.labeled(address,"Instruction breakpoint · byte PC")
	Chrome.labeled(serial_input,"UART0 input · byte")
	Chrome.section(self,"Board pin reference", "chip", pin_help, pin_help)
	Chrome.section(self,"Source workspace", "circuit", source_tabs, search)
	Chrome.section(self,"Build and diagnostics", "chip", compile_bar, diagnostic_list)
	Chrome.section(self,"Compiled image and deployment", "save", label, actions)
	Chrome.section(self,"Debug and serial controls", "settings", debug_bar, debug_output)
	Chrome.finish(self)
	source_map=Document.load_compiler_map(board,program(),source_files())
	if not source_map.is_empty():
		compiled_source_hash=preload("res://scripts/firmware_toolchain/source_request.gd").source_hash(source_files())
		compiled_image_hash=image.text.strip_edges().sha256_text()

static func source_name_ok(name: String) -> bool:
	return preload("res://scripts/firmware_toolchain/source_request.gd").name_ok(name)

func add_source(name: String,text: String) -> void:
	if not source_name_ok(name):return
	var editor := CodeEdit.new();editor.name=name;editor.text=text.left(65536);editor.gutters_draw_line_numbers=true;editor.gutters_draw_fold_gutter=true;editor.line_folding=true;editor.indent_automatic=true;editor.auto_brace_completion_enabled=true;editor.code_completion_enabled=true;editor.add_comment_delimiter("//","",true);editor.add_comment_delimiter("/*","*/",false)
	var syntax := CodeHighlighter.new();syntax.number_color=Color("e6b677");syntax.symbol_color=Color("8ccef0")
	for keyword in ["void","int","const","bool","float","if","else","while","for","return","include"]:syntax.add_keyword_color(keyword,Color("80ddbd"))
	syntax.add_color_region('"','"',Color("e8cb92"));syntax.add_color_region("//","",Color("81969d"),true);syntax.add_color_region("/*","*/",Color("81969d"));editor.syntax_highlighter=syntax
	editor.code_completion_requested.connect(func():
		var words: Array=["void","int","const","bool","float","if","else","while","for","return"]
		if board in ["uno","nano"]:words.append_array(["pinMode","digitalWrite","digitalRead","analogRead","analogWrite","delay","HIGH","LOW","INPUT","OUTPUT","INPUT_PULLUP","LED_BUILTIN"])
		for word in words:editor.add_code_completion_option(CodeEdit.KIND_FUNCTION,str(word),str(word))
		editor.update_code_completion_options(true)
	)
	editor.text_changed.connect(func():autosave_left=1.0)
	editors[name]=editor;source_tabs.add_child(editor);source_tabs.set_tab_title(source_tabs.get_tab_count()-1,name)

func button(parent: Node,text: String,action: Callable) -> void:
	Chrome.action(parent,text,action)

func source_files() -> Dictionary:
	var result := {}
	for name in editors:result[name]=editors[name].text
	return result
func program() -> Dictionary:
	var result := {"schema":1,"board":board,"format":"intel_hex" if board in ["uno","nano"] else "bin_base64","image":image.text.strip_edges()}
	if board=="pico":result.vector_offset=int(vector_offset.value)
	return result
func validate_program() -> bool:
	var result := Document.validate(board,program(),source_files())
	status.text="Valid compiled image · %d bytes in saved document"%result.bytes if result.ok else result.error
	return result.ok
func choose_image() -> void:
	var dialog := FileDialog.new();dialog.file_mode=FileDialog.FILE_MODE_OPEN_FILE;dialog.access=FileDialog.ACCESS_FILESYSTEM
	dialog.filters=PackedStringArray(["*.hex ; Intel HEX"]) if board in ["uno","nano"] else PackedStringArray(["*.bin ; Raw flash binary"])
	add_child(dialog)
	dialog.file_selected.connect(func(path):
		var file := FileAccess.open(path,FileAccess.READ)
		if file==null:status.text="Could not read selected image";dialog.queue_free();return
		var limit := 131072 if board in ["uno","nano"] else 2097152
		if file.get_length()>limit:status.text="Selected image exceeds board flash/image limit";dialog.queue_free();return
		var bytes := file.get_buffer(file.get_length())
		image.text=bytes.get_string_from_utf8() if board in ["uno","nano"] else Marshalls.raw_to_base64(bytes)
		validate_program();dialog.queue_free()
	)
	dialog.canceled.connect(func():dialog.queue_free());dialog.popup_centered_ratio(.7)
func set_snapshot(snapshot: Dictionary) -> void:
	if not is_instance_valid(debug_output):return
	var key := JSON.stringify([snapshot.get("cycles",0),snapshot.get("serial",[])])
	if key!=last_serial_key:
		last_serial_key=key
		for entry in snapshot.get("serial",[]):
			serial_history.append(entry)
		while serial_history.size()>256:serial_history.pop_front()
	var text := "%s · PC 0x%X · %.6f s · power %s"%[snapshot.get("status","Unavailable"),int(snapshot.get("pc",0)),float(snapshot.get("time",0)),"on" if snapshot.get("powered",false) else "off"]
	# Preserve save/validation diagnostics; runtime state has its own display.
	debug_output.text=text+"\n"+JSON.stringify({"GPIO":snapshot.get("outputs",{}),"registers":snapshot.get("registers",[]),"UART bytes":serial_history,"events":snapshot.get("events",[]),"dropped_events":snapshot.get("dropped_events",0)},"  ")

func apply_studio_theme() -> void:
	Chrome.setup(self)

func active_editor() -> CodeEdit:
	if source_tabs.current_tab<0:return null
	return source_tabs.get_current_tab_control() as CodeEdit

static func template_source(board_id: String) -> String:
	if board_id in ["uno","nano"]:return "void setup() { pinMode(LED_BUILTIN, OUTPUT); }\nvoid loop() {\n  digitalWrite(LED_BUILTIN, HIGH); delay(500);\n  digitalWrite(LED_BUILTIN, LOW); delay(500);\n}\n"
	return '#include "labvolt_pico.h"\nint main() {\n  lv_gpio_output(25);\n  for (;;) {\n    lv_gpio_write(25, 1); for (volatile unsigned i=0; i<100000; ++i) {}\n    lv_gpio_write(25, 0); for (volatile unsigned i=0; i<100000; ++i) {}\n  }\n}\n'

func compile_sources() -> void:
	var active := active_editor()
	if active==null:return
	var entry := ""
	for name in editors:
		if editors[name]==active:entry=str(name);break
	if entry.get_extension() in ["h","hpp"]:
		for name in editors:
			if str(name).get_extension() in ["ino","cpp","c"]:entry=str(name);break
	var language := "micropython" if entry.ends_with(".py") else ""
	var result: Dictionary=compiler.start(board,source_files(),entry,language)
	if result.ok:compile_button.disabled=true;status.text="Compiling in an isolated local job… Existing uploaded firmware keeps its current state."
	else:compile_finished(result)

func compile_finished(result: Dictionary) -> void:
	compile_button.disabled=false
	diagnostics=result.get("diagnostics",[]);diagnostic_list.clear()
	for diagnostic in diagnostics:diagnostic_list.add_item("%s:%d:%d · %s · %s"%[str(diagnostic.file),int(diagnostic.line),int(diagnostic.column),str(diagnostic.severity),str(diagnostic.message)])
	if not result.get("ok",false):status.text=str(result.get("status","Compile failed"))+": "+str(result.get("error","See diagnostics"));return
	var hash_now := preload("res://scripts/firmware_toolchain/source_request.gd").source_hash(source_files())
	if hash_now!=str(result.artifact.source_sha256):status.text="Source changed during compilation. Compile again; previous image retained.";return
	image.text=str(result.firmware.image)
	if board=="pico":vector_offset.value=int(result.firmware.get("vector_offset",256))
	source_map=result.get("source_map",[]);compiled_source_hash=hash_now
	compiled_image_hash=image.text.strip_edges().sha256_text()
	Document.save_compiler_map(board,program(),source_files(),source_map)
	status.text="Compiled and validated. %d source locations available. Save or upload when ready."%source_map.size()

func select_diagnostic(index: int) -> void:
	if index<0 or index>=diagnostics.size():return
	var diagnostic: Dictionary=diagnostics[index]
	if not editors.has(str(diagnostic.file)):return
	var editor: CodeEdit=editors[str(diagnostic.file)]
	source_tabs.current_tab=editor.get_index();editor.grab_focus()
	var line := clampi(int(diagnostic.line)-1,0,maxi(0,editor.get_line_count()-1))
	editor.set_caret_line(line);editor.set_caret_column(maxi(0,int(diagnostic.column)-1));editor.set_line_background_color(line,Color("60362f"))

func breakpoint_at_source() -> void:
	if compiled_source_hash!=preload("res://scripts/firmware_toolchain/source_request.gd").source_hash(source_files()) or compiled_image_hash!=image.text.strip_edges().sha256_text():status.text="Compile this exact source and image revision before setting source breakpoints.";return
	var active := active_editor()
	if active==null:return
	var file := ""
	for name in editors:
		if editors[name]==active:file=str(name);break
	var addresses := preload("res://scripts/firmware_toolchain/diagnostics.gd").addresses(source_map,file,active.get_caret_line()+1)
	if addresses.is_empty():status.text="This line has no emitted instruction address (it may be optimized out).";return
	control_requested.emit({"breakpoints":addresses.slice(0,32)})
	status.text="Source line mapped to %d byte-PC breakpoint(s)."%mini(32,addresses.size())

func choose_sources() -> void:
	var dialog := FileDialog.new();dialog.file_mode=FileDialog.FILE_MODE_OPEN_FILES;dialog.access=FileDialog.ACCESS_FILESYSTEM
	dialog.filters=PackedStringArray(["*.ino,*.cpp,*.c,*.h,*.hpp,*.py ; Source files"]);add_child(dialog)
	dialog.files_selected.connect(func(paths):
		for path in paths:
			var name: String=str(path).get_file()
			if not source_name_ok(name) or editors.has(name) or editors.size()>=16:status.text="Source import skipped a duplicate or invalid filename.";continue
			var file := FileAccess.open(str(path),FileAccess.READ)
			if file==null:continue
			if file.get_length()>65536:file.close();status.text="Source file exceeds 64 KiB.";continue
			add_source(name,file.get_as_text());file.close();autosave_left=1.0
		dialog.queue_free())
	dialog.canceled.connect(dialog.queue_free);dialog.popup_centered_ratio(.7)

func remove_active_source() -> void:
	var active := active_editor()
	if active==null or editors.size()<=1:status.text="Keep at least one source file.";return
	for name in editors.keys():
		if editors[name]==active:editors.erase(name);break
	source_tabs.remove_child(active);active.queue_free();autosave_left=1.0

func _process(delta: float) -> void:
	if autosave_left<0:return
	autosave_left-=delta
	if autosave_left<=0:
		autosave_left=-1
		var files := source_files()
		if preload("res://scripts/inventory_authority/firmware_schema.gd").files(files,false):draft_requested.emit(files)
