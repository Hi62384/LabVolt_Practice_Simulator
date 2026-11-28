extends RefCounted
## Classroom intentions and official curriculum constraints; no canned persona speech.
const Characters=preload("res://scripts/campus/academics/class_character_profile.gd")
const Roster=preload("res://scripts/campus/academics/faculty_roster.gd")
static var _config: Dictionary={}
static func personalities() -> Dictionary:
 # Dossiers can finish in the background and host profiles can change. Never
 # keep an earlier character definition in a process-global cache.
 _config={}
 for id in Roster.all_people():_config[id]=Characters.classroom(str(id))
 return _config

## Deliberately limited keyword recognition, not a claim to understand free speech.
static func message_intent(message: String) -> String:
 var words:=PackedStringArray()
 var word:=""
 for c in message.to_lower().left(240):
  if (c >= "a" and c <= "z") or c=="'":word+=c
  elif not word.is_empty():words.append(word);word=""
 if not word.is_empty():words.append(word)
 for token in ["sorry","apologize","apologise"]:
  if token in words:return "apology"
 if ("shut" in words and "up" in words) or ("you" in words and ("stupid" in words or "idiot" in words)):return "rude"
 for token in ["help","stuck","confused"]:
  if token in words:return "help"
 if "circuit" in words and ("look" in words or "check" in words or "see" in words) and ("my" in words or "this" in words):return "show_work"
 if ("demonstrate" in words or "demonstration" in words or "experiment" in words) and ("you" in words or "show" in words or "could" in words or "can" in words):return "demonstration_request"
 if ("wrong" in words or "incorrect" in words or "mistake" in words) and ("your" in words or "board" in words):return "challenge"
 if "joke" in words or "funny" in words:return "joke"
 if "?" in message:return "question"
 for token in ["hello","hi","hey"]:
  if token in words:return "greeting"
 return "chat"

## Scheduling chooses an intention, never a prewritten character response.
static func surprise_intention(personality: Dictionary,course: String) -> String:
 if float(personality.get("talkativeness",.5))<.7 or float(personality.get("focus",.5))>=.65:return ""
 return "There is a brief pause during "+course+". Decide whether to share a relevant personal thought, joke, digression or simply continue. Use your own interests and current mood; do not invent an event in this class."

static func lesson_wrap_intention(_personality: Dictionary,course: String) -> String:
 return "The lesson in "+course+" is ending. Bring it to a close in your own manner and remind students that the upcoming assessment is individual. Use the released teaching material if a recap suits your priorities."

## Legacy entry points remain callable for older scene/test integrations. Their
## ordinary speech was removed; the coordinated character pipeline owns it.
static func surprise_comment(_personality: Dictionary,_course: String,_variant: int) -> String:return ""
static func overlap_comment(_personality: Dictionary) -> String:return ""
static func lesson_wrap(_personality: Dictionary,_course: String) -> String:return ""
static func assessment_intro(_personality: Dictionary,_course: String) -> String:return ""
static func respond(_id: String,intent: String,_context: Dictionary,_variant: int) -> String:
 # Safety-critical official instructions must not wait for a model request.
 return "Power is off after a circuit fault. Check the connections before trying again." if intent=="hazard" else ""

static func _guidance(context: Dictionary) -> String:
 var course:=str(context.get("course","")).to_upper()
 var phase:=str(context.get("phase",""))
 if phase=="assignment":return "For the assessment, explain your reasoning and check your work against the task instructions. I can discuss the method without giving you the answer."
 if context.get("round_mode","")=="physical":
  var state: Dictionary=context.get("physical_state",{})
  if state.get("fault",false):return "The station has tripped. Switch off power and inspect the setup before trying another measurement."
  if state.get("changed",false):return "The station has a valid measured change. Keep your prediction separate until the result is revealed, then compare the two values."
  return "Make one permitted station change, observe the live meter, and record whether you expect the RMS value to rise, fall, or stay close."
 if context.get("round_mode","")=="group":
  var progress: Dictionary=context.get("team_progress",{})
  if progress.is_empty():return "Use your own team's notes to compare methods. You can still submit your own answer."
  if int(progress.get("notes",0))==0:return "Start your team's notes with a known value or assumption. Ask a teammate to check it against the question."
  if int(progress.get("submitted",0))==0:return "Your team has a starting note. Have someone explain or challenge its next step, then submit your own answer."
  return "Your team has an answer in. Compare the method with the question and make your own submission before time expires."
 if context.get("round_mode","")=="board":return "Write the known quantities on the board, explain the next step, and ask the class to check your reasoning."
 var topic:=str(context.get("title","")).strip_edges().left(64)
 var prefix:="For %s, "%topic if not topic.is_empty() else ""
 match course:
  "ETY155":return prefix+"identify the supply rails, component values, and polarity before you power the circuit. Then measure one node at a time."
  "ELM253":return prefix+"trace the complete current path with power isolated. Check the meter connection and range before taking a reading."
  "DGS266":return prefix+"write the truth table first, then simplify the logic expression and test each input combination."
  "MTH147","MTH255":return prefix+"write the known values and the required result, choose the relevant formula, and check units after calculating."
  _:
   if phase=="lesson":return prefix+"compare your next step with the example on the board and ask about the point where they differ."
 return "Tell me which course and step you are working on so I can give a more specific hint."
