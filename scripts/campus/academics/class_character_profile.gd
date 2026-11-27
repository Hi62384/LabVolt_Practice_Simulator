extends RefCounted
## Character traits also drive local pacing and participation, beyond prompt context.
const Roster=preload("res://scripts/campus/academics/faculty_roster.gd")
const Models=preload("res://scripts/campus/ai/openai_models.gd")
const Personas=preload("res://scripts/campus/academics/character_personas.gd")
const Traits=preload("res://scripts/campus/academics/character_traits.gd")
const Worldview=preload("res://scripts/campus/academics/character_worldview.gd")
const DATA_PATH:="res://assets/campus/faculty/personalities.json"
static var classroom_baselines: Dictionary={}
const VOICES:=["coral","echo","nova","fable","ash","onyx","sage","shimmer","alloy","verse","ballad","cedar","marin"]
const FIRST:=["Sam","Riley","Jordan","Taylor","Casey","Morgan","Avery","Jamie","Charlie","Devon","Kai","Ellis"]
const NEW_FIRST:=["Aria","Noah","Leila","Ethan","Zara","Owen","Maya","Leo","Nadia","Theo","Imani","Luca","Priya","Finn","Elena","Amir","Sofia","Mateo","Nora","Isaac","Aisha","Felix","Sana","Reese"]
const NEW_LAST:=["Morales","Tanaka","Williams","Khan","Costa","Walker","Ali","Wilson","Mendoza","Ibrahim","Brown","Martin","Novak","Bennett","Torres","Singh","Dubois","Chen","Park","Okafor","Reyes","Nguyen","Cohen","Laurent"]
const LAST:=["Chen","Patel","Reyes","Singh","Park","Rivera","Kim","Bernard","Okafor","Nguyen","Santos","Haddad"]
const INTERESTS:=["music","running","games","photography","electronics","drawing","cooking","football","cycling","reading","robots","design"]

static func teacher(id: String) -> Dictionary:
	var person:=Roster.entry(id)
	if classroom_baselines.is_empty():
		var source: Variant=JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
		if source is Dictionary:classroom_baselines=source.get("teachers",{})
	var style: Dictionary=classroom_baselines.get(id,{})
	var seed_value:=posmod(id.hash(),32749)
	var profile:={"id":id,"name":person.get("name","Instructor"),"role":"teacher","subjects":person.get("courses",[]),
		"style":person.get("style",style.get("description","Calm and clear")),
		"strictness":_baseline(style,"difficulty"),"talk":_baseline(style,"talkativeness"),
		"focus":_baseline(style,"focus"),"teaching":_baseline(style,"teaching"),
		"description":str(style.get("description","")),
		"interest":INTERESTS[seed_value%INTERESTS.size()],"voice_slot":_voice_slot(id,seed_value)}
	profile.merge(Personas.teacher(id),true)
	profile.traits=Traits.expand(profile.traits,profile.talk,profile.traits.reasoning,profile.focus,
		lerpf(float(profile.traits.demonstrations),float(profile.teaching),.45),profile.strictness)
	profile.traits.merge(Traits.author_overrides(id),true)
	profile.activities=Traits.activity_preferences(profile.traits)
	if id.begins_with("generated_") and person.has("style"):profile.style=person.style
	profile.knowledge_domains={"math":.94 if "MTH147" in profile.subjects or "MTH255" in profile.subjects else .58,
		"electronics":.94 if profile.subjects.any(func(course):return course in ["ELM253","ETY155","DGS266"]) else .24,
		"gaming":.68 if id=="brian" else (.26 if id=="mr_bro" else .13),
		"fitness":.9 if id in ["chad","mr_bro","mr_hamstrings"] else .3,
		"programming":.78 if "DGS266" in profile.subjects else .32,"mechanics":.77 if id in ["bill","mr_phillips","jeff","mr_stone"] else .38,
		"science":.94 if id in ["bill_nye","dr_volts"] else .56,"business":.78 if id=="chad" else .36,
		"culture":.75 if id in ["mr_apple","mr_gusto","ms_bird_heart"] else .42,"everyday":.85 if id=="ms_lunch" else .66}
	profile.merge(Worldview.teacher(profile),true)
	profile.goals=[{"goal":profile.ambition,"priority":.9,"horizon":"long_term"},{"goal":"complete required teaching accurately","priority":profile.traits.teaching_effort,"horizon":"class"},{"goal":"protect personal time and interests","priority":profile.traits.selfishness,"horizon":"today"}]
	return profile

static func _baseline(values: Dictionary,key: String) -> float:
	return float(values[key]) if values.get(key)!=null else .5

static func classroom(id: String) -> Dictionary:
	var profile:=teacher(id)
	return {"teaching":profile.traits.teaching_effort,"focus":profile.traits.focus,"difficulty":profile.traits.strictness,
		"talkativeness":profile.traits.talkativeness,"description":profile.style,"worldview":profile.worldview}

static func student(index: int) -> Dictionary:
	index=maxi(0,index)
	var seed_value:=posmod(("campus-student-%d"%index).hash(),2147483647) if index>=12 else posmod(("campus-student-%d"%index).hash(),32749)
	var curiosity:=float(seed_value%97)/96.
	var confidence:=float((seed_value/97)%97)/96.
	var rng:=RandomNumberGenerator.new()
	rng.seed=seed_value
	var effort:=rng.randf_range(.15,.96)
	var focus:=rng.randf_range(.22,.91)
	var knowledge:=rng.randf_range(.28,.91)
	var talk:=rng.randf_range(.17,.9)
	var energy:=rng.randf_range(.23,.94)
	var warmth:=rng.randf_range(.25,.91)
	var interest: String=INTERESTS[seed_value%INTERESTS.size()]
	var profile:={"id":"campus_student_%02d"%index,"name":FIRST[index%FIRST.size()]+" "+LAST[(index*7+3)%LAST.size()],
		"role":"student","interest":interest,"curiosity":curiosity,"confidence":confidence,
		"talk":talk,"focus":focus,"knowledge":knowledge,"voice_slot":seed_value,
		"style":"Quiet in groups and talkative about "+interest if talk<.42 else ("Joins discussions easily and talks through ideas" if confidence>.6 else "Sociable at first, hesitates when challenged")}
	profile.merge(Personas.student(profile,rng),true)
	profile.traits.merge({"energy":energy,"warmth":warmth},true)
	profile.traits=Traits.expand(profile.traits,profile.talk,confidence,profile.focus,curiosity,.25)
	profile.traits.merge(Traits.independent_student_traits(rng),true)
	profile.traits.study_habits=effort
	profile.traits.academic_ability=knowledge
	profile.confidence=profile.traits.confidence
	if index>=12:
		profile.name=NEW_FIRST[posmod(seed_value,NEW_FIRST.size())]+" "+NEW_LAST[posmod(seed_value/NEW_FIRST.size(),NEW_LAST.size())]
	profile.program={"robots":"mechatronics","electronics":"electronics technology","games":"software development","music":"audio technology","drawing":"design","photography":"media production","cooking":"hospitality","running":"general studies","football":"business","cycling":"mechanical technology","reading":"liberal studies","design":"design"}.get(interest,"general studies")
	if index<12:profile.program="electronics technology" if interest in ["robots","electronics","games"] else "general studies"
	profile.education="studies "+str(profile.program)
	profile.style=("Reserved until comfortable" if float(profile.traits.shyness)>.6 else "Direct and socially relaxed")+(", willing to defend an opinion" if float(profile.traits.willingness_to_disagree)>.6 else ", considers objections before replying")+(", enjoys sharp humour" if float(profile.traits.humor)>.65 else ", usually plain-spoken")
	profile.appearance_seed=seed_value
	profile.strengths=["independent work" if float(profile.traits.independence)>.6 else "working with people","academic reasoning" if knowledge>.65 else "practical persistence"]
	profile.weaknesses=["impatience" if float(profile.traits.anger_sensitivity)>.65 else "hesitation under pressure","procrastination" if effort<.45 else "overpreparation"]
	profile.social_habits={"initiative":profile.traits.initiative,"comfort_with_strangers":1.-float(profile.traits.shyness),"seeks_rivalry":profile.traits.competitiveness}
	profile.activities=Traits.activity_preferences(profile.traits)
	profile.knowledge_domains={"math":profile.knowledge,"electronics":.8 if interest in ["electronics","robots"] else profile.knowledge*.8,
		"gaming":.83 if interest=="games" else .24,"fitness":.74 if interest in ["running","cycling","football"] else .27,
		"programming":.76 if interest in ["robots","games"] else .29,"mechanics":.73 if interest in ["robots","cycling"] else .24,
		"science":.66 if interest in ["robots","electronics"] else .44,"business":.65 if profile.program=="business" else .3,
		"culture":.76 if interest in ["music","drawing","reading","photography"] else .36,"everyday":.78 if interest=="cooking" else .59}
	profile.merge(Worldview.student(profile),true)
	profile.goals=[{"goal":profile.ambition,"priority":.85,"horizon":"term"},{"goal":"improve in "+str(profile.program),"priority":profile.traits.academic_motivation,"horizon":"class"},{"goal":"spend time with trusted friends","priority":profile.traits.sociability,"horizon":"today"},{"goal":"make time for "+str(profile.interest),"priority":.7,"horizon":"today"}]
	return profile

static func _voice_slot(id: String,seed_value: int) -> int:
	var index:=Roster.PEOPLE.keys().find(id)
	return index if index>=0 else seed_value

static func speech(person: Dictionary,model: String,priority: int,emotion := "steady",affect: Dictionary={}) -> Dictionary:
	var available:=Models.speech_voices(model)
	var selectable:=VOICES.filter(func(candidate: String):return candidate in available)
	if selectable.is_empty():return {}
	var pace:=clampf(.78+float(person.traits.speaking_pace)*.40+(.12 if emotion in ["irritated","excited"] else -.10 if emotion in ["tired","sad"] else 0.),.65,1.25)
	var style:=str(person.style)
	var tone: String={"irritated":"Clipped and firm, without shouting.","amused":"Light, playful energy.",
		"tired":"Speak slowly, with little energy.","embarrassed":"Hesitate slightly, then recover.",
		"stressed":"Keep it brisk and controlled.","interested":"Lean into the subject with genuine curiosity."}.get(emotion,
		"Sound "+emotion+" and keep the delivery natural." if emotion!="steady" else ("Speak clearly." if priority>=3 else "Use natural pauses."))
	var mixed: Array=[]
	for feeling in affect:
		if affect[feeling] is float or affect[feeling] is int:
			if float(affect[feeling])>.55:mixed.append(str(feeling)+" "+str(snappedf(float(affect[feeling]),.1)))
	if not mixed.is_empty():tone+=" Mixed feelings: "+", ".join(mixed)+". Preserve the character's way of expressing them."
	if float(person.traits.get("arrogance",0))>.75:tone+=" Confident, dismissive, unhurried about the other person's approval."
	if float(person.traits.get("shyness",0))>.7:tone+=" Slight hesitation and quieter delivery; avoid a theatrical caricature."
	return {"voice":selectable[int(person.voice_slot)%selectable.size()],"speed":pace,
		"instructions":"Deliver the line as this character. Style: "+style+". "+tone}
