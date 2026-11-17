extends SceneTree
func _initialize():call_deferred("run")
func run():
 var game=load("res://scenes/Main.tscn").instantiate();root.add_child(game)
 for i in 6:await physics_frame
 game.player.global_position=Vector3(13,.05,-9)
 game.school.identities[1]=game.school.local_identity
 var id: int=game.school._give(1,load("res://scripts/course_generator.gd").generate(0,0,123),true,false)
 assert(id>0 and game.school.papers[id].held)
 var point: Vector3=game.player.global_position+Vector3(.6,0,0)
 game.school.apply(1,{"op":"drop","id":id,"position":point})
 assert(game.school.papers.has(id) and not game.school.papers[id].held)
 assert(game.discarded_items.drops.is_empty())
 game.school.apply(1,{"op":"pickup","id":id})
 assert(game.school.papers[id].held)
 print("PASS ground drop retains and restores original item")
 quit()
