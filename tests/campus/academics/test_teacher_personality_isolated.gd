extends SceneTree
const Dialogue=preload("res://scripts/campus/academics/teacher_dialogue.gd")
const Roster=preload("res://scripts/campus/academics/faculty_roster.gd")
const Brain=preload("res://scripts/campus/academics/teacher_brain.gd")
func _initialize() -> void:
 var expected={
  "bill_nye":[.65,.90,.75,.50],"mr_apple":[.30,.60,.40,.90],
  "ms_clocks":[.95,.90,.50,.40],"mr_phillips":[.75,.95,.40,.65],
  "mr_gusto":[.85,.90,.70,.85],"mr_hamstrings":[.30,.20,.70,.95],
  "mr_allu":[.20,.10,.20,.10],"bill":[.40,1.00,.90,.50],
  "chad":[.10,.10,.10,.90],"brian":[.30,.95,.50,.30],
  "ms_bird_heart":[.20,.50,.80,.90],"dr_volts":[.80,.40,1.00,1.00],
  "stanley":[.05,.05,.40,.10],"ms_rivera":[.05,.05,.10,.40],
  "mr_blake":[.70,.20,.50,.90],"mr_stone":[.70,1.00,1.00,.60],
  "josh_wildes":[.10,.20,.90,.40],"bradley":[.70,.50,.50,.60],
  "jeff":[1.00,1.00,1.00,.30],"mr_bro":[.30,.10,.30,.90]}
 var data:=Dialogue.personalities()
 assert(data.size()==21 and Roster.PEOPLE.size()==21)
 for id in expected:
  assert(data.has(id) and Roster.PEOPLE.has(id))
  var index:=0
  for field in ["teaching","focus","difficulty","talkativeness"]:
   assert(is_equal_approx(float(data[id][field]),float(expected[id][index])))
   index+=1
  for intent in ["chat","help","question","apology","greeting","hazard"]:
   assert(not Dialogue.respond(id,intent,{"course":"ETY155"},0).is_empty())
 for field in ["teaching","focus","difficulty","talkativeness"]:assert(data.ms_lunch[field]==null)
 assert(Roster.PEOPLE.ms_lunch.courses.is_empty())
 var brain:=Brain.new()
 assert(brain.consider("jeff","student","class_message",.5,data.jeff,1000,.7,0.0).is_empty())
 assert(brain.incidents.is_empty() and brain.relationships.is_empty())
 var heard:=brain.consider("jeff","student","class_message",.5,data.jeff,2000,0.0,1.0)
 assert(not heard.is_empty() and heard.student=="student")
 assert(not str(brain.relationships).contains("private message"))
 print("TEACHER_PERSONALITY_ISOLATED PASS")
 quit(0)
