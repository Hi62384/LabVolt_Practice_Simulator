extends RefCounted
## Extractive views over retained records. No generated prose or inferred
## misconception becomes a new fact; originals remain the source of truth.
const Knowledge=preload("res://scripts/campus/academics/character_knowledge.gd")
const COURSES:={"MTH147":"math","MTH255":"math","ETY155":"electronics","ELM253":"electronics","DGS266":"electronics"}
const RECENT_OUTCOMES:=12
const RECENT_WEEKS:=8

static func academic(character: String,observer: String,episodes: Array) -> Dictionary:
	var result:={"source":"verified_host_activity","character_id":character,"observer_id":observer,"courses":{},"misconceptions":[],
		"limitations":"Checked outcomes describe performance, not a diagnosis of why an answer was wrong. No solutions or marks are included."}
	var courses: Dictionary=result.courses
	for episode in episodes:
		if not episode is Dictionary or episode.get("source","")!="host_activity":continue
		if str(episode.get("speaker",""))!=character or str(episode.get("character",""))!=observer:continue
		var activity: Variant=episode.get("activity")
		if not activity is Dictionary or activity.get("kind") not in ["assessment","quiz","lab"] or not activity.get("correct") is bool:continue
		var course:=str(activity.get("course",""))
		if not COURSES.has(course):continue
		var entry: Dictionary=courses.get_or_add(course,{"domain":COURSES[course],"attempts":0,"successes":0,"difficulties":0,"weeks":{},"activity_kinds":{},"_recent":[],"_week_order":[]})
		var correct: bool=activity.correct
		entry.attempts+=1;entry.successes+=int(correct);entry.difficulties+=int(not correct)
		entry.activity_kinds[activity.kind]=int(entry.activity_kinds.get(activity.kind,0))+1
		entry._recent.append(correct)
		if entry._recent.size()>RECENT_OUTCOMES:entry._recent.pop_front()
		var week:=int(activity.get("week",0))
		if week>0 and week<=52:
			var key:=str(week)
			var weekly: Dictionary=entry.weeks.get_or_add(key,{"attempts":0,"successes":0,"difficulties":0})
			weekly.attempts+=1;weekly.successes+=int(correct);weekly.difficulties+=int(not correct)
			entry._week_order.erase(key);entry._week_order.append(key)
	for course in courses:
		var entry: Dictionary=courses[course]
		var recent: Array=entry._recent
		entry.recent_attempts=recent.size()
		entry.recent_successes=recent.count(true)
		entry.recent_difficulties=recent.count(false)
		entry.recent_success_rate=float(entry.recent_successes)/maxi(1,recent.size())
		entry.strengths=[];entry.practice_needs=[]
		entry.trend="insufficient_evidence"
		entry.uncertainty="There are too few checked attempts to establish a pattern."
		if recent.size()>=3:
			entry.uncertainty="Performance can vary by task. The specific cause of errors has not been diagnosed."
			entry.trend="mixed"
			if float(entry.recent_success_rate)>=.7:entry.strengths.append("Repeated successful checked work in "+course+".")
			if int(entry.recent_difficulties)>=2 and float(entry.recent_success_rate)<.6:
				entry.practice_needs.append("Repeated difficulty with checked "+course+" work; review the method without assuming a specific misconception.")
				entry.trend="struggling"
			if recent.size()>=6:
				var halfway:=recent.size()/2
				var earlier:=float(recent.slice(0,halfway).count(true))/halfway
				var later:=float(recent.slice(halfway).count(true))/(recent.size()-halfway)
				if later-earlier>=.3:entry.trend="improving"
				elif earlier-later>=.3:entry.trend="struggling"
		var order: Array=entry._week_order
		while order.size()>RECENT_WEEKS:entry.weeks.erase(order.pop_front())
		for weekly in entry.weeks.values():
			weekly.pattern="insufficient_evidence" if int(weekly.attempts)<3 else ("repeated_success" if float(weekly.successes)/float(weekly.attempts)>=.7 else ("repeated_difficulty" if int(weekly.difficulties)>=2 else "mixed"))
		entry.erase("_recent");entry.erase("_week_order")
	return result

static func topics(exchanges: Array,facts: Dictionary,episodes: Array,question: String,concepts: Dictionary,limit: int=4) -> Array:
	var buckets:={}
	for exchange in exchanges:
		var text:=str(exchange.get("student",""))+" "+str(exchange.get("teacher",""))
		var topic:=_topic(text,"",str(exchange.get("event","")),concepts)
		var at:=int(exchange.get("at",0))
		var summary:=_bucket(buckets,topic,at)
		summary.exchange_count+=1
		summary.latest_exchange={"at":at,"event_id":str(exchange.get("event_id","")),"speaker_excerpt":str(exchange.get("student","")).left(240),"reply_excerpt":str(exchange.get("teacher","")).left(240)}
		if str(exchange.get("teacher","")).is_empty() and "?" in str(exchange.get("student","")):
			summary.unanswered_questions.append({"at":at,"event_id":str(exchange.get("event_id","")),"excerpt":str(exchange.student).left(180)})
			if summary.unanswered_questions.size()>2:summary.unanswered_questions.pop_front()
	for subject in facts:
		var fact: Dictionary=facts[subject]
		var topic:=_topic(str(fact.get("statement","")),str(fact.get("domain","")),"",concepts)
		var summary:=_bucket(buckets,topic,int(fact.get("at",0)))
		summary.fact_count+=1
		summary.reported_facts.append({"subject":str(subject),"at":int(fact.get("at",0)),"excerpt":str(fact.get("statement","")).left(240),"source":str(fact.get("source","speaker_statement"))})
		summary.reported_facts.sort_custom(func(a,b):return int(a.at)>int(b.at))
		if summary.reported_facts.size()>2:summary.reported_facts.pop_back()
	for episode in episodes:
		var topic:=_topic(str(episode.get("description","")),"",str(episode.get("event","")),concepts)
		if episode.get("source","")=="host_activity":topic=str(episode.get("activity",{}).get("course",topic))
		var at:=int(episode.get("at",0))
		var summary:=_bucket(buckets,topic,at)
		summary.episode_count+=int(episode.get("count",1))
		var kind:=str(episode.get("event","conversation"))
		summary.events[kind]=int(summary.events.get(kind,0))+int(episode.get("count",1))
		summary.notable_experiences.append({"at":at,"event_id":str(episode.get("event_id","")),"event":kind,"excerpt":str(episode.get("description","")).left(320),"resolved":bool(episode.get("resolved",false)),"source":str(episode.get("source","stored_episode")),"_importance":float(episode.get("importance",.5))})
		summary.notable_experiences.sort_custom(func(a,b):return int(a.at)>int(b.at) if is_equal_approx(float(a._importance),float(b._importance)) else float(a._importance)>float(b._importance))
		if summary.notable_experiences.size()>2:summary.notable_experiences.pop_back()
	var selected: Array=buckets.values()
	var wanted:=_topic(question,Knowledge.domain_of(question),"",concepts)
	selected.sort_custom(func(a,b):
		if (a.topic==wanted)!=(b.topic==wanted):return a.topic==wanted
		return int(a.last_at)>int(b.last_at))
	selected=selected.slice(0,clampi(limit,1,8))
	for summary in selected:
		for experience in summary.notable_experiences:experience.erase("_importance")
	return selected

static func _bucket(buckets: Dictionary,topic: String,at: int) -> Dictionary:
	var summary: Dictionary=buckets.get_or_add(topic,{"topic":topic,"summary_kind":"extractive_records","first_at":at,"last_at":at,
		"exchange_count":0,"episode_count":0,"fact_count":0,"events":{},"latest_exchange":{},"notable_experiences":[],"reported_facts":[],"unanswered_questions":[]})
	summary.first_at=mini(int(summary.first_at),at);summary.last_at=maxi(int(summary.last_at),at)
	return summary

static func _topic(text: String,domain: String,event: String,concepts: Dictionary) -> String:
	if not domain.is_empty() and domain!="conversation":return domain
	if event in ["insult","apology","criticism","hostile_criticism","manipulation","provocation","inappropriate"]:return "relationship_conflict"
	var lower:=text.to_lower()
	for concept in concepts:
		for word in concepts[concept]:
			if str(word) in lower:return str(concept)
	var inferred:=Knowledge.domain_of(lower)
	return inferred if inferred!="conversation" else "general_conversation"
