extends RefCounted
## The stable speaker, personality, sustained affect, immediate reaction and
## conversational intent are separate inputs. No playback pitch is changed.
const Profiles=preload("res://scripts/campus/academics/teacher_voice_profiles.gd")
const Affect=preload("res://scripts/campus/academics/character_affect.gd")
const Models=preload("res://scripts/campus/ai/openai_models.gd")
const Speech=preload("res://scripts/campus/academics/character_speech.gd")
const EMOTION_KEYS:={"happy":"happiness","angry":"anger","extremely angry":"anger","irritated":"irritation","frustrated":"frustration",
	"stressed":"stress","excited":"excitement","bored":"boredom","sad":"sadness","disappointed":"disappointment",
	"anxious":"anxiety","embarrassed":"embarrassment","amused":"amusement","confident":"confidence","tired":"tiredness",
	"interested":"interest","dismissive":"disinterest","careless":"carelessness","confused":"confusion","concerned":"concern","sarcastic":"sarcasm"}
const INTENTS:={
	"converse":"Talk to one person, with natural turns and ordinary conversational phrasing.",
	"explain":"Explain the supplied facts clearly; preserve every number, qualifier and technical term.",
	"argue":"Defend the point with conversational stress; do not invent new claims.",
	"joke":"Use character-specific comic timing; a brief chuckle is appropriate only if the moment calls for it.",
	"tease":"Let the playfulness or bite be audible without turning into a theatrical narrator.",
	"whisper":"Use a genuine intimate whisper with intelligible words and a short audible range.",
	"warn":"Make the warning unmistakable with deliberate emphasis and clean articulation.",
	"complain":"Allow natural exasperation and pauses; keep the person's usual rhythm.",
	"reassure":"Use attentive, grounded concern; do not automatically sound cheerful.",
	"dismiss":"Let the loss of interest and impatience shorten the phrasing.",
	"challenge":"Ask the challenge with definite stress and a purposeful pause.",
	"celebrate":"Let the immediate success bring audible energy appropriate to this personality.",
	"instruct":"Give the exact supplied instructions clearly and in sequence.",
	"disappoint":"Let the lowered expectation be audible without changing speaker identity.",
}

static func build(person: Dictionary,model: String,priority: int,mood: String="steady",affect: Dictionary={},intent: String="",context: Dictionary={}) -> Dictionary:
	var resolved:=Profiles.resolve(person,model,context.get("voice_override",{}))
	if not bool(resolved.get("ok",false)):return resolved
	model=str(resolved.model)
	var identity: Dictionary=resolved.identity
	var traits: Dictionary=person.get("traits",{})
	var values:=Affect.baseline(traits)
	# Affect.presentation uses {emotions:{...}} while CharacterMind exposes the
	# raw dictionary. Accept both without treating wrapper keys as feelings.
	var supplied: Dictionary=affect.get("emotions",affect) if affect.get("emotions",affect) is Dictionary else {}
	for feeling: String in supplied:
		var value: Variant=supplied[feeling]
		if (value is float or value is int) and is_finite(float(value)):values[feeling]=clampf(float(value),0.,1.)
	var mood_key:=str(EMOTION_KEYS.get(mood,""))
	if not mood_key.is_empty() and not supplied.has(mood_key):values[mood_key]=.92 if mood=="extremely angry" else .62
	var reaction: Dictionary=context.get("immediate_reaction",{})
	var reaction_key:=str(EMOTION_KEYS.get(str(reaction.get("emotion","")),reaction.get("emotion","")))
	if not reaction_key.is_empty():values[reaction_key]=maxf(float(values.get(reaction_key,0.)),_value(reaction,"intensity",.6))
	var selected_intent:=intent if INTENTS.has(intent) else "explain" if priority>=3 else "converse"
	var sorrow:=maxf(float(values.sadness),float(values.disappointment)*.85)
	var fatigue:=float(values.tiredness)
	var anger:=maxf(float(values.anger),maxf(float(values.irritation)*.72,float(values.frustration)*.8))
	var expressiveness:=_value(traits,"expressiveness",.5)
	var restraint:=clampf(_value(traits,"discipline",.5)*.55+_value(traits,"emotional_stability",.5)*.45,0.,1.)
	var excitement:=float(values.excitement)*(1.-sorrow*.85)*(1.-fatigue*.55)
	var energy:=clampf(.28+_value(traits,"energy",.5)*.55+excitement*.44+anger*.22-sorrow*.58-fatigue*.36-float(values.boredom)*.22,.08,1.)
	var pace:=clampf(float(identity.normal_pace)+excitement*.16+anger*.09-sorrow*.2-fatigue*.12-float(values.get("confusion",0.))*.08,.68,1.25)
	var intensity:=clampf(maxf(anger,maxf(excitement,sorrow))*(.6+expressiveness*.4),0.,1.)
	var projection: String="lecture" if priority>=3 else "normal"
	if selected_intent=="whisper":projection="whisper"
	elif anger>=.85 and restraint<.7:projection="shout"
	elif context.get("projection","") in ["whisper","quiet","normal","lecture","shout"]:projection=str(context.projection)
	var feelings: Array[String]=[]
	for feeling: String in values:
		if float(values[feeling])>=.14:feelings.append("%s %.1f"%[feeling,float(values[feeling])])
	feelings.sort()
	var instructions:="PERMANENT SPEAKER: "+str(identity.design_description)+" Preserve age, accent, resonance and timbre through every phrase. "
	instructions+="USUAL SPEAKING STYLE: "+str(person.get("style",identity.mannerisms))+". Articulation: "+str(identity.articulation)+". Mannerisms: "+str(identity.mannerisms)+". These are tendencies, not an unchanging emotion. "
	instructions+="CURRENT MOOD: "+mood+". Emotional mixture: "+", ".join(feelings)+". Vocal energy %.2f, intensity %.2f, conversational pace %.2f. "%[energy,intensity,pace]
	instructions+=_emotional_direction(values,anger,sorrow,fatigue,restraint,expressiveness)
	instructions+=" CHARACTER EXPRESSION: "+str(identity.emotional_tendencies)+" "
	if _value(traits,"arrogance",0.)>.75:instructions+="Keep the character's arrogant, sometimes dismissive outlook; do not turn it into friendly encouragement. "
	if _value(traits,"shyness",0.)>.7:instructions+="Shyness can create tentative starts and pauses; maintain ordinary audible speech instead of making the permanent voice weak or inaudible. "
	instructions+="INTENT: "+str(INTENTS[selected_intent])+" Projection: "+projection+". "
	instructions+="Perform the exact supplied spoken words. Do not add, omit, translate or paraphrase them. Never read stage directions aloud. Use a natural breath, tiny hesitation, sigh or chuckle only when the emotion and line support it; avoid repeated filler or a constant smile. Do not imitate a real person."
	resolved.merge({"instructions":instructions,"speed":pace,"projection":projection,"intensity":intensity,"energy":energy,
		"mood":mood,"emotions":values,"immediate_reaction":reaction.duplicate(true),"intent":selected_intent,
		"expressive_supported":bool(Models.voice_capabilities(model).get("expressive",false)),"playback_pitch":1.0},true)
	resolved.delivery_key=JSON.stringify([str(person.get("id","")),identity.profile_version,identity.permanent_voice_id,
		model,mood,feelings,selected_intent,projection,snappedf(pace,.001),instructions]).sha256_text()
	return resolved

static func segments(person: Dictionary,model: String,text: String,priority: int,mood: String,affect: Dictionary,transitions: Array=[]) -> Array[Dictionary]:
	var output: Array[Dictionary]=[]
	var phrases:=Speech.pages(text,320)
	for index in phrases.size():
		var current_mood:=mood
		var current_affect:=affect.duplicate(true)
		var intent:=""
		for entry: Variant in transitions:
			if not entry is Dictionary or int(entry.get("phrase",-1))!=index:continue
			current_mood=str(entry.get("mood",mood))
			if entry.get("emotions") is Dictionary:current_affect.merge(entry.emotions,true)
			intent=str(entry.get("intent",""))
		var delivery:=build(person,model,priority,current_mood,current_affect,intent)
		output.append({"text":phrases[index],"phrase_index":index,"delivery":delivery})
	return output

static func _emotional_direction(values: Dictionary,anger: float,sorrow: float,fatigue: float,restraint: float,expression: float) -> String:
	var lines: Array[String]=[]
	if anger>=.85:
		lines.append("Extreme anger: strong, confrontational stress and pronounced tension; retain deliberate control rather than yelling." if restraint>=.7 else "Extreme anger: a raised, forceful voice with abrupt attacks and tense, irregular rhythm; genuinely sound furious rather than calmly reading anger.")
	elif anger>=.5:lines.append("Moderate anger: audible tension, forceful emphasis and abrupt rhythm.")
	elif anger>=.2:lines.append("Slight irritation: sharpen a few consonants, reduce warmth and leave shorter pauses; do not shout.")
	if sorrow>=.5:lines.append("Sadness or disappointment must override habitual excitement: lose the smile and bounce, reduce energy, slow the thought groups and let pauses carry the feeling. Keep the same pitch register and age.")
	elif sorrow>=.2:lines.append("Let disappointment modestly soften the delivery without exaggeration.")
	if fatigue>=.55:lines.append("Fatigue reduces breath energy and pace; avoid the usual brisk enthusiastic rhythm, but keep words audible.")
	if float(values.excitement)>=.5 and sorrow<.5:lines.append("Excitement brings lively changes of emphasis, shorter pauses and bursts of faster thought, shaped by this person's expressiveness.")
	if float(values.happiness)>=.45 and sorrow<.5:lines.append("Happiness adds warmth and melodic variety; it does not require a narrator's permanent smile.")
	if float(values.amusement)>=.4:lines.append("Amusement can produce a brief genuine chuckle or a smile in the timing; mixed anger may make it dry or disbelieving.")
	if float(values.boredom)>=.5 or float(values.get("disinterest",0.))>=.5:lines.append("Disinterest reduces variation and investment; detached is distinct from sad or robotic.")
	if float(values.embarrassment)>=.35:lines.append("Embarrassment brings a hesitant start, a short break in confidence, then a recovery.")
	if float(values.anxiety)>=.4 or float(values.stress)>=.55:lines.append("Tension tightens articulation and can interrupt the flow; preserve intelligibility and avoid caricature.")
	if float(values.get("confusion",0.))>=.4:lines.append("Confusion makes the rhythm tentative, with an honest thinking pause.")
	if float(values.get("carelessness",0.))>=.4:lines.append("Carelessness loosens enunciation and lets endings fall away slightly; keep the actual words intelligible.")
	if float(values.get("sarcasm",0.))>=.4:lines.append("Sarcasm uses restrained ironic stress and timing, not a new voice or repeated laughter.")
	if float(values.get("concern",0.))>=.4:lines.append("Concern steadies and softens the phrasing with attentive pauses; do not automatically become happy.")
	lines.append("Express these feelings subtly." if expression<.35 else "Allow recognizable emotional variation within the person's natural range.")
	return " ".join(lines)

static func _value(values: Dictionary,key: String,fallback: float) -> float:
	var value: Variant=values.get(key,fallback)
	return clampf(float(value),0.,1.) if (value is float or value is int) and is_finite(float(value)) else fallback
