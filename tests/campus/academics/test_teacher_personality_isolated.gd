extends SceneTree
const Dialogue=preload("res://scripts/campus/academics/teacher_dialogue.gd")
const Roster=preload("res://scripts/campus/academics/faculty_roster.gd")
const Brain=preload("res://scripts/campus/academics/teacher_brain.gd")
const Profiles=preload("res://scripts/campus/academics/class_character_profile.gd")
const Behavior=preload("res://scripts/campus/academics/character_behavior.gd")
const Affect=preload("res://scripts/campus/academics/character_affect.gd")
func _initialize() -> void:
 var data:=Dialogue.personalities()
 assert(data.size()==21 and Roster.PEOPLE.size()==21)
 var voices:={}
 for id in Roster.PEOPLE:
  assert(data.has(id))
  var person:=Profiles.teacher(id)
  var canonical:=Profiles.classroom(id)
  # The legacy four-number file seeds a profile; it must not silently override
  # authored traits in the actual classroom and dialogue adapters.
  for field in ["teaching","focus","difficulty","talkativeness","description","worldview"]:
   assert(data[id][field]==canonical[field],str(id)+":"+field)
  assert(is_equal_approx(float(data[id].teaching),float(person.traits.teaching_effort)))
  assert(is_equal_approx(float(data[id].difficulty),float(person.traits.strictness)))
  for intent in ["chat","help","question","apology","greeting","hazard"]:
   assert(not Dialogue.respond(id,intent,{"course":"ETY155"},0).is_empty(),str(id)+":"+intent)
  voices[person.style]=true
 assert(voices.size()==21)
 assert(Roster.PEOPLE.ms_lunch.courses.is_empty())
 var chad:=Profiles.teacher("chad")
 var bird:=Profiles.teacher("ms_bird_heart")
 var stanley:=Profiles.teacher("stanley")
 var jeff:=Profiles.teacher("jeff")
 assert(chad.traits.willingness_to_help<bird.traits.willingness_to_help)
 assert(chad.traits.arrogance>.8 and chad.traits.empathy<.3)
 assert(Profiles.teacher("mr_allu").traits.shyness>.7)
 assert(Profiles.teacher("josh_wildes").traits.willingness_to_disagree>.8)
 assert(Profiles.teacher("ms_clocks").traits.focus>.8)
 assert(Profiles.teacher("mr_stone").traits.discipline>.9)
 assert(Affect.dominant(Affect.baseline(stanley.traits),stanley.traits)=="tired")
 var help:="Can you explain the equation?"
 assert(Behavior.priorities(chad,help,{},"lesson").goal=="give_minimum")
 assert(Behavior.priorities(bird,help,{},"lesson").goal=="coach")
 assert(Behavior.priorities(jeff,"Tell me about your garage",{},"freeplay").goal=="share_personal_project")
 assert(data.jeff.difficulty>.9)
 # A teacher cannot build disciplinary or relationship evidence from an event
 # they did not perceive, even though the same personality would react if heard.
 var brain:=Brain.new()
 assert(brain.consider("jeff","student","class_message",.5,data.jeff,1000,.7,0.0).is_empty())
 assert(brain.incidents.is_empty() and brain.relationships.is_empty())
 var heard:=brain.consider("jeff","student","class_message",.5,data.jeff,2000,0.0,1.0)
 assert(not heard.is_empty() and heard.student=="student")
 assert(not str(brain.relationships).contains("private message"))
 print("TEACHER_PERSONALITY_ISOLATED PASS: authoritative classroom profiles, contrasting teaching choices and perception-gated consequences")
 quit(0)
