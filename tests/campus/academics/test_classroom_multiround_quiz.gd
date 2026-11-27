extends SceneTree
const Candidate=preload("res://scripts/campus/academics/classroom_events/service.gd")
class Session:
 var roster:={1:{},2:{}}
 var online:=false
 func peer_connected_now(_peer: int) -> bool:return false
class School:
 var identities:={1:"alice",2:"bob"}
 var random:=RandomNumberGenerator.new()
class Students:
 var completed: Array=[]
 func record_quiz_rivals(activity: Dictionary,scores: Dictionary) -> void:
  completed.append({"class_id":activity.id,"scores":scores.duplicate(true)})
class Classes:
 var classroom_students:=Students.new()
 var classes:={"room":{"id":"class-1","phase":"lesson","kind":"lecture","deadline":300.0,"course":"DGS266","week":3,"difficulty":0,"students":{"alice":{"peer":1,"done":false},"bob":{"peer":2,"done":false}}}}
 var present:={1:true,2:true}
 func _inside(peer: int,_room: String) -> bool:return present.get(peer,false)
class Game:
 extends Node
 var session:=Session.new()
 var school:=School.new()
 var lecture_classes:=Classes.new()
func _initialize() -> void:call_deferred("run")
func run() -> void:
 var game:=Game.new();root.add_child(game)
 var service:=Candidate.new();root.add_child(service);service.configure(game)
 assert(service.start("room",100.0,[],"quiz"))
 var first: String=service.rooms.room.round.event_id
 var answer: String=str(service.rooms.room.round.private_assignment.questions[service.rooms.room.round.question_index].answer)
 assert(service.perform(1,"room","class-1",first,"submit",answer,101.0)=="accepted")
 assert(service.perform(1,"room","class-1",first,"submit",answer,102.0)=="already_submitted")
 assert(not service.view(2,"room",102.0).has("leaderboard"))
 service.tick(130.0)
 assert(service.view(1,"room",130.0).personal_points==148)
 assert(service.view(1,"room",130.0).streak==1)
 assert(service.view(2,"room",130.0).personal_points==0)
 assert(service.view(2,"room",130.0).leaderboard.size()==2)
 assert(service.lifecycle.reservations.is_empty())
 service.tick(138.0)
 assert(service.rooms.has("room") and service.rooms.room.round.event_id!=first)
 assert(service.rooms.room.series.completed==1 and service.rooms.room.series.scores.alice==148)
 assert(service.lifecycle.reservations["room:projector"]==service.rooms.room.round.event_id)
 var second: String=service.rooms.room.round.event_id
 answer=str(service.rooms.room.round.private_assignment.questions[service.rooms.room.round.question_index].answer)
 assert(service.perform(1,"room","class-1",first,"submit",answer,139.0)=="not_participating")
 assert(service.perform(1,"room","class-1",second,"submit",answer,139.0)=="accepted")
 game.session.roster.erase(1);game.school.identities.erase(1);service.sync_roster("room",140.0)
 assert(not service.rooms.room.round.present.has("alice"))
 game.session.roster[3]={};game.school.identities[3]="alice";game.lecture_classes.present[3]=true
 service.sync_roster("room",141.0)
 assert(service.rooms.room.round.present.has("alice"))
 assert(service.perform(3,"room","class-1",second,"submit",answer,142.0)=="already_submitted")
 service.tick(168.0)
 assert(service.rooms.room.series.completed==2)
 assert(service.rooms.room.series.scores.alice==306)
 assert(service.view(3,"room",168.0).streak==2)
 service.tick(176.0)
 var third: String=service.rooms.room.round.event_id
 assert(third!=second and service.rooms.room.series.completed==2)
 game.lecture_classes.classes.room.phase="assignment";service.tick(177.0)
 assert(service.rooms.is_empty() and service.lifecycle.reservations.is_empty())
 assert(not service.lifecycle.states.has(third))
 game.lecture_classes.classes.room.id="class-2";game.lecture_classes.classes.room.phase="lesson"
 game.lecture_classes.classes.room.deadline=340.0
 assert(service.start("room",180.0,[],"quiz"))
 var timed: String=service.rooms.room.round.event_id
 service.tick(210.0)
 assert(service.lifecycle.states[timed].phase=="timed_out")
 assert(service.rooms.room.series.completed==1 and service.rooms.room.series.scores.alice==0)
 service.tick(218.0)
 assert(service.rooms.room.round.event_id!=timed)
 assert(service.lifecycle.reservations.has("room:projector"))
 game.session.roster[4]={};game.school.identities[4]="charlie";game.lecture_classes.present[4]=true
 game.lecture_classes.classes.room.students["charlie"]={"peer":4,"done":false}
 service.sync_roster("room",219.0)
 assert(service.view(4,"room",219.0).can_submit)
 var next_id: String=service.rooms.room.round.event_id
 answer=str(service.rooms.room.round.private_assignment.questions[service.rooms.room.round.question_index].answer)
 assert(service.perform(4,"room","class-2",next_id,"submit",answer,220.0)=="accepted")
 service.tick(248.0)
 assert(service.view(4,"room",248.0).personal_points>=100)
 assert(service.view(4,"room",248.0).team_scores.A+service.view(4,"room",248.0).team_scores.B==service.view(4,"room",248.0).personal_points)
 service.tick(256.0)
 assert(service.rooms.room.series.completed==2)
 service.tick(286.0)
 assert(service.rooms.room.series.completed==3)
 service.tick(294.0)
 assert(service.rooms.is_empty() and service.lifecycle.reservations.is_empty())
 game.lecture_classes.classes.room.id="class-3";game.lecture_classes.classes.room.deadline=380.0
 assert(service.start("room",300.0,[],"quiz"))
 assert(service.view(2,"room",300.0).rounds_total==1)
 service.tick(330.0);service.tick(338.0)
 assert(service.rooms.is_empty() and service.lifecycle.reservations.is_empty())
 assert(game.lecture_classes.classroom_students.completed.size()==2)
 assert(game.lecture_classes.classroom_students.completed[0].class_id=="class-2")
 assert(game.lecture_classes.classroom_students.completed[1].class_id=="class-3")
 print("CLASSROOM_MULTIROUND_QUIZ PASS")
 service.queue_free();game.queue_free();quit(0)
