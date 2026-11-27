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

static func domain_of(text: String) -> String:
	for topic in TOPICS:
		if TOPICS[topic].any(func(word):return word in text):return topic
	return "conversation"

static func assess(person: Dictionary,activity: Dictionary,question: String) -> Dictionary:
	var text:=question.to_lower()
	if arithmetic.search(text.replace(",","").replace("_",""))!=null or ("multiply" in text and text.count("0")>=10):
		return {"allowed":false,"line":person.lines.calculation,"domain":"arithmetic"}
	var domain:=domain_of(text)
	if domain=="conversation":return {"allowed":true,"domain":domain}
	var proficiency:=float(person.knowledge_domains.get(domain,.1))
	var detailed:=["optimal","exact","professional","specialist","derive","quantum","calibrate","proof","standards"].any(func(word):return word in text)
	if domain=="gaming":detailed=detailed or ["price","cost","season","mechanic","v-bucks","vbucks","how much"].any(func(word):return word in text)
	if domain=="electronics" and activity.get("phase","")=="lesson" and str(activity.get("course","")) in person.get("subjects",[]):
		proficiency=maxf(.8,proficiency)
	var required:=.7 if detailed else .35
	if domain in ["medicine","law"] or proficiency<required:
		var response: String=person.lines.unknown
		if domain=="gaming" and proficiency<.35:response=person.lines.gaming
		return {"allowed":false,"line":response,"domain":domain}
	return {"allowed":true,"domain":domain}

static func statement_topic(text: String) -> String:
	for topic in LEARNABLE_TOPICS:
		if text.begins_with(topic+" is ") or text.begins_with("a "+topic+" is "):return topic
	return ""

static func question_topic(text: String) -> String:
	var query:=text.to_lower().strip_edges().rstrip("?!.,")
	for topic in LEARNABLE_TOPICS:
		if query in ["what is "+topic,"what is a "+topic,"do you remember what "+topic+" is"]:return topic
	return ""
