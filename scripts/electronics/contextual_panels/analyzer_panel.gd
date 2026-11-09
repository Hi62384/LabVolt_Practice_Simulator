extends PanelContainer
signal tool_changed(tool: String)
signal dismissed
const UI = preload("res://scripts/ui/design_system/widgets.gd")
var canvas: Control
var allowed := false
var basic: VBoxContainer
var advanced: VBoxContainer
var reading: Label

func _ready() -> void:
	custom_minimum_size.x=275
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	var root := VBoxContainer.new()
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(root)
	root.add_child(UI.header("Analyzer","Measured solver data only",_dismiss))
	basic=VBoxContainer.new();root.add_child(basic)
	for item in [["Positive probe","probe+"],["Negative probe","probe-"]]:
		basic.add_child(UI.action(item[0],"meter",func():tool_changed.emit(item[1])))
	_add_toggle(basic,"Node voltage colors",true,func(on):canvas.voltage_overlay=on;canvas.queue_redraw())
	_add_toggle(basic,"Current arrows",true,func(on):canvas.current_overlay=on;canvas.queue_redraw())
	reading=UI.text("Select two probe holes for a measured reading.","MutedLabel");basic.add_child(reading)
	var reveal := UI.action("Advanced","settings",func():advanced.visible=not advanced.visible);root.add_child(reveal)
	advanced=VBoxContainer.new();advanced.hide();root.add_child(advanced)
	_add_toggle(advanced,"Voltage / timing trace",false,func(on):canvas.timing_visible=on;canvas.queue_redraw())
	_add_toggle(advanced,"Hold capture",false,func(on):canvas.capture.held=on)
	advanced.add_child(UI.action("Clear capture","trash",func():canvas.capture.samples.clear();canvas.queue_redraw()))
	var threshold := SpinBox.new();threshold.min_value=-1000;threshold.max_value=1000;threshold.step=0.1;threshold.value=2.5;threshold.prefix="Logic threshold V ";advanced.add_child(threshold)
	threshold.value_changed.connect(func(value):canvas.capture.threshold=value;canvas.queue_redraw())
	advanced.add_child(UI.text("Trace uses solver timestamps. Fast signals can alias; HIGH/LOW compares voltage only, and drive impedance needs backend data.","MutedLabel"))
	hide()

func _add_toggle(parent: Node,title: String,initial: bool,callback: Callable) -> void:
	var toggle := CheckButton.new();toggle.text=title;toggle.button_pressed=initial;parent.add_child(toggle);toggle.toggled.connect(callback)

func bind_canvas(source: Control, enabled: bool) -> void:
	canvas=source;allowed=enabled
	if not enabled:close_panel()

func open_panel() -> void:
	if not allowed or not is_instance_valid(canvas):return
	canvas.analyzer_enabled=true;canvas.queue_redraw();show();refresh_reading()

func refresh_reading() -> void:
	if not visible or not is_instance_valid(canvas):return
	reading.text=canvas.inspection_text() if canvas.has_method("inspection_text") else "No measured result available."

func _dismiss() -> void:
	close_panel()
	dismissed.emit()

func close_panel() -> void:
	if is_instance_valid(canvas):canvas.analyzer_enabled=false;canvas.queue_redraw()
	hide()
