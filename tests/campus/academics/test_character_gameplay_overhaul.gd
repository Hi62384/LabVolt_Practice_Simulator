extends SceneTree
## Actual Main/Faculty multi-turn acceptance with the provider explicitly off.
## The saved traces verify technical-unavailability and local simulation, not live-AI language quality.
const Profiles=preload("res://scripts/campus/academics/class_character_profile.gd")
const Roster=preload("res://scripts/campus/academics/faculty_roster.gd")
const Brain=preload("res://scripts/campus/academics/teacher_brain.gd")
const Mind=preload("res://scripts/campus/academics/character_mind.gd")
const Legacy=preload("res://tests/campus/academics/dossier/legacy_population_fixture.gd")
const Pipeline=preload("res://scripts/campus/academics/character_interaction.gd")
var checks:=0
var failures: Array[String]=[]
var traces: Array[Dictionary]=[]

func _initialize() -> void:call_deferred("run")

func check(ok: bool,message: String) -> void:
 checks+=1
 if not ok:failures.append(message);printerr("CHARACTER GAMEPLAY FAIL: "+message)

func same_saved_value(left: Variant,right: Variant) -> bool:
 # JSON restores integral values as floats and normalizes dictionary order.
 # Compare every stored field while allowing only numeric round-trip precision.
 if (left is int or left is float) and (right is int or right is float):return absf(float(left)-float(right))<=.000000001
 if left is Dictionary and right is Dictionary:
  if left.size()!=right.size():return false
  for key in left:
   if not right.has(key) or not same_saved_value(left[key],right[key]):return false
  return true
 if left is Array and right is Array:
  if left.size()!=right.size():return false
  for index in left.size():
   if not same_saved_value(left[index],right[index]):return false
  return true
 return left==right

func run() -> void:
 create_timer(60.).timeout.connect(func():quit(1))
 var game: Node=load("res://scenes/Main.tscn").instantiate();root.add_child(game)
 for frame in 4:await process_frame
 game.front.singleplayer_page();game.front._start_play(true)
 for frame in 2:await process_frame
 game.host_openai.enabled=false
 game.client_preferences.values.teacher_speech=false
 game.client_preferences.values.teacher_subtitles=false
 game.player.set_physics_process(false)
 game.faculty.set_process(false);game.lecture_classes.set_process(false)
 var faculty: Node=game.faculty
 check(game.front.in_game and faculty._sync_character_profile(),"Actual Singleplayer selects the host's character namespace")
 var identity:=str(game.school.local_identity)
 var shared:={"phase":"freeplay","course":"","title":"Offline character acceptance"}
 var strategies: Dictionary={}
 var apologies: Dictionary={}
 Legacy.seed(game.lecture_classes.classroom_students.population,24)
 for id in Roster.PEOPLE:
  var person:=Profiles.teacher(str(id))
  var prompts: Array[String]=["I'm excited to be here.","I don't think your teaching method is useful.","You're an idiot.","You are stupid.","You suck.","I've met rocks that teach better than you.","You're an idiot.","I'm sorry for insulting you."]
  var received:=0
  for question in prompts:
   var result: Dictionary=await faculty.generate_character_exchange(person,identity,shared,question)
   check(not result.is_empty() and not result.get("cancelled",false),"%s production exchange remains valid"%id)
   if result.is_empty():continue
   received+=1
   check(result.source in ["technical_unavailable","intentional_silence"] and str(result.line).is_empty(),"Offline recovery is explicitly identified")
   check(result.turn.get("interpretation",{}).get("event","")!="","Every perceived turn has an interpretation")
   strategies[result.turn.get("strategy","")]=true
   if question=="I'm sorry for insulting you.":apologies[str(result.line)]=true
   if question=="I don't think your teaching method is useful." and id in ["bill_nye","ms_bird_heart"]:
    check(not "insult" in str(result.line).to_lower() and not "that hurt" in str(result.line).to_lower(),"Reasoned disagreement is not answered as a personal insult")
   traces.append({"character":id,"name":person.name,"question":question,"speech":result.line,"strategy":result.turn.get("strategy",""),"emotion":result.emotion,"source":result.source,"event_id":result.event_id})
  check(faculty.brain.recall(str(id),identity).size()==received,"%s remembers every turn including silence"%id)
 check(strategies.size()>=5,"Actual production path selects diverse reactions across faculty")
 check(apologies.size()==1 and apologies.has(""),"Outages do not invent apology dialogue or feed generic speech to TTS")
 for question in ["I love college.","Do you think college is worth it?","Should I drop out?","I think escaping the matrix is stupid.","Your opinions about money are ridiculous.","I want to become financially independent.","I don't care about becoming rich."]:
  var result: Dictionary=await faculty.generate_character_exchange(Profiles.teacher("chad"),identity,shared,question)
  traces.append({"character":"chad","name":"Chad","question":question,"speech":result.line,"strategy":result.turn.get("strategy",""),"emotion":result.emotion,"source":result.source,"event_id":result.event_id})

 # Store more than the old twelve facts, then recreate the memory owner/mind.
 for index in 28:
  var result: Dictionary=await faculty.generate_character_exchange(Profiles.teacher("ms_bird_heart"),"memory-interview",shared,"I spent Saturday working on radio project %d with my aunt."%index)
  check(not result.is_empty(),"Long conversation turn %d completes"%index)
 var memory: Dictionary=faculty.brain.relationship("ms_bird_heart","memory-interview")
 check(memory.get("facts",{}).size()>=28,"Ordinary first-person experiences coexist beyond twelve facts")
 check(faculty.brain.save_memory()==OK,"Actual host memory saves successfully")
 var fresh_mind:=Mind.new();var fresh:=Brain.new();fresh.bind_mind(fresh_mind)
 check(fresh.set_host_profile(identity)==OK and fresh.load_memory(),"A fresh owner reloads the same host profile")
 check(fresh.recall("ms_bird_heart","memory-interview").size()==28,"All long-conversation exchanges survive reload")
 var restored: Dictionary=fresh.relationship("chad",identity)
 var original: Dictionary=faculty.brain.relationship("chad",identity)
 if not same_saved_value(restored,original):
  for field in original:
   if not same_saved_value(restored.get(field),original[field]):printerr("RELOAD DIFFERENCE ",field," saved=",str(original[field]).left(250)," loaded=",str(restored.get(field)).left(250))
 check(same_saved_value(restored,original),"All conflict, facts, episodes and relationship values survive reload")
 check(fresh.recall("chad","different-player").is_empty(),"A different speaker does not inherit the player's conversation")

 var room:="ac_lab"
 game.player.global_position=game.lecture_classes.signs[room].desk
 check(game.lecture_classes._start(room,{"kind":"lab","course_id":"ELM253","week":1,"difficulty":0})=="","Real class opens for assessment conversation")
 var activity: Dictionary=game.lecture_classes.classes[room]
 check(game.lecture_classes._sign(1,room)=="","Real profile signs into the class")
 activity.phase="lesson";activity.deadline=game.lecture_classes._now()+300.
 check(game.lecture_classes._begin_assignment(room,activity),"Real assessment is issued")
 var before:=JSON.stringify(activity.get("students",{}))
 var answers: Dictionary={}
 var students: Node=game.lecture_classes.classroom_students
 for index in range(6):
  var person: Dictionary=students.population.profile_for("campus_student_%d"%(12+index))
  var result: Dictionary=await faculty.generate_character_exchange(person,identity,activity,"Your major sounds completely useless.")
  check(not result.is_empty() and Pipeline.assessment_output_safe(str(result.line)),"Assessment reply preserves social behavior and protects solutions")
  answers[str(result.turn.get("strategy",""))]=true
  traces.append({"character":person.id,"name":person.name,"phase":"assignment","question":"Your major sounds completely useless.","speech":result.line,"strategy":result.turn.get("strategy",""),"emotion":result.emotion,"source":result.source,"event_id":result.event_id})
 check(answers.size()>=2,"Local student reactions remain varied while no AI speech is fabricated")
 check(JSON.stringify(activity.get("students",{}))==before,"Character conversation cannot change issued answers, submission state or marks")
 game.lecture_classes.classes.erase(room)
 var visit: Dictionary=faculty._ai_activity(room)
 var office: Dictionary=await faculty.generate_character_exchange(Profiles.teacher(str(visit.teacher)),identity,visit,"What do you do outside class?")
 check(not office.is_empty() and not office.get("cancelled",false),"Real office-hours activity passes the same shared-context validity gate")
 faculty._rotate(room)
 var exchange: Dictionary=faculty.lab_handoffs.get(room,{})
 check(not exchange.is_empty() and not exchange.get("waiting",true),"Offline staff handoff uses the shared pipeline without waiting on a provider")
 if not exchange.is_empty():
  var prior: int=faculty.brain.recall(str(exchange.outgoing),str(exchange.incoming)).size()
  check(prior>=1 and faculty.brain.recall(str(exchange.outgoing),str(exchange.incoming)).all(func(row):return str(row.teacher).is_empty()),"Outgoing shift perception is recorded without invented words")
  faculty._finish_lab_handoffs(int(exchange.due))
  check(faculty.current[room]==exchange.incoming,"The office-hours shift still changes instructors")
  check(faculty.brain.recall(str(exchange.incoming),str(exchange.outgoing)).all(func(row):return str(row.teacher).is_empty() and str(row.student).is_empty()),"An unspoken handoff creates no fabricated heard dialogue")
  check(faculty.brain.recall(str(exchange.outgoing),str(exchange.incoming)).size()==prior,"Outgoing colleague never hears an unspoken reply")
 faculty.open_conversation(room)
 check(faculty.character_debug_snapshot().get("persistence",{}).has("persistence_state"),"Selected host inspector exposes actual persistence state")
 var output:=OS.get_environment("LABVOLT_CHARACTER_OFFLINE_TRACE")
 if not output.is_empty():
  var file:=FileAccess.open(output,FileAccess.WRITE)
  check(file!=null,"Offline evidence output can be written")
  if file!=null:file.store_string(JSON.stringify({"kind":"observed technical unavailability and local simulation; not live AI","teachers":Roster.PEOPLE.size(),"students":6,"checks":checks,"failures":failures,"traces":traces},"  "));file.close()
 print("CHARACTER_GAMEPLAY_OVERHAUL %s checks=%d failures=%d teachers=%d students=6 (offline, not live AI)"%["PASS" if failures.is_empty() else "FAIL",checks,failures.size(),Roster.PEOPLE.size()])
 game.queue_free();await process_frame
 quit(0 if failures.is_empty() else 1)
