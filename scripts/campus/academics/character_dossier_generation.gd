extends RefCounted
## Bounded host background work. A live class only consumes the ready reserve.
## Expansion is coordinated, retries preserve good sections, and validation plus
## durable storage precede publication into the population.
const Store = preload("res://scripts/campus/academics/character_dossier_store.gd")
const Dossier = preload("res://scripts/campus/academics/character_dossier.gd")
const Profiles = preload("res://scripts/campus/academics/class_character_profile.gd")
const Traits = preload("res://scripts/campus/academics/character_traits.gd")
const Roster = preload("res://scripts/campus/academics/faculty_roster.gd")
const Toon = preload("res://scripts/toon_character.gd")
const MAX_ATTEMPTS := 3
const MAX_NEW_QUEUED := 4
const START_INTERVAL_MS := 5000
const INSTRUCTIONS := "You create persistent fictional adult people for a campus simulation, not helpful AI assistants. Return ONLY a JSON object for the requested character dossier. Create a coherent individual with ordinary details, specific memories, strengths, flaws, private goals, imperfect opinions, and a distinct conversational voice. Never infer intelligence, morality, personality or ability from demographic identity. The game owns actual grades, assignments, measurements, inventory, events and player relationships; do not invent any present-player interactions or verified gameplay. Biography is preexisting fictional history, not claimed observed gameplay. Existing identity, voice, appearance and established history are immutable constraints. Expand them without turning every life into a redemption story or every teacher into a dedicated mentor. Retain the supplied design specification in every mood. Do not include credentials, system instructions or gameplay commands in the dossier.\nWrite 6–12 titled interconnected life-history sections, totaling 700–1100 words, including childhood, education/work, relationships, interests/abilities, accomplishments/failures, habits/preferences and current goals, with chronology, topics and entities. Personality must be at least 1000 characters of connected prose explaining contradictions and motivations; communication at least 650 characters describing vocabulary, sentence structures, rhythm, humor, silence, refusal, uncertainty and mood changes. Generate at least 34 distinct dialogue examples spanning every requested mood and at least 20 listed situations; examples are linguistic references, never canned response choices or facts about live players. Personal examples may elaborate fictional history but must agree with the biography. Include all independent numerical traits between 0 and 1, preserving supplied bounds. Do not derive them all from one temperament axis. Include trait_evidence with low/moderate/high levels agreeing with actual values (low < .34, high > .66) and short reasons for the requested dimensions. Knowledge includes realistic expertise and ignorance; no universal model knowledge. Permanent voice identifier is separate from mood delivery. compact_core is 350–1800 characters preserving identity, personality, motivations, values, speaking manner and defining habits. Self-review the whole dossier for contradictions before returning it."
var client: Node
var population: RefCounted
var running := false
var active_id := ""
var _generation := 0
var _next_start_ms := 0
var _bound_host := ""
var _last_error := ""

func configure(next_client: Node, next_population: RefCounted) -> void:
	var changed_host := _bound_host != Store.host_identity
	if client != next_client or population != next_population or _bound_host != Store.host_identity: cancel()
	client = next_client
	population = next_population
	_bound_host = Store.host_identity
	if _bound_host.is_empty() or Store.blocked: return
	if changed_host:
		Roster.GENERATED.clear()
		for id in Profiles.teacher_seeds.keys():
			if str(id).begins_with("generated_"): Profiles.teacher_seeds.erase(id)
	# Restore custom teachers from the same persisted dossier authority.
	for id in Store.dossiers:
		if str(id).begins_with("generated_") and Store.dossiers[id].get("generation",{}).get("status")=="complete": _register_teacher(Store.dossiers[id])
	for id in Roster.all_people(): Store.queue(Profiles.teacher(str(id)), 0)
	if population != null:
		for person in population.people.values(): Store.queue(person, 0)
	if Store.dirty: Store.save()

func request_teacher(course: String, design: String) -> Dictionary:
	if not is_instance_valid(client) or not client.host_allowed() or not client.enabled or not client.configured(): return {"ok":false,"error":"Enable the host AI connection first."}
	if Store.blocked or Store.host_identity.is_empty(): return {"ok":false,"error":"Character persistence is unavailable."}
	if course not in ["MTH147","MTH255","ETY155","ELM253","DGS266"] or design.strip_edges().length()<3 or design.length()>2000: return {"ok":false,"error":"Choose a course and describe the instructor."}
	var count:=Roster.GENERATED.size()
	for job in Store.jobs.values():
		if job.get("kind")!="teacher" or job.get("status")=="complete": continue
		count+=1
		if job.get("status") in ["queued","running","retry"] and job.get("seed",{}).get("subjects",[])==[course] and job.get("seed",{}).get("design_specification")==design:
			return {"ok":true,"queued":true,"id":job.id,"name":"New instructor","message":"This instructor is already being developed in the background."}
	if count>=12: return {"ok":false,"error":"This campus already has 12 custom instructors or pending requests."}
	var id:="generated_"+Crypto.new().generate_random_bytes(8).hex_encode()
	if not Store.queue_custom_teacher(id,course,design): return {"ok":false,"error":"Could not queue this instructor."}
	if Store.save()!=OK:
		Store.jobs.erase(id)
		return {"ok":false,"error":"The instructor request could not be saved."}
	return {"ok":true,"queued":true,"id":id,"name":"New instructor","message":"The instructor's full identity is being developed in the background and will become available after validation."}

static func _register_teacher(dossier: Dictionary) -> bool:
	if Roster.PEOPLE.has(str(dossier.get("identity",{}).get("id",""))): return true
	var courses: Array=dossier.get("subjects",[])
	if courses.is_empty() or dossier.get("identity",{}).get("role")!="teacher": return false
	return Roster.add_generated(str(dossier.identity.id),{"name":str(dossier.identity.name),"course":str(courses[0]),"style":str(dossier.get("compact_core","")),"appearance":dossier.identity.get("appearance",{})})

func queue_teacher(profile: Dictionary) -> void:
	Store.queue(profile, 5)

func tick(preferred_ids: Array = []) -> void:
	if running or Time.get_ticks_msec() < _next_start_ms or Store.blocked or Store.host_identity != _bound_host: return
	if not is_instance_valid(client) or not client.has_method("generate_character_dossier"): return
	if not client.host_allowed() or not client.enabled or not client.configured(): return
	# Foreground requests retain priority; the separate HTTP lane prevents a
	# generation already in flight from blocking a player's conversation.
	if client.busy or client.get("background_busy") == true: return
	_sync_population()
	for id in preferred_ids:
		if Store.jobs.has(str(id)): Store.jobs[str(id)].priority = 10
	var ready: Array = []
	var now := int(Time.get_unix_time_from_system())
	for job in Store.jobs.values():
		if job.get("status") in ["queued", "retry"] and int(job.get("attempts", 0)) < MAX_ATTEMPTS and int(job.get("retry_at", 0)) <= now: ready.append(job)
	if ready.is_empty(): return
	ready.sort_custom(func(a, b): return int(a.priority) > int(b.priority) if int(a.priority) != int(b.priority) else int(a.created_at) < int(b.created_at))
	running = true
	active_id = str(ready[0].id)
	_next_start_ms = Time.get_ticks_msec() + START_INTERVAL_MS
	_run(active_id, _generation, Store.revision)

func _sync_population() -> void:
	if population == null or population.profile_blocked or population.persistence_blocked: return
	# A dossier may have been saved just before interruption; import it without
	# charging another generation request or changing its stable identity.
	for id in Store.dossiers:
		var d: Dictionary = Store.dossiers[id]
		if d.get("identity", {}).get("role") != "student" or d.get("generation", {}).get("status") != "complete": continue
		if not population.people.has(id) or int(population.people[id].get("dossier_revision",0)) != int(d.get("revision",1)):
			population.import_generated(student_profile(d))
	var pending_new := 0
	for job in Store.jobs.values():
		if job.get("kind") == "student" and job.get("status") != "complete": pending_new += 1
	var needed := mini(MAX_NEW_QUEUED - pending_new, maxi(0, population.requested_size - population.people.size() - pending_new))
	for _index in maxi(0, needed):
		var id: String = population.reserve_identity()
		if id.is_empty(): break
		Store.queue_student(id)
	if Store.dirty: Store.save()

func cancel() -> void:
	_generation += 1
	if running and not active_id.is_empty() and Store.jobs.has(active_id):
		var job: Dictionary = Store.jobs[active_id]
		job.status = "queued"
		job.attempts = maxi(0,int(job.get("attempts",0))-1)
		job.cancelled_requests = int(job.get("cancelled_requests",0))+1
		job.last_error = "Background generation was cancelled before publication."
		Store.dirty = true
		Store.save()
	if is_instance_valid(client) and client.has_method("cancel_background_generation"): client.cancel_background_generation()
	running = false
	active_id = ""

func retry_failed(id: String) -> bool:
	if running or not Store.jobs.has(id): return false
	var job: Dictionary = Store.jobs[id]
	if job.get("status") != "failed": return false
	job.status = "queued"
	job.attempts = 0
	job.retry_at = 0
	job.last_error = ""
	Store.dirty = true
	return Store.save() == OK

func _run(id: String, generation: int, store_revision: int) -> void:
	var job: Dictionary = Store.jobs[id].duplicate(true)
	var seed := Store.get_dossier(id)
	if seed.get("generation",{}).get("status")=="complete":
		if (seed.identity.role=="teacher" and _register_teacher(seed)) or (seed.identity.role=="student" and (population==null or population.import_generated(student_profile(seed)))):
			job.status="complete"
			job.draft={}
			job.last_error=""
			Store.update_job(id,job)
			Store.save()
			running=false
			active_id=""
			return
		_finish_failure(id,job,"Saved character is awaiting population storage recovery.",false)
		return
	if str(job.get("stage",""))=="publish" and not job.get("draft",{}).is_empty():
		var recovered:=Store.publish(job.draft,seed,job.get("measurement",{}))
		if recovered.get("ok",false):
			job.status="queued"
			Store.update_job(id,job)
			Store.save()
			running=false
			active_id=""
			return
		_finish_failure(id,job,"Validated character is awaiting dossier storage recovery.",false)
		return
	if seed.is_empty() and job.get("seed") is Dictionary: seed=job.seed.duplicate(true)
	if seed.is_empty(): seed = {"identity": {"id": id, "role": "student"}, "design_specification": "Create a distinct adult campus student. Any combination of ability, diligence, friendliness, confidence and sociability is possible; explain the person's actual motives rather than defaulting to cooperation."}
	job.status = "running"
	job.attempts = int(job.get("attempts", 0)) + 1
	job.started_at = int(Time.get_unix_time_from_system())
	Store.update_job(id, job)
	if Store.save() != OK:
		_finish_failure(id, job, "Generation paused because its job checkpoint could not be saved.", false)
		return
	var context := request_context(seed, job)
	var started := Time.get_ticks_msec()
	var response: Dictionary = await client.generate_character_dossier(INSTRUCTIONS, context, 10000)
	if generation != _generation or store_revision != Store.revision or _bound_host != Store.host_identity: return
	job.requests = int(job.get("requests", 0)) + 1
	job.elapsed_ms = int(job.get("elapsed_ms", 0)) + Time.get_ticks_msec() - started
	job.measurement = _measure(job.get("measurement", {}), response.get("measurement", {}))
	if not response.get("ok", false):
		_finish_failure(id, job, str(response.get("error", "Character generation failed.")), true)
		return
	var decoded: Variant = decode(str(response.get("text", "")))
	if not decoded is Dictionary:
		_finish_failure(id, job, "Character generation returned incomplete or invalid JSON; the draft was not published.", true)
		return
	var candidate: Dictionary = decoded
	if str(job.get("stage", "full")) == "repair" and not job.get("draft", {}).is_empty():
		candidate = job.draft.duplicate(true)
		for field in job.get("invalid_sections", []):
			if decoded.has(field): candidate[field] = decoded[field]
	# Deterministic provenance and immutable history are never model-writeable.
	candidate.version = Dossier.VERSION
	var appearance_error := false
	if candidate.get("identity") is Dictionary and candidate.identity.get("appearance") is Dictionary and seed.get("identity",{}).get("appearance",{}).is_empty():
		var raw_appearance: Dictionary = candidate.identity.appearance
		var sanitized := Toon.sanitize(raw_appearance)
		for key in raw_appearance:
			if key in ["name","creator","version"]: continue
			if not sanitized.has(key) or raw_appearance[key] != sanitized[key]: appearance_error = true
		if not appearance_error:
			candidate.identity.appearance = sanitized
			candidate.identity.appearance.name = str(candidate.identity.get("name", ""))
	var validation := Dossier.validate(candidate, seed)
	if appearance_error:
		validation.ok = false
		validation.errors.append("identity: appearance contains unsupported options or out-of-range body values")
		if "identity" not in validation.sections: validation.sections.append("identity")
	if not validation.ok:
		job.draft = candidate
		job.stage = "repair"
		job.issues = validation.errors
		job.invalid_sections = validation.sections
		if "trait_evidence" in job.invalid_sections and "traits" not in job.invalid_sections: job.invalid_sections.append("traits")
		if "traits" in job.invalid_sections and "trait_evidence" not in job.invalid_sections: job.invalid_sections.append("trait_evidence")
		_finish_failure(id, job, "Dossier validation failed: " + "; ".join(validation.errors), true)
		return
	var telemetry: Dictionary = job.measurement.duplicate(true)
	telemetry.requests = job.requests
	telemetry.total_elapsed_ms = job.elapsed_ms
	telemetry.attempts = job.attempts
	telemetry.model = str(client.model)
	var published := Store.publish(candidate, seed, telemetry)
	if not published.get("ok", false):
		job.draft = candidate
		job.stage = "publish"
		_finish_failure(id, job, str(published.get("error", "Validated dossier could not be persisted.")), false)
		return
	if str(published.dossier.identity.id).begins_with("generated_") and published.dossier.identity.role=="teacher" and not _register_teacher(published.dossier):
		_finish_failure(id,job,"Dossier was saved, but instructor registration needs recovery.",false)
		return
	if published.dossier.identity.role == "student" and population != null:
		if not population.import_generated(student_profile(published.dossier)):
			_finish_failure(id, job, "Dossier was saved, but population publication needs recovery.", false)
			return
	job.status = "complete"
	job.draft = {}
	job.issues = []
	job.invalid_sections = []
	job.completed_at = int(Time.get_unix_time_from_system())
	job.last_error = ""
	Store.update_job(id, job)
	Store.save()
	running = false
	active_id = ""
	_last_error = ""

func _finish_failure(id: String, job: Dictionary, reason: String, retryable: bool) -> void:
	job.status = "retry" if retryable and int(job.attempts) < MAX_ATTEMPTS else "failed"
	job.retry_at = int(Time.get_unix_time_from_system()) + 15 * int(job.attempts)
	job.last_error = reason.left(2500)
	Store.update_job(id, job)
	Store.save()
	_last_error = job.last_error
	running = false
	active_id = ""

static func request_context(seed: Dictionary, job: Dictionary) -> Dictionary:
	var identity: Dictionary = seed.get("identity", {}).duplicate(true)
	var required := {"identity": {"id": "stable ID supplied below", "name": "adult person's name", "age": "integer 18–110", "role": "teacher/student/staff", "program": "student program or teacher profession", "background": "summary", "physical_description": "appearance and physical characteristics consistent with appearance", "appearance": Toon.defaults()},
		"life_history": [{"id": "section_id", "title": "Meaningful heading", "text": "Substantial interconnected life prose", "topics": ["generated subject labels and related concepts"], "entities": ["relevant fictional people or places"], "aliases": ["natural related phrases"], "chronology": "age or period", "source": "preexisting_fiction"}],
		"personality": {"description": "1000+ characters", "motivations": ["private goals"], "values": ["personal values"], "interests": ["interests"], "strengths": ["strengths"], "weaknesses": ["real flaws"], "habits": ["routines and habits"], "beliefs": [{"id": "opinion_topic", "topic": "topic", "position": "opinion", "conviction": .7, "reason": "experience", "experience": "biography connection", "importance": .6, "openness": .4}]},
		"communication": {"description": "650+ characters", "examples": [{"id": "unique_example", "situation": "one listed circumstance", "mood": "one listed mood", "relationship": "friend/stranger/acquaintance/disliked_person", "prompt": "example utterance or situation", "reply": "new natural words in this person's voice"}]},
		"traits": Traits.required_keys(), "knowledge": {"education": "education and practical experience", "expertise": ["specific areas"], "ignorance": ["plausible gaps"], "domains": {"math": .5, "electronics": .5, "gaming": .5, "fitness": .5, "programming": .5, "mechanics": .5, "science": .5, "business": .5, "culture": .5, "everyday": .5}},
		"voice": {"identifier": "one of coral, echo, nova, fable, ash, onyx, sage, shimmer, alloy, verse, ballad, cedar, marin", "profile": "permanent timbre and natural accent", "characteristics": "natural vocal manner", "delivery": "how mood modifies delivery without changing speaker"},
		"compact_core": "350–1800 characters", "trait_evidence": {"confrontation": {"level": "low/moderate/high", "reason": "specific grounded explanation"}}}
	var context := {"task": "Expand the existing identity coherently" if job.get("kind") == "expand" else "Generate a new coherent adult teacher" if job.get("kind")=="teacher" else "Generate a new coherent adult student", "schema": required,
		"immutable_identity": identity, "assigned_subjects":seed.get("subjects",[]), "design_specification": str(seed.get("design_specification", "")), "trait_constraints": seed.get("trait_constraints", {}),
		"permanent_voice": seed.get("voice", {}), "established_life_history": seed.get("life_history", []), "established_facts": seed.get("established_biography", {}),
		"existing_traits": seed.get("traits", {}), "existing_beliefs": seed.get("personality", {}).get("beliefs", []), "moods": Dossier.MOODS, "situations": Dossier.SITUATIONS,
		"trait_evidence_required": ["confrontation", "empathy", "confidence", "shyness", "arrogance", "patience", "teaching_effort", "academic_motivation", "academic_ability", "laziness", "slang", "formality"],
		"appearance_options": {"hair": Toon.HAIR, "outfit": Toon.OUTFITS, "glasses": Toon.GLASSES, "expression": Toon.EXPRESSIONS, "body_scalars": "0.65–1.4", "colors": "six-digit HTML colors"}}
	if str(job.get("stage", "full")) == "repair":
		context.task = "Repair only the named invalid top-level sections. Return a JSON object containing only those fields. All other sections are already completed and MUST remain unchanged."
		context.invalid_sections = job.get("invalid_sections", [])
		context.validation_errors = job.get("issues", [])
		context.completed_draft = job.get("draft", {})
	else:
		var neighbors: Array = []
		for d in Store.dossiers.values():
			if d.get("identity", {}).get("role") == "student" and d.get("generation", {}).get("status") == "complete":
				neighbors.append({"name": d.identity.name, "personality": str(d.compact_core)})
			if neighbors.size() >= 4: break
		if not neighbors.is_empty(): context.existing_people_to_differ_from = neighbors
	return context

static func decode(text: String) -> Variant:
	var clean := text.strip_edges()
	if clean.begins_with("```"):
		var newline := clean.find("\n")
		if newline >= 0: clean = clean.substr(newline + 1).trim_suffix("```").strip_edges()
	var parser := JSON.new()
	return parser.data if parser.parse(clean) == OK else null

static func student_profile(d: Dictionary) -> Dictionary:
	var base := {"id": str(d.identity.id), "name": str(d.identity.name), "role": "student", "voice_slot": posmod(str(d.identity.id).hash(), 32749), "subjects": [], "lines": {}, "profile_version": 3}
	var profile := Dossier.project(base, d)
	profile.appearance_seed = posmod(str(d.identity.id).hash(), 2147483647)
	profile.created_at = int(d.get("provenance", {}).get("created_at", Time.get_unix_time_from_system()))
	profile.social_habits = {"initiative": float(profile.traits.get("initiative", .5)), "comfort_with_strangers": 1. - float(profile.traits.get("shyness", .5)), "seeks_rivalry": float(profile.traits.get("competitiveness", .5))}
	return profile

static func _measure(total: Dictionary, current: Dictionary) -> Dictionary:
	var result := total.duplicate(true)
	var usage: Dictionary = result.get("usage", {}).duplicate(true)
	for key in ["input", "output", "cached", "reasoning"]:
		if current.get("usage", {}).has(key): usage[key] = int(usage.get(key, 0)) + int(current.usage[key])
	result.usage = usage
	result.latency_ms = int(result.get("latency_ms", 0)) + int(current.get("latency_ms", 0))
	if current.has("model"): result.model = str(current.model)
	return result

func diagnostics() -> Dictionary:
	return {"running": running, "active_id": active_id, "last_error": _last_error, "host_bound": _bound_host == Store.host_identity, "max_attempts": MAX_ATTEMPTS, "concurrency": 1, "store": Store.diagnostics(active_id)}
