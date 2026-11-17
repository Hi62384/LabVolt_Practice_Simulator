extends RefCounted
## Host-side question round used by the gated classroom event service.
const Bridge=preload("res://scripts/campus/academics/course_bridge.gd")
const MAX_STUDENTS:=32
const MAX_RESPONSE_BYTES:=4096
const PRIVATE_KEYS:=["answer","answers","answer_key","solution","solutions","rubric","verification","verified","seed","expected","correct","accepted","parameters","inputs","steps","reference","reference_result","reference_ac","correct_value","oracle","host_only","private"]
var bridge=Bridge.new()
var private_assignment: Dictionary={}
var public_question: Dictionary={}
var participants:={}
var present:={}
var submissions:={}
var submitted_at:={}
var attempts:={}
var hints_used:={}
var hint_counts:={}
var hint_limit:=1
var progress:={}
var declined:={}
var started_at:=0.0
var deadline:=0.0
var closed:=false
var event_id:=""
var question_index:=-1
var mode:="practice"

func prepare(host: bool,id: String,course: String,week: int,difficulty: int,seed_value: int,ends_at: float,identities: Array,recent_indices: Array=[]) -> bool:
 if not host or not private_assignment.is_empty() or id.is_empty() or not is_finite(ends_at):return false
 if week<1 or difficulty not in range(5) or identities.is_empty() or identities.size()>MAX_STUDENTS:return false
 for identity in identities:
  if not identity is String or identity.is_empty() or participants.has(identity):participants.clear();return false
  participants[identity]=true
 var weeks: Array=bridge.weeks(course,"lecture")
 if week>weeks.size():participants.clear();return false
 var generated: Dictionary=bridge.generate(course,week,"lecture",difficulty,seed_value)
 if generated.is_empty() or generated.has("error") or generated.get("questions",[]).is_empty():participants.clear();return false
 var safe: Dictionary=bridge.public_copy(generated,false)
 var public_questions: Variant=safe.get("questions",[])
 var private_questions: Variant=generated.get("questions",[])
 if not public_questions is Array or not private_questions is Array or public_questions.size()!=private_questions.size():participants.clear();return false
 var eligible: Array[int]=[]
 for i in public_questions.size():
  if public_questions[i] is Dictionary and private_questions[i] is Dictionary and supports_question(public_questions[i],course) and not has_private_fields(public_questions[i]):eligible.append(i)
 if eligible.is_empty():participants.clear();return false
 var fresh: Array[int]=[]
 for index in eligible:
  if index not in recent_indices:fresh.append(index)
 if not fresh.is_empty():eligible=fresh
 var selection:=RandomNumberGenerator.new();selection.seed=seed_value
 question_index=eligible[selection.randi_range(0,eligible.size()-1)]
 private_assignment=generated;public_question=public_questions[question_index].duplicate(true);present=participants.duplicate()
 event_id=id;deadline=ends_at;started_at=ends_at-30.0;return true

func focus_question(stage: String,recent_indices: Array=[]) -> void:
 if private_assignment.is_empty() or closed or stage.is_empty():return
 var focus_words:=_concept_words(stage)
 if focus_words.is_empty():return
 var safe: Dictionary=bridge.public_copy(private_assignment,false)
 var public_questions: Array=safe.get("questions",[])
 var private_questions: Array=private_assignment.get("questions",[])
 var best_score:=0
 var best_index:=-1
 for i in mini(public_questions.size(),private_questions.size()):
  if i in recent_indices or not public_questions[i] is Dictionary or not private_questions[i] is Dictionary:continue
  var question: Dictionary=public_questions[i]
  if not supports_question(question,str(private_assignment.get("course_id",""))) or has_private_fields(question):continue
  var score:=0
  var words:=_concept_words(str(question.get("prompt","")))
  for word in words:
   if focus_words.has(word):score+=1
  if score>best_score:best_score=score;best_index=i
 if best_index>=0:
  question_index=best_index
  public_question=public_questions[best_index].duplicate(true)

static func _concept_words(value: String) -> Dictionary:
 var normalized:=value.to_lower()
 for separator in [",",".",":",";","?","!","(",")","/","+","-","=","\n","\t"]:normalized=normalized.replace(separator," ")
 var stop:={"which":true,"there":true,"their":true,"these":true,"those":true,"using":true,"given":true,"value":true,"values":true,"about":true,"after":true,"before":true,"would":true,"could":true,"should":true,"first":true,"second":true,"teacher":true,"student":true,"explain":true,"calculate":true,"determine":true,"following":true}
 var words:={}
 for raw in normalized.split(" ",false):
  var word:=str(raw).strip_edges()
  if word.ends_with("s") and word.length()>5:word=word.left(word.length()-1)
  if word.length()>=4 and not stop.has(word):words[word]=true
 return words

static func supports_question(question: Dictionary,course: String) -> bool:
 var choices: Variant=question.get("options",[])
 if not choices is Array or choices.size()>16:return false
 if course not in ["MTH147","MTH255"] and choices.is_empty() and (question.get("input",null) is Dictionary or question.get("expected_form","") in ["graph","table","system","frequency_table"]):return false
 return true

static func has_private_fields(value: Variant) -> bool:
 if value is Dictionary:
  for key in value:
   if str(key).to_lower() in PRIVATE_KEYS or has_private_fields(value[key]):return true
 elif value is Array:
  for item in value:
   if has_private_fields(item):return true
 return false

func snapshot(identity: String,now: float) -> Dictionary:
 if private_assignment.is_empty() or not is_finite(now):return {}
 var data:={"event_id":event_id,"question":public_question.duplicate(true),"submitted":submissions.has(identity),"declined":declined.has(identity),"seconds_left":maxf(0.0,deadline-now),"can_submit":not closed and now<deadline and present.has(identity) and not submissions.has(identity) and not declined.has(identity)}
 if not identity.is_empty() and participants.has(identity):
  data.attempts=int(attempts.get(identity,0))
  data.can_hint=not closed and now<deadline and present.has(identity) and not submissions.has(identity) and not declined.has(identity) and int(hint_counts.get(identity,0))<hint_limit and mode in ["practice","board","group","teacher"]
  if hints_used.has(identity):data.hint=str(hints_used[identity])
  if progress.has(identity):data.progress=progress[identity].duplicate(true)
 return data

func request_hint(host: bool,identity: String,id: String,now: float) -> String:
 if not host or closed or not is_finite(now) or now>=deadline:return "closed"
 if id!=event_id or not present.has(identity):return "not_participating"
 if mode not in ["practice","board","group","teacher"]:return "unsupported"
 if submissions.has(identity):return "already_submitted"
 if declined.has(identity):return "declined"
 if int(hint_counts.get(identity,0))>=hint_limit:return "already_used"
 var choices: Variant=public_question.get("options",[])
 var form:=str(public_question.get("expected_form",""))
 var hint: String="Identify the given values and the quantity the question asks for. Check your units before submitting."
 if choices is Array and not choices.is_empty():hint="Compare each choice with the conditions in the question; eliminate choices that contradict a given value."
 elif form in ["graph","table","frequency_table"]:hint="Check that each entry represents the requested value and that the table or graph covers every given case."
 elif form in ["system","set"]:hint="Check each candidate against every condition in the question and include the complete solution set."
 if int(hint_counts.get(identity,0))==1:
  hint="Try a second method or substitute your candidate back into the stated conditions. Check the sign and units without guessing from the choices."
 # Hints use only the already public question format, never answer or rubric data.
 hints_used[identity]=hint
 hint_counts[identity]=int(hint_counts.get(identity,0))+1
 return "accepted"

func submit(host: bool,identity: String,id: String,response: Variant,now: float) -> String:
 if not host or closed or not is_finite(now) or now>=deadline:return "closed"
 if id!=event_id or not present.has(identity):return "not_participating"
 if submissions.has(identity):return "already_submitted"
 if declined.has(identity):return "declined"
 if var_to_bytes(response).size()>MAX_RESPONSE_BYTES:return "invalid"
 var marked: Dictionary=bridge.grade(private_assignment,{str(question_index):response})
 if marked.has("error") or marked.get("feedback",[]).size()<=question_index:return "invalid"
 attempts[identity]=int(attempts.get(identity,0))+1
 var feedback: Dictionary=marked.feedback[question_index]
 if mode in ["practice","board","group","teacher"] and not feedback.get("correct",false) and int(attempts[identity])<2 and now+5.0<deadline:
  var fraction:=clampf(float(feedback.get("fraction",0.0)),0.0,1.0)
  progress[identity]={"message":"Some parts match. Recheck the remaining conditions." if fraction>=.5 else "Review the given values and try once more.","partial":fraction>=.5,"attempts_left":1}
  return "retry"
 submissions[identity]=marked.feedback[question_index].duplicate(true)
 submitted_at[identity]=now
 return "accepted"

func decline(host: bool,identity: String,id: String,now: float) -> String:
 if not host or closed or not is_finite(now) or now>=deadline:return "closed"
 if mode!="practice":return "unsupported"
 if id!=event_id or not present.has(identity):return "not_participating"
 if submissions.has(identity):return "already_submitted"
 if declined.has(identity):return "already_declined"
 declined[identity]=true
 progress.erase(identity)
 return "accepted"

func finish(host: bool) -> bool:
 if not host or closed or private_assignment.is_empty():return false
 closed=true;return true

func result(identity: String) -> Dictionary:
 if not closed or not submissions.has(identity):return {}
 var feedback: Dictionary=submissions[identity].duplicate(true)
 if mode=="quiz":feedback.points=quiz_points(identity)
 return feedback

func reveal() -> Dictionary:
 if not closed or private_assignment.is_empty() or question_index<0:return {}
 var value: Variant=private_assignment.questions[question_index].get("answer")
 if var_to_bytes(value).size()>2048:return {}
 return {"answer":value}

func quiz_points(identity: String) -> int:
 if mode!="quiz" or not closed or not submissions.has(identity) or not submissions[identity].get("correct",false):return 0
 var duration:=maxf(1.0,deadline-started_at)
 var remaining:=clampf((deadline-float(submitted_at.get(identity,deadline)))/duration,0.0,1.0)
 return 100+roundi(50.0*remaining)

func quiz_totals() -> Dictionary:
 if not closed:return {}
 var answered:=submissions.size();var correct:=0;var total_points:=0
 for identity in submissions:
  if submissions[identity].get("correct",false):correct+=1
  total_points+=quiz_points(identity)
 return {"answered":answered,"correct":correct,"participants":participants.size(),"total_points":total_points}

func disconnected(host: bool,identity: String) -> bool:
 if not host or not present.has(identity):return false
 present.erase(identity);return true

func add_participant(host: bool,identity: String,now: float) -> bool:
 if not host or closed or not is_finite(now) or now>=deadline or identity.is_empty() or participants.has(identity) or participants.size()>=MAX_STUDENTS:return false
 participants[identity]=true;present[identity]=true;return true

func rejoin(host: bool,identity: String,now: float) -> bool:
 if not host or closed or not is_finite(now) or now>=deadline or not participants.has(identity):return false
 present[identity]=true;return true
