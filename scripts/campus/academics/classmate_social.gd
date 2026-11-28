extends RefCounted
## Social choices are made from people actually sharing a room. Friendly and
## competitive ties can coexist, and willingness to study is directional.

static func choose(actors: Array,brain: RefCounted,used_pairs: Dictionary,phase: String="arrival") -> Array:
	var best: Array=[]
	var best_score:=-INF
	var now:=int(Time.get_unix_time_from_system())
	for speaker in actors:
		var person: Dictionary=speaker.profile
		if float(person.traits.initiative)<.25 or bool(speaker.get("removed_from_class",false)):continue
		if phase=="assignment" and str(speaker.get("action","")) not in ["whispering","joking","arguing"]:continue
		for listener in actors:
			var other: Dictionary=listener.profile
			if person.id==other.id or pair_key(person.id,other.id)+":"+phase in used_pairs or bool(listener.get("removed_from_class",false)):continue
			var distance: float=(speaker.position as Vector3).distance_to(listener.position)
			if distance>3.5:continue
			var history: Dictionary=brain.relationship_at(person.id,other.id,now)
			var reverse: Dictionary=brain.relationship_at(other.id,person.id,now)
			var social: Dictionary=brain.social_context(history)
			var resentment:=float(social.get("resentment",0.))
			if resentment>.45 and float(person.traits.confrontation)<.6:continue
			var score:=float(person.traits.initiative)+float(social.friendship)*1.6+float(social.rivalry)*.8-distance*.16
			score+=resentment*float(person.traits.confrontation)*.45
			if phase=="lesson":score-=float(person.traits.get("respect_for_authority",.5))*.8
			if str(speaker.get("action","")) in ["whispering","joking","arguing","helping classmate"]:score+=.5
			if person.interest==other.interest:score+=.34
			if score>best_score:
				best_score=score
				best=[speaker,listener,history,reverse]
	return best

static func pair_key(first: String,second: String) -> String:
	return first+":"+second if first<second else second+":"+first

static func intention(person: Dictionary,other: Dictionary,history: Dictionary,reverse: Dictionary,phase: String,action: String="") -> Dictionary:
	var purpose:="get to know a classmate"
	var kind:="greeting"
	if action=="arguing" or (int(history.get("resentment",0))>1 and float(person.traits.confrontation)>.6):
		kind="disagreement"
		purpose="raise an unresolved disagreement from real shared memory; if none exists, disagree about an ordinary opinion without inventing misconduct"
	elif int(history.get("competitions",0))>=2:
		kind="rivalry"
		purpose="talk about the competition you remember, without inventing scores"
	elif action in ["helping classmate","studying"] or int(history.get("study_sessions",0))>=2:
		kind="study"
		purpose="offer or request a little help with the lesson, guided by your actual willingness and ability"
	elif action in ["joking","whispering"]:
		kind="banter"
		purpose="share a quiet aside in your own sense of humor and relationship with this classmate"
	elif person.interest==other.interest:
		kind="shared_interest"
		purpose="start a conversation about your shared interest; refer to established memories if relevant"
	elif int(history.get("familiarity",0))>=2:
		purpose="reconnect with this familiar person based on your actual relationship and memories"
	if phase=="lesson":purpose+="; keep it brief and quiet because the teacher is teaching"
	if phase=="assignment":purpose="initiate one brief, quiet social aside in your own manner, unrelated to assessed work; nobody has spoken to you yet. Do not discuss answers, methods, questions, marks, or another student's work, and let the classmate return to concentrating"
	return {"kind":kind,"purpose":purpose,"other_name":str(other.name),"other_interest":str(other.interest),"phase":phase}

## A disconnected service is not an invented student conversation. These
## compatibility entry points stay silent; the UI exposes technical status.
static func exchange(_person: Dictionary,_other: Dictionary,_history: Dictionary,_reverse: Dictionary,_topic: String) -> Dictionary:
	return {"kind":"unavailable","line":"","reply":""}

static func fallback_reply(_person: Dictionary,_question: String,_history: Array,_phase: String,_relationship: Dictionary,_topic: String="") -> String:
	return ""
