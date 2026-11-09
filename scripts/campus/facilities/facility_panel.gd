extends PanelContainer
const UI = preload("res://scripts/ui/design_system/widgets.gd")
const HudTheme = preload("res://scripts/ui/design_system/theme.gd")
const Tokens = preload("res://scripts/ui/design_system/tokens.gd")
const Rules = preload("res://scripts/campus/facilities/facility_host.gd")
signal direct_error(message: String)
## The world interaction supplies the selected cashier or exercise station.
var controller: Node
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
var has_order_space := Callable()
var orders_changed := Callable()

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
	var gym := Rules.EXERCISES.has(station_kind)
	var tim := station_kind=="counter:tim_hortons"
	var accent := Color("a72c3c") if tim else Color("147343") if restaurant else Color("d2a95b")
	var surface := Color("2d1b1a") if tim else Color("15291e") if restaurant else Color("182528") if gym else Tokens.SURFACE
	add_theme_stylebox_override("panel", Tokens.surface(surface, accent if restaurant or gym else Tokens.BORDER, 18))
	var title := station_kind.trim_prefix("counter:").replace("_"," ").capitalize()
	if gym:
		title=str({"pushup":"Push-up","pullup":"Pull-up","benchpress":"Bench press","squat":"Squat","curl":"Biceps curl"}.get(station_kind,title))
	var subtitle := "DRINKS & BAKERY" if tim else "SUBS & DRINKS" if restaurant else "CAMPUS GYM  /  TRAINING STATION" if gym else ""
	body.add_child(UI.header(title if not title.is_empty() else "Campus service", subtitle, hide))
	status=Label.new();status.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;body.add_child(status)
	if state.is_empty():status.text="Connecting to campus host…";return
	status.text = last_error
	status.visible = not last_error.is_empty() or pending
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
	if gym:
		_workout(a, accent)
	elif not a.is_empty():button("Stand / stop",{"op":"stop"})
	elif restaurant:
		_food_menu(station_kind.trim_prefix("counter:"), accent, surface)
	if restaurant and has_order_space.is_valid() and not has_order_space.call():
		body.add_child(UI.text("Free a hotbar slot before ordering.","MutedLabel"))
	elif restaurant and Rules.carried_order_count(state.profile.get("orders",{}))>0:
		body.add_child(UI.text("Select your order in the hotbar. Right click to eat or drink, or left click a tabletop to place it.","MutedLabel"))

func _food_menu(venue: String, accent: Color, surface: Color) -> void:
	var grid := preload("res://scripts/ui/design_system/responsive_grid.gd").new()
	grid.minimum_card_width = 145
	grid.maximum_columns = 3
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	body.add_child(grid)
	for item in state.menu:
		var entry: Dictionary=state.menu[item]
		if entry.venue != venue:continue
		var card := PanelContainer.new()
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.add_theme_stylebox_override("panel", Tokens.surface(surface.lightened(.07), accent, 10))
		grid.add_child(card)
		var contents := VBoxContainer.new()
		contents.add_theme_constant_override("separation", 8)
		card.add_child(contents)
		var artwork := TextureRect.new()
		artwork.texture=load("res://assets/ui/food_menu/%s.svg" % item) as Texture2D
		artwork.custom_minimum_size.y=104
		artwork.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
		artwork.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		contents.add_child(artwork)
		var name_label := UI.text(str(entry.name), "SubtitleLabel")
		name_label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
		contents.add_child(name_label)
		var order := button("Order · $%d" % entry.price, {"op":"buy","station":station_id,"item":item}, contents)
		order.accessibility_name = "Order %s for $%d" % [entry.name,entry.price]
		order.disabled = pending or (has_order_space.is_valid() and not has_order_space.call())
		order.add_theme_stylebox_override("normal", Tokens.surface(accent.darkened(.28), accent, 8))
		order.add_theme_stylebox_override("hover", Tokens.surface(accent.darkened(.10), accent, 8))

func _workout(active: Dictionary, accent: Color) -> void:
	var summary := PanelContainer.new()
	summary.add_theme_stylebox_override("panel", Tokens.surface(Color("26373a"), accent, 12))
	body.add_child(summary)
	var metrics := VBoxContainer.new()
	summary.add_child(metrics)
	metrics.add_child(UI.text("LEVEL %d   /   %d XP" % [state.level,state.profile.xp], "MutedLabel"))
	if active.get("type","")=="exercise":
		metrics.add_child(UI.text("%02d REPS   /   %s" % [active.reps, "%d kg" % active.weight if int(active.weight)>0 else "Bodyweight"],"TitleLabel"))
		metrics.add_child(UI.text("Wait for the next movement to light up.", "MutedLabel"))
		workout_step=button("Lower" if int(active.phase)==0 else "Raise",{"op":"beat"})
		workout_ready_at=Time.get_ticks_msec()+int(Rules.EXERCISES[active.exercise])/2-100
		workout_step.disabled=true
		button("Finish set",{"op":"finish"}).disabled=pending or int(active.reps)<1
		button("Cancel set",{"op":"cancel"})
	elif active.is_empty():
		metrics.add_child(UI.text("Choose your load", "TitleLabel"))
		var loads := HFlowContainer.new()
		body.add_child(loads)
		for kg in Rules.WEIGHTS[station_kind]:
			var load_button := button("Bodyweight" if kg==0 else "%d kg" % kg,{"op":"start","station":station_id,"weight":kg},loads)
			load_button.custom_minimum_size.x=130
	else:
		button("Stand / stop",{"op":"stop"})

func _process(_delta: float) -> void:
	if visible and is_instance_valid(workout_step) and not pending:
		workout_step.disabled=Time.get_ticks_msec()<workout_ready_at
