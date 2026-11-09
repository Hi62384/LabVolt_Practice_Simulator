extends Control
signal closed

const GradebookTheme = preload("res://scripts/ui/design_system/theme.gd")
const Widgets = preload("res://scripts/ui/design_system/widgets.gd")
const T = preload("res://scripts/ui/design_system/tokens.gd")
const Source = preload("res://scripts/campus/ui/gradebook_source.gd")
const GREEN := Color("a3edaa")
const EDGE := Color("315266")
var school: Node
var model: Dictionary
var selected := ""
var expanded := {}
var open_weeks := {}
var pending := {}
var detail: VBoxContainer
var courses: VBoxContainer
var layout: BoxContainer
var sidebar: PanelContainer
var course_scroll: ScrollContainer
var table_scroll: ScrollContainer
var summary: HBoxContainer

func build(source: Node) -> void:
	school = source
	theme = GradebookTheme.create()
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	var shade := ColorRect.new()
	shade.color = Color("0a1e2a")
	shade.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(shade)
	var frame := MarginContainer.new()
	frame.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	for edge in ["left", "right", "top", "bottom"]:
		frame.add_theme_constant_override("margin_" + edge, 14)
	add_child(frame)
	layout = BoxContainer.new()
	layout.add_theme_constant_override("separation", 10)
	frame.add_child(layout)
	sidebar = _panel(layout, Color("102936"), 14)
	var nav := VBoxContainer.new()
	sidebar.add_child(nav)
	var heading := HBoxContainer.new()
	nav.add_child(heading)
	_label(heading, "View Courses", 27)
	var back := _button("Back", "back", func(): closed.emit())
	heading.add_child(back)
	course_scroll = _scroll(nav)
	courses = VBoxContainer.new()
	courses.size_flags_horizontal = SIZE_EXPAND_FILL
	courses.add_theme_constant_override("separation", 5)
	course_scroll.add_child(courses)

	var content := _panel(layout, Color("0d2432"), 12)
	content.size_flags_horizontal = SIZE_EXPAND_FILL
	content.size_flags_vertical = SIZE_EXPAND_FILL
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 9)
	content.add_child(column)
	table_scroll = _scroll(column)
	detail = VBoxContainer.new()
	detail.size_flags_horizontal = SIZE_EXPAND_FILL
	detail.add_theme_constant_override("separation", 11)
	table_scroll.add_child(detail)
	var footer := _panel(column, Color("14363e"), 8)
	summary = HBoxContainer.new()
	footer.add_child(summary)

	resized.connect(_reflow)
	school.academic_records_changed.connect(_reload, CONNECT_DEFERRED)
	school.updated.connect(_check_pending)
	_reflow()
	_reload()

func _reflow() -> void:
	layout.vertical = size.x < 790
	sidebar.custom_minimum_size.x = 0 if layout.vertical else 280
	course_scroll.custom_minimum_size.y = 110 if layout.vertical else 0

func _check_pending() -> void:
	if is_inside_tree() and school.pending_gradebook_records() != pending:
		_reload()

func _reload() -> void:
	if not is_inside_tree():
		return
	pending = school.pending_gradebook_records()
	model = Source.from_school(school, pending)
	if _course(selected).is_empty() and not model.courses.is_empty():
		selected = model.courses.front().course_id
	var position := table_scroll.scroll_vertical
	_refresh_courses()
	_refresh_detail()
	table_scroll.set_deferred("scroll_vertical", position)

func _course(id: String) -> Dictionary:
	for row in model.courses:
		if row.course_id == id:
			return row
	return {}

func _select(id: String) -> void:
	if id == selected:
		return
	selected = id
	_refresh_courses()
	_refresh_detail()
	table_scroll.scroll_vertical = 0

func _refresh_courses() -> void:
	_clear(courses)
	_label(courses, "Choose a course", 16, T.MUTED)
	for subject in model.groups:
		var ids: Array = model.groups[subject]
		var open: bool = expanded.get(subject, true)
		var group := _button("%s %s (%d)" % ["▾" if open else "▸", subject, ids.size()],
			"folder", func(): expanded[subject] = not open; _refresh_courses())
		courses.add_child(group)
		if open:
			for id in ids:
				var course := _course(id)
				var button := _button(_title(course), "course", _select.bind(id), selected == id)
				courses.add_child(button)
	var recent: Array = model.recent_attendance
	if not recent.is_empty():
		courses.add_child(HSeparator.new())
		_label(courses, "Recently attended", 15)
		for entry in recent.slice(0, 3):
			var id: String = entry.course_id
			var button := _button(_title(_course(id)), "clock", _select.bind(id))
			button.tooltip_text += " · " + str(entry.time).get_slice("T", 0)
			courses.add_child(button)

func _refresh_detail() -> void:
	_clear(detail)
	_clear(summary)
	var course := _course(selected)
	if course.is_empty():
		_label(detail, "No courses available", 20)
		return
	var grade: Dictionary = course.gradebook
	var header := HBoxContainer.new()
	detail.add_child(header)
	var intro := VBoxContainer.new()
	intro.size_flags_horizontal = SIZE_EXPAND_FILL
	intro.add_theme_constant_override("separation", 4)
	header.add_child(intro)
	_label(intro, _title(course), 26)
	var has_labs: bool = not course.tracks.lab.is_empty()
	var meta := "%s  ·  %s" % [course.subject, "Lecture + Laboratory" if has_labs else "Lecture"]
	_label(intro, meta, 14, T.ACCENT)
	if not course.description.is_empty():
		_label(intro, course.description, 14, T.MUTED)
	var average := _panel(header, Color("163341"), 10)
	average.custom_minimum_size.x = 154
	average.size_flags_vertical = SIZE_SHRINK_BEGIN
	var average_column := VBoxContainer.new()
	average_column.add_theme_constant_override("separation", 3)
	average.add_child(average_column)
	_label(average_column, "CURRENT AVERAGE", 12, T.MUTED)
	var mark: Variant = grade.current_average
	var empty_mark := "Weight not configured" if grade.rows.any(func(row): return row.completed) else "Not graded yet"
	_label(average_column, empty_mark if mark == null else _percent(mark), 15 if mark == null else 28, T.MUTED if mark == null else GREEN)

	var weekly := {"lecture": {}, "lab": {}}
	var extras: Array = []
	var weeks := {}
	for row in grade.rows:
		if row.week == null:
			extras.append(row)
			continue
		var number := int(row.week)
		var track: Dictionary = weekly[row.kind]
		if not track.has(number):
			track[number] = []
		track[number].append(row)
		weeks[number] = bool(weeks.get(number, true)) and row.completed
	var complete_weeks := weeks.values().count(true)
	var progress := "Course Completed" if grade.complete else "Course Progress  ·  %d / %d weeks" % [complete_weeks, weeks.size()]
	_label(detail, progress, 15, GREEN if grade.complete else T.INK)
	if not grade.policy_valid:
		_label(detail, "Weight not configured or grading weights do not total correctly.", 13, T.MUTED)
	_track("Lecture", weekly.lecture)
	if has_labs:
		_track("Laboratory", weekly.lab)
	if not extras.is_empty():
		_track("Other assessments", {}, extras)

	var recorded: Array = grade.unmatched_records
	if not recorded.is_empty():
		_label(detail, "Recorded results without a confirmed assessment match", 16)
		for record in recorded:
			_label(detail, "%s   ·   %s" % [record.get("title", record.get("assessment_id", "Assessment")), _percent(record.get("score"), "Not available")], 14, T.MUTED)
	if not grade.historical_records.is_empty():
		_label(detail, "%d historical results retained. The gradebook uses the original mark for each assessment." % grade.historical_records.size(), 13, T.MUTED)

	_metric("Graded weight", _percent(grade.completed_weight) if grade.policy_valid else "—")
	_metric("Earned final-grade points", _points(grade.earned_final_points))
	_metric("Final Grade", _percent(grade.final_mark, "Not yet determined"), grade.final_mark != null)

func _track(title: String, weeks: Dictionary, extras: Array = []) -> void:
	if weeks.is_empty() and extras.is_empty():
		return
	var card := _panel(detail, Color("112b39"), 0)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 0)
	card.add_child(column)
	var heading := _band(column, Color("102936"), 8)
	_label(heading, title, 17)
	var done := 0
	for entries in weeks.values():
		if entries.all(func(row): return row.completed):
			done += 1
	if not weeks.is_empty():
		_label(heading, "%d / %d weeks complete" % [done, weeks.size()], 13, T.MUTED, 0)
	_cells(column, ["Week", "Topic / Assessment", "Mark", "Final Weight", "Contribution", "Status"], Color("1c3a49"), T.MUTED)
	var index := 0
	for week in weeks:
		var entries: Array = weeks[week]
		var first: Dictionary = entries.front()
		var background := Color("132e3e") if index % 2 == 0 else Color("102735")
		index += 1
		if entries.size() == 1:
			_assessment(column, "W%d" % week, first, background)
			continue
		var key := "%s/%s/%d" % [selected, first.kind, week]
		var all_graded := entries.all(func(row): return row.completed)
		var row := _cells(column, ["W%d" % week, first.title, "—", "—", "—", "Graded" if all_graded else "%d assessments" % entries.size()], background)
		var parts := VBoxContainer.new()
		parts.add_theme_constant_override("separation", 0)
		column.add_child(parts)
		parts.visible = bool(open_weeks.get(key, false))
		for assessment in entries:
			_assessment(parts, "", assessment, Color("19394a"))
		var toggle := _button("−" if parts.visible else "+", "", Callable())
		toggle.tooltip_text = "Show or hide assessments for week %d" % week
		toggle.custom_minimum_size.y = 22
		row.get_child(0).add_child(toggle)
		toggle.pressed.connect(func():
			parts.visible = not parts.visible
			open_weeks[key] = parts.visible
			toggle.text = "−" if parts.visible else "+")
	for assessment in extras:
		_assessment(column, "—", assessment, Color("132e3e"))

func _assessment(parent: Node, week: String, row: Dictionary, background: Color) -> void:
	var cells := _cells(parent, [week, row.title, _percent(row.score),
		_percent(row.weight, "Weight not configured"), _points(row.weighted_points),
		str(row.status).replace("_", " ").capitalize()], background)
	if row.completed:
		for index in [2, 4, 5]:
			cells.get_child(index).add_theme_color_override("font_color", GREEN)

func _cells(parent: Node, values: Array, background: Color, ink := T.INK) -> HBoxContainer:
	var row := _band(parent, background, 5)
	for index in values.size():
		if index == 0:
			var week := HBoxContainer.new()
			week.custom_minimum_size.x = 58
			week.add_theme_constant_override("separation", 3)
			row.add_child(week)
			_label(week, values[index], 13, ink, 0)
		else:
			_label(row, values[index], 13, ink, [58, -1, 49, 91, 88, 84][index])
	return row

func _metric(title: String, value: String, highlight := false) -> void:
	var column := VBoxContainer.new()
	column.size_flags_horizontal = SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 2)
	summary.add_child(column)
	_label(column, title, 12, T.MUTED)
	_label(column, value, 17, GREEN if highlight else T.INK)

func _panel(parent: Node, fill: Color, padding: int) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", T.surface(fill, EDGE, padding))
	parent.add_child(panel)
	return panel

func _band(parent: Node, fill: Color, padding: int) -> HBoxContainer:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.set_content_margin_all(padding)
	style.content_margin_left = 10
	style.content_margin_right = 10
	panel.add_theme_stylebox_override("panel", style)
	parent.add_child(panel)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	panel.add_child(row)
	return row

func _scroll(parent: Node) -> ScrollContainer:
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = SIZE_EXPAND_FILL
	parent.add_child(scroll)
	return scroll

func _label(parent: Node, value: String, font_size: int, ink := T.INK, width := -1) -> Label:
	var label := Widgets.text(value)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", ink)
	if width >= 0:
		label.custom_minimum_size.x = width
		label.size_flags_horizontal = SIZE_FILL
		if width == 0:
			label.autowrap_mode = TextServer.AUTOWRAP_OFF
	parent.add_child(label)
	return label

func _button(value: String, icon: String, callback: Callable, active := false) -> Button:
	var button := Widgets.action(value, icon, callback)
	if icon.is_empty():
		button.icon = null
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.clip_text = not icon.is_empty() and icon != "back"
	button.custom_minimum_size.y = 32
	button.add_theme_font_size_override("font_size", 13)
	button.add_theme_constant_override("icon_max_width", 17)
	for state in ["normal", "hover", "pressed", "hover_pressed"]:
		var fill := Color("143444") if state == "normal" else Color("204959")
		if active:
			fill = Color("22594f") if state == "normal" else Color("2c6a60")
		button.add_theme_stylebox_override(state, T.surface(fill, T.ACCENT if active else EDGE, 6))
	return button

func _clear(parent: Node) -> void:
	for child in parent.get_children():
		parent.remove_child(child)
		child.queue_free()

func _title(course: Dictionary) -> String:
	return "%s · %s" % [course.course_id, course.display_name]

func _percent(value: Variant, fallback := "—") -> String:
	if not (value is int or value is float) or not is_finite(float(value)):
		return fallback
	return ("%0.2f" % float(value)).rstrip("0").trim_suffix(".") + "%"

func _points(value: Variant) -> String:
	return "—" if value == null else "%.2f pts" % float(value)
