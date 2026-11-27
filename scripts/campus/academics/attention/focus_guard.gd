extends Node
## The host owns the deadline and grades only the authenticated peer's active paper.
const GRACE_MS:=5000
var game: Node
var reports:={}
var local_out:=false
var local_assessment:=""
var alert_clock:=0.0
var application_focused:=true
var assessment_at_focus_loss:=""

func build(owner_game: Node) -> void:
 game=owner_game
 process_mode=Node.PROCESS_MODE_ALWAYS
 game.session.roster_changed.connect(_prune)
 game.session.leaving.connect(func():reports.clear();local_out=false;local_assessment="";assessment_at_focus_loss="")

func _notification(what: int) -> void:
 if what==NOTIFICATION_APPLICATION_FOCUS_OUT and application_focused:
  application_focused=false
  # A paper issued while the game is already in the background belongs to
  # the next focus cycle. Losing focus during the lecture cannot grade it.
  if is_instance_valid(game) and is_instance_valid(game.front) and game.front.in_game:
   assessment_at_focus_loss=_local_assessment(multiplayer.get_unique_id())
 elif what==NOTIFICATION_APPLICATION_FOCUS_IN:
  application_focused=true
  assessment_at_focus_loss=""

func _process(delta: float) -> void:
 if not is_instance_valid(game) or not is_instance_valid(game.front):return
 var peer:=multiplayer.get_unique_id()
 var assignment:=_local_assessment(peer) if game.front.in_game else ""
 var unfocused:=not application_focused and not assignment.is_empty() and assignment==assessment_at_focus_loss
 if unfocused and (not local_out or assignment!=local_assessment):
  local_out=true;local_assessment=assignment;alert_clock=0
  game.sfx.play("trip")
  game.ui.log_message("Return to the game within 5 seconds or this assessment receives 0%.")
  _report(false,assignment)
 elif local_out and (not unfocused or assignment!=local_assessment):
  _report(true,local_assessment)
  local_out=false;local_assessment=""
 if local_out:
  alert_clock+=delta
  if alert_clock>=1.0:alert_clock=0;game.sfx.play("trip")
 if multiplayer.is_server():
  for id in reports.keys():
   if Time.get_ticks_msec()>=int(reports[id].deadline):_expire(int(id))

func _local_assessment(peer: int) -> String:
 for paper in game.school.papers.values():
  if int(paper.get("owner",0))!=peer or not paper.get("mark",{}).is_empty():continue
  if bool(paper.get("lesson",true)) or int(paper.get("class_round",0))==0:continue
  if str(paper.get("project",{}).get("practice_scope",""))=="ungraded":continue
  var id:=str(paper.get("assessment_id",""))
  if not id.is_empty():return id
 return ""

func _report(focused: bool,id: String) -> void:
 if id.is_empty():return
 if multiplayer.is_server():_accept(multiplayer.get_unique_id(),focused,id)
 elif game.session.online:_send.rpc_id(1,focused,id)

@rpc("any_peer","call_remote","reliable",10)
func _send(focused: bool,id: String) -> void:
 if multiplayer.is_server():_accept(multiplayer.get_remote_sender_id(),focused,id)

func _accept(peer: int,focused: bool,id: String) -> void:
 if not game.session.roster.has(peer) or id.length()>64:return
 if focused:
  if reports.has(peer) and str(reports[peer].id)==id:
   if Time.get_ticks_msec()>=int(reports[peer].deadline):_expire(peer)
   else:reports.erase(peer)
 elif _server_paper(peer,id)!=null:
  if not reports.has(peer) or str(reports[peer].id)!=id:
   reports[peer]={"id":id,"deadline":Time.get_ticks_msec()+GRACE_MS}

func _server_paper(peer: int,id: String) -> Variant:
 for paper in game.school.papers.values():
  if int(paper.get("owner",0))!=peer or str(paper.get("assessment_id",""))!=id or not paper.get("mark",{}).is_empty():continue
  if not game.school._class_assessment(paper):continue
  var room:=str(paper.get("room_class",""))
  if not room.is_empty():
   var classroom: Dictionary=game.lecture_classes.classes.get(room,{})
   if str(classroom.get("id",""))!=id or classroom.get("phase","")!="assignment":continue
  elif game.school.phase!="assignment" or str(game.school.assessment_id)!=id:continue
  return paper
 return null

func _expire(peer: int) -> void:
 if not reports.has(peer):return
 var paper: Variant=_server_paper(peer,str(reports[peer].id))
 if paper==null:reports.erase(peer);return
 game.school._mark(paper,false,"Left the game window for five seconds during the assessment.")
 if not paper.get("mark",{}).is_empty():
  if not str(paper.get("room_class","")).is_empty():game.lecture_classes.paper_submitted(paper)
  reports.erase(peer);game.school.broadcast();game.school.checkpoint()
 else:
  # Preserve a failed grade-write attempt and retry without losing the report.
  reports[peer].deadline=Time.get_ticks_msec()+1000

func _prune() -> void:
 if not multiplayer.is_server():return
 for peer in reports.keys():
  if not game.session.roster.has(peer):reports.erase(peer)
