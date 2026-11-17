extends SceneTree
func _initialize():call_deferred("run")
func run():
 var game=load("res://scenes/Main.tscn").instantiate();root.add_child(game)
 for i in 4:await process_frame
 var avatar:=Node3D.new();game.add_child(avatar)
 var body=preload("res://scripts/toon_character.gd").build(preload("res://scripts/toon_character.gd").defaults())
 body.name="CharacterModel";avatar.add_child(body);game.avatars[2]=avatar
 var weights=game.gym_weights
 weights.items[8].owner=2;weights.items[8].where="held"
 weights._sync_remote_visuals()
 var ok: bool=weights.remote_models.has(2) and weights.remote_models[2].parts.size()==2
 if ok:
  for part in weights.remote_models[2].parts:ok=ok and part.get_parent().name in ["ArmL","ArmR"] and part.transform.basis.get_scale().length()>.9
  var activity=preload("res://scripts/campus/facilities/avatar_activity.gd").new();avatar.add_child(activity);activity.bind_visual(body)
  var left: Node3D=weights.remote_models[2].parts[0]
  var before:=left.global_position
  activity.apply_event({"activity":"exercise","station":"gym/dumbbell/2","exercise":"curl","phase":1,"half_ms":700},false)
  for i in 90:activity._process(.02);weights._sync_remote_visuals()
  ok=ok and left.global_position.distance_to(before)>.08
  activity.apply_event({"activity":"idle"},false)
 weights.items[8].where="rack";weights.items[8].owner=0;weights._sync_remote_visuals()
 ok=ok and not weights.remote_models.has(2)
 if not ok:push_error("Remote dumbbells did not follow both hands and clear")
 print("DUMBBELL_REMOTE_VISUAL ","PASS" if ok else "FAIL")
 game.avatars.erase(2);game.queue_free();await process_frame;quit(0 if ok else 1)
