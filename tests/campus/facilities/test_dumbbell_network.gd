extends SceneTree
var game
var deadline:=0
func until(condition: Callable,label: String) -> bool:
 while Time.get_ticks_msec()<deadline:
  if condition.call():return true
  await create_timer(.05).timeout
 push_error("DUMBBELL NETWORK TIMEOUT "+label);quit(1);return false
func _initialize():call_deferred("run")
func run():
 var role:=OS.get_cmdline_user_args()[0]
 game=load("res://scenes/Main.tscn").instantiate();root.add_child(game)
 for i in 4:await process_frame
 deadline=Time.get_ticks_msec()+50000
 if role=="host":
  if game.session.host_game("Host",26315)!=OK:quit(1);return
  print("HOST_READY")
  if not await until(func():return int(game.gym_weights.items[8].owner)>1,"remote pair pickup"):return
  if not await until(func():return game.gym_weights.items[8].where=="rack","remote pair return"):return
  print("PASS host observed exclusive pickup and return")
 else:
  if game.session.join_game("127.0.0.1","Student",26315)!=OK:quit(1);return
  if not await until(func():
   var p: Vector3=game.gym_weights.RACK
   game.player.global_position=p
   game.session.send_pose({"position":p})
   return game.session.roster.size()==2 and game.session.poses.get(game.multiplayer.get_unique_id(),{}).get("position",Vector3.INF).distance_to(p)<.6
  ,"approach rack"):return
  game.gym_weights.request("pickup",8)
  if not await until(func():return game.gym_weights.held_id(game.multiplayer.get_unique_id())==8,"pickup acknowledged"):return
  assert(absf(game.gym_weights.held_mass(game.multiplayer.get_unique_id())-25.0*2*.45359237)<.0001)
  game.gym_weights.request("return",8)
  if not await until(func():return game.gym_weights.items[8].where=="rack","return acknowledged"):return
  print("PASS client received dumbbell state and mass")
 quit()
