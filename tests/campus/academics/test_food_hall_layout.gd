extends SceneTree
func _initialize():call_deferred("run")
func run():
 var game=load("res://scenes/Main.tscn").instantiate();root.add_child(game)
 for i in 5:await physics_frame
 var space=game.get_world_3d().direct_space_state
 var hit=space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(21,1.6,24.7),Vector3(21,1.6,27.3),1))
 if not hit.is_empty():printerr("Passage blocked by ",hit.collider.get_path())
 assert(hit.is_empty())
 assert(game.campus.room_roots.cafeteria.get_node_or_null("Door_cafeteria")==null)
 var furniture=game.campus_services.facilities.rooms.subway
 assert(absf(absf(furniture.rotation.y)-PI)<.01)
 assert(furniture.stations["subway/counter"].position.z>47.0)
 print("PASS cafeteria passage and Subway counter orientation")
 quit()
