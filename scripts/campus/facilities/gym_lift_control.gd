extends PanelContainer
## Minimal in-world rep HUD. Facility authority validates each phase and rep.
signal lower_requested
signal rep_requested
signal failed
signal finish_requested
signal motion_changed(progress: float)
signal effort_requested
var live := false
var displayed_target := 0.0
var last_effort := -1000
var strength_ratio := 0.0
var fill_style: StyleBoxFlat

var phase := 0
var reps := 0
var progress := 1.0
var click_gain := .10
var drain_rate := .035
var movement: ProgressBar
var instruction: Label
var rep_label: Label

func configure(capacity: float, load: float, active_phase: int, completed_reps: int, live_progress := -1.0) -> void:
	phase=active_phase;reps=completed_reps
	live = live_progress >= 0.0
	var parameters := preload("res://scripts/campus/facilities/gym_progress.gd").lift_parameters(capacity, load)
	click_gain = parameters.x
	drain_rate = parameters.y
	strength_ratio = parameters.z
	_refresh_strain()
	displayed_target = live_progress
	if not live or not is_instance_valid(movement):
		progress = live_progress if live else (.36 if phase==1 else 1.0)
	if is_instance_valid(movement):
		movement.value = progress
		_refresh_text()
		set_process(live or phase==1)
		return
	custom_minimum_size=Vector2(410,112)
	var row:=HBoxContainer.new();row.add_theme_constant_override("separation",14);add_child(row)
	movement=ProgressBar.new();movement.min_value=0;movement.max_value=1;movement.value=progress;movement.show_percentage=false
	movement.fill_mode=ProgressBar.FILL_BOTTOM_TO_TOP;movement.custom_minimum_size=Vector2(32,82);movement.size_flags_vertical=Control.SIZE_SHRINK_CENTER
	movement.accessibility_name="Lift progress";row.add_child(movement)
	var track:=StyleBoxFlat.new()
	track.bg_color=Color("26373d");track.set_corner_radius_all(5)
	movement.add_theme_stylebox_override("background",track)
	fill_style=StyleBoxFlat.new();fill_style.set_corner_radius_all(5)
	movement.add_theme_stylebox_override("fill",fill_style)
	_refresh_strain()
	var copy:=VBoxContainer.new();copy.size_flags_horizontal=Control.SIZE_EXPAND_FILL;row.add_child(copy)
	instruction=Label.new();instruction.add_theme_font_size_override("font_size",19);copy.add_child(instruction)
	rep_label=Label.new();rep_label.add_theme_font_size_override("font_size",15);copy.add_child(rep_label)
	var key_hint:=Label.new();key_hint.text="Esc ends the set";key_hint.add_theme_font_size_override("font_size",13);copy.add_child(key_hint)
	_refresh_text()
	set_process(live or phase==1)

func _refresh_text() -> void:
	if not is_instance_valid(instruction):return
	instruction.text="Click to lower" if phase==0 else ("Lowering the weight" if phase==2 else "Tap E to raise")
	rep_label.text="%d reps  ·  %s strain" % [reps,"High" if strength_ratio>=1.0 else "Moderate" if strength_ratio>=.70 else "Light"]

func _refresh_strain() -> void:
	if not is_instance_valid(fill_style):return
	var strain:=clampf(strength_ratio,0.0,1.5)
	fill_style.bg_color=Color("38c8ab").lerp(Color("e3c14c"),inverse_lerp(.25,.95,minf(strain,.95))) if strain<.95 else Color("e3c14c").lerp(Color("e86a4c"),inverse_lerp(.95,1.5,strain))

func handle_input(event: InputEvent) -> bool:
	if live:
		return _handle_live_input(event)
	if event is InputEventMouseButton and event.pressed and event.button_index==MOUSE_BUTTON_LEFT and phase==0:
		phase=1;progress=.36;movement.value=progress;lower_requested.emit();_refresh_text();set_process(true);return true
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode==KEY_X and phase==0:
			finish_requested.emit();return true
		if event.keycode==KEY_E and phase==1:
			progress=minf(1.0,progress+click_gain);movement.value=progress
			motion_changed.emit(progress)
			if progress>=1.0:
				phase=0;reps+=1;rep_requested.emit();_refresh_text();set_process(false)
			else:_refresh_text();set_process(true)
			return true
	return false

func show_progress(value: float) -> void:
	displayed_target = clampf(value, 0.0, 1.0)

func _handle_live_input(event: InputEvent) -> bool:
	if event is InputEventMouseButton and event.pressed and event.button_index==MOUSE_BUTTON_LEFT:
		if phase == 0:lower_requested.emit()
		return true
	if event is InputEventKey and event.pressed and event.keycode == KEY_E:
		if phase == 1 and not event.echo and Time.get_ticks_msec()-last_effort >= 95:
			last_effort = Time.get_ticks_msec()
			effort_requested.emit()
		return true
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_X:
		finish_requested.emit()
		return true
	return false

func _process(delta: float) -> void:
	if live:
		progress = move_toward(progress, displayed_target, delta*3.8)
		movement.value = progress
		return
	if phase!=1:return
	progress=maxf(0.0,progress-delta*drain_rate);movement.value=progress
	motion_changed.emit(progress)
	if progress<=0.0:
		# The bottom is a stable resting position for another attempt.
		set_process(false)
