extends PanelContainer
const UI = preload("res://scripts/ui/design_system/widgets.gd")
const HudTheme = preload("res://scripts/ui/design_system/theme.gd")
const Tokens = preload("res://scripts/ui/design_system/tokens.gd")
const Rules = preload("res://scripts/campus/facilities/facility_host.gd")
signal direct_error(message: String)
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
var direct := {}
var direct_in_flight := false
var workout_step: Button
var workout_ready_at := 0
var workout_reached := false
var has_order_space := Callable()
var orders_changed := Callable()
var dumbbell_mass := Callable()
var barbell_mass := Callable()
var cable_resistance := Callable()
var capture_game := Callable()
var rep_control: Control
var regular_position := Vector2(60,60)
var regular_minimum := Vector2(300,240)
var showing_gym_progress := false
var close: Button

static func exercise_name(id: String) -> String:
	return str({"pushup":"Push-up","pike_pushup":"Pike push-up","pullup":"Pull-up","benchpress":"Bench press","curl":"Biceps curl","dip":"Dip"}.get(id,id.replace("_"," ").capitalize()))

func _ready() -> void:
	theme=HudTheme.create()
	custom_minimum_size=Vector2(300,240)
	size=Vector2(minf(600,get_viewport_rect().size.x-32),minf(620,get_viewport_rect().size.y-32))
	add_theme_stylebox_override("panel",HudTheme.card_style())
	var layout := VBoxContainer.new()
	add_child(layout)
	close = UI.action("Close", "close", hide)
	layout.add_child(close)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus=true
	layout.add_child(scroll)
	body.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	scroll.add_child(body)
	body.add_theme_constant_override("separation",12)

func bind(value: Node) -> void:
	controller=value
	controller.owner_result.connect(receive)

func open_for(id: String,kind: String) -> void:
	station_id=id;station_kind=kind;visible=true
	position=regular_position;custom_minimum_size=regular_minimum
	showing_gym_progress=false
	last_error=""
	redraw()
	controller.refresh()

func receive(result: Dictionary) -> void:
	pending=false
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
	if visible:redraw()
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
	service_actions.clear()
	for child in body.get_children():body.remove_child(child);child.queue_free()
	workout_step=null
	var restaurant := station_kind.begins_with("counter:")
	var gym := Rules.STATION_EXERCISES.has(station_kind) or station_kind in ["bench_dumbbell","bench_barbell","gym_progress"]
	var tim := station_kind=="counter:tim_hortons"
	var accent := Color("a72c3c") if tim else Color("147343") if restaurant else Color("d2a95b")
	var surface := Color("2d1b1a") if tim else Color("15291e") if restaurant else Color("182528") if gym else Tokens.SURFACE
	add_theme_stylebox_override("panel", Tokens.surface(surface, accent if restaurant or gym else Tokens.BORDER, 18))
	var title := station_kind.trim_prefix("counter:").replace("_"," ").capitalize()
	if gym:
		title=str({"pushup":"Exercise mat","pullup":"Pull-up & dip station","benchpress":"Bench press","squat":"Squat","curl":"Biceps curl","bench_dumbbell":"Bench · Dumbbells","bench_barbell":"Bench · Barbell"}.get(station_kind,title))
	var subtitle := "DRINKS & BAKERY" if tim else "SUBS & DRINKS" if restaurant else "CAMPUS GYM  /  TRAINING STATION" if gym else ""
	close.visible = gym
	if gym:
		body.add_child(UI.text(title, "TitleLabel"))
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
	if gym and a.get("type","")=="exercise":
		_show_exercise_hud(a)
		return
	position=regular_position;custom_minimum_size=regular_minimum
	var target_size := Vector2(600, 620)
	if gym and station_kind != "gym_progress" and not showing_gym_progress:
		target_size = Vector2(460, 330)
	size = target_size.min(get_viewport_rect().size - position - Vector2(12,12))
	if gym:
		if station_kind=="gym_progress":_gym_progress(accent)
		elif showing_gym_progress and a.is_empty():_gym_progress(accent)
		else:_workout(a, accent)
	elif not a.is_empty():button("Stand / stop",{"op":"stop"})
	elif restaurant:
		_food_menu(station_kind.trim_prefix("counter:"), accent, surface)
	if restaurant and has_order_space.is_valid() and not has_order_space.call():
		body.add_child(UI.text("Free a hotbar slot before ordering.","MutedLabel"))
	elif restaurant and Rules.carried_order_count(state.profile.get("orders",{}))>0:
		var key_name := str(placement_key_name.call()) if placement_key_name.is_valid() else "F"
		body.add_child(UI.text("Select your order in the hotbar. Right click to eat or drink, or press %s to place it on a flat surface." % key_name,"MutedLabel"))

func _show_exercise_hud(active: Dictionary) -> void:
	close.hide()
	for child in body.get_children():body.remove_child(child);child.queue_free()
	custom_minimum_size=Vector2(410,112);size=custom_minimum_size
	var viewport:=get_viewport_rect().size
	position=Vector2((viewport.x-410.0)*.5,viewport.y-142.0)
	var control=preload("res://scripts/campus/facilities/gym_lift_control.gd").new()
	body.add_child(control);rep_control=control
	var gym: Dictionary=state.profile.get("gym",{"muscles":{}})
	var capacity: float=Rules.GymProgress.capacity(gym,str(active.exercise))
	var load: float=Rules.GymProgress.effective_load(str(active.exercise),float(active.weight),float(active.get("body_mass",70.0)))
	control.configure(capacity,load,int(active.phase),int(active.reps))
	control.lower_requested.connect(func():request_direct({"op":"lower"}))
	control.rep_requested.connect(func():request_direct({"op":"beat"}))
	control.failed.connect(func():request_direct({"op":"rep_fail"}))
	control.finish_requested.connect(func():request_direct({"op":"finish" if int(active.reps)>0 else "cancel"}))
	if capture_game.is_valid():capture_game.call()

func handle_workout_input(event: InputEvent) -> bool:
	return is_instance_valid(rep_control) and visible and rep_control.has_method("handle_input") and bool(rep_control.call("handle_input",event))

func _food_menu(venue: String, accent: Color, surface: Color) -> void:
	var categories: Array[String]=[]
	for entry in state.menu.values():
		if entry.venue==venue and not str(entry.get("category", "Other")) in categories:categories.append(str(entry.get("category", "Other")))
	for category in categories:
		body.add_child(UI.text(category, "SubtitleLabel"))
		var grid := preload("res://scripts/ui/design_system/responsive_grid.gd").new()
		grid.minimum_card_width=145
		grid.maximum_columns=3
		grid.add_theme_constant_override("h_separation",8)
		grid.add_theme_constant_override("v_separation",8)
		body.add_child(grid)
		for item in state.menu:
			var entry: Dictionary=state.menu[item]
			if entry.venue!=venue or str(entry.get("category", "Other"))!=category:continue
			var card := PanelContainer.new()
			card.size_flags_horizontal=Control.SIZE_EXPAND_FILL
			card.add_theme_stylebox_override("panel",Tokens.surface(surface.lightened(.07),accent,10))
			grid.add_child(card)
			var contents := VBoxContainer.new()
			contents.add_theme_constant_override("separation",8)
			card.add_child(contents)
			var artwork := TextureRect.new()
			artwork.texture=load("res://assets/ui/food_menu/%s.svg" % str(entry.get("art",item))) as Texture2D
			artwork.custom_minimum_size.y=88
			artwork.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
			artwork.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			contents.add_child(artwork)
			var name_label := UI.text(str(entry.name),"SubtitleLabel")
			name_label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
			contents.add_child(name_label)
			var order := button("Order · $%d" % entry.price,{"op":"buy","station":station_id,"item":item},contents)
			order.accessibility_name="Order %s for $%d" % [entry.name,entry.price]
			order.disabled=pending or (has_order_space.is_valid() and not has_order_space.call())
			order.add_theme_stylebox_override("normal",Tokens.surface(accent.darkened(.28),accent,8))
			order.add_theme_stylebox_override("hover",Tokens.surface(accent.darkened(.10),accent,8))

func _workout(active: Dictionary, accent: Color) -> void:
	var metrics := VBoxContainer.new()
	if active.is_empty():
		body.add_child(metrics)
	else:
		var summary := PanelContainer.new()
		summary.add_theme_stylebox_override("panel", Tokens.surface(Color("26373a"), accent, 12))
		body.add_child(summary)
		summary.add_child(metrics)
	var gym_state: Dictionary=state.profile.get("gym",{"muscles":{}})
	if active.get("type","")=="trapped":
		metrics.add_child(UI.text("BAR TRAPPED  ·  %.0f%% FREE" % (100.0*float(active.progress)),"TitleLabel"))
		var direction:=int(active.direction)
		metrics.add_child(UI.text("Move left to shift the bar." if direction<0 else "Move right to shift the bar.","MutedLabel"))
		metrics.add_child(UI.text("A nearby player can help. The safety reset releases the bar after 45 seconds.","MutedLabel"))
		var movement:=HSlider.new();movement.min_value=0.0;movement.max_value=1.0;movement.step=.01
		movement.value=1.0 if direction<0 else 0.0;movement.custom_minimum_size.y=38
		movement.accessibility_name="Shift the trapped bar left or right";body.add_child(movement)
		workout_reached=false
		movement.value_changed.connect(func(value: float):workout_reached=value<=.02 if direction<0 else value>=.98)
		workout_step=button("Shift left" if direction<0 else "Shift right",{"op":"wiggle","direction":direction})
		workout_ready_at=Time.get_ticks_msec()+650;workout_step.disabled=true
	elif active.get("type","")=="exercise":
		metrics.add_child(UI.text(exercise_name(str(active.exercise)),"TitleLabel"))
		metrics.add_child(UI.text("%02d REPS   /   %s" % [active.reps, "%.1f kg" % float(active.weight) if int(active.weight)>0 else "Bodyweight"],"TitleLabel"))
		var progress: Dictionary=state.profile.get("gym",{"muscles":{}})
		var capacity: float=Rules.GymProgress.capacity(progress,str(active.exercise))
		var required: float=Rules.GymProgress.effective_load(str(active.exercise),float(active.weight),float(active.get("body_mass",70.0)))
		metrics.add_child(UI.text("Effort %.0f%% · estimated capacity %.1f kg" % [100.0*required/maxf(capacity,.01),capacity],"MutedLabel"))
		var trained: Dictionary=Rules.GymProgress.exercise_data()[str(active.exercise)].muscles
		var fatigue_labels:=PackedStringArray()
		for muscle_name in trained:
			var muscle: Dictionary=progress.get("muscles",{}).get(muscle_name,{})
			fatigue_labels.append("%s %.0f%%" % [str(muscle_name).replace("_"," ").capitalize(),100.0*float(muscle.get("fatigue",0.0))])
		metrics.add_child(UI.text("FATIGUE  ·  "+"  /  ".join(fatigue_labels),"MutedLabel"))
		var lowering: bool=int(active.phase)==0
		metrics.add_child(UI.text("Adjust effort and hold to move. The target changes through the lift.", "MutedLabel"))
		var movement=preload("res://scripts/campus/facilities/gym_lift_control.gd").new()
		body.add_child(movement)
		movement.configure(capacity,required,int(active.phase),int(active.reps))
		workout_reached=false
		movement.completed.connect(func():workout_reached=true)
		movement.failure_ready.connect(func():workout_reached=true)
		movement.motion_changed.connect(func(value: float):
			if is_instance_valid(controller) and controller.has_method("preview_motion"):controller.preview_motion(value,int(active.phase),int(active.reps),int(active.get("started",0))))
		var actions:=HBoxContainer.new();body.add_child(actions)
		workout_step=button("Complete lower" if lowering else "Attempt lift" if required>capacity else "Complete raise",{"op":"beat"},actions)
		workout_step.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		workout_ready_at=Time.get_ticks_msec()+int(active.get("half_ms",int(Rules.EXERCISES[active.exercise])/2))-100
		workout_step.disabled=true
		button("Finish set",{"op":"finish"},actions).disabled=pending or int(active.reps)<1
		button("Cancel",{"op":"cancel"},actions)
	elif active.is_empty():
		var spotting:=str(state.get("spotting",""))
		if not spotting.is_empty():
			metrics.add_child(UI.text("SPOTTING · %s" % spotting.get_file().capitalize(),"TitleLabel"))
			body.add_child(UI.text("Stay close and ready to assist the lifter.","MutedLabel"))
			button("Stop spotting",{"op":"unspot"})
			return
		if station_kind in ["benchpress","squat"]:
			button("Spot the next lift",{"op":"spot","station":station_id})
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
		muscles.add_child(UI.text("%s  ·  %.1f%% size" % [muscle.replace("_", " ").capitalize(), 100.0 * float(sizes[muscle])], "SubtitleLabel"))
		var meters := HBoxContainer.new()
		muscles.add_child(meters)
		_progress_meter(meters, "Growth", float(sizes[muscle]), accent)
		_progress_meter(meters, "Strength", float(values.get("strength", 0.0)), accent)
		_progress_meter(meters, "Fatigue", float(values.get("fatigue", 0.0)), Color("dc8a76"))
		_progress_meter(meters, "Stimulus", float(values.get("stimulus", 0.0)), Color("80b9ae"), "Pending training stimulus")

	var sets := _progress_tab(tabs, "Training history")
	sets.add_child(UI.text("No recorded sets yet" if history.is_empty() else "%d recent sets" % history.size(), "SubtitleLabel"))
	for i in range(history.size()-1, -1, -1):
		var entry: Dictionary = history[i]
		sets.add_child(UI.text("%s  ·  %d reps  ·  %.1f kg" % [exercise_name(entry.exercise), int(entry.reps), float(entry.weight_kg)], "SubtitleLabel"))
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

func _exercise_icon(category: String) -> Texture2D:
	match category:
		"CHEST": return preload("res://assets/ui/design_system/icons/gym-press.svg")
		"BACK": return preload("res://assets/ui/design_system/icons/gym-pull.svg")
		"SHOULDERS": return preload("res://assets/ui/design_system/icons/gym-raise.svg")
		"ARMS": return preload("res://assets/ui/design_system/icons/gym-curl.svg")
		_: return UI.icon("play")

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
			select.add_icon_item(_exercise_icon(category), exercise_name(exercise))
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
			request.weight = int(cable_resistance.call(station_id)) if cable_resistance.is_valid() else 5
			summary.text = "%s · %d kg on the stack" % [exercise_name(exercise), request.weight]
		elif station_kind in ["barbell", "bench_barbell", "benchpress", "squat", "curl", "bench_dumbbell"]:
			var dumbbells := station_kind in ["curl", "bench_dumbbell"]
			var mass := 0.0
			if dumbbells and dumbbell_mass.is_valid():
				mass = float(dumbbell_mass.call())
			elif not dumbbells and barbell_mass.is_valid():
				mass = float(barbell_mass.call(station_id if station_kind in ["benchpress", "squat"] else "held"))
			if station_kind in ["bench_barbell", "bench_dumbbell"]:
				request.equipment = "dumbbell" if dumbbells else "barbell"
			summary.text = "%s · %.1f kg %s" % [exercise_name(exercise), mass, "dumbbell pair" if dumbbells else "barbell"] if mass > 0 else ("Equip a pair of dumbbells" if dumbbells else "A barbell is required")
			start.disabled = pending or mass <= 0
		else:
			summary.text = exercise_name(exercise)
			for kg in Rules.WEIGHTS[exercise]:
				load_choice.add_item("Bodyweight" if kg == 0 else "%d kg" % kg, kg)
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

func _process(_delta: float) -> void:
	if visible and is_instance_valid(workout_step) and not pending:
		workout_step.disabled=not workout_reached or Time.get_ticks_msec()<workout_ready_at
