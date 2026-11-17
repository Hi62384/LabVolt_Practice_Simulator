extends SceneTree
const Demo=preload("res://scripts/campus/academics/classroom_events/demonstration_round.gd")
const Mistake=preload("res://scripts/campus/academics/classroom_events/mistake_round.gd")
const Mystery=preload("res://scripts/campus/academics/classroom_events/mystery_round.gd")
const PassRound=preload("res://scripts/campus/academics/classroom_events/pass_round.gd")
const Service=preload("res://scripts/campus/academics/classroom_events/service.gd")
const Selector=preload("res://scripts/campus/academics/classroom_events/event_selector.gd")
const MathDemo=preload("res://scripts/campus/academics/classroom_events/math_demonstration_round.gd")
const AcDemo=preload("res://scripts/campus/academics/classroom_events/ac_demonstration_round.gd")
class Session:
 var roster:={1:{},2:{}}
 var online:=false
 func peer_connected_now(_peer: int) -> bool:return false
class School:
 var identities:={1:"alice",2:"bob"}
 var random:=RandomNumberGenerator.new()
class Classes:
 var classes:={"room":{"id":"class-1","phase":"lesson","kind":"lecture","deadline":300.0,"course":"ETY155","week":3,"difficulty":0,"students":{"alice":{"peer":1,"done":false},"bob":{"peer":2,"done":false}}}}
 var present:={1:true,2:true}
 func _inside(peer: int,_room: String) -> bool:return present.get(peer,false)
class Game:
 extends Node
 var session:=Session.new()
 var school:=School.new()
 var lecture_classes:=Classes.new()
func _initialize() -> void:call_deferred("run")
func run() -> void:
 var demo:=Demo.new()
 assert(demo.prepare(true,"demo","ETY155",3,0,42,130.0,["alice","bob"]))
 assert(demo.reveal().is_empty() and not demo.public_question.has("answer"))
 assert(absf(demo.changed_ma-demo.initial_ma/2.0)<0.05)
 assert(demo.public_question.options.size()==4)
 assert(demo.public_question.options[demo.correct_option]=="%.2f mA"%demo.changed_ma)
 assert(demo.submit(true,"alice","demo","99",101.0)=="invalid")
 assert(demo.submit(true,"alice","demo",str(demo.correct_option),101.0)=="accepted")
 assert(demo.submit(true,"alice","demo",str(demo.correct_option),102.0)=="already_submitted")
 assert(demo.add_participant(true,"late",103.0))
 assert(demo.submit(true,"late","demo",str(demo.correct_option),104.0)=="accepted")
 assert(demo.disconnected(true,"bob"))
 assert(demo.submit(true,"bob","demo",str(demo.correct_option),105.0)=="not_participating")
 assert(demo.rejoin(true,"bob",106.0))
 assert(demo.finish(true) and demo.result("alice").correct)
 assert(demo.reveal().source=="circuit solver")
 for week in [4,5,6]:
  var network_demo:=Demo.new()
  assert(network_demo.prepare(true,"network-%d"%week,"ETY155",week,1,42,130.0,["alice"]))
  var parameters: Dictionary=network_demo.private_assignment.demonstration
  var voltage: float=float(parameters.volts)
  var first: float=float(parameters.initial_ohms)
  var second: float=float(parameters.changed_ohms)
  var expected: float=voltage/(first+second)*1000.0 if week==4 else (voltage*(1.0/first+1.0/second)*1000.0 if week==5 else voltage/(first+first*second/(first+second))*1000.0)
  assert(absf(network_demo.changed_ma-expected)<0.05)
  assert(network_demo.public_question.options.size()==4 and network_demo.public_question.options.has("%.2f mA"%network_demo.changed_ma))
  var distinct: Dictionary={}
  for option in network_demo.public_question.options:distinct[option]=true
  assert(distinct.size()==4 and network_demo.reveal().is_empty())
  assert(network_demo.submit(true,"alice",network_demo.event_id,str(network_demo.correct_option),101.0)=="accepted")
  assert(network_demo.finish(true) and network_demo.result("alice").correct)
  assert(absf(float(network_demo.reveal().changed_ma)-expected)<0.05)
 assert(not Demo.new().prepare(true,"ac","ELM253",3,0,42,130.0,["alice"]))
 assert(not Demo.new().prepare(true,"late-dc","ETY155",7,0,42,130.0,["alice"]))
 var dc_activity: Dictionary={"kind":"lecture","course":"ETY155","week":4,"teaching":{"title":"Series DC circuits"}}
 assert("demonstration" in Selector.rank(dc_activity,{},2,[],42,100.0))
 dc_activity.course="ELM253";dc_activity.week=2
 assert("demonstration" not in Selector.rank(dc_activity,{},2,[],42,100.0))
 dc_activity.course="ETY155";dc_activity.week=7
 assert("demonstration" not in Selector.rank(dc_activity,{},2,[],42,100.0))
 for week in [3,4,5]:
  var ac_demo:=AcDemo.new()
  assert(ac_demo.prepare(true,"ac-%d"%week,"ELM253",week,1,42,130.0,["alice"]))
  var ac_parameters: Dictionary=ac_demo.private_assignment.demonstration
  var r: float=float(ac_parameters.resistance_ohms)
  var x: float=TAU*float(ac_parameters.after_hz)*float(ac_parameters.inductance_henry)
  var rms: float=float(ac_parameters.voltage_rms)
  var expected_ac: float=0.0
  if week==3:expected_ac=rms/Vector2(r,x).length()*1000.0
  elif week==4:expected_ac=rms*Vector2(1.0/r,1.0/x).length()*1000.0
  else:
   var real_parallel:=r*x*x/(r*r+x*x)
   var imaginary_parallel:=r*r*x/(r*r+x*x)
   expected_ac=rms/Vector2(r+real_parallel,imaginary_parallel).length()*1000.0
  assert(absf(ac_demo.changed_ma-expected_ac)<0.05)
  assert(ac_demo.reveal().is_empty() and ac_demo.public_question.options.size()==4)
  var ac_distinct: Dictionary={}
  for option in ac_demo.public_question.options:ac_distinct[option]=true
  assert(ac_distinct.size()==4)
  assert(ac_demo.submit(true,"alice",ac_demo.event_id,str(ac_demo.correct_option),101.0)=="accepted")
  assert(ac_demo.finish(true) and ac_demo.result("alice").correct and ac_demo.reveal().source=="AC network solver")
 assert(not AcDemo.new().prepare(true,"wrong-week","ELM253",2,0,42,130.0,["alice"]))
 dc_activity.course="ELM253";dc_activity.week=3;dc_activity.teaching={"title":"Series AC circuits"}
 assert("demonstration" in Selector.rank(dc_activity,{},2,[],42,100.0))
 var mistake:=Mistake.new()
 assert(mistake.prepare(true,"mistake","ETY155",3,0,42,130.0,["alice"]))
 assert(mistake.public_question.prompt.contains("Find the mistake"))
 assert(not mistake.public_question.prompt.contains(mistake.public_question.options[mistake.correct_option]))
 assert(mistake.reveal().is_empty())
 assert(Service.comment_for_round(mistake,0,0,{}).is_empty())
 assert(mistake.submit(true,"alice","mistake",str(mistake.correct_option),101.0)=="accepted")
 assert(mistake.finish(true) and mistake.result("alice").correct)
 assert(Service.comment_for_round(mistake,1,1,{}).contains(mistake.reveal().answer))
 assert(Service.comment_for_round(mistake,1,1,{}).contains("incorrectly"))
 var mystery:=Mystery.new()
 assert(mystery.prepare(true,"mystery","ETY155",3,0,42,230.0,["alice"]))
 assert(mystery.snapshot("alice",201.0).clues.is_empty())
 assert(mystery.snapshot("alice",211.0).clues.size()==1)
 assert(mystery.snapshot("alice",221.0).clues.size()==2)
 assert(mystery.reveal().is_empty())
 assert(mystery.finish(true) and mystery.reveal().source=="circuit solver")
 var passing:=PassRound.new()
 assert(passing.prepare(true,"pass","ETY155",3,0,42,330.0,["alice","bob"]))
 assert(passing.snapshot("alice",301.0).can_submit)
 assert(not passing.snapshot("bob",301.0).can_submit)
 assert(passing.submit(true,"bob","pass","6",302.0)=="not_your_turn")
 assert(passing.submit(true,"alice","pass",str(passing.private_assignment.demonstration.volts),302.0)=="accepted")
 assert(passing.snapshot("bob",303.0).can_submit)
 assert(passing.submit(true,"bob","pass",str(passing.private_assignment.demonstration.changed_ohms),304.0)=="accepted")
 assert(passing.snapshot("alice",305.0).can_submit)
 assert(passing.submit(true,"alice","pass","%.2f"%passing.changed_ma,306.0)=="accepted")
 assert(passing.snapshot("alice",307.0).pass_completed==3)
 assert(passing.reveal().is_empty())
 assert(passing.finish(true))
 assert(passing.reveal().steps.size()==3 and not str(passing.reveal()).contains("alice"))
 var solo:=PassRound.new()
 assert(solo.prepare(true,"solo","ETY155",3,0,43,330.0,["alice"]))
 assert(solo.submit(true,"alice","solo",str(solo.private_assignment.demonstration.volts),302.0)=="accepted")
 assert(solo.snapshot("alice",303.0).can_submit)
 assert(solo.disconnected(true,"alice") and not solo.snapshot("alice",304.0).can_submit)
 assert(solo.rejoin(true,"alice",305.0) and solo.snapshot("alice",306.0).can_submit)
 var game:=Game.new();root.add_child(game)
 var service:=Service.new();root.add_child(service);service.configure(game)
 var reactions: Array=[]
 service.round_completed.connect(func(room,teacher,comment):reactions.append({"room":room,"teacher":teacher,"comment":comment}))
 assert(service.start("room",100.0,[],"demonstration"))
 var id: String=service.rooms.room.round.event_id
 assert(service.lifecycle.reservations["room:projector"]==id and service.lifecycle.reservations["room:demo_bench"]==id)
 assert(not service.lifecycle.begin("conflict","room",["demo_bench"]))
 var public_view: Dictionary=service.view(2,"room",101.0)
 assert(not public_view.has("reveal") and not str(public_view).contains("changed_ma"))
 assert(service.perform(1,"room","class-1",id,"submit",str(service.rooms.room.round.correct_option),102.0)=="accepted")
 assert(not service.view(2,"room",103.0).has("result"))
 service.tick(130.0)
 assert(reactions.size()==1 and reactions[0].room=="room" and not reactions[0].comment.is_empty())
 assert(service.view(2,"room",130.0).reveal.source=="circuit solver")
 assert(service.view(1,"room",130.0).result.correct)
 assert(service.lifecycle.reservations.is_empty())
 service.tick(140.0)
 assert(reactions.size()==1)
 assert(service.rooms.is_empty())
 assert(service.start("room",150.0,[],"demonstration"))
 game.lecture_classes.classes.room.phase="assignment";service.tick(151.0)
 assert(service.rooms.is_empty() and service.lifecycle.reservations.is_empty())
 game.lecture_classes.classes.room.phase="lesson"
 assert(service.start("room",160.0,[],"mistake"))
 id=service.rooms.room.round.event_id
 assert(service.lifecycle.reservations["room:board"]==id)
 assert(not service.view(2,"room",161.0).has("reveal"))
 game.lecture_classes.classes.room.phase="assignment";service.tick(162.0)
 assert(service.rooms.is_empty() and service.lifecycle.reservations.is_empty())
 game.lecture_classes.classes.room.phase="lesson"
 assert(service.start("room",170.0,[],"teacher"))
 id=service.rooms.room.round.event_id
 assert(service.lifecycle.reservations["room:board"]==id)
 assert(not service.view(2,"room",171.0).has("reveal"))
 assert(service.rooms.room.round.deadline<200.0)
 service.tick(service.rooms.room.round.deadline)
 assert(service.view(2,"room",190.0).has("reveal"))
 assert(service.view(2,"room",190.0).teacher_result.students_beat_teacher==0)
 assert(service.lifecycle.reservations.is_empty())
 service.tick(service.rooms.room.round.deadline+10.0)
 assert(service.rooms.is_empty())
 assert(service.start("room",200.0,[],"mystery"))
 assert(service.view(2,"room",201.0).clues.is_empty())
 assert(service.view(2,"room",211.0).clues.size()==1)
 assert(not service.view(2,"room",211.0).has("reveal"))
 game.lecture_classes.classes.room.phase="assignment";service.tick(212.0)
 assert(service.rooms.is_empty() and service.lifecycle.reservations.is_empty())
 game.lecture_classes.classes.room.phase="lesson"
 game.lecture_classes.classes.room.deadline=400.0
 assert(service.start("room",220.0,[],"duel"))
 id=service.rooms.room.round.event_id
 assert(not service.view(1,"room",221.0).can_submit)
 assert(service.perform(1,"room","class-1",id,"submit","0",221.0)=="not_selected")
 assert(service.perform(1,"room","class-1",id,"hand",true,222.0)=="accepted")
 assert(service.perform(2,"room","class-1",id,"hand",true,223.0)=="accepted")
 service.tick(227.0)
 assert(service.rooms.room.duel_slots.size()==2)
 assert(service.view(1,"room",227.0).can_submit)
 assert(service.perform(1,"room","class-1",id,"hand",false,227.5)=="closed")
 game.lecture_classes.present[1]=false;service.sync_roster("room",227.6)
 assert(service.rooms.room.duel_slots==["alice","bob"])
 assert(service.perform(1,"room","class-1",id,"submit","0",227.7)=="denied")
 game.lecture_classes.present[1]=true;service.sync_roster("room",227.8)
 assert(service.view(1,"room",227.9).can_submit)
 var duel_answer: Variant=service.rooms.room.round.private_assignment.questions[service.rooms.room.round.question_index].answer
 assert(service.perform(1,"room","class-1",id,"submit",duel_answer,228.0)=="accepted")
 assert(service.perform(1,"room","class-1",id,"submit",duel_answer,228.1)=="already_submitted")
 assert(not service.view(2,"room",229.0).has("reveal"))
 service.tick(250.0)
 assert(service.view(2,"room",250.0).has("reveal"))
 assert(service.lifecycle.reservations.is_empty())
 assert(service.view(2,"room",250.0).duel.winner=="Student 1")
 assert(not service.view(2,"room",250.0).duel.won)
 assert(not str(service.view(2,"room",250.0).teacher_comment).is_empty())
 service.tick(260.0)
 assert(service.rooms.is_empty())
 game.lecture_classes.classes.room.deadline=500.0
 assert(service.start("room",270.0,[],"duel"))
 id=service.rooms.room.round.event_id
 assert(service.perform(1,"room","class-1",id,"hand",true,271.0)=="accepted")
 service.tick(277.0)
 assert(service.rooms.room.duel_slots==["alice"])
 assert(service.view(1,"room",278.0).can_submit)
 assert(not service.view(2,"room",278.0).can_submit)
 game.lecture_classes.classes.room.phase="assignment";service.tick(279.0)
 assert(service.rooms.is_empty() and service.lifecycle.reservations.is_empty())
 game.lecture_classes.classes.room.phase="lesson"
 assert(service.start("room",300.0,[],"race"))
 id=service.rooms.room.round.event_id
 var race_answer: Variant=service.rooms.room.round.private_assignment.questions[service.rooms.room.round.question_index].answer
 assert(service.perform(2,"room","class-1",id,"submit",race_answer,302.0)=="accepted")
 assert(service.perform(1,"room","class-1",id,"submit",race_answer,304.0)=="accepted")
 assert(not service.view(1,"room",305.0).has("race"))
 service.tick(330.0)
 assert(service.view(1,"room",330.0).race.winner=="Student 2")
 assert(service.view(2,"room",330.0).race.won)
 assert(not str(service.view(1,"room",330.0)).contains("bob"))
 service.tick(340.0)
 assert(service.rooms.is_empty() and service.lifecycle.reservations.is_empty())
 game.lecture_classes.classes.room.course="MTH147"
 game.lecture_classes.classes.room.week=2
 game.lecture_classes.classes.room.teaching={"title":"Linear functions and slope"}
 assert("demonstration" in Selector.rank(game.lecture_classes.classes.room,{},2,[],41,350.0))
 game.lecture_classes.classes.room.teaching={"title":"Probability experiment"}
 assert("demonstration" not in Selector.rank(game.lecture_classes.classes.room,{},2,[],41,350.0))
 assert(service.start("room",350.0,[],"demonstration"))
 id=service.rooms.room.round.event_id
 var math_round=service.rooms.room.round
 assert(math_round.get_script()==preload("res://scripts/campus/academics/classroom_events/math_demonstration_round.gd"))
 assert(math_round.reveal().is_empty() and not str(service.view(2,"room",351.0)).contains("diagram"))
 assert(math_round.diagram.curves[1].points[math_round.target_x+4].y==math_round.result_value)
 assert(service.perform(1,"room","class-1",id,"submit",str(math_round.correct_option),352.0)=="accepted")
 assert(not service.view(2,"room",353.0).has("reveal"))
 service.tick(380.0)
 assert(service.view(2,"room",380.0).reveal.diagram.kind=="graph")
 assert(service.view(1,"room",380.0).result.correct)
 service.tick(390.0)
 assert(service.rooms.is_empty() and service.lifecycle.reservations.is_empty())
 assert(service.start("room",400.0,[],"demonstration"))
 game.lecture_classes.classes.room.phase="assignment";service.tick(401.0)
 assert(service.rooms.is_empty() and service.lifecycle.reservations.is_empty())
 var advanced_math:=MathDemo.new()
 assert(advanced_math.prepare(true,"mth255","MTH255",2,1,42,440.0,["alice"]))
 assert(advanced_math.reveal().is_empty())
 assert(advanced_math.finish(true) and advanced_math.reveal().diagram.curves.size()==2)
 game.lecture_classes.classes.room.course="ETY155"
 game.lecture_classes.classes.room.phase="lesson"
 game.lecture_classes.classes.room.deadline=800.0
 for week in [4,5,6]:
  var start_time: float=410.0+float(week-4)*50.0
  game.lecture_classes.classes.room.week=week
  assert(service.start("room",start_time,[],"demonstration"))
  id=service.rooms.room.round.event_id
  assert(not service.view(2,"room",start_time+1.0).has("reveal"))
  assert(service.perform(1,"room","class-1",id,"submit",str(service.rooms.room.round.correct_option),start_time+2.0)=="accepted")
  service.tick(start_time+30.0)
  assert(service.view(1,"room",start_time+30.0).result.correct)
  assert(service.view(2,"room",start_time+30.0).reveal.source=="circuit solver")
  service.tick(start_time+41.0)
  assert(service.rooms.is_empty() and service.lifecycle.reservations.is_empty())
 game.lecture_classes.classes.room.course="ELM253"
 game.lecture_classes.classes.room.deadline=1000.0
 for week in [3,4,5]:
  var ac_start: float=570.0+float(week-3)*50.0
  game.lecture_classes.classes.room.week=week
  assert(service.start("room",ac_start,[],"demonstration"))
  id=service.rooms.room.round.event_id
  assert(service.rooms.room.round.get_script()==AcDemo)
  assert(not service.view(2,"room",ac_start+1.0).has("reveal"))
  assert(service.perform(1,"room","class-1",id,"submit",str(service.rooms.room.round.correct_option),ac_start+2.0)=="accepted")
  service.tick(ac_start+30.0)
  assert(service.view(1,"room",ac_start+30.0).result.correct)
  assert(service.view(2,"room",ac_start+30.0).reveal.source=="AC network solver")
  service.tick(ac_start+41.0)
  assert(service.rooms.is_empty() and service.lifecycle.reservations.is_empty())
 game.lecture_classes.classes.room.week=3
 assert(service.start("room",720.0,[],"demonstration"))
 game.lecture_classes.classes.room.phase="assignment";service.tick(721.0)
 assert(service.rooms.is_empty() and service.lifecycle.reservations.is_empty())
 print("CLASSROOM_DEMONSTRATION PASS")
 service.queue_free();game.queue_free();quit(0)
