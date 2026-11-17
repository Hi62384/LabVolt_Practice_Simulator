extends SceneTree
const Candidate=preload("res://scripts/campus/academics/classroom_events/service.gd")
class Session:
 var roster:={1:{},2:{},3:{}}
 var online:=false
 func peer_connected_now(_peer: int) -> bool:return false
class School:
 var identities:={1:"alice",2:"bob",3:"observer"}
 var random:=RandomNumberGenerator.new()
class Classes:
 var classes:={"room":{"id":"class-1","phase":"lesson","kind":"lecture","deadline":200.0,"course":"DGS266","week":3,"difficulty":0,"students":{"alice":{"peer":1,"done":false},"bob":{"peer":2,"done":false}}}}
 var present:={1:true,2:true,3:true}
 func _inside(peer: int,_room: String) -> bool:return present.get(peer,false)
class Game:
 extends Node
 var session:=Session.new()
 var school:=School.new()
 var lecture_classes:=Classes.new()
func _initialize() -> void:call_deferred("run")
func run() -> void:
 var game:=Game.new();root.add_child(game)
 var candidate:=Candidate.new();root.add_child(candidate);candidate.configure(game)
 assert(candidate.start("room",100.0,[],"quiz"))
 var id: String=candidate.rooms.room.round.event_id
 assert(candidate.lifecycle.states[id].phase=="active")
 assert(candidate.lifecycle.reservations["room:projector"]==id)
 assert(candidate.perform(1,"room","class-1",id,"hint",null,100.5)=="unsupported")
 var answer: String=str(candidate.rooms.room.round.private_assignment.questions[candidate.rooms.room.round.question_index].answer)
 assert(candidate.perform(3,"room","class-1",id,"submit",answer,101.0)=="denied")
 assert(candidate.perform(1,"room","old-class",id,"submit",answer,101.0)=="denied")
 assert(candidate.perform(1,"room","class-1","old-event","submit",answer,101.0)=="not_participating")
 assert(candidate.perform(1,"room","class-1",id,"submit",answer,101.0)=="accepted")
 assert(candidate.rooms.room.round.quiz_points("alice")==0)
 var private_view:=candidate.view(1,"room",102.0)
 var observer_view:=candidate.view(3,"room",102.0)
 assert(private_view.submitted and not private_view.has("result"))
 assert(not observer_view.can_submit and not str(observer_view).contains("alice"))
 assert(not observer_view.hands.selected and not observer_view.hands.raised)
 assert(not observer_view.question.has("answer"))
 assert(not observer_view.has("reveal"))
 game.lecture_classes.classes.room.students["observer"]={"peer":3,"done":false}
 candidate.sync_roster("room",102.0)
 assert(candidate.view(3,"room",102.0).can_submit)
 assert(candidate.perform(3,"room","class-1",id,"submit",answer,102.0)=="accepted")
 # A duplicate profile mapping must not displace the enrolled live peer.
 game.session.roster[5]={};game.school.identities[5]="bob";game.lecture_classes.present[5]=true
 candidate.sync_roster("room",102.0)
 assert(candidate.rooms.room.round.present.has("bob"))
 assert(game.lecture_classes.classes.room.students.bob.peer==2)
 assert(not candidate.view(5,"room",102.0).can_submit)
 game.session.roster.erase(5);game.school.identities.erase(5)
 game.session.roster.erase(2);game.school.identities.erase(2);candidate.sync_roster("room",103.0)
 assert(not candidate.rooms.room.round.present.has("bob"))
 game.session.roster[4]={};game.school.identities[4]="bob";game.lecture_classes.present[4]=true
 game.session.roster[5]={};game.school.identities[5]="bob"
 candidate.sync_roster("room",103.5)
 assert(not candidate.rooms.room.round.present.has("bob"))
 assert(game.lecture_classes.classes.room.students.bob.peer==2)
 game.session.roster.erase(5);game.school.identities.erase(5)
 candidate.sync_roster("room",104.0)
 assert(candidate.rooms.room.round.present.has("bob"))
 assert(game.lecture_classes.classes.room.students.bob.peer==4)
 assert(candidate.perform(2,"room","class-1",id,"hand",true,104.0)=="denied")
 assert(candidate.perform(4,"room","class-1",id,"hand",true,104.0)=="accepted")
 assert(candidate.perform(1,"room","class-1",id,"hand",true,104.0)=="accepted")
 candidate.rooms.room.next_call=110.0
 candidate.tick(110.0)
 assert(candidate.view(4,"room",110.0).hands.selected)
 assert(candidate.view(3,"room",110.0).hands.called)
 assert(not candidate.view(3,"room",110.0).hands.selected)
 game.lecture_classes.present[4]=false
 candidate.sync_roster("room",111.0)
 assert(candidate.rooms.room.hands.selected.is_empty())
 candidate.tick(114.0)
 assert(candidate.rooms.room.hands.selected.is_empty())
 game.lecture_classes.present[4]=true
 candidate.sync_roster("room",115.0)
 candidate.tick(122.0)
 assert(not candidate.view(4,"room",118.0).hands.selected)
 game.lecture_classes.present[1]=false;game.lecture_classes.present[3]=false;game.lecture_classes.present[4]=false
 candidate.sync_roster("room",123.0)
 assert(candidate.lifecycle.states[id].phase=="interrupted")
 game.lecture_classes.present[1]=true;game.lecture_classes.present[4]=true;candidate.sync_roster("room",124.0)
 assert(candidate.lifecycle.states[id].phase=="active")
 assert(candidate.perform(4,"room","class-1",id,"submit",{"x":NAN},104.0)=="invalid")
 var huge:=[]
 for i in 6:huge.append(range(100))
 assert(not Candidate.safe_payload(huge,0))
 for i in 6:assert(candidate.perform(4,"room","class-1",id,"hand",false,104.0)=="accepted")
 assert(candidate.perform(4,"room","class-1",id,"hand",true,104.0)=="rate_limited")
 candidate.tick(130.0)
 assert(candidate.view(1,"room",130.0).totals.answered>=1)
 assert(candidate.view(1,"room",130.0).totals.total_points>=100)
 assert(candidate.perform(4,"room","class-1",id,"hand",true,130.0)=="denied")
 assert(candidate.lifecycle.states[id].phase=="complete")
 assert(candidate.lifecycle.reservations.is_empty())
 assert(candidate.view(1,"room",130.0).result.correct)
 assert(candidate.view(1,"room",130.0).has("reveal"))
 assert(candidate.view(1,"room",130.0).result.points>=100)
 assert(candidate.view(1,"room",130.0).result.points==148)
 assert(candidate.rooms.room.round.quiz_points("bob")==0)
 assert(candidate.view(4,"room",130.0).result.is_empty())
 game.session.roster[5]={};game.school.identities[5]="alice";game.lecture_classes.present[5]=true
 assert(not candidate.view(5,"room",130.0).has("result"))
 game.lecture_classes.classes.room.phase="assignment";candidate.tick(131.0)
 assert(candidate.view(1,"room",131.0).is_empty() and candidate.rooms.is_empty())
 assert(not candidate.lifecycle.states.has(id))
 game.lecture_classes.classes.room.phase="lesson"
 game.lecture_classes.classes.room.deadline=220.0
 assert(candidate.start("room",132.0,[],"practice"))
 var practice_id: String=candidate.rooms.room.round.event_id
 assert(candidate.perform(1,"room","class-1",practice_id,"hint",true,133.0)=="invalid")
 assert(candidate.perform(5,"room","class-1",practice_id,"hint",null,133.0)=="denied")
 assert(candidate.perform(1,"room","class-1",practice_id,"hint",null,133.0)=="accepted")
 assert(candidate.perform(1,"room","class-1",practice_id,"hint",null,133.1)=="already_used")
 assert(candidate.view(1,"room",133.0).has("hint"))
 assert(not candidate.view(4,"room",133.0).has("hint"))
 assert(not candidate.view(4,"room",133.0).has("progress"))
 assert(candidate.perform(1,"room","class-1",practice_id,"submit","invalid response",134.0)=="retry")
 assert(candidate.view(1,"room",134.0).progress.attempts_left==1)
 assert(not candidate.view(4,"room",134.0).has("progress"))
 game.lecture_classes.present[1]=false;candidate.sync_roster("room",135.0)
 assert(candidate.perform(1,"room","class-1",practice_id,"submit","invalid response",135.0)=="denied")
 game.lecture_classes.present[1]=true;candidate.sync_roster("room",136.0)
 assert(candidate.view(1,"room",136.0).progress.attempts_left==1)
 assert(candidate.perform(1,"room","class-1",practice_id,"submit","invalid response",136.0)=="accepted")
 assert(not candidate.view(1,"room",136.0).has("result"))
 game.lecture_classes.classes.room.phase="assignment";candidate.tick(137.0)
 assert(candidate.rooms.is_empty() and candidate.view(1,"room",137.0).is_empty())
 print("CLASSROOM_INTEGRATION_CANDIDATE PASS")
 candidate.queue_free();game.queue_free();quit(0)
