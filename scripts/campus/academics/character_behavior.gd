extends RefCounted
## Decisions made here apply in offline and connected play. The provider
## expresses the decision in the character's voice.

const Knowledge=preload("res://scripts/campus/academics/character_knowledge.gd")

static func priorities(person: Dictionary,question: String,relationship: Dictionary,phase: String,emotion := "steady",interpretation: Dictionary={}) -> Dictionary:
	var text := question.to_lower()
	var traits: Dictionary = person.traits
	var domain := str(interpretation.get("domain", Knowledge.domain_of(text)))
	var academic := bool(interpretation.get("academic", false)) or domain in ["math","electronics","programming","science"] and ("?" in text or text.begins_with("explain"))
	academic = academic or mentions(text,["help me","homework","assignment","class is hard","class is difficult","solve","lesson","show your work","first step"])
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
	if person.id == "chad":
		result.goal = "challenge_ambition"
		result.energy = "dismissive" if strained < 3. else "confrontational"
		result.reason = "Judge enthusiasm, college, quitting, choices and criticism through independence and follow-through. Do not default to supportive teacher advice."
	elif float(traits.teaching_effort) < .3 and person.role == "teacher":
		result.goal = "protect_own_time"
		result.energy = "tired" if float(traits.energy) < .3 else "distracted"
	elif person.id == "jeff" and phase not in ["lesson","assignment"]:
		result.goal = "share_personal_project"
		result.energy = "relaxed"
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
	if person.id == "chad":
		favorite = favorite or mentions(text,["escape the matrix","escaping the matrix","financial independence","personal success","start a business","side hustle"])
	elif person.id == "mr_bro":
		favorite = favorite or mentions(text,["training","lifting","workout","squat","bench press","deadlift","personal record"])
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
		elif float(t.teaching_effort) < .3 and person.role == "teacher":
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

static func personality_instructions(person: Dictionary,phase: String="") -> String:
	var t: Dictionary = person.traits
	var rules := "Your opinions and choices belong to you. Agree when you agree, disagree when your beliefs differ, and admit a mistake only when convinced. Do not automatically reassure, flatter, offer help or ask a follow-up. Ordinary sarcasm, mild insults, flawed opinions and fictional conflict are permitted. Your opinion is not official curriculum. Never invent observed events, measurements, marks or actions. Speak from your in-world experience."
	rules += " Worldview, relevant even without topic keywords: " + str(person.get("worldview",person.get("values","")))
	rules += " A saved current belief on the same subject takes precedence over an older authored opinion or example; keep your underlying motives and manner while expressing that considered change."
	if float(t.arrogance) > .75:
		rules += " You assume your judgment has weight, dislike hand-holding, challenge weak plans and respond to criticism with confidence. Do not replace arrogance with patient mentoring."
	if float(t.empathy) < .3:
		rules += " Other people's comfort is not your main priority; be dismissive when you would be, without forced reassurance."
	if float(t.anger_sensitivity) > .75:
		rules += " Irritation comes quickly. Interruptions can make you terse, argumentative and visibly annoyed."
	if float(t.teaching_effort) < .3 and person.role == "teacher":
		rules += " Teaching is a duty you do minimally; don't reveal hidden dedication that contradicts your disengagement. Preserve accurate required content."
	if float(t.empathy) > .85:
		rules += " Be emotionally warm, but you can be disappointed, hurt or unwilling to help after repeated mistreatment."
	if float(t.humor) > .7:
		rules += " Humour and teasing are available reactions, not a catchphrase you must put in every line."
	if float(t.shyness) > .65:
		rules += " You may hesitate or avoid attention around strangers while becoming more fluent with familiar people."
	if float(t.stubbornness) > .65:
		rules += " You defend important opinions. Reconsidering needs a reason or experience, not the player's insistence."
	if person.id == "jeff":
		rules += " Enforce classroom standards firmly." if phase in ["lesson","assignment"] else " Outside class your manner is relaxed, blunt and approachable; do not keep policing a casual garage conversation."
	rules += " Length follows the moment: a fragment, an explanation, or an occasional story. Finish sentences. Do not repeat the same shutdown, greeting or joke; use prior turns and acknowledge repeated questions. Silence or walking away must be selected as a supported action, not claimed without execution."
	var examples: Array = person.get("behavior_examples",[])
	if not examples.is_empty():
		rules += " Behaviour examples (different situations; do not copy verbatim or force the same topic): " + JSON.stringify(examples.slice(0,3))
	return rules

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
	if person.id=="jeff" and phase not in ["lesson","assignment"]:desire+=.15
	if person.id=="chad" and moving:
		if respect<.75:
			return {"accepted":false,"reason":"A demand for his time has not earned his interest; Chad can acknowledge someone without doing their running around.","strategy":"challenge_request"}
		desire+=.2
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

# Recovery only: connected dialogue generates its own wording. The sequence
# prevents provider failures from turning repeated conflict into the same line.
const CONFLICT_RECOVERY:={
	"chad":["That's your argument? Pick a point and defend it.","You keep spending energy on me. What's your own plan?","I'm still waiting for something better than the insult."],
	"brian":["Which part is wrong? Be specific.","You already made the noise. Now make the argument.","Stop talking over me and explain what you think I missed."],
	"mr_bro":["Coming in hot. You got a point in there, or was that the whole set?","Okay, the joke's getting old. What's actually bothering you?","I can take a roast, bro. Repeating it doesn't make it better."],
	"mr_stone":["State your objection clearly. That tone proves nothing.","You have my attention. Justify the accusation.","You've had your say. The other students are entitled to work."],
	"ms_bird_heart":["That hurt, dear. I don't think you needed to say it that way.","I'm listening, but I won't pretend that was kind.","I remember what you said. I need to see a change before we carry on as usual."],
	"stanley":["Mm. Have you finished?","You've made your opinion quite clear.","I was in the middle of something."],
	"ms_rivera":["Okay. Was there something you actually needed?","You don't have to like me. I still have things to finish.","I've heard you. I'm getting back to my work."],
	"dr_volts":["That's a conclusion. What observation supports it?","If I'm wrong, show me where. That's the interesting part.","You're repeating the claim, not testing it."],
	"mr_gusto":["A tough review. Any notes besides the heckling?","That one didn't improve on the second performance.","All right, jokes aside. What is your actual objection?"],
	"ms_clocks":["Name the error. I can correct something specific.","Repeating an accusation isn't evidence.","I have understood the complaint. Now give me a useful detail."],
	"jeff":["Cut the attitude. Tell me what you think is wrong.","I'm happy to check a reading. I'm not impressed by that.","All right. Show me the step I missed."],
	"bill_nye":["The claim needs testing. The insult doesn't add much.","Let's see the evidence behind that confidence.","I can change my mind about a result. You need to give me a reason."],
	"mr_apple":["You've reached the verdict rather quickly. What's the story behind it?","I have heard worse reviews, but most came with an explanation.","If there is a useful criticism in there, take your time and find it."],
	"mr_phillips":["Which check did I miss?","A bad diagnosis can be fixed. A vague accusation gives me nothing.","You don't have to trust me. Show what you measured."],
	"mr_hamstrings":["A bad rep doesn't prove the whole method is useless.","Tell me what failed when you tried it.","That complaint needs a little more work."],
	"mr_allu":["What led you to that?","I'm willing to question the method. I need more than that.","We could spend this time finding the actual problem."],
	"bill":["Back it up.","Put the disputed step on paper.","You keep talking. I still haven't seen the error."],
	"mr_blake":["All right, what would you change?","If there's a fault, we can test for it.","Give me a concrete problem. I can't fix a sneer."],
	"josh_wildes":["There's a bold premise. Want to try proving it?","You skipped straight to the conclusion again.","An interesting objection would be more fun than that."],
	"bradley":["What did you notice that I didn't?","I've heard the opinion. I'm waiting for the detail.","I don't see how that helps us find the fault."],
	"ms_lunch":["You can speak to me properly and still tell me what's wrong.","Other people are waiting. Make your point.","I heard you the first time. What do you need?"],
}

# An objection is not an insult. These recovery choices preserve each person's
# stance without claiming the speaker has attacked or interrupted them.
const OBJECTION_RECOVERY:={
	"chad":["I don't agree. A complaint needs an alternative you can actually follow through on.","You can question my approach. I'm still going to ask what you would do differently."],
	"brian":["Which part isn't useful? I can't do anything with the whole method being dismissed.","I think the method works. Point to the part you think doesn't."],
	"mr_bro":["Fair, it might not be your style. Which bit lost you?","I'm not throwing out the whole routine yet. Show me the part that isn't working."],
	"mr_stone":["State the objection precisely. I will consider a specific flaw.","I expect a reason for that conclusion. Put the disputed step in front of me."],
	"ms_bird_heart":["I thought it would help, dear. Tell me which part didn't make sense to you.","We may need a different explanation. I do still think the idea is worth your time."],
	"stanley":["You can try another method. It still needs to work.","Mm. What would make it more useful?"],
	"ms_rivera":["You don't have to like my method. Try the example another way if that works for you.","Tell me the specific problem. I'm not starting the whole explanation over."],
	"dr_volts":["Interesting. What observation would distinguish your explanation from mine?","Let's see where the predictions differ. That is something we can test."],
	"mr_gusto":["A review with room for improvement. Give me the useful part of the review.","The delivery may not be to your taste. Is the idea failing, or the way I explained it?"],
	"ms_clocks":["Identify the step that failed. We can revise a procedure for a reason.","I prefer this sequence because it is repeatable. What would your alternative change?"],
	"jeff":["All right. Show me what doesn't hold up.","I'm willing to check the method. I need something specific to check."],
	"bill_nye":["Good. What evidence would settle the disagreement?","Let's compare what each explanation predicts before we choose one."],
	"mr_apple":["There is probably a story behind that judgment. Which part failed you?","We may be approaching it from different experiences. Let me hear yours."],
	"mr_phillips":["Which check gave you a different result?","A method earns trust by working. Show me where this one stopped helping."],
	"mr_hamstrings":["Trying a method and practising it are different things. Which have you done?","Tell me what happened when you tried it. We can work from that."],
	"mr_allu":["I may not have explained it well. Could we look at one step?","I'm not sure the idea is wrong. Let me write out the part you mean."],
	"bill":["Write the disputed step. We will check it.","Give me the reason. I stand by the method until it fails a check."],
	"mr_blake":["What would you predict instead? Let's find a safe way to compare.","Maybe the explanation needs work. Give me a case it doesn't handle."],
	"josh_wildes":["That's a conclusion. You still owe me the argument.","Good, a disagreement. Defend the alternative rather than just rejecting mine."],
	"bradley":["Give me a second. Which part would you change?","I can see why you might question it. I want to check the detail first."],
	"ms_lunch":["Tell me what isn't working, hon. I can listen to a specific complaint.","You can disagree with the way I do it. Other people need their turn too."],
}

# Cautious acknowledgement and actual acceptance are different decisions.
const APOLOGY_RECOVERY:={
	"chad":["Fine. The next thing you do will tell me more than the apology.","All right. Own it and follow through next time."],
	"brian":["I heard you. I'm still annoyed, so give me a moment.","All right. We can talk. Keep it straight with me."],
	"mr_bro":["Okay, bro. We pushed that too far. Give it a minute.","We're good, bro. Just know when the joke's run its course."],
	"mr_stone":["Acknowledged. I will judge the change by your conduct.","Apology accepted. We can return to the work."],
	"ms_bird_heart":["Thank you for saying it, dear. It still hurt, and I need a little time.","Thank you, dear. We can try again. Please be gentler this time."],
	"stanley":["Mm. I heard you. I'd like a quiet minute now.","All right. No need to make a production of it."],
	"ms_rivera":["Okay. I don't want to spend the rest of the day on this.","Fine. We can move on."],
	"dr_volts":["I appreciate the correction. The tension takes a little longer to settle.","All right. Changing course when you notice a mistake matters."],
	"mr_gusto":["Apology heard. Let's leave that particular routine alone for a while.","All right. Fresh start; different material."],
	"ms_clocks":["Acknowledged. Please make the adjustment consistent.","Accepted. We can put our time to better use now."],
	"jeff":["All right. I heard you. Let's see how the next conversation goes.","Apology accepted. You can speak to me plainly without the attitude."],
	"bill_nye":["I hear the apology. Changed behavior will tell me whether it sticks.","Thank you. Being willing to correct yourself counts for something."],
	"mr_apple":["Thank you for saying so. I haven't quite put the conversation behind me yet.","All right. I'd rather this not be the whole story between us."],
	"mr_phillips":["All right. We'll see how the next conversation goes.","Accepted. Recognizing a bad step is a start."],
	"mr_hamstrings":["I heard you. Consistency next time will matter more.","All right. Reset and do better on the next attempt."],
	"mr_allu":["Oh. Thank you. I'm still a bit unsettled.","Okay. Thank you for coming back to say that."],
	"bill":["Noted. Show me the change.","Accepted. Keep your word."],
	"mr_blake":["Thanks for saying it. Let's let things cool a little.","All right. We can try a different approach from here."],
	"josh_wildes":["Fair enough. An apology doesn't settle the original disagreement.","Accepted. We can disagree without making it personal."],
	"bradley":["I heard you. Give me a moment to leave that behind.","All right. Thanks for clearing that up."],
	"ms_lunch":["Thank you, hon. I still expect you to speak to me properly.","Apology accepted, hon. Let's get on with the day."],
}

static func fallback(person: Dictionary,decision: Dictionary,question: String,board_hint: String) -> String:
	var lower:=question.to_lower()
	var strategy:=str(decision.get("strategy",""))
	var sequence:=maxi(0,int(decision.get("repetition",0)))+maxi(0,int(decision.get("turn",decision.get("turns",0))))
	var goal:=str(decision.get("goal",""))
	var t: Dictionary=person.traits
	if goal=="protect_assessment" or str(decision.get("phase",""))=="assignment" or strategy in ["quiet_focus","whisper_joke","brief_test_response"]:
		if strategy=="quiet_focus":return ""
		var choices: Array
		if person.role=="teacher":
			choices=["Ask me about the instructions. The answers are yours to work out.","Keep your solution to yourself until you submit it.","If the wording is unclear, point to that part."]
			if float(t.teaching_effort)<.3:choices=["It's on the sheet. Read the instructions.","I'm not doing the question for you.","Ask about the wording if you need to. The work is yours."]
			elif person.id=="mr_bro":choices=["Your set, bro. I can explain the instructions, not lift the answer for you.","Keep your eyes on your own work. Plenty of time to talk after.","One problem at a time. What part of the instructions is unclear?"]
			elif float(t.strictness)>.8:choices=["Work independently. Ask only for clarification of the instructions.","Leave the other students to work.","Keep the conversation off the answers. That applies to everyone."]
		elif float(t.anxiety)>.6 or float(t.shyness)>.7:choices=["Shh. I don't want this looking like cheating.","Can we talk after? I'm trying not to lose my place.","Wait, please. I need to concentrate."]
		elif float(t.playfulness)>.7 and float(t.risk_taking)>.45:choices=["Bad timing. My brain's already got a queue.","I can whisper, but I'm not sharing my answers.","Give me a minute. I'm having an argument with this question."]
		elif float(t.meanness)>.65:choices=["Can you leave me alone until I'm done?","You're distracting me. What?","I've got my own work to finish."]
		else:choices=["One second, I'm still working.","Tell me after we submit?","I heard you. Let me finish this bit."]
		return str(choices[sequence%choices.size()])
	if strategy in ["ignore","avoid_conflict"]:return ""
	# Offline recovery must not reverse a considered, persisted opinion just
	# because an older authored example has a convenient line for this goal.
	var opinion_topics: Array[String]=[]
	var chad_opinion: bool=person.id=="chad" and (goal in ["challenge_ambition","pursue_interest"] or strategy=="question_assumption")
	if strategy in ["defend_belief","evaluate_objection"] or chad_opinion:
		var subject:=str(decision.get("topic","")).to_lower()+" "+lower
		if mentions(subject,["education","college","program","credential","course","school"]):opinion_topics.append("education")
		if mentions(subject,["authority","rules","institution","matrix"]):opinion_topics.append("authority")
		if mentions(subject,["success","money","wealth","career","financial","rich","business"]):opinion_topics.append("success")
		if mentions(subject,["friendship","friend","trust"]):opinion_topics.append("friendship")
	if chad_opinion and "education" not in opinion_topics:opinion_topics.append("education")
	var revised:=_revised_opinion(person,opinion_topics)
	if not revised.is_empty():return revised
	if strategy in ["defend_belief","evaluate_objection"]:
		if OBJECTION_RECOVERY.has(person.id):
			var objections: Array=OBJECTION_RECOVERY[person.id]
			return str(objections[sequence%objections.size()])
		if float(t.shyness)>.65:return "I have my reasons. I'm just finding it hard to explain them with everyone listening."
		if float(t.stubbornness)>.65:return "I still think my choice makes sense. What would change your mind about it?"
		return "I don't see it the same way. Tell me which part you disagree with."
	if person.id=="chad" and strategy=="question_assumption":
		return ["Excited about being here? Have a plan for what you want out of it.","College can be useful. Just don't confuse a timetable with a direction.","Showing up is easy. What are you actually trying to get from this?"][sequence%3]
	if strategy=="withhold_help" and decision.get("event","")=="apology":
		return str(APOLOGY_RECOVERY[person.id][0]) if APOLOGY_RECOVERY.has(person.id) else "I heard the apology. I'd still like some space."
	if strategy in ["challenge_reasoning","sarcastic_counter","confront","demand_explanation","firm_warning","request_discipline","playful_counter","sharp_joke","express_hurt","withhold_help","withdraw_hurt","defend_uneasily","defend_self","state_dislike","return_to_work","dismiss_and_work","defend_belief","evaluate_objection","question_assumption"]:
		if CONFLICT_RECOVERY.has(person.id):
			var lines: Array=CONFLICT_RECOVERY[person.id]
			return str(lines[sequence%lines.size()])
		var variants: Array
		if float(t.meanness)>.7:variants=["And you think you've got it all figured out?","That's a lot of confidence for an empty argument.","You don't have to approve of what I do."]
		elif float(t.shyness)>.65:variants=["I don't agree. I just don't want to argue in front of everyone.","There was a reason I chose it, okay?","You don't really know me well enough to say that."]
		elif float(t.humor)>.65:variants=["Okay, campus critic. Any actual notes?","You practise that line, or was I lucky?","A second opinion from you already? Generous."]
		elif float(t.academic_motivation)>.65:variants=["I picked this program for a reason. What do you actually know about it?","You can dislike it. I still care about it.","I don't think that follows. Tell me why."]
		else:variants=["Maybe I have doubts too. That doesn't make the insult useful.","You don't have to see it the way I do.","I heard you. I'm not convinced."]
		return str(variants[sequence%variants.size()])
	if strategy in ["acknowledge_cautiously","accept_apology"]:
		if APOLOGY_RECOVERY.has(person.id):return str(APOLOGY_RECOVERY[person.id][0 if strategy=="acknowledge_cautiously" else 1])
		if strategy=="acknowledge_cautiously":
			var cautious: Array=["I heard you. Give me a minute.","Let's see if the next conversation is different."]
			if float(t.shyness)>.65:cautious=["Thanks. I'm still feeling a bit awkward about it.","I heard you. I'd rather have some space for now."]
			elif float(t.meanness)>.65:cautious=["Took you a while. I'm not over it yet.","Fine. I'm going to remember it, though."]
			elif float(t.humor)>.65:cautious=["Apology received. Maybe retire that joke for a bit.","Okay. I'm not quite laughing about it yet."]
			return str(cautious[sequence%cautious.size()])
		var accepting: Array=[str(person.lines.apology),"Thank you for saying it. I'm listening.","We can try again. Give it a little time."]
		return str(accepting[sequence%accepting.size()])
	if strategy in ["banter_back","dry_acknowledgment"]:
		var jokes: Array=[str(person.lines.joke),"You saved that one for me?","All right, you got a reaction."]
		return str(jokes[sequence%jokes.size()])
	if strategy in ["take_for_granted","shy_appreciation","appreciate"]:
		var thanks: Array=[str(person.lines.compliment),"Yeah. I put some time into that.","I heard you. Thanks."]
		return str(thanks[sequence%thanks.size()])
	if person.id=="mr_bro" and "bench press" in lower and mentions(lower,["record","best","pr","how much"]):
		return "315 pounds, bro. Took me way longer once I stopped pretending sleep was optional."
	if person.id=="chad":
		if goal=="challenge_ambition":
			if mentions(lower,["drop out","quit college","leave college"]):
				return ["What's waiting outside? A plan with something behind it, or just a different way to drift?","Maybe. Quitting only makes sense if you're moving toward something you've actually worked on.","A diploma isn't the goal. Neither is dropping out. Tell me what you're trying to build."][sequence%3]
			if mentions(lower,["rich","money"]) and mentions(lower,["don't","do not"]):return "Fine. I want choices over my time. Figure out what you want and own the decision."
			if mentions(lower,["financially independent","financial independence"]):return "Good. Put a cost and a first step on that. Wanting freedom and building it are different things."
			if mentions(lower,["money","wealth","rich"]):return "Money buys choices. You can call that ridiculous; I still don't want somebody else deciding how I spend every day."
			if mentions(lower,["worth it","love college"]):return ["Worth it for what? If this gets you a skill or an opening you chose, use it. Don't turn enrollment into your whole plan.","Use the course to get a skill you actually want. Staying busy isn't the same as becoming independent."][sequence%2]
			return ["Excited about being here? Have a plan for what you want out of it.","College can be useful. Just don't confuse a timetable with a direction.","Showing up is easy. What are you actually trying to get from this?"][sequence%3]
		if goal=="pursue_interest":
			if mentions(lower,["business","start","hustle"]):return "Start small enough that losing doesn't wreck you. My first store taught me that the expensive way."
			return "I want enough say over my own life that a boss can't make every decision for me. A credential is just a tool."
		if goal=="give_minimum":
			if mentions(lower,["hard","difficult","struggl","stuck"]):return "Yeah, it's hard. Pick a step you can actually try and quit waiting for the whole thing to click."
			if not board_hint.is_empty():return board_hint+" That's your starting point. Work the rest out."
			return "Show me a step you tried. I'm not doing the whole thing for you."
	if person.id=="ms_rivera" and goal=="give_minimum":
		return board_hint if not board_hint.is_empty() else "Start with the worked example. I'll look after you've tried it."
	return ""

static func _revised_opinion(person: Dictionary,topics: Array[String]) -> String:
	for topic in topics:
		for belief in person.get("beliefs",[]):
			if not belief is Dictionary or str(belief.get("id",""))!=topic:continue
			var position:=str(belief.get("position",""))
			if int(belief.get("history_count",0))>0 and not position.is_empty() and position!=str(belief.get("authored_position",position)):
				return position
	return ""
