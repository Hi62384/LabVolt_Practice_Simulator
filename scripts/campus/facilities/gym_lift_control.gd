extends PanelContainer
## Minimal in-world rep HUD. Facility authority validates each phase and rep.
signal lower_requested
signal rep_requested
signal failed
signal finish_requested

var phase := 0
var reps := 0
var progress := 1.0
var click_gain := .10
var drain_rate := .035
var movement: ProgressBar
var instruction: Label
var rep_label: Label

func configure(capacity: float, load: float, active_phase: int, completed_reps: int) -> void:
	phase=active_phase;reps=completed_reps
	var ratio:=maxf(0.0,load/maxf(capacity,.01))
	click_gain=clampf(.16*(1.0-.82*clampf(ratio,0.0,1.0)),.028,.16)
	if ratio>1.0:click_gain=.022
	progress=.36 if phase==1 else 1.0
	custom_minimum_size=Vector2(410,112)
	var row:=HBoxContainer.new();row.add_theme_constant_override("separation",14);add_child(row)
	movement=ProgressBar.new();movement.min_value=0;movement.max_value=1;movement.value=progress;movement.show_percentage=false
	movement.fill_mode=ProgressBar.FILL_BOTTOM_TO_TOP;movement.custom_minimum_size=Vector2(32,82);movement.size_flags_vertical=Control.SIZE_SHRINK_CENTER
	movement.accessibility_name="Rep progress, from bottom failure to top completion";row.add_child(movement)
	var copy:=VBoxContainer.new();copy.size_flags_horizontal=Control.SIZE_EXPAND_FILL;row.add_child(copy)
	instruction=Label.new();instruction.add_theme_font_size_override("font_size",19);copy.add_child(instruction)
	rep_label=Label.new();rep_label.add_theme_font_size_override("font_size",15);copy.add_child(rep_label)
	var key_hint:=Label.new();key_hint.text="While waiting: X ends the set";key_hint.add_theme_font_size_override("font_size",13);copy.add_child(key_hint)
	_refresh_text()
	set_process(phase==1)

func _refresh_text() -> void:
	if not is_instance_valid(instruction):return
	instruction.text="Click to lower" if phase==0 else "Press E repeatedly to raise"
	rep_label.text="%d reps  ·  Keep the bar above the bottom" % reps if phase==1 else "%d reps completed" % reps

func handle_input(event: InputEvent) -> bool:
	if event is InputEventMouseButton and event.pressed and event.button_index==MOUSE_BUTTON_LEFT and phase==0:
		phase=1;progress=.36;movement.value=progress;lower_requested.emit();_refresh_text();set_process(true);return true
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode==KEY_X and phase==0:
			finish_requested.emit();return true
		if event.keycode==KEY_E and phase==1:
			progress=minf(1.0,progress+click_gain);movement.value=progress
			if progress>=1.0:
				phase=0;reps+=1;rep_requested.emit();_refresh_text();set_process(false)
			else:_refresh_text()
			return true
	return false

func _process(delta: float) -> void:
	if phase!=1:return
	progress=maxf(0.0,progress-delta*drain_rate);movement.value=progress
	if progress<=0.0:
		phase=0;set_process(false);failed.emit();return
