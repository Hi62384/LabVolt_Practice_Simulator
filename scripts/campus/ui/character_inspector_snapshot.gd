extends RefCounted
## Read-only inspection. The host separately authorizes public selected-NPC
## packets; private diagnostics never leave the local host.
const Affect = preload("res://scripts/campus/academics/character_affect.gd")
const Profiles = preload("res://scripts/campus/academics/class_character_profile.gd")
const Roster = preload("res://scripts/campus/academics/faculty_roster.gd")
const DossierStore = preload("res://scripts/campus/academics/character_dossier_store.gd")
const PRIVATE_CONTEXT_FIELDS := ["core", "character_core", "compact_core", "personality", "speaking_style", "character", "biography", "life_history", "life_sections", "relevant_life_history", "personal_facts", "personal_records", "established_facts", "dialogue_examples", "selected_examples", "examples", "relationship", "emotional_state", "beliefs", "knowledge_restrictions", "decision", "dossier", "relevant_biography", "identity", "context_layers"]

static func can_inspect_private(faculty: Node) -> bool:
	if not is_instance_valid(faculty) or not faculty.is_inside_tree() or not faculty.multiplayer.is_server():
		return false
	var game: Variant = faculty.get("game")
	var brain: Variant = faculty.get("brain")
	if not is_instance_valid(game) or not is_instance_valid(brain):
		return false
	var school: Variant = game.get("school")
	if not is_instance_valid(school):
		return false
	var identity := str(school.get("local_identity"))
	return not identity.is_empty() and identity == str(brain.host_profile()) and (DossierStore.host_identity.is_empty() or DossierStore.host_identity == identity)

static func capture(faculty: Node) -> Dictionary:
	if not is_instance_valid(faculty) or not faculty.is_inside_tree():
		return {}
	var room := str(faculty.get("conversation_room"))
	if room.is_empty():
		return {}
	var game: Node = faculty.get("game")
	if not is_instance_valid(game):
		return {}
	var student := str(faculty.get("conversation_student"))
	var class_id := str(faculty.get("conversation_class"))
	var panel: Variant = faculty.get("conversation")
	var selected := str(panel.get_meta("selected_character_id", "")) if is_instance_valid(panel) else ""
	return _capture_selected(faculty, room, student, class_id, selected)

static func for_peer(faculty: Node, peer: int, room: String, student: String, class_id: String, selected: String) -> Dictionary:
	if not can_inspect_private(faculty):
		return {}
	var game: Node = faculty.game
	if not game.session.roster.has(peer) or not game.lecture_classes._inside(peer, room):
		return {}
	# The network request contains no player identity. Resolve it exclusively
	# from the authenticated session, including on every dynamic refresh.
	var identity := str(game.school.identities.get(peer, ""))
	if identity.is_empty():
		return {}
	var activity: Dictionary = faculty._ai_activity(room)
	if student.is_empty():
		if str(activity.get("teacher", "")) != selected or (not class_id.is_empty() and str(activity.get("id", "")) != class_id):
			return {}
		var origin: Vector3 = faculty._teacher_position(room)
		var position: Vector3 = game.lecture_classes._position(peer)
		if not origin.is_finite() or not position.is_finite() or origin.distance_to(position) > 3.8:
			return {}
	else:
		if selected != student or game.lecture_classes.classroom_students.nearby_member(peer, room, class_id, student).is_empty():
			return {}
	return _capture_selected(faculty, room, student, class_id, selected, identity)

static func _capture_selected(faculty: Node, room: String, student: String, class_id: String, selected: String, viewer_identity := "") -> Dictionary:
	var game: Node = faculty.game
	var activity: Dictionary = faculty._ai_activity(room)
	var member: Dictionary = {}
	var person: Dictionary = {}
	var private_access := can_inspect_private(faculty)
	if student.is_empty():
		var teacher_id := str(activity.get("teacher", ""))
		if not Roster.has(teacher_id) or (not selected.is_empty() and selected != teacher_id) or (not class_id.is_empty() and str(activity.get("id", "")) != class_id):
			return {}
		if private_access:
			person = Profiles.teacher(teacher_id)
		else:
			# Roster identity is already public. Never project private host dossiers
			# on a client merely because it knows a faculty identifier.
			person = {"id": teacher_id, "name": Roster.entry(teacher_id).get("name", ""), "role": "teacher"}
	else:
		if str(activity.get("id", "")) != class_id:
			return {}
		if private_access:
			member = activity.get("classmates", {}).get(student, {})
			person = member.get("profile", {})
		else:
			member = game.lecture_classes.classroom_students.visible_member(room, class_id, student)
			person = member.get("public_profile", {})
		if member.is_empty() or person.is_empty() or member.get("removed_from_class", false):
			return {}
	var result := {"available": true, "private_access": private_access and viewer_identity.is_empty(), "details_access": private_access, "selected_id": str(person.get("id", "")), "name": str(person.get("name", member.get("name", ""))), "role": str(person.get("role", "")), "activity": str(member.get("action", activity.get("phase", "freeplay"))), "mood": str(member.get("mood", "Not observed")), "room": room, "phase": str(activity.get("phase", ""))}
	if not private_access:
		result.access_note = "Personal history and diagnostics are available to the host. Public character information is shown here."
		return result
	var identity := str(game.school.local_identity) if viewer_identity.is_empty() else viewer_identity
	var brain: RefCounted = faculty.brain
	var mind: RefCounted = faculty.character_mind
	var id := str(person.get("id", ""))
	var dossier: Dictionary = DossierStore.get_dossier(id)
	if dossier.is_empty():
		dossier = person.get("dossier", {})
	var identity_data: Dictionary = dossier.get("identity", {})
	var relation: Dictionary = brain.relationship(id, identity)
	var mood_state: Dictionary = mind.moods.get(id, {})
	var values: Dictionary = mood_state.get("values", Affect.baseline(person.get("traits", {})))
	var disengagement: Dictionary = mind.disengagements.get(id + ":" + identity, {})
	var own_events: Array = relation.get("episodes", [])
	var own_event_ids: Dictionary = {}
	for event in own_events:
		if event is Dictionary and not str(event.get("event_id", "")).is_empty():
			own_event_ids[str(event.event_id)] = true
	var emotion_history: Array = []
	for event in mood_state.get("history", []):
		# The global mood is visible, but another player's private conversation
		# must not become an explanation in this selected-player inspector.
		if event is Dictionary and own_event_ids.has(str(event.get("event_id", ""))):
			emotion_history.append(event.duplicate(true))
	var mode := str(disengagement.get("disengagement", ""))
	var mood := Affect.dominant(values, person.get("traits", {}))
	var personality: Dictionary = dossier.get("personality", {})
	var communication: Dictionary = dossier.get("communication", {})
	var beliefs: Array = []
	for belief in brain.character_beliefs(person):
		if belief is Dictionary:
			# Histories include supporting quotes from arbitrary interlocutors.
			# Expose the present fictional opinion, not its private evidence chain.
			beliefs.append({"id": str(belief.get("id", "")), "position": str(belief.get("position", "")), "conviction": belief.get("conviction", null)})
	result.merge({"age": identity_data.get("age", person.get("age", null)), "program": str(identity_data.get("program", person.get("program", ""))), "background": str(identity_data.get("background", person.get("background", ""))), "physical_description": str(identity_data.get("physical_description", "")), "personality_description": str(personality.get("description", person.get("personality_description", person.get("description", "")))), "speaking_description": str(communication.get("description", person.get("speaking_description", person.get("style", "")))), "traits": person.get("traits", {}).duplicate(true), "motivations": personality.get("motivations", person.get("goals", [])), "values": personality.get("values", []), "interests": personality.get("interests", [person.get("interest", "")]), "strengths": personality.get("strengths", person.get("strengths", [])), "weaknesses": personality.get("weaknesses", person.get("weaknesses", [])), "beliefs": beliefs, "life_history": dossier.get("life_history", []), "personal_information": brain.character_biography(person), "voice": dossier.get("voice", {}), "knowledge": dossier.get("knowledge", {}), "examples": communication.get("examples", []), "generation": dossier.get("generation", {}), "mood": mood, "emotions": values.duplicate(true), "emotion_state_source": "Current simulated state" if not mood_state.is_empty() else "Personality baseline; no emotional event recorded", "emotional_history": emotion_history.slice(-20), "relationship": brain.social_context(relation), "reputation": relation.get("reputation", {}).duplicate(true), "relationship_events": own_events.slice(-24).duplicate(true), "disengagement": disengagement.duplicate(true), "willingness": "No disengagement decision recorded" if mode.is_empty() else mode.replace("_", " ").capitalize()}, true)
	var diagnostics: Array = faculty.character_interaction.diagnostics
	if brain.has_method("character_life_records"):
		result.life_records = brain.character_life_records(person)
	if not viewer_identity.is_empty():
		# No trace, API measurements, save paths, or other host-only fields are
		# even constructed for remote readers.
		return result.duplicate(true)
	result.diagnostics = selected_diagnostics(diagnostics, id, identity, str(activity.get("phase", "")))
	result.dossier_diagnostics = DossierStore.diagnostics(id)
	var persistence: Dictionary = brain.diagnostics()
	result.persistence = {}
	for field in ["memory_blocked", "memory_dirty", "last_error", "last_saved_at", "persistence_state", "blocked_reason", "unsaved_data", "profile_scoped"]:
		if persistence.has(field):
			result.persistence[field] = persistence[field]
	# Inspector rendering always receives an isolated value tree.
	return result.duplicate(true)

static func selected_diagnostics(traces: Array, character: String, speaker: String, phase: String) -> Dictionary:
	var trace: Dictionary = {}
	for index in range(traces.size() - 1, -1, -1):
		var candidate: Variant = traces[index]
		if candidate is Dictionary and str(candidate.get("character", "")) == character and str(candidate.get("speaker", "")) == speaker:
			trace = candidate
			break
	if trace.is_empty():
		return {"available": false}
	var result := {"available": true, "source": str(trace.get("source", "")), "fallback_reason": str(trace.get("fallback_reason", "")), "delivered": bool(trace.get("delivered", false)), "memory_recorded": trace.get("memory_recorded", null), "duration_ms": trace.get("duration_ms", null), "retrieval_ms": trace.get("retrieval_ms", null), "request_count": trace.get("request_count", null), "usage": trace.get("usage", {}).duplicate(true), "strategy": str(trace.get("strategy", "")), "assessment_redacted": phase == "assignment"}
	result.timing = {}
	for field in ["input_kind", "host_to_text_ms", "queue_wait_ms", "transcription_ms", "host_to_audio_ready_ms", "host_to_playback_started_ms"]:
		if trace.get("timing", {}).has(field):result.timing[field] = trace.timing[field]
	if phase == "assignment":
		return result
	result.reason = str(trace.get("reason", ""))
	var interpretation: Dictionary = trace.get("interpretation", {})
	result.interpretation = {}
	for field in ["event", "tone", "severity", "meaning", "topic", "domain", "difficulty", "requested_action", "sincere", "constructive"]:
		if interpretation.has(field):
			result.interpretation[field] = interpretation[field]
	var context: Dictionary = trace.get("retrieved_context", {})
	result.retrieved_context = {}
	for field in PRIVATE_CONTEXT_FIELDS:
		if context.has(field):
			result.retrieved_context[field] = _safe_context(context[field])
	result.retrieved_memories = []
	for field in ["memories", "reported_facts", "personal_records", "personal_memories", "fictional_memories"]:
		if context.get(field) is Array:
			for memory in context[field]:
				if memory is Dictionary:
					# Never accept arbitrary nested identity-bound content as a debug
					# field. IDs and authored/observed descriptions are sufficient.
					var selected: Dictionary = {}
					for key in ["id", "event", "description", "statement", "detail", "quote", "source", "at", "importance", "topic", "subject"]:
						if memory.has(key):
							selected[key] = memory[key]
					result.retrieved_memories.append(selected)
	result.selected_examples = _safe_context(context.get("selected_examples", context.get("dialogue_examples", context.get("examples", []))))
	return result.duplicate(true)

static func _safe_context(value: Variant, depth := 0) -> Variant:
	if depth > 10:
		return "Nested detail omitted"
	if value is Dictionary:
		var result: Dictionary = {}
		for key in value:
			var normalized := str(key).to_lower()
			if normalized in ["api_key", "authorization", "headers", "credentials", "access_token", "refresh_token", "history", "emotional_history", "evidence", "revision_reason", "prior_turns", "transcript", "raw_response", "answer", "answers", "answer_key", "solution", "solutions", "correct_answer", "private_tasks", "tasks"]:
				continue
			result[key] = _safe_context(value[key], depth + 1)
		return result
	if value is Array:
		var result: Array = []
		for item in value:
			result.append(_safe_context(item, depth + 1))
		return result
	return value
