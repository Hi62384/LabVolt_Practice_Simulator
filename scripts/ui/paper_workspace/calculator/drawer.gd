extends Control
## Full-viewport overlay. Adopt one existing scientific_calculator instance via configure().
signal revealed_changed(open: bool)
signal locked_changed(locked: bool)

const UI = preload("res://scripts/ui/design_system/widgets.gd")
const PEEK := 36.0
const EDGE_MARGIN := 20.0
const TOP_MARGIN := 18.0
const BOTTOM_MARGIN := 18.0
const SPEED := 1200.0
const CLOSE_DELAY := 0.16

var calculator: Control
var anchor_y := 88.0
var reduced_motion := false
var locked := false
var revealed := false
var _keyboard_open := false
var _keyboard_suppressed := false
var _leave_elapsed := 0.0
var _returning_to_dock := false
var _occlusion_rect := Rect2()
var _bridge_active := false
var _dragging := false
var _drag_offset := Vector2.ZERO
var _drag_position := Vector2.ZERO
var _current_position := Vector2.INF
var _shell: PanelContainer
var _lock_button: Button
var _handle: Control

func configure(value: Control) -> void:
	if calculator == value:
		return
	if is_instance_valid(calculator) and is_instance_valid(_shell):
		_shell.remove_child(calculator)
	calculator = value
	if is_node_ready():
		_mount_calculator()

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# The full-screen overlay must never become the GUI hit target over paper.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = false
	_shell = PanelContainer.new()
	_shell.name = "CalculatorDrawer"
	_shell.mouse_filter = Control.MOUSE_FILTER_STOP
	_shell.add_theme_stylebox_override("panel", _shell_style())
	add_child(_shell)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 0)
	_shell.add_child(body)
	_handle = HBoxContainer.new()
	_handle.custom_minimum_size.y = 32
	_handle.mouse_filter = Control.MOUSE_FILTER_STOP
	_handle.gui_input.connect(_handle_input)
	body.add_child(_handle)
	var grip := Label.new()
	grip.text = "Calculator"
	grip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grip.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	grip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_handle.add_child(grip)
	_lock_button = UI.action("", "lock", _toggle_lock)
	_lock_button.custom_minimum_size = Vector2(36, 36)
	_lock_button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_lock_button.accessibility_name = "Pin calculator"
	_lock_button.tooltip_text = "Pin calculator and enable dragging (Ctrl+Shift+L)"
	_handle.add_child(_lock_button)
	_lock_button.modulate.a = 0.0
	_lock_button.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mount_calculator(body)
	resized.connect(_on_resized)
	_update_position(0.0)

func _shell_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color.TRANSPARENT
	style.set_content_margin_all(0)
	return style

func _mount_calculator(body: VBoxContainer = null) -> void:
	if not is_instance_valid(calculator) or not is_instance_valid(_shell):
		return
	if body == null:
		body = _shell.get_child(0) as VBoxContainer
	if calculator.get_parent() != null:
		calculator.get_parent().remove_child(calculator)
	body.add_child(calculator)
	calculator.visible = true
	calculator.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_style_physical_calculator()
	call_deferred("_on_resized")

func _style_physical_calculator() -> void:
	# Visual overrides only: the original calculator owns every key callback,
	# display, memory, angle mode, and expression implementation.
	calculator.rotation = 0.0
	calculator.custom_minimum_size.x = 350
	calculator.add_theme_stylebox_override("panel", _bezel_style())
	var body := calculator.get_child(0) as VBoxContainer
	if body == null:
		return
	var lcd := body.get_child(1) as PanelContainer
	if lcd != null:
		var glass := StyleBoxFlat.new()
		glass.bg_color = Color("b7c8b3")
		glass.border_color = Color("718b83")
		glass.set_border_width_all(2)
		glass.set_corner_radius_all(5)
		glass.set_content_margin_all(10)
		lcd.add_theme_stylebox_override("panel", glass)
	var grid := body.get_child(body.get_child_count() - 1) as GridContainer
	if grid == null:
		return
	for child in grid.get_children():
		if child is Button:
			var key := child as Button
			key.custom_minimum_size = Vector2(54, 42)
			key.add_theme_stylebox_override("normal", _key_style(key.text))
			var hover_style := _key_style(key.text)
			hover_style.bg_color = hover_style.bg_color.lightened(0.13)
			key.add_theme_stylebox_override("hover", hover_style)
			key.add_theme_stylebox_override("pressed", hover_style)

func _bezel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color("343d4c")
	style.border_color = Color("8b9caa")
	style.set_border_width_all(2)
	style.set_corner_radius_all(17)
	style.set_content_margin_all(13)
	style.shadow_color = Color(0, 0, 0, 0.36)
	style.shadow_size = 9
	style.shadow_offset = Vector2(-3, 6)
	return style

func _key_style(label: String) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color("758494") if label.is_valid_int() or label == "." else Color("4c5b6b")
	if label == "=": style.bg_color = Color("408873")
	if label in ["AC", "DEL"]: style.bg_color = Color("a2605d")
	style.border_color = style.bg_color.darkened(0.32)
	style.border_width_bottom = 3
	style.set_corner_radius_all(6)
	style.set_content_margin_all(3)
	return style

func _process(delta: float) -> void:
	if not is_instance_valid(_shell) or not is_visible_in_tree():
		return
	rotation = 0.0
	_shell.rotation = 0.0
	if is_instance_valid(calculator): calculator.rotation = 0.0
	if _dragging and not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_dragging = false
	if _dragging:
		_drag_position = clamp_position(get_local_mouse_position() - _drag_offset, size, _drawer_size())
	elif not locked and not _returning_to_dock:
		var pointer := get_local_mouse_position()
		# Use the settled open rect; following the moving shell causes hover
		# to alternate open/stowed while it slides under a stationary pointer.
		var inside_body := _inside_open_target(pointer)
		if inside_body: _bridge_active = false
		var hover := _inside_peek(pointer) or (revealed and inside_body) or (_bridge_active and _inside_bridge(pointer))
		if _keyboard_suppressed and not hover:
			_keyboard_suppressed = false
		if hover or _keyboard_open:
			_leave_elapsed = 0.0
			_set_revealed(_keyboard_open or not _keyboard_suppressed)
		else:
			_leave_elapsed += delta
			if _leave_elapsed >= CLOSE_DELAY: _set_revealed(false)
	_update_position(delta)
	if _returning_to_dock and _current_position.distance_to(anchor_position(size, _drawer_size(), anchor_y, false)) < 0.5:
		_returning_to_dock = false

func _update_position(delta: float) -> void:
	if not is_instance_valid(_shell):
		return
	var target := _drag_position if locked else _dock_position(revealed and not _returning_to_dock)
	if _current_position == Vector2.INF or reduced_motion or delta <= 0.0:
		_current_position = target
	else:
		_current_position = _current_position.move_toward(target, SPEED * delta)
	_shell.position = _current_position
	_shell.size = _shell_size()
	_shell.scale = Vector2.ONE * _drawer_scale()

func _shell_size() -> Vector2:
	var measured := _shell.get_combined_minimum_size() if is_instance_valid(_shell) else Vector2(300, 440)
	return Vector2(maxf(300.0, measured.x), maxf(440.0, measured.y))

func _drawer_scale() -> float:
	return clampf((size.y - anchor_y - BOTTOM_MARGIN) / _shell_size().y, .50, 1.0)

func _drawer_size() -> Vector2:
	return _shell_size() * _drawer_scale()

func _inside_open_target(point: Vector2) -> bool:
	return Rect2(_dock_position(true), _drawer_size()).has_point(point)

func _inside_bridge(point: Vector2) -> bool:
	var body := Rect2(_dock_position(true), _drawer_size())
	return Rect2(Vector2(body.end.x, body.position.y), Vector2(maxf(0.0, size.x - body.end.x), body.size.y)).has_point(point)

func _dock_position(open: bool) -> Vector2:
	var candidate := anchor_position(size, _drawer_size(), anchor_y, open)
	if open and _occlusion_rect.has_area() and Rect2(candidate, _drawer_size()).intersects(_occlusion_rect):
		var below_case := _occlusion_rect.end.y + 10.0
		if below_case + _drawer_size().y + BOTTOM_MARGIN <= size.y:
			candidate.y = below_case
		else:
			candidate.x = maxf(EDGE_MARGIN, _occlusion_rect.position.x - _drawer_size().x - 12.0)
	return candidate

func set_occlusion_rect(rect: Rect2) -> void:
	_occlusion_rect = rect

func measured_rect() -> Rect2:
	return Rect2(_current_position, _drawer_size())

func dock_rect(open: bool = false) -> Rect2:
	return Rect2(_dock_position(open), _drawer_size())

func _inside_peek(point: Vector2) -> bool:
	var stowed := anchor_position(size, _drawer_size(), anchor_y, false)
	return Rect2(Vector2(maxf(0.0, size.x - PEEK - 8.0), stowed.y), Vector2(PEEK + 8.0, _drawer_size().y)).has_point(point)

func _set_revealed(value: bool) -> void:
	if revealed == value:
		return
	revealed = value
	_bridge_active = value
	if is_instance_valid(_lock_button):
		_lock_button.modulate.a = 1.0 if value else 0.0
		_lock_button.mouse_filter = Control.MOUSE_FILTER_STOP if value else Control.MOUSE_FILTER_IGNORE
	revealed_changed.emit(value)

func _toggle_lock() -> void:
	set_locked(not locked)

func set_locked(value: bool) -> void:
	if locked == value:
		return
	locked = value
	_dragging = false
	if locked:
		_drag_position = clamp_position(_shell.position, size, _drawer_size())
		_set_revealed(true)
		_returning_to_dock = false
	else:
		_keyboard_open = false
		_keyboard_suppressed = true
		_set_revealed(false)
		_returning_to_dock = true
	_lock_button.accessibility_name = "Unpin calculator" if locked else "Pin calculator"
	_lock_button.tooltip_text = "Unpin and return to right edge" if locked else "Pin calculator and enable dragging (Ctrl+Shift+L)"
	locked_changed.emit(locked)

func _handle_input(event: InputEvent) -> void:
	if not locked:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_dragging = true
			_drag_offset = get_local_mouse_position() - _shell.position
		else:
			_dragging = false
		accept_event()

func _input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		_dragging = false
	if event is InputEventKey and event.pressed and not event.echo and event.ctrl_pressed and event.shift_pressed:
		if event.keycode == KEY_C:
			_keyboard_open = not _keyboard_open
			_keyboard_suppressed = not _keyboard_open
			if not locked:
				_set_revealed(_keyboard_open)
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_L:
			set_locked(not locked)
			get_viewport().set_input_as_handled()

func _on_resized() -> void:
	if locked:
		_drag_position = clamp_position(_drag_position, size, _drawer_size())
	else:
		_current_position = clamp_position(_current_position, size, _drawer_size()) if _current_position != Vector2.INF and revealed else _current_position
	_update_position(0.0)

func close() -> void:
	_dragging = false
	_keyboard_open = false
	_keyboard_suppressed = false
	set_locked(false)
	_set_revealed(false)
	visible = false

func open() -> void:
	visible = true

func snapshot_state() -> Dictionary:
	return {"locked": locked, "revealed": revealed, "keyboard_open": _keyboard_open, "drag_position": _drag_position, "anchor_y": anchor_y}

func restore_state(state: Dictionary) -> void:
	anchor_y = float(state.get("anchor_y", anchor_y))
	_keyboard_open = bool(state.get("keyboard_open", false))
	_keyboard_suppressed = false
	locked = bool(state.get("locked", false))
	_dragging = false
	_drag_position = clamp_position(state.get("drag_position", anchor_position(size, _drawer_size(), anchor_y, true)), size, _drawer_size())
	_set_revealed(locked or bool(state.get("revealed", false)))
	if is_instance_valid(_lock_button):
		_lock_button.accessibility_name = "Unpin calculator" if locked else "Pin calculator"
		_lock_button.tooltip_text = "Unpin and return to right edge" if locked else "Pin calculator and enable dragging (Ctrl+Shift+L)"
	_update_position(0.0)

static func anchor_position(viewport_size: Vector2, drawer_size: Vector2, vertical_anchor: float, open: bool) -> Vector2:
	var x := viewport_size.x - drawer_size.x - EDGE_MARGIN if open else viewport_size.x - PEEK
	var y := clampf(vertical_anchor, TOP_MARGIN, maxf(TOP_MARGIN, viewport_size.y - drawer_size.y - BOTTOM_MARGIN))
	return Vector2(x, y)

static func clamp_position(candidate: Vector2, viewport_size: Vector2, drawer_size: Vector2) -> Vector2:
	return Vector2(clampf(candidate.x, EDGE_MARGIN, maxf(EDGE_MARGIN, viewport_size.x - drawer_size.x - EDGE_MARGIN)), clampf(candidate.y, TOP_MARGIN, maxf(TOP_MARGIN, viewport_size.y - drawer_size.y - BOTTOM_MARGIN)))
