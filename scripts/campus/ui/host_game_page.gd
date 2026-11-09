extends Control
signal closed

const ThemeFactory = preload("res://scripts/ui/design_system/theme.gd")
const T = preload("res://scripts/ui/design_system/tokens.gd")
const Widgets = preload("res://scripts/ui/design_system/widgets.gd")
const Source = preload("res://scripts/campus/ui/gradebook_source.gd")
const GREEN := Color("a3edaa")

var game: Node
var classroom := ""
var class_requested: Callable
var model := {}
var selected_course := ""
var selected_kind := ""
var selected_week := {}
var expanded := {}
var course_cards: VBoxContainer
var tracks: HBoxContainer
var week_cards: VBoxContainer
var class_split: BoxContainer
var class_box: VBoxContainer
var difficulty: OptionButton
var start: Button
var replay_note: Label
var notice: Label
var outer: MarginContainer

func build(owner_game: Node) -> void:
	game = owner_game
	theme = ThemeFactory.create()
	_compact_buttons()
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	var background := ColorRect.new()
	background.color = Color("0b212e")
	background.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(background)
	outer = MarginContainer.new()
	outer.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		outer.add_theme_constant_override("margin_" + side, 24)
	add_child(outer)
	var frame := _panel(outer)
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 14)
	frame.add_child(page)
	_label(page, "START CLASS · "+classroom, 35)
	_label(page, "C O L L E G E   S I M U L A T O R", 13, T.ACCENT)

	class_box = VBoxContainer.new()
	class_box.size_flags_vertical = SIZE_EXPAND_FILL
	class_box.add_theme_constant_override("separation", 6)
	page.add_child(class_box)
	class_split = BoxContainer.new()
	class_split.size_flags_vertical = SIZE_EXPAND_FILL
	class_box.add_child(class_split)
	var course_panel := _panel(class_split)
	course_panel.custom_minimum_size.x = 315
	var courses := VBoxContainer.new()
	course_panel.add_child(courses)
	_label(courses, "Choose a course", 17)
	course_cards = _scroll_list(courses)
	var week_panel := _panel(class_split)
	week_panel.size_flags_horizontal = SIZE_EXPAND_FILL
	var schedule := VBoxContainer.new()
	week_panel.add_child(schedule)
	tracks = HBoxContainer.new()
	schedule.add_child(tracks)
	week_cards = _scroll_list(schedule)
	replay_note = _label(schedule, "", 13, GREEN)

	var class_footer := HBoxContainer.new()
	class_box.add_child(class_footer)
	_label(class_footer, "Difficulty", 14, T.MUTED, false)
	difficulty = OptionButton.new()
	difficulty.custom_minimum_size = Vector2(130, 34)
	class_footer.add_child(difficulty)
	for title in ["Beginner", "Easy", "Normal", "Hard", "Expert"]:
		difficulty.add_item(title)
	difficulty.select(2)

	notice = _label(page, "", 14, T.ERROR)
	notice.hide()
	page.add_child(HSeparator.new())
	var footer := HBoxContainer.new()
	page.add_child(footer)
	var back := _action(footer, "Back", "back", func(): closed.emit())
	back.size_flags_horizontal = SIZE_EXPAND_FILL
	back.custom_minimum_size.y = 50
	back.add_theme_font_size_override("font_size", 18)
	start = _action(footer, "Start Class", "play", _launch)
	start.theme_type_variation = "PrimaryButton"
	start.size_flags_horizontal = SIZE_EXPAND_FILL
	start.custom_minimum_size.y = 50
	start.add_theme_font_size_override("font_size", 18)

	resized.connect(_layout)
	model = Source.from_school(game.school, game.school.pending_gradebook_records())
	_render_courses()
	_render_weeks()
	_update_start()
	_layout()

func _layout() -> void:
	class_split.vertical = size.x < 720

func _render_courses() -> void:
	_clear(course_cards)
	for subject in model.groups:
		var open: bool = expanded.get(subject, true)
		var ids: Array = model.groups[subject]
		_action(course_cards, "%s %s (%d)" % ["▾" if open else "▸", subject, ids.size()], "folder",
			func(): expanded[subject] = not open; _render_courses())
		if not open:
			continue
		for id in ids:
			var info := _course(id)
			var grades: Dictionary = info.gradebook
			var caption := "%s · %s" % [id, info.display_name]
			var progress := _progress("Lecture", grades.tracks.lecture)
			if not info.tracks.lab.is_empty():
				progress += "   ·   " + _progress("Lab", grades.tracks.lab)
			var button := _action(course_cards, caption + "\n" + progress, "course", _pick_course.bind(id))
			button.theme_type_variation = "PrimaryButton" if id == selected_course else "Button"
			button.add_theme_font_size_override("font_size", 13)
			button.custom_minimum_size.y = 44
			button.clip_text = true

func _progress(label: String, rows: Array) -> String:
	var weeks := {}
	for row in rows:
		if row.week != null:
			weeks[row.week] = bool(weeks.get(row.week, true)) and row.completed
	return "%s %d/%d" % [label, weeks.values().count(true), weeks.size()]

func _course(id: String) -> Dictionary:
	for entry in model.courses:
		if entry.course_id == id:
			return entry
	return {}

func _pick_course(id: String) -> void:
	if selected_course == id:
		return
	selected_course = id
	var info := _course(id)
	selected_kind = "lecture" if not classroom.is_empty() or not info.tracks.lecture.is_empty() else "lab"
	selected_week = {}
	_render_courses()
	_render_weeks()
	_update_start()

func _render_weeks() -> void:
	_clear(tracks)
	_clear(week_cards)
	replay_note.hide()
	if selected_course.is_empty():
		_label(week_cards, "Choose a course to see its weeks.", 15, T.MUTED)
		return
	var info := _course(selected_course)
	for kind in ["lecture", "lab"]:
		if not classroom.is_empty() and kind!="lecture":continue
		if not info.tracks[kind].is_empty():
			var button := _action(tracks, "Lecture" if kind == "lecture" else "Laboratory", "course", _pick_track.bind(kind))
			button.custom_minimum_size = Vector2(132, 44)
			button.add_theme_font_size_override("font_size", 16)
			button.theme_type_variation = "PrimaryButton" if kind == selected_kind else "Button"
	for entry in info.tracks[selected_kind]:
		_week_card(int(entry.week), "", "Week %d · %s" % [entry.week, entry.title], "%s:%d" % [selected_kind, entry.week])
	for entry in game.school.official_extra_assessments(selected_course):
		if entry.kind == selected_kind:
			_week_card(int(entry.content_week), entry.id, entry.title, entry.id)
	if not selected_week.is_empty() and selected_week.completed:
		replay_note.text = "Replay — Your existing grade will be preserved."
		replay_note.show()

func _week_card(number: int, extra_id: String, caption: String, curriculum_id: String) -> void:
	var info := _course(selected_course)
	var result := {}
	for row in info.gradebook.rows:
		if row.id == curriculum_id:
			result = row
			break
	var complete: bool = result.get("completed", false)
	var state := "Not completed"
	if complete:
		state = "Completed · %.1f%%" % float(result.score)
	elif result.get("status") in ["in_progress", "submitted"]:
		state = str(result.status).replace("_", " ").capitalize()
	var config := {"week": number, "id": extra_id, "completed": complete, "curriculum": curriculum_id}
	var button := _action(week_cards, "%s    |    %s" % [caption, state], "check" if complete else "course", _pick_week.bind(config))
	button.theme_type_variation = "PrimaryButton" if selected_week.get("curriculum") == curriculum_id else "Button"
	button.custom_minimum_size.y = 34
	button.clip_text = true
	if complete:
		button.add_theme_color_override("font_color", GREEN)

func _pick_track(kind: String) -> void:
	if selected_kind != kind:
		selected_kind = kind
		selected_week = {}
		_render_weeks()
		_update_start()

func _pick_week(config: Dictionary) -> void:
	selected_week = config
	var scroll := week_cards.get_parent() as ScrollContainer
	var position := scroll.scroll_vertical
	_render_weeks()
	scroll.set_deferred("scroll_vertical", position)
	_update_start()

func _update_start() -> void:
	start.disabled = selected_week.is_empty()

func _launch() -> void:
	if start.disabled or not class_requested.is_valid():
		return
	start.disabled=true
	class_requested.call({"course_id":selected_course,"kind":selected_kind,"week":selected_week.week,"gradebook_assessment_id":selected_week.id,"difficulty":difficulty.selected})

func _error(value: String) -> void:
	notice.text = value
	notice.show()

func classroom_error(value: String) -> void:
	_error(value)
	_update_start()

func _panel(parent: Node) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", T.surface(Color("102938"), Color("315266"), 10))
	parent.add_child(panel)
	return panel

func _scroll_list(parent: Node) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = SIZE_EXPAND_FILL
	scroll.follow_focus = true
	parent.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 4)
	scroll.add_child(list)
	return list

func _compact_buttons() -> void:
	for variant in ["Button", "PrimaryButton"]:
		for state in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
			var style: StyleBoxFlat = theme.get_stylebox(state, variant).duplicate()
			style.set_content_margin_all(6)
			theme.set_stylebox(state, variant, style)

func _action(parent: Node, value: String, icon: String, callback: Callable) -> Button:
	var button := Widgets.action(value, icon, callback)
	button.custom_minimum_size.y = 35
	button.add_theme_font_size_override("font_size", 14)
	button.add_theme_constant_override("icon_max_width", 18)
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	parent.add_child(button)
	return button

func _label(parent: Node, value: String, font_size: int, ink := T.INK, expand := true) -> Label:
	var item := Widgets.text(value)
	item.add_theme_font_size_override("font_size", font_size)
	item.add_theme_color_override("font_color", ink)
	if not expand:
		item.size_flags_horizontal = SIZE_FILL
		item.autowrap_mode = TextServer.AUTOWRAP_OFF
	parent.add_child(item)
	return item

func _clear(parent: Node) -> void:
	for child in parent.get_children():
		parent.remove_child(child)
		child.queue_free()
