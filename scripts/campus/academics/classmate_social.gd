extends RefCounted
## Social choices are made from people actually sharing a room. Friendly and
## competitive ties can coexist, and willingness to study is directional.

static func choose(actors: Array,brain: RefCounted,used_pairs: Dictionary) -> Array:
	var best: Array=[]
	var best_score:=-INF
	var now:=int(Time.get_unix_time_from_system())
	for speaker in actors:
		var person: Dictionary=speaker.profile
		if float(person.traits.initiative)<.36:continue
		for listener in actors:
			var other: Dictionary=listener.profile
			if person.id==other.id or pair_key(person.id,other.id) in used_pairs:continue
			var distance: float=(speaker.position as Vector3).distance_to(listener.position)
			if distance>3.5:continue
			var history: Dictionary=brain.relationship_at(person.id,other.id,now)
			var reverse: Dictionary=brain.relationship_at(other.id,person.id,now)
			if int(history.get("resentment",0))>=3 or int(reverse.get("resentment",0))>=3:continue
			var social: Dictionary=brain.social_context(history)
			var score:=float(person.traits.initiative)+float(social.friendship)*1.6+float(social.rivalry)*.8-distance*.16
			if person.interest==other.interest:score+=.34
			if score>best_score:
				best_score=score
				best=[speaker,listener,history,reverse]
	return best

static func pair_key(first: String,second: String) -> String:
	return first+":"+second if first<second else second+":"+first

static func exchange(person: Dictionary,other: Dictionary,history: Dictionary,reverse: Dictionary,topic: String) -> Dictionary:
	var name:=str(other.name).get_slice(" ",0)
	if int(history.get("competitions",0))>=2:
		return {"kind":"rivalry","line":"Another quiz today, %s? We've been close the last few times."%name,
			"reply":"You're on. We can compare methods afterward." if int(reverse.get("study_sessions",0))>=2 else
				("You're on. Let's see who's quicker today." if float(other.traits.competitiveness)>.55 else "Sure. I'd rather get it right than get it fast.")}
	if int(history.familiarity)>=2 or (person.interest==other.interest and int(history.familiarity)>=1):
		var willingness:=float(other.traits.cooperativeness)+float(reverse.get("study_sessions",0))*.075
		var ready: bool=willingness>=.45 or person.interest==other.interest
		var prompt:="Hey, %s. What did you write down about %s?"%[name,topic] if not topic.is_empty() else "Hey, %s. I marked the step where I got stuck. What did you try?"%name
		if int(history.get("study_sessions",0))>=3:prompt="Saved you a spot, %s. Want to work together again?"%name
		return {"kind":"study" if ready else "decline","line":prompt,
			"reply":"I wrote down what we knew first, then compared it with the example. Let me see your notes." if ready else "I'm going to work through it on my own this time."}
	return {"kind":"greeting","line":person.lines.greeting,
		"reply":other.lines.greeting if float(other.talk)<.53 else "Oh, hey. I was reading about %s before class."%other.interest}
