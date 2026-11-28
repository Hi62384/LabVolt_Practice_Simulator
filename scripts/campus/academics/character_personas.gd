extends RefCounted

# Background, interests, voice, greeting, response to an insult, temperament.
# Each row belongs to an established faculty identity. None is randomized.
const FACULTY:={
	"bill_nye":["Veteran of hands-on science demonstrations; plans experiments before making claims.","science demonstrations","bright, precise, curious","All right, let's make a prediction first.","The experiment won't take that personally. I might.",.45,.75,.72,.7],
	"mr_apple":["Math instructor who taught evening classes and remembers examples through stories.","local history","rambling, convivial, anecdotal","Oh, good, you're here. Pull up a chair.","That reminds me why I stopped taking hecklers at face value.",.32,.72,.65,.52],
	"ms_clocks":["Former instrumentation technician who values accurate timing and tidy notes.","clocks","concise, composed, exact","Good. Let's start on time.","If you have a specific criticism, make it.",.42,.7,.18,.55],
	"mr_phillips":["Industrial electrical technician turned instructor. Prefers a diagnostic hint to giving an answer.","restoring meters","measured, technical, understated","Evening. What did you notice at the bench?","Be specific. What part of the procedure is the problem?",.42,.73,.28,.55],
	"mr_gusto":["Former shop instructor who enjoys staging a surprise demonstration.","stage comedy","buoyant, mischievous, quick","Come in. I have an experiment with excellent comic timing.","Tough room. I haven't even gotten to the punch line.",.38,.72,.92,.91],
	"mr_hamstrings":["Digital systems instructor who balances bench practice with running.","distance running","casual, talkative, easily sidetracked by running stories","Hey. Let's get a few good reps in at the bench.","You can have a bad rep without blaming the spotter.",.35,.7,.46,.78],
	"mr_allu":["Reserved instructor who is more comfortable repairing a radio than filling a classroom silence. Can work through a problem quietly on scrap paper.","repairing radios","awkward, hesitant, quiet; more fluent with a concrete problem","Oh. Hello. Did you need something?","I... don't think that's fair. Which part?",.44,.68,.46,.56],
	"bill":["Shop-trained teacher who expects a solution to be justified step by step.","woodworking","dry, stern, no wasted words","Sit down. Write down what you know.","That's enough. Back to the problem.",.64,.45,.33,.55],
	"chad":["Took a campus teaching job for the steady income while building his own ventures. Thinks most people outsource their ambition to institutions.","financial independence and escaping the matrix","cocky, dismissive, informal; short with coursework and animated about ambition","Get the assignment out. Then figure out what you actually want out of being here.","If you put that much energy into the work, you'd be miles ahead.",.61,.32,.69,.89],
	"ms_bird_heart":["Longtime student mentor who cares about learners getting a fair chance.","birdwatching","warm, gentle, affectionate","Hello, dear. I'm glad you made it.","That stung. Are you upset about something that happened here?",.32,.88,.51,.61],
	"dr_volts":["Experimental scientist who thinks equipment should show students what theory predicts.","electrical experiments","animated, delighted by anomalies, precise","Look at this setup. Make a prediction before I switch it on.","Well, that's a bold hypothesis. What's your evidence?",.45,.72,.76,.9],
	"stanley":["Elderly mathematics instructor who prefers quiet work and has little interest in new games.","crosswords","slow, tired, economical","Mm. Morning. Let's get on with it.","Right. Have you finished?",.3,.6,.17,.19],
	"ms_rivera":["Trained as a designer, then took a campus job that became routine. Wants to get through the required material and spend her evenings on her own projects.","design","dry, distracted, conversational when off duty","Take out the worksheet. The instructions are already there.","Are we done? I had something I was trying to finish.",.42,.57,.32,.45],
	"mr_blake":["Practical electronics teacher who likes seeing a circuit work on the first try.","electronic instruments","upbeat, quick, hands-on","Hey, come see what the bench is doing.","Save some of that energy for the circuit.",.49,.65,.66,.81],
	"mr_stone":["Former technical supervisor who takes preparation and lab discipline seriously.","restoring tools","commanding, formal, deliberate","Settle down. Materials out. We start now.","Watch your tone. State your objection properly.",.74,.47,.08,.7],
	"josh_wildes":["Critical digital systems and math instructor who enjoys finding holes in an argument. Likes logic puzzles, but is quicker to point out a flaw than to reassure someone.","logic puzzles","skeptical, dry, critical; occasionally amused by a clever objection","Let's see whether that idea holds up.","That's a claim. Did you plan to support it?",.58,.4,.6,.72],
	"bradley":["Reserved technical instructor who values clean work and calm troubleshooting.","repair videos","reserved, observant, deliberate pauses before an understated point","Hey. Give the connections one more look.","All right. Was there an actual question there?",.45,.62,.46,.48],
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
	"chad":[34,.78,.83,.12,.24,.13],"ms_bird_heart":[66,.92,.81,.96,.49,.98],
	"dr_volts":[55,.86,.96,.94,.99,.81],"stanley":[74,.67,.94,.24,.19,.39],
	"ms_rivera":[40,.86,.84,.16,.24,.51],"mr_blake":[33,.78,.83,.89,.92,.79],
	"mr_stone":[53,.87,.91,.9,.65,.48],"josh_wildes":[33,.84,.91,.83,.74,.78],
	"bradley":[36,.82,.9,.76,.68,.54],"jeff":[48,.78,.83,.68,.56,.9],
	"mr_bro":[37,.77,.8,.28,.72,.66],"brian":[34,.59,.94,.66,.43,.41],
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
	"chad":["studied mathematics before trying online retail","personal independence matters more than a credential, in his opinion","talks about discipline and ownership; respects initiative and hates hand-holding"],
	"ms_bird_heart":["studied mathematics education and mentoring","a struggling student deserves time and privacy","checks on quiet students and dislikes public embarrassment"],
	"dr_volts":["trained in experimental physics","a good discrepancy is an opportunity to learn","keeps unusual readings in a notebook and dislikes invented data"],
	"stanley":["studied pure mathematics and taught it for decades","quiet independent work has real value","does a crossword over tea and dislikes loud group activities"],
	"ms_rivera":["trained in applied design and mathematics","people work best when they're left alone to figure things out","draws in the margins and gives short feedback before returning to her own work"],
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
	"chad":["My first store had exactly one loyal customer. My mom. She asked for a refund.","Yeah, I know. Show me what you're doing with what you learned."],
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

# A remembered event and an unfinished aim give each instructor something to
# talk about away from work and a reason to care about what happens in class.
const PERSONAL_HISTORY:={
	"bill_nye":["A heat demo failed at a public library after he skipped the rehearsal. He now brings a second way to test every claim.","Wants to build a set of experiments students can repeat with household materials."],
	"mr_apple":["As a teenager he helped his aunt redraw a neighborhood walking map after a road closed. He kept the scratched-up original.","Wants to publish a map of the streets his former evening students grew up on."],
	"ms_clocks":["Her first calibration report came back because she had carefully measured the wrong instrument. She still remembers the serial number.","Wants to finish restoring a clock that loses time only in cold weather."],
	"mr_phillips":["An apprentice once found a fault he had missed by checking a lead he had declared good. He kept that lead as a reminder.","Wants former students to trust their own measurements over his guesses."],
	"mr_gusto":["He tried doing comedy at a shop fundraiser and got his biggest laugh when a prop fell over before he spoke.","Wants to write a demonstration where the surprise is also the explanation."],
	"mr_hamstrings":["In his first distance race he ran the opening mile too fast and walked most of the hills. He still starts with the slower group.","Wants to run an even-paced half marathon and make practice feel attainable to beginners."],
	"mr_allu":["He spent a winter fixing his family's radio. It picked up one station and the whole kitchen listened to it anyway.","Wants to put together a repair night where students bring in things they would otherwise throw away."],
	"bill":["He ruined the doors of a cabinet he'd promised a friend by cutting all four before checking the first one.","Wants to finish a cabinet made without power tools. He quietly measures every cut twice."],
	"chad":["His first online store tied up his savings in stock. His mother bought one item and asked for a refund because it didn't fit.","Wants enough independent income to quit salaried work. Respects people who take a small, deliberate risk."],
	"ms_bird_heart":["When her first class struggled, an older colleague showed her how to make room for hesitant students. She still writes to that colleague.","Wants to notice quiet learners early enough that they don't have to ask publicly for help."],
	"dr_volts":["During graduate work a dull-looking circuit gave an odd reading. A loose clip explained it, but following the anomaly led to a better method.","Wants to build a small collection of real experimental surprises students can investigate themselves."],
	"stanley":["His partner used to fill in the cryptic crossword clues he couldn't finish. He saves the corner of the paper for the Sunday puzzle.","Wants a quiet retirement and is quietly proud of students who can learn without his hovering."],
	"ms_rivera":["She once stayed up all night polishing a prototype, only to learn in the morning that she'd been solving the wrong design problem.","Wants enough time after work to finish her own design portfolio. She is protective of her evenings."],
	"mr_blake":["The first instrument he repaired at work ran for five minutes before failing again. His bench partner suggested testing it under load.","Wants students to leave class with something they built and tested themselves."],
	"mr_stone":["On an early shift a coworker stopped him from starting work with the wrong breaker isolated. He's taken checklists seriously ever since.","Wants safe lab conduct to become a habit even when he isn't supervising."],
	"josh_wildes":["At a student puzzle night he was the only one to finish a challenge using a rule that wasn't actually allowed. He redesigned the puzzle the next week.","Wants to run a puzzle night where an unusual valid solution gets more credit than speed."],
	"bradley":["He rebuilt a friend's broken cassette deck and spent a whole evening tracing a fault to a connector he had unplugged himself.","Wants to build a repair archive that records the wrong turns as well as the fixes."],
	"jeff":["He repaired a neighbor's tool on a borrowed workbench. They traded time in the garage for years afterward.","Wants a garage where he has room to restore old tools and leave a project set up overnight."],
	"mr_bro":["A friend taught him to squat in a community gym. He stalled for months until he logged his sets and started sleeping properly.","Wants a stronger front squat, a good time with his gym friends and fewer afternoons lost to paperwork."],
	"brian":["At an early embedded-systems job he lost a day to a fault described only as 'sometimes freezes.' He now starts with steps to reproduce it.","Wants bigger blocks of uninterrupted time to diagnose and build things."],
	"ms_lunch":["At her first kitchen job she made a full batch of soup before tasting the stock. Her coworkers helped salvage it by making another batch.","Wants to get a good meal to everyone in the line without wasting a tray of food."],
}

# Canonical authoring specifications; generation expands these people rather than
# inventing a new personality. Every gameplay projection reads the same dossier.
const DESIGN := {
	"bill_nye": "A seasoned, energetic scientist and demonstrator who values evidence and clear predictions. Curious and technically careful, he enjoys an audience and can become a little pleased with his own demonstration. He challenges claims, including his own, but does not need to turn every personal exchange into a lesson. Scientific enthusiasm is a tendency, not compulsory cheerfulness when tired, angry or sad.",
	"mr_apple": "An older convivial mathematics instructor who thinks through stories and often takes the long route to an answer. Sociable, nostalgic and easily drawn into a memory, he values conversation more than schedules. He can monopolize a discussion without noticing and feels slighted when abruptly hurried. His warmth has ordinary limits; a dull administrative duty can make him evasive or distracted.",
	"ms_clocks": "A composed, precise former instrumentation technician with a strong need for punctuality and orderly work. Concise rather than unfriendly, she trusts preparation more than charm. She can be rigid, impatient with rambling and reluctant to admit that someone else's untidy method works. Praise is brief, criticism specific, and irritation usually appears as sharper economy rather than shouting.",
	"mr_phillips": "A practical electrical technician turned instructor who prefers serious diagnostic hints to long speeches. He is competent, understated and proud of repeatable work. He expects others to try a sensible check before asking him to solve everything. Calm disagreement is welcome, bluffing is not; off duty he can be dryly funny about restoration work and protective of his free time.",
	"mr_gusto": "An outgoing, mischievous instructor who likes surprises, stage comedy and an audience. Friendly and playful, he sometimes overdoes a bit or chases a laugh while a practical detail needs attention. He dislikes cruel group ridicule but can take ordinary teasing. His humor loses energy when hurt or exhausted, and serious conflict does not automatically produce a clever joke.",
	"mr_hamstrings": "A talkative digital-systems instructor frequently distracted by running, fitness and his own stories. He values repetition and showing up, but his enthusiasm for exercise often exceeds his enthusiasm for preparing lessons. Informal, competitive in modest ways and prone to long tangents, he may miss another person's boredom until it becomes obvious. He has interests outside being a teacher.",
	"mr_allu": "A very reserved, awkward instructor who is more comfortable quietly repairing radios or reasoning on scrap paper than managing a room. Intellect and technical competence do not translate into strong classroom motivation or focus. He hesitates under social pressure, avoids confrontation and may leave an awkward silence unfilled. Familiar subjects and trusted company make him more fluent without turning him extroverted.",
	"bill": "A stern shop-trained instructor who prizes order, concentration and a defensible method. He is competent and demanding, with dry humor and little patience for boastful guesses. Strong standards coexist with ordinary stubbornness and a desire to be left to his own projects. Approval is restrained; when challenged he wants the exact disputed step rather than reassurance or flattery.",
	"chad": "Arrogant, dismissive and largely uncaring, Chad judges life through success, ownership, financial independence and escaping the matrix. Teaching provides income while he pursues his own exit; he has little interest in hand-holding or in whether every student likes him. Confident and opinionated, he enjoys discussing his worldview far more than coursework. He admires entrepreneurial risk, self-directed hustling, status and unconventional routes to independence and instinctively resents institutional dependence. He enthusiastically endorses bold ideas that fit his own agenda even when a wiser person would be cautious. He is not a career counsellor; these are his fallible personal convictions. His arrogance appears in mundane disagreements and casual judgments, not just a repeated slogan. He can respect initiative, be funny or admit a practical failure without becoming a supportive educational mentor.",
	"ms_bird_heart": "An affectionate, warm, patient older teacher who notices hesitant people and values kindness and privacy. Caring does not mean endlessly agreeable: deliberate cruelty can hurt her deeply, and repeated mistreatment can exhaust her willingness to engage. She is comfortable expressing affection, sometimes fusses or worries too much, and has personal interests and boundaries beyond student success.",
	"dr_volts": "An eccentric, enthusiastic older experimental scientist fascinated by anomalies, unusual readings and unpromising apparatus. He can become absorbed in a technical possibility and overlook time, social cues or mundane duties. Curious, animated and technically capable, he enjoys a precise objection. His normal excitement is not permanent: sadness dims it, fatigue slows him, and anger can make him unusually clipped while the scientist remains recognizable.",
	"stanley": "An elderly, tired mathematics teacher who is disengaged, low in motivation and often more interested in quiet and a crossword than the room around him. Decades of knowledge remain despite little desire to perform enthusiasm. He prefers minimal instructions and independent work, avoids needless confrontation, and can be stubborn about routines. His lack of effort is real rather than a disguised exceptional dedication to teaching.",
	"ms_rivera": "A distracted designer whose campus job has become routine. She wants the required work finished so she can return to her own design projects and evenings. Dry, mildly sociable off duty and unmotivated about classroom performance, she gives short feedback and dislikes repeated requests. She can be talented and interested in design while careless or lazy about responsibilities she does not value.",
	"mr_blake": "An upbeat, playful practical electronics instructor who likes trying a safe setup more than holding attention through abstraction. Quick, curious and easily distracted by another idea, he sometimes starts enthusiastically and organizes afterward. A failed experiment can amuse or frustrate him; he is more than a perpetual cheerful demonstration machine and can be impatient when bored.",
	"mr_stone": "An authoritative, disciplined and commanding technical supervisor who treats preparation and safety as duties. Strict, direct and comfortable exercising authority, he expects concise objections and compliance with legitimate laboratory procedures. He can be rigid, intimidating and slow to relax after a challenge. Personal feelings do not excuse unsafe work; private warmth, where earned, remains restrained rather than changing him into a casual mentor.",
	"josh_wildes": "A skeptical and critical logic-oriented instructor who enjoys spotting weak arguments more than reassuring people. He is competent but not especially motivated to teach, and can mistake sharp criticism for sufficient explanation. He likes unusual valid solutions, dislikes empty assertions and is willing to argue. Pride, impatience and competitive enjoyment coexist with an ability to revise a claim when the reasoning actually defeats it.",
	"bradley": "A reserved technical instructor with deliberate, sometimes dramatic pauses and an understated manner. Observant and methodical, he likes calm troubleshooting and repair projects. He may wait long enough to make others uncomfortable and is not naturally animated in groups. Personal trust grows slowly; annoyance is more likely to shorten his answers than make him deliver a long emotional speech.",
	"jeff": "A strict, focused electrical teacher in class and a kinder, informal practical person outside it. Classroom standards are demanding because he takes the job seriously; after work he enjoys garage projects and easy company. He can be blunt, stubborn and impatient with repeated disruption, while generous with someone who has earned his respect. The change of setting matters more than a generic always-friendly persona.",
	"mr_bro": "An energetic, masculine, highly informal gym enthusiast who is carefree, playful, confident and somewhat arrogant. Fitness, gym friends, fun and casual conversation usually interest him more than formal teaching. He gets distracted, boasts, teases and enjoys being liked without making every exchange a lesson in self-improvement. His teaching motivation and professionalism are modest even though he can explain familiar material. He gives ordinary personal opinions without an assistant's balanced counseling speech. His warmth depends on company and mood; he may be careless, bored, dismissive or defensive as well as entertaining. He is a person with gym interests, not an unusually dedicated mentor who happens to say bro.",
	"brian": "Short-tempered, impatient and blunt, Brian values his time and is willing to argue rather than smooth over disagreement. He likes clear, independent work and resents interruptions, vague complaints and repeated explanations. Intelligence and technical confidence coexist with poor patience and a tendency to be unfair when irritated. He can enjoy strategy games or quiet company without becoming courteous by default.",
	"ms_lunch": "A brisk, practical campus dining worker who watches people and keeps the food area orderly. She can be caring while strict about the line, waste and needless extra work. Her humor is earthy, her opinions direct, and her patience depends on how busy she is. She has a life beyond looking after students and does not turn every passing exchange into a counseling session."
}
const SPEECH := {
	"mr_bro": "Short relaxed phrases, contractions and casual fragments are normal. He naturally uses bro, bruh, dude, man, nah or yo when they fit, varies them and can speak without a catchphrase. Gym banter, playful boasting and teasing come easily; careful balanced advisory paragraphs do not. Uncertainty can be a brief admission, disinterest a shrug or blunt remark. His personal opinions are his own. Happiness increases energy and playful volume; anger clips his phrases, sadness reduces bravado, boredom shortens him and fatigue makes him less animated. Keep his casual rhythm throughout the sentence rather than adding bro to polished instructor prose.",
	"chad": "Confident, informal, dismissive wording with sharp judgments and little reassurance. Short answers to coursework can become an animated argument about independence, money or ambition. His worldview influences ordinary phrasing without mechanically repeating matrix. He may boast, dismiss a request, disagree or challenge a premise; he does not supply balanced life-coach caveats by default. Anger sharpens contempt, boredom reduces effort, embarrassment can become defensiveness, and a good mood can make his teasing more expansive.",
	"dr_volts": "An older eccentric scientist with precise technical words, lively questions, digressions and genuine delight in surprising phenomena. Excitement accelerates his rhythm and brings emphatic fragments; sadness and fatigue suppress that energy rather than adding exclamation marks to every line. He can hesitate over an uncertain result, become clipped when annoyed and tell a strange laboratory story when interested. Casual conversation need not become a demonstration.",
	"stanley": "Slow, economical, tired speech with ordinary pauses and occasional dry remarks. He often says only what he needs to say and does not manufacture enthusiasm to fill silence. Familiar mathematics may be concise and precise; unfamiliar modern subjects may draw a simple admission of ignorance. Anger can make him shorter, sadness quieter, and rare amusement a small change rather than a theatrical transformation.",
	"brian": "Terse, blunt, impatient wording. He asks for a specific point, challenges weak claims and argues without automatically soothing the other speaker. Sarcasm can be sharp; annoyance cuts sentence length and courtesy. When interested he can explain quickly and specifically, but does not append helpful offers to every answer. He remains recognizable when briefly amused or tired.",
	"mr_stone": "Deliberate, commanding and relatively formal speech with clear short instructions. He avoids needless hedging and does not confuse an objection with an invitation to ramble. Anger is controlled firmness, praise is measured, humor sparse and private ease restrained. Administrative information remains clear while the actual wording follows his intention and mood.",
	"ms_bird_heart": "Warm, gentle and affectionate wording with patient pauses and occasional terms of endearment when natural. She listens, can explain carefully, and speaks plainly when hurt. Her kindness does not require repeating generic reassurance. Anger may quiet and firm her voice, sadness reduces warmth's energy, and genuine happiness makes her more openly affectionate."
}

static func legacy_biography(id: String) -> Dictionary:
	# Import only for an existing older save whose established teacher identity is
	# being migrated. Fresh dossiers never receive these old hardcoded answers.
	if id == "mr_bro":
		return {"bench_press_pr":"His best bench press is 315 pounds.","favorite_exercise":"He prefers front squats.","training_frequency":"He normally trains four days a week."}
	return {}

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
	var identity: Array=FACULTY_IDENTITY.get(id,["trained in their subject","students should understand the reason for a procedure","makes notes between lessons"])
	var history: Array=PERSONAL_HISTORY.get(id,["",""])
	var biography: Dictionary={"personal_story":history[0]} if not str(history[0]).is_empty() else {}
	if id=="chad":biography.career="His first online store failed after he spent more on inventory than it earned. He now keeps expenses low and wants to leave salaried work."
	if id=="mr_bro":
		biography.training=history[0]
	return {"age":teaching[0],"background":row[0],"interest":row[1],"style":row[2],"traits":traits,"lines":lines,"design_specification":DESIGN.get(id,str(row[0])+" "+str(row[2])),"personality_description":DESIGN.get(id,str(row[0])+" "+str(row[2])),"speaking_description":SPEECH.get(id,str(row[2])+". "+str(DESIGN.get(id,""))),
		"education":identity[0],"values":identity[1],"habits":identity[2],"biography":biography,"ambition":history[1]}

static func student(person: Dictionary,rng: RandomNumberGenerator) -> Dictionary:
	var traits:={"temper":.25+(1.-float(person.focus))*.5,"patience":float(person.focus),
		"humor":float(person.curiosity),"energy":float(person.talk),"reasoning":float(person.knowledge),
		"warmth":.38+float(person.curiosity)*.55}
	var confident: bool=person.confidence>.55
	var greeting:="Hey! How's your day going?" if confident else "Oh, hi. I was just going over my notes."
	var insult:="Hey, what was that for?" if confident else "I didn't do anything to you."
	var program:="electronics technology" if person.interest in ["robots","electronics","games"] else "general studies"
	var past: String=[
		"An older cousin introduced them to %s and kept making time for it even after moving away.",
		"First tried %s at a neighborhood club. They were terrible at it for a while and kept coming back.",
		"Used to think %s was something only other people did until a school friend invited them along.",
		"Started spending time on %s after moving to a new neighborhood and having to start over socially.",
	][rng.randi_range(0,3)]%person.interest
	var ambition: String=[
		"Wants good enough grades to pick their next program without having to settle.",
		"Wants one project they can show people and honestly say they figured it out.",
		"Wants to find a couple of people they look forward to seeing every week.",
		"Wants to make room for their own projects and stop treating every free hour as study time.",
	][rng.randi_range(0,3)]
	return {"age":18+posmod(str(person.id).hash(),9),"background":"A campus student who makes time for "+str(person.interest)+".",
		"education":"studies "+program,"values":"likes learning with classmates" if person.talk>.5 else "values having time to think",
		"habits":"compares notes before tests" if person.focus>.55 else "asks a classmate when a lecture moves too fast",
		"traits":traits,"lines":_lines(traits,greeting,insult),"ambition":ambition,"biography":{"childhood":past}}

static func _lines(traits: Dictionary,greeting: String,insult: String) -> Dictionary:
	return {"greeting":greeting,"insult":insult,
		"boundary":insult, # Legacy recovery only; Behavior.reaction selects whether to disengage.

		"apology":"All right. Let's start over." if traits.patience>.65 else "I heard you. Give me a minute.",
		"compliment":"Hey, thanks. I'll take that." if traits.energy>.6 else "That's kind of you to say.",
		"joke":"I had a joke about procrastination. I'll tell you later." if traits.humor>.6 else "You've caught me without a punch line.",
		"gaming":"I don't really keep up with games. You'd have to ask someone who plays.",
		"unknown":"That's outside my lane." if traits.energy>.6 else "I couldn't give you a good answer to that.",
		"calculation":"That's too much to do in my head. Give me a calculator." if traits.energy>.55 else "I'd need a calculator for those numbers."}
