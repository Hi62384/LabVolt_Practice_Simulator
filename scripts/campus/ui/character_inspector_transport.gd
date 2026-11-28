extends RefCounted
## Bounded public read packets, independent of dialogue and model requests.
const MAX_PACKET_BYTES := 196608
const MIN_REQUEST_MS := 1000
const STATIC_FIELDS := ["selected_id", "name", "role", "age", "program", "background", "physical_description", "personality_description", "speaking_description", "traits", "motivations", "values", "interests", "strengths", "weaknesses", "beliefs", "life_history", "personal_information", "voice", "knowledge", "examples", "generation", "life_records"]
const DYNAMIC_FIELDS := ["available", "activity", "mood", "room", "phase", "emotions", "emotion_state_source", "emotional_history", "relationship", "reputation", "relationship_events", "disengagement", "willingness", "persistent_status"]
var recent: Dictionary = {}

func allow_request(peer: int, now: int, roster: Dictionary, serial: int, nonce: String) -> bool:
	for previous in recent.keys():
		if not roster.has(previous):
			recent.erase(previous)
	if not roster.has(peer) or peer <= 0 or serial <= 0 or nonce.is_empty() or nonce.length() > 64:
		return false
	var previous: Dictionary = recent.get(peer, {})
	if now - int(previous.get("at", -MIN_REQUEST_MS)) < MIN_REQUEST_MS:
		return false
	if str(previous.get("nonce", "")) == nonce and serial <= int(previous.get("serial", 0)):
		return false
	if not recent.has(peer) and recent.size() >= 64:
		return false
	recent[peer] = {"at": now, "serial": serial, "nonce": nonce}
	return true

static func public_packet(snapshot: Dictionary, known_revision: String, nonce: String, serial: int) -> Dictionary:
	var stable: Dictionary = {}
	var dynamic: Dictionary = {"private_access": false, "details_access": bool(snapshot.get("available", false))}
	for field in STATIC_FIELDS:
		if snapshot.has(field):
			stable[field] = snapshot[field]
	for field in DYNAMIC_FIELDS:
		if snapshot.has(field):
			dynamic[field] = snapshot[field]
	dynamic.available = bool(snapshot.get("available", false))
	if stable.get("generation") is Dictionary:
		stable.generation = {"status": str(stable.generation.get("status", "")), "source": str(stable.generation.get("source", ""))}
	# Only fictional life records are shareable. Their supporting conversation
	# evidence and other internal metadata are never transmitted.
	if stable.get("life_records") is Dictionary:
		var records: Dictionary = {}
		for key in stable.life_records.keys().slice(-96):
			var value: Variant = stable.life_records[key]
			if value is Dictionary:
				records[key] = {}
				for field in ["detail", "kind", "status", "provenance", "chronology", "valid_from", "valid_until", "topics", "entities"]:
					if value.has(field):
						records[key][field] = value[field]
		stable.life_records = records
	if stable.get("personal_information") is Dictionary and stable.personal_information.size() > 96:
		var details: Dictionary = {}
		for key in stable.personal_information.keys().slice(-96):
			details[key] = stable.personal_information[key]
		stable.personal_information = details
	for field in ["relationship_events", "emotional_history"]:
		var events: Array = []
		if str(snapshot.get("phase", "")) != "assignment":
			for value in snapshot.get(field, []):
				if value is Dictionary:
					var event: Dictionary = {}
					for key in ["event", "description", "at", "source", "importance", "emotion"]:
						if value.has(key):
							event[key] = value[key]
					events.append(event)
		dynamic[field] = events
	var revision := JSON.stringify(stable).sha256_text()
	var packet := {"nonce": nonce, "serial": serial, "revision": revision, "dynamic": dynamic, "stable": stable if revision != known_revision else {}}
	if JSON.stringify(packet).to_utf8_buffer().size() > MAX_PACKET_BYTES:
		return {"nonce": nonce, "serial": serial, "revision": "", "dynamic": {"available": false, "private_access": false, "details_access": false}, "stable": {}}
	return packet

static func accept_packet(packet: Dictionary, nonce: String, serial: int, selected: String, previous: Dictionary, previous_revision: String) -> Dictionary:
	if str(packet.get("nonce", "")) != nonce or int(packet.get("serial", -1)) != serial:
		return {}
	if not packet.get("stable") is Dictionary or not packet.get("dynamic") is Dictionary or JSON.stringify(packet).to_utf8_buffer().size() > MAX_PACKET_BYTES:
		return {}
	var stable: Dictionary = packet.stable
	var revision := str(packet.get("revision", ""))
	if stable.is_empty() and bool(packet.dynamic.get("available", false)) and (previous.is_empty() or previous_revision != revision):
		return {}
	var result := previous.duplicate(true) if stable.is_empty() else stable.duplicate(true)
	result.merge(packet.dynamic, true)
	result.private_access = false
	result.erase("diagnostics")
	result.erase("persistence")
	result.erase("population_diagnostics")
	if bool(result.get("available", false)) and str(result.get("selected_id", "")) != selected:
		return {}
	return {"snapshot": result, "revision": revision}
