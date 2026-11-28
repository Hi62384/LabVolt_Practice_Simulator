extends SceneTree
const Exchange = preload("res://scripts/campus/ui/character_inspector_transport.gd")
var failures: Array[String] = []

func _initialize() -> void:
	var exchange := Exchange.new()
	var roster := {1: {}, 2: {}}
	_check(exchange.allow_request(2, 10000, roster, 1, "selection_a"), "Authenticated initial request should be admitted")
	_check(not exchange.allow_request(2, 10001, roster, 2, "selection_a"), "Snapshot requests must be rate limited")
	_check(not exchange.allow_request(2, 12000, roster, 1, "selection_a"), "Duplicate request serial must not be replayed")
	_check(not exchange.allow_request(99, 12000, roster, 1, "selection_a"), "Unconnected peer cannot obtain inspection state")
	_check(exchange.allow_request(2, 12000, roster, 2, "selection_a"), "Bounded later refresh should be admitted")
	var snapshot := {"available": true, "private_access": true, "selected_id": "mr_bro", "name": "Mr Bro", "personality_description": "Stored description", "life_history": [{"title": "Stored life section", "text": "A fictional life section."}], "mood": "steady", "phase": "freeplay", "relationship": {"friendship": 0.6}, "diagnostics": {"speech": "HOST_PRIVATE_TRANSCRIPT"}, "persistence": {"path": "HOST_PRIVATE_PATH"}, "api_key": "CREDENTIAL", "generation": {"status": "ready", "raw_request": "PRIVATE_REQUEST"}, "life_records": {"hobby": {"detail": "A fictional hobby", "evidence": "PRIVATE_EVIDENCE"}}, "relationship_events": [{"description": "Your own event", "raw_answer": "PRIVATE_ANSWER"}]}
	var packet := Exchange.public_packet(snapshot, "", "selection_a", 1)
	var serialized := JSON.stringify(packet)
	for forbidden in ["HOST_PRIVATE_TRANSCRIPT", "HOST_PRIVATE_PATH", "CREDENTIAL", "PRIVATE_REQUEST", "PRIVATE_EVIDENCE", "PRIVATE_ANSWER"]:
		_check(not forbidden in serialized, "Public packet leaked " + forbidden)
	_check(not packet.stable.is_empty(), "First packet must include identity")
	var accepted := Exchange.accept_packet(packet, "selection_a", 1, "mr_bro", {}, "")
	_check(accepted.get("snapshot", {}).get("relationship", {}).get("friendship") == 0.6, "Public packet must preserve actual relationship values")
	_check(not accepted.snapshot.private_access, "Transport cannot enable private host UI")
	_check(Exchange.accept_packet(packet, "selection_b", 1, "mr_bro", {}, "").is_empty(), "Response from a closed selection must be rejected")
	_check(Exchange.accept_packet(packet, "selection_a", 2, "mr_bro", {}, "").is_empty(), "Stale response serial must be rejected")
	_check(Exchange.accept_packet(packet, "selection_a", 1, "chad", {}, "").is_empty(), "A response must match the currently selected character")
	snapshot.mood = "angry"
	var delta := Exchange.public_packet(snapshot, packet.revision, "selection_a", 2)
	_check(delta.stable.is_empty(), "Unchanged life history must not be sent on every refresh")
	var refreshed := Exchange.accept_packet(delta, "selection_a", 2, "mr_bro", accepted.snapshot, accepted.revision)
	_check(refreshed.snapshot.mood == "angry" and refreshed.snapshot.personality_description == "Stored description", "Dynamic updates must preserve the existing identity")
	_check(Exchange.accept_packet(delta, "selection_a", 2, "mr_bro", {}, "").is_empty(), "Delta cannot be applied without its matching identity revision")
	snapshot.phase = "assignment"
	var assessment := Exchange.public_packet(snapshot, "", "selection_a", 3)
	_check(assessment.dynamic.relationship_events.is_empty(), "Private remembered answer text must not be exposed during an assessment")
	var invalidated := Exchange.public_packet({}, packet.revision, "selection_a", 4)
	var removed := Exchange.accept_packet(invalidated, "selection_a", 4, "mr_bro", accepted.snapshot, accepted.revision)
	_check(not removed.snapshot.available, "Losing proximity must invalidate the client view")
	snapshot.life_history = [{"text": "a".repeat(Exchange.MAX_PACKET_BYTES + 1)}]
	var oversized := Exchange.public_packet(snapshot, "", "selection_a", 5)
	_check(not oversized.dynamic.available and JSON.stringify(oversized).length() < 1000, "Oversized dossier packets must fail closed within the resource budget")
	roster.erase(2)
	exchange.allow_request(1, 14000, roster, 1, "host")
	_check(not exchange.recent.has(2), "Disconnected peer request state must be pruned")
	if failures.is_empty():
		print("CHARACTER_INSPECTOR_TRANSPORT PASS — bounded read packets, rate limits, static caching, replay/selection guards, privacy")
	quit(0 if failures.is_empty() else 1)

func _check(value: bool, message: String) -> void:
	if not value:
		failures.append(message)
		push_error(message)
