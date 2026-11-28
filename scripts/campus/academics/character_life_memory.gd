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
	return " ".join(terms(value))

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
	return {"ok":true,"record":{"id":old_topic if not old_topic.is_empty() else topic,"topic":old_topic if not old_topic.is_empty() else topic,
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
	var lower := speech.to_lower().replace("’","'")
	var spoken_terms := terms(speech)
	var proposed_topics: Array[String] = []
	for proposal in proposals:
		if proposal is Dictionary:proposed_topics.append(canonical(str(proposal.get("topic",""))))
	for record in records.values():
		var title := terms(str(record.topic))
		var subjects := title.filter(func(term):return term not in ["record","train","prefer","personal","history","current","value"])
		var shared := 0
		for term in title:
			if term in spoken_terms:shared += 1
		if shared==0:continue
		if not subjects.is_empty() and not subjects.any(func(term):return term in spoken_terms):continue
		var old_numbers: Array[String] = []
		for number in numbers.search_all(str(record.value)):old_numbers.append(number.get_string())
		var new_numbers: Array[String] = []
		for number in numbers.search_all(speech):new_numbers.append(number.get_string())
		if not old_numbers.is_empty() and not new_numbers.is_empty() and canonical(str(record.topic)) not in proposed_topics:
			if not old_numbers.any(func(n):return n in new_numbers):
				return {"ok":false,"review":false,"reason":"Spoken quantities conflict with a relevant established personal fact, including when no memory update was proposed."}
		if ["never ","i haven't ","i have not ","i didn't ","i don't ","no longer ","i used to "].any(func(s):return s in lower):review=true
	if personal and proposals.is_empty() and not numbers.search_all(speech).is_empty():
		# Recalling an existing value is fine; an unrecorded new one is not.
		var recalled := records.values().any(func(r):return not numbers.search_all(str(r.value)).is_empty() and numbers.search_all(str(r.value)).all(func(n):return n.get_string() in speech))
		if not recalled:return {"ok":false,"review":false,"reason":"New numerical personal information must be proposed for persistent memory."}
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
