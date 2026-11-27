extends RefCounted
## Host-side, reproducible ranking. The service still validates the chosen mode.
const MODES:=["practice","quiz","board","group","demonstration","mistake","teacher","mystery","duel","pass","race"]
const Characters=preload("res://scripts/campus/academics/class_character_profile.gd")
const Faculty=preload("res://scripts/campus/academics/faculty_roster.gd")

static func stage_focus(activity: Dictionary,now: float) -> String:
 var teaching: Dictionary=activity.get("teaching",{})
 var elapsed:=maxf(0.0,float(teaching.get("duration_seconds",420.0))-(float(activity.get("deadline",0.0))-now))
 for stage in teaching.get("stages",[]):
  if not stage is Dictionary:continue
  var beginning:=float(stage.get("start_seconds",0.0))
  if elapsed>=beginning and elapsed<beginning+float(stage.get("duration_seconds",stage.get("duration",0.0))):
   return (str(stage.get("title",""))+" "+str(stage.get("caption",stage.get("text","")))).left(500)
 return str(teaching.get("title",activity.get("title",""))).left(500)

static func lesson_focus(activity: Dictionary,now: float) -> String:
 var teaching: Dictionary=activity.get("teaching",{})
 var text:=str(teaching.get("title",""))
 for objective in teaching.get("objectives",[]):text+=" "+str(objective)
 var elapsed:=maxf(0.0,float(teaching.get("duration_seconds",420.0))-(float(activity.get("deadline",0.0))-now))
 for stage in teaching.get("stages",[]):
  if not stage is Dictionary:continue
  var beginning:=float(stage.get("start_seconds",0.0))
  if elapsed>=beginning and elapsed<beginning+float(stage.get("duration_seconds",stage.get("duration",0.0))):
   text+=" "+str(stage.get("title",""))+" "+str(stage.get("caption",stage.get("text","")))
   break
 return text.to_lower().left(1200)

static func rank(activity: Dictionary,personality: Dictionary,student_count: int,recent: Array,seed_value: int,now: float,has_board: bool=true) -> Array:
 var course:=str(activity.get("course",""))
 if activity.get("kind","")=="lab":return ["physical"] if course=="ELM253" and str(activity.get("room","ac_lab"))=="ac_lab" else []
 if student_count<1 or activity.get("kind","")!="lecture":return []
 var focus_text:=lesson_focus(activity,now)
 var electrical:=course in ["ETY155","ELM253"]
 var dc_demonstration:=course=="ETY155" and int(activity.get("week",0)) in range(1,7)
 var ac_demonstration:=course=="ELM253" and int(activity.get("week",0)) in [3,4,5]
 var math_function:=course in ["MTH147","MTH255"] and ("linear" in focus_text or "slope" in focus_text)
 var practical:=electrical and ("circuit" in focus_text or "resistor" in focus_text or "voltage" in focus_text or "current" in focus_text or "waveform" in focus_text)
 var explanation: bool="explain" in focus_text or "derive" in focus_text or "concept" in focus_text
 var teaching:=clampf(float(personality.get("teaching",.5)),0.0,1.0)
 var focus:=clampf(float(personality.get("focus",.5)),0.0,1.0)
 var difficulty:=clampf(float(personality.get("difficulty",.5)),0.0,1.0)
 var talk:=clampf(float(personality.get("talkativeness",.5)),0.0,1.0)
 var traits:=str(personality.get("description","")).to_lower()
 var weights:={
  "practice":1.0+.5*teaching,
  "quiz":.45+.6*difficulty+.25*focus,
  "board":.45+.8*teaching+(.35 if explanation else 0.0),
  "group":.3+.7*talk,
  "demonstration":.35+.8*teaching+(.65 if practical else 0.0),
  "mistake":.35+.6*focus+(.4 if practical else 0.0),
  "teacher":.25+.5*difficulty+.3*focus,
  "mystery":.25+.45*(1.0-focus)+(.3 if practical else 0.0),
  "duel":.25+.55*difficulty,
  "pass":.3+.55*talk+(.3 if explanation else 0.0),
  "race":.3+.55*difficulty,
 }
 if "concise" in traits:weights.practice*=1.4;weights.group*=.55
 if "stories" in traits:weights.group*=1.35;weights.pass*=1.25
 if "humor" in traits:weights.mystery*=1.5;weights.duel*=1.25
 if "strict" in traits:weights.teacher*=1.4;weights.quiz*=1.2
 if "tired" in traits or "senile" in traits:weights.quiz*=.55;weights.race*=.55
 var teacher:=str(activity.get("teacher",""))
 if Faculty.has(teacher):
  var person:=Characters.teacher(teacher)
  weights.demonstration*=lerpf(.35,2.15,float(person.activities.demonstration))
  weights.group*=lerpf(.55,1.6,float(person.activities.group))
  weights.mystery*=lerpf(.6,1.7,float(person.traits.creativity))
  weights.board*=lerpf(.55,1.45,float(person.activities.board))
  weights.practice*=lerpf(.7,1.65,float(person.activities.practice))
  weights.quiz*=lerpf(.65,1.6,float(person.activities.quiz))
 var choices: Array[String]=[]
 for mode in MODES:
  if mode=="quiz" and recent.is_empty():continue
  if mode=="demonstration" and not dc_demonstration and not ac_demonstration and not math_function:continue
  if mode in ["mistake","mystery","pass"] and not electrical:continue
  if mode in ["group","duel","race","quiz"] and student_count<2:continue
  if mode in ["board","demonstration","mistake","teacher","mystery","duel","pass","race"] and not has_board:continue
  if mode in recent:weights[mode]=float(weights[mode])*.12
  choices.append(mode)
 var rng:=RandomNumberGenerator.new();rng.seed=seed_value
 var ordered: Array[String]=[]
 while not choices.is_empty():
  var total:=0.0
  for mode in choices:total+=float(weights[mode])
  var sample:=rng.randf()*total
  var selected: String=str(choices.back())
  for mode in choices:
   sample-=float(weights[mode])
   if sample<=0.0:selected=mode;break
  ordered.append(selected);choices.erase(selected)
 return ordered
