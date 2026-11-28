extends RefCounted
## Persistent authored/generated identity. Actual gameplay remains in CharacterMemory.
## All construction, validation and retrieval is local and independent of transport.
const Traits = preload("res://scripts/campus/academics/character_traits.gd")
const VocalDesign = preload("res://scripts/campus/academics/character_voice_design.gd")
const VERSION := 1
const MAX_BYTES := 262144
const MIN_LIFE_CHARS := 3600
const MIN_EXAMPLES := 34
const MOODS := ["neutral", "happy", "excited", "angry", "irritated", "frustrated", "sad", "disappointed", "bored", "tired", "embarrassed", "anxious", "confident", "dismissive", "amused", "uninterested", "careless"]
const SITUATIONS := ["classroom_greeting", "casual_greeting", "ordinary_conversation", "personal_question", "academic_question", "help", "joke", "compliment", "teasing", "insult", "argument", "disagreement", "criticism", "apology", "opinion", "interest", "dislike", "unexpected_event", "refusal", "boredom", "excitement", "discipline", "assessment", "friend", "stranger", "disliked_person"]
const STOP_WORDS := ["the", "a", "an", "to", "of", "and", "or", "it", "is", "was", "were", "are", "be", "been", "for", "in", "at", "on", "you", "your", "i", "me", "my", "do", "did", "does", "can", "could", "would", "should", "what", "when", "who", "how", "that", "this", "with", "have", "has", "had", "about", "ever", "again", "much", "most", "get", "got", "say", "said", "tell", "them", "they", "their", "his", "her", "he", "she", "we", "our"]
# Concepts describe language, not character-specific question/answer branches.
# Generated section topics/entities/aliases provide the extensible part of the index.
const CONCEPTS := {
	"strength_record": ["pr", "record", "personalbest", "maximum", "heaviest", "strongest"],
	"training": ["fitness", "gym", "workout", "exercise", "lifting", "lift", "training", "train"],
	"bench": ["bench", "benched", "benchpress", "pressing"],
	"squat": ["squat", "squatted", "squatting"],
	"childhood": ["childhood", "child", "kid", "young", "grew", "growing"],
	"education": ["school", "college", "university", "degree", "education", "studied", "study", "diploma"],
	"career": ["job", "jobs", "career", "occupation", "employment", "employer", "worked", "profession"],
	"relationships": ["friend", "friendship", "partner", "buddy", "mate", "colleague", "coworker"],
	"food": ["food", "meal", "cooking", "cook", "eat", "ate", "eating", "dish"],
	"opinion": ["think", "opinion", "believe", "belief", "worth", "worthwhile", "view"],
	"failure": ["failure", "failed", "mistake", "regret", "embarrassing", "embarrassed"],
	"goals": ["goal", "ambition", "dream", "plan", "future", "hope"],
}

static func migrate(profile: Dictionary) -> Dictionary:
	var sections: Array = []
	var biography: Dictionary = profile.get("biography", {})
	for topic in biography:
		if str(biography[topic]).strip_edges().is_empty(): continue
		sections.append({"id": str(topic), "title": str(topic).replace("_", " ").capitalize(), "text": str(biography[topic]), "topics": [str(topic)], "entities": [], "chronology": "Preexisting fictional history", "source": "migrated_fiction"})
	if not str(profile.get("background", "")).is_empty():
		sections.append({"id": "background", "title": "Background", "text": str(profile.background), "topics": ["background", "career"], "entities": [], "chronology": "Preexisting fictional history", "source": "migrated_fiction"})
	var examples: Array = []
	for pair in profile.get("behavior_examples", []):
		if pair is Array and pair.size() >= 2:
			examples.append({"id": "legacy_%d" % examples.size(), "situation": "ordinary_conversation", "mood": "neutral", "relationship": "acquaintance", "prompt": str(pair[0]), "reply": str(pair[1]), "source": "authored_reference"})
	# Legacy recovery lines become references only. Nothing selects them as answers.
	var lines: Dictionary = profile.get("lines", {})
	for key in lines:
		examples.append({"id": "legacy_" + str(key), "situation": str(key), "mood": "neutral", "relationship": "stranger", "prompt": str(key).replace("_", " "), "reply": str(lines[key]), "source": "authored_reference"})
	var description := str(profile.get("personality_description", profile.get("worldview", profile.get("style", ""))))
	var speech := str(profile.get("speaking_description", profile.get("style", "")))
	var identity := {"id": str(profile.get("id", "")), "name": str(profile.get("name", "")), "age": int(profile.get("age", 18)), "role": str(profile.get("role", "student")), "program": str(profile.get("program", "")), "background": str(profile.get("background", "")), "physical_description": str(profile.get("physical_description", "Appearance is defined by the saved character model.")), "appearance": profile.get("appearance", {}).duplicate(true)}
	var voice := VocalDesign.dossier_seed(profile)
	var dossier := {"version": VERSION, "revision": 1, "identity": identity, "life_history": sections,
		"personality": {"description": description, "motivations": [str(profile.get("ambition", ""))], "values": [str(profile.get("values", ""))], "interests": [str(profile.get("interest", ""))], "strengths": profile.get("strengths", []), "weaknesses": profile.get("weaknesses", []), "beliefs": profile.get("beliefs", []).duplicate(true), "habits": [str(profile.get("habits", ""))]},
		"communication": {"description": speech, "examples": examples}, "traits": profile.get("traits", {}).duplicate(true),
		"knowledge": {"education": str(profile.get("education", "")), "expertise": profile.get("subjects", []).duplicate(), "ignorance": [], "domains": profile.get("knowledge_domains", {}).duplicate(true)},
		"voice": voice,
		"compact_core": str(identity.name) + ", " + str(identity.role) + ". " + description + " Speaking manner: " + speech + " Personal priority: " + str(profile.get("ambition", "")),
		"subjects": profile.get("subjects",[]).duplicate(), "design_specification": str(profile.get("design_specification", description)), "trait_constraints": profile.get("trait_constraints", {}).duplicate(true),
		"established_biography": biography.duplicate(true),
		"generation": {"status": "needs_expansion", "source": "legacy_migration", "completed_at": 0},
		"provenance": {"source": "legacy_migration", "history_kind": "fictional", "created_at": int(Time.get_unix_time_from_system())}}
	return dossier

static func project(profile: Dictionary, dossier: Dictionary, include_dossier := false) -> Dictionary:
	# A remote public identity is already the complete authorized view. Never
	# enrich it from this device's private dossier with a coincidentally equal ID.
	if profile.get("identity_scope", "") == "public": return profile.duplicate(true)
	if dossier.is_empty(): return profile.duplicate(true)
	var result := {}
	for key in profile:
		if key in ["dossier","behavior_examples","traits","beliefs","goals","biography","voice_slot","voice_scope"]: continue
		result[key] = profile[key].duplicate(true) if profile[key] is Dictionary or profile[key] is Array else profile[key]
	var identity: Dictionary = dossier.get("identity", {})
	for key in ["id", "name", "age", "role", "program", "background", "physical_description", "appearance"]:
		if identity.has(key): result[key] = identity[key].duplicate(true) if identity[key] is Dictionary or identity[key] is Array else identity[key]
	var personality: Dictionary = dossier.get("personality", {})
	var communication: Dictionary = dossier.get("communication", {})
	var knowledge: Dictionary = dossier.get("knowledge", {})
	if include_dossier: result.dossier = dossier.duplicate(true)
	result.dossier_status = str(dossier.get("generation",{}).get("status","needs_expansion"))
	result.dossier_revision = int(dossier.get("revision",1))
	result.traits = dossier.get("traits", result.get("traits", {})).duplicate(true)
	result.personality_description = str(personality.get("description", ""))
	result.speaking_description = str(communication.get("description", ""))
	result.style = result.speaking_description
	result.worldview = result.personality_description
	result.biography = dossier.get("established_biography", {}).duplicate(true)
	for key in ["strengths", "weaknesses", "beliefs"]:
		result[key] = personality.get(key, result.get(key, [])).duplicate(true)
	result.interest = ", ".join(personality.get("interests", []))
	result.ambition = "; ".join(personality.get("motivations", []))
	result.values = "; ".join(personality.get("values", []))
	result.habits = "; ".join(personality.get("habits", []))
	result.education = str(knowledge.get("education", ""))
	result.knowledge_domains = knowledge.get("domains", {}).duplicate(true)
	result.voice = dossier.get("voice", {}).duplicate(true)
	# Existing faculty have an authored acoustic design independent of legacy
	# modulo suggestions or any generated dossier prose. Actual approved IDs
	# remain in the separate voice store and never enter the dossier.
	if VocalDesign.has_authored(str(result.get("id",""))):result.voice=VocalDesign.dossier_seed(result)
	result.subjects = dossier.get("subjects",profile.get("subjects",[])).duplicate()
	result.behavior_examples = []
	# Examples live only in the dossier and are retrieved for real requests.
	for pair in [["talk", "talkativeness"], ["focus", "focus"], ["confidence", "confidence"], ["knowledge", "academic_ability"], ["curiosity", "curiosity"], ["teaching", "teaching_effort"], ["strictness", "strictness"]]:
		result[pair[0]] = float(result.traits.get(pair[1], result.get(pair[0], .5)))
	result.activities = Traits.activity_preferences(result.traits)
	result.goals = []
	for motivation in personality.get("motivations", []):
		result.goals.append({"goal": str(motivation), "priority": .8, "horizon": "long_term"})
	return result

static func validate(candidate: Variant, seed: Dictionary = {}, complete := true) -> Dictionary:
	var errors: Array[String] = []
	if not candidate is Dictionary: return {"ok": false, "errors": ["root: expected an object"], "sections": ["all"]}
	var d: Dictionary = candidate
	if JSON.stringify(d).to_utf8_buffer().size() > MAX_BYTES: return {"ok": false, "errors": ["root: dossier exceeds storage bound"], "sections": ["all"]}
	for field in ["identity", "personality", "communication", "traits", "knowledge", "voice"]:
		if not d.get(field) is Dictionary: errors.append(field + ": expected an object")
	if not errors.is_empty(): return _validation_result(errors)
	var identity: Dictionary = d.identity
	for field in ["id", "name", "role", "background", "physical_description"]:
		if not _string(identity.get(field), 1, 2400): errors.append("identity: missing or invalid " + field)
	if identity.get("role", "") not in ["teacher", "student", "staff"]: errors.append("identity: unsupported role")
	if not _number(identity.get("age"), 18, 110) or floorf(float(identity.get("age", 0))) != float(identity.get("age", 0)): errors.append("identity: age must be a whole adult age")
	if str(identity.get("name", "")).length() > 80: errors.append("identity: name too long")
	for character in str(identity.get("name","")):
		if character in ["\n","\r","\t","[","]"]: errors.append("identity: unsupported name characters")
	if not identity.get("appearance") is Dictionary: errors.append("identity: missing appearance")
	if identity.get("role") == "student" and not _string(identity.get("program"), 2, 160): errors.append("identity: student program required")
	var fixed: Dictionary = seed.get("identity", {})
	for key in ["id", "name", "age", "role", "program"]:
		if fixed.has(key) and not str(fixed[key]).is_empty() and identity.get(key) != fixed[key]: errors.append("identity: changed established " + key)
	if not fixed.get("appearance", {}).is_empty() and not _same_json_data(identity.get("appearance"), fixed.appearance): errors.append("identity: changed established appearance")
	for key in Traits.required_keys():
		if not _number(d.traits.get(key), 0., 1.): errors.append("traits: missing or invalid " + key)
	for key in d.traits:
		if not _number(d.traits[key], 0., 1.): errors.append("traits: invalid value " + str(key))
	for key in seed.get("trait_constraints", {}):
		var bounds: Array = seed.trait_constraints[key]
		if bounds.size() == 2 and not _number(d.traits.get(key), float(bounds[0]), float(bounds[1])): errors.append("traits: violates established " + str(key) + " constraint")
	if not _string(d.personality.get("description"), 1000 if complete else 1, 14000): errors.append("personality: requires a substantial coherent description")
	for field in ["motivations", "values", "interests", "strengths", "weaknesses", "habits", "beliefs"]:
		if not d.personality.get(field) is Array or (complete and d.personality[field].is_empty()): errors.append("personality: missing " + field)
		elif field != "beliefs":
			for entry in d.personality[field]:
				if not _string(entry, 1, 1200): errors.append("personality: invalid " + field + " entry")
		else:
			for belief in d.personality.beliefs:
				if not belief is Dictionary or not _string(belief.get("topic"),1,100) or not _string(belief.get("position"),1,2000): errors.append("personality: invalid belief")
	if not _string(d.communication.get("description"), 650 if complete else 1, 9000): errors.append("communication: requires a detailed speaking description")
	var sections: Variant = d.get("life_history")
	var total := 0
	var ids := {}
	if not sections is Array: errors.append("life_history: expected sections")
	else:
		if sections.size() < (6 if complete else 1) or sections.size() > 60: errors.append("life_history: requires 6–60 meaningful sections")
		for section in sections:
			if not section is Dictionary: errors.append("life_history: invalid section"); continue
			if not _string(section.get("id"), 1, 80) or ids.has(str(section.get("id", ""))): errors.append("life_history: unique section IDs required")
			ids[str(section.get("id", ""))] = true
			if not _string(section.get("title"), 1, 160) or not _string(section.get("text"), 120 if complete else 1, 16000): errors.append("life_history: section title/text is incomplete")
			if not section.get("topics") is Array or not section.get("entities") is Array: errors.append("life_history: topics/entities arrays required")
			else:
				for field in ["topics","entities","aliases"]:
					if not section.get(field,[]) is Array: errors.append("life_history: invalid " + field); continue
					for entry in section.get(field,[]):
						if not _string(entry,1,180): errors.append("life_history: invalid " + field + " entry")
			if not section.get("chronology", "") is String: errors.append("life_history: chronology must be text")
			if str(section.get("source", "preexisting_fiction")) not in ["preexisting_fiction", "migrated_fiction", "improvised_fiction"]: errors.append("life_history: biography cannot invent observed gameplay")
			total += str(section.get("text", "")).length()
		if complete and total < MIN_LIFE_CHARS: errors.append("life_history: biography must contain at least %d characters of substantive prose" % MIN_LIFE_CHARS)
	var examples: Variant = d.communication.get("examples")
	var mood_set := {}
	var situation_set := {}
	var replies := {}
	if not examples is Array: errors.append("communication: examples array required")
	else:
		if examples.size() < (MIN_EXAMPLES if complete else 1) or examples.size() > 120: errors.append("communication: requires 34–120 varied examples")
		for e in examples:
			if not e is Dictionary: errors.append("communication: invalid example"); continue
			for key in ["id", "situation", "mood", "relationship", "prompt", "reply"]:
				if not _string(e.get(key), 1, 1800): errors.append("communication: missing example " + key)
			mood_set[str(e.get("mood", ""))] = true
			situation_set[str(e.get("situation", ""))] = true
			replies[str(e.get("reply", ""))] = true
		if complete:
			for mood in MOODS:
				if not mood_set.has(mood): errors.append("communication: missing mood " + mood)
			if situation_set.size() < 20: errors.append("communication: requires at least 20 distinct circumstances")
			if replies.size() < MIN_EXAMPLES: errors.append("communication: repeated examples are insufficient")
	if not _string(d.knowledge.get("education"), 1, 2400) or not d.knowledge.get("expertise") is Array or not d.knowledge.get("ignorance") is Array or not d.knowledge.get("domains") is Dictionary: errors.append("knowledge: education, expertise, ignorance and domains required")
	else:
		for value in d.knowledge.domains.values():
			if not _number(value, 0., 1.): errors.append("knowledge: invalid domain value")
	for field in ["identifier", "profile", "characteristics", "delivery"]:
		if not _string(d.voice.get(field), 1, 2800): errors.append("voice: missing " + field)
	if d.voice.get("identifier","") not in ["coral","echo","nova","fable","ash","onyx","sage","shimmer","alloy","verse","ballad","cedar","marin"]: errors.append("voice: unsupported permanent voice identifier")
	if seed.get("voice", {}).has("identifier") and d.voice.get("identifier") != seed.voice.identifier: errors.append("voice: changed established preset suggestion")
	# Structured acoustic fields are optional for older saved dossiers.
	if d.voice.has("presentation") and d.voice.presentation not in ["masculine","feminine","androgynous"]: errors.append("voice: invalid presentation")
	if d.voice.has("perceived_age") and not _number(d.voice.perceived_age,18.,110.): errors.append("voice: adult perceived age required")
	if d.voice.has("normal_pace") and not _number(d.voice.normal_pace,.65,1.3): errors.append("voice: invalid normal pace")
	for field in ["pitch_range","resonance","timbre","texture","accent","articulation"]:
		if d.voice.has(field) and not _string(d.voice[field],1,220): errors.append("voice: invalid "+field)
	for field in ["expertise","ignorance"]:
		if d.knowledge.get(field) is Array:
			for entry in d.knowledge[field]:
				if not _string(entry,1,1200): errors.append("knowledge: invalid "+field+" entry")
	if not _string(d.get("compact_core"), 350 if complete else 1, 2400): errors.append("compact_core: needs a distinctive 350–2400 character core")
	# Generated trait evidence binds the numerical scale to the written portrayal.
	# This cannot prove every natural-language claim; consequential dialogue still
	# undergoes the interaction validator. It catches common contradictory bands.
	if complete:
		var evidence: Variant = d.get("trait_evidence")
		if not evidence is Dictionary: errors.append("trait_evidence: explain the major independent dimensions")
		else:
			for key in ["confrontation", "empathy", "confidence", "shyness", "arrogance", "patience", "teaching_effort", "academic_motivation", "academic_ability", "laziness", "slang", "formality"]:
				var item: Variant = evidence.get(key)
				if not item is Dictionary or not _string(item.get("reason"), 10, 800): errors.append("trait_evidence: missing " + key); continue
				var value := float(d.traits.get(key, .5))
				var band := "low" if value < .34 else "high" if value > .66 else "moderate"
				if item.get("level") != band: errors.append("trait_evidence: " + key + " level disagrees with value")
	return _validation_result(errors)

static func _validation_result(errors: Array) -> Dictionary:
	var sections: Array = []
	for error in errors:
		var field := str(error).get_slice(":", 0)
		if field not in sections: sections.append(field)
	return {"ok": errors.is_empty(), "errors": errors, "sections": sections}

static func _same_json_data(left: Variant, right: Variant) -> bool:
	# JSON numbers round-trip as floats. Dictionary equality can otherwise
	# reject an unchanged authored appearance solely because 1 became 1.0.
	if left == right: return true
	return JSON.parse_string(JSON.stringify(left)) == JSON.parse_string(JSON.stringify(right))

static func _string(value: Variant, minimum: int, maximum: int) -> bool:
	return value is String and value.strip_edges().length() >= minimum and value.length() <= maximum

static func _number(value: Variant, minimum: float, maximum: float) -> bool:
	return (value is float or value is int) and is_finite(float(value)) and float(value) >= minimum and float(value) <= maximum

static func terms(text: String) -> Array[String]:
	var cleaned := text.to_lower().replace("personal best", "personalbest").replace("bench press", "benchpress")
	for mark in ["?", "!", ".", ",", ";", ":", "\"", "'", "-", "_", "(", ")", "[", "]", "\n", "\t", "/"]: cleaned = cleaned.replace(mark, " ")
	var found: Dictionary = {}
	for raw in cleaned.split(" ", false):
		if raw.length() < 2 or raw in STOP_WORDS: continue
		found[raw] = true
		if raw.length() > 4 and raw.ends_with("s"): found[raw.left(-1)] = true
		if raw.length() > 5 and raw.ends_with("ing"): found[raw.left(-3)] = true
		if raw.length() > 4 and raw.ends_with("ed"): found[raw.left(-2)] = true
	for concept in CONCEPTS:
		if CONCEPTS[concept].any(func(term): return found.has(term)): found[concept] = true
	var result: Array[String] = []
	result.assign(found.keys())
	return result

static func relevance(text: String, question: String, recent: Array = []) -> float:
	var source := terms(text)
	var query := terms(question)
	var score := 0.
	for term in query:
		if term in source: score += 2.5 if term in CONCEPTS else 2.
	# A short follow-up inherits actual recent conversation topics at lower weight.
	var recent_text := ""
	for turn in recent.slice(maxi(0, recent.size() - 2)):
		if turn is Dictionary:
			recent_text += " " + str(turn.get("question", turn.get("student", turn.get("player", "")))) + " " + str(turn.get("reply", turn.get("teacher", turn.get("speech", ""))))
	var carry := terms(recent_text)
	for term in carry:
		if term in source and term not in query: score += .55 if query.size() <= 4 else .12
	return score

static func retrieve(person: Dictionary, question: String, recent: Array = [], mood := "neutral", relationship: Dictionary = {}, budget_chars := 6500) -> Dictionary:
	var started := Time.get_ticks_usec()
	var d: Dictionary = person.get("dossier", {})
	if d.is_empty(): d = migrate(person)
	budget_chars = clampi(budget_chars, 2400, 18000)
	var result := {"core": str(d.get("compact_core", "")), "life_history": [], "examples": []}
	var used := JSON.stringify(result).length()
	var candidates: Array = []
	for section in d.get("life_history", []):
		var search := str(section.get("title", "")) + " " + str(section.get("text", "")) + " " + " ".join(section.get("topics", [])) + " " + " ".join(section.get("entities", [])) + " " + " ".join(section.get("aliases", []))
		var score := relevance(search, question, recent)
		if score > 0.: candidates.append({"score": score, "section": section})
	candidates.sort_custom(func(a, b): return float(a.score) > float(b.score))
	var selected_sections: Array = []
	var life_budget := maxi(0, budget_chars - used - 1400)
	var life_used := 0
	for entry in candidates:
		if result.life_history.size() >= 4: break
		var section: Dictionary = entry.section
		var compact := {"id": str(section.get("id", "")), "title": str(section.get("title", "")), "text": str(section.get("text", "")), "chronology": str(section.get("chronology", "")), "source": str(section.get("source", "preexisting_fiction"))}
		var size := JSON.stringify(compact).length()
		if life_used + size > life_budget:
			# Select complete sentences; never split a JSON string or a word.
			compact.text = relevant_sentences(str(compact.text), question, recent, maxi(0, life_budget - life_used - 160))
			if str(compact.text).is_empty(): continue
			size = JSON.stringify(compact).length()
			if life_used + size > life_budget: continue
		result.life_history.append(compact)
		selected_sections.append(compact.id)
		life_used += size
	used += life_used
	var examples: Array = []
	var mood_name := mood if mood in MOODS else "neutral"
	var bond := "friend" if float(relationship.get("friendship", 0.)) > .4 else "disliked_person" if float(relationship.get("resentment", 0.)) > .4 else "stranger" if float(relationship.get("familiarity", 0.)) < .1 else "acquaintance"
	for e in d.get("communication", {}).get("examples", []):
		var score := relevance(str(e.get("situation", "")) + " " + str(e.get("prompt", "")), question, recent)
		if e.get("mood") == mood_name: score += 7.
		if e.get("relationship") == bond: score += 2.
		examples.append({"score": score, "example": e})
	examples.sort_custom(func(a, b): return float(a.score) > float(b.score))
	var example_ids: Array = []
	for entry in examples:
		if result.examples.size() >= 3: break
		var e: Dictionary = entry.example
		var compact := {"situation": str(e.get("situation", "")), "mood": str(e.get("mood", "")), "prompt": str(e.get("prompt", "")), "reply": str(e.get("reply", ""))}
		var size := JSON.stringify(compact).length()
		if used + size > budget_chars: continue
		result.examples.append(compact)
		example_ids.append(str(e.get("id", "")))
		used += size
	result.diagnostics = {"section_ids": selected_sections, "example_ids": example_ids, "retrieval_usec": Time.get_ticks_usec() - started, "context_chars": JSON.stringify(result).length(), "budget_chars": budget_chars, "generation_status": str(d.get("generation", {}).get("status", "needs_expansion")), "measurement_kind": "characters_are_not_tokens"}
	return result

static func relevant_sentences(text: String, question: String, recent: Array, budget: int) -> String:
	if budget <= 0: return ""
	if text.length() <= budget: return text
	var ranked: Array = []
	var sentences := text.replace("! ", "!\n").replace("? ", "?\n").replace(". ", ".\n").split("\n", false)
	for index in sentences.size():
		var sentence := sentences[index].strip_edges()
		if not sentence.is_empty(): ranked.append({"index": index, "text": sentence, "score": relevance(sentence, question, recent)})
	ranked.sort_custom(func(a, b): return float(a.score) > float(b.score))
	var kept: Array = []
	var used := 0
	for entry in ranked:
		if used + str(entry.text).length() + 1 > budget: continue
		kept.append(entry)
		used += str(entry.text).length() + 1
	kept.sort_custom(func(a, b): return int(a.index) < int(b.index))
	var parts: PackedStringArray = []
	for entry in kept: parts.append(entry.text)
	return " ".join(parts)
