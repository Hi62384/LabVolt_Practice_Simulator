extends SceneTree
var game
func _initialize():call_deferred("run")
func until(test: Callable):
 var deadline=Time.get_ticks_msec()+20000
 while not test.call():
  if Time.get_ticks_msec()>deadline:push_error("IO NETWORK TIMEOUT");quit(1);return false
  await create_timer(.02).timeout
 return true
func run():
 var role=OS.get_cmdline_user_args()[0]
 game=load("res://scenes/Main.tscn").instantiate();root.add_child(game)
 for i in 4:await process_frame
 var lab=game.dc_lab
 if role=="host":
  assert(game.session.host_game("Host",24940)==OK)
  game.capture()
  var design=load("res://scripts/breadboard_model.gd").empty()
  design.parts=[{"id":"pad","type":"io_keypad","a":"A1","b":"F1","pins":["A1","F1","A2","F2","A3","F3","A4"]}]
  assert(lab.benches[0].apply({"op":"board","design":design})=="");lab.benches[0].board_owner=1;lab.broadcast()
  if not await until(func():return game.session.roster.size()==2):return
  if not await until(func():return lab.benches[0].board.get("io_controls",{}).get("board/pad",{}).get("keys",0)==2):return
  if not await until(func():return game.session.roster.size()==1):return
  if not await until(func():return lab.benches[0].board.io_controls["board/pad"].keys==0):return
  print("PASS: authoritative IO disconnect cleanup on real ENet actor")
 else:
  assert(game.session.join_game("127.0.0.1","Client",24940)==OK)
  var destination: Vector3=lab.bench_position(0)
  if not await until(func():
   game.player.position=destination
   game.session.send_pose({"position":destination})
   if game.session.roster.size()!=2:return false
   var pose: Vector3=game.session.poses.get(game.multiplayer.get_unique_id(),{}).get("position",Vector3.INF)
   return not lab.states[0].board.is_empty() and pose.distance_to(destination)<2
  ):return
  var epoch=int(lab.states[0].board_epoch)
  lab.request(0,{"op":"input","id":"board/pad","board_epoch":epoch,"command":{"op":"key","key":0,"pressed":true,"revision":99}})
  if not await until(func():return lab.io_pending.is_empty()):return
  assert(lab.states[0].board.get("io_controls",{}).is_empty())
  lab.request(0,{"op":"input","id":"board/pad","board_epoch":epoch,"command":{"op":"key","key":0,"pressed":true,"revision":0}})
  if not await until(func():return lab.io_pending.is_empty() and lab.states[0].board.get("io_controls",{}).get("board/pad",{}).get("keys",0)==1):return
  lab.request(0,{"op":"input","id":"board/pad","board_epoch":epoch,"command":{"op":"release","revision":0}})
  if not await until(func():return lab.io_pending.is_empty() and lab.states[0].board.io_controls["board/pad"].keys==0):return
  lab.request(0,{"op":"input","id":"board/pad","board_epoch":epoch,"command":{"op":"key","key":1,"pressed":true,"revision":2}})
  if not await until(func():return lab.io_pending.is_empty() and lab.states[0].board.io_controls["board/pad"].keys==2):return
  print("PASS: reliable rejected ACK, accepted ACK, real shared keypad and rapid release over ENet")
  await create_timer(.3).timeout
 quit()
