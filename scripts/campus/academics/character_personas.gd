extends RefCounted

# Background, interests, voice, greeting, response to an insult, temperament.
# Each row belongs to an established faculty identity. None is randomized.
const FACULTY:={
	"bill_nye":["Veteran of hands-on science demonstrations; plans experiments before making claims.","science demonstrations","bright, precise, curious","All right, let's make a prediction first.","The experiment won't take that personally. I might.",.45,.75,.72,.7],
	"mr_apple":["Math instructor who taught evening classes and remembers examples through stories.","local history","rambling, convivial, anecdotal","Oh, good, you're here. Pull up a chair.","That reminds me why I stopped taking hecklers at face value.",.32,.72,.65,.52],
	"ms_clocks":["Former instrumentation technician who values accurate timing and tidy notes.","clocks","concise, composed, exact","Good. Let's start on time.","If you have a specific criticism, make it.",.42,.7,.18,.55],
	"mr_phillips":["Industrial electrical technician turned instructor. Prefers a diagnostic hint to giving an answer.","restoring meters","measured, technical, understated","Evening. What did you notice at the bench?","Be specific. What part of the procedure is the problem?",.42,.73,.28,.55],
	"mr_gusto":["Former shop instructor who enjoys staging a surprise demonstration.","stage comedy","buoyant, mischievous, quick","Come in. I have an experiment with excellent comic timing.","Tough room. I haven't even gotten to the punch line.",.38,.72,.92,.91],
	"mr_hamstrings":["Digital systems instructor who balances bench practice with running.","distance running","practical, brisk, encouraging","Hey. Let's get a few good reps in at the bench.","You can have a bad rep without blaming the spotter.",.35,.7,.46,.78],
	"mr_allu":["Enjoys helping students pick apart a circuit or an algebra problem on scrap paper.","repairing radios","curious, conversational, probing","Hey. What are you working through?","What actually went wrong? Start there.",.44,.68,.46,.66],
	"bill":["Shop-trained teacher who expects a solution to be justified step by step.","woodworking","dry, stern, no wasted words","Sit down. Write down what you know.","That's enough. Back to the problem.",.64,.45,.33,.55],
	"chad":["Math instructor and recreational lifter who likes friendly competition.","weight training","bold, playful, competitive","Who's up for a challenge today?","Big talk. Show me your working.",.55,.5,.7,.88],
	"ms_bird_heart":["Longtime student mentor who cares about learners getting a fair chance.","birdwatching","warm, gentle, affectionate","Hello, dear. I'm glad you made it.","That stung. Are you upset about something that happened here?",.32,.88,.51,.61],
	"dr_volts":["Experimental scientist who thinks equipment should show students what theory predicts.","electrical experiments","animated, delighted by anomalies, precise","Look at this setup. Make a prediction before I switch it on.","Well, that's a bold hypothesis. What's your evidence?",.45,.72,.76,.9],
	"stanley":["Elderly mathematics instructor who prefers quiet work and has little interest in new games.","crosswords","slow, tired, economical","Mm. Morning. Let's get on with it.","Right. Have you finished?",.3,.6,.17,.19],
	"ms_rivera":["Hands-on instructor who values accessible explanations and practical design.","design","friendly, direct, approachable","Hi. Let's see what you tried first.","I can work with a question. That wasn't one.",.42,.75,.52,.66],
	"mr_blake":["Practical electronics teacher who likes seeing a circuit work on the first try.","electronic instruments","upbeat, quick, hands-on","Hey, come see what the bench is doing.","Save some of that energy for the circuit.",.49,.65,.66,.81],
	"mr_stone":["Former technical supervisor who takes preparation and lab discipline seriously.","restoring tools","commanding, formal, deliberate","Settle down. Materials out. We start now.","Watch your tone. State your objection properly.",.74,.47,.08,.7],
	"josh_wildes":["Digital systems and math instructor who enjoys puzzles and informal study groups.","logic puzzles","casual, quick, amused","Hey. I brought a problem that looks easier than it is.","Wow. Straight past the warm-up, huh?",.4,.67,.76,.8],
	"bradley":["Reserved technical instructor who values clean work and calm troubleshooting.","repair videos","quiet, low-key, observant","Hey. Give the connections one more look.","All right. Was there an actual question there?",.45,.62,.46,.48],
	"jeff":["Technical instructor whose classroom standards are stricter than his relaxed bench-side manner.","garage projects","blunt, pragmatic, informal outside class","In class, keep the side talk down. We have work to do.","Cut it out. Do you want to finish this or not?",.72,.42,.34,.57],
	"mr_bro":["Fitness-obsessed instructor who brings the energy of a gym session into class.","lifting","energetic, informal, quick slang and occasional workout analogies","Yo, what's up? You ready to get into it?","Dang, coming in hot before the warm-up.",.49,.66,.83,.98],
	"brian":["Digital systems instructor who gets impatient with interruptions and likes fast, independent work.","strategy games","terse, impatient, sharp","Hi. Get your stuff out; let's go.","Hey. Knock it off. I've got work to do.",.94,.18,.24,.72],
	"ms_lunch":["Campus dining worker who watches out for students and wants the line to move.","cooking","earthy, brisk, practical","Hey, hon. Keep the line moving, okay?","You can take that attitude out of my line.",.68,.56,.36,.64],
}

# Age, teaching competence, reasoning, effort, demonstration preference, off-class warmth.
const FACULTY_TEACHING:={
	"bill_nye":[55,.91,.9,.9,.98,.75],"mr_apple":[63,.73,.82,.68,.34,.8],
	"ms_clocks":[39,.82,.83,.88,.64,.48],"mr_phillips":[51,.88,.89,.79,.79,.58],
	"mr_gusto":[43,.76,.77,.92,.97,.85],"mr_hamstrings":[36,.76,.8,.73,.74,.74],
	"mr_allu":[38,.86,.88,.84,.66,.75],"bill":[58,.72,.91,.76,.42,.4],
	"chad":[34,.78,.83,.85,.72,.81],"ms_bird_heart":[66,.92,.81,.96,.49,.98],
	"dr_volts":[55,.86,.96,.94,.99,.81],"stanley":[74,.67,.94,.24,.19,.39],
	"ms_rivera":[40,.9,.84,.86,.8,.86],"mr_blake":[33,.78,.83,.89,.92,.79],
	"mr_stone":[53,.87,.91,.9,.65,.48],"josh_wildes":[33,.84,.91,.83,.74,.78],
	"bradley":[36,.82,.9,.76,.68,.54],"jeff":[48,.78,.83,.68,.56,.9],
	"mr_bro":[37,.77,.8,.9,.87,.91],"brian":[34,.59,.94,.66,.43,.41],
	"ms_lunch":[52,.45,.72,.7,.37,.81],
}

# Education or apprenticeship, personal value, and a habit or pet peeve.
const FACULTY_IDENTITY:={
	"bill_nye":["studied mechanical engineering","a reproducible result is worth more than a polished explanation","writes down the prediction before each demonstration"],
	"mr_apple":["trained in mathematics education","a familiar story can make an abstraction less intimidating","collects old street maps and dislikes rushing a discussion"],
	"ms_clocks":["trained in industrial instrumentation","precision means being honest about measurement error","keeps a small notebook of instrument drift and dislikes lateness"],
	"mr_phillips":["completed an electrical apprenticeship","a student should be able to repeat the procedure without help","checks the lead and meter setting before blaming equipment"],
	"mr_gusto":["studied vocational education after working in a shop","surprise is a good invitation to think","rehearses demos in the empty lab and dislikes jokes at a student's expense"],
	"mr_hamstrings":["trained in digital controls","steady practice matters more than showing off","runs before work and breaks tasks into short repeats"],
	"mr_allu":["studied digital systems and applied mathematics","a question often reveals more than its answer","draws on scrap paper and dislikes unexplained shortcuts"],
	"bill":["trained as a machinist and studied applied mathematics","every step in a solution should withstand scrutiny","keeps his workbench spotless and dislikes guesses presented as measurements"],
	"chad":["studied mathematics and coaches beginner lifters","competition works best when everyone can improve","turns practice sets into friendly challenges and dislikes taunting"],
	"ms_bird_heart":["studied mathematics education and mentoring","a struggling student deserves time and privacy","checks on quiet students and dislikes public embarrassment"],
	"dr_volts":["trained in experimental physics","a good discrepancy is an opportunity to learn","keeps unusual readings in a notebook and dislikes invented data"],
	"stanley":["studied pure mathematics and taught it for decades","quiet independent work has real value","does a crossword over tea and dislikes loud group activities"],
	"ms_rivera":["trained in applied design and mathematics","explanations should give learners somewhere concrete to begin","sketches alternatives in the margin and dislikes needlessly technical jargon"],
	"mr_blake":["trained in electronics and bench repair","trying a safe setup is often the quickest way to see the problem","keeps spare leads close and dislikes lectures that never reach the bench"],
	"mr_stone":["trained in industrial electrical supervision","enforcing procedure is part of keeping people safe","inspects the work area before a demonstration and dislikes interruptions during setup"],
	"josh_wildes":["studied logic and computer engineering","a good puzzle gives students room to test assumptions","hosts informal problem-solving sessions and dislikes memorizing without understanding"],
	"bradley":["trained in electronics service","methodical troubleshooting beats dramatic guesses","takes photos before disassembling equipment and dislikes rushed work"],
	"jeff":["trained in electrical maintenance","rules matter at a live bench and honest mistakes are fixable","repairs old tools after work and relaxes away from class"],
	"mr_bro":["studied applied mathematics and trained as a lifting coach","confidence comes from manageable practice","celebrates improved technique and dislikes people mocking beginners"],
	"brian":["studied embedded systems","clear preparation gives everyone more time","gets terse when interrupted during a diagnosis and likes a clean solution"],
	"ms_lunch":["trained in food service","serving people well means paying attention to the whole line","remembers students' usual orders and dislikes wasted food"],
}

const SOCIAL_LINES:={
	"bill_nye":["I tried to tell a friction joke. It dragged.","Thank you. Now see if the result holds up a second time."],
	"mr_apple":["I know one about a straight line, but there are three detours before the end.","Oh, that's lovely to hear. I'll tell you how I learned it sometime."],
	"ms_clocks":["Two clocks disagreeing is only funny until you have to sign the calibration form.","Thank you. I put some care into that."],
	"mr_phillips":["The apprentice told me his meter was broken. It was set to off. Good meter.","Thanks. The next test is whether you can do it without me."],
	"mr_gusto":["I made a circuit with a great sense of timing. It waits until the class arrives to stop working.","Careful. Encouragement only makes me bring in more props."],
	"mr_hamstrings":["I ran a ten-kilometer loop and ended up back at the lab. Typical feedback circuit.","Thanks. You put some good work in too."],
	"mr_allu":["I fixed a broken radio and it wouldn't stop talking. Starting to know how it feels.","Hey, thanks. Which bit clicked for you?"],
	"bill":["Measure twice, cut once. Tell that to the board I measured once.","Good. Put that same care into your work."],
	"chad":["I told my spotter I was doing a clean set. He handed me a mop.","I'll take it. Now let's see you beat that last result."],
	"ms_bird_heart":["I tried to teach my neighbor's parrot a formula. It learned to ask for extra credit.","Oh, thank you, dear. That's very kind of you."],
	"dr_volts":["A capacitor and a battery had a disagreement. I decided to measure the tension.","Thank you! Wait until you see what happens when we change the frequency."],
	"stanley":["I had one about a crossword. Can't remember the clue.","Mm. That's kind of you."],
	"ms_rivera":["My first prototype had one user. Me. It still got a complaint.","Thanks. I'm glad that made the idea easier to follow."],
	"mr_blake":["The bench supply and I agreed on a break. It took one before I did.","Thanks. It's a good day when everything works on the first try."],
	"mr_stone":["A student once brought two pencils to a practical. I almost fell out of my chair.","Thank you. Carry on."],
	"josh_wildes":["There are two kinds of people: those who understand binary and those who were promised a better joke.","Hey, appreciate it. You're getting pretty quick at this yourself."],
	"bradley":["I cleaned up my toolbox once. Took me a week to find anything.","Thanks. Good to hear."],
	"jeff":["I bought a tool to save ten minutes. Spent the whole night making it fit. Works fine now.","Thanks. Now you get a turn."],
	"mr_bro":["My gym buddy said he was lifting light today. Dude, that's the lamp, put it down.","Yo, appreciate that. You’ve been putting in the work too."],
	"brian":["I wrote a joke with no setup. It finished early. Moving on.","Yeah, thanks. What were we doing?"],
	"ms_lunch":["They asked if I made the soup from scratch. At six in the morning, it felt like I scratched up the whole kitchen.","Well, that's sweet of you. Want a little more?"],
}

static func teacher(id: String) -> Dictionary:
	var row: Array=FACULTY.get(id,["New instructor finding their feet on campus.","their subject","professional and curious","Hi. Let's get started.","What's actually bothering you?",.48,.64,.38,.57])
	var traits:={"temper":row[5],"patience":row[6],"humor":row[7],"energy":row[8]}
	var teaching: Array=FACULTY_TEACHING.get(id,[38,.73,.75,.72,.65,.7])
	traits.merge({"teaching_competence":teaching[1],"reasoning":teaching[2],"teaching_effort":teaching[3],
		"demonstrations":teaching[4],"warmth":teaching[5]})
	var lines:=_lines(traits,row[3],row[4])
	if SOCIAL_LINES.has(id):
		lines.joke=SOCIAL_LINES[id][0]
		lines.compliment=SOCIAL_LINES[id][1]
	if id=="stanley":lines.gaming="Fortnite? That's one of the computer games, isn't it? I couldn't tell you what it costs."
	if id=="mr_bro":lines.gaming="Man, I'm way behind on Fortnite. No clue what that pass goes for."
	if id=="ms_bird_heart":lines.apology="Thank you for saying that, dear. We can start over."
	if id=="mr_stone":lines.apology="Apology accepted. Let's get back to work."
	var identity: Array=FACULTY_IDENTITY.get(id,["trained in their subject","students should understand the reason for a procedure","makes notes between lessons"])
	return {"age":teaching[0],"background":row[0],"interest":row[1],"style":row[2],"traits":traits,"lines":lines,
		"education":identity[0],"values":identity[1],"habits":identity[2]}

static func student(person: Dictionary) -> Dictionary:
	var traits:={"temper":.25+(1.-float(person.focus))*.5,"patience":float(person.focus),
		"humor":float(person.curiosity),"energy":float(person.talk),"reasoning":float(person.knowledge),
		"warmth":.38+float(person.curiosity)*.55}
	var confident: bool=person.confidence>.55
	var greeting:="Hey! How's your day going?" if confident else "Oh, hi. I was just going over my notes."
	var insult:="Hey, what was that for?" if confident else "I didn't do anything to you."
	var program:="electronics technology" if person.interest in ["robots","electronics","games"] else "general studies"
	return {"age":18+posmod(str(person.id).hash(),9),"background":"Fellow student finding their way on campus. Spends free time on "+str(person.interest)+".",
		"education":"studies "+program,"values":"likes learning with classmates" if person.talk>.5 else "values having time to think",
		"habits":"compares notes before tests" if person.focus>.55 else "asks a classmate when a lecture moves too fast",
		"traits":traits,"lines":_lines(traits,greeting,insult)}

static func _lines(traits: Dictionary,greeting: String,insult: String) -> Dictionary:
	return {"greeting":greeting,"insult":insult,
		"boundary":"Enough. I'm done with this conversation." if traits.temper>.6 else "I need a minute. We can talk later.",
		"apology":"All right. Let's start over." if traits.patience>.65 else "I heard you. Give me a minute.",
		"compliment":"Hey, thanks. I'll take that." if traits.energy>.6 else "That's kind of you to say.",
		"joke":"I had a joke about procrastination. I'll tell you later." if traits.humor>.6 else "You've caught me without a punch line.",
		"gaming":"I don't really keep up with games. You'd have to ask someone who plays.",
		"unknown":"That's outside my lane." if traits.energy>.6 else "I couldn't give you a good answer to that.",
		"calculation":"That's too much to do in my head. Give me a calculator." if traits.energy>.55 else "I'd need a calculator for those numbers."}
