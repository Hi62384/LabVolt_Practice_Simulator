extends RefCounted
## Character traits also drive local pacing and participation, beyond prompt context.
const Roster=preload("res://scripts/campus/academics/faculty_roster.gd")
const Dialogue=preload("res://scripts/campus/academics/teacher_dialogue.gd")
const Models=preload("res://scripts/campus/ai/openai_models.gd")
const VOICES:=["coral","echo","nova","fable","ash","onyx","sage","shimmer","alloy","verse","ballad","cedar","marin"]
const FIRST:=["Sam","Riley","Jordan","Taylor","Casey","Morgan","Avery","Jamie","Charlie","Devon","Kai","Ellis"]
const LAST:=["Chen","Patel","Reyes","Singh","Park","Rivera","Kim","Bernard","Okafor","Nguyen","Santos","Haddad"]
const INTERESTS:=["music","running","games","photography","electronics","drawing","cooking","football","cycling","reading","robots","design"]

static func teacher(id: String) -> Dictionary:
	var person:=Roster.entry(id)
	var style: Dictionary=Dialogue.personalities().get(id,{})
	var seed_value:=posmod(id.hash(),32749)
	return {"id":id,"name":person.get("name","Instructor"),"role":"teacher","subjects":person.get("courses",[]),
		"style":person.get("style",style.get("description","Calm and clear")),
		"strictness":float(style.get("difficulty",.5)),"talk":float(style.get("talkativeness",.5)),
		"focus":float(style.get("focus",.5)),"teaching":float(style.get("teaching",.5)),
		"interest":INTERESTS[seed_value%INTERESTS.size()],"voice_slot":_voice_slot(id,seed_value)}

static func student(index: int) -> Dictionary:
	var seed_value:=posmod(("campus-student-%d"%index).hash(),32749)
	var curiosity:=float(seed_value%97)/96.
	var confidence:=float((seed_value/97)%97)/96.
	var interest: String=INTERESTS[seed_value%INTERESTS.size()]
	return {"id":"campus_student_%02d"%index,"name":FIRST[index%FIRST.size()]+" "+LAST[(index*7+3)%LAST.size()],
		"role":"student","interest":interest,"curiosity":curiosity,"confidence":confidence,
		"talk":clampf((curiosity+confidence)*.5,.1,.9),"focus":.3+curiosity*.6,
		"knowledge":.25+float(seed_value%51)/100.,"voice_slot":seed_value,
		"style":"Curious about "+interest if curiosity>.55 else "Quiet and practical"}

static func _voice_slot(id: String,seed_value: int) -> int:
	var index:=Roster.PEOPLE.keys().find(id)
	return index if index>=0 else seed_value

static func speech(person: Dictionary,model: String,priority: int) -> Dictionary:
	var available:=Models.speech_voices(model)
	var selectable:=VOICES.filter(func(candidate: String):return candidate in available)
	if selectable.is_empty():return {}
	var pace:=clampf(.84+float(person.talk)*.32,.80,1.18)
	var style:=str(person.style).left(120)
	var tone: String="Address a student clearly and warmly." if priority>=3 else "Teach at a natural pace with short pauses."
	return {"voice":selectable[int(person.voice_slot)%selectable.size()],"speed":pace,
		"instructions":"Deliver the line as this character. Style: "+style+". "+tone}
