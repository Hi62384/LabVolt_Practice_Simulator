extends SceneTree
const Faculty=preload("res://scripts/campus/academics/faculty.gd")
class Session:
 var online:=false
class Game:
 extends Node
 var session:=Session.new()
func _initialize() -> void:call_deferred("run")
func run() -> void:
 var world:=Node3D.new();root.add_child(world)
 var game:=Game.new()
 var faculty:=Faculty.new();world.add_child(faculty);faculty.set_process(false);faculty.game=game
 faculty.lunch=Node3D.new();faculty.add_child(faculty.lunch)
 faculty.lunch.position=faculty.lunch_patrol.position
 faculty.lunch_patrol.pause=0.0
 var obstacle:=StaticBody3D.new();obstacle.collision_layer=1;world.add_child(obstacle)
 var collider:=CollisionShape3D.new();var box:=BoxShape3D.new();box.size=Vector3(1.0,2.0,.2)
 collider.shape=box;obstacle.add_child(collider)
 obstacle.position=faculty.lunch_patrol.position+Vector3(0,.8,.5)
 await physics_frame;await physics_frame
 var original: Vector3=faculty.lunch_patrol.position
 faculty._update_food_patrol(.1)
 if faculty.lunch_patrol.position!=original or faculty.lunch_patrol.direction!= -1.0:
  push_error("Patrol failed to stop and reverse at obstacle");quit(1);return
 obstacle.queue_free();await physics_frame;await physics_frame
 faculty.lunch_patrol.pause=0.0;faculty._update_food_patrol(.1)
 if faculty.lunch_patrol.position.z>=original.z:
  push_error("Patrol failed to move away from obstacle");quit(1);return
 print("FOOD_PATROL_OBSTRUCTION PASS")
 world.queue_free();game.free();await process_frame;quit(0)
