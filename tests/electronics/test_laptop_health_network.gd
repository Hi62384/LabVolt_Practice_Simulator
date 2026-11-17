extends SceneTree
var game
var deadline: int
func _initialize():call_deferred("run")
func until(condition:Callable,what:String)->bool:
 while Time.get_ticks_msec()<deadline:
  if condition.call():return true
  await create_timer(.1).timeout
 push_error("FAIL "+what);quit(1);return false
func run():
 var role:=OS.get_cmdline_user_args()[0]
 game=load("res://scenes/Main.tscn").instantiate();root.add_child(game)
 for i in 4:await process_frame
 game.set_physics_process(false)
 deadline=Time.get_ticks_msec()+60000
 if role=="host":
  if game.session.host_game("Host",26492)!=OK:quit(1);return
  if not await until(func():return game.session.roster.size()==2,"client joined"):return
  var peer:int=game.session.roster.keys().filter(func(id):return id!=1)[0]
  game.session.poses[peer].position=Vector3(-8.8,0,5.5)
  if not await until(func():return game.ac_laptops.model.laptops[0].where=="held","remote laptop request"):return
  var lab=game.session.lab
  lab.powered=true;lab.readings.voltages["P_A"]=Vector2(120,0)
  lab.cables.append({"id":999,"a":"P_A","b":"","owner":peer,"creator":peer,"color":0})
  if not await until(func():return game.health.people.get(peer,{}).get("dead",false),"remote shock death"):return
  await create_timer(2).timeout
  print("PASS host accepted remote laptop and authoritative shock")
  quit()
 else:
  if game.session.join_game("127.0.0.1","Client",26492)!=OK:quit(1);return
  if not await until(func():return game.session.roster.size()==2,"roster"):return
  await create_timer(1).timeout
  game.ac_laptops.request("cabinet")
  if not await until(func():return game.ac_laptops.state.cabinet_open,"cabinet replication"):return
  game.ac_laptops.request("take_laptop",0)
  if not await until(func():return game.ac_laptops.state.laptops[0].owner==game.multiplayer.get_unique_id(),"laptop replication"):return
  if not await until(func():return game.health.people.get(game.multiplayer.get_unique_id(),{}).get("dead",false),"death replication"):return
  print("PASS client received laptop and shock state")
  quit()

