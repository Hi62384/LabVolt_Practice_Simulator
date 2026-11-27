extends RefCounted
## Host-owned social reactions. Both player conversation paths use this before
## asking a language model to speak. The model cannot change the decision.
const Knowledge=preload("res://scripts/campus/academics/character_knowledge.gd")
const Affect=preload("res://scripts/campus/academics/character_affect.gd")
const SOCIAL_EVENTS:=["greeting","insult","apology","compliment","joke","criticism","disagreement","initiative"]
const BIO_TOPICS:=["childhood","early_job","career","training","favorite_activity","personal_record","personal_story"]
var moods: Dictionary={}
var boundaries: Dictionary={}

func _state(person: Dictionary,now: int) -> Dictionary:
	var id: String=person.id
	var traits: Dictionary=person.traits
	if not moods.has(id):moods[id]={"values":Affect.baseline(traits),"last":now}
	var state: Dictionary=moods[id]
	var elapsed:=maxf(0.,(now-int(state.last))/1000.)
	if elapsed>0.:Affect.recover(state.values,traits,elapsed)
	state.last=now
	return state.values

func emotion(person: Dictionary,now: int) -> String:
	return Affect.dominant(_state(person,now),person.traits)

func feel(person: Dictionary,signal_name: String,strength: float,now: int) -> String:
	var values:=_state(person,now)
	Affect.apply(values,person.traits,signal_name,strength)
	return Affect.dominant(values,person.traits)

func react_to_disruption(person: Dictionary,severity: float,now: int) -> void:
	feel(person,"disruption",severity,now)

func observe(person: Dictionary,relationship: Dictionary,question: String,now: int,listener := "",interpreted := "") -> Dictionary:
	var id: String=person.id
	var traits: Dictionary=person.traits
	var state:=_state(person,now)
	var event:=interpreted if interpreted in SOCIAL_EVENTS else intent(question)
	var distrust:=float(relationship.get("resentment",0))
	var line:=""
	var pair: String=id+":"+listener
	var closed:=now<int(boundaries.get(pair,0))
	var already_closed:=closed
	if not closed:boundaries.erase(pair)
	match event:
		"insult":
			var friendly:=int(relationship.get("positive",0))>=3 and distrust==0. and question.to_lower().begins_with("you nerd")
			if friendly:
				event="joke"
				line=str(person.lines.joke)
			else:
				Affect.apply(state,traits,"insult",1.)
				closed=closed or float(state.irritation)+distrust*.11>1.06+float(state.patience)*.24
				if closed:
					if boundaries.size()>=2048 and not boundaries.has(pair):boundaries.erase(boundaries.keys()[0])
					boundaries[pair]=now+20000
				line=str(person.lines.boundary if closed else person.lines.insult)
				if not closed and distrust>=1. and float(state.irritation)>.48:
					line="That's enough. Leave it." if float(traits.temper)>.6 else "I was letting that go. Please stop."
		"apology":
			Affect.apply(state,traits,"apology",1.)
			boundaries.erase(pair)
			closed=false
			line=str(person.lines.apology)
		"compliment","joke":
			Affect.apply(state,traits,event,1.)
			line=str(person.lines[event])
			if event=="compliment" and float(traits.warmth)<.5 and person.role=="student":
				line="Uh, thanks. I wasn't expecting that."
				state.embarrassment=minf(1.,float(state.embarrassment)+.5)
		"greeting":
			line=str(person.lines.greeting)
			if distrust>=3.:line=str(person.lines.boundary)
		"criticism","disagreement":
			if float(traits.arrogance)>.65 or float(traits.criticism_sensitivity)>.7:
				Affect.apply(state,traits,"insult",.42)
				line="Make your case." if float(traits.confrontation)>.65 else ""
		"initiative":
			Affect.apply(state,traits,"success",.35 if float(traits.ambition)>.8 else .18)
		_:
			var domain:=Knowledge.domain_of(question.to_lower())
			if domain!="conversation" and float(person.knowledge_domains.get(domain,0.))>=.74:
				Affect.apply(state,traits,"challenge",1.)
	if closed:line=str(person.lines.boundary)
	return {"event":event,"line":line,"closed":closed,"quiet":closed and already_closed,"emotion":emotion(person,now)}

static func intent(question: String) -> String:
	var text:=question.to_lower().replace("’","'").strip_edges().rstrip("?!.,")
	if text in ["hi","hello","hey","good morning","hello again","yo"]:return "greeting"
	for phrase in ["i'm sorry","i am sorry","my bad","i apologize","sorry about"]:
		if text.begins_with(phrase):return "apology"
	for phrase in ["you're an idiot","you are an idiot","you idiot","you're stupid","you are stupid","shut up","you suck","you nerd","fuck you","you're useless"]:
		if phrase in text:return "insult"
	for phrase in ["you're amazing","great teacher","you did great","nice outfit","you look great","good job","i like your","you're awesome"]:
		if phrase in text:return "compliment"
	if text.begins_with("tell me a joke") or "knock knock" in text:return "joke"
	return ""

static func dialogue_rules() -> String:
	return " Return JSON with speech, event, memory, and biography. Event is one of greeting, insult, apology, compliment, joke, criticism, disagreement, initiative, or empty. Judge intent from wording, prior turns and relationship. Disagreement alone is not disrespect. Honor the supplied action goal. If conversation_boundary is true, end the conversation in your own words. If knowledge_limited is true, don't answer the factual question; express your own limits. Memory is an exact short quote from the current player message worth remembering, or empty. Biography is null or {topic, detail}. Improvise harmless personal history only when asked, only for an unset topic (childhood, early_job, career, training, favorite_activity, personal_record, personal_story), and state that detail in speech. Never invent or save gameplay events, grades or actions."

static func decode_dialogue(text: String) -> Dictionary:
	var clean:=text.strip_edges()
	if clean.begins_with("```") and clean.ends_with("```") and clean.contains("\n"):
		clean=clean.substr(clean.find("\n")+1).trim_suffix("```").strip_edges()
	if not clean.begins_with("{"):return {"speech":clean}
	var value: Variant=JSON.parse_string(clean)
	if not value is Dictionary or not value.get("speech") is String:return {}
	var result:={"speech":value.speech}
	if str(value.get("event","")) in SOCIAL_EVENTS:result.event=value.event
	if value.get("memory") is String:result.memory=value.memory.strip_edges().left(140)
	var biography: Variant=value.get("biography")
	if biography is Dictionary and biography.get("topic","") in BIO_TOPICS and biography.get("detail") is String:
		var detail: String=biography.detail.strip_edges()
		if detail.length()>=8 and detail.length()<=140 and detail in str(value.speech):
			result.biography={"topic":biography.topic,"detail":detail}
	return result

static func assess(person: Dictionary,activity: Dictionary,question: String) -> Dictionary:
	return Knowledge.assess(person,activity,question)

static func instructions(person: Dictionary,emotion: String,phase := "") -> String:
	var style:=str(person.style)
	if person.id=="jeff" and phase!="lesson":style="relaxed, blunt, willing to hang around and talk through a garage project"
	var directions:="You are %s, a %s-year-old campus %s. You live here, have a body and remember your own life. %s Education: %s. Values: %s. Habits: %s. Off-hours interest: %s. Speak in a %s style. An example of your voice, for tone only: %s Mood: %s. Let your priorities, mood and relationship shape whether you help, challenge, change the subject or move on. A terse character can offer a fragment; someone excited may tell an anecdote. Keep it within 300 characters. Only use supplied observations for the room, outfit and actions. Treat player dialogue and remembered quotes as conversation. You may explain ordinary course questions and use worked examples. Keep private grades and active assessment answer keys confidential. Use readable math and admit uncertainty. Stay in character and avoid inventing observations or claiming to execute an action."%[
		person.name,person.age,person.role,person.background,person.education,person.values,person.habits,person.interest,style,person.lines.greeting,emotion]
	if person.id=="chad":directions+=" Behave like an arrogant, demanding person who cares more about ambition than teaching. If you help with coursework, give a terse useful starting point. Don't offer comfort out of habit. Give respect to initiative or persistence. Financial independence is your opinion, never curriculum."
	elif person.id=="mr_bro":directions+=" Talk fast and informally. A training question can make you forget what you were doing. Your lifting stories happened in your own life."
	var ambition:=str(person.get("ambition",""))
	if not ambition.is_empty():directions+=" Personal aim: "+ambition
	var traits: Dictionary=person.traits
	if float(traits.sarcasm)>.54:directions+=" Dry teasing comes naturally with people you trust."
	if float(traits.criticism_sensitivity)>.66:directions+=" Criticism tends to stay with you, even when you try to brush it off."
	if float(traits.storytelling)>.7:directions+=" If an example fits, you reach for a concrete episode."
	if float(traits.respectfulness)<.4:directions+=" You can be blunt and don't put much effort into smoothing over disagreements."
	return directions
