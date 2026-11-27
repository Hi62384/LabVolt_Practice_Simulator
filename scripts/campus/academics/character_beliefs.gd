extends RefCounted
## A remembered change of opinion is narrower than an authored personality.
## Only existing opinions can change, from a new quoted argument the character
## actually answered. Neither a player's claim nor an opinion becomes curriculum.
const MAX_CHARACTERS:=2048
const MAX_BELIEFS:=64
const MAX_HISTORY:=4096
const EVENTS:=["chat","conversation","disagreement","criticism","challenge","initiative","study","collaboration"]
const CORE:=["profession","personal_priority"]

static func effective(person: Dictionary,revisions: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary]=[]
	var saved: Dictionary=revisions.get(str(person.get("id","")),{})
	for source in person.get("beliefs",[]):
		if not source is Dictionary or not source.get("id") is String:continue
		var belief: Dictionary=source.duplicate(true)
		belief.authored_position=str(source.get("authored_position",source.get("position","")))
		belief.authored_conviction=float(source.get("authored_conviction",source.get("conviction",.7)))
		var revision: Dictionary=saved.get(belief.id,{})
		if not revision.is_empty():
			belief.position=revision.position
			belief.conviction=revision.conviction
			# Retain the complete evidence chain on disk; generation needs only the
			# recent reasons, not thousands of historical revisions in every prompt.
			belief.history=revision.history.slice(-6).duplicate(true)
			belief.history_count=revision.history.size()
			belief.revision_reason=str(revision.history[-1].reason)
		else:
			belief.history=[];belief.history_count=0
		result.append(belief)
	return result

static func policy(person: Dictionary,revisions: Dictionary) -> Dictionary:
	var result:={}
	for belief in effective(person,revisions):
		var openness:=clampf(float(belief.get("openness",.25)),0.,1.)
		var importance:=clampf(float(belief.get("importance",.8)),0.,1.)
		var conviction:=clampf(float(belief.get("conviction",.7)),0.,1.)
		var count:=int(belief.get("history_count",0))
		var core: bool=belief.id in CORE
		# A willing, uncertain person can reconsider promptly. A stubborn person
		# needs several distinct arguments and gradually reduced certainty first.
		var can_revise:=not core and ((openness>=.65 and conviction<.8) or (openness>=.35 and count>=2) or (openness>=.15 and count>=4 and conviction<=.6) or (count>=8 and conviction<=.5))
		result[belief.id]={"max_conviction_change":snappedf((.015+.105*openness)*(1.-.35*importance),.001),
			"can_revise_position":can_revise,"evidence_count":count,"core_identity":core}
	return result

static func evidence_key(evidence: String) -> String:
	var normalized:=RegEx.create_from_string("\\s+").sub(evidence.to_lower().strip_edges()," ",true)
	return normalized.strip_edges().trim_suffix(".").trim_suffix("!").trim_suffix("?").sha256_text()

static func validate(person: Dictionary,revisions: Dictionary,question: String,speech: String,proposal: Variant,event: String="chat") -> Dictionary:
	if not proposal is Dictionary:return _invalid("belief_update_not_object")
	if event not in EVENTS:return _invalid("event_is_not_reasoned_evidence")
	for field in ["id","position","reason","evidence"]:
		if not proposal.get(field) is String:return _invalid("missing_belief_"+field)
	for field in proposal:
		if field not in ["id","position","reason","evidence","conviction_change"]:return _invalid("unknown_belief_update_field")
	var id: String=proposal.id
	var current: Dictionary={}
	for belief in effective(person,revisions):
		if belief.id==id:current=belief;break
	if current.is_empty():return _invalid("unknown_belief_id")
	var position: String=proposal.position.strip_edges()
	var reason: String=proposal.reason.strip_edges()
	var evidence: String=proposal.evidence.strip_edges()
	if position.length()<8 or position.length()>1000 or not position in speech:return _invalid("position_not_in_delivered_speech")
	if reason.is_empty() or reason.length()>500:return _invalid("invalid_belief_reason")
	if evidence.length()<8 or evidence.length()>1000 or not evidence in question:return _invalid("evidence_not_in_current_input")
	var change: Variant=proposal.get("conviction_change")
	if not (change is int or change is float) or not is_finite(float(change)):return _invalid("invalid_conviction_change")
	var rules: Dictionary=policy(person,revisions).get(id,{})
	if absf(float(change))>float(rules.max_conviction_change)+.000001:return _invalid("conviction_change_exceeds_personal_limit")
	var changed:=position!=str(current.position)
	if changed and not rules.can_revise_position:return _invalid("position_change_needs_more_evidence")
	if not changed and is_zero_approx(float(change)):return _invalid("belief_update_has_no_change")
	var conviction:=float(current.conviction)+float(change)
	if conviction<0. or conviction>1.:return _invalid("conviction_out_of_range")
	var prior: Dictionary=revisions.get(str(person.get("id","")),{}).get(id,{})
	var history: Array=prior.get("history",[])
	if history.size()>=MAX_HISTORY:return _invalid("belief_history_full")
	var fingerprint:=evidence_key(evidence)
	for revision in history:
		if revision.evidence_hash==fingerprint:return _invalid("belief_evidence_already_considered")
	return {"ok":true,"reason":"","update":{"id":id,"position":position,"reason":reason,"evidence":evidence,"conviction_change":float(change)}}

static func apply(person: Dictionary,revisions: Dictionary,question: String,speech: String,proposal: Variant,event: String,identity: String,event_id: String,now: int) -> Dictionary:
	var result:=validate(person,revisions,question,speech,proposal,event)
	if not result.ok:return result
	var character:=str(person.get("id",""))
	if not character.is_valid_identifier() or character.length()>64:return _invalid("invalid_belief_character")
	if identity.is_empty() or identity.length()>128 or event_id.length()>128 or now<0:return _invalid("invalid_belief_source")
	if not revisions.has(character) and revisions.size()>=MAX_CHARACTERS:return _invalid("belief_characters_full")
	var update: Dictionary=result.update
	var current: Dictionary={}
	for belief in effective(person,revisions):
		if belief.id==update.id:current=belief;break
	var saved: Dictionary=revisions.get_or_add(character,{})
	if not saved.has(update.id) and saved.size()>=MAX_BELIEFS:return _invalid("character_beliefs_full")
	var history: Array=saved.get(update.id,{}).get("history",[]).duplicate(true)
	var conviction:=float(current.conviction)+float(update.conviction_change)
	history.append({"at":now,"speaker":identity,"event_id":event_id,"event":event,
		"from_position":str(current.position),"position":update.position,"from_conviction":float(current.conviction),"conviction":conviction,
		"reason":update.reason,"evidence":update.evidence,"evidence_hash":evidence_key(update.evidence)})
	saved[update.id]={"position":update.position,"conviction":conviction,"history":history}
	return result

static func valid_snapshot(source: Variant) -> bool:
	if not source is Dictionary or source.size()>MAX_CHARACTERS:return false
	for character in source:
		if not character is String or not character.is_valid_identifier() or character.length()>64:return false
		var beliefs: Variant=source[character]
		if not beliefs is Dictionary or beliefs.size()>MAX_BELIEFS:return false
		for id in beliefs:
			if not id is String or not id.is_valid_identifier() or id.length()>64:return false
			var belief: Variant=beliefs[id]
			if not belief is Dictionary or belief.size()!=3 or not _position(belief.get("position")) or not _unit(belief.get("conviction")):return false
			if not belief.get("history") is Array or belief.history.is_empty() or belief.history.size()>MAX_HISTORY:return false
			var seen:={}
			var previous: Dictionary={}
			for revision in belief.history:
				if not revision is Dictionary or revision.size()!=11:return false
				if not _whole(revision.get("at")) or revision.get("event") not in EVENTS:return false
				if not revision.get("speaker") is String or revision.speaker.is_empty() or revision.speaker.length()>128:return false
				if not revision.get("event_id") is String or revision.event_id.length()>128:return false
				if not _position(revision.get("position")) or not _position(revision.get("from_position")):return false
				if not _unit(revision.get("conviction")) or not _unit(revision.get("from_conviction")):return false
				if absf(float(revision.conviction)-float(revision.from_conviction))>.120001:return false
				if not revision.get("reason") is String or revision.reason.is_empty() or revision.reason.length()>500:return false
				if not revision.get("evidence") is String or revision.evidence.length()<8 or revision.evidence.length()>1000:return false
				if revision.get("evidence_hash")!=evidence_key(revision.evidence) or seen.has(revision.evidence_hash):return false
				if not previous.is_empty() and (revision.from_position!=previous.position or not is_equal_approx(float(revision.from_conviction),float(previous.conviction))):return false
				seen[revision.evidence_hash]=true;previous=revision
			if belief.position!=previous.position or not is_equal_approx(float(belief.conviction),float(previous.conviction)):return false
	return true

static func _invalid(reason: String) -> Dictionary:
	return {"ok":false,"reason":reason,"update":{}}

static func _position(value: Variant) -> bool:
	return value is String and value.length()>=8 and value.length()<=1000

static func _unit(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value)>=0. and float(value)<=1.

static func _whole(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value)>=0. and float(value)<=100000000000. and float(value)==floor(float(value))
