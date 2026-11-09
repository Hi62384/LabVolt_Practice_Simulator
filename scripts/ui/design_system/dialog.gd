extends Control
## Local modal chrome. Callers retain transaction, input-capture and session authority.
signal dismissed
const UI = preload("res://scripts/ui/design_system/widgets.gd")
const UISkin = preload("res://scripts/ui/design_system/theme.gd")
var body: VBoxContainer
var actions: HFlowContainer
var _panel: PanelContainer
var _title: Label
var _subtitle: Label
var _previous_focus: WeakRef

func _ready() -> void:
	_ensure_built()
	resized.connect(_layout)
	_layout()
	hide()

func _ensure_built() -> void:
	if is_instance_valid(_panel): return
	theme = UISkin.create()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var shade := ColorRect.new()
	shade.color = Color(0.015, 0.03, 0.05, 0.82)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(shade)
	_panel = PanelContainer.new()
	add_child(_panel)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_panel.add_child(scroll)
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(column)
	var row := HBoxContainer.new()
	column.add_child(row)
	_title = UI.text("", "TitleLabel")
	row.add_child(_title)
	row.add_child(UI.action("Close", "close", dismiss))
	_subtitle = UI.text("", "MutedLabel")
	column.add_child(_subtitle)
	body = VBoxContainer.new()
	body.name = "Body"
	column.add_child(body)
	actions = HFlowContainer.new()
	actions.name = "Actions"
	column.add_child(actions)

func configure(title: String, subtitle: String = "") -> void:
	_ensure_built()
	_title.text = title
	_subtitle.text = subtitle
	_subtitle.visible = not subtitle.is_empty()

func _layout() -> void:
	if not is_instance_valid(_panel): return
	var inset := minf(20.0, size.x * 0.03)
	var extent := Vector2(maxf(1.0, minf(620.0, size.x - inset * 2.0)), maxf(1.0, minf(600.0, size.y - inset * 2.0)))
	_panel.size = extent
	_panel.position = (size - extent) * 0.5

func open() -> void:
	_ensure_built()
	if visible: return
	var focused := get_viewport().gui_get_focus_owner()
	_previous_focus = weakref(focused) if is_instance_valid(focused) else null
	show()
	_layout()
	var controls: Array[Control] = []
	for node in find_children("*", "Control", true, false):
		var control := node as Control
		if control != null and control.focus_mode == Control.FOCUS_ALL and control.is_visible_in_tree():
			var button := control as BaseButton
			if button != null and button.disabled: continue
			controls.append(control)
	# Keep keyboard traversal inside this modal, even with caller-added fields.
	for index in controls.size():
		controls[index].focus_next = controls[(index + 1) % controls.size()].get_path()
		controls[index].focus_previous = controls[(index - 1 + controls.size()) % controls.size()].get_path()
	if not controls.is_empty(): controls[0].grab_focus()

func dismiss() -> void:
	if not visible: return
	hide()
	if _previous_focus != null:
		var previous = _previous_focus.get_ref()
		if is_instance_valid(previous) and previous.is_visible_in_tree(): previous.grab_focus()
	dismissed.emit()

func _unhandled_key_input(event: InputEvent) -> void:
	if is_visible_in_tree() and event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		dismiss()
