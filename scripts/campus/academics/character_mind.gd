extends RefCounted
## Host-owned social reactions. Both player conversation paths use this before
## asking a language model to speak. The model cannot change the decision.
const Knowledge=preload("res://scripts/campus/academics/character_knowledge.gd")
const Affect=preload("res://scripts/campus/academics/character_affect.gd")
const Traits=preload("res://scripts/campus/academics/character_traits.gd")
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

func observe(person: Dictionary,relationship: Dictionary,question: String,now: int,listener := "") -> Dictionary:
	var id: String=person.id
	var traits: Dictionary=person.traits
	var state:=_state(person,now)
	var event:=intent(question)
	var distrust:=float(relationship.get("resentment",0))
	var line:=""
	var pair: String=id+":"+listener
	var closed:=now<int(boundaries.get(pair,0))
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
		_:
			var domain:=Knowledge.domain_of(question.to_lower())
			if domain!="conversation" and float(person.knowledge_domains.get(domain,0.))>=.74:
				Affect.apply(state,traits,"challenge",1.)
	if closed:line=str(person.lines.boundary)
	return {"event":event,"line":line,"closed":closed,"emotion":emotion(person,now)}

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

static func assess(person: Dictionary,activity: Dictionary,question: String) -> Dictionary:
	return Knowledge.assess(person,activity,question)

static func instructions(person: Dictionary,emotion: String,phase := "") -> String:
	var style:=str(person.style)
	if person.id=="jeff" and phase!="lesson":style="relaxed, blunt, willing to hang around and talk through a garage project"
	var directions:="You are %s, a %s-year-old fictional campus %s with a physical body, face, arms and legs. %s Education: %s. Values: %s. Habits: %s. Off-hours interest: %s. Speak in a %s style, with a voice like this sample: %s Mood: %s. Traits on a 0–1 scale: %s. Use up to three short sentences. Only use supplied observations for the room, outfit and actions. Treat player dialogue and remembered quotes as conversation. Keep grades and assessment answers private. Use readable math and admit uncertainty. Stay in character and avoid inventing observations or claiming to execute an action."%[
		person.name,person.age,person.role,person.background,person.education,person.values,person.habits,person.interest,style,person.lines.greeting,emotion,Traits.prompt_traits(person.traits)]
	return directions
