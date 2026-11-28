extends Node
## Host-owned event service. Caller supplies lifecycle and room ownership.
const Round=preload("res://scripts/campus/academics/classroom_events/practice_round.gd")
const Demonstration=preload("res://scripts/campus/academics/classroom_events/demonstration_round.gd")
const MathDemonstration=preload("res://scripts/campus/academics/classroom_events/math_demonstration_round.gd")
const AcDemonstration=preload("res://scripts/campus/academics/classroom_events/ac_demonstration_round.gd")
const Mistake=preload("res://scripts/campus/academics/classroom_events/mistake_round.gd")
const Mystery=preload("res://scripts/campus/academics/classroom_events/mystery_round.gd")
const PassRound=preload("res://scripts/campus/academics/classroom_events/pass_round.gd")
const PhysicalRound=preload("res://scripts/campus/academics/classroom_events/physical_round.gd")
const Hands=preload("res://scripts/campus/academics/classroom_events/hand_queue.gd")
const SharedWork=preload("res://scripts/campus/academics/classroom_events/shared_work.gd")
const Authority=preload("res://scripts/campus/academics/classroom_events/participant_authority.gd")
const MAX_ROOMS:=4
const RESERVED_SECONDS:=45.0
const WRAP_RESERVE_SECONDS:=25.0
const ROUND_SECONDS:=30.0
const QUIZ_ROUNDS:=3
const RESULTS_SECONDS:=8.0
const Dialogue=preload("res://scripts/campus/academics/teacher_dialogue.gd")
const Lifecycle=preload("res://scripts/campus/academics/classroom_events/event_lifecycle.gd")
const REQUEST_LIMIT:=8
const REQUEST_WINDOW:=1.0
var game: Node
var rooms:={}
var request_budget:={}
var lifecycle:=Lifecycle.new()
signal view_received(room: String,view: Dictionary)
signal action_status_received(class_id: String,event_id: String,op: String,status: String)
signal round_completed(room: String,teacher: String,comment: String)
signal student_called(room: String,teacher: String,peer: int)
signal board_progress(room: String,teacher: String,comment: String)
signal participation_declined(room: String,teacher: String,comment: String)

func configure(owner: Node) -> void:game=owner

func can_mark_board(peer: int,room: String,now: float) -> bool:
 if not multiplayer.is_server() or not is_instance_valid(game) or not rooms.has(room):return false
 var state: Dictionary=rooms[room]
 if state.round.mode!="board" or state.round.closed or now<float(state.open_at) or now>=state.round.deadline:return false
 var activity: Dictionary=game.lecture_classes.classes.get(room,{})
 if activity.get("phase","")!="lesson" or str(activity.get("id",""))!=state.class_id or now>=float(activity.get("deadline",0.0)):return false
 var identity:=Authority.resolve(peer,game.session.roster,game.school.identities,activity,game.lecture_classes._inside(peer,room))
 return not identity.is_empty() and state.hands.selected==identity and state.hands.present.has(identity)

## A firm perceived warning may ask the same student to solve the current
## shared board question. It never creates a graded task or interrupts a round.
func call_disruptive_student(peer: int,room: String,teacher: String,now: float) -> bool:
 if not multiplayer.is_server() or not is_instance_valid(game) or not is_finite(now) or not rooms.has(room):return false
 var state: Dictionary=rooms[room]
 var round: RefCounted=state.round
 var activity: Dictionary=game.lecture_classes.classes.get(room,{})
 if round.mode!="board" or round.closed or now<float(state.open_at) or now>=round.deadline:return false
 if activity.get("phase","")!="lesson" or activity.get("id","")!=state.class_id or activity.get("teacher","")!=teacher or now>=float(activity.get("deadline",0.0)):return false
 var identity:=Authority.resolve(peer,game.session.roster,game.school.identities,activity,game.lecture_classes._inside(peer,room))
 if identity.is_empty() or not round.present.has(identity) or round.submissions.has(identity) or state.called.has(identity) or not state.hands.selected.is_empty():return false
 if not state.hands.call_student(true,round.event_id,identity):return false
 state.called[identity]=true;state.call_count=int(state.call_count)+1
 state.called_until=now+25.0;state.next_call=0.0
 state.board_called_at=now;state.board_strokes_at_call=int(state.board_strokes);state.board_notes_at_call=state.shared.entries.size();state.board_idle_prompted=false
 student_called.emit(room,teacher,peer)
 publish(room,now)
 return true

func _physical_board(room: String) -> Dictionary:
 var papers: Variant=game.school.get("papers")
 if papers is Dictionary:
  for paper in papers.values():
   if paper.get("classroom_board","")==room:return paper
 return {}

func board_stroke(peer: int,room: String,now: float) -> void:
 if not can_mark_board(peer,room,now):return
 var state: Dictionary=rooms[room]
 state.board_strokes=int(state.board_strokes)+1
 if int(state.board_strokes)==1 or int(state.board_strokes)==12:
  _react_to_board(room,state,now,"The selected student has made the first visible stroke on the board." if int(state.board_strokes)==1 else "The selected student has added several visible strokes to the board.")

func _react_to_board(room: String,state: Dictionary,now: float,comment: String) -> bool:
 if now<float(state.board_feedback_at):return false
 state.board_feedback_at=now+6.0
 var activity: Dictionary=game.lecture_classes.classes.get(room,{})
 board_progress.emit(room,str(activity.get("teacher","")),comment)
 return true

func start(room: String,now: float,recent_indices: Array=[],mode: String="practice",existing_series: Dictionary={},staged: bool=false,stage_focus: String="") -> bool:
 if not multiplayer.is_server() or not is_instance_valid(game) or not is_finite(now) or rooms.has(room) or rooms.size()>=MAX_ROOMS:return false
 if mode not in ["practice","quiz","board","group","demonstration","mistake","teacher","mystery","duel","pass","race","physical"]:return false
 var activity: Dictionary=game.lecture_classes.classes.get(room,{})
 var time_left:=float(activity.get("deadline",0))-now
 var required:=ROUND_SECONDS+RESULTS_SECONDS+WRAP_RESERVE_SECONDS if not existing_series.is_empty() else ROUND_SECONDS+RESERVED_SECONDS
 if activity.get("phase","")!="lesson" or time_left<required:return false
 if mode=="physical" and (activity.get("kind","")!="lab" or activity.get("course","")!="ELM253" or room!="ac_lab"):return false
 if mode!="physical" and activity.get("kind","")!="lecture":return false
 var members: Array=[]
 for identity in activity.get("students",{}):
  var student: Dictionary=activity.students[identity]
  var peer:=int(student.get("peer",0))
  if Authority.resolve(peer,game.session.roster,game.school.identities,activity,game.lecture_classes._inside(peer,room))==str(identity):members.append(identity)
 if members.is_empty():return false
 if mode=="quiz":
  for id in activity.get("classmates",{}):
   if activity.classmates[id].seated and members.size()<Round.MAX_STUDENTS:members.append(id)
 var bench: int=-1
 var lab: RefCounted=null
 if mode=="physical":
  if game.session.labs.is_empty():return false
  for identity in members:
   var assigned: int=int(activity.students[identity].get("bench",-1))
   if assigned>=0 and assigned<game.session.labs.size():bench=assigned;break
  if bench<0:return false
  lab=game.session.labs[bench]
 var id:=Crypto.new().generate_random_bytes(16).hex_encode()
 var resource:=["ac_station_%d"%bench] if mode=="physical" else (["projector","demo_bench"] if mode=="demonstration" else (["board"] if mode in ["board","mistake","teacher","mystery","duel","pass","race"] else (["projector"] if mode=="quiz" else ["worksheet"])))
 if not lifecycle.begin(id,room,resource):return false
 var practice: RefCounted=PhysicalRound.new() if mode=="physical" else ((MathDemonstration.new() if str(activity.course) in ["MTH147","MTH255"] else (AcDemonstration.new() if str(activity.course)=="ELM253" else Demonstration.new())) if mode=="demonstration" else (Mistake.new() if mode=="mistake" else (Mystery.new() if mode=="mystery" else (PassRound.new() if mode=="pass" else Round.new()))))
 var personality: Dictionary=Dialogue.personalities().get(str(activity.get("teacher","")),{})
 var competency:=clampf(float(personality.get("teaching",.5)),0.0,1.0)
 var focus:=clampf(float(personality.get("focus",.5)),0.0,1.0)
 # A busy room gives the teacher a little more time; focused, capable teachers solve sooner.
 var teacher_seconds:=clampf(25.0-10.0*competency-7.0*focus+minf(3.0,maxi(0,members.size()-1)*.5),8.0,24.0)
 var introduction_seconds := 3.0 if staged else 0.0
 var round_end := now + introduction_seconds + (teacher_seconds if mode == "teacher" else ROUND_SECONDS)
 var prepared: bool=practice.prepare_live(true,id,lab,bench,round_end,members) if mode=="physical" else practice.prepare(true,id,str(activity.course),int(activity.week),int(activity.difficulty),int(game.school.random.randi()),round_end,members,recent_indices)
 if not prepared:lifecycle.cancel(id);lifecycle.states.erase(id);return false
 if practice.get_script()==Round and not stage_focus.is_empty():practice.focus_question(stage_focus,recent_indices)
 practice.mode=mode
 practice.hint_limit=2 if float(personality.get("difficulty",.5))<.35 and mode in ["practice","board","group","teacher"] else 1
 var hands:=Hands.new()
 if not hands.begin(true,id,members):lifecycle.cancel(id);lifecycle.states.erase(id);return false
 var shared:=SharedWork.new()
 if mode in ["board","group"] and not shared.begin(mode,members):lifecycle.cancel(id);lifecycle.states.erase(id);return false
 if mode=="group":
  shared.set_question(str(practice.public_question.get("prompt","")))
  if members.size()==1:
   for classmate in activity.get("classmates",{}):
    var actor: Dictionary=activity.classmates[classmate]
    if actor.seated:
     shared.add_member(classmate)
     break
 lifecycle.advance(id,"preparing");lifecycle.advance(id,"announcing")
 if not staged:lifecycle.advance(id,"active")
 var target:=clampi(floori((time_left-10.0)/(ROUND_SECONDS+RESULTS_SECONDS)),1,QUIZ_ROUNDS) if mode=="quiz" else 1
 var series: Dictionary=existing_series if not existing_series.is_empty() else {"completed":0,"target":target,"scores":{},"streaks":{},"teams":{},"labels":{},"recent":[]}
 rooms[room]={"class_id":str(activity.id),"teacher":str(activity.get("teacher","")),"round":practice,"hands":hands,"shared":shared,"open_at":now+introduction_seconds,"next_call":now+clampf(14.0-6.0*float(personality.get("difficulty",.5)),7.0,14.0),"called_until":0.0,"call_count":0,"called":{},"closed_at":0.0,"series":series,"teacher_seconds":teacher_seconds,"duel_lock_at":now+7.0,"duel_locked":false,"duel_slots":[],"physical_bench":bench,"notice_until":0.0,"notice_cooldown":0.0,"board_strokes":0,"board_feedback_at":0.0,"board_called_at":0.0,"board_strokes_at_call":0,"board_notes_at_call":0,"board_idle_prompted":false}
 rooms[room].decline_reactions=0;rooms[room].last_decline_reaction=-100.0
 rooms[room].group_prompts={};rooms[room].group_notice_at={};rooms[room].group_status={}
 if mode=="board":rooms[room].next_call=now+4.0
 if mode=="board":
  var board:=_physical_board(room)
  if not board.is_empty():
   board.board_lines=[]
   board.board_notes=[]
   board.revision=int(board.revision)+1
   game.school.broadcast()
 publish(room,now)
 return true

func perform(peer: int,room: String,class_id: String,event_id: String,op: String,payload: Variant,now: float) -> String:
 if not multiplayer.is_server() or not is_instance_valid(game) or not game.session.roster.has(peer) or not rooms.has(room) or not is_finite(now):return "denied"
 if room.length()>64 or class_id.length()>64 or event_id.length()>64 or op.length()>16:return "invalid"
 if not allow_request(peer,now):return "rate_limited"
 var state: Dictionary=rooms[room]
 var activity: Dictionary=game.lecture_classes.classes.get(room,{})
 if activity.get("phase","")!="lesson" or str(activity.get("teacher",""))!=str(state.get("teacher","")) or now>=float(activity.get("deadline",0.0)):return "denied"
 if str(activity.get("id",""))!=class_id or state.class_id!=class_id:return "denied"
 # Apply the event identity to every action, including shared board notes.
 if state.round.event_id!=event_id:return "not_participating"
 if now<float(state.open_at):return "announcing"
 if state.round.closed or now>=state.round.deadline:return "denied"
 var identity:=Authority.resolve(peer,game.session.roster,game.school.identities,activity,game.lecture_classes._inside(peer,room))
 if identity.is_empty():return "denied"
 if not safe_payload(payload,0) or var_to_bytes(payload).size()>4096:return "invalid"
 match op:
  "submit":
   if state.round.mode=="duel" and (not state.duel_locked or identity not in state.duel_slots):return "not_selected"
   var result: String=state.round.submit(true,identity,event_id,payload,now)
   if result=="accepted":
    var outcome_id:=event_id+(":step:%d"%int(state.round.step_index) if state.round.mode=="pass" else "")
    _remember_human_outcome(activity,state.round,identity,outcome_id)
   if result=="accepted" and state.hands.selected==identity:
    state.hands.finish_turn(true,event_id);state.called_until=0.0;state.next_call=now+3.0
   return result
  "hint":
   if payload!=null:return "invalid"
   return state.round.request_hint(true,identity,event_id,now)
  "decline":
   if payload!=null:return "invalid"
   var result: String=state.round.decline(true,identity,event_id,now)
   if result=="accepted":
    if state.hands.selected==identity:
     state.hands.finish_turn(true,event_id);state.called_until=0.0;state.next_call=now+3.0
    else:state.hands.set_hand(true,event_id,identity,false)
    if state.round.mode=="practice" and int(state.decline_reactions)<2 and now-float(state.last_decline_reaction)>=8.0:
     state.decline_reactions=int(state.decline_reactions)+1;state.last_decline_reaction=now
     var teacher:=str(activity.get("teacher",""))
     participation_declined.emit(room,teacher,"A student declined this optional practice round. They may keep following the lesson without participating.")
   return result
  "hand":
   if not payload is bool:return "invalid"
   if state.round.mode=="duel" and state.duel_locked:return "closed"
   if not state.hands.set_hand(true,event_id,identity,payload):return "denied"
   if state.round.mode=="duel":return "accepted"
   if payload and float(state.next_call)<=0.0:
    var personality: Dictionary=Dialogue.personalities().get(str(activity.get("teacher","")),{})
    var talk: float=float(personality.get("talkativeness",.5)) if personality.get("talkativeness")!=null else .5
    state.next_call=now+lerpf(7.0,3.0,clampf(talk,0.0,1.0))
   return "accepted"
  "contribute":
   if state.round.mode not in ["board","group"]:return "denied"
   if state.round.mode=="board":
    if not can_mark_board(peer,room,now):return "not_selected"
    var board:=_physical_board(room)
    if not board.is_empty() and not game.school._near(peer,board.position):return "denied"
   var result: String=state.shared.contribute(identity,payload)
   if result=="accepted" and state.round.mode=="board":
    var board:=_physical_board(room)
    if not board.is_empty():
     board.board_notes=state.shared.view(identity).entries
     board.revision=int(board.revision)+1
     game.school.broadcast()
    _react_to_board(room,state,now,"Good. Explain how that idea helps solve the problem.")
   return result
  "vote":
   if state.round.mode!="group":return "denied"
   return state.shared.vote(identity,payload)
  "explain":
   if state.round.mode!="group":return "denied"
   var explained: String=state.shared.explain(identity,payload)
   if explained=="accepted":
    var team:=str(state.shared.groups.get(identity,""))
    for entry in state.shared.entries:
     if entry.group==team and activity.get("classmates",{}).has(entry.author):
      var collaborations: Dictionary=state.get_or_add("recorded_collaborations",{})
      var pair_key:=str(entry.author)+":"+identity
      if not collaborations.has(pair_key):
       collaborations[pair_key]=true
       game.faculty.brain.remember(entry.author,identity,"study",int(Time.get_unix_time_from_system()))
      break
    if not team.is_empty() and now>=float(state.group_notice_at.get(team,0.0)):
     state.group_notice_at[team]=now+8.0
     state.group_prompts[team]="A teammate added an explanation."
   return explained
 return "invalid"

func _remember_human_outcome(activity: Dictionary,round: RefCounted,identity: String,event_id: String) -> void:
 # The accepted host feedback is the sole source of correctness. In a live
 # prediction round it becomes available only after a valid measurement.
 var outcome: Dictionary=round.submissions.get(identity,{})
 if not outcome.get("correct") is bool:return
 if round.mode=="physical" and (not round.measurement_valid or not round.fault.is_empty()):return
 var faculty: Node=game.get("faculty")
 if is_instance_valid(faculty) and faculty.has_method("record_human_academic_outcome"):
  faculty.record_human_academic_outcome(activity,identity,"quiz",bool(outcome.correct),event_id)

func allow_request(peer: int,now: float) -> bool:
 var bucket: Dictionary=request_budget.get(peer,{"start":now,"count":0})
 if now<float(bucket.start) or now-float(bucket.start)>=REQUEST_WINDOW:bucket={"start":now,"count":0}
 if int(bucket.count)>=REQUEST_LIMIT:return false
 bucket.count=int(bucket.count)+1;request_budget[peer]=bucket
 return true

static func safe_payload(value: Variant,depth: int) -> bool:
 return _safe_payload(value,depth,[512])

static func _safe_payload(value: Variant,depth: int,budget: Array) -> bool:
 budget[0]=int(budget[0])-1
 if depth>12 or int(budget[0])<0:return false
 match typeof(value):
  TYPE_NIL,TYPE_BOOL,TYPE_INT:return true
  TYPE_FLOAT:return is_finite(value)
  TYPE_STRING:return value.length()<=4096
  TYPE_ARRAY:
   if value.size()>128:return false
   for item in value:
    if not _safe_payload(item,depth+1,budget):return false
   return true
  TYPE_DICTIONARY:
   if value.size()>128:return false
   for key in value:
    if not key is String or key.length()>128 or not _safe_payload(value[key],depth+1,budget):return false
   return true
 return false

func view(peer: int,room: String,now: float) -> Dictionary:
 if not multiplayer.is_server() or not rooms.has(room):return {}
 var state: Dictionary=rooms[room];var activity: Dictionary=game.lecture_classes.classes.get(room,{})
 if str(activity.get("id",""))!=state.class_id or str(activity.get("teacher",""))!=str(state.get("teacher","")) or activity.get("phase","")!="lesson" or not game.session.roster.has(peer) or not game.lecture_classes._inside(peer,room):return {}
 if str(game.school.identities.get(peer,"")).is_empty():return {}
 # A matching profile token alone does not make a peer the enrolled student.
 # Observers may see the question, never another student's state or feedback.
 var identity:=Authority.resolve(peer,game.session.roster,game.school.identities,activity,true)
 if now<float(state.open_at):
  return {"event_id":state.round.event_id,"class_id":state.class_id,"course":str(activity.get("course","")),"mode":state.round.mode,"stage":"announcing","closed":false,"question":{"prompt":"The teacher is preparing a short activity.","options":[]},"can_submit":false,"seconds_left":maxf(0.0,float(state.open_at)-now)}
 var snapshot: Dictionary=state.round.snapshot(identity,now)
 snapshot.class_id=state.class_id;snapshot.course=str(activity.get("course",""))
 snapshot.mode=state.round.mode
 snapshot.closed=state.round.closed
 snapshot.stage="active" if not state.round.closed else "results"
 if now<float(state.notice_until):snapshot.class_notice="The teacher is addressing a classroom interruption."
 if state.round.mode in ["board","group"]:snapshot.shared=state.shared.view(identity)
 if state.round.mode=="group" and not identity.is_empty() and not state.round.closed:
  var team:=str(state.shared.groups.get(identity,""))
  snapshot.team_prompt=str(state.group_prompts.get(team,""))
  if not team.is_empty():
   var team_members:=0;var team_answers:=0;var team_explanations:=0;var team_notes:=0
   for member in state.shared.groups:
    if str(state.shared.groups[member])!=team or not state.round.present.has(member):continue
    team_members+=1
    if state.round.submissions.has(member):team_answers+=1
    if state.shared.explanations.has(member):team_explanations+=1
   for entry in state.shared.entries:
    if str(entry.group)==team and str(entry.get("kind","note"))=="note":team_notes+=1
   snapshot.team_progress={"members":team_members,"notes":team_notes,"explanations":team_explanations,"submitted":team_answers}
 if state.round.mode=="group" and state.round.closed and not identity.is_empty():
  var team:=str(state.shared.groups.get(identity,""))
  if not team.is_empty():
   var members:=0;var answered:=0;var correct:=0
   for member in state.shared.groups:
    if str(state.shared.groups[member])!=team:continue
    members+=1
    if state.round.submissions.has(member):
     answered+=1
     if state.round.submissions[member].get("correct",false):correct+=1
   snapshot.group_result={"team":team,"members":members,"answered":answered,"correct":correct}
   var fastest: Dictionary=_fastest_group(state)
   if not fastest.is_empty():
    snapshot.group_result.fastest_team=str(fastest.team)
    snapshot.group_result.fastest_seconds=float(fastest.seconds)
 snapshot.hands={"count":state.hands.hands.size(),"raised":not identity.is_empty() and identity in state.hands.hands,"selected":not identity.is_empty() and state.hands.selected==identity,"called":not state.hands.selected.is_empty()}
 var raised_peers: Array[int]=[]
 for member in state.hands.hands:
  var hand_peer:=int(activity.get("students",{}).get(member,{}).get("peer",0))
  if hand_peer>0 and game.session.roster.has(hand_peer) and game.lecture_classes._inside(hand_peer,room):raised_peers.append(hand_peer)
 snapshot.raised_peers=raised_peers
 if state.round.mode=="duel":
  snapshot.duel={"locked":bool(state.duel_locked),"volunteers":state.hands.hands.size(),"competitors":state.duel_slots.size(),"selected":identity in state.duel_slots}
  snapshot.can_submit=bool(snapshot.can_submit) and identity in state.duel_slots
  if state.round.closed:
   var winner: String=""
   var best:=INF
   for member in state.duel_slots:
    if state.round.submissions.get(member,{}).get("correct",false) and float(state.round.submitted_at.get(member,INF))<best:
     winner=member;best=float(state.round.submitted_at[member])
   snapshot.duel.winner="Student %d"%(state.duel_slots.find(winner)+1) if not winner.is_empty() else "No correct answer"
   snapshot.duel.won=not identity.is_empty() and identity==winner
   snapshot.duel.points=100 if snapshot.duel.won else 0
 if state.round.mode=="race" and state.round.closed:
  var winner: String=""
  var best:=INF
  for member in state.round.submissions:
   if state.round.submissions[member].get("correct",false) and float(state.round.submitted_at.get(member,INF))<best:
    winner=member;best=float(state.round.submitted_at[member])
  var ordered: Array=state.round.participants.keys();ordered.sort()
  snapshot.race={"winner":"Student %d"%(ordered.find(winner)+1) if not winner.is_empty() else "No correct answer","won":not identity.is_empty() and winner==identity,"points":100 if not identity.is_empty() and winner==identity else 0}
 if state.round.closed and not identity.is_empty():snapshot.result=state.round.result(identity)
 if state.round.closed and state.round.mode=="quiz":snapshot.totals=state.round.quiz_totals()
 if state.round.closed and state.round.mode in ["quiz","demonstration","mistake","teacher","mystery","duel","pass","race","physical"]:snapshot.reveal=state.round.reveal()
 if state.round.closed:
  var personality: Dictionary=Dialogue.personalities().get(str(activity.get("teacher","")),{})
  var correct_count:=0
  var attempts: int=state.round.submissions.size()
  if state.round.mode=="pass":
   attempts=state.round.step_answers.size()
   for step in state.round.step_answers:
    if step.get("correct",false):correct_count+=1
  else:
   for member in state.round.submissions:
    if state.round.submissions[member].get("correct",false):correct_count+=1
  snapshot.teacher_comment=comment_for_round(state.round,correct_count,attempts,personality)
 if state.round.mode=="teacher" and state.round.closed:
  var beat: Array=[]
  for member in state.round.submissions:
   if state.round.submissions[member].get("correct",false):beat.append(member)
  snapshot.teacher_result={"students_beat_teacher":beat.size(),"teacher_seconds":float(state.teacher_seconds)}
 if state.round.mode=="quiz":
  var series: Dictionary=state.series
  snapshot.round_number=int(series.completed)+1 if not state.round.closed else int(series.completed)
  snapshot.rounds_total=int(series.get("target",1))
  if not identity.is_empty():
   snapshot.personal_points=int(series.scores.get(identity,0))
   snapshot.streak=int(series.streaks.get(identity,0))
  if state.round.closed:
   var leaders: Array=[]
   for member in series.scores:
    leaders.append({"name":str(series.labels.get(member,"Student")),"points":int(series.scores[member])})
   leaders.sort_custom(func(a: Dictionary,b: Dictionary):return int(a.points)>int(b.points))
   snapshot.leaderboard=leaders.slice(0,mini(3,leaders.size()))
   var teams:={"A":0,"B":0}
   for member in series.scores:teams[str(series.teams.get(member,"A"))]+=int(series.scores[member])
   if series.scores.size()>1:snapshot.team_scores=teams
 return snapshot

static func _fastest_group(state: Dictionary) -> Dictionary:
 var fastest:={}
 for member in state.round.submissions:
  if not bool(state.round.submissions[member].get("correct",false)):continue
  var team:=str(state.shared.groups.get(member,""))
  if team.is_empty():continue
  var submitted:=float(state.round.submitted_at.get(member,INF))
  if submitted<float(fastest.get(team,INF)):fastest[team]=submitted
 if fastest.size()<2:return {}
 var ordered:=fastest.keys();ordered.sort_custom(func(a,b):return float(fastest[a])<float(fastest[b]))
 if absf(float(fastest[ordered[0]])-float(fastest[ordered[1]]))<.001:return {}
 return {"team":str(ordered[0]),"seconds":maxf(0.0,float(fastest[ordered[0]])-float(state.open_at))}

## Authoritative result text for the practice UI and the model's observations.
## These are facts, not dialogue attributed to the teacher.
static func outcome_comment(mode: String,correct_count: int,attempts: int,_personality: Dictionary) -> String:
 if attempts==0:return "Practice ended without a submission."
 return "%d of %d %s were correct."%[correct_count,attempts,"submitted steps" if mode=="pass" else "submitted answers"]

static func comment_for_round(round: RefCounted,correct_count: int,attempts: int,personality: Dictionary) -> String:
 if str(round.get("mode"))=="physical":return physical_comment(round,personality)
 if str(round.get("mode"))=="mistake":
  var revealed: Dictionary=round.reveal()
  var answer:=str(revealed.get("answer",""))
  if answer.is_empty():return ""
  return "The deliberately incorrect board current was written incorrectly. The released circuit-solver result after the resistor change is %s. %s"%[answer,outcome_comment("mistake",correct_count,attempts,{})]
 return outcome_comment(str(round.get("mode")),correct_count,attempts,personality)

static func physical_comment(round: RefCounted,_personality: Dictionary={}) -> String:
 if not round.fault.is_empty():return "The station tripped. Switch off power and inspect the circuit before trying again."
 if not round.measurement_valid:return "No valid live station change was recorded; predictions cannot be compared."
 return "The AC station changed from %.2f V to %.2f V RMS."%[round.first_voltage,round.final_voltage]

## A perceived disruption only delays the next optional activity. It never
## changes an active answer window, attendance, or official assessment marks.
func note_disruption(room: String,teacher: String,now: float) -> bool:
 if not multiplayer.is_server() or not is_instance_valid(game) or not is_finite(now) or not rooms.has(room):return false
 var activity: Dictionary=game.lecture_classes.classes.get(room,{})
 var state: Dictionary=rooms[room]
 if str(activity.get("id",""))!=state.class_id or activity.get("phase","")!="lesson" or str(activity.get("teacher",""))!=teacher or state.round.closed or now<float(state.notice_cooldown):return false
 state.notice_until=now+6.0
 state.notice_cooldown=now+20.0
 publish(room,now)
 return true

func _cancel_room(room: String,state: Dictionary,now: float) -> void:
 lifecycle.cancel(state.round.event_id)
 lifecycle.states.erase(state.round.event_id)
 if state.round.mode in ["board","group"]:state.shared.finish()
 state.hands.close(true,state.round.event_id)
 if state.round.mode=="board":
  var board:=_physical_board(room)
  if not board.is_empty():
   board.board_lines=[];board.board_notes=[];board.revision=int(board.revision)+1
   game.school.broadcast()
 rooms.erase(room)
 publish(room,now)

func cancel_for_assessment(room: String,class_id: String,now: float) -> void:
 if not multiplayer.is_server() or not rooms.has(room):return
 var state: Dictionary=rooms[room]
 if str(state.class_id)!=class_id:return
 _cancel_room(room,state,now)

func tick(now: float) -> void:
 if not multiplayer.is_server() or not is_instance_valid(game):return
 for peer in request_budget.keys():
  if not game.session.roster.has(peer):request_budget.erase(peer)
 for room in rooms.keys():
  sync_roster(room,now)
  var state: Dictionary=rooms[room];var activity: Dictionary=game.lecture_classes.classes.get(room,{})
  if activity.get("phase","")!="lesson" or str(activity.get("id",""))!=state.class_id or str(activity.get("teacher",""))!=str(state.get("teacher","")) or now>=float(activity.get("deadline",0)):
   _cancel_room(room,state,now);continue
  if state.round.mode=="physical" and not state.round.closed:
   var bench: int=int(state.physical_bench)
   if bench<0 or bench>=game.session.labs.size():
    _cancel_room(room,state,now);continue
   state.round.observe_live(true,game.session.labs[bench])
  if now>=float(state.open_at) and lifecycle.states.get(state.round.event_id,{}).get("phase","")=="announcing":
   lifecycle.advance(state.round.event_id,"active");publish(room,now)
  if state.round.mode=="quiz" and not state.round.closed and now>=float(state.open_at):
   _classmate_quiz(room,state,activity,now)
  if state.round.mode=="group" and now>=float(state.open_at)+7.0 and now<state.round.deadline and not state.round.closed:
   if _classmate_group(room,state,activity,now):publish(room,now)
  if now>=state.round.deadline and not state.round.closed:
   if state.round.submissions.is_empty():
    lifecycle.advance(state.round.event_id,"timed_out")
   else:
    if lifecycle.states.get(state.round.event_id,{}).get("phase","")=="interrupted":lifecycle.advance(state.round.event_id,"active")
    lifecycle.advance(state.round.event_id,"resolving")
    lifecycle.advance(state.round.event_id,"complete")
   state.round.finish(true)
   if state.round.mode=="physical":
    for identity in state.round.submissions:_remember_human_outcome(activity,state.round,str(identity),str(state.round.event_id))
   if state.round.mode in ["board","group"]:state.shared.finish()
   if state.round.mode=="quiz":_award_quiz(state,activity)
   var correct_count:=0
   var attempts: int=state.round.submissions.size()
   if state.round.mode=="pass":
    attempts=state.round.step_answers.size()
    for step in state.round.step_answers:
     if step.get("correct",false):correct_count+=1
   else:
    for member in state.round.submissions:
     if state.round.submissions[member].get("correct",false):correct_count+=1
   var personality: Dictionary=Dialogue.personalities().get(str(activity.get("teacher","")),{})
   var comment: String=comment_for_round(state.round,correct_count,attempts,personality)
   if state.round.mode=="group" and (float(personality.get("talkativeness",.5))>=.65 or float(personality.get("difficulty",.5))>=.75):
    var fastest: Dictionary=_fastest_group(state)
    if not fastest.is_empty():comment+=" Team %s had the fastest correct submission; at least two teams found a valid answer."%str(fastest.team)
   round_completed.emit(room,str(activity.get("teacher","")),comment)
   state.closed_at=now
   state.hands.close(true,state.round.event_id)
   publish(room,now)
  elif state.round.closed and now>=float(state.closed_at)+(RESULTS_SECONDS if state.round.mode=="quiz" else 10.0):
   if state.round.mode=="quiz" and int(state.series.completed)<int(state.series.get("target",1)):
    var series: Dictionary=state.series
    var previous_id: String=state.round.event_id
    var recent: Array=series.recent.duplicate()
    recent.append(state.round.question_index)
    lifecycle.states.erase(previous_id)
    rooms.erase(room)
    series.recent=recent
    if not start(room,now,recent,"quiz",series):publish(room,now)
    continue
   lifecycle.states.erase(state.round.event_id)
   rooms.erase(room);publish(room,now)
  elif not state.round.closed:
   var changed:=false
   if state.round.mode=="group" and now>=float(state.open_at)+12.0:
    for team in state.shared.group_labels:
     var members:=0;var notes:=0;var answers:=0;var hints:=0;var retries:=0;var revisions:=0
     for member in state.shared.groups:
      if str(state.shared.groups[member])!=team or not state.round.present.has(member):continue
      members+=1
      if state.round.submissions.has(member):answers+=1
      if state.round.hints_used.has(member):hints+=1
      if int(state.round.attempts.get(member,0))>1:retries+=1
      if state.shared.votes.has(member) and not bool(state.shared.votes[member]):revisions+=1
     if members==0:continue
     for entry in state.shared.entries:
      if str(entry.group)==team:notes+=1
     var fingerprint: String="%d:%d:%d:%d:%d"%[notes,answers,hints,retries,revisions]
     if str(state.group_status.get(team,""))==fingerprint or now<float(state.group_notice_at.get(team,0.0)):continue
     state.group_status[team]=fingerprint;state.group_notice_at[team]=now+6.0
     if notes==0 and answers==0:state.group_prompts[team]="No team notes or submissions yet."
     elif revisions>0:state.group_prompts[team]="A teammate marked the proposal for revision."
     elif retries>0 or hints>0:state.group_prompts[team]="A hint or retry has been used during this round."
     elif notes>0 and answers==0:state.group_prompts[team]="Team notes have been started; no answers submitted yet."
     else:state.group_prompts[team]="One or more team members have submitted an answer."
   if state.round.mode=="board" and not state.hands.selected.is_empty() and not state.board_idle_prompted and now>=float(state.board_called_at)+10.0 and int(state.board_strokes)==int(state.board_strokes_at_call) and state.shared.entries.size()==int(state.board_notes_at_call):
    var comment: String="The selected student has been at the board for ten seconds without adding a visible stroke or a shared note."
    if _react_to_board(room,state,now,comment):state.board_idle_prompted=true
   if state.round.mode=="duel" and not state.duel_locked and now>=float(state.duel_lock_at):
    for member in state.hands.hands:
     if state.round.present.has(member):state.duel_slots.append(member)
     if state.duel_slots.size()==2:break
    if state.duel_slots.is_empty():
     _cancel_room(room,state,now);continue
    state.duel_locked=true
    changed=true
   if state.round.mode in ["duel","pass","physical"]:
    if changed:publish(room,now)
    continue
   if not state.hands.selected.is_empty() and float(state.called_until)>0.0 and now>=float(state.called_until):
    state.hands.finish_turn(true,state.round.event_id);state.called_until=0.0;state.next_call=now+3.0;changed=true
   if state.hands.selected.is_empty() and int(state.call_count)<2 and float(state.next_call)>0.0 and now>=float(state.next_call):
    if _call_student(room,state,activity,now):
     state.next_call=0.0;changed=true
    else:state.next_call=0.0
   if changed:publish(room,now)

func _call_student(room: String,state: Dictionary,activity: Dictionary,now: float) -> bool:
 var personality: Dictionary=Dialogue.personalities().get(str(activity.get("teacher","")),{})
 var difficulty:=clampf(float(personality.get("difficulty",.5)),0.0,1.0)
 var focus:=clampf(float(personality.get("focus",.5)),0.0,1.0)
 var candidates: Array=[]
 for identity in state.round.present:
  if not state.round.submissions.has(identity) and not state.round.declined.has(identity) and not state.called.has(identity):candidates.append(identity)
 candidates.sort()
 var sampled: String=str(candidates[posmod(state.round.event_id.hash(),candidates.size())]) if not candidates.is_empty() else ""
 var strict_call:=difficulty>=.75 and focus>=.65 and int(state.call_count)==0
 var picked: String=""
 if strict_call:
  var faculty: Node=game.get("faculty") as Node
  if is_instance_valid(faculty) and faculty.has_method("classroom_distracted"):
   for candidate in candidates:
    if bool(faculty.call("classroom_distracted",room,str(activity.get("id","")),str(candidate),now)):picked=str(candidate);break
  if picked.is_empty():picked=sampled
 elif not state.hands.hands.is_empty():
  for identity in state.hands.hands:
   if identity in candidates:picked=str(identity);break
 elif focus>=.55:picked=sampled
 if picked.is_empty() and state.round.mode=="board":picked=sampled
 if picked.is_empty() or not state.hands.call_student(true,state.round.event_id,picked):return false
 state.called[picked]=true;state.call_count=int(state.call_count)+1
 state.called_until=now+(25.0 if state.round.mode=="board" else 8.0)
 if state.round.mode=="board":
  state.board_called_at=now
  state.board_strokes_at_call=int(state.board_strokes)
  state.board_notes_at_call=state.shared.entries.size()
  state.board_idle_prompted=false
 var peer:=int(activity.get("students",{}).get(picked,{}).get("peer",0))
 if peer>0:student_called.emit(room,str(activity.get("teacher","")),peer)
 return true

func _award_quiz(state: Dictionary,activity: Dictionary) -> void:
 var series: Dictionary=state.series
 if int(series.completed)>=int(series.get("target",1)):return
 var members: Array=state.round.participants.keys()
 members.sort()
 for member in members:
  if not series.labels.has(member):
   var slot: int=series.labels.size()+1
   series.labels[member]="Student %d"%slot
   series.teams[member]="A" if slot%2==1 else "B"
  var correct: bool=bool(state.round.submissions.get(member,{}).get("correct",false))
  var streak:=int(series.streaks.get(member,0))+1 if correct else 0
  series.streaks[member]=streak
  series.scores[member]=int(series.scores.get(member,0))+state.round.quiz_points(member)+(10*maxi(0,streak-1) if correct else 0)
 series.completed=int(series.completed)+1
 if int(series.completed)>=int(series.get("target",1)):
  game.lecture_classes.classroom_students.record_quiz_rivals(activity,series.scores)

func _classmate_quiz(room: String,state: Dictionary,activity: Dictionary,now: float) -> void:
 var classmates: Dictionary=activity.get("classmates",{})
 var round: RefCounted=state.round
 for identity in round.participants:
  if not classmates.has(identity) or round.submissions.has(identity) or round.attempts.has(identity):continue
  var actor: Dictionary=classmates[identity]
  var profile: Dictionary=actor.profile
  var delay:=6.+float(posmod(hash([identity,round.event_id]),1400))/100.
  if now<float(state.open_at)+delay or now>=round.deadline:continue
  var proficiency: float=game.lecture_classes.classroom_students.proficiency(identity,activity.course,profile.knowledge)
  var outcome: String=round.simulate_quiz_answer(identity,proficiency,now)
  if outcome=="accepted":
   state.series.labels[identity]=profile.name
   state.series.teams[identity]="A" if posmod(hash(identity),2)==0 else "B"
   game.lecture_classes.classroom_students.record_practice(identity,activity.course,round.submissions[identity].get("correct",false),activity.week,activity,str(round.event_id),"quiz")

func _classmate_group(room: String,state: Dictionary,activity: Dictionary,now: float) -> bool:
 var client: Node=game.get("host_openai")
 var faculty: Node=game.get("faculty")
 if not is_instance_valid(client) or not is_instance_valid(faculty) or not faculty.has_method("generate_character_exchange"):return false
 if client.busy or not client.ready_for_class() or state.get("npc_group_pending",false) or now<float(state.get("npc_group_next",0.)):return false
 var shared: RefCounted=state.shared
 var attempted: Dictionary=state.get_or_add("npc_group_attempted",{})
 for identity in shared.members:
  if attempted.has(identity) or shared.entries.any(func(entry):return entry.author==identity):continue
  var actor: Dictionary=activity.get("classmates",{}).get(identity,{})
  if actor.is_empty() or not actor.seated or actor.get("removed_from_class",false) or actor.get("leaving_class",false):continue
  # NPC helpers belong to shared work, not the graded human participant list.
  if not shared.present.has(identity):continue
  var team: String=shared.groups[identity]
  if not state.round.present.keys().any(func(member):return member!=identity and shared.groups.get(member)==team):continue
  attempted[identity]=true
  state.npc_group_pending=true;state.npc_group_next=now+18.0
  _generate_group_contribution(room,state,activity,actor,str(identity))
  return true
 return false

func _generate_group_contribution(room: String,state: Dictionary,activity: Dictionary,actor: Dictionary,identity: String) -> void:
 var event_id:=str(state.round.event_id)
 var class_id:=str(activity.id)
 var now: float=game.lecture_classes._now()
 var shared: RefCounted=state.shared
 var released: Dictionary=state.round.snapshot(identity,now)
 var result: Dictionary=await game.faculty.generate_character_exchange(actor.profile,"group:"+event_id.sha256_text().left(24)+":"+str(shared.groups[identity]),activity,"",{
  "initiate":true,"defer_record":true,"intention":"You are participating in this practice group. Decide whether to contribute a short note in your own words, based on your knowledge, interest and the team's visible work. The note must be a complete thought of at most 160 characters. You may stay silent. Do not claim a correct result or a performed measurement without evidence.",
  "teaching_step":{"task":shared.task(identity),"question":released.get("question",{}),"team_notes":shared.view(identity)},
  "observations":{"current_activity":"group practice"},
  "_valid":func():return _group_contribution_current(room,state,activity,actor,identity,event_id,class_id)})
 state.npc_group_pending=false
 if result.is_empty() or result.get("cancelled",false):return
 var line:=str(result.get("line",""))
 var accepted:=false
 if _group_contribution_current(room,state,activity,actor,identity,event_id,class_id) and line.length()<=SharedWork.MAX_TEXT and not line.is_empty():
  accepted=shared.contribute(identity,line,str(actor.profile.name))=="accepted"
 if accepted:
  actor.action="discussing group work";actor.next=maxf(float(actor.get("next",0.)),game.lecture_classes._now()+5.0)
  publish(room,game.lecture_classes._now())
 game.faculty.character_interaction.record(result,accepted)

func _group_contribution_current(room: String,state: Dictionary,activity: Dictionary,actor: Dictionary,identity: String,event_id: String,class_id: String) -> bool:
 return rooms.has(room) and rooms[room]==state and str(state.round.event_id)==event_id and not state.round.closed and str(activity.id)==class_id and activity.phase=="lesson" and activity.get("classmates",{}).get(identity,{})==actor and state.shared.present.has(identity) and actor.get("seated",false) and not actor.get("removed_from_class",false) and not actor.get("leaving_class",false)

func sync_roster(room: String,now: float) -> void:
 if not multiplayer.is_server() or not rooms.has(room):return
 for old_peer in request_budget.keys():
  if not game.session.roster.has(old_peer):request_budget.erase(old_peer)
 var state: Dictionary=rooms[room];var activity: Dictionary=game.lecture_classes.classes.get(room,{})
 if activity.get("phase","")!="lesson" or str(activity.get("id",""))!=state.class_id or str(activity.get("teacher",""))!=str(state.get("teacher","")) or state.round.closed:return
 # Students signing in during a round may participate when there is time to read it.
 if now<float(state.round.deadline)-8.0:
  for identity in activity.students:
   if state.round.participants.has(identity):continue
   var peer:=int(activity.students[identity].get("peer",0))
   if Authority.resolve(peer,game.session.roster,game.school.identities,activity,game.lecture_classes._inside(peer,room))!=str(identity):continue
   if state.round.participants.size()>=Round.MAX_STUDENTS or state.hands.eligible.size()>=Hands.MAX_STUDENTS:break
   if state.round.add_participant(true,str(identity),now):
    state.hands.add_participant(true,state.round.event_id,str(identity))
    if state.round.mode in ["board","group"]:state.shared.add_member(str(identity))
 for identity in state.round.participants:
  if activity.get("classmates",{}).has(identity):continue
  var student: Dictionary=activity.students.get(identity,{})
  var previous:=int(student.get("peer",0))
  # Keep a connected enrollment stable even if another peer presents the same
  # profile token. Rebind a departed peer only when the mapping is unambiguous.
  var peer:=0
  if game.session.roster.has(previous) and str(game.school.identities.get(previous,""))==str(identity):
   peer=previous
  elif not game.session.roster.has(previous):
   var candidates: Array=[]
   for mapped_peer in game.school.identities:
    if game.session.roster.has(mapped_peer) and str(game.school.identities[mapped_peer])==str(identity):candidates.append(int(mapped_peer))
   if candidates.size()==1 and not student.get("done",false):
    peer=candidates[0];student.peer=peer
  var valid:=not Authority.resolve(peer,game.session.roster,game.school.identities,activity,peer>0 and game.lecture_classes._inside(peer,room)).is_empty()
  if valid and not state.round.present.has(identity):
   state.round.rejoin(true,identity,now);state.hands.rejoined(true,state.round.event_id,identity)
   if state.round.mode in ["board","group"]:state.shared.set_present(str(identity),true)
  elif not valid and state.round.present.has(identity):
   var was_selected: bool=state.hands.selected==identity
   state.round.disconnected(true,identity);state.hands.disconnected(true,identity)
   if state.round.mode in ["board","group"]:state.shared.set_present(str(identity),false)
   if was_selected:
    state.called_until=0.0
    state.next_call=now+3.0 if not state.hands.hands.is_empty() else 0.0
 if state.round.present.is_empty() and lifecycle.states.get(state.round.event_id,{}).get("phase","")=="active":lifecycle.advance(state.round.event_id,"interrupted")
 elif lifecycle.states.get(state.round.event_id,{}).get("phase","")=="interrupted":lifecycle.advance(state.round.event_id,"active")

@rpc("any_peer","call_remote","reliable")
func request(room: String,class_id: String,event_id: String,op: String,payload: Variant) -> void:
 if not multiplayer.is_server():return
 var peer:=multiplayer.get_remote_sender_id()
 var now:=Time.get_ticks_msec()/1000.0
 var status:=perform(peer,room,class_id,event_id,op,payload,now)
 action_status.rpc_id(peer,class_id,event_id,op,status)
 if status in ["accepted","retry"]:publish(room,now)
 else:receive.rpc_id(peer,room,view(peer,room,now))

@rpc("authority","call_remote","reliable")
func action_status(class_id: String,event_id: String,op: String,status: String) -> void:
 action_status_received.emit(class_id,event_id,op,status)

func publish(room: String,now: float) -> void:
 if not multiplayer.is_server():return
 for recipient in game.session.roster:
  var peer:=int(recipient);var snapshot:=view(peer,room,now)
  if peer==multiplayer.get_unique_id():view_received.emit(room,snapshot)
  elif game.session.online and game.session.peer_connected_now(peer):receive.rpc_id(peer,room,snapshot)

@rpc("authority","call_remote","reliable")
func receive(room: String,snapshot: Dictionary) -> void:
 view_received.emit(room,snapshot)
