extends SceneTree
const Controller=preload("res://scripts/campus/academics/classroom_events/controller.gd")
const Dialogue=preload("res://scripts/campus/academics/teacher_dialogue.gd")
class FakeClasses extends Node:
 var classes: Dictionary={}
class FakeGame extends Node:
 var lecture_classes: Node
 var faculty: Node
class FakeFaculty extends Node:
 var calls: Array=[]
 func present_class_intention(room: String,teacher: String,intention: String,_observation: Dictionary={},_priority:=2) -> void:calls.append([room,teacher,intention])
class FakeService extends Node:
 var rooms: Dictionary={}
 func tick(_now: float) -> void:pass
 func sync_roster(_room: String,_now: float) -> void:pass
 func publish(_room: String,_now: float) -> void:pass
func _initialize() -> void:call_deferred("run")
func run() -> void:
 if Dialogue.surprise_intention({"talkativeness":.4,"focus":.2},"ETY155")!="" or Dialogue.surprise_intention({"talkativeness":.9,"focus":.9},"ETY155")!="":push_error("Focused teachers received tangents");quit(1);return
 var intention:=Dialogue.surprise_intention({"talkativeness":.9,"focus":.2},"ETY155")
 if not intention.contains("ETY155") or not intention.contains("own interests") or not intention.contains("do not invent"):
  push_error("Surprise intention lacks current-course, identity or gameplay-truth constraints");quit(1);return
 for i in 3:assert(Dialogue.surprise_comment({"talkativeness":.9,"focus":.2},"ETY155",i).is_empty(),"Legacy variant indices must not select canned dialogue")
 var game=FakeGame.new();root.add_child(game)
 var classes=FakeClasses.new();game.add_child(classes)
 var faculty=FakeFaculty.new();game.add_child(faculty)
 var service=FakeService.new();game.add_child(service)
 game.lecture_classes=classes;game.faculty=faculty
 var owner=Controller.new();game.add_child(owner)
 owner.game=game;owner.service=service;owner.enabled=true
 var class_id: String=""
 for i in 1000:
  var candidate: String="surprise-%d"%i
  if posmod(candidate.hash() ^ "mr_apple".hash(),100)<35:class_id=candidate;break
 if class_id.is_empty():push_error("No deterministic surprise seed");quit(1);return
 classes.classes.ety155_lecture={"id":class_id,"phase":"lesson","teacher":"mr_apple","course":"ETY155","deadline":250.0}
 owner.attempted[class_id]={"count":1,"tries":0,"next":INF,"recent":[],"recent_modes":[]}
 owner.step(100.0);owner.step(101.0)
 if not owner.surprise_shown.has(class_id) or faculty.calls.size()!=1:push_error("Surprise was absent or repeated");quit(1);return
 assert(faculty.calls[0][0]=="ety155_lecture" and faculty.calls[0][1]=="mr_apple" and str(faculty.calls[0][2]).contains("ETY155"),"The actual scheduler routes the intention to the correct character and class")
 classes.classes.ety155_lecture.phase="assignment"
 owner.step(102.0)
 if faculty.calls.size()!=1:push_error("Surprise continued into assessment");quit(1);return
 classes.classes.clear();owner.step(103.0)
 if owner.surprise_shown.has(class_id):push_error("Finished class retained surprise state");quit(1);return
 print("TEACHER_SURPRISE PASS")
 game.queue_free();await process_frame;quit(0)
