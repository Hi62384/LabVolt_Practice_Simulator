extends SceneTree
const Patrol=preload("res://scripts/campus/academics/food_patrol.gd")
func _initialize() -> void:
 var patrol=Patrol.new()
 assert(not patrol.advance(1.0,false))
 assert(not patrol.advance(1.0,false))
 var original: Vector3=patrol.position
 assert(patrol.advance(1.0,false) and patrol.position.z>original.z)
 var before: Vector3=patrol.position
 assert(not patrol.advance(.1,true) and patrol.position==before and patrol.direction<0)
 for i in 1000:patrol.advance(.1,false)
 assert(patrol.position.z>=Patrol.MIN_Z and patrol.position.z<=Patrol.MAX_Z)
 assert(is_equal_approx(patrol.position.x,Patrol.START.x))
 print("FOOD_PATROL PASS")
 quit(0)
