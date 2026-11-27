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
 for point in humans:
  if point is Vector3 and point.is_finite() and eye.distance_to(point)<RANGE:
   human_dot=maxf(human_dot,forward.normalized().dot((point-eye).normalized()))
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
