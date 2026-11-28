extends SceneTree
## Real reader controls + authority/privacy boundary. Fixture dialogue is test
## data, never evidence of live model quality.
const Inspector = preload("res://scripts/campus/ui/character_inspector.gd")
const Snapshot = preload("res://scripts/campus/ui/character_inspector_snapshot.gd")
const Memory = preload("res://scripts/campus/academics/character_memory.gd")
var failures: Array[String] = []
var sends := 0
var recordings := 0

class SchoolFixture extends Node:
	var local_identity := "inspector_test_host"
	var identities: Dictionary = {1: "inspector_test_host", 2: "inspector_test_remote"}

class SessionFixture extends RefCounted:
	var roster: Dictionary = {1: {}, 2: {}}

class LectureFixture extends Node:
	var inside := true
	var position := Vector3(0, 0, 1)
	func _inside(_peer: int, _room: String) -> bool:
		return inside
	func _position(_peer: int) -> Vector3:
		return position

class GameFixture extends Node:
	var school: Node
	var session := SessionFixture.new()
	var lecture_classes := LectureFixture.new()

class MindFixture extends RefCounted:
	var moods: Dictionary = {}
	var disengagements: Dictionary = {}

class InteractionFixture extends RefCounted:
	var diagnostics: Array = []

class FacultyFixture extends Node:
	var game: Node
	var brain: RefCounted
	var character_mind := MindFixture.new()
	var character_interaction := InteractionFixture.new()
	var conversation_room := "ac_lab"
	var conversation_student := ""
	var conversation_class := ""
	func _ai_activity(_room: String) -> Dictionary:
		return {"teacher": "mr_bro", "phase": "freeplay"}
	func _teacher_position(_room: String) -> Vector3:
		return Vector3.ZERO

func _initialize() -> void:
	_run.call_deferred()

func _check(condition: bool, description: String) -> void:
	if not condition:
		failures.append(description)
		push_error(description)

func _run() -> void:
	var traces := [{"character": "mr_bro", "speaker": "inspector_test_host", "source": "ai", "duration_ms": 243, "request_count": 1, "usage": {"input": 1701, "output": 83, "cached": 1000}, "memory_recorded": true, "retrieved_context": {"compact_core": "Selected identity", "emotional_state": {"emotional_history": [{"description": "OTHER_PLAYER_PRIVATE"}]}, "beliefs": [{"position": "Test opinion", "history": [{"evidence": "OTHER_PLAYER_PRIVATE"}]}], "memories": [{"event": "chat", "description": "This player's remembered event"}], "prior_turns": [{"teacher": "ASSESSMENT_ANSWER"}], "api_key": "CREDENTIAL_VALUE"}, "interpretation": {"event": "greeting", "meaning": "A casual greeting"}}, {"character": "mr_bro", "speaker": "another_player", "source": "ai", "speech": "OTHER_PLAYER_PRIVATE"}, {"character": "chad", "speaker": "inspector_test_host", "speech": "ANOTHER_CHARACTER_PRIVATE"}]
	var own := Snapshot.selected_diagnostics(traces, "mr_bro", "inspector_test_host", "freeplay")
	_check(own.get("duration_ms") == 243, "Selected trace must match both character and local player")
	_check(own.get("usage", {}).get("input") == 1701, "Inspector must retain measured tokens exactly")
	var encoded := JSON.stringify(own)
	for excluded in ["OTHER_PLAYER_PRIVATE", "ANOTHER_CHARACTER_PRIVATE", "ASSESSMENT_ANSWER", "CREDENTIAL_VALUE"]:
		_check(not excluded in encoded, "Inspector leaked " + excluded)
	var assessment := Snapshot.selected_diagnostics(traces, "mr_bro", "inspector_test_host", "assignment")
	_check(assessment.get("assessment_redacted", false), "Assessment diagnostics must redact textual context")
	_check(not assessment.has("retrieved_context") and not assessment.has("interpretation"), "Assessment context must not be exposed")
	_check(not Snapshot.selected_diagnostics(traces, "mr_bro", "unknown", "freeplay").get("available", true), "Missing trace must not be represented as a completed AI response")
	var game := GameFixture.new()
	game.school = SchoolFixture.new()
	game.add_child(game.school)
	game.add_child(game.lecture_classes)
	root.add_child(game)
	var faculty := FacultyFixture.new()
	faculty.name = "InspectorFixture"
	faculty.game = game
	faculty.brain = Memory.new()
	faculty.brain._host_profile = "inspector_test_host"
	faculty.character_interaction.diagnostics = traces
	faculty.character_mind.moods = {"mr_bro": {"values": {"happiness": 0.8}, "history": [{"event_id": "private_other", "description": "OTHER_PLAYER_PRIVATE"}, {"event_id": "own_event", "description": "Own event", "event": "greeting"}]}}
	faculty.brain.relationships = {"mr_bro:inspector_test_host": {"familiarity": 1, "episodes": [{"event_id": "own_event", "event": "greeting", "description": "Own event"}]}}
	root.add_child(faculty)
	_check(Snapshot.can_inspect_private(faculty), "Matching local host must be authorized without launch flags")
	var before := JSON.stringify([faculty.brain.relationships, faculty.character_mind.moods, faculty.character_mind.disengagements, faculty.brain.memory_dirty, faculty.brain.conversations])
	var captured := Snapshot.capture(faculty)
	Snapshot.capture(faculty)
	_check(before == JSON.stringify([faculty.brain.relationships, faculty.character_mind.moods, faculty.character_mind.disengagements, faculty.brain.memory_dirty, faculty.brain.conversations]), "Opening/refreshing inspection must not mutate social, emotion, conversation or persistence state")
	_check(not "OTHER_PLAYER_PRIVATE" in JSON.stringify(captured), "Global mood history must not leak another player's event explanation")
	faculty.brain.relationships["mr_bro:inspector_test_remote"] = {"familiarity": 3, "episodes": [{"event_id": "remote_event", "event": "chat", "description": "Remote player's own event"}]}
	var remote := Snapshot.for_peer(faculty, 2, "ac_lab", "", "", "mr_bro")
	_check(remote.get("details_access", false) and not remote.get("private_access", true), "Authenticated nearby clients can inspect public dossier sections")
	_check(not remote.has("diagnostics") and not remote.has("persistence"), "Host-only traces and storage diagnostics must never be built for clients")
	_check(remote.get("relationship_events", []).any(func(event): return event.get("description") == "Remote player's own event"), "Remote relationship must use authenticated peer identity")
	_check(not "Own event" in JSON.stringify(remote), "Remote reader must not receive the host player's relationship history")
	_check(Snapshot.for_peer(faculty, 999, "ac_lab", "", "", "mr_bro").is_empty(), "Unknown network peer cannot inspect characters")
	_check(Snapshot.for_peer(faculty, 2, "ac_lab", "", "", "chad").is_empty(), "A stale or forged teacher selection must be rejected")
	game.lecture_classes.position = Vector3(0, 0, 10)
	_check(Snapshot.for_peer(faculty, 2, "ac_lab", "", "", "mr_bro").is_empty(), "Host must recheck proximity for every snapshot request")
	game.lecture_classes.position = Vector3(0, 0, 1)
	game.lecture_classes.inside = false
	_check(Snapshot.for_peer(faculty, 2, "ac_lab", "", "", "mr_bro").is_empty(), "Host must recheck actual room membership")
	game.lecture_classes.inside = true
	captured.emotions.happiness = 0.0
	_check(faculty.character_mind.moods.mr_bro.values.happiness == 0.8, "Inspector data must be detached from mutable authoritative state")
	game.school.local_identity = "wrong_profile"
	_check(not Snapshot.can_inspect_private(faculty), "Host profile switch must revoke private inspection immediately")
	var switched := Snapshot.capture(faculty)
	_check(not switched.get("private_access", true) and not switched.has("traits") and not switched.has("diagnostics"), "Unauthorized snapshot must contain public identity only")
	game.school.local_identity = "inspector_test_host"
	var client := ENetMultiplayerPeer.new()
	var client_error := client.create_client("127.0.0.1", 41193)
	_check(client_error == OK, "Create disconnected client for authority boundary")
	if client_error == OK:
		var remote_api := MultiplayerAPI.create_default_interface()
		remote_api.multiplayer_peer = client
		set_multiplayer(remote_api, faculty.get_path())
		_check(not Snapshot.can_inspect_private(faculty), "A network client cannot access host inspection even with matching profile string")
		_check(not Snapshot.capture(faculty).has("diagnostics"), "Data accessor must reject client diagnostics")
		set_multiplayer(null, faculty.get_path())
		client.close()
	var panel := Inspector.new()
	root.add_child(panel)
	panel.size = Vector2(1100, 680)
	panel.send_requested.connect(func(): sends += 1)
	panel.record_requested.connect(func(): recordings += 1)
	var display := Snapshot.capture(faculty)
	panel.configure(func(): return display)
	panel.open_character()
	panel.input.text = "Unsent draft"
	await process_frame
	for title in Inspector.PAGES:
		panel._select_page(title)
		panel.refresh()
		await process_frame
	_check(sends == 0 and recordings == 0, "Opening and navigating the inspector must not send messages or capture microphone audio")
	_check(panel.input.text == "Unsent draft", "Live state refresh must preserve unsent text")
	_check(Inspector._measured(null) == "Not recorded", "Missing telemetry must not be fabricated as zero")
	panel.apply_snapshot({"available": true, "private_access": false, "name": "Public character", "role": "student"})
	panel._select_page("Diagnostics")
	_check(panel._page == "Overview", "Clients must not open private tabs")
	panel.apply_snapshot(remote)
	panel._select_page("Personality")
	_check(panel._page == "Personality", "Host-shared public dossier should be readable by joining players")
	var existing_heading := panel.page_body.get_child(0)
	var changed_mood := remote.duplicate(true)
	changed_mood.mood = "angry"
	panel.apply_snapshot(changed_mood)
	_check(panel.page_body.get_child(0) == existing_heading, "A mood refresh must not rebuild an unchanged personality page")
	panel._select_page("Diagnostics")
	_check(panel._page == "Personality", "Public dossier sharing must not enable private diagnostics")
	panel.apply_snapshot({})
	_check(panel.send_button.disabled and not panel.input.editable, "A vanished character must disable message submission")
	panel.queue_free()
	faculty.queue_free()
	game.queue_free()
	await process_frame
	if failures.is_empty():
		print("CHARACTER_INSPECTOR PASS — authority, privacy, read-only state, real UI navigation and accurate telemetry")
	else:
		print("CHARACTER_INSPECTOR FAIL: ", failures)
	quit(0 if failures.is_empty() else 1)
