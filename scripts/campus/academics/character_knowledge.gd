extends RefCounted
static var arithmetic:=RegEx.create_from_string(r"[0-9]{5,}\s*(?:\*|×|times|multiplied)(?:\s+by)?\s*[0-9]{5,}")
const TOPICS:={
	"gaming":["fortnite","battle pass","roblox","minecraft","v-bucks","raid boss"],
	"medicine":["diagnosis","surgery","chemotherapy","prescription","antibiotics"],
	"law":["statute","lawsuit","court precedent","legislation","legal advice"],
	"math":["derivative","integral","matrix","phasor","equation","trig","probability","quadratic"],
	"electronics":["resistor","capacitor","circuit","voltage","breadboard","transistor","logic gate","oscilloscope","alternating current","reactance","ac signal","rlc"],
	"fitness":["deadlift","workout","bench press","lifting","squat","gym routine"],
	"programming":["compiler","python","javascript","source code","programming","algorithm"],
	"mechanics":["bearing","wheel alignment","gearbox","welding","torque wrench","hydraulic"],
	"culture":["composer","art history","museum","poetry","folk music"],
	"everyday":["laundry","cooking","bus fare","grocery","library","recipe"],
}
const LEARNABLE_TOPICS:=["fortnite","minecraft","roblox","capacitor","resistor","breadboard","phasor","matrix","transistor","compiler","gearbox"]
const COURSE_DOMAINS:={"MTH147":"math","MTH255":"math","ETY155":"electronics","ELM253":"electronics","DGS266":"electronics"}
const MAX_PRACTICE_GAIN:=.18
const PRACTICE_PROFICIENCY_CEILING:=.70
const PRACTICE_DIFFICULTY_CEILING:=.65

static func domain_of(text: String) -> String:
	text=text.to_lower()
	if "escape the matrix" in text or "escaping the matrix" in text:return "conversation"
	for topic in TOPICS:
		if TOPICS[topic].any(func(word):return word in text):return topic
	return "conversation"

static func assess(person: Dictionary,activity: Dictionary,question: String,interpretation: Dictionary={},prior_learning: Dictionary={}) -> Dictionary:
	var text:=question.to_lower()
	var traits: Dictionary=person.get("traits",{})
	var kind := str(interpretation.get("question_kind",""))
	if kind in ["personal_experience","biography","opinion","casual"]:
		return {"allowed":true,"domain":"conversation","question_kind":kind,"mode":"personal_conversation",
			"reason":"Own experiences and opinions use the character's life and beliefs, not a specialist factual-knowledge gate.",
			"limit_rules":"Personal opinions are not factual expertise. Reuse established life facts; fictional improvisation cannot establish gameplay events or academic results."}
	if arithmetic.search(text.replace(",","").replace("_",""))!=null or ("multiply" in text and text.count("0")>=10):
		return {"allowed":false,"line":"","domain":"arithmetic","mode":"use_tool","reason":"Calculation exceeds reliable mental arithmetic; use an observed calculator."}
	var semantic_domain:=str(interpretation.get("domain","")).to_lower().strip_edges()
	var aliases:={"mathematics":"math","electrical":"electronics","computer_science":"programming","medical":"medicine","legal":"law","music":"culture","art":"culture","engineering":"mechanics","general_knowledge":"everyday","physics":"science","chemistry":"science","personal":"conversation","social":"conversation"}
	var domain: String=aliases.get(semantic_domain,semantic_domain) if not semantic_domain.is_empty() else domain_of(text)
	var has_semantic:=not semantic_domain.is_empty()
	var difficulty:=clampf(float(interpretation.get("difficulty",.35)),0.,1.)
	var detailed:=["optimal","exact","professional","specialist","derive","quantum","calibrate","proof","standards"].any(func(word):return word in text)
	var current:=bool(interpretation.get("current_information",false)) or (domain=="gaming" and ["price","cost","season","current","latest","v-bucks","vbucks","how much"].any(func(word):return word in text))
	if not has_semantic:difficulty=.78 if detailed else .35
	if domain=="conversation":
		return {"allowed":true,"domain":domain,"mode":"personal_conversation","requires_semantic_check":not has_semantic,
			"reason":"Use personal opinions and ordinary lived experience. An unrecognized technical term is not permission for expert knowledge.",
			"limit_rules":"Before answering an unfamiliar factual request, classify its field and difficulty against this profile. Unknown specialist subjects require uncertainty or an in-game resource; never borrow the model's unlimited knowledge."}
	var authored_proficiency:=float(person.get("knowledge_domains",{}).get(domain,.18))
	var proficiency:=authored_proficiency
	var known_domain: bool=person.get("knowledge_domains",{}).has(domain)
	var course:=str(activity.get("course",""))
	if domain=="electronics" and activity.get("phase","")=="lesson" and COURSE_DOMAINS.get(course,"")==domain and course in person.get("subjects",[]):
		proficiency=maxf(.8,proficiency)
	# This fifth argument comes directly from the host's persisted outcome
	# ledger. Neither dialogue, semantic output nor proposed profile fields can
	# award knowledge. The original profile remains an immutable baseline.
	var learning:=_practice_learning(person,activity,domain,difficulty,current,detailed,interpretation,prior_learning)
	if float(learning.gain)>0.:
		var previous:=proficiency
		proficiency=maxf(proficiency,minf(PRACTICE_PROFICIENCY_CEILING,proficiency+float(learning.gain)))
		learning.gain=proficiency-previous
		known_domain=known_domain or float(learning.gain)>0.
	var required:=clampf(.22+difficulty*.64,.25,.91)
	var restricted: bool=domain in ["medicine","law","specialist_unknown","unknown_specialist"] or not known_domain and difficulty>.4
	if current:restricted=true
	var allowed: bool=not restricted and proficiency>=required
	var mode:="explain" if allowed else ("use_resource" if current else "uncertain")
	var reason:="Within this character's education and experience." if allowed else "This exceeds this character's established knowledge, is specialist information, or needs a current in-game source."
	if allowed and float(learning.gain)>0.:reason="Established knowledge reinforced by this character's verified supervised practice; limited to ordinary coursework."
	if proficiency>=required-.12 and not restricted and not allowed:mode="tentative_estimate"
	return {"allowed":allowed,"line":"","domain":domain,"mode":mode,"proficiency":proficiency,"authored_proficiency":authored_proficiency,"prior_learning":learning,
		"required":required,"difficulty":difficulty,"current_information":current,"reason":reason,
		"limit_rules":"Do not invent expertise, current facts or tool use. You may say what ordinary part you recognize, admit uncertainty, or ask someone who knows. Verified practice supports only bounded familiarity with its course domain, never specialist expertise or permission to help with an active assessment. Official course explanations and safety instructions must remain accurate."}

static func _practice_learning(person: Dictionary,activity: Dictionary,domain: String,difficulty: float,current: bool,detailed: bool,interpretation: Dictionary,prior: Dictionary) -> Dictionary:
	var result:={"gain":0.,"source":"none","course":"","reason":"No qualifying verified personal practice."}
	if prior.get("source","")!="verified_host_activity" or prior.get("character_id","")!=str(person.get("id","")) or prior.get("observer_id","")!=str(person.get("id","")):return result
	if not prior.get("courses") is Dictionary:return result
	if current or domain in ["medicine","law","specialist_unknown","unknown_specialist"] or difficulty>PRACTICE_DIFFICULTY_CEILING or detailed:
		result.reason="Course practice does not establish specialist, advanced or current information."
		return result
	if activity.get("phase","")=="assignment" and interpretation.get("assessment_request","social") in ["solution","clarification"]:
		result.reason="Prior learning cannot authorize assistance with assessed work."
		return result
	var current_course:=str(activity.get("course",""))
	for course in COURSE_DOMAINS:
		if COURSE_DOMAINS[course]!=domain:continue
		var evidence: Variant=prior.courses.get(course)
		if not evidence is Dictionary:continue
		if not _practice_count(evidence.get("attempts"),4096) or not _practice_count(evidence.get("successes"),4096):continue
		if not _practice_count(evidence.get("recent_attempts"),12) or not _practice_count(evidence.get("recent_successes"),12):continue
		var attempts:=int(evidence.attempts)
		var successes:=int(evidence.successes)
		var recent:=int(evidence.recent_attempts)
		var correct:=int(evidence.recent_successes)
		if attempts<3 or recent<3 or successes<3 or successes>attempts or recent>attempts or correct>recent or correct>successes:continue
		# Retain a small foundation from earlier demonstrated success. Recent
		# checked work supplies the rest; repeated failures cannot invent mastery.
		var foundation:=minf(.03,float(successes)*.005)
		var practice:=minf(MAX_PRACTICE_GAIN,foundation+.0125*float(correct)*float(correct)/float(recent))
		# Practice transfers conservatively within a subject. Multiple courses
		# cannot stack into unlimited expertise in an entire field.
		var transfer:=1. if current_course==course else (.65 if COURSE_DOMAINS.has(current_course) else .8)
		var gain:=practice*transfer
		if gain<=float(result.gain):continue
		result={"gain":gain,"source":"verified_host_activity","course":course,"attempts":attempts,"successes":successes,
			"recent_attempts":recent,"recent_successes":correct,"transfer":transfer,
			"reason":"Bounded familiarity from this character's own checked course practice; coarse outcomes do not prove mastery of a specific concept."}
	return result

static func _practice_count(value: Variant,maximum: int) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value)>=0. and float(value)<=maximum and float(value)==floorf(float(value))

static func statement_topic(text: String) -> String:
	for topic in LEARNABLE_TOPICS:
		if text.begins_with(topic+" is ") or text.begins_with("a "+topic+" is "):return topic
	return ""

static func question_topic(text: String) -> String:
	var query:=text.to_lower().strip_edges().rstrip("?!.,")
	for topic in LEARNABLE_TOPICS:
		if query in ["what is "+topic,"what is a "+topic,"do you remember what "+topic+" is"]:return topic
	return ""
