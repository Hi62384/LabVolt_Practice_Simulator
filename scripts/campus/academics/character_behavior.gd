extends RefCounted
## Decisions made here apply in offline and connected play. The provider
## expresses the decision in the character's voice.

const Knowledge=preload("res://scripts/campus/academics/character_knowledge.gd")

static func priorities(person: Dictionary,question: String,relationship: Dictionary,phase: String,emotion := "steady") -> Dictionary:
	var text:=question.to_lower()
	var traits: Dictionary=person.traits
	var known_interest:=str(person.interest).to_lower()
	var favorite:=known_interest in text
	if person.id=="chad":
		favorite=mentions(text,["escape the matrix","escaping the matrix","financial independence","personal success","ambition","start a business","side hustle","discipline"])
	elif person.id=="mr_bro":
		favorite=mentions(text,["training","lifting","workout","squat","bench press","deadlift","personal record"])
	var academic:=mentions(text,["explain","help me","homework","assignment","class is hard","class is difficult","solve","formula","lesson","equation","show your work","first step"])
	academic=academic or (phase=="lesson" and "?" in text and Knowledge.domain_of(text) in ["math","electronics","programming"])
	var strained:=int(relationship.get("resentment",0))-.35*float(relationship.get("positive",0))
	if phase=="assignment":
		return {"goal":"protect_assessment","energy":"quiet","academic":academic}
	if favorite:
		return {"goal":"pursue_interest","energy":"animated","academic":false} if strained<4. else {"goal":"return_to_activity","energy":"reserved","academic":false}
	if academic and person.role=="teacher":
		if float(traits.willingness_to_help)<.35 or ((strained>=3. or emotion in ["angry","irritated"]) and float(traits.forgiveness)<.6):
			return {"goal":"give_minimum","energy":"impatient","academic":true}
		if float(traits.interest_in_student_success)>.72:
			return {"goal":"coach","energy":"attentive","academic":true}
		return {"goal":"give_focused_help","energy":"steady","academic":true}
	if academic and person.role=="student":
		var partner:=int(relationship.get("study_sessions",0))>=2
		var willing:=float(traits.cooperativeness)>.52 or partner
		return {"goal":"work_together" if willing else "protect_study_time","energy":"thoughtful","academic":true}
	var nonessential:=phase=="lesson" and float(traits.professionalism)>.82
	if strained>=4. or nonessential or (int(relationship.get("familiarity",0))<2 and float(traits.shyness)>.6):
		return {"goal":"return_to_activity","energy":"reserved","academic":false}
	return {"goal":"socialize","energy":"steady","academic":false}

static func student_activity(person: Dictionary,activity: Dictionary,member: Dictionary,mood: String) -> String:
	var traits: Dictionary=person.traits
	var practical: bool=activity.get("kind","")=="lab"
	var intent:={"listening":.52+float(traits.attention_span)*.48,
		"taking notes":float(traits.study_habits)*.85+float(traits.organization)*.3,
		"thinking":.26+float(traits.curiosity)*.75,
		"raising hand":float(traits.initiative)*.48+float(traits.academic_confidence)*.45,
		"distracted":(1.-float(traits.attention_span))*.78+float(traits.impulsiveness)*.26}
	if practical:intent["thinking"]+=.13
	if mood in ["bored","tired","frustrated"]:intent.distracted+=.42
	if mood in ["interested","confident","excited"]:intent["raising hand"]+=.42
	if mood in ["anxious","embarrassed"]:intent.erase("raising hand")
	if activity.phase!="lesson":intent.erase("raising hand")
	var choice:="listening"
	var best:=-INF
	for option in intent:
		var score:=float(intent[option])+float(posmod(hash([person.id,activity.id,member.turns,option]),100))*.004
		if option==member.action:score-=.22
		if score>best:
			best=score
			choice=option
	return choice

static func classroom_line(person: Dictionary,event: String,topic := "") -> String:
	var traits: Dictionary=person.traits
	var strict:=float(traits.strictness)>.65 or float(traits.discipline)>.86
	var caring:=float(traits.interest_in_student_success)>.78
	var disengaged:=float(traits.teaching_effort)<.35
	match event:
		"attendance":
			if strict:return "You're marked present. Take your seat and get your materials out."
			if caring:return "I've marked you present. Come settle in. There's time to get your bearings."
			return "You're on the roll. Take a seat." if disengaged else "You're marked present. Find a seat and join us when you're ready."
		"practice":
			if strict:return "Write down what you know. Show each step and check your answer before handing it in."
			if disengaged:return "The next question's up. Show your work and submit it when you're done."
			if float(traits.demonstrations)>.9:return "Make a prediction first. See if the example we just tried backs it up, then show your reasoning."
			if caring:return "Try the first step on your own. If it feels stuck, write down what you know and start there."
			return "Try this next question. Show your reasoning, then submit."
		"assessment":
			if person.id=="mr_bro":return "All right, this is your set. Take it one problem at a time. Show your work and hand it in when you're done."
			if disengaged:return "The %s assessment is ready. Instructions are on the sheet. Hand it in when you're done."%topic
			if strict:return "%s assessment. Work independently, show your steps, and submit your own work."%topic
			if caring:return "Start with a question you know. You can come back to the hard ones. Hand in your own work when you're ready."
	return ""

static func mentions(text: String,phrases: Array) -> bool:
	for phrase in phrases:
		if phrase in text:return true
	return false

static func fallback(person: Dictionary,decision: Dictionary,question: String,board_hint: String) -> String:
	var lower:=question.to_lower()
	if person.id=="mr_bro" and "bench press" in lower and mentions(lower,["record","best","pr","how much"]):
		return "315 pounds, bro. Took me way longer once I stopped pretending sleep was optional."
	if person.id=="chad":
		if decision.goal=="pursue_interest":
			if mentions(lower,["business","start","hustle"]):return "Start small enough that losing doesn't wreck you. My first store taught me that the expensive way."
			return "I mean having enough say over your own life that a boss can't make every decision for you. That's my take, anyway."
		if decision.goal=="give_minimum":
			if mentions(lower,["hard","difficult","struggl","stuck"]):return "Yeah, it's hard. Pick a step you can actually try and quit waiting for the whole thing to click."
			if not board_hint.is_empty():return board_hint+" That's your starting point. Work the rest out."
			return "Show me a step you tried. I'm not doing the whole thing for you."
	if person.id=="ms_rivera" and decision.goal=="give_minimum":
		return board_hint if not board_hint.is_empty() else "Start with the worked example. I'll look after you've tried it."
	return ""
