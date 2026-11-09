extends SceneTree
var game
func _initialize():call_deferred("run")
func run():
 var role=OS.get_cmdline_user_args()[0]
 game=load("res://scenes/Main.tscn").instantiate();root.add_child(game)
 for i in 4:await process_frame
 if role=="host":
  assert(game.session.host_game("Host",24925)==OK)
  game.capture()
  var lab=game.dc_lab
  assert(lab.edit_external(1,0,"begin_external","CH1+")=="");assert(lab.edit_external(1,1,"link_external","R1a")=="")
  assert(lab.edit_external(1,0,"begin_external","CH1-")=="");assert(lab.edit_external(1,1,"link_external","R1b")=="")
  lab.benches[0].master=true;lab.benches[0].channels[0].enabled=true;lab.benches[0].channels[0].limit=.003
  var end=Time.get_ticks_msec()+20000
  while game.session.roster.size()<3 and Time.get_ticks_msec()<end:await create_timer(.1).timeout
  assert(game.session.roster.size()==3)
  await create_timer(14).timeout
  print("PASS: shared circuit host with two late clients")
 else:
  assert(game.session.join_game("127.0.0.1",role,24925)==OK)
  var destination: Vector3=game.dc_lab.bench_position(0)
  var end=Time.get_ticks_msec()+20000
  while game.dc_lab.states[0].get("external_links",[]).size()!=2 and Time.get_ticks_msec()<end:
   game.player.position=destination
   game.session.send_pose({"position":destination})
   await create_timer(.1).timeout
  await create_timer(.5).timeout
  var a=game.dc_lab.states[0];var b=game.dc_lab.states[1]
  assert(a.external_links.size()==2 and a.result.mode.s0=="CC")
  assert(abs(float(b.result.i.r0)-.003)<.000001)
  assert(abs(a.result.i.s0+b.result.i.r0)<.000001)
  print("PASS: "+role+" cross-bench wiring and loaded current-limit result synchronized")
  await create_timer(2).timeout
 quit()
