extends SceneTree
var game: Node
var failures := 0
var role := ""
func check(ok: bool,message: String):
 if not ok:failures+=1;printerr("FAIL SCHOOL NET: "+message)
 else:print("PASS SCHOOL NET: "+message)
func wait_for(predicate: Callable,seconds: float=15) -> bool:
 var end := Time.get_ticks_msec()+int(seconds*1000)
 while Time.get_ticks_msec()<end:
  if predicate.call():return true
  await create_timer(.05).timeout
 return false
func _initialize():call_deferred("run")
func run():
 role=OS.get_cmdline_user_args()[0]
 game=load("res://scenes/Main.tscn").instantiate()
 root.add_child(game)
 await create_timer(.3).timeout
 if role=="host":
  game.session.host_game("Instructor host",24919)
  game.school.start("Class",0)
  game.capture()
  game.school.project=preload("res://scripts/course_generator.gd").generate(0,0,42)
  check(await wait_for(func():return game.school.identities.size()==2),"early identity registered")
  game.school.advance(300)
  game.school.class_students[game.school.local_identity].done=true
  var student: String = game.school.identities.values().filter(func(token):return token!=game.school.local_identity)[0]
  check(await wait_for(func():
   return game.school.archive.get(student,{}).values().any(func(grade):return grade.get("assessment_id","")==game.school.assessment_id and grade.get("score",-1)==0.)
  ),"assignment disconnect records zero")
  check(await wait_for(func():return game.school.identities.values().has(student)),"same identity rejoined")
  await create_timer(2).timeout
 elif role=="client":
  game.session.join_game("127.0.0.1","Early student",24919)
  check(await wait_for(func():return game.school.phase=="assignment" and game.school.held(game.multiplayer.get_unique_id())!=0),"receives Class assignment")
  var id: int=game.school.held(game.multiplayer.get_unique_id())
  game.player.position=game.school.teacher_position+Vector3(0,0,-1)
  await create_timer(.3).timeout
  game.school.request({"op":"answer","id":id,"key":"0","value":"1"})
  game.school.request({"op":"stroke","id":id,"page":1,"points":[Vector2(.2,.3),Vector2(.5,.6)],"color":"b24c45","width":5.0})
  game.school.request({"op":"page","id":id,"page":1})
  await create_timer(2).timeout
  var token: String=game.school.local_identity
  game.session.leave()
  await create_timer(.7).timeout
  game.session.join_game("127.0.0.1","Early student",24919)
  check(await wait_for(func():return game.school.gradebook.values().any(func(grade):return grade.get("profile","")==token and grade.get("score",-1)==0.)),"reconnect receives zero grade")
  check(game.school.local_identity==token,"same profile restored")
  check(not game.school.papers.has(id),"original assignment is not reissued")
 print("SCHOOL NETWORK %s: %d failures"%[role,failures])
 game.session.leave()
 game.queue_free()
 await process_frame
 await process_frame
 quit(1 if failures else 0)
