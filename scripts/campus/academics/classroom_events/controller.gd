extends Node
## Integration remains gated until full multiplayer and visual validation.
const Candidate=preload("res://scripts/campus/academics/classroom_events/service.gd")
const CandidateView=preload("res://scripts/campus/academics/classroom_events/view.gd")
const Projector=preload("res://scripts/campus/academics/classroom_events/projector.gd")
const Dialogue=preload("res://scripts/campus/academics/teacher_dialogue.gd")
const Selector=preload("res://scripts/campus/academics/classroom_events/event_selector.gd")
const MAX_ACTIVITIES:=3
const WRAP_SECONDS:=25.0
const CORE_RESERVE_SECONDS:=75.0
const MAX_EVENT_SECONDS:=165.0
const EVENT_RESERVATION_SECONDS:=40.0
var enabled:=false
var game: Node
var service: Node
var presentation: Control
var presentation_layer: CanvasLayer
var projector: Node3D
var current_room: String=""
var attempted:={}
var disruption_cooldown:={}
var interruption_until:={}
var offtopic_until:={}
var surprise_shown:={}
var wrap_shown:={}
var requested_demonstrations:={}
var demonstration_cooldown:={}
var pending_board_challenges:={}
var board_challenge_cooldown:={}
var next_publish:=0.0
var owned_focus:=false
var raised_peers: Array[int]=[]

static func activity_gap(personality: Dictionary,student_count: int=1) -> float:
 var talk: float=float(personality.get("talkativeness",.5)) if personality.get("talkativeness")!=null else .5
 var focus: float=float(personality.get("focus",.5)) if personality.get("focus")!=null else .5
 var teaching:=clampf(float(personality.get("teaching",.5)),0.0,1.0)
 var difficulty:=clampf(float(personality.get("difficulty",.5)),0.0,1.0)
 return clampf(lerpf(120.0,80.0,clampf(talk,0.0,1.0))+(.5-clampf(focus,0.0,1.0))*20.0+(.5-teaching)*12.0+(difficulty-.5)*10.0+minf(10.0,maxi(0,student_count-1)*2.0),75.0,140.0)

static func quiz_affinity(personality: Dictionary) -> float:
 var focus:=clampf(float(personality.get("focus",.5)),0.0,1.0)
 var difficulty:=clampf(float(personality.get("difficulty",.5)),0.0,1.0)
 var talk:=clampf(float(personality.get("talkativeness",.5)),0.0,1.0)
 var teaching:=clampf(float(personality.get("teaching",.5)),0.0,1.0)
 return .35*focus+.25*difficulty+.2*talk+.2*(1.0-teaching)

static func choose_mode(personality: Dictionary,activity_number: int,student_count: int,course: String="") -> String:
 var teaching:=clampf(float(personality.get("teaching",.5)),0.0,1.0)
 var talk:=clampf(float(personality.get("talkativeness",.5)),0.0,1.0)
 var focus:=clampf(float(personality.get("focus",.5)),0.0,1.0)
 if activity_number==0 and teaching>=.62:return "demonstration" if course in ["ETY155","ELM253"] else "board"
 if activity_number==0 and course in ["ETY155","ELM253"] and student_count>=1 and teaching<.62:return "pass"
 if activity_number>=2 and teaching>=.7:return "teacher"
 if activity_number>=2 and course in ["ETY155","ELM253"] and focus<.65:return "mystery"
 if activity_number>=2 and student_count>=2 and talk<.55:return "duel"
 if activity_number>=1 and course in ["ETY155","ELM253"] and focus>=.65:return "mistake"
 if activity_number>=1 and student_count>=2 and talk>=.55:return "group"
 if activity_number>=1 and student_count>=2 and quiz_affinity(personality)>=.52:return "quiz"
 if activity_number>=1 and student_count>=2:return "race"
 return "practice"

func _present_count(room: String,activity: Dictionary) -> int:
 var count:=0
 for identity in activity.get("students",{}):
  var peer:=int(activity.students[identity].get("peer",0))
  if peer>0 and game.session.roster.has(peer) and str(game.school.identities.get(peer,""))==str(identity) and game.lecture_classes._inside(peer,room):count+=1
 for member in activity.get("classmates",{}).values():
  if member.get("seated",false):count+=1
 return count

## Host-only, bounded request from a perceived teacher-addressed message.
func request_demonstration(peer: int,room: String,teacher: String,now: float) -> bool:
 if not enabled or not multiplayer.is_server() or not is_instance_valid(game) or not is_finite(now):return false
 var activity: Dictionary=game.lecture_classes.classes.get(room,{})
 if activity.get("phase","")!="lesson" or str(activity.get("teacher",""))!=teacher or str(activity.get("kind",""))!="lecture":return false
 if str(activity.get("course","")) not in ["ETY155","ELM253","MTH147","MTH255"] or float(activity.get("deadline",0.0))-now<CORE_RESERVE_SECONDS:return false
 var class_id:=str(activity.get("id",""))
 var identity:=str(game.school.identities.get(peer,""))
 if class_id.is_empty() or identity.is_empty() or not game.session.roster.has(peer) or not game.lecture_classes._inside(peer,room):return false
 if int(activity.get("students",{}).get(identity,{}).get("peer",0))!=peer:return false
 var schedule: Dictionary=attempted.get(class_id,{"count":0})
 var key:=class_id+":"+identity
 if int(schedule.count)>=MAX_ACTIVITIES or float(schedule.get("event_seconds",0.0))+EVENT_RESERVATION_SECONDS>MAX_EVENT_SECONDS or requested_demonstrations.has(class_id) or now<float(demonstration_cooldown.get(key,0.0)):return false
 requested_demonstrations[class_id]={"room":room,"teacher":teacher,"identity":identity,"peer":peer,"until":now+55.0}
 demonstration_cooldown[key]=now+75.0
 return true

## A firm warning can turn into one shared, ungraded board question. The
## warned student gets the marker; classmates keep their own answer controls.
func request_board_challenge(peer: int,room: String,teacher: String,now: float) -> bool:
 if not enabled or not multiplayer.is_server() or not is_instance_valid(game) or not is_finite(now):return false
 var activity: Dictionary=game.lecture_classes.classes.get(room,{})
 if activity.get("phase","")!="lesson" or str(activity.get("teacher",""))!=teacher or str(activity.get("kind",""))!="lecture":return false
 var class_id:=str(activity.get("id",""))
 var identity:=str(game.school.identities.get(peer,""))
 if class_id.is_empty() or identity.is_empty() or not game.session.roster.has(peer) or not game.lecture_classes._inside(peer,room):return false
 if int(activity.get("students",{}).get(identity,{}).get("peer",0))!=peer or float(activity.get("deadline",0.0))-now<CORE_RESERVE_SECONDS:return false
 var key:=class_id+":"+identity
 if now<float(board_challenge_cooldown.get(key,0.0)):return false
 if service.rooms.has(room) and service.rooms[room].round.mode=="board":
  var called: bool=service.call_disruptive_student(peer,room,teacher,now)
  if called:board_challenge_cooldown[key]=now+90.0
  return called
 if not game.lecture_classes.signs.has(room) or not is_instance_valid(projector) or not is_instance_valid(projector.board):return false
 var schedule: Dictionary=attempted.get(class_id,{"count":0})
 if int(schedule.count)>=MAX_ACTIVITIES or float(schedule.get("event_seconds",0.0))+EVENT_RESERVATION_SECONDS>MAX_EVENT_SECONDS or pending_board_challenges.has(class_id):return false
 pending_board_challenges[class_id]={"room":room,"teacher":teacher,"identity":identity,"peer":peer,"until":now+55.0}
 board_challenge_cooldown[key]=now+90.0
 return true

func configure(owner: Node) -> void:
 game=owner;service=Candidate.new();service.name="ClassroomCandidate";add_child(service);service.configure(owner)
 service.view_received.connect(_received)
 service.action_status_received.connect(_status)
 service.round_completed.connect(_round_completed)
 service.student_called.connect(_student_called)
 service.board_progress.connect(_round_completed)
 service.participation_declined.connect(_round_completed)
 presentation_layer=CanvasLayer.new();presentation_layer.layer=25;add_child(presentation_layer)
 presentation=CandidateView.new();presentation_layer.add_child(presentation)
 presentation.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);presentation.mouse_filter=Control.MOUSE_FILTER_IGNORE
 presentation.action_requested.connect(_action)
 presentation.opened.connect(_open_input)
 presentation.closed.connect(_close_input)
 projector=Projector.new();add_child(projector);projector.configure(owner)

func step(now: float) -> void:
 if not enabled or not is_instance_valid(game) or not is_finite(now):return
 if multiplayer.is_server():
  # Drop departed students before any timed call chooses its next participant.
  for room in service.rooms.keys():service.sync_roster(room,now)
  service.tick(now)
  for room in game.lecture_classes.classes:
   var activity: Dictionary=game.lecture_classes.classes[room]
   if activity.get("phase","")!="lesson":
    var inactive_id:=str(activity.get("id",""))
    requested_demonstrations.erase(inactive_id)
    pending_board_challenges.erase(inactive_id)
    wrap_shown.erase(inactive_id)
    attempted.erase(inactive_id);disruption_cooldown.erase(inactive_id);interruption_until.erase(inactive_id);offtopic_until.erase(inactive_id);surprise_shown.erase(inactive_id)
    continue
   var class_id:=str(activity.get("id",""))
   if class_id.is_empty():continue
   if not attempted.has(class_id):attempted[class_id]={"count":0,"tries":0,"next":float(activity.get("deadline",0))-game.lecture_classes.lesson_duration(activity)*.5,"recent":[],"recent_modes":[],"last_step":now,"teaching_seconds":0.0,"event_seconds":0.0,"interruption_seconds":0.0,"offtopic_seconds":0.0}
   var schedule: Dictionary=attempted[class_id]
   if activity.get("ai_teaching",false):
    _step_adaptive_activity(room,activity,schedule,now)
    continue
   # Requests may create a partial schedule before the first timed step.
   for key in ["count","tries","next","last_step","teaching_seconds","event_seconds","interruption_seconds","offtopic_seconds"]:
    if not schedule.has(key):schedule[key]=now if key=="last_step" else 0.0
   if not schedule.has("recent"):schedule.recent=[]
   if not schedule.has("recent_modes"):schedule.recent_modes=[]
   var elapsed:=maxf(0.0,now-float(schedule.get("last_step",now)))
   schedule.last_step=now
   if activity.get("ai_waiting",false) and not service.rooms.has(room):continue
   if service.rooms.has(room):schedule.event_seconds=float(schedule.event_seconds)+elapsed
   elif now<float(interruption_until.get(class_id,0.0)):schedule.interruption_seconds=float(schedule.interruption_seconds)+elapsed
   elif now<float(offtopic_until.get(class_id,0.0)):schedule.offtopic_seconds=float(schedule.offtopic_seconds)+elapsed
   else:schedule.teaching_seconds=float(schedule.teaching_seconds)+elapsed
   var personality: Dictionary=Dialogue.personalities().get(str(activity.get("teacher","")),{})
   if not wrap_shown.has(class_id) and float(activity.get("deadline",0.0))-now<=WRAP_SECONDS and not service.rooms.has(room):
    wrap_shown[class_id]=true
    var faculty: Node=game.get("faculty") as Node
    if is_instance_valid(faculty):faculty.present_class_intention(room,str(activity.get("teacher","")),Dialogue.lesson_wrap_intention(personality,str(activity.get("course",""))))
   if pending_board_challenges.has(class_id):
    var warning: Dictionary=pending_board_challenges[class_id]
    var warning_valid: bool=now<=float(warning.until) and str(warning.teacher)==str(activity.get("teacher","")) and str(game.school.identities.get(int(warning.peer),""))==str(warning.identity) and int(activity.students.get(str(warning.identity),{}).get("peer",0))==int(warning.peer) and game.lecture_classes._inside(int(warning.peer),room)
    if not warning_valid or int(schedule.count)>=MAX_ACTIVITIES or float(schedule.event_seconds)+EVENT_RESERVATION_SECONDS>MAX_EVENT_SECONDS or float(activity.get("deadline",0.0))-now<CORE_RESERVE_SECONDS or not is_instance_valid(projector.board):pending_board_challenges.erase(class_id)
    elif not service.rooms.has(room):
     pending_board_challenges.erase(class_id)
     if service.start(room,now,schedule.recent,"board",{},false,Selector.stage_focus(activity,now)):
      service.call_disruptive_student(int(warning.peer),room,str(warning.teacher),now)
      schedule.count=int(schedule.count)+1
      schedule.recent_modes.append("board")
      if schedule.recent_modes.size()>2:schedule.recent_modes.pop_front()
      schedule.next=now+activity_gap(personality,service.rooms[room].round.participants.size())
      continue
   if requested_demonstrations.has(class_id):
    var request: Dictionary=requested_demonstrations[class_id]
    var valid: bool=now<=float(request.until) and str(request.teacher)==str(activity.get("teacher","")) and str(game.school.identities.get(int(request.peer),""))==str(request.identity) and int(activity.students.get(str(request.identity),{}).get("peer",0))==int(request.peer) and game.lecture_classes._inside(int(request.peer),room)
    if not valid or int(schedule.count)>=MAX_ACTIVITIES or float(schedule.event_seconds)+EVENT_RESERVATION_SECONDS>MAX_EVENT_SECONDS or float(activity.get("deadline",0.0))-now<CORE_RESERVE_SECONDS:requested_demonstrations.erase(class_id)
    elif not service.rooms.has(room):
     requested_demonstrations.erase(class_id)
     if service.start(room,now,schedule.recent,"demonstration",{},true,Selector.stage_focus(activity,now)):
      schedule.count=int(schedule.count)+1
      schedule.recent_modes.append("demonstration")
      if schedule.recent_modes.size()>2:schedule.recent_modes.pop_front()
      schedule.next=now+activity_gap(personality,service.rooms[room].round.participants.size())
      continue
   if not surprise_shown.has(class_id) and int(schedule.count)>=1 and not service.rooms.has(room) and float(activity.get("deadline",0))-now>100.0:
    surprise_shown[class_id]=true
    var seed:=class_id.hash() ^ str(activity.get("teacher","")).hash()
    var surprise_roll:=posmod(seed,100)
    var competitiveness:=clampf(float(personality.get("difficulty",.5))*.55+float(personality.get("talkativeness",.5))*.45,0.0,1.0)
    var present_count:=_present_count(room,activity)
    if surprise_roll<int(18.0*competitiveness) and activity.get("kind","")=="lecture" and present_count>1 and int(schedule.count)<MAX_ACTIVITIES and float(schedule.event_seconds)+EVENT_RESERVATION_SECONDS<=MAX_EVENT_SECONDS:
     var competition_modes: Array=Selector.rank(activity,personality,present_count,schedule.recent_modes,seed,now,is_instance_valid(projector.board))
     var competition: String="duel" if "duel" in competition_modes and posmod(seed,2)==0 else "race"
     if competition in competition_modes and service.start(room,now,schedule.recent,competition,{},true,Selector.stage_focus(activity,now)):
      schedule.count=int(schedule.count)+1
      schedule.recent_modes.append(competition)
      if schedule.recent_modes.size()>2:schedule.recent_modes.pop_front()
      if int(service.rooms[room].round.question_index)>=0:
       schedule.recent.append(service.rooms[room].round.question_index)
       if schedule.recent.size()>2:schedule.recent.pop_front()
      schedule.next=now+activity_gap(personality,service.rooms[room].round.participants.size())
    elif surprise_roll<35:
     var aside:=Dialogue.surprise_intention(personality,str(activity.get("course","")))
     var faculty: Node=game.get("faculty") as Node
     if not aside.is_empty() and is_instance_valid(faculty):faculty.present_class_intention(room,str(activity.get("teacher","")),aside);offtopic_until[class_id]=now+5.0
   if int(schedule.count)>=MAX_ACTIVITIES or float(schedule.event_seconds)+EVENT_RESERVATION_SECONDS>MAX_EVENT_SECONDS or now<float(schedule.next) or service.rooms.has(room):continue
   if int(schedule.tries)>=4:
    schedule.tries=0;schedule.next=now+45.0;continue
   if float(activity.get("deadline",0))-now<CORE_RESERVE_SECONDS:continue
   schedule.tries=int(schedule.tries)+1
   var available_board: bool=game.lecture_classes.signs.has(room) and is_instance_valid(projector.board)
   var seed_value:=class_id.hash() ^ int(schedule.count)*7919
   var modes: Array=Selector.rank(activity,personality,_present_count(room,activity),schedule.recent_modes,seed_value,now,available_board)
   var started: String=""
   var candidates: Array=modes.slice(0,3)
   if activity.get("kind","")=="lecture" and "practice" not in candidates:candidates.append("practice")
   for mode in candidates:
    var reservation:=115.0 if str(mode)=="quiz" else EVENT_RESERVATION_SECONDS
    if float(schedule.event_seconds)+reservation>MAX_EVENT_SECONDS:continue
    if service.start(room,now,schedule.recent,str(mode),{},true,Selector.stage_focus(activity,now)):
     started=str(mode);break
   if not started.is_empty():
    schedule.count=int(schedule.count)+1
    schedule.recent_modes.append(started)
    if schedule.recent_modes.size()>2:schedule.recent_modes.pop_front()
    if int(service.rooms[room].round.question_index)>=0:
     schedule.recent.append(service.rooms[room].round.question_index)
     if schedule.recent.size()>2:schedule.recent.pop_front()
    schedule.next=now+activity_gap(personality,service.rooms[room].round.participants.size())
   else:schedule.next=now+15.0
  # Newly started rounds also need the current enrollment before publication.
  for room in service.rooms.keys():service.sync_roster(room,now)
  if now>=next_publish:
   next_publish=now+1.0
   for room in service.rooms:service.publish(room,now)
  var live_ids:={}
  for activity in game.lecture_classes.classes.values():live_ids[str(activity.get("id",""))]=true
  for id in attempted.keys():
   if not live_ids.has(id):attempted.erase(id)
  for id in disruption_cooldown.keys():
   if not live_ids.has(id):disruption_cooldown.erase(id)
  for id in interruption_until.keys():
   if not live_ids.has(id):interruption_until.erase(id)
  for id in offtopic_until.keys():
   if not live_ids.has(id):offtopic_until.erase(id)
  for id in surprise_shown.keys():
   if not live_ids.has(id):surprise_shown.erase(id)
  for id in wrap_shown.keys():
   if not live_ids.has(id):wrap_shown.erase(id)
  for id in requested_demonstrations.keys():
   if not live_ids.has(id):requested_demonstrations.erase(id)
  for id in pending_board_challenges.keys():
   if not live_ids.has(id):pending_board_challenges.erase(id)
  for key in demonstration_cooldown.keys():
   if not live_ids.has(str(key).get_slice(":",0)):demonstration_cooldown.erase(key)
  for key in board_challenge_cooldown.keys():
   if not live_ids.has(str(key).get_slice(":",0)):board_challenge_cooldown.erase(key)

func _step_adaptive_activity(room: String,activity: Dictionary,schedule: Dictionary,now: float) -> void:
 if activity.get("ai_waiting",false) or service.rooms.has(room) or _present_count(room,activity)==0:return
 var board: Dictionary=game.lecture_classes._stage(activity)
 var phase:=str(board.get("teaching_step",{}).get("key",""))
 if phase not in ["example","practice"] or schedule.has(phase) or now<float(schedule.get("adaptive_retry_at",0.0)):return
 var modes: Array[String]=["practice"]
 if activity.get("kind","")=="lab":
  if activity.get("course","")!="ELM253" or phase!="practice":return
  modes=["physical"]
 elif phase=="example":modes=["demonstration","practice"]
 for mode in modes:
  if service.start(room,now,schedule.recent,mode,{},true,str(board.get("title",""))):
   schedule[phase]=true
   var index: int=service.rooms[room].round.question_index
   if index>=0:schedule.recent.append(index)
   return
 schedule.adaptive_retry_at=now+5.0

func on_teacher_disruption(room: String,teacher: String) -> void:
 if not enabled or not multiplayer.is_server() or not is_instance_valid(game):return
 var activity: Dictionary=game.lecture_classes.classes.get(room,{})
 if activity.get("phase","")!="lesson" or str(activity.get("teacher",""))!=teacher:return
 var class_id:=str(activity.get("id",""))
 var now:=Time.get_ticks_msec()/1000.0
 if class_id.is_empty() or now<float(disruption_cooldown.get(class_id,0.0)):return
 disruption_cooldown[class_id]=now+20.0
 interruption_until[class_id]=now+6.0
 if service.rooms.has(room):service.note_disruption(room,teacher,now)
 if attempted.has(class_id):
  var schedule: Dictionary=attempted[class_id]
  schedule.next=maxf(float(schedule.next),now+12.0)

func disable() -> void:
 if is_instance_valid(game):
  var avatars: Variant=game.get("avatars")
  if avatars is Dictionary:
   for peer in avatars:
    var avatar: Node3D=avatars[peer]
    if not is_instance_valid(avatar):continue
    var model:=avatar.get_node_or_null("CharacterModel") as Node3D
    if is_instance_valid(model):preload("res://scripts/avatar_model.gd").raise_hand(model,false,1.0)
 enabled=false
 raised_peers.clear()
 next_publish=0.0;attempted.clear();disruption_cooldown.clear();interruption_until.clear();offtopic_until.clear();surprise_shown.clear();wrap_shown.clear();requested_demonstrations.clear();demonstration_cooldown.clear();pending_board_challenges.clear();board_challenge_cooldown.clear();current_room=""
 if is_instance_valid(service):service.rooms.clear();service.lifecycle.clear();service.request_budget.clear()
 if is_instance_valid(presentation):presentation.apply({})
 if is_instance_valid(projector):projector.clear()

func begin_assessment(room: String,class_id: String,now: float) -> void:
 if not enabled or not multiplayer.is_server() or not is_instance_valid(service):return
 if is_instance_valid(game.get("smartphones")):game.smartphones.release_class_handoffs(room,class_id)
 service.cancel_for_assessment(room,class_id,now)
 requested_demonstrations.erase(class_id)
 pending_board_challenges.erase(class_id)
 wrap_shown.erase(class_id)

func _received(room: String,view: Dictionary) -> void:
 if not enabled:return
 if view.is_empty() and room!=current_room:return
 current_room=room if not view.is_empty() else ""
 raised_peers.clear()
 for peer in view.get("raised_peers",[]):
  if peer is int and peer>0 and raised_peers.size()<32:raised_peers.append(peer)
 presentation.apply(view)
 if is_instance_valid(projector):projector.apply(room,view)

func _process(delta: float) -> void:
 if not enabled or not is_instance_valid(game):return
 var avatars: Variant=game.get("avatars")
 if not avatars is Dictionary:return
 var room: String=game.campus.registry.locate(game.player.global_position)
 var lecture_hands: Array=game.lecture_classes.public_classes.get(room,{}).get("raised_peers",[])
 for peer in avatars:
  var avatar: Node3D=avatars[peer]
  if not is_instance_valid(avatar):continue
  var model:=avatar.get_node_or_null("CharacterModel") as Node3D
  if is_instance_valid(model):preload("res://scripts/avatar_model.gd").raise_hand(model,int(peer) in raised_peers or int(peer) in lecture_hands,delta)

func _action(class_id: String,event_id: String,op: String,payload: Variant) -> void:
 if not enabled or current_room.is_empty():return
 if multiplayer.is_server():
  var now:=Time.get_ticks_msec()/1000.0
  var status: String=service.perform(multiplayer.get_unique_id(),current_room,class_id,event_id,op,payload,now)
  if status not in ["accepted","retry"]:presentation.apply(service.view(multiplayer.get_unique_id(),current_room,now))
  _status(class_id,event_id,op,status)
  if status in ["accepted","retry"]:service.publish(current_room,now)
 else:service.request.rpc_id(1,current_room,class_id,event_id,op,payload)

func _status(class_id: String,event_id: String,op: String,status: String) -> void:
 if enabled:presentation.action_status(class_id,event_id,op,status)

func _round_completed(room: String,teacher: String,comment: String) -> void:
 if not enabled or not is_instance_valid(game):return
 var faculty: Node=game.get("faculty") as Node
 if not is_instance_valid(faculty) or not faculty.has_method("present_class_intention"):return
 var priority:=1
 var state: Dictionary=service.rooms.get(room,{}) if is_instance_valid(service) else {}
 var round: Variant=state.get("round")
 if round!=null and is_instance_valid(round) and round.closed and not round.submissions.is_empty():
  var any_correct:=false
  for submission in round.submissions.values():
   if bool(submission.get("correct",false)):any_correct=true;break
  if not any_correct:
   var traits: Dictionary=Dialogue.personalities().get(teacher,{})
   priority=3 if float(traits.get("difficulty",.5))>=.8 and float(traits.get("talkativeness",.5))>=.65 else 2
 faculty.present_class_intention(room,teacher,"React to the supplied verified practice event in your own manner. Preserve its released result; decide what you care to emphasize.",{"kind":"practice_event","description":comment},priority)

func _student_called(room: String,teacher: String,peer: int) -> void:
 if not enabled or not is_instance_valid(game):return
 var faculty: Node=game.get("faculty") as Node
 if is_instance_valid(faculty) and faculty.has_method("present_class_call"):faculty.present_class_call(room,teacher,peer)

func _unhandled_input(event: InputEvent) -> void:
 if not enabled or not event is InputEventKey or not event.pressed or event.echo or event.keycode!=KEY_F7:return
 if not is_instance_valid(game) or not game.front.in_game or not game.player.enabled:return
 if Input.mouse_mode!=Input.MOUSE_MODE_CAPTURED or game.front.screen.visible or game.ui.menu.visible or game.ui.sheet.visible:return
 if presentation.reopen():get_viewport().set_input_as_handled()

func _open_input() -> void:
 if not is_instance_valid(game) or not game.front.in_game or not game.player.enabled:return
 if game.front.screen.visible or game.ui.menu.visible or game.ui.sheet.visible:return
 owned_focus=true;game.release_mouse()

func _close_input() -> void:
 if not owned_focus:return
 owned_focus=false
 if is_instance_valid(game) and game.front.in_game and not game.front.screen.visible and not game.ui.menu.visible and not game.ui.sheet.visible:game.capture()
