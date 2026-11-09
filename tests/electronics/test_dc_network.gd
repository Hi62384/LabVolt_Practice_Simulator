extends SceneTree
var game
func _initialize():call_deferred("run")
func run():
 var role=OS.get_cmdline_user_args()[0]
 game=load("res://scenes/Main.tscn").instantiate();root.add_child(game)
 for f in 4:await process_frame
 if role=="host":
  assert(game.session.host_game("Host",24921)==OK);game.school.start("Freeplay",0)
  game.capture()
  for n in 3:
   var station=game.dc_lab.benches[n]
   station.master=true;station.channels[0].enabled=true;station.channels[0].voltage=3+n
   assert(station.apply({"op":"wire","a":"CH1+","b":"R1a"})=="")
   assert(station.apply({"op":"wire","a":"CH1-","b":"R1b"})=="")
  game.dc_lab.broadcast()
  var end=Time.get_ticks_msec()+20000
  while game.session.roster.size()<3 and Time.get_ticks_msec()<end:await create_timer(.1).timeout
  assert(game.session.roster.size()==3)
  await create_timer(14).timeout
  print("PASS: host three independent DC circuits with two late clients")
 else:
  assert(game.session.join_game("127.0.0.1",role,24921)==OK)
  var destination: Vector3=game.dc_lab.bench_position(1)
  var end=Time.get_ticks_msec()+20000
  while (game.dc_lab.states.slice(0,3).any(func(state):return not state.master or not state.result.get("drop",{}).has("s0")) or game.session.roster.size()<3) and Time.get_ticks_msec()<end:
   game.player.position=destination
   game.session.send_pose({"position":destination})
   await create_timer(.1).timeout
  for n in 3:
   var state=game.dc_lab.states[n]
   assert(state.master and state.result.ok)
   assert(abs(float(state.result.drop.s0)-(3+n))<.01)
   assert(abs(float(state.result.i.s0))>.0001)
   assert(state.wires.size()==2)
  print("PASS: "+role+" late-join all three supplies, actual electrical results and wiring synchronized")
  await create_timer(2).timeout
 quit()

