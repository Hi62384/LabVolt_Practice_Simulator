extends VBoxContainer
const Chrome = preload("res://scripts/ui/circuit_editor_panels/chrome.gd")
const Runtime=preload("res://scripts/firmware_runtime.gd")
const SourceProject=preload("res://scripts/firmware_backends/source_project.gd")
var file_tabs: TabBar
var files: Dictionary={}
var active_file := "main.lvs"
var compiled_source := ""
var parameter_hint: Label
const HINTS={"mode":"mode D0|D1|PWM in|out","write":"write D0|D1|PWM number-or-variable","read":"read variable D0|D1|A0|PWM","analog":"analog variable D0|D1|A0|PWM → 0–1023","pwm":"pwm D0|D1|PWM duty (0–1)","wait":"wait milliseconds (0–3600000)","set":"set variable number-or-variable","add":"add variable number-or-variable","if":"if value ==|!=|<|>|<=|>= value goto line","goto":"goto line (local to this source file)","serial":"serial number-or-variable","halt":"halt (no arguments)"}
var ui: Node
var editor: CodeEdit
var notice: Label
var monitor: TextEdit
var device_id := ""
var previous_error := -1
var view_key := ""
var kit_id := ""
func build(studio: Node) -> void:
	Chrome.setup(self)
	ui=studio;kit_id=str(ui.profile.data.equipped);size_flags_horizontal=Control.SIZE_EXPAND_FILL
	var native_devices := preload("res://scripts/breadboard_model.gd").devices(kit().board).filter(func(entry):return entry.part.type in ["native_uno","native_pico","native_nano"])
	if not native_devices.is_empty():
		var native_panel := preload("res://scripts/firmware_backends/native_studio.gd").new();add_child(native_panel);native_panel.build(studio)
	Chrome.heading(self,"LV Micro · programming", "Write → validate → upload → run", "chip")
	ui.label(self,"LabVolt Script 1 · educational controller, not Arduino or MicroPython · power VIN and GND to run")
	var choices := HFlowContainer.new();add_child(choices)
	var picker := OptionButton.new();choices.add_child(picker)
	for device in preload("res://scripts/breadboard_model.gd").devices(kit().board):
		if device.part.type=="lv_mcu":picker.add_item("LV Micro · "+str(device.id).trim_prefix("board/"));picker.set_item_metadata(picker.item_count-1,str(device.id).trim_prefix("board/"))
	if picker.item_count==0:ui.label(self,"Add an LV Micro from Components to your kit, then place it on the breadboard.");return
	device_id=str(picker.get_item_metadata(0))
	var actions := HFlowContainer.new();add_child(actions)
	Chrome.action(actions,"Validate",validate)
	Chrome.action(actions,"Save / Upload",upload)
	Chrome.action(actions,"Run",func():set_running(true))
	Chrome.action(actions,"Stop",func():set_running(false))
	Chrome.action(actions,"Reset",func():
		if ui.bench>=0:ui.game.dc_lab.request(ui.bench,{"op":"firmware_reset","id":"board/"+device_id})
	)
	var examples := OptionButton.new();actions.add_child(examples)
	for name in ["Templates…","Blink D0","Read button → D1","PWM ramp"]:examples.add_item(name)
	var searchbar := HFlowContainer.new();add_child(searchbar)
	var find := LineEdit.new();find.placeholder_text="Find";searchbar.add_child(find)
	var replacement := LineEdit.new();replacement.placeholder_text="Replace with";searchbar.add_child(replacement)
	Chrome.action(searchbar,"Find next",func():
		if find.text=="":return
		var hit := editor.search(find.text,0,editor.get_caret_line(),editor.get_caret_column()+1)
		if hit.x>=0:editor.select(hit.y,hit.x,hit.y,hit.x+find.text.length());editor.set_caret_line(hit.y);editor.set_caret_column(hit.x)
	)
	Chrome.action(searchbar,"Replace all",func():
		if find.text!="":editor.text=editor.text.replace(find.text,replacement.text)
	)
	var file_actions := HFlowContainer.new();add_child(file_actions)
	var file_name := LineEdit.new();file_name.placeholder_text="library.lvs";file_name.custom_minimum_size.x=200;file_actions.add_child(file_name)
	Chrome.action(file_actions,"Add file",func():
		capture_file()
		if not SourceProject.filename_ok(file_name.text) or files.has(file_name.text) or files.size()>=16:notice.text="Choose a unique simple .lvs filename (up to 16 files).";return
		files[file_name.text]="";active_file=file_name.text;refresh_tabs();editor.text=""
	)
	Chrome.action(file_actions,"Find references",func():
		capture_file();var word: String=word_at_caret();var hits: Array=[]
		if word.is_empty():return
		for name in files:
			var lines := str(files[name]).split("\n")
			for i in lines.size():
				if word in lines[i]:hits.append("%s:%d  %s"%[name,i+1,lines[i]])
		monitor.text="References to "+word+"\n"+"\n".join(hits)
		view_key="references"
	)
	Chrome.action(file_actions,"Serial monitor",func():view_key="")
	file_tabs=TabBar.new();add_child(file_tabs)
	file_tabs.tab_changed.connect(func(index):
		if index<0:return
		capture_file();active_file=file_tabs.get_tab_title(index);editor.text=str(files.get(active_file,""));previous_error=-1
	)
	editor=CodeEdit.new();editor.custom_minimum_size=Vector2(280,360);editor.size_flags_horizontal=Control.SIZE_EXPAND_FILL;editor.gutters_draw_line_numbers=true;editor.gutters_draw_fold_gutter=true;editor.line_folding=true;editor.indent_automatic=true;editor.auto_brace_completion_enabled=true;editor.code_completion_enabled=true;editor.add_comment_delimiter("#", "",true);add_child(editor)
	var colors := CodeHighlighter.new();colors.number_color=Color("e6b677");colors.symbol_color=Color("8ccef0")
	for word in Runtime.APIS:colors.add_keyword_color(word,Color("80ddbd"))
	for word in ["D0","D1","A0","PWM","in","out"]:colors.add_keyword_color(word,Color("e8cb92"))
	colors.add_color_region("#","",Color("81969d"),true);editor.syntax_highlighter=colors
	editor.code_completion_requested.connect(func():
		var prefix := editor.get_line(editor.get_caret_line()).left(editor.get_caret_column())
		var tokens := prefix.strip_edges().split(" ",false);var options: Array=Runtime.APIS.duplicate()
		if tokens.size()>=1 and (tokens.size()>1 or prefix.ends_with(" ")):
			var argument := tokens.size()-1 if not prefix.ends_with(" ") else tokens.size()
			if tokens[0]=="mode":options=["D0","D1","PWM"] if argument==1 else ["in","out"]
			elif tokens[0] in ["write","pwm"] and argument==1:options=["D0","D1","PWM"]
			elif tokens[0] in ["read","analog"] and argument==2:options=Runtime.PINS.keys()
			elif tokens[0]=="#include":options=files.keys().map(func(name):return '"'+str(name)+'"')
		for word in options:editor.add_code_completion_option(CodeEdit.KIND_FUNCTION,str(word),str(word))
		editor.update_code_completion_options(true)
	)
	parameter_hint=ui.label(self,"")
	editor.caret_changed.connect(func():
		var tokens := editor.get_line(editor.get_caret_line()).strip_edges().split(" ",false)
		parameter_hint.text=str(HINTS.get(tokens[0],"")) if not tokens.is_empty() else ""
	)
	notice=ui.label(self,"");monitor=TextEdit.new();monitor.editable=false;monitor.custom_minimum_size.y=100;add_child(monitor)
	var guide := CheckButton.new();guide.text="Language and wiring reference";add_child(guide)
	var reference: Label = ui.label(self,"One instruction per line; # starts a comment. 64 instructions/step, 32 variables, 256 expanded lines, 8 KB/project.\nmain.lvs is the entry; #include \"library.lvs\" inserts a project file. Numeric jumps stay local to each file.\nmode D0 out | write D0 1 | wait 500 | goto 2 | read button D1 | analog value A0\nset x 0 | add x 1 | if x >= 10 goto 2 | pwm PWM 0.5 | serial x | halt\nDigital reads use 60% of VIN; ADC returns 0–1023. PWM is 50 Hz. Connect a resistor in series with each LED.")
	reference.visible=false;guide.toggled.connect(func(on):reference.visible=on)
	picker.item_selected.connect(func(index):remember();device_id=str(picker.get_item_metadata(index));load_source())
	examples.item_selected.connect(func(index):
		if index==1:editor.text=Runtime.TEMPLATE
		elif index==2:editor.text="mode D1 out\nread button D0\nwrite D1 button\nwait 5\ngoto 2"
		elif index==3:editor.text="mode PWM out\nset level 0\npwm PWM level\nwait 100\nadd level 0.1\nif level <= 1 goto 3\ngoto 2"
	)
	Chrome.labeled(picker,"Target LV Micro")
	Chrome.labeled(examples,"Insert template")
	Chrome.labeled(find,"Find in active file")
	Chrome.labeled(replacement,"Replacement text")
	Chrome.labeled(file_name,"New project filename")
	Chrome.section(self,"Device and deployment", "chip", choices, actions)
	Chrome.section(self,"Search and project files", "search", searchbar, file_actions)
	Chrome.section(self,"Source editor", "circuit", file_tabs, parameter_hint)
	Chrome.section(self,"Validation and serial output", "info", notice, monitor)
	Chrome.finish(self)
	load_source()
func kit() -> Dictionary:return ui.profile.data.kits[kit_id]
func part() -> Dictionary:
	if "/" in device_id:
		if not kit().board.has("programs"):kit().board.programs={}
		var key := "board/"+device_id
		if not kit().board.programs.has(key):
			for device in preload("res://scripts/breadboard_model.gd").devices(kit().board):
				if device.id==key:
					kit().board.programs[key]={"firmware":device.part.get("firmware",Runtime.TEMPLATE),"run":device.part.get("run",true)}
					if device.part.get("code_files") is Dictionary:kit().board.programs[key].code_files=device.part.code_files.duplicate(true)
		return kit().board.programs.get(key,{})
	for item in kit().board.parts:
		if str(item.id)==device_id:return item
	return {}
func remember() -> void:
	if not is_instance_valid(editor) or device_id=="":return
	capture_file()
	var item := part();item.code_files=files.duplicate(true);item.draft=str(files.get("main.lvs",""));item.code_scroll=editor.scroll_vertical;item.code_line=editor.get_caret_line();item.code_column=editor.get_caret_column();ui.profile.save()
func load_source() -> void:
	var item := part();var stored=item.get("code_files",{})
	files={}
	if stored is Dictionary and stored.size()<=16:
		for name in stored:
			if SourceProject.filename_ok(str(name)) and stored[name] is String:files[name]=stored[name].left(8192)
	if not files.has("main.lvs"):files["main.lvs"]=str(item.get("draft",item.get("firmware",Runtime.TEMPLATE)))
	active_file="main.lvs";refresh_tabs();editor.text=str(files[active_file]);editor.scroll_vertical=float(item.get("code_scroll",0));editor.set_caret_line(int(item.get("code_line",0)));editor.set_caret_column(int(item.get("code_column",0)));notice.text="Draft loaded. Upload applies it to the device.";previous_error=-1
func capture_file() -> void:
	if is_instance_valid(editor) and not files.is_empty():files[active_file]=editor.text.left(8192)
func word_at_caret() -> String:
	if editor.has_selection():return editor.get_selected_text()
	var line := editor.get_line(editor.get_caret_line())
	var left := editor.get_caret_column();var right := left
	var characters := "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_"
	while left>0 and line[left-1] in characters:left-=1
	while right<line.length() and line[right] in characters:right+=1
	return line.substr(left,right-left)
func refresh_tabs() -> void:
	file_tabs.set_block_signals(true);file_tabs.clear_tabs()
	for name in files:
		file_tabs.add_tab(name)
		if name==active_file:file_tabs.current_tab=file_tabs.tab_count-1
	file_tabs.set_block_signals(false)
func validate() -> bool:
	if previous_error>=0 and previous_error<editor.get_line_count():editor.set_line_background_color(previous_error,Color.TRANSPARENT)
	capture_file()
	var checked := SourceProject.build(files)
	if not checked.ok:
		if files.has(checked.file):active_file=checked.file;refresh_tabs();editor.text=str(files[active_file])
		previous_error=int(checked.line)-1
		if previous_error<editor.get_line_count():editor.set_line_background_color(previous_error,Color("663333"))
		notice.text="%s:%d: %s"%[checked.file,checked.line,checked.error];return false
	compiled_source=checked.source;notice.text="Valid LabVolt Script project";return true
func upload() -> void:
	if not validate():return
	var item := part();item.firmware=compiled_source;item.draft=str(files["main.lvs"]);item.code_files=files.duplicate(true)
	if ui.profile.save()!=OK:notice.text="Could not save firmware";return
	if ui.bench>=0 and ui.game.dc_lab.states[ui.bench].get("board_owner",0)==multiplayer.get_unique_id():ui.deploy()
	notice.text="Saved. Deployed devices receive the program; stowed devices run it when powered."
func set_running(running: bool) -> void:
	part().run=running;ui.profile.save()
	if ui.bench>=0:
		ui.deploy()
		if running:ui.game.dc_lab.request(ui.bench,{"op":"firmware_reset","id":"board/"+device_id})
func _process(_delta: float) -> void:
	if not is_instance_valid(monitor) or ui.bench<0 or view_key=="references":return
	var live: Dictionary=ui.game.dc_lab.states[ui.bench].get("firmware",{}).get("board/"+device_id,{})
	var text := "Device: "+str(live.get("status","Not deployed"))+" · line "+str(live.get("line",1))+"\nVariables: "+JSON.stringify(live.get("variables",{}))+"\n"+"\n".join(live.get("serial",[]))
	if monitor.text!=text:monitor.text=text
func _exit_tree() -> void:remember()
