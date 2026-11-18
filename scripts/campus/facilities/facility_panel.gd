extends PanelContainer
const UI = preload("res://scripts/ui/design_system/widgets.gd")
const HudTheme = preload("res://scripts/ui/design_system/theme.gd")
const Tokens = preload("res://scripts/ui/design_system/tokens.gd")
const Rules = preload("res://scripts/campus/facilities/facility_host.gd")
signal direct_error(message: String)
signal sandwich_builder_requested(station: String)
## The world interaction supplies the selected cashier or exercise station.
var controller: Node
var placement_key_name := Callable()
var state:={}
var station_id:=""
var station_kind:=""
var body:=VBoxContainer.new()
var status: Label
var pending:=false
var service_actions: Array[Button]=[]
var last_error:=""
var cafe_category := ""
var cafe_selection := ""
var subway_category := "Subs"
var direct := {}
var direct_in_flight := false
var has_order_space := Callable()
var orders_changed := Callable()
var dumbbell_mass := Callable()
var barbell_mass := Callable()
var cable_resistance := Callable()
var cable_extra_mass := Callable()
var capture_game := Callable()
var preview_workout := Callable()
var rep_control: Control
var regular_position := Vector2(60,60)
var regular_minimum := Vector2(300,240)
var showing_gym_progress := false
var close: Button
var menu_layout := VBoxContainer.new()
var trap_content: VBoxContainer
var trap_meter: ProgressBar
var trap_instruction: Label
var workout_exit_pending := false
var workout_identity := ""
var workout_phase := -1
var last_motion_ms := -1000

static func exercise_name(id: String) -> String:
	return str({"pushup":"Push-up","pike_pushup":"Pike push-up","pullup":"Pull-up","benchpress":"Bench press","curl":"Biceps curl","dip":"Dip"}.get(id,id.replace("_"," ").capitalize()))

func _ready() -> void:
	theme=HudTheme.create()
	custom_minimum_size=Vector2(300,240)
	size=Vector2(minf(600,get_viewport_rect().size.x-32),minf(620,get_viewport_rect().size.y-32))
	add_theme_stylebox_override("panel",HudTheme.card_style())
	add_child(menu_layout)
	get_viewport().size_changed.connect(_position_panel)
	close = UI.action("Close", "close", close_or_end_workout)
	menu_layout.add_child(close)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus=true
	menu_layout.add_child(scroll)
	body.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	scroll.add_child(body)
	body.add_theme_constant_override("separation",12)

func bind(value: Node) -> void:
	controller=value
	controller.owner_result.connect(receive)
	if controller.has_signal("room_event"):
		controller.room_event.connect(func(peer: int, event: Dictionary):
			if peer == multiplayer.get_unique_id() and event.has("lift_progress") and is_instance_valid(rep_control):
				rep_control.show_progress(float(event.lift_progress)))

func close_or_end_workout() -> void:
	var active: Dictionary = state.get("active", {})
	match active.get("type", ""):
		"trapped":
			show()
		"exercise_exit":
			return
		"exercise":
			workout_exit_pending = true
			if not pending and not direct_in_flight and direct.is_empty():
				_end_workout(active)
		_:
			if pending:
				workout_exit_pending = true
			else:
				hide()

func _end_workout(active: Dictionary) -> void:
	if active.get("quit_after_lower",false):return
	var resting := int(active.get("phase", 0)) == 0
	if active.has("lift_settings"):
		resting = int(active.phase) == 1 and float(active.lift_progress) == 0.0
	var op := "finish" if int(active.get("reps", 0)) > 0 and resting else "cancel"
	request_direct({"op":op})

func open_for(id: String,kind: String) -> void:
	cafe_category="";cafe_selection=""
	station_id=id;station_kind=kind;visible=true
	position=regular_position;custom_minimum_size=regular_minimum
	showing_gym_progress=false
	last_error=""
	redraw()
	controller.refresh()

func receive(result: Dictionary) -> void:
	var was_active: bool = state.get("active", {}).get("type") in ["exercise", "exercise_exit", "trapped"]
	pending=false
	if result.has("lift") and state.get("active", {}).get("type") == "exercise":
		state.active.merge(result.lift, true)
	if result.has("state"):
		state=result.state
		if orders_changed.is_valid():orders_changed.call()
	if direct_in_flight:
		direct_in_flight=false
		if not result.get("ok",false):direct_error.emit(str(result.get("error","Unavailable")))
	elif not direct.is_empty():
		var request := direct
		direct={}
		if state.has("profile"):
			direct_in_flight=true
			_send(request)
		else:direct_error.emit("Campus service unavailable")
		return
	if not result.get("ok",false):last_error=str(result.get("error","Unavailable"))
	elif result.get("spot_saved",false):last_error="Your spotter helped return the bar safely. Rest before another set."
	elif result.get("muscular_failure",false):last_error="Muscular failure: your muscles could not complete that repetition. Rest before your next set."
	if was_active and (state.get("active", {}).is_empty() or state.active.get("type")=="exercise_exit"):
		hide()
	if workout_exit_pending:
		var active: Dictionary = state.get("active", {})
		workout_exit_pending = false
		if active.get("type", "") == "exercise" and result.get("ok", false):
			workout_exit_pending = true
			_end_workout(active)
			return
		if active.is_empty():
			hide()
	if visible or is_instance_valid(rep_control) or is_instance_valid(trap_content):
		redraw()
	if not result.get("ok",false):
		# Failed requests do not advance the sequence. Refresh to recover from reconnect/replay.
		controller.refresh()

func request_direct(request: Dictionary) -> void:
	if pending or direct_in_flight or not direct.is_empty() or not controller.connected():return
	if state.has("profile"):
		direct_in_flight=true
		_send(request)
	else:
		direct=request
		controller.refresh()

func _send(request: Dictionary) -> void:
	var value:=request.duplicate(true)
	value.sequence=int(state.profile.last_sequence)+1
	controller.request(value)

func button(text: String,request: Dictionary,parent: Control = null) -> Button:
	var node:=UI.action(text, {"buy":"cart","start":"play","beat":"play","finish":"save","cancel":"back","consume":"check","sit":"home","place":"inventory","pickup":"inventory","emote":"play","stop":"back"}.get(str(request.get("op","")),"info"), Callable(), request.get("op","") in ["start","beat","buy"])
	node.disabled=pending
	node.pressed.connect(func():
		if pending or state.is_empty():return
		if request.get("op")=="buy" and has_order_space.is_valid() and not has_order_space.call():
			status.show()
			status.text="Free a hotbar slot before ordering."
			return
		pending=true
		last_error=""
		status.show()
		status.text="Waiting for campus host…"
		for action in service_actions: action.disabled=true
		_send(request))
	service_actions.append(node)
	(body if parent==null else parent).add_child(node)
	return node

func redraw() -> void:
	var active_workout: Dictionary = state.get("active", {})
	if active_workout.get("type") != "trapped" and is_instance_valid(trap_content):
		remove_child(trap_content)
		trap_content.queue_free()
		trap_content = null
	if active_workout.get("type", "") == "exercise":
		_show_exercise_hud(active_workout)
		return
	if is_instance_valid(rep_control):
		remove_child(rep_control)
		rep_control.queue_free()
		rep_control = null
		workout_identity = ""
	if active_workout.get("type") == "trapped":
		_show_trap_hud(active_workout)
		return
	menu_layout.show()
	service_actions.clear()
	for child in body.get_children():body.remove_child(child);child.queue_free()
	var restaurant := station_kind.begins_with("counter:")
	var gym := Rules.STATION_EXERCISES.has(station_kind) or station_kind in ["bench_dumbbell","bench_barbell","gym_progress"]
	var tim := station_kind=="counter:tim_hortons"
	var accent := Color("a72c3c") if tim else Color("147343") if restaurant else Color("d2a95b")
	var surface := Color("f8eee4") if tim else Color("f3f2dd") if restaurant else Color("182528") if gym else Tokens.SURFACE
	body.theme = _restaurant_theme(accent, surface) if restaurant else null
	add_theme_stylebox_override("panel", Tokens.surface(surface, accent if restaurant or gym else Tokens.BORDER, 16))
	var title := station_kind.trim_prefix("counter:").replace("_"," ").capitalize()
	if gym:
		title=str({"pushup":"Exercise mat","pullup":"Pull-up & dip station","benchpress":"Bench","squat":"Squat","curl":"Biceps curl","bench_dumbbell":"Bench · Dumbbells","bench_barbell":"Bench · Barbell"}.get(station_kind,title))
	var subtitle := "DRINKS & BAKERY" if tim else "SUBS & DRINKS" if restaurant else "CAMPUS GYM  /  TRAINING STATION" if gym else ""
	close.visible = gym
	if gym:
		body.add_child(UI.text(title, "TitleLabel"))
	elif restaurant:
		var header := HBoxContainer.new()
		body.add_child(header)
		var branded := _restaurant_label(title, 29, accent)
		branded.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		header.add_child(branded)
		var dismiss := Button.new()
		dismiss.text = "Close"
		dismiss.pressed.connect(hide)
		header.add_child(dismiss)
	else:
		body.add_child(UI.header(title if not title.is_empty() else "Campus service", subtitle, hide))
	status=Label.new();status.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;body.add_child(status)
	if state.is_empty():status.text="Connecting to campus host…";return
	var pending_count: int=int(state.get("pending_workouts",0))
	status.text = last_error
	if pending_count>0:
		status.text += ("\n" if not status.text.is_empty() else "") + "%d workout record%s waiting to save. Keep this host open and retry when profile storage is available."%[pending_count,"s" if pending_count!=1 else ""]
	status.visible = not status.text.is_empty() or pending
	if station_kind == "emotes":
		status.text = "Your emotes"
		var available: Array = state.profile.unlocks
		for emote in Rules.EMOTES:
			if emote in available:
				button(str(emote).capitalize(), {"op":"emote","emote":emote})
			else:
				var locked := Label.new()
				locked.text = str(emote).capitalize() + "  ·  Locked"
				body.add_child(locked)
		body.add_child(UI.action("Close", "close", hide))
		return
	var a: Dictionary=state.get("active",{})
	position=regular_position;custom_minimum_size=regular_minimum
	var target_size := Vector2(600, 620)
	if gym and station_kind != "gym_progress" and not showing_gym_progress:
		target_size = Vector2(460, 330)
	size = target_size.min(get_viewport_rect().size - Vector2(24,24))
	_position_panel()
	if gym:
		if station_kind=="gym_progress":_gym_progress(accent)
		elif showing_gym_progress and a.is_empty():_gym_progress(accent)
		else:_workout(a, accent)
	elif not a.is_empty():button("Stand / stop",{"op":"stop"})
	elif restaurant:
		_restaurant_menu(station_kind.trim_prefix("counter:"), accent, surface)
	if restaurant and has_order_space.is_valid() and not has_order_space.call():
		body.add_child(UI.text("Free a hotbar slot before ordering.","MutedLabel"))
	elif restaurant and Rules.carried_order_count(state.profile.get("orders",{}))>0:
		var key_name := str(placement_key_name.call()) if placement_key_name.is_valid() else "F"
		body.add_child(UI.text("Select your order in the hotbar. Right click to eat or drink, or press %s to place it on a flat surface." % key_name,"MutedLabel"))

func _position_panel() -> void:
	var viewport := get_viewport_rect().size
	if is_instance_valid(rep_control) or is_instance_valid(trap_content):
		position = Vector2((viewport.x-size.x)*.5, viewport.y-size.y-144)
	elif station_kind.begins_with("counter:"):
		size=Vector2(724,555).min(viewport-Vector2(24,24))
		position=(viewport-size)*.5
	elif Rules.STATION_EXERCISES.has(station_kind) or station_kind in ["bench_dumbbell", "bench_barbell", "gym_progress"]:
		var compact := station_kind != "gym_progress" and not showing_gym_progress
		size = (Vector2(460,330) if compact else Vector2(600,620)).min(viewport-Vector2(24,24))
		position = (viewport-size)*.5

func _fit_workout_hud() -> void:
	if is_instance_valid(rep_control) or is_instance_valid(trap_content):
		size = Vector2(410,112).max(get_combined_minimum_size())
		_position_panel()

func _show_exercise_hud(active: Dictionary) -> void:
	menu_layout.hide()
	custom_minimum_size=Vector2(410,112)
	size=custom_minimum_size
	var identity := "%s/%s" % [active.station, active.get("started", 0)]
	var phase := int(active.phase)
	if is_instance_valid(rep_control) and workout_identity != identity:
		remove_child(rep_control)
		rep_control.queue_free()
		rep_control = null
	if not is_instance_valid(rep_control):
		rep_control = preload("res://scripts/campus/facilities/gym_lift_control.gd").new()
		add_child(rep_control)
		rep_control.lower_requested.connect(func():request_direct({"op":"lower"}))
		rep_control.effort_requested.connect(func():request_direct({"op":"effort"}))
		rep_control.rep_requested.connect(func():request_direct({"op":"beat"}))
		rep_control.failed.connect(func():request_direct({"op":"rep_fail"}))
		rep_control.finish_requested.connect(close_or_end_workout)
		rep_control.motion_changed.connect(func(progress: float):
			if preview_workout.is_valid():preview_workout.call(progress)
			var current: Dictionary = state.get("active", {})
			if current.get("type") == "exercise" and Time.get_ticks_msec()-last_motion_ms >= 120:
				last_motion_ms = Time.get_ticks_msec()
				controller.preview_motion(progress, int(current.phase), int(current.reps), int(current.started)))
	if workout_identity != identity or workout_phase != phase or rep_control.reps != int(active.reps):
		var gym: Dictionary=state.profile.get("gym",{"muscles":{}})
		var capacity: float=Rules.GymProgress.capacity(gym,str(active.exercise))
		var load: float=Rules.GymProgress.effective_load(str(active.exercise),float(active.weight),float(active.get("body_mass",70.0)))
		rep_control.configure(capacity,load,phase,int(active.reps),float(active.get("lift_progress",-1.0)))
		workout_identity = identity
		workout_phase = phase
	_fit_workout_hud.call_deferred()
	if capture_game.is_valid():capture_game.call()

func handle_workout_input(event: InputEvent) -> bool:
	if state.get("active",{}).get("type")=="exercise_exit":
		return event is InputEventKey and event.pressed and event.keycode==KEY_ESCAPE
	if not visible:
		return false
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE and state.get("active", {}).get("type") in ["exercise", "trapped"]:
		close_or_end_workout()
		return true
	var active: Dictionary = state.get("active", {})
	if active.get("type") == "trapped" and event is InputEventKey and event.pressed and event.keycode in [KEY_A, KEY_D]:
		if not event.echo:
			request_direct({"op":"wiggle", "direction": -1 if event.keycode == KEY_A else 1})
		return true
	if is_instance_valid(rep_control):
		if direct_in_flight or workout_exit_pending:
			return (event is InputEventKey and event.keycode in [KEY_E, KEY_X]) or (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT)
		return bool(rep_control.handle_input(event))
	return false

func _restaurant_theme(accent: Color, surface: Color) -> Theme:
	var result := HudTheme.create()
	var ink := Color("252b23")
	for type in ["Label", "SubtitleLabel", "TitleLabel", "MutedLabel", "Button", "CheckBox", "CheckButton", "OptionButton"]:
		result.set_color("font_color", type, ink)
		result.set_color("font_hover_color", type, ink)
		result.set_color("font_focus_color", type, ink)
		result.set_color("font_pressed_color", type, Color.WHITE)
		result.set_color("font_disabled_color", type, Color("6b7064"))
	for type in ["Button", "OptionButton", "PrimaryButton", "QuietButton"]:
		for state in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
			var fill := surface.lightened(.5)
			if state in ["pressed", "hover_pressed"]:
				fill = accent
			elif state == "hover":
				fill = surface.lerp(accent,.10)
			elif state == "disabled":
				fill = surface.darkened(.08)
			var style := Tokens.surface(fill, surface.lerp(accent,.25), 9)
			style.content_margin_top = 7
			style.content_margin_bottom = 7
			result.set_stylebox(state,type,style)
	return result

func _restaurant_label(value: String, height: int, tint: Color) -> Label:
	var label := Label.new()
	label.text = value
	label.add_theme_font_size_override("font_size",height)
	label.add_theme_color_override("font_color",tint)
	return label

const KIOSK_ILLUSTRATIONS := ["iced_coffee","lemon_iced_tea","chocolate_donut","maple_donut","bagel","egg_bagel","chicken_wrap","cookie"]

func _restaurant_menu(venue: String, accent: Color, surface: Color) -> void:
	var tim := venue=="tim_hortons"
	var categories := ["Hot drinks","Cold drinks","Bakery","Breakfast","Lunch"] if tim else ["Subs","Sides","Drinks"]
	var category := cafe_category if tim else subway_category
	if category not in categories: category=categories[0]
	if not tim:
		var build := Button.new()
		build.text = "Build Your Own Sandwich"
		build.custom_minimum_size.y = 50
		build.add_theme_stylebox_override("normal",Tokens.surface(Color("f2ce4b"),Color("d0ad36"),9))
		build.add_theme_stylebox_override("hover",Tokens.surface(Color("ffe785"),Color("d0ad36"),9))
		build.pressed.connect(func():
			hide()
			sandwich_builder_requested.emit(station_id))
		body.add_child(build)
	var tabs := HFlowContainer.new()
	tabs.add_theme_constant_override("h_separation",6)
	tabs.add_theme_constant_override("v_separation",5)
	body.add_child(tabs)
	for name in categories:
		var tab := Button.new()
		tab.text = name
		tab.toggle_mode = true
		tab.set_pressed_no_signal(category==name)
		tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tab.pressed.connect(func():
			if tim:cafe_category=name
			else:subway_category=name
			redraw())
		tabs.add_child(tab)
	var visible_products := 0
	for entry in state.menu.values():
		if entry.venue==venue and entry.category==category:visible_products+=1
	var grid := GridContainer.new()
	grid.columns=3 if visible_products==3 and size.x>=530.0 else 2
	grid.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation",8)
	grid.add_theme_constant_override("v_separation",8)
	body.add_child(grid)
	for item in state.menu:
		var entry: Dictionary=state.menu[item]
		if entry.venue!=venue or entry.category!=category:continue
		var card := PanelContainer.new()
		card.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		card.add_theme_stylebox_override("panel",Tokens.surface(Color.WHITE, accent if cafe_selection==item else surface.darkened(.14),10))
		grid.add_child(card)
		var contents := VBoxContainer.new()
		contents.add_theme_constant_override("separation",4)
		card.add_child(contents)
		var artwork := TextureRect.new()
		var art := str(item) if item in KIOSK_ILLUSTRATIONS else str(entry.get("art",item))
		var path := "res://assets/ui/food_menu/%s.svg" % art
		if not ResourceLoader.exists(path):path="res://assets/ui/food_menu/%s.svg" % str(entry.get("art",item))
		artwork.texture=load(path) as Texture2D
		artwork.custom_minimum_size.y=67
		artwork.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
		artwork.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		contents.add_child(artwork)
		var title := _restaurant_label(entry.name,16,Color("252b23"))
		title.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
		title.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
		contents.add_child(title)
		var choose := Button.new()
		choose.text = "Selected · $%d" % entry.price if cafe_selection==item else "$%d  ·  Select" % entry.price
		choose.accessibility_name = "Select %s for $%d" % [entry.name,entry.price]
		choose.disabled=pending
		choose.pressed.connect(func():
			cafe_selection=item
			redraw())
		contents.add_child(choose)
	var order: Dictionary=state.menu.get(cafe_selection,{})
	var summary := HBoxContainer.new()
	var title := "%s  ·  $%d" % [order.name,order.price] if order.get("venue","")==venue else "Select an item to review your order"
	var selected := _restaurant_label(title,17,accent)
	selected.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	summary.add_child(selected)
	body.add_child(summary)
	if order.get("venue","")!=venue:return
	var confirm := button("Confirm order",{"op":"buy","station":station_id,"item":cafe_selection},summary)
	confirm.disabled=pending or (has_order_space.is_valid() and not has_order_space.call())

func _show_trap_hud(active: Dictionary) -> void:
	menu_layout.hide()
	custom_minimum_size = Vector2(410,112)
	size = custom_minimum_size
	if not is_instance_valid(trap_content):
		trap_content = VBoxContainer.new()
		add_child(trap_content)
		trap_content.add_child(UI.text("Pinned under the bar", "TitleLabel"))
		trap_meter = ProgressBar.new()
		trap_meter.accessibility_name = "Escape progress"
		trap_content.add_child(trap_meter)
		trap_instruction = UI.text("", "MutedLabel")
		trap_content.add_child(trap_instruction)
		trap_content.add_child(UI.text("A nearby player can lift the bar with E.", "MutedLabel"))
	trap_meter.value = float(active.progress)*100.0
	trap_instruction.text = "Press A to shift left" if int(active.direction)<0 else "Press D to shift right"
	_fit_workout_hud.call_deferred()
	if capture_game.is_valid():capture_game.call()

func _workout(active: Dictionary, _accent: Color) -> void:
	if active.is_empty():
		_exercise_choices()
	else:
		button("Stand / stop",{"op":"stop"})

func _exercise_category(exercise: String) -> String:
	if exercise in ["pushup","benchpress","incline_press","chest_fly","cable_fly","cable_press"] or exercise.begins_with("dip"):return "CHEST"
	if exercise in ["pullup","lat_pulldown","cable_row","bent_over_row","deadlift","romanian_deadlift","shrug","reverse_fly","cable_reverse_fly"]:return "BACK"
	if exercise in ["curl","wrist_curl","tricep_pushdown","overhead_extension"]:return "ARMS"
	if "crunch" in exercise or "leg_raise" in exercise or exercise=="plank":return "CORE"
	if "raise" in exercise or "overhead" in exercise or "shoulder" in exercise or exercise in ["upright_row","lateral_raise"]:return "SHOULDERS"
	if exercise in ["squat","calf_raise"]:return "LEGS"
	return "OTHER"

func _gym_progress(accent: Color) -> void:
	var gym: Dictionary = state.profile.get("gym", {"muscles":{}})
	var sizes: Dictionary = Rules.GymProgress.muscle_sizes(gym)
	var history: Array = gym.get("history", [])
	var total_growth := 0.0
	var total_fatigue := 0.0
	for muscle in Rules.GymProgress.MUSCLE_GROUPS:
		total_growth += float(sizes[muscle])
		total_fatigue += float(gym.get("muscles", {}).get(muscle, {}).get("fatigue", 0.0))
	var count: int = Rules.GymProgress.MUSCLE_GROUPS.size()
	var overview := HBoxContainer.new()
	body.add_child(overview)
	_progress_meter(overview, "Overall strength", Rules.GymProgress.overall_strength(gym), accent)
	_progress_meter(overview, "Mean growth", total_growth / count, accent)
	_progress_meter(overview, "Mean fatigue", total_fatigue / count, Color("dc8a76"))
	var completed := history.filter(func(entry):return entry.outcome == "voluntary" or entry.outcome == "failure").size()
	body.add_child(UI.text("%d completed sets in recent history" % completed, "MutedLabel"))

	var tabs := TabContainer.new()
	tabs.custom_minimum_size.y = clampf(get_viewport_rect().size.y - 330, 160, 365)
	body.add_child(tabs)
	var muscles := _progress_tab(tabs, "Muscles")
	for muscle in Rules.GymProgress.MUSCLE_GROUPS:
		var values: Dictionary = gym.get("muscles", {}).get(muscle, {})
		var meters := HBoxContainer.new()
		muscles.add_child(meters)
		var muscle_name: String=muscle.replace("_"," ").capitalize()
		var icon:=preload("res://scripts/campus/facilities/gym_muscle_icon.gd").new()
		icon.muscle=muscle
		icon.tooltip_text=muscle_name
		meters.add_child(icon)
		var name_label:=UI.text(muscle_name,"SubtitleLabel")
		name_label.custom_minimum_size.x=92
		name_label.vertical_alignment=VERTICAL_ALIGNMENT_CENTER
		name_label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
		meters.add_child(name_label)
		_progress_meter(meters, "Growth", float(sizes[muscle]), accent)
		_progress_meter(meters, "Strength", float(values.get("strength", 0.0)), accent)
		_progress_meter(meters, "Fatigue", float(values.get("fatigue", 0.0)), Color("dc8a76"))
		_progress_meter(meters, "Stimulus", float(values.get("stimulus", 0.0)), Color("80b9ae"), "Pending training stimulus")

	var sets := _progress_tab(tabs, "Training history")
	sets.add_child(UI.text("No recorded sets yet" if history.is_empty() else "%d recent sets" % history.size(), "SubtitleLabel"))
	for i in range(history.size()-1, -1, -1):
		var entry: Dictionary = history[i]
		sets.add_child(UI.text("%s  ·  %d reps  ·  %.1f lb" % [exercise_name(entry.exercise), int(entry.reps), float(entry.weight_kg)*2.20462262], "SubtitleLabel"))
		var details := "%s  ·  Relative load %.0f%%" % [str(entry.outcome).replace("_"," ").capitalize(), 100.0 * float(entry.relative_effort)]
		if entry.has("stimulus_added"):
			details += "  ·  Stimulus +%.1f%%" % (100.0 * float(entry.stimulus_added))
		var label := UI.text(details, "MutedLabel")
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		sets.add_child(label)
	if station_kind != "gym_progress":
		body.add_child(UI.action("Back to exercises", "back", func():showing_gym_progress=false;redraw()))

func _progress_tab(tabs: TabContainer, title: String) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.name = title
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	tabs.add_child(scroll)
	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(content)
	return content

func _progress_meter(parent: Container, title: String, amount: float, color: Color, tooltip := "") -> void:
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(column)
	var caption := UI.text("%s %.0f%%" % [title, amount * 100.0], "MutedLabel")
	caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	caption.tooltip_text = tooltip
	column.add_child(caption)
	var meter := ProgressBar.new()
	meter.show_percentage = false
	meter.value = amount * 100.0
	meter.custom_minimum_size.y = 6
	meter.add_theme_stylebox_override("fill", Tokens.surface(color, color, 3))
	column.add_child(meter)

const EXERCISE_ICON_ATLAS = preload("res://assets/ui/design_system/icons/gym-exercises.svg")
const EXERCISE_ICON_ORDER := [
	"pushup", "pullup", "benchpress", "squat", "curl", "deadlift",
	"romanian_deadlift", "front_raise", "upright_row", "overhead_extension", "bent_over_row", "shrug",
	"wrist_curl", "calf_raise", "lateral_raise", "reverse_fly", "chest_fly", "overhead_press",
	"good_morning", "incline_press", "chest_supported_row", "hanging_leg_raise", "dip", "cable_fly",
	"cable_reverse_fly", "cable_press", "lat_pulldown", "cable_row", "tricep_pushdown", "cable_crunch",
	"crunch", "leg_raise", "pike_pushup",
]

func _exercise_icon(exercise: String) -> Texture2D:
	var index := EXERCISE_ICON_ORDER.find(exercise)
	if index < 0:
		return null
	var icon := AtlasTexture.new()
	icon.atlas = EXERCISE_ICON_ATLAS
	icon.region = Rect2((index%6)*24, (index/6)*24, 24, 24)
	icon.filter_clip = true
	return icon

func _exercise_choices() -> void:
	var exercises: Array = Rules.STATION_EXERCISES.get(station_kind, [])
	if station_kind == "bench_dumbbell":
		exercises = Rules.BENCH_DUMBBELL_EXERCISES
	elif station_kind == "bench_barbell":
		exercises = Rules.BENCH_BARBELL_EXERCISES
	var select := OptionButton.new()
	select.accessibility_name = "Exercise"
	select.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(select)
	var summary := UI.text("", "MutedLabel")
	summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(summary)
	var load_choice := OptionButton.new()
	body.add_child(load_choice)
	load_choice.name = "ExerciseLoad"
	var request := {"op":"start", "station":station_id}
	var start := button("Start set", request)
	var first := -1
	for category in ["CHEST", "BACK", "SHOULDERS", "ARMS", "LEGS", "CORE", "OTHER"]:
		var heading_added := false
		for exercise in exercises:
			if _exercise_category(exercise) != category:
				continue
			if not heading_added:
				select.add_separator(category)
				heading_added = true
			var index := select.item_count
			select.add_icon_item(_exercise_icon(exercise), exercise_name(exercise))
			select.set_item_metadata(index, exercise)
			if first < 0:
				first = index
	if station_kind == "curl":
		select.add_item("Chest fly · Requires a supported bench")
		select.set_item_disabled(select.item_count - 1, true)
	var update := func(index: int):
		var exercise := str(select.get_item_metadata(index))
		request.exercise = exercise
		request.erase("weight")
		load_choice.clear()
		load_choice.hide()
		start.disabled = pending
		if station_kind == "cable":
			request.weight = int(cable_resistance.call(station_id)) if cable_resistance.is_valid() else 10
			var extra:=float(cable_extra_mass.call(station_id)) if cable_extra_mass.is_valid() else 0.0
			summary.text = "%s · %d lb total" % [exercise_name(exercise),roundi(float(request.weight)+extra*2.20462262)]
		elif station_kind in ["barbell", "bench_barbell", "benchpress", "squat", "curl", "bench_dumbbell"]:
			var dumbbells := station_kind in ["curl", "bench_dumbbell"]
			var mass := 0.0
			if dumbbells and dumbbell_mass.is_valid():
				mass = float(dumbbell_mass.call())
			elif not dumbbells and barbell_mass.is_valid():
				mass = float(barbell_mass.call(station_id if station_kind in ["benchpress", "squat"] else "held"))
			if station_kind in ["bench_barbell", "bench_dumbbell"]:
				request.equipment = "dumbbell" if dumbbells else "barbell"
			summary.text = "%s · %.1f lb %s" % [exercise_name(exercise),mass*2.20462262, "dumbbell pair" if dumbbells else "barbell"] if mass > 0 else ("Equip a pair of dumbbells" if dumbbells else "A barbell is required")
			start.disabled = pending or mass <= 0
		else:
			summary.text = exercise_name(exercise)
			for kg in Rules.WEIGHTS[exercise]:
				load_choice.add_item("Bodyweight" if kg == 0 else "%d lb" % roundi(kg*2.20462262), kg)
			load_choice.select(0)
			request.weight = load_choice.get_item_id(0)
			load_choice.show()
	load_choice.item_selected.connect(func(index: int): request.weight = load_choice.get_item_id(index))
	select.item_selected.connect(update)
	if first >= 0:
		select.select(first)
		update.call(first)
	else:
		start.disabled = true
