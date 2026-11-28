extends SceneTree
## Actual ENet peers and production faculty RPC handlers. Campus positioning and
## session identity are isolated fixtures; no AI response is mocked or asserted.
const Faculty = preload("res://scripts/campus/academics/faculty.gd")
const Store = preload("res://scripts/campus/academics/character_dossier_store.gd")
const ROOM := "elm253_lecture"
const PORT := 34848
var failures: Array[String] = []

class SchoolState extends Node:
	var local_identity := ""
	var identities: Dictionary = {}
	func formal_active() -> bool:
		return false

class SessionState extends Node:
	var roster: Dictionary = {}
	var online := true
	func peer_connected_now(peer: int) -> bool:
		return peer in multiplayer.get_peers()

class ClassState extends Node:
	var classes: Dictionary = {ROOM: {"teacher": "mr_bro", "phase": "lesson", "id": "inspection_class"}}
	var public_classes: Dictionary = classes.duplicate(true)
	var signs: Dictionary = {ROOM: {"desk": Vector3.ZERO}}
	var inside := true
	var position := Vector3(0, 0, 1)
	func _inside(_peer: int, room: String) -> bool:
		return inside and room == ROOM
	func _position(_peer: int) -> Vector3:
		return position

class FrontState extends RefCounted:
	var in_game := true

class BusyProvider extends Node:
	var busy := true
	var enabled := false

class TransportBarrier extends Node:
	var received := 0
	@rpc("any_peer", "call_remote", "reliable")
	func ping(serial: int) -> void:
		if multiplayer.is_server():
			pong.rpc_id(multiplayer.get_remote_sender_id(), serial)
	@rpc("authority", "call_remote", "reliable")
	func pong(serial: int) -> void:
		if multiplayer.get_remote_sender_id() == 1:
			received = serial

class GameState extends Node:
	var school := SchoolState.new()
	var session := SessionState.new()
	var lecture_classes := ClassState.new()
	var front := FrontState.new()
	var host_openai := BusyProvider.new()
	func _init() -> void:
		add_child(school)
		add_child(session)
		add_child(lecture_classes)
		add_child(host_openai)
	func release_mouse() -> void:
		pass
	func capture() -> void:
		pass

class SpeechState extends Node:
	var subtitle_layer := Control.new()
	func _init() -> void:
		add_child(subtitle_layer)

func _initialize() -> void:
	_run.call_deferred()

func _wait_for(check: Callable, label: String) -> bool:
	var deadline := Time.get_ticks_msec() + 7000
	while Time.get_ticks_msec() < deadline:
		if check.call():
			return true
		await create_timer(0.025).timeout
	_check(false, "Network wait timed out: " + label)
	return false

func _surface(name_value: String, api: MultiplayerAPI, identity: String) -> Dictionary:
	var branch := Node3D.new()
	branch.name = name_value
	root.add_child(branch)
	set_multiplayer(api, branch.get_path())
	var game := GameState.new()
	game.name = "Game"
	game.school.local_identity = identity
	branch.add_child(game)
	var faculty := Faculty.new()
	faculty.name = "Faculty"
	faculty.game = game
	branch.add_child(faculty)
	faculty.set_process(false)
	faculty._build_conversation_ui()
	faculty.speech_player = SpeechState.new()
	faculty.add_child(faculty.speech_player)
	var barrier := TransportBarrier.new()
	barrier.name = "TransportBarrier"
	branch.add_child(barrier)
	return {"branch": branch, "game": game, "faculty": faculty, "barrier": barrier}

func _flush_remote(client: Dictionary, serial: int) -> void:
	# All three nodes use ENet's same reliable channel. The acknowledged ping
	# proves the earlier production faculty RPCs were processed by the host.
	client.barrier.ping.rpc_id(1, serial)
	await _wait_for(func(): return client.barrier.received == serial, "reliable request barrier")

func _run() -> void:
	var server_peer := ENetMultiplayerPeer.new()
	var client_peer := ENetMultiplayerPeer.new()
	var server_error := server_peer.create_server(PORT, 1)
	var client_error := client_peer.create_client("127.0.0.1", PORT)
	if server_error != OK or client_error != OK:
		push_error("Unable to create isolated ENet inspector peers: %s / %s" % [server_error, client_error])
		quit(2)
		return
	var server_api := MultiplayerAPI.create_default_interface()
	var client_api := MultiplayerAPI.create_default_interface()
	server_api.multiplayer_peer = server_peer
	client_api.multiplayer_peer = client_peer
	var server := _surface("InspectorServer", server_api, "inspection_host")
	var client := _surface("InspectorClient", client_api, "inspection_guest")
	Store.host_identity = "inspection_host"
	server.faculty.brain._host_profile = "inspection_host"
	if not await _wait_for(func(): return client_api.get_unique_id() > 1 and not server_api.get_peers().is_empty(), "ENet connection"):
		quit(1)
		return
	var guest := client_api.get_unique_id()
	server.game.session.roster = {1: {}, guest: {}}
	client.game.session.roster = {1: {}, guest: {}}
	server.game.school.identities = {1: "inspection_host", guest: "inspection_guest"}
	client.game.school.identities = server.game.school.identities.duplicate(true)
	server.faculty.brain.relationships = {"mr_bro:inspection_guest": {"familiarity": 5, "episodes": [{"event_id": "guest_event", "event": "chat", "description": "Guest's own remembered exchange"}]}, "mr_bro:inspection_host": {"episodes": [{"event": "chat", "description": "HOST_PRIVATE_EXCHANGE"}]}}
	server.faculty.character_interaction.diagnostics.append({"character": "mr_bro", "speaker": "inspection_host", "speech": "HOST_PRIVATE_TRACE"})
	var before := JSON.stringify(server.faculty.brain.relationships)
	client.faculty.open_conversation(ROOM)
	if await _wait_for(func(): return int(client.faculty.conversation.get_meta("inspection_received", 0)) > 0, "host dossier packet"):
		var received: Dictionary = client.faculty.conversation.get_meta("inspection_snapshot", {})
		_check(received.get("available", false) and received.get("details_access", false), "Joining player must receive the selected public dossier")
		_check(received.get("name", "") == "Mr Bro", "Delivered identity must match production selected profile")
		_check(not received.get("private_access", true) and not received.has("diagnostics"), "Production network handler must withhold host diagnostics")
		_check(not "HOST_PRIVATE" in JSON.stringify(received), "Production network payload must not expose host conversations")
		_check(received.get("relationship_events", []).any(func(event): return event.get("description", "") == "Guest's own remembered exchange"), "Production network relationship must belong to the requesting guest")
		_check(before == JSON.stringify(server.faculty.brain.relationships) and server.faculty.brain.conversations.is_empty(), "Opening remote inspector must not create a social event or AI conversation")
		# The teacher can rotate between a snapshot refresh and a button press.
		# A queued message must never silently target the replacement person.
		client.game.lecture_classes.public_classes[ROOM].teacher = "chad"
		client.faculty.conversation_input.text = "Keep this unsent draft"
		client.faculty._submit_question()
		_check(client.faculty.conversation_input.text == "Keep this unsent draft" and client.faculty.ai_busy.is_empty(), "A stale teacher selection preserves the draft and sends no question")
		client.faculty._conversation_choice("help")
		_check(client.faculty.conversation_input.text == "Keep this unsent draft", "A stale teacher selection cannot submit a gameplay action")
		client.faculty.conversation_student = "student_fixture"
		client.faculty.conversation_class = "former_class"
		client.faculty.conversation.set_meta("selected_character_id", "student_fixture")
		_check(not client.faculty._selected_conversation_current(), "A departed student's class cannot receive a queued message")
		client.faculty.conversation_student = ""
		client.faculty.conversation_class = "inspection_class"
		client.faculty.conversation.set_meta("selected_character_id", "mr_bro")
		client.game.lecture_classes.public_classes[ROOM].teacher = "mr_bro"
		# The client still sees the selected teacher while the host has already
		# rotated the classroom. These calls exercise production outbound methods
		# and production RPC handlers, not a locally called queue substitute.
		var samples := PackedByteArray()
		samples.resize(32000)
		var wav: PackedByteArray = Faculty.TeacherAI.wav_16k(samples)
		server.game.lecture_classes.classes[ROOM].teacher = "chad"
		client.faculty.conversation_input.text = "Transit teacher mismatch"
		client.faculty._submit_question()
		client.faculty._send_voice_question(ROOM, wav, "", "inspection_class", "mr_bro")
		client.faculty._ask.rpc_id(1, ROOM, "hand_phone", "", "mr_bro", "inspection_class")
		client.faculty._send_lesson_feedback.rpc_id(1, ROOM, "ready", "mr_bro", "inspection_class")
		await _flush_remote(client, 1)
		_check(server.faculty.questions.is_empty() and server.faculty.ai_busy.is_empty() and server.faculty.last_dialogue.is_empty() and server.faculty.lesson_feedback.is_empty(), "Host rejects typed, microphone, action and lesson feedback requests after teacher rotation in transit")
		server.game.lecture_classes.classes[ROOM].teacher = "mr_bro"
		client.faculty.conversation_input.text = "Authenticated current target"
		client.faculty._submit_question()
		client.faculty._send_voice_question(ROOM, wav, "", "inspection_class", "mr_bro")
		await _flush_remote(client, 2)
		_check(server.faculty.questions.size() == 2 and server.faculty.questions.all(func(entry): return entry.teacher == "mr_bro" and entry.class == "inspection_class" and entry.peer == guest), "Valid typed and microphone requests retain the exact selected teacher, class and authenticated peer")
		_check(server.faculty.questions.any(func(entry): return entry.content is PackedByteArray) and server.faculty.questions.any(func(entry): return entry.content is String), "Real RPC transport preserves both supported input channels")
		server.game.lecture_classes.classes[ROOM].id = "rotated_class"
		client.faculty.conversation_input.text = "Transit class mismatch"
		client.faculty._submit_question()
		client.faculty._send_voice_question(ROOM, wav, "", "inspection_class", "mr_bro")
		client.faculty._ask_question.rpc_id(1, ROOM, "Missing target", "", "")
		client.faculty._ask_speech.rpc_id(1, ROOM, wav, "", "")
		await _flush_remote(client, 3)
		_check(server.faculty.questions.size() == 2, "Host rejects changed-class and empty-target requests before adding work")
		server.game.host_openai.busy = false
		server.faculty._next_question()
		server.faculty._next_question()
		_check(server.faculty.questions.is_empty() and server.faculty.ai_busy.is_empty(), "Queued typed and microphone requests are rejected again if the captured class changes before processing")
		server.game.lecture_classes.classes[ROOM].id = "inspection_class"
		server.game.host_openai.busy = true
		var initial_time := int(client.faculty.conversation.get_meta("inspection_received", 0))
		server.game.lecture_classes.position = Vector3(0, 0, 20)
		if await _wait_for(func(): return int(client.faculty.conversation.get_meta("inspection_received", 0)) > initial_time, "range-checked dynamic refresh"):
			var out_of_range: Dictionary = client.faculty.conversation.get_meta("inspection_snapshot", {})
			_check(not out_of_range.get("available", true), "Host must invalidate the inspector when the guest leaves interaction range")
	client.faculty.close_conversation()
	client_peer.close()
	server_peer.close()
	server.branch.queue_free()
	client.branch.queue_free()
	await process_frame
	if failures.is_empty():
		print("CHARACTER_INSPECTOR_NETWORK PASS — real ENet, production RPCs, authenticated guest history, selected-target transit guards, text/mic queue validation, range refresh, no model call")
	quit(0 if failures.is_empty() else 1)

func _check(value: bool, message: String) -> void:
	if not value:
		failures.append(message)
		push_error(message)
