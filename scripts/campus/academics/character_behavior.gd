extends RefCounted
## Decisions made here apply in offline and connected play. The provider
## expresses the decision in the character's voice.

const Knowledge=preload("res://scripts/campus/academics/character_knowledge.gd")

static func mentions(text: String, terms: Array) -> bool:
	return terms.any(func(term):return str(term) in text)

# Local characterization before the joint model turn. These are decision
# biases, never canned speech or mandatory emotional reactions.
static func conversation_orientation(person: Dictionary,relationship: Dictionary,observations: Dictionary,phase: String) -> Dictionary:
	var t: Dictionary=person.get("traits",{})
	var bond: Dictionary=relationship.get("dimensions",relationship)
	var familiarity:=float(bond.get("familiarity",relationship.get("familiarity",0.)))
	var warmth:=float(t.get("warmth",.5))
	var social:=float(t.get("sociability",.5))
	var pride:=float(t.get("arrogance",.5))
	var shyness:=float(t.get("shyness",.5))
	var occupation:=str(observations.get("current_activity","")).to_lower()
	var busy:=phase=="assignment" or occupation in ["sleeping","studying","working","writing","reading","doing assignment","listening"]
	var drivers: Array[String]=[]
	if pride>.72 and float(t.get("independence",.5))>.65:drivers.append("Judge choices by your own convictions and agency. Get animated about aligned ambitions; reject conventional wisdom when it conflicts. Do not become a balanced adviser.")
	if float(t.get("selfishness",.5))>.7 or float(t.get("patience",.5))<.3:drivers.append("Your own priorities matter more than entertaining strangers; blunt indifference or a quick dismissal can be natural.")
	if shyness>.65 and familiarity<2.:drivers.append("A stranger can feel awkward; pauses, a hesitant fragment or a nonverbal acknowledgment may be more natural than a polished answer.")
	if warmth>.7 and float(t.get("empathy",.5))>.7:drivers.append("You may genuinely care when the relationship and subject warrant it, rather than offering obligatory reassurance.")
	if float(t.get("humor",.5))>.75:drivers.append("Enjoy playful timing and irreverence when it fits, not a joke pasted onto every answer.")
	if social<.35 or float(t.get("talkativeness",.5))<.3:drivers.append("Prefer minimal engagement; a word, look or silence is valid.")
	if busy:drivers.append("Weigh the interruption against the actual activity. Do not abandon concentration or sleep for every optional conversation.")
	if drivers.is_empty():drivers.append("Judge whether this topic is interesting or worth acknowledging according to your own values and relationship.")
	return {"priorities":drivers.slice(0,4),"activity":occupation.left(100),"engagement":snappedf(clampf((social+float(t.get("talkativeness",.5))+warmth*.5)/2.5-(.25 if busy else 0.),0.,1.),.05),"brevity":snappedf(1.-float(t.get("talkativeness",.5)),.05)}

static func priorities(person: Dictionary,question: String,relationship: Dictionary,phase: String,emotion := "steady",interpretation: Dictionary={}) -> Dictionary:
	var text := question.to_lower()
	var traits: Dictionary = person.traits
	var domain := str(interpretation.get("domain", Knowledge.domain_of(text)))
	var academic := bool(interpretation.get("academic", false)) or domain in ["math","electronics","programming","science"] and ("?" in text or text.begins_with("explain"))
	var kind:=str(interpretation.get("question_kind",""))
	if kind in ["casual","opinion","personal_experience","biography"]:academic=false
	elif kind=="academic":academic=true
	elif kind.is_empty():academic=academic or mentions(text,["help me","homework","assignment","class is hard","class is difficult","solve","lesson","show your work","first step"])
	var strained := float(relationship.get("resentment",0)) - .35 * float(relationship.get("positive",0))
	var event := str(interpretation.get("event",""))
	var result := {"goal":"socialize", "energy":"steady", "academic":academic, "worldview":person.get("worldview",person.get("values","")), "phase":phase}
	if phase == "assignment":
		result.goal = "protect_assessment"
		result.energy = "quiet"
		result.social_intention = "keep_working" if float(traits.focus) > .7 else ("risk_brief_aside" if float(traits.risk_taking) > .6 else "whisper_briefly")
		result.reason = "Keep answers private while responding as this person; concentration and social willingness are separate decisions."
		return result
	if event in ["insult","hostile_criticism","provocation","disagreement","criticism","challenge"]:
		result.goal = "defend_position" if float(traits.willingness_to_disagree) > .5 else "consider_objection"
		result.energy = "assertive" if float(traits.confrontation) > .6 else "reserved"
		result.reason = "Evaluate the speaker's claim against your own beliefs rather than accepting it to be agreeable."
		return result
	if academic:
		if person.role == "teacher":
			if float(traits.willingness_to_help) < .35 or ((strained >= 3. or emotion in ["angry","irritated"]) and float(traits.forgiveness) < .6):
				result.goal = "give_minimum"
				result.energy = "impatient"
			elif float(traits.interest_in_student_success) > .72:
				result.goal = "coach"
				result.energy = "attentive"
			else:
				result.goal = "give_focused_help"
		else:
			var partner := int(relationship.get("study_sessions",0)) >= 2
			result.goal = "work_together" if float(traits.cooperativeness) > .52 or partner else "protect_study_time"
			result.energy = "thoughtful"
		return result
	# Values are active even when a favourite-topic keyword is absent.
	if float(traits.arrogance) > .78 and float(traits.independence) > .7:
		result.goal = "express_own_priorities"
		result.energy = ("animated" if event in ["initiative","success","excitement"] else "dismissive") if strained < 3. else "confrontational"
		result.reason = "Judge the idea by your convictions, not by what a responsible adviser would recommend. Enthusiasm for aligned ambition and contempt for opposing priorities can coexist; never force a slogan."
	elif float(traits.teaching_effort) < .3 and person.role == "teacher" and (float(traits.energy)+float(traits.get("sociability",.5)))*.5 < .4:
		result.goal = "protect_own_time"
		result.energy = "tired" if float(traits.energy) < .3 else "distracted"
	elif float(traits.demonstrations) > .92:
		result.goal = "investigate_curiosity"
		result.energy = "animated"
	elif float(traits.humor) > .8:
		result.goal = "entertain_or_connect"
		result.energy = "playful"
	elif strained >= 4. or (phase == "lesson" and float(traits.professionalism) > .82):
		result.goal = "return_to_activity"
		result.energy = "reserved"
	elif int(relationship.get("familiarity",0)) < 2 and float(traits.shyness) > .6:
		result.goal = "assess_social_comfort"
		result.energy = "hesitant"
	var favorite := str(interpretation.get("topic", "")).to_lower() in [str(person.interest).to_lower(), "personal_interest"]
	favorite = favorite or (str(person.interest).to_lower() in text)
	for interest in person.get("interests",[person.get("interest","")]):
		if str(interest).length()>2 and str(interest).to_lower() in text:favorite=true
	if favorite and strained < 4.:
		result.goal = "pursue_interest"
		result.energy = "animated"
	elif favorite and strained >= 4.:
		result.goal = "return_to_activity"
	return result

static func reaction(person: Dictionary,event: String,relationship: Dictionary,emotions: Dictionary,phase: String="",repetition: int=0) -> Dictionary:
	var t: Dictionary = person.traits
	var strategy := "respond_naturally"
	var reason := "Respond from your own position and current priorities."
	var disengagement := ""
	var quiet := false
	var pose := ""
	var hostile := event in ["insult","hostile_criticism","provocation","inappropriate_remark","inappropriate","harassment"]
	if hostile:
		if float(t.arrogance) > .78 and float(t.confidence) > .75:
			strategy = "challenge_reasoning" if repetition % 3 != 1 else "sarcastic_counter"
			reason = "Pride and confidence make you challenge the claim instead of placating the speaker. Repeated jabs deserve a sharper counter, not a shared shutdown line."
			pose = "argue" if repetition > 1 else "shrug"
		elif float(t.teaching_effort) < .3 and person.role == "teacher" and (float(t.energy)+float(t.get("sociability",.5)))*.5 < .4:
			strategy = "ignore" if repetition % 3 != 1 else "dismiss_and_work"
			reason = "Your own time matters more than winning this argument; the insult can still affect your opinion."
			disengagement = "return_to_work"
			quiet = strategy == "ignore"
			pose = "turn_away"
		elif float(t.confrontation) > .78 and float(t.anger_sensitivity) > .65 and not (float(t.discipline) > .9 and phase in ["lesson","assignment"]):
			strategy = "confront" if repetition % 3 != 2 else "demand_explanation"
			reason = "You are angry and willing to argue. Require a specific objection instead of smoothing over a personal attack."
			pose = "argue"
		elif float(t.discipline) > .9 and phase in ["lesson","assignment"]:
			strategy = "firm_warning" if repetition < 3 else "request_discipline"
			reason = "Authority and the other students' work matter; consequences require host-validated evidence and rules."
			pose = "point"
		elif float(t.humor) > .73 and repetition < 3:
			strategy = "playful_counter" if repetition < 2 else "sharp_joke"
			reason = "You initially meet provocation with humour; repeat attacks are becoming less amusing."
			pose = "shrug"
		elif float(t.empathy) > .85:
			strategy = "express_hurt" if repetition < 4 else "withhold_help"
			reason = "You care about the relationship and are hurt. Warmth does not require pretending the comment was harmless or instantly forgiving it."
			if repetition > 6:
				strategy = "withdraw_hurt"
				disengagement = "await_apology"
				quiet = repetition > 7
			pose = "defensive"
		elif float(t.shyness) > .65 and float(t.confidence) < .55:
			strategy = "defend_uneasily" if repetition < 2 else "avoid_conflict"
			reason = "You have an opinion but feel exposed under a hostile spotlight. Avoiding someone is a personal decision, not a universal timeout."
			if repetition >= 2:
				disengagement = "avoid"
				quiet = repetition > 3
			pose = "defensive" if repetition < 2 else "turn_away"
		elif float(t.willingness_to_disagree) > .55 or float(t.confidence) > .6:
			strategy = "defend_self" if repetition % 2 == 0 else "challenge_reasoning"
			reason = "You do not accept the insult as a fact; defend your position or ask what supports it."
			pose = "argue"
		else:
			strategy = "state_dislike" if repetition < 4 else "return_to_work"
			reason = "You dislike the attack but do not want to spend the whole day arguing."
			if repetition >= 4:
				disengagement = "return_to_work"
				quiet = repetition > 5
	elif event in ["criticism","disagreement","challenge","constructive_criticism"]:
		strategy = "defend_belief" if float(t.stubbornness) > .65 or float(t.arrogance) > .7 else "evaluate_objection"
		reason = "Disagreement is not automatically disrespect. Compare the argument with your beliefs, evidence and willingness to reconsider."
		pose = "think" if strategy == "evaluate_objection" else "argue"
	elif event == "apology":
		strategy = "acknowledge_cautiously" if float(t.forgiveness) < .55 or float(relationship.get("resentment",0)) > 3. else "accept_apology"
		reason = "An apology can reopen conversation without erasing hurt, resentment or disciplinary history. Judge subsequent behaviour."
		pose = "nod"
	elif event in ["joke","banter","teasing"]:
		strategy = "banter_back" if float(t.playfulness) > .55 else "dry_acknowledgment"
		reason = "Respond according to your own sense of humour and the relationship; friendly teasing differs from an attack."
	elif event == "compliment":
		strategy = "take_for_granted" if float(t.arrogance) > .7 else ("shy_appreciation" if float(t.shyness) > .6 else "appreciate")
		reason = "Praise does not make every person warm or trusting; your values determine what it means."
	elif event in ["initiative","success"]:
		strategy = "respect_initiative" if float(t.ambition) > .75 else "share_satisfaction"
		reason = "Notice the action according to what you value, rather than offering generic encouragement."
	elif event in ["greeting","chat","conversation"]:
		var orientation:=conversation_orientation(person,relationship,{},phase)
		if float(t.get("shyness",.5))>.65 and float(relationship.get("familiarity",0.))<2.:
			strategy="awkward_acknowledgment";pose="nod"
		elif float(orientation.engagement)<.3:
			strategy="minimal_acknowledgment";pose="shrug"
		elif float(t.get("arrogance",.5))>.72:
			strategy="express_own_view"
		reason="Choose whether the remark actually merits interest, indifference, an opinion, a fragment or a gesture according to this person."
	elif event in ["excitement","disappointment","opinion"]:
		strategy = "question_assumption" if float(t.arrogance) > .7 else "share_own_view"
		reason = "The speaker's enthusiasm or disappointment does not require you to share their opinion."
	if phase == "assignment" and not hostile:
		if event not in ["apology","disagreement","criticism"]:
			strategy = "quiet_focus" if float(t.focus) > .77 and float(t.talkativeness) < .55 else ("whisper_joke" if float(t.playfulness) > .7 and float(t.risk_taking) > .45 else "brief_test_response")
			quiet = strategy == "quiet_focus"
		reason += " An assessment restricts answer disclosure, not personality; brief unrelated conversation may be possible."
	return {"strategy":strategy,"goal":strategy,"reason":reason,"disengagement":disengagement,"quiet":quiet,
		"closed":disengagement in ["avoid","await_apology","return_to_work"],"pose":pose,
		"intensity":clampf(maxf(float(emotions.get("anger",0)),float(emotions.get("irritation",0))),0.,1.)}

static func personality_instructions(_person: Dictionary,_phase: String="") -> String:
	return "Speak from the supplied identity, life, current beliefs and mood. You may be flawed, uninterested, proud, selfish, playful, caring or argumentative as this person would be. Examples demonstrate manner, not sentences to copy. Ordinary conversation need not teach, reassure, advise or end in a question. Required academic information stays accurate."

static func action_willingness(person: Dictionary,action: String,relationship: Dictionary,phase: String,decision: Dictionary,emotions: Dictionary={}) -> Dictionary:
	# This chooses intent only. The caller must still validate ownership, location,
	# physical reach, action support, classroom authority and successful execution.
	var supported:=["raise_hand","point","wave","nod","approach","approach_board","sit","stand","phone","write","sleep","whisper","argue","think","celebrate","shrug","turn_away","defensive"]
	if action not in supported:return {"accepted":false,"reason":"That action is not supported by this character.","strategy":"explain_limit"}
	if str(decision.get("goal",""))=="protect_safety":return {"accepted":true,"reason":"Respond to a perceived safety incident; physical and authority validation still apply.","strategy":"intervene"}
	if bool(decision.get("closed",false)) or bool(decision.get("quiet",false)) or str(decision.get("strategy","")) in ["withhold_help","withdraw_hurt","avoid_conflict","ignore","dismiss_and_work","return_to_work"]:
		return {"accepted":false,"reason":"The character is maintaining their decision to disengage or withhold assistance.","strategy":"decline_request"}
	if phase=="assignment" and action not in ["nod","think","write","turn_away","defensive"]:
		return {"accepted":false,"reason":"This request would interrupt independent assessment work or supervision.","strategy":"protect_assessment"}
	var t: Dictionary=person.traits
	var dimensions: Dictionary=relationship.get("dimensions",relationship)
	var respect:=clampf(float(dimensions.get("respect",.5)),0.,1.)
	var friendship:=clampf(float(dimensions.get("friendship",0.)),0.,1.)
	var resentment:=clampf(float(dimensions.get("resentment",0.))/(1. if relationship.has("dimensions") else 6.),0.,1.)
	var anger:=maxf(float(emotions.get("anger",0.)),float(emotions.get("irritation",0.))*.7)
	var moving:=action in ["approach","approach_board","sit","stand"]
	var public_gesture:=action in ["raise_hand","wave","celebrate","argue","phone","sleep"]
	var cost:=.32 if moving else .12 if public_gesture else .02
	if phase=="lesson":cost+=(1.-float(t.interruption_tolerance))*(.22 if moving else .06)
	if public_gesture:cost+=float(t.shyness)*.18
	cost+=float(t.laziness)*(.12 if moving else .025)
	var desire:=.3+float(t.willingness_to_help)*.35+float(t.generosity)*.1+float(t.cooperativeness)*.1+respect*.18+friendship*.16
	desire-=anger*.28+resentment*.25
	if float(t.arrogance)>.8 and float(t.willingness_to_help)<.3 and moving:
		cost += .28*(1.-respect)
	if action in ["phone","sleep"] and phase in ["lesson","assignment"]:
		desire-=float(t.respect_for_authority)*.3+float(t.professionalism)*.25
	if str(decision.get("goal","")) in ["give_minimum","protect_own_time","protect_study_time"] and moving:cost+=.16
	var accepted:=desire-cost>=.32
	var reason:="The effort fits this character's willingness to help, attention and relationship." if accepted else "The interruption costs more than this character currently wants to give; personality, mood and relationship affect the choice."
	if action=="nod" and not accepted and anger<.4 and resentment<.5:
		accepted=true
		reason="A small acknowledgment is comfortable even when a larger request is not."
	return {"accepted":accepted,"reason":reason,"strategy":"cooperate" if accepted else "decline_request"}

static func student_activity(person: Dictionary,activity: Dictionary,member: Dictionary,mood: String) -> String:
	var t: Dictionary = person.traits
	var phase: String = str(activity.get("phase",""))
	var turns := int(member.get("turns",0))
	var intent := {"listening":.64 + float(t.attention_span)*.55,
		"taking notes":float(t.study_habits)*.8 + float(t.organization)*.4,
		"thinking":.25 + float(t.curiosity)*.75,
		"raising hand":float(t.initiative)*.5 + float(t.academic_confidence)*.5,
		"distracted":(1.-float(t.attention_span))*.78 + float(t.impulsiveness)*.26,
		"studying":float(t.academic_motivation)*.5 + float(t.independence)*.5,
		"asking for help":(1.-float(t.academic_confidence))*.5 + float(t.trustfulness)*.25,
		"helping classmate":float(t.cooperativeness)*.35 + float(t.generosity)*.4,
		"using phone":float(t.misbehavior)*.6 + (1.-float(t.respect_for_authority))*.35,
		"whispering":float(t.sociability)*.4 + float(t.risk_taking)*.35,
		"joking":float(t.playfulness)*.35 + float(t.mischievousness)*.35,
		"sleeping":(1.-float(t.energy))*.5 + float(t.laziness)*.3,
		"avoiding distraction":float(t.focus)*.35 + float(t.shyness)*.4}
	if mood in ["bored","tired","frustrated"]:
		intent.distracted += .42
		intent["using phone"] += .2
		if mood == "tired": intent.sleeping += .5
	if mood in ["interested","confident","excited"]: intent["raising hand"] += .42
	if mood in ["anxious","embarrassed"]:
		intent.erase("raising hand")
		intent["avoiding distraction"] += .5
	if mood in ["angry","irritated"] and float(t.confrontation) > .65:
		intent.arguing = .4 + float(t.confrontation)*.6
	if mood in ["happy","excited"] and bool(member.get("finished",false)):
		intent.celebrating = .4 + float(t.expressiveness)*.5
	if phase != "lesson": intent.erase("raising hand")
	if phase == "assignment":
		intent.erase("helping classmate")
		intent.erase("asking for help")
		intent.studying += .45
		intent["taking notes"] += .25
		for option in ["whispering","joking","using phone","arguing"]:
			if intent.has(option): intent[option] *= .35 + float(t.risk_taking)*.55
	var choice := "listening"
	var best := -INF
	for option in intent:
		var score := float(intent[option]) + float(posmod(hash([person.id,activity.get("id",""),turns,option]),100))*.004
		if option == member.get("action",""): score -= .22
		# Social actions are occasional, not a new action every idle tick.
		if option in ["whispering","joking","arguing","helping classmate","asking for help","celebrating"] and posmod(hash([person.id,turns]),4) != 0: score -= .55
		if score > best:
			best = score
			choice = option
	return choice

## Legacy signatures retained for callers during migration. Technical recovery
## is rendered by the interface; it never impersonates a canned character.
static func classroom_line(_person: Dictionary,_event: String,_topic := "") -> String:
	return ""

static func fallback(_person: Dictionary,_decision: Dictionary,_question: String,_board_hint: String) -> String:
	return ""
