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

## Used only while the dialogue provider is unavailable. Connected play sends
## an intention through the same semantic/memory pipeline as player speech.
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

static func fallback_reply(person: Dictionary,question: String,history: Array,phase: String,relationship: Dictionary,topic: String="") -> String:
	var traits: Dictionary=person.traits
	var variant:=posmod(hash([person.id,question,history.size(),relationship.get("familiarity",0)]),3)
	var last:=""
	if not history.is_empty():last=str(history[-1].get("teacher",history[-1].get("response","")))
	var options: Array=[]
	if phase=="assignment":
		if float(traits.get("anxiety",traits.get("criticism_sensitivity",.5)))>.73:
			options=["Shh, I really need to concentrate.","Please, I'm already nervous enough.","Can this wait until I've handed it in?"]
		elif float(traits.get("confrontation",.5))>.7:
			options=["Give me a minute. I'm in the middle of this.","Come on, let me finish.","Ask me when I'm done."]
		elif float(traits.get("humor",.5))>.7:
			options=["My brain's got one tab open right now.","Catch me after this. I'm negotiating with the clock.","Hold that thought. I'm trying to have one of my own."]
		elif int(relationship.get("positive",0))>=2:
			options=["Give me a minute, okay? I'll find you after.","After we finish. I want to hear it properly.","Let me get through this first, then we can talk."]
		else:
			options=["I'm concentrating. Later?","Just a moment. I need to finish this.","Can we talk after I hand this in?"]
	elif ["hobby","free time","interest"].any(func(word):return word in question.to_lower()):
		options=["I'm into %s."%person.interest,"Mostly %s when I get some time to myself."%person.interest,"Lately it's been %s."%person.interest]
	elif "sorry" in question.to_lower():
		options=["I heard you. Give me a bit.","Okay. I'd rather see things change.","Let's leave it there for now."] if int(relationship.get("resentment",0))>1 else ["Okay, we're fine.","Don't worry about it.","All right. Let's move on."]
	elif int(relationship.get("resentment",0))>2:
		options=["What do you want?","You had plenty to say earlier.","I'm not in the mood for another round."]
	elif question.strip_edges().to_lower() in ["hi","hello","hey"]:
		options=[str(person.lines.greeting),"Hey. How's it going?","Oh, hey."]
	elif not topic.is_empty():
		options=["I'm still thinking about %s."%topic,"I need another look at my notes on %s."%topic,"That part about %s has me thinking."%topic]
	else:
		options=["I've been thinking about %s lately."%person.interest,"What was that? I was a bit distracted.","Give me a second to think about that."]
	for offset in options.size():
		var line: String=options[(variant+offset)%options.size()]
		if line!=last:return line
	return options[variant%options.size()]
