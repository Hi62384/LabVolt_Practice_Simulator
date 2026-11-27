extends RefCounted
## Character traits also drive local pacing and participation, beyond prompt context.
const Roster=preload("res://scripts/campus/academics/faculty_roster.gd")
const Models=preload("res://scripts/campus/ai/openai_models.gd")
const Personas=preload("res://scripts/campus/academics/character_personas.gd")
const Traits=preload("res://scripts/campus/academics/character_traits.gd")
const DATA_PATH:="res://assets/campus/faculty/personalities.json"
static var classroom_baselines: Dictionary={}
const VOICES:=["coral","echo","nova","fable","ash","onyx","sage","shimmer","alloy","verse","ballad","cedar","marin"]
const FIRST:=["Sam","Riley","Jordan","Taylor","Casey","Morgan","Avery","Jamie","Charlie","Devon","Kai","Ellis"]
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
	if person.has("style"):profile.style=person.style
	profile.knowledge_domains={"math":.94 if "MTH147" in profile.subjects or "MTH255" in profile.subjects else .58,
		"electronics":.94 if profile.subjects.any(func(course):return course in ["ELM253","ETY155","DGS266"]) else .24,
		"gaming":.68 if id=="brian" else (.26 if id=="mr_bro" else .13),
		"fitness":.9 if id in ["chad","mr_bro","mr_hamstrings"] else .3,
		"programming":.78 if "DGS266" in profile.subjects else .32,"mechanics":.77 if id in ["bill","mr_phillips","jeff","mr_stone"] else .38,
		"culture":.75 if id in ["mr_apple","mr_gusto","ms_bird_heart"] else .42,"everyday":.85 if id=="ms_lunch" else .66}
	return profile

static func _baseline(values: Dictionary,key: String) -> float:
	return float(values[key]) if values.get(key)!=null else .5

static func classroom(id: String) -> Dictionary:
	var profile:=teacher(id)
	return {"teaching":profile.traits.teaching_effort,"focus":profile.focus,"difficulty":profile.strictness,
		"talkativeness":profile.talk,"description":profile.description}

static func student(index: int) -> Dictionary:
	var seed_value:=posmod(("campus-student-%d"%index).hash(),32749)
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
	profile.traits.merge({"study_habits":effort,"academic_motivation":rng.randf_range(.16,.96),"initiative":rng.randf_range(.16,.92),
		"competitiveness":rng.randf_range(.08,.93),"cooperativeness":rng.randf_range(.24,.95),"ambition":rng.randf_range(.12,.94),
		"confrontation":rng.randf_range(.12,.9),"criticism_sensitivity":rng.randf_range(.15,.92),
		"self_control":rng.randf_range(.19,.92),"teasing":rng.randf_range(.14,.91)},true)
	profile.activities=Traits.activity_preferences(profile.traits)
	profile.knowledge_domains={"math":profile.knowledge,"electronics":.8 if interest in ["electronics","robots"] else profile.knowledge*.8,
		"gaming":.83 if interest=="games" else .24,"fitness":.74 if interest in ["running","cycling","football"] else .27,
		"programming":.76 if interest in ["robots","games"] else .29,"mechanics":.73 if interest in ["robots","cycling"] else .24,
		"culture":.76 if interest in ["music","drawing","reading","photography"] else .36,"everyday":.78 if interest=="cooking" else .59}
	return profile

static func _voice_slot(id: String,seed_value: int) -> int:
	var index:=Roster.PEOPLE.keys().find(id)
	return index if index>=0 else seed_value

static func speech(person: Dictionary,model: String,priority: int,emotion := "steady") -> Dictionary:
	var available:=Models.speech_voices(model)
	var selectable:=VOICES.filter(func(candidate: String):return candidate in available)
	if selectable.is_empty():return {}
	var pace:=clampf(.78+float(person.traits.speaking_pace)*.40+(.12 if emotion in ["irritated","excited"] else -.10 if emotion in ["tired","sad"] else 0.),.65,1.25)
	var style:=str(person.style).left(120)
	var tone: String={"irritated":"Clipped and firm, without shouting.","amused":"Light, playful energy.",
		"tired":"Speak slowly, with little energy.","embarrassed":"Hesitate slightly, then recover.",
		"stressed":"Keep it brisk and controlled.","interested":"Lean into the subject with genuine curiosity."}.get(emotion,
		"Sound "+emotion+" and keep the delivery natural." if emotion!="steady" else ("Speak clearly." if priority>=3 else "Use natural pauses."))
	return {"voice":selectable[int(person.voice_slot)%selectable.size()],"speed":pace,
		"instructions":"Deliver the line as this character. Style: "+style+". "+tone}
