extends SceneTree
func _initialize():call_deferred("run")
func run():
 var game=load("res://scenes/Main.tscn").instantiate();root.add_child(game)
 for i in 4:await physics_frame
 var registry=game.campus.registry
 assert(registry.locate(Vector3(0,.1,64))=="lost_found")
 var query:=PhysicsRayQueryParameters3D.create(Vector3(11,1.6,64),Vector3(9,1.6,64),1)
 var hit:Dictionary=game.get_world_3d().direct_space_state.intersect_ray(query)
 if not hit.is_empty():print("DOOR_BLOCKED ",hit)
 assert(hit.is_empty())
 print("PASS lost-and-found room registry and entrance")
 quit()
