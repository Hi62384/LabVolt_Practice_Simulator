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

static func exercise_name(id: String) -> String:
	return str({"pushup":"Push-up","pike_pushup":"Pike push-up","pullup":"Pull-up","benchpress":"Bench press","curl":"Biceps curl","dip":"Dip"}.get(id,id.replace("_"," ").capitalize()))

func _ready() -> void:
	theme=HudTheme.create()
	custom_minimum_size=Vector2(300,240)
	size=Vector2(minf(600,get_viewport_rect().size.x-32),minf(620,get_viewport_rect().size.y-32))
	add_theme_stylebox_override("panel",HudTheme.card_style())
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus=true
	add_child(scroll)
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
	if not active.is_empty():
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
		metrics.add_child(UI.text("Choose an exercise", "TitleLabel"))
		if station_kind in ["benchpress","squat"]:
			button("Spot the next lift",{"op":"spot","station":station_id})
		if station_kind=="cable":
			_cable_choices()
			return
		var labels := {"pushup":"Push-up","crunch":"Crunch","leg_raise":"Leg raise","pike_pushup":"Pike push-up","pullup":"Pull-up","hanging_leg_raise":"Hanging leg raise","dip":"Dip","benchpress":"Bench press","squat":"Squat","curl":"Biceps curl","deadlift":"Deadlift","romanian_deadlift":"Romanian deadlift","front_raise":"Front raise","upright_row":"Upright row","wrist_curl":"Wrist curl","overhead_extension":"Overhead extension","bent_over_row":"Bent-over row","shrug":"Shrug","lateral_raise":"Lateral raise","reverse_fly":"Reverse fly","calf_raise":"Calf raise"}
		var exercises: Array=Rules.BENCH_DUMBBELL_EXERCISES if station_kind=="bench_dumbbell" else Rules.BENCH_BARBELL_EXERCISES if station_kind=="bench_barbell" else Rules.STATION_EXERCISES[station_kind]
		var categories := ["CHEST", "BACK", "SHOULDERS", "ARMS", "LEGS", "CORE", "OTHER"]
		for category in categories:
			var category_exercises: Array=[]
			for exercise in exercises:
				if _exercise_category(str(exercise))==category:category_exercises.append(exercise)
			if category_exercises.is_empty():continue
			body.add_child(UI.text(category,"MutedLabel"))
			for exercise in category_exercises:
				body.add_child(UI.text(str(labels.get(exercise,exercise.capitalize())),"SubtitleLabel"))
				var loads := HFlowContainer.new()
				body.add_child(loads)
				if station_kind in ["barbell","bench_barbell"]:
					var mass: float=float(barbell_mass.call("held")) if barbell_mass.is_valid() else 0.0
					var request:={"op":"start","station":station_id,"exercise":exercise}
					if station_kind=="bench_barbell":request.equipment="barbell"
					var load_button := button("Carried bar · %.1f kg" % mass if mass>0 else "Pick up a barbell first",request,loads)
					load_button.disabled=mass<=0 or pending
				elif station_kind in ["curl","bench_dumbbell"]:
					var mass: float=float(dumbbell_mass.call()) if dumbbell_mass.is_valid() else 0.0
					var request := {"op":"start","station":station_id,"exercise":exercise}
					if station_kind=="bench_dumbbell":request.equipment="dumbbell"
					var load_button := button("Equipped pair · %.1f kg total" % mass if mass>0 else "Equip dumbbells first",request,loads)
					load_button.disabled=mass<=0 or pending
				elif station_kind in ["benchpress","squat"]:
					var mass: float=float(barbell_mass.call(station_id)) if barbell_mass.is_valid() else 0.0
					var load_button := button("Loaded bar · %.1f kg" % mass if mass>0 else "Barbell unavailable",{"op":"start","station":station_id,"exercise":exercise},loads)
					load_button.disabled=mass<=0 or pending
				else:
					for kg in Rules.WEIGHTS[exercise]:
						var load_button := button("Bodyweight" if kg==0 else "%d kg" % kg,{"op":"start","station":station_id,"exercise":exercise,"weight":kg},loads)
						load_button.custom_minimum_size.x=130
		if station_kind=="curl":
			body.add_child(UI.text("Chest fly","SubtitleLabel"))
			var supported:=button("Use a supported bench",{"op":"start","station":station_id,"exercise":"chest_fly"})
			supported.disabled=true
	else:
		button("Stand / stop",{"op":"stop"})

func _exercise_category(exercise: String) -> String:
	if exercise in ["pushup","benchpress","incline_press","chest_fly","cable_fly","cable_press"] or exercise.begins_with("dip"):return "CHEST"
	if exercise in ["pullup","lat_pulldown","cable_row","bent_over_row","deadlift","romanian_deadlift","shrug","reverse_fly","cable_reverse_fly"]:return "BACK"
	if "raise" in exercise or "overhead" in exercise or "shoulder" in exercise or exercise in ["upright_row","lateral_raise"]:return "SHOULDERS"
	if exercise in ["curl","wrist_curl","tricep_pushdown","overhead_extension"]:return "ARMS"
	if exercise in ["squat","calf_raise"]:return "LEGS"
	if "crunch" in exercise or "leg_raise" in exercise or exercise=="plank":return "CORE"
	return "OTHER"

func _gym_progress(accent: Color) -> void:
	var gym: Dictionary=state.profile.get("gym",{"muscles":{}})
	var sizes: Dictionary=Rules.GymProgress.muscle_sizes(gym)
	body.add_child(UI.text("MUSCLE PROGRESS", "TitleLabel"))
	body.add_child(UI.text("Overall strength  %.1f%%  ·  Training adapts during recovery" % (100.0*Rules.GymProgress.overall_strength(gym)),"MutedLabel"))
	for name in Rules.GymProgress.MUSCLE_GROUPS:
		var muscle: Dictionary=gym.get("muscles",{}).get(name,{})
		var row:=PanelContainer.new()
		row.add_theme_stylebox_override("panel",Tokens.surface(Color("26373a"),accent,8))
		body.add_child(row)
		var detail:=VBoxContainer.new();row.add_child(detail)
		detail.add_child(UI.text("%s  ·  %.1f%% size" % [str(name).replace("_"," ").capitalize(),100.0*float(sizes[name])],"SubtitleLabel"))
		detail.add_child(UI.text("Fatigue %.0f%%  ·  Pending stimulus %.0f%%" % [100.0*float(muscle.get("fatigue",0.0)),100.0*float(muscle.get("stimulus",0.0))],"MutedLabel"))
	var history: Array=gym.get("history",[])
	if not history.is_empty():
		var last: Dictionary=history.back()
		body.add_child(UI.text("LAST SET", "SubtitleLabel"))
		body.add_child(UI.text("%s  ·  %d reps  ·  %.1f kg  ·  %s" % [str(last.exercise).replace("_"," ").capitalize(),int(last.reps),float(last.weight_kg),str(last.outcome).replace("_"," ").capitalize()],"MutedLabel"))
		var names:=PackedStringArray()
		for name in last.muscles:names.append(str(name).replace("_"," ").capitalize())
		body.add_child(UI.text("Muscles: "+", ".join(names),"MutedLabel"))
		body.add_child(UI.text("Relative load %.0f%%  ·  %.0f seconds" % [100.0*float(last.relative_effort),float(last.duration_seconds)],"MutedLabel"))
		if last.has("fatigue_added") and last.has("stimulus_added"):
			body.add_child(UI.text("Fatigue added %.1f%%  ·  Training stimulus added %.1f%%" % [100.0*float(last.fatigue_added),100.0*float(last.stimulus_added)],"MutedLabel"))
	body.add_child(UI.action("Back to exercises", "back", func():showing_gym_progress=false;redraw()))

func _cable_choices() -> void:
	body.add_child(UI.text("Exercise", "SubtitleLabel"))
	var select:=OptionButton.new();select.size_flags_horizontal=Control.SIZE_EXPAND_FILL;body.add_child(select)
	var labels:={"cable_fly":"Cable fly","cable_reverse_fly":"Reverse fly","cable_press":"Chest press","lat_pulldown":"Lat pulldown","cable_row":"Cable row","lateral_raise":"Lateral raise","front_raise":"Front raise","overhead_press":"Shoulder press","curl":"Biceps curl","tricep_pushdown":"Triceps pushdown","overhead_extension":"Overhead extension","cable_crunch":"Cable crunch"}
	var grouped: Dictionary={"CHEST": ["cable_fly","cable_press"],"BACK": ["lat_pulldown","cable_row"],"SHOULDERS": ["cable_reverse_fly","lateral_raise","front_raise","overhead_press"],"ARMS": ["curl","tricep_pushdown","overhead_extension"],"CORE": ["cable_crunch"]}
	var first_exercise: String=Rules.CABLE_EXERCISES[0]
	for category in grouped:
		var available: Array=[]
		for exercise in grouped[category]:
			if exercise in Rules.CABLE_EXERCISES:available.append(exercise)
		if available.is_empty():continue
		select.add_separator(category)
		for exercise in available:
			var index:=select.item_count;select.add_item(str(labels.get(exercise,exercise.capitalize())));select.set_item_metadata(index,exercise)
			if first_exercise.is_empty():first_exercise=exercise
	var request:={"op":"start","station":station_id,"exercise":first_exercise,"weight":int(cable_resistance.call(station_id)) if cable_resistance.is_valid() else 5}
	select.item_selected.connect(func(index: int):request.exercise=str(select.get_item_metadata(index)))
	button("Start set",request)

func _process(_delta: float) -> void:
	if visible and is_instance_valid(workout_step) and not pending:
		workout_step.disabled=not workout_reached or Time.get_ticks_msec()<workout_ready_at
