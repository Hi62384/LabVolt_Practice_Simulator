extends SceneTree
const Profiles=preload("res://scripts/campus/academics/class_character_profile.gd")
var game
var deadline: int
func until(condition: Callable,label: String) -> bool:
 while Time.get_ticks_msec()<deadline:
  if condition.call():return true
  await create_timer(.05).timeout
 push_error("TEACHER FACING TIMEOUT "+label)
 quit(1);return false
func _initialize() -> void:call_deferred("run")
func run() -> void:
 var role: String=OS.get_cmdline_user_args()[0]
 game=load("res://scenes/Main.tscn").instantiate();root.add_child(game)
 for i in 4:await process_frame
 game.front.entered()
 game.client_preferences.values.teacher_speech=false
 game.client_preferences.values.teacher_subtitles=true
 deadline=Time.get_ticks_msec()+45000
 var room:="dc_lab"
 if role=="host":
  if game.session.host_game("Host",26319)!=OK:quit(1);return
  game.faculty.current[room]="mr_phillips";game.faculty._show_lab(room,"mr_phillips");game.faculty._publish()
  print("FACING_HOST_READY")
  if not await until(func():return game.session.roster.size()==2 and game.session.poses.size()>=1,"client joined"):return
  if not await until(func():return game.session.poses.values().any(func(p):return game.campus.registry.locate(p.get("position",Vector3.INF))==room),"client in lab"):return
  await create_timer(2.0).timeout
  var point: Vector3=game.campus.registry.anchor(room).origin
  game.faculty._publish_attention(room,"mr_phillips",point)
  if not game.faculty.attention.has(room):push_error("Host attention missing");quit(1);return
  var serial: int=game.faculty._next_speech(room)
  var person: Dictionary=Profiles.teacher("mr_phillips")
  var mood: String=game.faculty.character_mind.feel(person,"disruption",.65,Time.get_ticks_msec())
  game.faculty._character_gesture(room,game.faculty._model_for_room(room,"mr_phillips"),mood,false,"nod")
  game.faculty._show_reaction(room,"mr_phillips","Please check the circuit.",point,serial,2)
  game.faculty._broadcast_reaction(room,"mr_phillips","Please check the circuit.",point,serial,2)
  await create_timer(4.0).timeout
  print("FACING_HOST PASS")
 else:
  if game.session.join_game("127.0.0.1","Student",26319)!=OK:quit(1);return
  var point: Vector3=game.campus.registry.anchor(room).origin
  if not await until(func():
   game.player.global_position=point;game.session.send_pose({"position":point})
   return game.session.roster.size()==2 and game.faculty.current.get(room)=="mr_phillips"
  ,"roster and instructor"):return
  if not await until(func():return game.faculty.attention.has(room),"replicated attention"):return
  if not await until(func():return game.faculty.speech_player.last_serial.get(room,0)==1,"replicated speech order"):return
  if not game.faculty.speech_player.subtitles.has(room):push_error("Subtitle missing");quit(1);return
  var gesture: Dictionary=game.faculty.reaction_pose.get(room,{})
  var affect: Dictionary=gesture.get("affect",{})
  if gesture.get("gesture","")!="nod" or affect.size()!=16 or float(affect.get("anger",0.))<=0. or float(affect.get("irritation",0.))<=0.:
   push_error("Teacher mixed emotion or gesture was lost in the reaction RPC");quit(1);return
  var old_serial: int=game.faculty.speech_player.last_serial[room]
  game.faculty._reaction(room,"mr_phillips","Stale replay",point,old_serial,2)
  if game.faculty.speech_player.last_serial[room]!=old_serial:push_error("Stale event advanced order");quit(1);return
  var state: Dictionary=game.faculty.attention[room]
  var model: Node3D=state.model
  var expected:=atan2((model.get_parent_node_3d().to_local(point)-model.position).x,(model.get_parent_node_3d().to_local(point)-model.position).z)
  if absf(angle_difference(float(state.target),expected))>.01:push_error("Wrong facing target");quit(1);return
  await create_timer(.5).timeout
  if absf(angle_difference(model.rotation.y,expected))>.4:push_error("Client model did not turn");quit(1);return
  print("FACING_CLIENT PASS")
 quit(0)
