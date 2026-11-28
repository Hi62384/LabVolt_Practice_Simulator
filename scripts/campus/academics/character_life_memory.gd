extends RefCounted
## Expandable fictional autobiography. This ledger never grants game authority.
## A record's wording may vary; its canonical value, origin and earlier versions
## remain available to every interlocutor of the same persistent character.
const KINDS := ["historical", "current", "preference", "opinion"]
const MAX_RECORDS := 2048
const MAX_HISTORY := 64
const MAX_DETAIL := 900
const STOP_WORDS := ["the","and","that","this","with","from","what","when","your","have","about","were","does","would","could","been","said","again","much","most","ever","how","did","who","was","for","you","are","his","her","has","had","its","she","him","but","not","can","get"]
const WORD_FAMILIES := {
	"record":["record","records","best","maximum","highest","pr"],
	"train":["train","training","trained","workout","workouts","exercise","exercises","lifting","lifted","lift"],
	"education":["education","educated","school","college","study","studied","university"],
	"job":["job","jobs","career","employment","employed","occupation"],
	"childhood":["childhood","child","young","grew","growing"],
	"friend":["friend","friends","friendship","buddy","buddies","partner"],
	"prefer":["favorite","favourite","prefer","preferred","preference","love","enjoy"],
}
static var words := RegEx.create_from_string("[\\p{L}\\p{N}]+")
static var numbers := RegEx.create_from_string("[0-9]+(?:[.,][0-9]+)?")
static var written_numbers := RegEx.create_from_string("(?i)\\b(?:zero|one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve|thirteen|fourteen|fifteen|sixteen|seventeen|eighteen|nineteen|twenty|thirty|forty|fifty|sixty|seventy|eighty|ninety|hundred|thousand|million|billion|trillion)\\b")
static var negation := RegEx.create_from_string("(?i)\\b(?:not|never|no|cannot|can't|isn't|wasn't|aren't|weren't|don't|doesn't|didn't|won't|haven't|hasn't)\\b")
static var clause_boundaries := RegEx.create_from_string("(?i)[!?;\\n]+|\\.(?:\\s+|$)|\\b(?:and|but|while|whereas)\\s+(?=(?:my|your|his|her|their|i|we|they|the)\\b)")
static var _indexes: Dictionary = {}
const MAX_INDEXES := 16

static func terms(text: String) -> Array[String]:
	var result: Array[String] = []
	for matched in words.search_all(text.to_lower()):
		var word := matched.get_string()
		if word.length() < 2 or word in STOP_WORDS:continue
		for family in WORD_FAMILIES:
			if word in WORD_FAMILIES[family]:word = family;break
		# General morphology handles bench/benched/benching and new subjects alike.
		if word.length() > 5:
			if word.ends_with("ing"):word = word.trim_suffix("ing")
			elif word.ends_with("ed"):word = word.trim_suffix("ed")
		if word.length() > 4 and word.ends_with("s"):word = word.trim_suffix("s")
		if word not in result:result.append(word)
	return result

static func query_terms(question: String, recent: Array = []) -> Array[String]:
	var result := terms(question)
	# Short follow-ups inherit the actual last subject, not an exact question list.
	if result.size() <= 3:
		for exchange in recent.slice(-2):
			if not exchange is Dictionary:continue
			for term in terms(str(exchange.get("student","")) + " " + str(exchange.get("teacher",""))):
				if term not in result:result.append(term)
	return result

static func canonical(topic: String) -> String:
	var tokens := terms(topic.replace("_"," ").replace("."," ").replace("-"," "))
	tokens.sort()
	return ".".join(tokens)

static func normalized(value: String) -> String:
	# Search normalization deliberately removes filler and expands concepts.
	# Canonical values cannot do that: "not vegetarian" and "vegetarian" are
	# different facts, and changing either requires an explained revision.
	var result: PackedStringArray = []
	for matched in words.search_all(value.to_lower().replace("’", "'")):
		result.append(matched.get_string())
	return " ".join(result)

static func _quantities(value: String) -> Array[String]:
	var result: Array[String] = []
	for matched in numbers.search_all(value):
		if matched.get_string() not in result:result.append(matched.get_string())
	return result

static func _value_grounding(value: String, detail: String) -> Dictionary:
	var expected := _quantities(value)
	var spoken := _quantities(detail)
	if not spoken.is_empty() and expected.any(func(quantity):return quantity not in spoken) and written_numbers.search(detail)==null:
		return {"ok":false,"review":false,"reason":"The canonical quantity must occur in the quoted spoken detail."}
	var plain_value := normalized(value)
	if plain_value.is_empty():return {"ok":false,"review":false,"reason":"The canonical value must contain meaningful text."}
	var mentions: Array[String] = []
	for clause in clause_boundaries.sub(detail, "\n", true).split("\n", false):
		if (" " + plain_value + " ") in (" " + normalized(clause) + " "):mentions.append(clause)
	var literal := not mentions.is_empty()
	var value_negative := negation.search(value.replace("’", "'")) != null
	# An unrelated "not bad" in the next sentence does not negate the value.
	# Conflicting positive/negative assertions in the quote still need review.
	var same_polarity := mentions.all(func(clause):return (negation.search(clause.replace("’", "'")) != null)==value_negative)
	# A semantic paraphrase (including a spelled-out quantity) may be valid,
	# but a local topic or token match is not proof of what the speaker asserted.
	return {"ok":true,"review":not literal or not same_polarity,"reason":""}

static func _subjects(topic: String) -> Array[String]:
	var result: Array[String] = []
	for term in terms(topic):
		if term not in ["record","train","prefer","personal","history","current","value"]:result.append(term)
	result.sort()
	return result

static func valid_topic(topic: String) -> bool:
	if topic.length() < 3 or topic.length() > 96:return false
	for c in topic:
		if not (c.is_valid_identifier() or c.is_valid_int() or c in [".","-","_"]):return false
	return not canonical(topic).is_empty()

static func migrate(saved: Dictionary) -> Dictionary:
	var result := {}
	for topic in saved:
		if not topic is String or not saved[topic] is String:continue
		result[topic] = {"id":topic, "topic":topic, "detail":saved[topic], "value":saved[topic],
			"kind":"historical", "provenance":"migrated_fiction", "at":0, "chronology":"", "links":[], "history":[]}
	return result

static func find_topic(records: Dictionary, topic: String) -> String:
	if records.has(topic):return topic
	var key := canonical(topic)
	for existing in records:
		if canonical(str(existing)) == key:return str(existing)
	return ""

static func relevance(record: Dictionary, query: Array[String], now: int) -> float:
	var title := terms(str(record.get("topic","")))
	var contents := terms(str(record.get("detail","")) + " " + " ".join(record.get("entities",[])))
	var score := 0.0
	for word in query:
		if word in title:score += 3.0
		elif word in contents:score += 1.0
	# Recency breaks ties; it does not make an unrelated fact relevant.
	if score > 0:score += .15 / (1.0 + maxf(0.0,float(now-int(record.get("at",0)))) / 86400.0)
	return score

static func _index(records: Dictionary, cache_key: String) -> Dictionary:
	# Tokenization and concept expansion happen only when stored records change.
	# Cached postings contain IDs, never another host's record text.
	var signature := records.hash()
	var cached: Dictionary = _indexes.get(cache_key,{})
	if cached.get("signature",-1)==signature:return cached
	var built := {"signature":signature,"postings":{},"tokens":{}}
	for id in records:
		var record: Dictionary=records[id]
		var title:=terms(str(record.get("topic","")))
		var contents:=terms(str(record.get("detail",""))+" "+" ".join(record.get("entities",[]))+" "+" ".join(record.get("aliases",[]))+" "+str(record.get("chronology","")))
		built.tokens[id]={"title":title,"contents":contents}
		for word in title+contents:
			var posting: Dictionary=built.postings.get_or_add(word,{})
			posting[id]=true
	if not _indexes.has(cache_key) and _indexes.size()>=MAX_INDEXES:_indexes.erase(_indexes.keys()[0])
	_indexes[cache_key]=built
	return built

static func retrieve(records: Dictionary, question: String, recent: Array = [], limit := 8, cache_key := "transient") -> Array:
	var query := query_terms(question,recent)
	var now := int(Time.get_unix_time_from_system())
	var indexed:=_index(records,cache_key)
	var candidates: Dictionary={}
	for word in query:candidates.merge(indexed.postings.get(word,{}))
	var ranked: Array = []
	for id in candidates:
		if not records.has(id):continue
		var record: Dictionary=records[id]
		var tokens: Dictionary=indexed.tokens[id]
		var score:=0.0
		for word in query:
			if word in tokens.title:score+=3.0
			elif word in tokens.contents:score+=1.0
		if score>0:
			score+=.15/(1.0+maxf(0.0,float(now-int(record.get("at",0))))/86400.0)
			score+=clampf(float(record.get("importance",.5)),0.,1.)*.2
		if score > 0:ranked.append({"score":score,"record":record})
	# An experience may link its current record to the people and chronology
	# behind it. Include only connected records, never arbitrary recent facts.
	for entry in ranked.duplicate():
		for linked in entry.record.get("links",[]):
			if records.has(linked) and not candidates.has(linked):
				candidates[linked]=true;ranked.append({"score":float(entry.score)*.65,"record":records[linked]})
	ranked.sort_custom(func(a,b):return float(a.score)>float(b.score))
	var selected: Array = []
	for entry in ranked.slice(0,clampi(limit,1,16)):
		var record: Dictionary = entry.record
		selected.append({"id":record.id,"topic":record.topic,"detail":record.detail,"value":record.value,
			"kind":record.kind,"provenance":record.provenance,"chronology":record.get("chronology",""),"links":record.get("links",[]),"history":record.get("history",[]).slice(-2)})
	return selected

static func validate(proposal: Variant, speech: String, records: Dictionary) -> Dictionary:
	if not proposal is Dictionary or not proposal.get("topic") is String or not proposal.get("detail") is String:
		return {"ok":false,"reason":"A personal fact needs a topic and a verbatim spoken detail."}
	var topic: String = proposal.topic
	var detail: String = proposal.detail.strip_edges()
	if not valid_topic(topic) or detail.length()<8 or detail.length()>MAX_DETAIL or not detail in speech:
		return {"ok":false,"reason":"The personal detail must be a complete, bounded quote from delivered speech."}
	var kind := str(proposal.get("kind","historical"))
	if kind not in KINDS:return {"ok":false,"reason":"Unsupported personal memory category."}
	var provenance := str(proposal.get("provenance","improvised_fiction"))
	if provenance != "improvised_fiction":return {"ok":false,"reason":"Dialogue may only propose fictional personal history, never observed game state."}
	var lower := (topic+" "+detail).to_lower()
	for forbidden in ["answer_key","assessment_answer","equipment_reading","player_action","your grade","your mark","you scored","you insulted","you told me","you completed","you submitted","you handed","you cheated","you threw","you measured","i gave you"]:
		if forbidden in lower:return {"ok":false,"reason":"A fictional biography cannot establish a player action, measurement or academic outcome."}
	var value := str(proposal.get("value",detail)).strip_edges()
	if value.is_empty() or value.length()>500:return {"ok":false,"reason":"Invalid canonical value."}
	var grounding := _value_grounding(value,detail)
	if not grounding.ok:return grounding
	var old_topic := find_topic(records,topic)
	var previous: Dictionary = records.get(old_topic,{})
	var revision := str(proposal.get("revision",""))
	var reason := str(proposal.get("reason",""))
	if not previous.is_empty() and normalized(str(previous.value)) != normalized(value):
		if revision not in ["update","correction"] or reason.length()<12 or reason.length()>MAX_DETAIL or not reason in speech:
			return {"ok":false,"reason":"This subject already has an established value. A change requires a spoken explanation and preserved history."}
		if previous.kind=="historical" and revision!="correction":return {"ok":false,"reason":"A historical event cannot be replaced by a current preference or achievement."}
		if previous.get("history",[]).size()>=MAX_HISTORY:return {"ok":false,"reason":"The personal record revision history is full."}
	var links: Array = []
	if proposal.get("links") is Array:
		for link in proposal.links.slice(0,8):
			if link is String and records.has(link):links.append(link)
	var entities:=_bounded_strings(proposal.get("entities",[]),12,80)
	var aliases:=_bounded_strings(proposal.get("aliases",[]),8,80)
	return {"ok":true,"review":grounding.review,"record":{"id":old_topic if not old_topic.is_empty() else topic,"topic":old_topic if not old_topic.is_empty() else topic,
		"detail":detail,"value":value,"kind":str(previous.get("kind",kind)),"provenance":provenance,"at":int(Time.get_unix_time_from_system()),
		"chronology":str(proposal.get("chronology","")).left(180),"links":links,"entities":entities,"aliases":aliases,"history":previous.get("history",[]).duplicate(true)},"previous":previous,"reason":reason,"revision":revision}

static func _bounded_strings(value: Variant, count: int, length: int) -> Array[String]:
	var result: Array[String]=[]
	if value is Array:
		for item in value.slice(0,count):
			if item is String and item.length()<=length and not item.strip_edges().is_empty():result.append(item.strip_edges())
	return result

static func apply(records: Dictionary, checked: Dictionary) -> void:
	var record: Dictionary = checked.record.duplicate(true)
	var previous: Dictionary = checked.previous
	if not previous.is_empty() and normalized(str(previous.value))!=normalized(str(record.value)):
		record.history.append({"detail":previous.detail,"value":previous.value,"at":previous.at,"kind":previous.kind,"reason":checked.reason,"revision":checked.revision})
	records[record.id] = record

## Check the actual utterance too: a model must not omit its memory proposal to
## evade a value conflict. Ambiguous consequential claims request a bounded
## semantic consistency review instead of pretending local NLP proves truth.
static func speech_check(speech: String, records: Dictionary, proposals: Array, personal := false) -> Dictionary:
	var review := false
	var clauses: Array = []
	for clause in clause_boundaries.sub(speech, "\n", true).split("\n", false):
		clauses.append({"text":clause,"terms":terms(clause),"quantities":_quantities(clause)})
	var proposed: Dictionary = {}
	var covered_quantities: Array[String] = []
	for proposal in proposals:
		if not proposal is Dictionary:return {"ok":false,"review":false,"reason":"Invalid personal history proposal."}
		var candidate: Dictionary = proposal.duplicate(true)
		var topic := str(candidate.get("topic",""))
		var established := find_topic(records,topic)
		if established.is_empty():
			var subjects := _subjects(topic)
			if not subjects.is_empty():
				for existing in records:
					if _subjects(str(existing))==subjects:established=str(existing);break
		if not established.is_empty():candidate.topic=established
		var checked := validate(candidate,speech,records)
		if not checked.ok:return {"ok":false,"review":false,"reason":checked.reason}
		review = review or bool(checked.get("review",false))
		if not established.is_empty():proposed[established]=checked
		for quantity in _quantities(str(checked.record.detail)):
			if quantity not in covered_quantities:covered_quantities.append(quantity)
	for record in records.values():
		var title := terms(str(record.topic))
		var subjects := _subjects(str(record.topic))
		var old_numbers := _quantities(str(record.value))
		var allowed := old_numbers.duplicate()
		var update: Dictionary = proposed.get(str(record.id),{})
		if not update.is_empty():
			# Structural validation already required a spoken reason before a
			# changed current value or historical correction could reach here.
			for quantity in _quantities(str(update.record.value)):
				if quantity not in allowed:allowed.append(quantity)
		for clause in clauses:
			if not title.any(func(term):return term in clause.terms):continue
			if not subjects.is_empty() and not subjects.any(func(term):return term in clause.terms):continue
			var spoken: Array = clause.quantities
			if not old_numbers.is_empty() and written_numbers.search(str(clause.text))!=null:review=true
			if not old_numbers.is_empty() and not spoken.is_empty():
				if not allowed.any(func(quantity):return quantity in spoken):
					return {"ok":false,"review":false,"reason":"Spoken quantities conflict with the established or explicitly revised personal value."}
				# Mentioning the old number somewhere in a mixed assertion cannot
				# legitimize another, contradictory number for the same subject.
				if spoken.any(func(quantity):return quantity not in allowed):review=true
			if ["never ","i haven't ","i have not ","i didn't ","i don't ","no longer ","i used to "].any(func(s):return s in str(clause.text).to_lower()):review=true
	if personal and not _quantities(speech).is_empty():
		var known: Array[String] = []
		for record in records.values():
			var content := str(record.value)+" "+str(record.detail)+" "+str(record.get("chronology",""))
			for prior in record.get("history",[]):
				if prior is Dictionary:content+=" "+str(prior.get("value",""))+" "+str(prior.get("detail",""))+" "+str(prior.get("reason",""))
			for quantity in _quantities(content):
				if quantity not in known:known.append(quantity)
		var spoken := _quantities(speech)
		var unknown: Array = spoken.filter(func(quantity):return quantity not in known and quantity not in covered_quantities)
		if not unknown.is_empty():
			if proposals.is_empty() and not spoken.any(func(quantity):return quantity in known):
				return {"ok":false,"review":false,"reason":"New numerical personal information must be proposed for persistent memory."}
			review=true
	elif personal and proposals.is_empty() and written_numbers.search(speech)!=null:
		# A model must not bypass quantity checks by spelling an unrecorded or
		# conflicting number in words. Ambiguous wording is reviewed, not parsed
		# as if a small local grammar could establish the complete life claim.
		review=true
	return {"ok":true,"review":review,"reason":""}

static func valid_snapshot(source: Variant) -> bool:
	if not source is Dictionary or source.size()>2048:return false
	for id in source:
		if not id is String or id.length()>64 or not source[id] is Dictionary or source[id].size()>MAX_RECORDS:return false
		for topic in source[id]:
			var record: Variant = source[id][topic]
			if not topic is String or not valid_topic(topic) or not record is Dictionary:return false
			if not record.has_all(["id","topic","detail","value","kind","provenance","at","history"]):return false
			if record.id!=topic or record.topic!=topic or not record.detail is String or record.detail.length()>MAX_DETAIL:return false
			if not record.value is String or record.value.length()>900 or record.kind not in KINDS:return false
			if record.provenance not in ["improvised_fiction","migrated_fiction","authored_fiction"]:return false
			if not record.history is Array or record.history.size()>MAX_HISTORY:return false
			if not (record.at is int or record.at is float) or not is_finite(float(record.at)) or float(record.at)<0:return false
			if record.has("chronology") and (not record.chronology is String or record.chronology.length()>180):return false
			for field in ["links","entities","aliases"]:
				if record.has(field):
					if not record[field] is Array or record[field].size()>12:return false
					for item in record[field]:
						if not item is String or item.length()>96:return false
			for prior in record.history:
				if not prior is Dictionary or not prior.has_all(["detail","value","at","kind","reason","revision"]):return false
				if not prior.detail is String or prior.detail.length()>MAX_DETAIL or not prior.value is String or prior.value.length()>900:return false
				if prior.kind not in KINDS or prior.revision not in ["update","correction"] or not prior.reason is String or prior.reason.length()>MAX_DETAIL:return false
				if not (prior.at is int or prior.at is float) or not is_finite(float(prior.at)) or float(prior.at)<0:return false
			if JSON.stringify(record).length()>90000:return false
	return true
