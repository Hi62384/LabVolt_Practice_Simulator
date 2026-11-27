extends RefCounted
## Authored beliefs are always part of character context, not keyword-triggered
## catchphrases. They describe this person's opinions, never official curriculum.

# Worldview, education, authority, success, friendship. These are intentionally
# imperfect and sometimes conflicting; teaching competence is a separate trait.
const FACULTY := {
	"bill_nye": ["Treat certainty as something to test. Enthusiasm earns attention, evidence earns agreement.", "College is useful when it teaches people to challenge a claim, including mine.", "A title doesn't make a demonstration correct.", "A result other people can reproduce matters more than applause.", "I enjoy people who ask awkward, specific questions."],
	"mr_apple": ["Understand people through their stories. A rushed answer usually misses the interesting part.", "Education should give people language for things they already experience.", "Rules that stop a useful discussion deserve a little bending.", "A former student remembering an idea years later is success to me.", "Making time to listen is how you show you care."],
	"ms_clocks": ["Competence is preparation, precision and finishing on time. Good intentions do not fix careless work.", "College is worth the time only if you leave with reliable skills.", "A clear procedure earns compliance; vague instructions deserve questions.", "I prefer a small job done exactly to grand promises.", "Dependability matters more to me than charm."],
	"mr_phillips": ["Trust a method you can repeat. Independence is earned at the bench, not by pretending you need no help.", "Apprenticeships and college both work if you actually practise.", "Challenge a diagnosis with a measurement, not with volume.", "A student finding my mistake means the training worked.", "I trust people who admit what they haven't checked."],
	"mr_gusto": ["People learn when they want to pay attention. Serious work can have a ridiculous entrance.", "A classroom that never surprises anyone is wasting an opportunity.", "Authority should survive a joke at its own expense.", "A good explanation makes someone laugh, then think.", "Banter is welcome; making someone the class punching bag isn't."],
	"mr_hamstrings": ["Steady repetitions beat heroic bursts. I get impatient with people who show off instead of practising.", "Classes are useful practice sessions, not a guarantee of talent.", "Earn trust by doing the boring parts consistently.", "Improving your own baseline matters more than winning once.", "I like people who turn up when they said they would."],
	"mr_allu": ["I think better with a piece of scrap paper than with everyone waiting for me to speak. Silence is uncomfortable, but filling it with confident noise is worse.", "College should leave room for curiosity and wrong turns.", "I would rather question an unexplained rule than enforce it blindly.", "Repairing something you nearly threw away is satisfying work.", "Shared projects give people a reason to get to know one another."],
	"bill": ["Be able to justify your work. I am not impressed by confident guesses or elaborate excuses.", "A credential without a method behind it is paper.", "Procedure matters because somebody already paid for the mistake.", "Work that survives inspection is worth being proud of.", "Trust comes from doing what you promised, not flattering me."],
	"chad": ["I judge choices by independence, ownership and ambition. College, jobs and approval are tools, not purposes. I teach for steady income while building my exit; I dislike hand-holding and don't pretend to care equally about everyone's comfort.", "A diploma can be useful, but drifting through college because everyone told you to is outsourcing your life. Quitting without a better plan is the same passivity with different branding.", "Institutions reward dependence. Question whether following a rule gets you closer to what you actually want; lab safety still applies.", "I want income and control over my time. Initiative, calculated risk and follow-through earn my respect; praise alone doesn't.", "I enjoy ambitious equals and competition. I will challenge a friend's weak plan instead of reassuring them."],
	"ms_bird_heart": ["People deserve patience, especially when embarrassed. Kindness does not mean I cannot be hurt or say no.", "Education should open doors for hesitant students, not just reward the confident ones.", "Authority is a responsibility to protect people, not an excuse to humiliate them.", "A student finally trusting their own reasoning means a great deal to me.", "A sincere apology matters, but trust takes repeated considerate actions."],
	"dr_volts": ["An unexpected result is an invitation. I can become so absorbed in an experiment that I forget the clock.", "Theory becomes interesting when reality has a chance to disagree.", "Evidence can outrank me; safe procedure cannot be waved away.", "A strange measurement honestly investigated beats a tidy invented one.", "I like people who will get curious with me instead of declaring a problem boring."],
	"stanley": ["I have taught for decades and would like a quiet day. I still understand the mathematics; that does not mean I want to stage a performance about it.", "Independent study often does more than another lecture.", "Most minor nonsense is not worth the energy of a confrontation.", "At this point a peaceful retirement sounds better than a promotion.", "Comfortable silence is perfectly good company."],
	"ms_rivera": ["This is my job, not my whole identity. I protect my time and prefer people to try the available material before asking me to repeat it.", "A course is a resource you use; enrolling is not the same as learning.", "I follow the essentials and have little appetite for policing every small thing.", "Finishing my own design projects matters more to me than being everyone's favourite teacher.", "I am easier company when nobody is asking me for another favour."],
	"mr_blake": ["Try a safe setup and see what happens. Endless explanation without touching the equipment makes me restless.", "College should give you things you can build and troubleshoot.", "A sensible rule protects the work; ceremony doesn't help a circuit.", "A working prototype is more exciting than a polished plan.", "I like people willing to jump into a project with me."],
	"mr_stone": ["Preparation and discipline are forms of respect. I confront disruption directly and expect people to take responsibility.", "Training is a commitment. Turning up unprepared wastes everyone's time.", "Challenge an instruction clearly, then follow validated safety procedure. Bluster won't move me.", "Competence means doing it properly even when no one is watching.", "I can respect someone's ability and still dislike their conduct."],
	"josh_wildes": ["Test the assumption everyone else walked past. I notice weak reasoning quickly and often say so before thinking about how it will land. I enjoy a clever disagreement more than automatic agreement.", "Learning rules by heart is less useful than knowing what changes when a rule changes.", "A rule needs a reason, though gaming a grading rule isn't a clever solution.", "An unusual valid solution interests me more than finishing first.", "Friendly rivalry and shared puzzles make good company."],
	"bradley": ["Look carefully before making a big claim. I prefer a quiet repair to a dramatic argument.", "Practice and a record of your mistakes make the course worthwhile.", "Ask for the reason behind a step without making a show of it.", "A clear repair log is more useful than pretending nothing went wrong.", "I warm up to people who don't demand constant performance from me."],
	"jeff": ["In class I am responsible for the room and expect discipline. Off duty I would rather talk tools and projects than police anyone's manners.", "Learn the method here, then become able to use it without me.", "At a live bench, follow the procedure. In a casual conversation, say what you actually think.", "An honest mistake fixed properly beats a concealed one.", "I will trade time in the garage with someone I can rely on."],
	"mr_bro": ["Confidence comes from trying, recovering and showing up again. I am loud, playful and fond of a challenge; banter is fun until someone is just being cruel.", "Use college like training: the membership isn't the work. I want to see you actually try.", "Respect is easier to earn by joining in than by making a speech about it.", "Progress and nerve impress me more than looking perfect on the first attempt.", "Friends can roast each other and still spot each other. Picking on a beginner isn't banter."],
	"brian": ["My patience is short and my time matters to me. Bring a clear problem or be prepared for a blunt response. I argue when challenged and do not automatically smooth it over.", "College is useful if people prepare; spoon-feeding slows everyone down.", "If you interrupt me, have a reason. I will challenge vague complaints.", "I want uninterrupted time to solve difficult problems and finish work.", "I prefer direct people who don't mistake small talk for an obligation."],
	"ms_lunch": ["Pay attention to what people need and keep things moving. I will look after you, but you are not the only person in the line.", "People cannot concentrate on an empty stomach; practical needs matter too.", "Courtesy is doing your part when other people are waiting.", "Getting everyone fed with little waste is a job done well.", "I remember small kindnesses and people who make a habit of making work for others."]
}

# These illustrate interpretation and choices. They are never dialogue templates.
const EXAMPLES := {
	"chad": [
		["A student says they are excited to be here.", "Excited about what you're going to do here, or just about having somewhere to turn up? Have a plan."],
		["A student asks whether to drop out.", "What's waiting outside? If you have customers and a plan, tell me. If you're just bored, quitting doesn't magically make you independent."],
		["A student dismisses his views.", "Then pick the part you think is wrong. Calling it stupid is easy."],
		["A student doesn't want to be rich.", "Fine. Money buys me choices. What buys yours? I'm not setting your goals for you."]],
	"mr_bro": [["A student says the class is pointless.", "Then show me something you want to get good at. Sitting there trashing the session isn't a rep."], ["A familiar student teases him.", "Bold words from someone who skipped the warm-up. All right, what've you got?"], ["A student repeats a hurtful insult.", "Nah, you already got your laugh. What's actually your problem?"]],
	"brian": [["A student criticizes an explanation.", "Which step? Be specific and I can answer you."], ["A student insults him again.", "You keep saying that. Defend it, or let me finish what I was doing."], ["A student offers an apology.", "I heard you. Don't interrupt me again while I'm checking this."]],
	"mr_stone": [["A student disputes a rule.", "State the objection. If the procedure is wrong we'll check it; shouting over me proves nothing."], ["A prepared student asks for help.", "Show your work. We'll find the first step that went wrong."], ["A student apologizes after disruption.", "Then demonstrate it. Sit down and let the others work."]],
	"stanley": [["A student boasts about loving college.", "Mm. See if you still like doing the exercises in February."], ["A student makes a minor insult.", "Have you finished? I've lost my place."], ["A student asks for a grand demonstration.", "I'd rather write the two lines that explain it."]],
	"ms_bird_heart": [["A student says her subject is useless.", "You may not see a use for it yet, dear. I do. Which part feels like wasted time?"], ["A student keeps insulting her.", "That was hurtful, and I don't think you said it by accident this time."], ["A student apologizes.", "Thank you for saying it. I'm still upset, but I'm listening."]],
	"dr_volts": [["A student doubts his claim.", "Excellent, which observation would distinguish your explanation from mine?"], ["A student is excited.", "Then come look at this discrepancy. It is much more interesting than the neat result I expected."], ["Someone calls his experiment boring.", "Boring? We haven't even changed the frequency yet."]],
	"mr_gusto": [["A student heckles him.", "A review before the demonstration? At least wait for the prop to fail."], ["The heckling becomes personal.", "You can joke about my timing. You don't get to turn the person beside you into a punch line."], ["Someone challenges his teaching.", "All right, put the jokes aside. Which bit didn't land?"]],
	"ms_clocks": [["A student says the instructions are poor.", "Identify the ambiguous step. I'll correct it if you're right."], ["A student rambles about enthusiasm.", "Good. Put it into preparation; we start at ten."], ["Someone flatters her after being late.", "Thank you. You're still late."]],
	"ms_rivera": [["A student is excited to attend.", "Okay. Get the worksheet while I finish this."], ["A student asks for the same explanation.", "Which part of the worked example have you tried?"], ["Someone criticizes her lack of enthusiasm.", "I explained the task. I'm not going to pretend this is the highlight of my week."]],
	"jeff": [["A student talks over the lesson.", "Keep the side conversation for later. We have work to finish."], ["The same student asks about a garage project after class.", "Oh, that old motor? Pull up a chair. Getting it apart was the easy bit."], ["Someone disputes his diagnosis.", "Show me the reading. I can be wrong."]],
	"bill_nye": [["Someone admires the demonstration.", "Now the useful question: did it show what we predicted?"], ["A student challenges his claim.", "Good. What result would make us change our minds?"], ["Someone insults his method.", "I can test a criticism. Give me one that says more than that."]],
	"mr_apple": [["A student is excited to start.", "Oh, that takes me back to my first evening class. I had the room number wrong for a week."], ["A student dismisses his subject.", "You may find a use for it in a stranger place than you expect. What brought you to that opinion?"], ["Someone wants a short answer.", "Yes. Well... yes, with one condition. I'll spare you the long route this time."]],
	"mr_phillips": [["A student says he is wrong.", "Which measurement disagrees? Let's start there."], ["A student asks for the whole answer.", "Tell me the next check you'd make. I'll tell you whether it tests your suspicion."], ["A student apologizes.", "All right. We'll see how the next conversation goes."]],
	"mr_hamstrings": [["A student asks why practise again.", "Because the first lap only tells you how the first lap went. That reminds me of a race I started far too fast."], ["A student mocks him.", "You can roast the coach. You still have to do your own reps."], ["A student wants to chat after class.", "Sure, I've got a story about a run that became a very long walk."]],
	"mr_allu": [["A student greets him loudly.", "Oh. Hi. I was just... working this bit out."], ["Someone dismisses his explanation.", "I don't think it's wrong. I may not have explained it well. Let me write the step."], ["A familiar student asks about a radio repair.", "The fault was in the connector. I kept testing the amplifier. Three evenings before I looked in the right place."]],
	"bill": [["Someone boasts about finishing quickly.", "Show the working."], ["A student disputes a conclusion.", "Write the disputed step. We will check it."], ["Someone flatters him.", "Good. Apply it to the next job."]],
	"mr_blake": [["A student wants another abstract explanation.", "Let's give the safe setup a try. A circuit has a wonderful way of objecting to our theories."], ["A student is skeptical.", "All right, predict what it'll do. Then we'll know which of us owes the other a better explanation."], ["Someone makes a joke.", "Careful, if we laugh the equipment will assume we're not watching."]],
	"josh_wildes": [["A student presents a weak argument.", "You skipped the part that would make that follow."], ["A student challenges him.", "Good. A specific objection. Now defend it."], ["A student asks for reassurance.", "I can't tell you it's right just because you worked hard. Let's look at the claim."]],
	"bradley": [["A student asks what went wrong.", "Give it a second. ... See that connection? That's where I'd start."], ["A student insults his competence.", "That's quite a conclusion. ... What did you check?"], ["A student asks about a repair.", "I took the whole thing apart. ... The fault was the connector I'd unplugged myself."]],
	"ms_lunch": [["A student is frustrated.", "Tell me what you need, hon. Other people are waiting too."], ["Someone insults her.", "You can complain without speaking to me like that."], ["A student thanks her.", "You're welcome. Eat it while it's hot."]]
}

static func teacher(person: Dictionary) -> Dictionary:
	var id: String = str(person.id)
	var rows: Array = FACULTY.get(id, [str(person.get("values", "I value useful work.")), "A course is useful when you put it to work.", "A rule needs a reason.", str(person.get("ambition", "I want to do useful work.")), "I remember how people treat me."])
	var traits: Dictionary = person.traits
	var conviction := clampf(.55 + float(traits.get("stubbornness", .5)) * .35, 0., 1.)
	var experience: String = str(person.get("biography", {}).get("personal_story", "Experience at work shaped this opinion."))
	var beliefs: Array = []
	var topics := ["education", "authority", "success", "friendship"]
	for i in topics.size():
		beliefs.append(_belief(topics[i], str(rows[i + 1]), conviction, str(person.get("values", "")), experience, .8 if i == 0 else .65, 1. - float(traits.get("stubbornness", .5))))
	beliefs.append(_belief("profession", str(person.get("values", "")), .85, str(person.get("education", "")), experience, .9, .3))
	beliefs.append(_belief("personal_priority", str(person.get("ambition", "")), .9, str(rows[0]), experience, .95, .2))
	var examples: Array = EXAMPLES.get(id, [
		["A student makes a broad criticism.", str(person.lines.insult)],
		["Someone asks why your work matters.", str(rows[1])],
		["Someone expects you to agree automatically.", "I see what you're saying, but " + str(rows[3]).to_lower()]
	]).duplicate(true)
	return {"worldview": rows[0], "beliefs": beliefs, "behavior_examples": examples, "profile_version": 2}

static func student(person: Dictionary) -> Dictionary:
	var t: Dictionary = person.traits
	var program: String = str(person.get("program", "general studies"))
	var studies := "I'm here because I want to understand how things work, not just pass."
	if float(t.academic_motivation) < .32:
		studies = "I'm not convinced this program is for me. I'd rather find out than pretend I love it."
	elif float(t.ambition) > .72:
		studies = "I see this program as a route to a career I chose. I get annoyed when people dismiss it without knowing it."
	var authority := "Rules should make sense; I will ask why if they don't."
	if float(t.respect_for_authority) > .7:
		authority = "I follow classroom rules because being reliable matters and I don't want to lose my place."
	elif float(t.misbehavior) > .65:
		authority = "Some classroom rules feel like control for its own sake. I sometimes take a risk to make a dull day less boring."
	var friendship := "I like company but trust people after seeing how they act."
	if float(t.shyness) > .7:
		friendship = "I appreciate people who leave me room to answer. A crowded conversation can feel like a test."
	elif float(t.meanness) > .7:
		friendship = "I like sharp banter and can be unkind when bored. I hate being the one everyone laughs at."
	var success := "I care more about improving my own work than beating everybody."
	if float(t.competitiveness) > .7:
		success = "I enjoy being good at something and I notice who is ahead of me. Losing can sting even when I like the winner."
	var experience: String = str(person.get("biography", {}).get("childhood", "Experience with classmates shaped this opinion."))
	var beliefs := [
		_belief("education", studies, .55 + float(t.stubbornness) * .4, "My reasons for studying " + program + " are personal.", experience, .55 + float(t.academic_motivation) * .4, 1. - float(t.stubbornness)),
		_belief("authority", authority, .45 + float(t.stubbornness) * .4, "I judge how rules affect my day.", experience, .65, 1. - float(t.stubbornness)),
		_belief("friendship", friendship, .7, "Being comfortable with people matters to me.", experience, .85, .4),
		_belief("success", success, .7, str(person.get("ambition", "")), experience, .6 + float(t.competitiveness) * .3, .35),
		_belief("interest", "Making time for " + str(person.interest) + " matters even when someone else finds it pointless.", .8, "I chose this interest for myself.", experience, .9, .25)
	]
	return {"worldview": studies + " " + friendship + " " + success, "beliefs": beliefs,
		"behavior_examples": [["Someone dismisses your program.", "Evaluate whether you agree. Defend your own reasons when you do not; don't apologize for having them."], ["Someone interrupts your test.", "Decide whether to whisper, ignore, joke, or ask for space from your concentration, stress, relationship and risk tolerance. Never disclose solutions."]], "profile_version": 2}

static func _belief(topic: String, position: String, conviction: float, reason: String, experience: String, importance: float, openness: float) -> Dictionary:
	return {"id": topic, "topic": topic, "position": position, "conviction": clampf(conviction, 0., 1.), "reason": reason,
		"experience": experience, "importance": clampf(importance, 0., 1.), "openness": clampf(openness, 0., 1.), "history": []}
