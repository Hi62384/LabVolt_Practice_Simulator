extends SceneTree
func _initialize():call_deferred("run")
func run():
 var game=load("res://scenes/Main.tscn").instantiate();root.add_child(game)
 for i in 4:await process_frame
 var styles:={}
 for tier in ["compact","standard","extended","large"]:
  var root: StaticBody3D=game.kit_world._create_kit_view(1,{"id":tier,"name":tier,"tier":tier})
  assert(root.get_meta("tier")==tier and root.has_node("Lid") and root.has_node("LidHit"))
  var shapes:=root.find_children("*","CollisionShape3D",false,false)
  var box: BoxShape3D=shapes[0].shape
  styles[tier]=box.size.x
  root.queue_free()
 assert(styles.compact<styles.standard and styles.standard<styles.extended and styles.extended<styles.large)
 var limit=game.get_script()
 var pair: Array=[[Vector3(4.9,0,0),Vector3.ZERO]]
 var clipped:Vector3=limit._clip_cable_motion(Vector3(1,0,0),pair)
 assert(absf(clipped.x-.1)<.0001)
 assert(limit._clip_cable_motion(Vector3(-1,0,0),pair)==Vector3(-1,0,0))
 var outside: Array=[[Vector3(5.2,0,0),Vector3.ZERO]]
 assert(limit._clip_cable_motion(Vector3(1,0,0),outside)==Vector3.ZERO)
 assert(limit._clip_cable_motion(Vector3(-.1,0,0),outside)==Vector3(-.1,0,0))
 print("PASS kit tier geometry and hard cable reach")
 quit()
