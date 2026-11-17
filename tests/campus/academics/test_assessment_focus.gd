extends SceneTree
const Guard=preload("res://scripts/campus/academics/attention/focus_guard.gd")
class FakeSession extends Node:
 signal roster_changed
 signal leaving
 var online:=false
 var roster:={1:{"name":"Student"}}
class FakeSchool extends Node:
 var papers:={}
 var phase:="assignment"
 var assessment_id:="exam-1"
 var marks:=0
 func _class_assessment(paper: Dictionary)->bool:return not paper.get("lesson",true) and int(paper.get("class_round",0))!=0
 func _mark(paper: Dictionary,_expired: bool,reason: String)->void:
  marks+=1;paper.mark={"score":0.0,"reason":reason}
 func broadcast()->void:pass
 func checkpoint()->void:pass
class FakeLecture extends Node:
 var classes:={}
 func paper_submitted(_paper: Dictionary)->void:pass
class FakeGame extends Node:
 var session: FakeSession
 var school: FakeSchool
 var lecture_classes: FakeLecture
func _initialize():call_deferred("run")
func run():
 var game:=FakeGame.new();root.add_child(game)
 game.session=FakeSession.new();game.add_child(game.session)
 game.school=FakeSchool.new();game.add_child(game.school)
 game.lecture_classes=FakeLecture.new();game.add_child(game.lecture_classes)
 var paper:={"owner":1,"assessment_id":"exam-1","class_round":1,"lesson":false,"project":{},"mark":{}}
 game.school.papers={1:paper}
 var guard:=Guard.new();game.add_child(guard);guard.build(game);guard.set_process(false)
 guard._accept(1,false,"exam-1")
 assert(guard.reports.has(1))
 guard._accept(1,true,"exam-1")
 assert(not guard.reports.has(1) and game.school.marks==0)
 guard._accept(1,false,"exam-1")
 guard.reports[1].deadline=Time.get_ticks_msec()-1
 guard._accept(1,true,"exam-1")
 assert(game.school.marks==1 and paper.mark.score==0.0 and not guard.reports.has(1))
 guard._accept(1,false,"exam-1");assert(not guard.reports.has(1))
 game.school.papers={2:{"owner":1,"assessment_id":"practice","class_round":0,"lesson":true,"project":{},"mark":{}}}
 guard._accept(1,false,"practice");assert(not guard.reports.has(1))
 print("PASS assessment focus grace, zero and practice exclusion")
 quit()
