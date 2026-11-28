extends PanelContainer
## A selected-character reader with a persistent conversation composer. Refresh
## callbacks only read host state; opening a page never starts an AI request.
signal close_requested
signal send_requested
signal record_requested
signal action_requested(intent: String)

const ThemeFactory = preload("res://scripts/ui/design_system/theme.gd")
const PAGES := ["Overview", "Personality", "Life history", "Relationships", "Emotions", "Diagnostics"]
const PAGE_FIELDS := {
	"Overview": ["age", "role", "program", "persistent_status", "activity", "mood", "willingness", "access_note", "background", "physical_description", "relationship", "generation", "voice"],
	"Personality": ["personality_description", "speaking_description", "traits", "interests", "motivations", "values", "strengths", "weaknesses", "beliefs", "examples"],
	"Life history": ["life_history", "personal_information", "life_records", "knowledge"],
	"Relationships": ["willingness", "disengagement", "relationship", "reputation", "relationship_events"],
	"Emotions": ["mood", "emotion_state_source", "emotions", "emotional_history"],
	"Diagnostics": ["diagnostics", "persistence", "generation", "dossier_diagnostics", "population_diagnostics"],
}
const ACCENT := Color("94d4c4")
const MUTED := Color("9bb4c5")
var heading: Label
var subtitle: Label
var dialogue: Label
var input: LineEdit
var send_button: Button
var microphone_button: Button
var conversation_scroll: ScrollContainer
var action_buttons: Dictionary = {}
var page_buttons: Dictionary = {}
var page_scroll: ScrollContainer
var page_body: VBoxContainer
var _snapshot_provider: Callable
var _snapshot: Dictionary = {}
var _page := "Overview"
var _next_refresh := 0.0
var _signature := ""

func _init() -> void:
	theme = ThemeFactory.create()
	# This reader shares space with a composer. Keep controls comfortably sized
	# without the store theme's much larger padding forcing a 720px minimum.
	for type in ["Button", "PrimaryButton", "QuietButton", "DangerButton", "LineEdit"]:
		for state in ["normal", "hover", "pressed", "disabled", "hover_pressed", "read_only", "focus"]:
			if not theme.has_stylebox(state, type):
				continue
			var compact := theme.get_stylebox(state, type).duplicate() as StyleBox
			compact.content_margin_top = 6
			compact.content_margin_bottom = 6
			compact.content_margin_left = 10
			compact.content_margin_right = 10
			theme.set_stylebox(state, type, compact)
	var frame := ThemeFactory.card_style()
	frame.bg_color = Color("102331fa")
	frame.set_content_margin_all(14)
	add_theme_stylebox_override("panel", frame)
	_build()
	hide()

func configure(provider: Callable) -> void:
	_snapshot_provider = provider

func open_character() -> void:
	_page = "Overview"
	_signature = ""
	page_scroll.scroll_vertical = 0
	show()
	refresh()

func show_diagnostics() -> void:
	if not bool(_snapshot.get("private_access", false)):
		return
	_select_page("Diagnostics")

func _process(delta: float) -> void:
	if not visible:
		return
	_next_refresh -= delta
	if _next_refresh <= 0.0:
		_next_refresh = 0.8
		refresh()

func refresh() -> void:
	if not _snapshot_provider.is_valid():
		return
	var value: Variant = _snapshot_provider.call()
	if value is Dictionary:
		apply_snapshot(value)

func apply_snapshot(value: Dictionary) -> void:
	_snapshot = value.duplicate(true)
	var available := bool(_snapshot.get("available", false))
	heading.text = str(_snapshot.get("name", "Character no longer available"))
	if heading.text.is_empty():
		heading.text = "Character"
	var pieces: PackedStringArray = []
	for field in ["role", "program", "activity"]:
		var text_value := str(_snapshot.get(field, "")).replace("_", " ").strip_edges()
		if not text_value.is_empty():
			pieces.append(text_value.capitalize() if field == "role" else text_value)
	subtitle.text = "  ·  ".join(pieces) if available else "Close this panel and select someone nearby."
	input.editable = available
	send_button.disabled = not available
	microphone_button.disabled = not available
	for intent in action_buttons:
		action_buttons[intent].disabled = not available and intent != "bye"
	var private_access := bool(_snapshot.get("private_access", false))
	var details_access := bool(_snapshot.get("details_access", private_access))
	for title in PAGES:
		page_buttons[title].disabled = (title == "Diagnostics" and not private_access) or (title != "Overview" and not details_access)
		page_buttons[title].tooltip_text = "Available to the host" if title == "Diagnostics" and not private_access else ("Waiting for character details from the host" if title != "Overview" and not details_access else "")
	if (not details_access and _page != "Overview") or (_page == "Diagnostics" and not private_access):
		_page = "Overview"
	var signature := _page_fingerprint()
	if signature != _signature:
		_signature = signature
		_render_page()

func _build() -> void:
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 8)
	add_child(body)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 16)
	body.add_child(header)
	var title_column := VBoxContainer.new()
	title_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_column.add_theme_constant_override("separation", 2)
	header.add_child(title_column)
	heading = Label.new()
	heading.add_theme_font_size_override("font_size", 25)
	heading.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title_column.add_child(heading)
	subtitle = Label.new()
	subtitle.add_theme_color_override("font_color", MUTED)
	subtitle.add_theme_font_size_override("font_size", 14)
	subtitle.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title_column.add_child(subtitle)
	var close := Button.new()
	close.text = "Close"
	close.tooltip_text = "Close character panel (Esc)"
	close.pressed.connect(func(): close_requested.emit())
	header.add_child(close)
	body.add_child(HSeparator.new())
	var reading := HBoxContainer.new()
	reading.size_flags_vertical = Control.SIZE_EXPAND_FILL
	reading.add_theme_constant_override("separation", 18)
	body.add_child(reading)
	var navigation := VBoxContainer.new()
	navigation.custom_minimum_size.x = 140
	navigation.add_theme_constant_override("separation", 5)
	reading.add_child(navigation)
	var group := ButtonGroup.new()
	for title in PAGES:
		var button := Button.new()
		button.text = title
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.toggle_mode = true
		button.button_group = group
		button.custom_minimum_size.y = 36
		button.pressed.connect(_select_page.bind(title))
		navigation.add_child(button)
		page_buttons[title] = button
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	navigation.add_child(spacer)
	var refresh_note := Label.new()
	refresh_note.text = "Live character state\nRead-only inspection"
	refresh_note.add_theme_font_size_override("font_size", 12)
	refresh_note.add_theme_color_override("font_color", MUTED)
	navigation.add_child(refresh_note)
	page_scroll = ScrollContainer.new()
	page_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	page_scroll.follow_focus = true
	reading.add_child(page_scroll)
	page_body = VBoxContainer.new()
	page_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page_body.add_theme_constant_override("separation", 12)
	page_scroll.add_child(page_body)
	body.add_child(HSeparator.new())
	var dialogue_heading := Label.new()
	dialogue_heading.text = "Conversation"
	dialogue_heading.add_theme_font_size_override("font_size", 15)
	dialogue_heading.add_theme_color_override("font_color", ACCENT)
	body.add_child(dialogue_heading)
	conversation_scroll = ScrollContainer.new()
	conversation_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	conversation_scroll.custom_minimum_size.y = 44
	body.add_child(conversation_scroll)
	dialogue = Label.new()
	dialogue.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dialogue.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	dialogue.add_theme_font_size_override("font_size", 14)
	conversation_scroll.add_child(dialogue)
	var compose := HBoxContainer.new()
	body.add_child(compose)
	input = LineEdit.new()
	input.placeholder_text = "Say something…"
	input.max_length = 500
	input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	input.text_submitted.connect(func(_text: String): send_requested.emit())
	compose.add_child(input)
	send_button = Button.new()
	send_button.text = "Send"
	send_button.theme_type_variation = "PrimaryButton"
	send_button.pressed.connect(func(): send_requested.emit())
	compose.add_child(send_button)
	microphone_button = Button.new()
	microphone_button.text = "Mic"
	microphone_button.tooltip_text = "Record a spoken message"
	microphone_button.pressed.connect(func(): record_requested.emit())
	compose.add_child(microphone_button)
	var actions := ScrollContainer.new()
	actions.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	actions.follow_focus = true
	body.add_child(actions)
	var actions_row := HBoxContainer.new()
	actions_row.add_theme_constant_override("separation", 5)
	actions.add_child(actions_row)
	for option in [["Talk", "chat"], ["Ask for help", "help"], ["I'm ready", "ready"], ["Explain another way", "clarify"], ["Inspect circuit", "inspect_circuit"], ["Evaluate LED", "evaluate_led"], ["Hand over phone", "hand_phone"], ["Reclaim phone", "reclaim_phone"], ["Goodbye", "bye"]]:
		var button := Button.new()
		button.text = option[0]
		button.add_theme_font_size_override("font_size", 13)
		button.pressed.connect(func(): action_requested.emit(str(option[1])))
		actions_row.add_child(button)
		action_buttons[option[1]] = button

func _select_page(title: String) -> void:
	if title == "Diagnostics" and not bool(_snapshot.get("private_access", false)):
		return
	if title != "Overview" and not bool(_snapshot.get("details_access", _snapshot.get("private_access", false))):
		return
	_page = title
	_signature = _page_fingerprint()
	page_scroll.scroll_vertical = 0
	_render_page()

func _page_fingerprint() -> String:
	var content := {"page": _page, "available": _snapshot.get("available", false), "private_access": _snapshot.get("private_access", false), "details_access": _snapshot.get("details_access", false)}
	for field in PAGE_FIELDS.get(_page, []):
		if _snapshot.has(field):
			content[field] = _snapshot[field]
	return JSON.stringify(content).sha256_text()

func _render_page() -> void:
	var previous_scroll := page_scroll.scroll_vertical
	for child in page_body.get_children():
		page_body.remove_child(child)
		child.queue_free()
	for title in PAGES:
		page_buttons[title].set_pressed_no_signal(title == _page)
	_heading(_page)
	if not bool(_snapshot.get("available", false)):
		_paragraph("This character is no longer available in the current location.")
		return
	match _page:
		"Overview": _overview()
		"Personality": _personality()
		"Life history": _life_history()
		"Relationships": _relationships()
		"Emotions": _emotions()
		"Diagnostics": _diagnostics()
	page_scroll.set_deferred("scroll_vertical", previous_scroll)

func _overview() -> void:
	var age: Variant = _snapshot.get("age")
	var program := str(_snapshot.get("program", ""))
	_rows({"Age": str(age) if age != null else "Not shared", "Role / program": program if not program.is_empty() else str(_snapshot.get("role", "")), "Current activity": _snapshot.get("activity", ""), "Mood": _snapshot.get("mood", "Not observed"), "Conversation": _snapshot.get("willingness", "Not shared")})
	if _snapshot.has("persistent_status"):
		_rows({"Persistent student":str(_snapshot.persistent_status).replace("_"," ").capitalize()})
	if not bool(_snapshot.get("details_access", _snapshot.get("private_access", false))):
		_paragraph(str(_snapshot.get("access_note", "")), true)
		return
	_section("Background", _snapshot.get("background", ""))
	_section("Appearance", _snapshot.get("physical_description", ""))
	_section("Relationship with you", _relationship_summary())
	var generation: Dictionary = _snapshot.get("generation", {})
	if not generation.is_empty():
		_section("Identity status", str(generation.get("status", "Not recorded")).replace("_", " ").capitalize())
	var voice: Dictionary = _snapshot.get("voice", {})
	_section("Vocal identity", voice.get("characteristics", voice.get("profile", "")))

func _personality() -> void:
	_section("Personality", _snapshot.get("personality_description", ""))
	_section("Speaking style", _snapshot.get("speaking_description", ""))
	for field in ["interests", "motivations", "values", "strengths", "weaknesses"]:
		_section(field.capitalize(), _snapshot.get(field, []))
	_section("Current beliefs", _snapshot.get("beliefs", []))
	_heading("Personality values", 18)
	_meters(_snapshot.get("traits", {}))
	var examples: Array = _snapshot.get("examples", [])
	if not examples.is_empty():
		_heading("Speaking references", 18)
		_paragraph("These are style examples, not replies selected by the game.", true)
		for example in examples:
			if not example is Dictionary:
				continue
			_section("%s · %s" % [str(example.get("situation", "Conversation")).capitalize(), str(example.get("mood", "neutral"))], "You: %s\n%s" % [str(example.get("prompt", "")), str(example.get("reply", ""))])

func _life_history() -> void:
	var sections: Array = _snapshot.get("life_history", [])
	if sections.is_empty():
		_paragraph("The expanded life history has not been generated yet. Existing personal information is preserved below.", true)
	for section in sections:
		if not section is Dictionary:
			continue
		_section(str(section.get("title", section.get("id", "Personal history"))), section.get("text", ""))
	_heading("Established fictional information", 18)
	var information: Dictionary = _snapshot.get("personal_information", {})
	if information.is_empty():
		_paragraph("No additional personal details have been established.", true)
	else:
		for key in information:
			_section(str(key).replace("_", " ").replace(".", " / ").capitalize(), information[key])
	_section("Developed fictional memories", _snapshot.get("life_records", []))
	_section("Education and knowledge", _snapshot.get("knowledge", {}))

func _relationships() -> void:
	_paragraph("This page shows this character's relationship with you. Other players' conversations are private.", true)
	_section("Conversation decision", _snapshot.get("willingness", "Not recorded"))
	var disengagement: Dictionary = _snapshot.get("disengagement", {})
	if not disengagement.is_empty():
		_rows({"Silent": str(bool(disengagement.get("quiet", false))), "Persistent state": str(disengagement.get("disengagement", "None")).replace("_", " "), "Reason": str(disengagement.get("reason", "Not recorded"))})
	_heading("Relationship values", 18)
	_meters(_snapshot.get("relationship", {}))
	_heading("Your reputation with this character", 18)
	_meters(_snapshot.get("reputation", {}))
	_heading("Significant experiences together", 18)
	_events(_snapshot.get("relationship_events", []))

func _emotions() -> void:
	_section("Current dominant mood", str(_snapshot.get("mood", "Not recorded")).capitalize())
	_paragraph(str(_snapshot.get("emotion_state_source", "")), true)
	_meters(_snapshot.get("emotions", {}))
	_heading("Recent changes involving you", 18)
	_events(_snapshot.get("emotional_history", []))

func _diagnostics() -> void:
	if not bool(_snapshot.get("private_access", false)):
		return
	_paragraph("Host diagnostics for this character and your conversations. Values are recorded by the running game.", true)
	var trace: Dictionary = _snapshot.get("diagnostics", {})
	var persistence: Dictionary = _snapshot.get("persistence", {})
	_rows({"Persistence": persistence.get("persistence_state", "Not recorded"), "Last save": _timestamp(persistence.get("last_saved_at", 0)), "Save error": persistence.get("last_error", "Not recorded")})
	if _snapshot.get("population_diagnostics") is Dictionary:
		_section("Persistent student", _snapshot.population_diagnostics)
	_section("Identity generation", _snapshot.get("generation", {}))
	_section("Generation and dossier storage", _snapshot.get("dossier_diagnostics", {}))
	if not bool(trace.get("available", false)):
		_paragraph("No completed interaction with you has been recorded in this session.", true)
		return
	var usage: Dictionary = trace.get("usage", {})
	var timing: Dictionary = trace.get("timing", {})
	_rows({"Response source": trace.get("source", "Not recorded"), "AI generated": "Yes" if trace.get("source", "") == "ai" else "No", "Fallback / failure reason": _or_none(trace.get("fallback_reason", "")), "Delivered": str(trace.get("delivered", false)), "Memory committed": _measured(trace.get("memory_recorded")), "Input channel": timing.get("input_kind", "Not recorded"), "Host receipt → reply ready": _measured(timing.get("host_to_text_ms"), " ms"), "Host queue wait": _measured(timing.get("queue_wait_ms"), " ms"), "Transcription": _measured(timing.get("transcription_ms"), " ms"), "Character processing": _measured(trace.get("duration_ms"), " ms"), "Host receipt → audio ready": _measured(timing.get("host_to_audio_ready_ms"), " ms"), "Host receipt → local playback": _measured(timing.get("host_to_playback_started_ms"), " ms"), "Retrieval latency": _measured(trace.get("retrieval_ms"), " ms"), "AI requests": _measured(trace.get("request_count")), "Actual input tokens": _measured(usage.get("input", usage.get("input_tokens"))), "Actual output tokens": _measured(usage.get("output", usage.get("output_tokens"))), "Cached input tokens": _measured(usage.get("cached", usage.get("cached_tokens"))), "Behavioral intention": trace.get("strategy", "Not recorded")})
	_paragraph("Timings start when the host receives the request. Client upload, remote playback, and audio-device buffering are not measured here.", true)
	if trace.get("assessment_redacted", false):
		_paragraph("Context and memory text are hidden during an assessment.", true)
		return
	_section("Decision reason", trace.get("reason", ""))
	_section("Message interpretation", trace.get("interpretation", {}))
	_section("Selected character context", trace.get("retrieved_context", {}))
	_section("Retrieved memories", trace.get("retrieved_memories", []))
	_section("Selected dialogue examples", trace.get("selected_examples", []))

func _relationship_summary() -> String:
	var relation: Dictionary = _snapshot.get("relationship", {})
	if relation.is_empty():
		return "No relationship information recorded."
	var parts: PackedStringArray = []
	for key in ["familiarity", "liking", "trust", "respect", "friendship", "resentment"]:
		if relation.has(key):
			parts.append("%s %d%%" % [key.capitalize(), roundi(float(relation[key]) * 100.0)])
	return "  ·  ".join(parts)

func _heading(text_value: String, font_size := 20) -> void:
	var label := Label.new()
	label.text = text_value
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", ACCENT)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	page_body.add_child(label)

func _paragraph(text_value: String, muted := false) -> void:
	if text_value.strip_edges().is_empty():
		return
	var label := Label.new()
	label.text = text_value
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_font_size_override("font_size", 14)
	if muted:
		label.add_theme_color_override("font_color", MUTED)
	page_body.add_child(label)

func _section(title: String, value: Variant) -> void:
	var content := _readable(value)
	if content.strip_edges().is_empty():
		return
	var card := PanelContainer.new()
	var style := ThemeFactory.card_style()
	style.bg_color = Color("152d3b")
	style.set_content_margin_all(12)
	card.add_theme_stylebox_override("panel", style)
	page_body.add_child(card)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 5)
	card.add_child(column)
	var title_label := Label.new()
	title_label.text = title
	title_label.add_theme_font_size_override("font_size", 14)
	title_label.add_theme_color_override("font_color", ACCENT)
	title_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(title_label)
	var content_label := Label.new()
	content_label.text = content
	content_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content_label.add_theme_font_size_override("font_size", 14)
	column.add_child(content_label)

func _rows(values: Dictionary) -> void:
	for key in values:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		page_body.add_child(row)
		var title := Label.new()
		title.text = str(key)
		title.custom_minimum_size.x = 165
		title.add_theme_font_size_override("font_size", 14)
		title.add_theme_color_override("font_color", MUTED)
		row.add_child(title)
		var value := Label.new()
		value.text = _readable(values[key])
		value.add_theme_font_size_override("font_size", 14)
		value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		value.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		row.add_child(value)

func _meters(values: Dictionary) -> void:
	if values.is_empty():
		_paragraph("No values recorded.", true)
		return
	var keys: Array = values.keys()
	keys.sort()
	for key in keys:
		if not (values[key] is float or values[key] is int):
			continue
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		page_body.add_child(row)
		var label := Label.new()
		label.text = str(key).replace("_", " ").capitalize()
		label.add_theme_font_size_override("font_size", 14)
		label.custom_minimum_size.x = 170
		row.add_child(label)
		var meter := ProgressBar.new()
		meter.max_value = 1.0
		meter.value = clampf(float(values[key]), 0.0, 1.0)
		meter.show_percentage = false
		meter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		meter.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		meter.custom_minimum_size.y = 7
		var fill := StyleBoxFlat.new()
		fill.bg_color = Color("70bba9")
		fill.set_corner_radius_all(4)
		meter.add_theme_stylebox_override("fill", fill)
		var background := fill.duplicate() as StyleBoxFlat
		background.bg_color = Color("244350")
		meter.add_theme_stylebox_override("background", background)
		row.add_child(meter)
		var number := Label.new()
		number.text = "%0.2f" % float(values[key])
		number.custom_minimum_size.x = 38
		number.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		number.add_theme_font_size_override("font_size", 14)
		row.add_child(number)

func _events(events: Array) -> void:
	if events.is_empty():
		_paragraph("No relevant events recorded.", true)
		return
	for index in range(events.size() - 1, -1, -1):
		var event: Variant = events[index]
		if event is Dictionary:
			_section(str(event.get("event", event.get("kind", "Experience"))).replace("_", " ").capitalize() + " · " + _timestamp(event.get("at", 0)), event.get("description", event.get("emotion", "Recorded event")))

static func _timestamp(value: Variant) -> String:
	if not (value is int or value is float) or int(value) <= 0:
		return "Not recorded"
	return Time.get_datetime_string_from_unix_time(int(value)).replace("T", " ") + " UTC"

static func _measured(value: Variant, suffix := "") -> String:
	return "Not recorded" if value == null else str(value) + suffix

static func _or_none(value: Variant) -> String:
	return "None" if str(value).is_empty() else str(value)

static func _readable(value: Variant, depth := 0) -> String:
	if value == null:
		return "Not recorded"
	if value is String:
		return value
	if value is Dictionary:
		var lines: PackedStringArray = []
		for key in value:
			if value[key] is Dictionary or value[key] is Array:
				lines.append(str(key).replace("_", " ").capitalize() + ":\n" + _readable(value[key], depth + 1))
			else:
				lines.append(str(key).replace("_", " ").capitalize() + ": " + _readable(value[key], depth + 1))
		return "\n".join(lines)
	if value is Array:
		var parts: PackedStringArray = []
		for item in value:
			parts.append(_readable(item, depth + 1))
		return ("\n\n" if value.any(func(item): return item is Dictionary) else " · ").join(parts)
	return str(value)
