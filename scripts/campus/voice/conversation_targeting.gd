extends RefCounted
## Pure target scoring; caller supplies host-observed positions and visibility.
const RANGE := 5.5
const FOLLOWUP_RANGE := 7.0

static func select(candidates: Array, eye: Vector3, forward: Vector3, current: String="", humans: Array=[]) -> Dictionary:
 if not eye.is_finite() or not forward.is_finite() or forward.length_squared()<.5:return {}
 var best: Dictionary={}
 var second_score:=-INF
 var best_score:=-INF
 var human_dot:=-1.0
 var nearby_humans: Array[Dictionary]=[]
 for point in humans:
  if point is Vector3 and point.is_finite() and eye.distance_to(point)<RANGE:
   var facing:=forward.normalized().dot((point-eye).normalized())
   human_dot=maxf(human_dot,facing)
   nearby_humans.append({"gaze":facing,"distance":eye.distance_to(point)})
 for candidate in candidates:
  var position: Vector3=candidate.get("position",Vector3.INF)
  if not position.is_finite() or not candidate.get("visible",false):continue
  var id:=str(candidate.get("id",""))
  var distance:=eye.distance_to(position)
  var continuing:=id==current
  var invited:=bool(candidate.get("invited",false))
  if distance>(FOLLOWUP_RANGE if continuing else (16.0 if invited else RANGE)):continue
  var gaze:=forward.normalized().dot((position-eye).normalized())
  if gaze<(.1 if continuing else (.0 if invited else .62)):continue
  if human_dot>.94 and human_dot>gaze+.06 and not invited:continue
  # A person directly in front of an NPC has nearly the same gaze score.
  # A new cloud conversation must not begin merely because the distant NPC
  # is also in that cone. Existing addressed turns/invitations remain explicit.
  if not continuing and not invited:
   var addressing_human:=false
   for human: Dictionary in nearby_humans:
    if float(human.gaze)>.94 and float(human.gaze)>=gaze-.025 and float(human.distance)+.35<distance:
     addressing_human=true;break
   if addressing_human:continue
  var score:=gaze*3.0-distance*.16+(1.1 if continuing else 0.0)+(.9 if invited else 0.0)
  if score>best_score:
   second_score=best_score;best_score=score;best=candidate.duplicate()
  else:second_score=maxf(second_score,score)
 if best.is_empty():return {}
 if best_score-second_score<.15 and str(best.get("id",""))!=current and not best.get("invited",false):return {}
 best.reason="continuing conversation" if str(best.id)==current else ("teacher invitation" if best.get("invited",false) else "nearby, visible and facing")
 best.score=best_score
 return best

static func acknowledgement(text: String) -> bool:
 var clean:=text.to_lower().strip_edges()
 for mark in [".",",","!","?","—","-"]:clean=clean.replace(mark,"")
 return clean in ["yeah","yes","yep","okay","ok","right","uh huh","uhhuh","mhm","mmhmm","mm hmm","i see","got it","sure"]
