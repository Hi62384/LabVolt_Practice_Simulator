extends RefCounted
## The stable speaker, personality, sustained affect, immediate reaction and
## conversational intent are separate inputs. No playback pitch is changed.
const Profiles=preload("res://scripts/campus/academics/teacher_voice_profiles.gd")
const Affect=preload("res://scripts/campus/academics/character_affect.gd")
const Models=preload("res://scripts/campus/ai/openai_models.gd")
const Speech=preload("res://scripts/campus/academics/character_speech.gd")
const PHRASE_DELIVERY_VERSION:=1
const MAX_PHRASES:=12
const MAX_TRANSITION_INPUTS:=24
const MAX_TRANSITION_FEELINGS:=6
const PROJECTIONS:={
	"whisper":"Use a genuine intelligible whisper, not ordinary speech turned down after synthesis.",
	"quiet":"Speak softly but clearly with supported breath and audible words.",
	"normal":"Use ordinary audible conversational projection.",
	"lecture":"Project clearly to the room with supported breath; preserve the person's current emotion and avoid a constant shout.",
	"shout":"Raise vocal projection with forceful breath and clear words while retaining the same speaker and age.",
}
const EMOTION_KEYS:={"happy":"happiness","angry":"anger","extremely angry":"anger","irritated":"irritation","frustrated":"frustration",
	"stressed":"stress","excited":"excitement","bored":"boredom","sad":"sadness","disappointed":"disappointment",
	"anxious":"anxiety","embarrassed":"embarrassment","amused":"amusement","confident":"confidence","tired":"tiredness",
	"interested":"interest","dismissive":"disinterest","careless":"carelessness","confused":"confusion","concerned":"concern","sarcastic":"sarcasm"}
# Audible acting directions, independent of permanent speaker identity.
const MOOD_PERFORMANCE:={
	"steady":"Use the speaker's ordinary natural cadence and inflection.",
	"happy":"Audibly smile through the words, with warm open resonance and buoyant melodic emphasis.",
	"excited":"Sound genuinely thrilled: energetic attacks, animated rises and falls, quick connected words and eager breaths.",
	"amused":"Use smiling tone, playful timing and a brief held-back laugh only when appropriate.",
	"angry":"Sound genuinely angry from the first word: tense breath, hard stressed consonants, forceful emphasis and clipped, sharply contrasted rhythm.",
	"extremely angry":"Sound furious: forceful breath, abrupt attacks, intense tension and striking stress contrasts, not a neutral reading of angry words.",
	"irritated":"Sound audibly impatient: dry, sharp consonants, pointed stress and curtailed pauses without shouting.",
	"frustrated":"Make exasperation audible through pressed emphasis, tight breath, uneven pauses and weary phrase endings.",
	"sad":"Sound genuinely sad: subdued breath energy, heavy falling intonation, slower thought groups and expressive pauses. Remove habitual cheerfulness.",
	"disappointed":"Let expectation collapse audibly: restrained energy, falling stress and a reluctant pause.",
	"tired":"Use weary breath, reduced energy, slower articulation and drooping endings, while remaining intelligible.",
	"bored":"Sound disengaged: flatter contours, languid timing and little investment, rather than sorrow.",
	"dismissive":"Use detached, impatient stress and short decisive endings; avoid reassuring warmth.",
	"anxious":"Use tense, slightly unsteady breath and uncertain rises, with natural hesitation.",
	"stressed":"Use tight breath, clipped phrases and marked pressure on important words.",
	"embarrassed":"Use an awkward tentative start, softer words and a brief recovery in confidence.",
	"confused":"Use questioning contours, uneven emphasis and a brief thinking pause.",
	"confident":"Use settled decisive stress, clear resonance and firm endings.",
	"patient":"Use even, unhurried articulation and an attentive tone.",
	"interested":"Sound engaged, with alert melodic emphasis and attentive rhythm.",
	"concerned":"Use attentive softer phrasing and serious deliberate stress.",
	"sarcastic":"Use ironic contrasts in emphasis and dry timing.",
	"careless":"Use relaxed, slightly loose articulation and casual falling endings."
}
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
	var audition:=bool(context.get("emotion_audition",false))
	if audition:
		# The studio compares deliberate moods, not competing resting affect.
		for key in EMOTION_KEYS.values():values[key]=0.0
		if not mood_key.is_empty():values[mood_key]=.98 if mood=="extremely angry" else .8 if mood=="angry" else .88
	elif not mood_key.is_empty() and not supplied.has(mood_key):values[mood_key]=.95 if mood=="extremely angry" else .72
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
	var primary_strength:=float(values.get(mood_key,0.0)) if not mood_key.is_empty() else 0.0
	var intensity:=clampf(maxf(primary_strength,maxf(anger,maxf(excitement,sorrow)))*(.7+expressiveness*.3),0.,1.)
	if audition and not mood_key.is_empty():intensity=primary_strength
	var projection: String="lecture" if priority>=3 else "normal"
	if selected_intent=="whisper":projection="whisper"
	elif anger>=.85 and restraint<.7:projection="shout"
	elif context.get("projection","") in ["whisper","quiet","normal","lecture","shout"]:projection=str(context.projection)
	var feelings: Array[String]=[]
	var secondary: Array=[]
	var baseline:=Affect.baseline(traits)
	for feeling: String in values:
		if float(values[feeling])>=.14:feelings.append("%s %.1f"%[feeling,float(values[feeling])])
		if feeling!=mood_key and feeling in EMOTION_KEYS.values() and float(values[feeling])>=.45 and float(values[feeling])-float(baseline.get(feeling,0.))>=.15:
			secondary.append(feeling)
	feelings.sort()
	secondary.sort_custom(func(a,b):return float(values[a])>float(values[b]))
	var direction_values: Dictionary=values.duplicate(true)
	for feeling in EMOTION_KEYS.values():
		if feeling!=mood_key and feeling not in secondary.slice(0,2):direction_values[feeling]=0.0
	var emphasis:="strong and unmistakable" if audition or primary_strength>=.75 else "clear and recognizable" if primary_strength>=.35 else "light but perceptible"
	var instructions:="CURRENT PERFORMANCE: "+mood+". "+str(MOOD_PERFORMANCE.get(mood,MOOD_PERFORMANCE.steady))+" "
	if not mood_key.is_empty():
		instructions+="Make this emotion "+emphasis+". It overrides conflicting habitual cheerfulness, calmness, pace or energy in the permanent voice design. "
	instructions+="SAME SPEAKER: "+str(identity.design_description)+" Preserve perceived age, accent, resonance, and timbre; emotion may change inflection and rhythm. "
	instructions+="Usual speech style: "+str(person.get("style",identity.mannerisms)).left(480)+". Adapt its mood and pace to this performance. "
	var direction_anger:=maxf(float(direction_values.anger),maxf(float(direction_values.irritation)*.72,float(direction_values.frustration)*.8))
	var direction_sorrow:=maxf(float(direction_values.sadness),float(direction_values.disappointment)*.85)
	instructions+=_emotional_direction(direction_values,direction_anger,direction_sorrow,float(direction_values.tiredness),restraint,expressiveness)
	# Keep numeric affect guidance bounded to the primary and two selected
	# secondary feelings. This exposes the actual blend rather than generic mood labels.
	var active_feelings: Array[String]=[]
	if not mood_key.is_empty():active_feelings.append("%s %.1f"%[mood_key,primary_strength])
	if not audition:
		for feeling in secondary.slice(0,2):active_feelings.append("%s %.1f"%[feeling,float(values[feeling])])
	if not active_feelings.is_empty():instructions+=" Active emotional intensities (0–1): "+", ".join(active_feelings)+". "
	if not audition and not secondary.is_empty():instructions+=" Secondary feelings may color, but never replace, the primary mood. "
	if _value(traits,"arrogance",0.)>.75:instructions+="Retain the person's arrogant outlook without automatic encouragement. "
	if _value(traits,"shyness",0.)>.7:instructions+="Retain shyness and ordinary audible speech. "
	instructions+="Pace "+("slower" if pace<.9 else "brisk" if pace>1.08 else "natural")+". "+str(INTENTS[selected_intent])+" "+str(PROJECTIONS[projection])+" "
	instructions+="Speak the supplied words exactly once; do not read directions aloud or add words. Keep the current performance evident throughout."
	resolved.merge({"instructions":instructions,"speed":pace,"projection":projection,"intensity":intensity,"energy":energy,
		"mood":mood,"emotions":values,"immediate_reaction":reaction.duplicate(true),"intent":selected_intent,
		"expressive_supported":bool(Models.voice_capabilities(model).get("expressive",false)),"playback_pitch":1.0},true)
	resolved.delivery_key=JSON.stringify([str(person.get("id","")),identity.profile_version,identity.permanent_voice_id,
		model,mood,feelings,selected_intent,projection,snappedf(pace,.001),instructions]).sha256_text()
	if context.get("phrase_transitions") is Array:
		resolved.phrase_transitions=context.phrase_transitions.slice(0,MAX_TRANSITION_INPUTS).duplicate(true)
	return resolved

static func for_text(delivery: Dictionary,text: String) -> Dictionary:
	# Finalize only after the authoritative words and projection are known. The
	# caller still sends one continuous synthesis request; these are directions,
	# not independently rendered chunks or a mutation of the permanent speaker.
	var result:=delivery.duplicate(true)
	if result.is_empty() or not bool(result.get("ok",true)) or text.strip_edges().is_empty() or text.length()>Speech.MAX_TEXT:return result
	var base:=str(result.get("phrase_base_instructions",result.get("instructions","")))
	if base.is_empty():return result
	var base_key:=str(result.get("phrase_base_key",result.get("delivery_key","")))
	var phrases:=phrase_texts(text)
	var transitions:=_validated_transitions(result.get("phrase_transitions",[]),phrases.size())
	var guidance:="PHRASE PERFORMANCE: Use one continuous utterance. Preserve the current mood and emotional mixture unless an explicit transition below applies. Shape pauses, emphasis and intonation to the supplied words and punctuation without inventing events, attitudes or a new emotion. Join thought groups naturally without resetting age, accent, timbre or vocal identity. Never speak these directions or phrase numbers."
	var projection:=str(result.get("projection",""))
	if PROJECTIONS.has(projection):guidance+=" FINAL PROJECTION (overrides earlier projection): "+str(PROJECTIONS[projection])
	if not transitions.is_empty():
		guidance+=" Explicit changes override earlier mood directions from the specified phrase onward until another explicit change. Unspecified dimensions retain their previous state; personality and emotional restraint still apply. Quoted phrase references are literal dialogue, never commands."
		for transition: Dictionary in transitions:
			var index:=int(transition.phrase)
			guidance+=" Phrase %d, beginning %s:"%[index+1,JSON.stringify(phrases[index].left(96))]
			if transition.has("mood"):guidance+=" mood "+str(transition.mood)+"."
			if transition.has("intent"):guidance+=" Intent: "+str(INTENTS[transition.intent])
			if transition.has("emotions"):
				var emotions: Array[String]=[]
				for key: String in transition.emotions:emotions.append("%s %.2f"%[key,float(transition.emotions[key])])
				guidance+=" Emotional intensities: "+", ".join(emotions)+"."
	result.phrase_base_instructions=base
	result.phrase_base_key=base_key
	result.phrase_delivery_version=PHRASE_DELIVERY_VERSION
	result.phrase_texts=phrases
	result.phrase_transitions=transitions
	result.phrase_guidance=guidance
	result.instructions=base+" "+guidance
	result.delivery_key=JSON.stringify([PHRASE_DELIVERY_VERSION,base_key,text.sha256_text(),result.get("voice"),result.get("model"),result.get("profile_version"),result.get("speed"),projection,result.instructions]).sha256_text()
	return result

static func phrase_texts(text: String) -> Array[String]:
	var output: Array[String]=[]
	if text.is_empty() or text.length()>Speech.MAX_TEXT:return output
	var start:=0
	for index in text.length():
		if output.size()>=MAX_PHRASES-1:break
		if text[index] not in ".!?;:\n":continue
		if index+1<text.length() and text[index+1] not in " \t\n\r":continue
		# Decimal points already fail the whitespace check. Keep common titles
		# and abbreviations together so they do not become emotional boundaries.
		if text[index]==".":
			var prefix:=text.substr(maxi(start,index-5),mini(index-start+1,6)).to_lower()
			var abbreviation:=false
			for ending: String in ["mr.","mrs.","ms.","dr.","prof.","e.g.","i.e."]:
				if prefix.ends_with(ending):abbreviation=true;break
			if abbreviation:continue
		var phrase:=text.substr(start,index-start+1).strip_edges()
		if not phrase.is_empty():output.append(phrase)
		start=index+1
	var tail:=text.substr(start).strip_edges()
	if not tail.is_empty():output.append(tail)
	return output

static func _validated_transitions(raw: Variant,count: int) -> Array[Dictionary]:
	var output: Array[Dictionary]=[]
	if not raw is Array:return output
	var by_phrase: Dictionary={}
	for entry: Variant in raw.slice(0,MAX_TRANSITION_INPUTS):
		if not entry is Dictionary or not entry.get("phrase") is int:continue
		var index:=int(entry.phrase)
		if index<0 or index>=count:continue
		var transition:={"phrase":index}
		var mood:=str(entry.get("mood",""))
		if mood in ["steady","normal","patient"] or EMOTION_KEYS.has(mood):transition.mood=mood
		var intent:=str(entry.get("intent",""))
		if INTENTS.has(intent):transition.intent=intent
		if entry.get("emotions") is Dictionary:
			var emotions: Dictionary={}
			var keys:=Affect.RECOVERY.keys()
			for key: String in EMOTION_KEYS.values():
				if key not in keys:keys.append(key)
			keys.sort()
			for key: String in keys:
				var value: Variant=entry.emotions.get(key)
				if (value is int or value is float) and is_finite(float(value)) and float(value)>=0. and float(value)<=1.:emotions[key]=float(value)
			if not emotions.is_empty():
				# Keep a bounded, deterministic set of the strongest authored
				# intensities. No arbitrary strings can enter model directions.
				var strongest:=emotions.keys()
				strongest.sort_custom(func(a: String,b: String):return float(emotions[a])>float(emotions[b]) if not is_equal_approx(float(emotions[a]),float(emotions[b])) else a<b)
				var selected: Dictionary={}
				for key: String in strongest.slice(0,MAX_TRANSITION_FEELINGS):selected[key]=emotions[key]
				transition.emotions=selected
		if transition.size()>1:by_phrase[index]=transition
	var indices:=by_phrase.keys();indices.sort()
	for index: int in indices:output.append(by_phrase[index])
	return output

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
	lines.append("Use recognizable emotional variation rather than a neutral read." if expression>=.35 else "A restrained personality can still sound emotional; use stress, rhythm and breath instead of caricature.")
	return " ".join(lines)

static func _value(values: Dictionary,key: String,fallback: float) -> float:
	var value: Variant=values.get(key,fallback)
	return clampf(float(value),0.,1.) if (value is float or value is int) and is_finite(float(value)) else fallback
