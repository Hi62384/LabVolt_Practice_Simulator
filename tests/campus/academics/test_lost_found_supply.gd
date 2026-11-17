extends SceneTree
func _initialize():call_deferred("run")
func run():
 var game=load("res://scenes/Main.tscn").instantiate();root.add_child(game)
 for i in 6:await physics_frame
 game.school.identities[1]=game.school.local_identity
 game.player.global_position=Vector3(13,.05,-9)
 var profile=game.electronics.profile
 var counts: Dictionary=profile.data.dorm.get("supply_counts",{})
 counts.flashlight=1;profile.data.dorm.supply_counts=counts
 profile.data.dorm.carry_items=profile.data.dorm.get("carry_items",[])+["flashlight"]
 assert(profile.save()==OK)
 var lesson: Dictionary=load("res://scripts/course_generator.gd").generate(0,0,123)
 var paper_id: int=game.school._give(1,lesson,true,false,true)
 game.school.papers[paper_id].supply_id="flashlight"
 var point: Vector3=game.player.global_position+Vector3(.6,0,0)
 game.school.apply(1,{"op":"drop","id":paper_id,"position":point})
 var paper: Dictionary=game.school.papers[paper_id]
 assert(not paper.held and paper.has("lost_token"))
 var token: String=paper.lost_token
 assert(game.discarded_items._local_entries().has(token))
 game.school.apply(1,{"op":"pickup","id":paper_id})
 assert(paper.held and not game.discarded_items._local_entries().has(token))
 game.school.apply(1,{"op":"drop","id":paper_id,"position":point})
 token=paper.lost_token
 game.discarded_items.session_loaded=false # Simulate an interrupted game without a clean leave.
 game.school.papers.clear()
 game.front.in_game=true
 game.discarded_items._process(0)
 assert(game.discarded_items.session_loaded and game.discarded_items.drops.size()==1)
 var drop_id: int=game.discarded_items.drops.keys()[0]
 assert(game.discarded_items.drops[drop_id].label=="Flashlight")
 assert(is_equal_approx(game.discarded_items.drops[drop_id].position.y,.84))
 var item_view: Node=game.discarded_items.views[drop_id]
 assert(item_view.get_child(0).get_child_count()>0)
 assert(item_view.get_child(0).get_child(0) is MeshInstance3D)
 game.player.global_position=game.discarded_items.drops[drop_id].position
 game.discarded_items._pickup(1,drop_id,6)
 assert(not game.discarded_items._local_entries().has(token))
 assert(int(profile.data.dorm.supply_counts.get("flashlight",0))==1)
 print("PASS real ground flashlight, pickup, leave, rejoin and recovery")
 quit()

