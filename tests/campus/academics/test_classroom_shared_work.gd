extends SceneTree
const Service=preload("res://scripts/campus/academics/classroom_events/service.gd")
class Session:
 var roster:={1:{},2:{},3:{}}
 var online:=false
 func peer_connected_now(_peer: int) -> bool:return false
class School:
 var identities:={1:"alice",2:"bob",3:"observer"}
 var random:=RandomNumberGenerator.new()
 var papers:={1:{"classroom_board":"room","position":Vector3.ZERO,"board_lines":[[Vector2.ZERO,Vector2.ONE]],"board_notes":[],"revision":0}}
 var nearby:=true
 func _near(_peer: int,_point: Vector3) -> bool:return nearby
 func broadcast() -> void:pass
class Classes:
 var classes:={"room":{"id":"class-1","phase":"lesson","kind":"lecture","teacher":"mr_stone","deadline":300.0,"course":"DGS266","week":3,"difficulty":0,"students":{"alice":{"peer":1,"done":false},"bob":{"peer":2,"done":false}}}}
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
 var service:=Service.new();root.add_child(service);service.configure(game)
 assert(service.start("room",100.0,[],"group"))
 assert(not service.view(1,"room",101.0).shared.task.is_empty())
 assert(service.view(1,"room",101.0).shared.task!=service.view(2,"room",101.0).shared.task)
 var id: String=service.rooms.room.round.event_id
 assert(service.lifecycle.reservations["room:worksheet"]==id)
 assert(not service.lifecycle.begin("conflict","room",["worksheet"]))
 assert(not service.start("room",101.0,[],"group"))
 assert(service.perform(3,"room","class-1",id,"contribute","spy",101.0)=="denied")
 assert(service.perform(1,"room","class-1",id,"contribute",["bad"],101.0)=="invalid")
 assert(service.perform(1,"room","class-1",id,"contribute","a\nb",101.0)=="invalid")
 assert(service.perform(1,"room","class-1",id,"contribute","Reasoning from Alice",101.0)=="accepted")
 assert(service.perform(1,"room","class-1",id,"vote",true,101.0)=="accepted")
 assert(service.view(1,"room",101.0).shared.agree==1)
 assert(service.perform(2,"room","class-1",id,"vote",true,101.0)=="no_proposal")
 assert(service.perform(3,"room","class-1",id,"vote",true,101.0)=="denied")
 assert(service.perform(1,"room","class-1",id,"contribute","second",102.0)=="already_submitted")
 assert(service.perform(2,"room","class-1",id,"contribute","Reasoning from Bob",102.0)=="accepted")
 assert(service.perform(2,"room","class-1",id,"vote",true,102.0)=="accepted")
 assert(service.view(1,"room",103.0).shared.agree==1 and service.view(2,"room",103.0).shared.agree==1)
 assert(service.view(1,"room",103.0).shared.entries.size()==1)
 assert(service.view(2,"room",103.0).shared.entries.size()==1)
 assert(service.view(3,"room",103.0).shared.entries.is_empty())
 assert(service.view(3,"room",103.0).shared.proposal.is_empty() and service.view(3,"room",103.0).shared.agree==0)
 game.session.roster.erase(2);game.school.identities.erase(2);service.sync_roster("room",104.0)
 assert(service.rooms.room.shared.view("bob").agree==0 and service.rooms.room.shared.view("bob").vote==null)
 assert(service.rooms.room.shared.view("alice").agree==1)
 assert(service.perform(2,"room","class-1",id,"contribute","departed",105.0)=="denied")
 game.session.roster[4]={};game.school.identities[4]="bob";game.lecture_classes.present[4]=true
 service.sync_roster("room",106.0)
 assert(service.view(4,"room",106.0).shared.contributed)
 assert(service.view(4,"room",106.0).shared.agree==1 and service.view(4,"room",106.0).shared.vote==true)
 assert(service.perform(4,"room","class-1",id,"contribute","repeat",107.0)=="already_submitted")
 game.session.roster[5]={};game.school.identities[5]="charlie";game.lecture_classes.present[5]=true
 game.lecture_classes.classes.room.students["charlie"]={"peer":5,"done":false}
 service.sync_roster("room",108.0)
 assert(service.view(5,"room",108.0).shared.group=="A")
 assert(service.perform(5,"room","class-1",id,"contribute","Late note",109.0)=="accepted")
 assert(service.view(1,"room",109.0).shared.entries.size()==2)
 game.lecture_classes.classes.room.phase="assignment";service.tick(110.0)
 assert(service.rooms.is_empty() and service.lifecycle.reservations.is_empty())
 assert(service.view(1,"room",110.0).is_empty())
 assert(service.perform(1,"room","class-1",id,"vote",true,111.0)=="denied")
 game.lecture_classes.classes.room.phase="lesson"
 assert(service.start("room",120.0,[],"board"))
 var previous_id:=id
 id=service.rooms.room.round.event_id
 assert(service.lifecycle.reservations["room:board"]==id)
 assert(game.school.papers[1].board_lines.is_empty())
 assert(not service.can_mark_board(1,"room",120.0))
 assert(not service.call_disruptive_student(3,"room","mr_stone",120.5))
 assert(not service.call_disruptive_student(1,"room","wrong teacher",120.5))
 game.lecture_classes.present[1]=false
 assert(not service.call_disruptive_student(1,"room","mr_stone",120.5))
 game.lecture_classes.present[1]=true
 assert(service.call_disruptive_student(1,"room","mr_stone",120.5))
 assert(service.rooms.room.hands.selected=="alice" and service.can_mark_board(1,"room",120.5))
 assert(not service.call_disruptive_student(1,"room","mr_stone",120.6))
 assert(service.rooms.room.hands.finish_turn(true,id))
 assert(service.rooms.room.hands.call_student(true,id,"alice"))
 assert(service.can_mark_board(1,"room",121.0))
 assert(not service.can_mark_board(2,"room",121.0))
 assert(not service.can_mark_board(3,"room",121.0))
 game.lecture_classes.present[1]=false
 assert(not service.can_mark_board(1,"room",121.0))
 game.lecture_classes.present[1]=true
 assert(service.can_mark_board(1,"room",121.0))
 game.session.roster.erase(1);game.school.identities.erase(1)
 service.sync_roster("room",121.5)
 assert(not service.can_mark_board(1,"room",122.0))
 game.session.roster[1]={};game.school.identities[1]="alice"
 service.sync_roster("room",122.5)
 assert(not service.can_mark_board(1,"room",123.0))
 assert(service.rooms.room.hands.call_student(true,id,"alice"))
 assert(service.can_mark_board(1,"room",123.0))
 assert(not service.lifecycle.begin("board-conflict","room",["board"]))
 assert(service.perform(1,"room","class-1",previous_id,"contribute","Replay note",120.5)=="not_participating")
 assert(service.view(1,"room",120.5).shared.entries.is_empty())
 game.school.nearby=false
 assert(service.perform(1,"room","class-1",id,"contribute","Too far",123.0)=="denied")
 game.school.nearby=true
 assert(service.perform(1,"room","class-1",id,"contribute","On the board",123.0)=="accepted")
 assert(game.school.papers[1].board_notes[0].text=="On the board")
 assert(service.view(3,"room",122.0).shared.entries.size()==1)
 service.tick(150.0)
 assert(not service.can_mark_board(1,"room",150.0))
 assert(service.perform(1,"room","class-1",id,"contribute","too late",151.0)=="denied")
 assert(service.lifecycle.reservations.is_empty())
 service.tick(160.0)
 assert(service.rooms.is_empty())
 var solo:=preload("res://scripts/campus/academics/classroom_events/shared_work.gd").new()
 assert(solo.begin("group",["solo"]) and solo.view("solo").group=="A")
 assert(solo.view("solo").task.contains("Solve"))
 var circuit:=preload("res://scripts/campus/academics/classroom_events/shared_work.gd").new()
 assert(circuit.begin("group",["one","two"]))
 circuit.set_question("Calculate current in the circuit")
 assert(circuit.view("one").task.contains("Calculate") and circuit.view("two").task.contains("units"))
 var eight:=preload("res://scripts/campus/academics/classroom_events/shared_work.gd").new()
 var members: Array=[]
 for i in 8:members.append("student_%d"%i)
 assert(eight.begin("group",members))
 # The existing classroom groups seven or more people into four teams.
 # Check all teams and use an actual same-team voter for the privacy probe.
 var team_counts:={}
 for member in members:
  var team: String=eight.view(member).group
  team_counts[team]=int(team_counts.get(team,0))+1
 assert(team_counts=={"A":2,"B":2,"C":2,"D":2})
 assert(eight.contribute("student_0","A team note")=="accepted")
 assert(eight.vote("student_4",true)=="accepted")
 assert(eight.vote("student_0",false)=="accepted")
 assert(eight.view("student_4").agree==1 and eight.view("student_4").disagree==1)
 assert(eight.view("student_1").proposal.is_empty() and eight.view("student_1").agree==0)
 assert(eight.vote("student_0",true)=="accepted" and eight.view("student_4").agree==2)
 assert(eight.view("student_4").entries.size()==1)
 assert(eight.view("student_1").entries.is_empty())
 assert(eight.view("observer").entries.is_empty())
 eight.finish()
 assert(eight.vote("student_4",false)=="denied")
 assert(service.start("room",170.0,[],"group"))
 id=service.rooms.room.round.event_id
 assert(not service.view(1,"room",171.0).has("group_result"))
 var round=service.rooms.room.round
 var answer: Variant=round.private_assignment.questions[round.question_index].answer
 assert(service.perform(1,"room","class-1",id,"submit",answer,172.0)=="accepted")
 service.tick(200.0)
 assert(service.view(1,"room",200.0).group_result=={"team":"A","members":2,"answered":1,"correct":1})
 assert(service.view(4,"room",200.0).group_result=={"team":"B","members":1,"answered":0,"correct":0})
 assert(not service.view(3,"room",200.0).has("group_result"))
 service.tick(211.0)
 assert(service.rooms.is_empty())
 assert(service.start("room",220.0,[],"board"))
 assert(service.rooms.room.hands.selected.is_empty())
 service.tick(224.0)
 var called: String=service.rooms.room.hands.selected
 assert(not called.is_empty())
 var called_peer: int=int(game.lecture_classes.classes.room.students[called].peer)
 var reactions: Array[String]=[]
 service.board_progress.connect(func(_room: String,_teacher: String,comment: String):reactions.append(comment))
 service.board_stroke(called_peer,"room",225.0)
 assert(reactions.size()==1 and reactions[0].contains("first visible stroke"))
 for i in 11:service.board_stroke(called_peer,"room",232.0)
 assert(reactions.size()==2 and reactions[1].contains("several visible strokes"))
 game.lecture_classes.classes.room.phase="assignment"
 service.tick(233.0)
 assert(not service.call_disruptive_student(called_peer,"room","mr_stone",233.0))
 service.board_stroke(called_peer,"room",234.0)
 assert(reactions.size()==2)
 game.lecture_classes.classes.room.phase="lesson"
 game.lecture_classes.classes.room.deadline=400.0
 assert(service.start("room",240.0,[],"board"))
 service.tick(244.0)
 assert(not service.rooms.room.hands.selected.is_empty())
 service.tick(254.0)
 assert(reactions.size()==3 and (reactions[2].contains("first step") or reactions[2].contains("quantities")))
 service.tick(255.0)
 assert(reactions.size()==3)
 print("CLASSROOM_SHARED_WORK PASS")
 service.queue_free();game.queue_free();quit(0)
