extends Node3D
const Roster=preload("res://scripts/campus/academics/faculty_roster.gd")
const Toon=preload("res://scripts/toon_character.gd")
const Dialogue=preload("res://scripts/campus/academics/teacher_dialogue.gd")
const TeacherAI=preload("res://scripts/campus/academics/teacher_ai.gd")
const Characters=preload("res://scripts/campus/academics/class_character_profile.gd")
const Classmates=preload("res://scripts/campus/academics/classroom_students.gd")
const Visuals=preload("res://scripts/campus/academics/classroom_visuals.gd")
const SpeechMath=preload("res://scripts/campus/academics/speech_math.gd")
const VoicePolicy=preload("res://scripts/campus/academics/teacher_voice_policy.gd")
const SpeechPlayer=preload("res://scripts/campus/academics/teacher_speech_player.gd")
const SpeechSynth=preload("res://scripts/campus/academics/teacher_speech_synth.gd")
const LECTURE_ROOMS := ["elm253_lecture","ety155_lecture","lecture_north_west","lecture_north_east","lecture_north_annex"]
const LectureDirector=preload("res://scripts/campus/academics/lecture_director.gd")
const ClassroomRoute=preload("res://scripts/campus/academics/classroom_teacher_route.gd")
const AdaptiveLesson=preload("res://scripts/campus/academics/adaptive_lesson.gd")
const InventionRubric=preload("res://scripts/campus/academics/invention_rubric.gd")
const ROTATE_SECONDS:=1200.0
var game: Node
var current:={}
var remaining:={"ac_lab":0.0,"dc_lab":0.0}
var lecture_models:={}
var lab_routes:={}
var lab_entries:={}
var lab_handoffs:={}
var classroom_routes:={}
var lecture_cues := {}
var lecture_clock := 0.0
var conversation_scroll: ScrollContainer
var conversation_actions := {}
var classroom_homes:={}
var classroom_route_seen:={}
var classroom_group_visits:={}
var classroom_motion_seq:={}
var classroom_remote_seq:={}
var classroom_motion_clock:=0.0
var classroom_remote:={}
var classroom_last_positions:={}
var publish_time:=0.0
var lunch: Node3D
var lunch_time:=0.0
var lunch_patrol=preload("res://scripts/campus/academics/food_patrol.gd").new()
var lunch_remote:=Vector3(18.8,0,33.0)
var lunch_walking:=false
var lunch_publish:=0.0
var rng:=RandomNumberGenerator.new()
var conversation: PanelContainer
var conversation_text: Label
var conversation_name: Label
var conversation_input: LineEdit
var ask_button: Button
var record_button: Button
var record_player: AudioStreamPlayer
var record_samples:=PackedByteArray()
var recording:=false
var record_started:=0
var record_phase:=0.0
var conversation_room:=""
var conversation_student:=""
var conversation_class:=""
var voice_room:=""
var voice_class:=""
var voice_student:=""
var voice_until:=0
var voice_invited:=false
var voice_hint: Label
var voice_recognizer=preload("res://scripts/campus/computers/TeacherVoiceActivity.cs").new()
var last_dialogue:={}
var ai_busy:={}
var questions: Array[Dictionary]=[]
var ai_stage:={}
var lesson_feedback:={}
var brain=preload("res://scripts/campus/academics/teacher_brain.gd").new()
const CharacterMind=preload("res://scripts/campus/academics/character_mind.gd")
const CharacterMotion=preload("res://scripts/campus/academics/character_motion.gd")
var character_mind:=CharacterMind.new()
var appearance_catalog: Dictionary={}
var reaction_labels:={}
var reaction_until:={}
var speech_player: Node
var speech_synth: Node
var speech_serial:={}
var received_voice:={}
var pending_voice:={}
var classmate_voice_serials:={}
var class_calls:={}
var classroom_phase:={}
var attention:={}
var reaction_pose:={}
var class_overlap:={}
var memory_clock:=0.0
var memory_error: Error=OK
var seat_watch: Dictionary={}
var verified_incidents: Array[Dictionary]=[]
var seat_watch_clock:=0.0
signal classroom_disruption(room: String,teacher: String)
func build(owner: Node) -> void:
 game=owner;rng.randomize()
 var events: Node=game.lecture_classes.classroom_events
 if is_instance_valid(events):classroom_disruption.connect(events.on_teacher_disruption)
 if multiplayer.is_server() and not brain.load_memory():
  memory_error=ERR_FILE_CORRUPT
  push_warning("Teacher relationship save could not be loaded; original files are preserved. New observations cannot be saved until recovery.")
 _build_conversation_ui()
 speech_player=SpeechPlayer.new();speech_player.name="TeacherSpeechPlayer";add_child(speech_player)
 speech_synth=SpeechSynth.new();speech_synth.name="TeacherSpeechSynth";add_child(speech_synth)
 speech_synth.completed.connect(_speech_completed)
 lunch=_make_model("ms_lunch");lunch.name="MsLunch";add_child(lunch)
 lunch.position=lunch_patrol.position
 _tag_name(lunch,"Ms Lunch")
 if multiplayer.is_server():
  _rotate("ac_lab");_rotate("dc_lab")
 game.session.roster_changed.connect(_publish)
 game.session.roster_changed.connect(_prune_dialogue)
 game.session.chat_received.connect(_on_player_message)
 game.session.leaving.connect(_save_memory)
 game.session.leaving.connect(_clear_speech)
 game.session.restarted.connect(_clear_speech)
func _clear_speech() -> void:
 _cancel_recording()
 _stop_voice_conversation()
 ai_stage.clear()
 character_mind.moods.clear()
 character_mind.boundaries.clear()
 lesson_feedback.clear()
 for room in ["ac_lab","dc_lab"]:_hide_lab(room)
 lab_routes.clear();lab_entries.clear();lab_handoffs.clear()
 Roster.GENERATED.clear()
 ai_busy.clear();questions.clear();ai_stage.clear()
 if is_instance_valid(speech_player):speech_player.clear_session()
 if is_instance_valid(speech_synth):speech_synth.clear_session()
 speech_serial.clear()
 received_voice.clear()
 pending_voice.clear()
 classmate_voice_serials.clear()
 class_calls.clear()
 classroom_phase.clear()
 for room in reaction_pose.keys():_clear_reaction_pose(str(room))
 class_overlap.clear()
 seat_watch.clear();seat_watch_clock=0.0
 verified_incidents.clear()
 classroom_routes.clear();classroom_route_seen.clear();classroom_group_visits.clear();classroom_remote.clear();classroom_motion_seq.clear();classroom_remote_seq.clear();classroom_last_positions.clear()
func _save_memory() -> void:
 if not multiplayer.is_server():return
 if brain.memory_blocked and not brain.memory_dirty:
  if brain.retry_memory_load():memory_error=OK
 var error: Error=brain.save_memory()
 if error!=memory_error:
  if error!=OK:push_warning("Teacher relationship save failed (%d); observations remain in memory for retry."%error)
  memory_error=error
func _pick(courses: Array,excluded: Array) -> String:
 var candidates:=Roster.eligible(courses,excluded)
 return "" if candidates.is_empty() else str(candidates[rng.randi_range(0,candidates.size()-1)])
func pick_lecture(course: String) -> String:
 var excluded: Array=current.values()
 for activity in game.lecture_classes.classes.values():
  var id:=str(activity.get("teacher",""))
  if not id.is_empty() and id not in excluded:excluded.append(id)
 return _pick([course],excluded)
func generate_teacher(course: String,style: String) -> Dictionary:
 if not multiplayer.is_server() or course not in ["MTH147","MTH255","ETY155","ELM253","DGS266"] or style.strip_edges().length()<3 or style.length()>120:return {"ok":false,"error":"Choose a course and describe a teaching style."}
 if not game.host_openai.enabled or not game.host_openai.configured():return {"ok":false,"error":"Enable the host OpenAI connection first."}
 var prompt:="Create one original fictional campus instructor for course %s with this teaching style: %s. Return only compact JSON with keys name and style. Name must be 3-32 letters/spaces; style must be 3-120 characters. Do not use a real person's name, copyrighted character, or a living person's likeness. No markdown."%[course,style]
 var result: Dictionary=await game.host_openai.respond(prompt)
 if not result.get("ok",false):return result
 var parsed: Variant=JSON.parse_string(str(result.get("text","")))
 if not parsed is Dictionary:return {"ok":false,"error":"The generated instructor profile was invalid. Try again."}
 var id: String="generated_"+Crypto.new().generate_random_bytes(8).hex_encode()
 var profile:={"name":str(parsed.get("name","")),"course":course,"style":str(parsed.get("style","")),"appearance":{}}
 if not Roster.add_generated(id,profile):return {"ok":false,"error":"The generated profile was invalid or the session has reached 12 generated instructors."}
 _publish()
 return {"ok":true,"name":str(Roster.entry(id).name),"id":id}
func _rotate(room: String) -> void:
 var excluded: Array=current.values()
 for exchange in lab_handoffs.values():excluded.append(exchange.incoming)
 for activity in game.lecture_classes.classes.values():
  var id:=str(activity.get("teacher",""))
  if not id.is_empty() and id not in excluded:excluded.append(id)
 var id:=_pick(["ELM253"] if room=="ac_lab" else ["ETY155","DGS266"],excluded)
 if id.is_empty():return
 var visit:=_lab_visit(room)
 if visit.get("phase","")=="office_hours":
  if lesson_question_active(room):
   remaining[room]=10.
   return
  var outgoing: String=visit.teacher
  var name_to_address:=str(Roster.entry(id).name)
  var handoff:="Good to see you again, %s. Are you ready to take the next office-hours shift?"%name_to_address if int(brain.relationship(outgoing,id).familiarity)>0 else "%s, can you take over office hours? I'm heading out."%name_to_address
  lab_handoffs[room]={"outgoing":outgoing,"incoming":id,"due":Time.get_ticks_msec()+4400,"handoff":handoff}
  remaining[room]=ROTATE_SECONDS
  _staff_line(room,outgoing,handoff)
  return
 _switch_lab_instructor(room,id)

func _switch_lab_instructor(room: String,id: String) -> void:
 current[room]=id;remaining[room]=ROTATE_SECONDS
 _hide_lab(room)
 _publish()

func _finish_lab_handoffs(now: int) -> void:
 for room in lab_handoffs.keys():
  var exchange: Dictionary=lab_handoffs[room]
  var visit:=_lab_visit(room)
  var incoming: String=exchange.incoming
  if visit.get("teacher","")!=exchange.outgoing or _scheduled_teacher(incoming) or incoming in current.values():
   lab_handoffs.erase(room)
   remaining[room]=minf(float(remaining[room]),60.)
   continue
  if now<int(exchange.due) or lesson_question_active(room):continue
  lab_handoffs.erase(room)
  _switch_lab_instructor(room,incoming)
  _sync_lab_teachers()
  var outgoing: String=exchange.outgoing
  var response:="I've got it, %s. I'll help anyone who comes in with a bench question."%str(Roster.entry(outgoing).name)
  _staff_line(room,incoming,response)
  var timestamp:=int(Time.get_unix_time_from_system())
  brain.remember_conversation(outgoing,incoming,response,exchange.handoff,timestamp)
  brain.remember_conversation(incoming,outgoing,exchange.handoff,response,timestamp)

func _staff_line(room: String,id: String,line: String) -> void:
 var point:=_teacher_position(room)
 var serial:=_next_speech(room)
 _show_reaction(room,id,line,point,serial,1)
 _broadcast_reaction(room,id,line,point,serial,1)
func _show_lab(room: String,id: String,animated: bool=false) -> void:
 if not Roster.has(id):return
 _clear_reaction_pose(room)
 if is_instance_valid(speech_player):speech_player.cancel(room)
 if is_instance_valid(speech_synth):speech_synth.cancel(room)
 var root: Node3D=game.school_world.teacher if room=="ac_lab" else game.school_world.dc_instructor
 var old: Node3D=root.get_node_or_null("InstructorModel")
 if is_instance_valid(old) and not old.is_queued_for_deletion() and str(old.get_meta("faculty_id",""))==id:
  old.visible=true
  return
 if old==null:
  for child in root.get_children():
   if child is Node3D and not child is CollisionObject3D:old=child;break
 if old!=null:root.remove_child(old);old.queue_free()
 for child in root.get_children():
  if child is CollisionObject3D:child.collision_layer=0
 var model:=_make_model(id);model.name="InstructorModel";model.set_meta("faculty_id",id);model.visible=true;model.rotation.y=PI if room=="ac_lab" else 0.0
 root.add_child(model);root.move_child(model,0)
 _tag_name(model,str(Roster.entry(id).name))
 var target:=StaticBody3D.new();target.name="ClassInstructorTarget";target.collision_layer=4;target.collision_mask=0
 target.set_meta("role","faculty_teacher");target.set_meta("room",room);target.set_meta("label",str(Roster.entry(id).name))
 var hit:=CollisionShape3D.new();var shape:=CapsuleShape3D.new();shape.radius=.28;shape.height=1.75;hit.shape=shape;hit.position.y=.9;target.add_child(hit);model.add_child(target)
 if animated:
  var definition: Dictionary=game.campus.registry.get_room(room)
  var center: Vector3=game.campus.registry.vector(definition.center)
  var door: Vector3=game.campus.registry.vector(definition.door)
  var inward: Vector3=(center-door).normalized()
  var entry: Vector3=door+inward*1.7
  var home:=Vector3(model.global_position.x,entry.y,model.global_position.z)
  var path:=ClassroomRoute.plan(game,room,entry,home,0.0)
  if not path.is_empty():
   lab_entries[room]=entry
   model.global_position=entry
   lab_routes[room]={"path":path,"departing":false,"index":0}
func _hide_lab(room: String) -> void:
 if room not in ["ac_lab","dc_lab"] or not is_instance_valid(game) or not is_instance_valid(game.school_world):return
 _clear_reaction_pose(room)
 if is_instance_valid(speech_player):speech_player.cancel(room)
 if is_instance_valid(speech_synth):speech_synth.cancel(room)
 var root: Node3D=game.school_world.teacher if room=="ac_lab" else game.school_world.dc_instructor
 if not is_instance_valid(root):return
 var current_model:=root.get_node_or_null("InstructorModel")
 if is_instance_valid(current_model):
  root.remove_child(current_model)
  current_model.queue_free()
 else:
  for child in root.get_children():
   if child is Node3D and not child is CollisionObject3D:child.visible=false
 for child in root.get_children():
  if child is CollisionObject3D:child.collision_layer=0
 if is_instance_valid(reaction_labels.get(room)):reaction_labels[room].queue_free()
 reaction_labels.erase(room);reaction_until.erase(room)
 lab_routes.erase(room);lab_entries.erase(room)
 classroom_remote.erase(room)
 classroom_last_positions.erase(room)
func _lab_activity(room: String) -> Dictionary:
 var activity: Dictionary=game.lecture_classes.classes.get(room,{}) if multiplayer.is_server() else game.lecture_classes.public_classes.get(room,{})
 return _formal_activity(room) if activity.is_empty() else activity

func _lab_visit(room: String) -> Dictionary:
 var activity:=_lab_activity(room)
 if not activity.is_empty() or not _freeplay_lab_available(room):return activity
 var id:=str(current.get(room,""))
 if not Roster.has(id) or _scheduled_teacher(id):return {}
 var course: String="ELM253" if room=="ac_lab" else "ETY155"
 if room=="dc_lab" and course not in Roster.entry(id).get("courses",[]):course="DGS266"
 return {"id":"office:%s:%s"%[room,id],"teacher":id,"phase":"office_hours","course":course,"ai_teaching":false}

func _scheduled_teacher(id: String) -> bool:
 var active: Dictionary=game.lecture_classes.classes if multiplayer.is_server() else game.lecture_classes.public_classes
 for scheduled in active.values():
  if scheduled.get("teacher","")==id:return true
 return false

func _formal_activity(room: String) -> Dictionary:
 var school: Node=game.school
 if not school.formal_active() or school.activity.get("room",{}).get("id","")!=room:return {}
 var course:=str(school.activity.get("course_id",""))
 var instructor:=str(school.activity.get("teacher",""))
 if not Roster.has(instructor):
  var eligible: Array=Roster.eligible([course])
  if eligible.is_empty():return {}
  instructor=str(eligible[0])
 return {"id":school.assessment_id,"teacher":instructor,"phase":school.phase,"course":course,"ai_teaching":school.activity.get("ai_teaching",false),
  "week":school.activity.get("week",0),"title":school.project.get("title",course)}
func _sync_lab_teachers() -> void:
 for room in ["ac_lab","dc_lab"]:
  var activity:=_lab_visit(room)
  var id:=str(activity.get("teacher",""))
  var root: Node3D=game.school_world.teacher if room=="ac_lab" else game.school_world.dc_instructor
  var model:=root.get_node_or_null("InstructorModel")
  if Roster.has(id):
   if not is_instance_valid(model) or model.is_queued_for_deletion() or str(model.get_meta("faculty_id",""))!=id or lab_routes.get(room,{}).get("departing",false):
    _hide_lab(room)
    _show_lab(room,id,bool(activity.get("ai_teaching",false)) or activity.get("phase","")=="office_hours")
  elif is_instance_valid(model) and not lab_routes.get(room,{}).get("departing",false):
   if not lab_entries.has(room):_hide_lab(room);continue
   var path:=ClassroomRoute.plan(game,room,model.global_position,lab_entries[room],0.0)
   if path.is_empty():_hide_lab(room);continue
   var target:=model.get_node_or_null("ClassInstructorTarget") as CollisionObject3D
   if is_instance_valid(target):target.collision_layer=0
   speech_player.cancel(room)
   speech_synth.cancel(room)
   lab_routes[room]={"path":path,"departing":true,"index":0}

func _step_lab_routes(delta: float) -> void:
 for room in lab_routes.keys():
  var root: Node3D=game.school_world.teacher if room=="ac_lab" else game.school_world.dc_instructor
  var model:=root.get_node_or_null("InstructorModel") as Node3D
  if not is_instance_valid(model):lab_routes.erase(room);continue
  var route: Dictionary=lab_routes[room]
  if not multiplayer.is_server() and not route.departing and classroom_remote.has(room):continue
  if int(route.index)>=route.path.size():
   if route.has("return_path"):
    if not route.has("pause_until"):route.pause_until=Time.get_ticks_msec()+2000
    if Time.get_ticks_msec()<int(route.pause_until):continue
    route.path=route.return_path
    route.erase("return_path")
    route.index=0
    continue
   if route.departing:_hide_lab(room)
   else:
    lab_routes.erase(room)
    preload("res://scripts/avatar_model.gd").animate(model,false)
   continue
  var target: Vector3=route.path[route.index]
  var offset:=target-model.global_position
  if offset.length()<.07:route.index+=1;continue
  var next:=model.global_position+offset.limit_length(delta*1.3)
  if not ClassroomRoute.clear_step(game,model.global_position,next):
   route["blocked"]=float(route.get("blocked",0.0))+delta
   if route.blocked>=4.0:
    if route.departing:_hide_lab(room)
    else:
     lab_routes.erase(room)
     preload("res://scripts/avatar_model.gd").animate(model,false)
   continue
  route.blocked=0.0
  model.global_position=next
  model.rotation.y=lerp_angle(model.rotation.y,atan2(offset.x,offset.z),clampf(delta*8.0,0.0,1.0))
  preload("res://scripts/avatar_model.gd").animate(model,true)
func _freeplay_lab_available(room: String) -> bool:
 return game.school.mode in ["Freeplay","Creative Freeplay","Open Lab"] and not game.school.formal_active() and _lab_activity(room).is_empty()
func _make_model(id: String) -> Node3D:
 var appearance:=Roster.config(id)
 var model:=Toon.build(appearance)
 model.set_meta("character_outfit",_outfit_color(Color.html(str(appearance.top)))+" "+str(appearance.outfit))
 if id in ["bradley","mr_bro"]:
  var head:=model.find_child("Head",true,false) as Node3D
  if head:
   var shade:=Toon.material("18262b",.25)
   for side in [-1,1]:Toon.ellipsoid(head,Vector3(side*.087,.016,.214),Vector3(.065,.054,.008),shade,"SunglassLens")
 if id=="ms_lunch":
  for part in ["ArmL","ArmR"]:
   var arm:=model.find_child(part,true,false) as Node3D
   if arm:
    var sleeve:=arm.find_child("Sleeve",true,false) as MeshInstance3D
    if sleeve:sleeve.scale=Vector3(1.65,1.0,1.55)
 return model

func _tag_name(parent: Node3D,value: String) -> void:
 var label_height := 2.05
 var head := parent.find_child("Head",true,false) as Node3D
 if is_instance_valid(head):
  var top := -INF
  for part in head.find_children("*","MeshInstance3D",true,false):
   var mesh := part as MeshInstance3D
   var bounds: AABB = parent.global_transform.affine_inverse() * mesh.global_transform * mesh.get_aabb()
   top = maxf(top, bounds.end.y)
  if is_finite(top): label_height = top + .15
 var label:=Label3D.new();label.name="FacultyName";label.text=value;label.position.y=label_height;label.billboard=BaseMaterial3D.BILLBOARD_ENABLED;label.pixel_size=.003;label.font_size=36;label.outline_size=5;label.visibility_range_end=12;parent.add_child(label)
func _publish() -> void:
 if not multiplayer.is_server() or not game.session.online:return
 for peer in game.session.roster:
  if int(peer)!=multiplayer.get_unique_id() and game.session.peer_connected_now(int(peer)):receive.rpc_id(int(peer),current,Roster.GENERATED)
@rpc("authority","call_remote","reliable")
func receive(value: Dictionary,generated: Dictionary={}) -> void:
 for id in generated:
  if not Roster.has(str(id)):
   var data: Dictionary=generated[id]
   var courses: Array=data.get("courses",[])
   if not courses.is_empty():Roster.add_generated(str(id),{"name":data.get("name",""),"course":courses[0],"style":data.get("style",""),"appearance":data.get("appearance",{})})
 for room in ["ac_lab","dc_lab"]:
  var id:=str(value.get(room,""))
  if Roster.has(id):current[room]=id
 _sync_lab_teachers()
func _process(delta: float) -> void:
 if not is_instance_valid(game):return
 _record_step()
 _voice_conversation_step()
 _sync_lab_teachers()
 _step_lab_routes(delta)
 if multiplayer.is_server():
  _next_question()
  if not lab_handoffs.is_empty():_finish_lab_handoffs(Time.get_ticks_msec())
  memory_clock+=delta
  if memory_clock>=10.0:memory_clock=0;_save_memory()
  for room in ["ac_lab","dc_lab"]:
   if game.lecture_classes.classes.has(room) or (game.school.formal_active() and str(game.school.activity.get("room",{}).get("id",""))==room):continue
   remaining[room]=float(remaining[room])-delta
   if remaining[room]<=0:_rotate(room)
  publish_time+=delta
  if publish_time>=5.0:publish_time=0;_publish()
 _sync_lectures()
 lecture_clock += delta
 if multiplayer.is_server() and lecture_clock >= 0.5:
  lecture_clock = 0.0
  _direct_lectures()
 _step_classroom_routes(delta)
 _animate_lecture_movement()
 if multiplayer.is_server():
  seat_watch_clock+=delta
  if seat_watch_clock>=1.0:
   seat_watch_clock=0.0
   _observe_classroom_seats()
 _prune_class_calls()
 for room in reaction_until.keys():
  if Time.get_ticks_msec()>=int(reaction_until[room]):
   if is_instance_valid(reaction_labels.get(room)):reaction_labels[room].queue_free()
   reaction_labels.erase(room);reaction_until.erase(room)
 for room in attention.keys():
  var state: Dictionary=attention[room]
  var model: Variant=state.get("model")
  if not is_instance_valid(model):attention.erase(room);continue
  var target: float=float(state.get("target",0.0)) if Time.get_ticks_msec()<int(state.get("until",0)) else float(state.get("rest",0.0))
  model.rotation.y=lerp_angle(model.rotation.y,target,minf(1.0,delta*5.0))
  if Time.get_ticks_msec()>=int(state.get("until",0)) and absf(angle_difference(model.rotation.y,target))<.01:
   model.rotation.y=target;attention.erase(room)
 for room in reaction_pose.keys():
  var pose: Dictionary=reaction_pose[room]
  var model: Node3D=pose.get("model") as Node3D
  if not is_instance_valid(model):reaction_pose.erase(room);continue
  var active:=Time.get_ticks_msec()<int(pose.get("until",0))
  CharacterMotion.express(model,str(pose.get("mood","steady")) if active else "steady",delta,
   str(pose.get("gesture","")) if active else "",float(pose.get("until",0)-Time.get_ticks_msec())*-.001+2.2,pose.get("point",Vector3.INF))
  if not active and Time.get_ticks_msec()>=int(pose.get("until",0))+350:_clear_reaction_pose(room)
 _update_food_patrol(delta)

func _update_food_patrol(delta: float) -> void:
 if multiplayer.is_server():
  var start: Vector3=lunch_patrol.position+Vector3.UP*.8
  var end: Vector3=start+Vector3(0,0,lunch_patrol.direction*.7)
  var query:=PhysicsRayQueryParameters3D.create(start,end,1)
  var blocked:=not get_world_3d().direct_space_state.intersect_ray(query).is_empty()
  lunch_walking=lunch_patrol.advance(minf(delta,.1),blocked)
  lunch.position=lunch_patrol.position
  lunch_publish+=delta
  if game.session.online and lunch_publish>=.5:
   lunch_publish=0.0
   for peer in game.session.roster:
    if int(peer)!=multiplayer.get_unique_id() and game.session.peer_connected_now(int(peer)):
     _receive_patrol.rpc_id(int(peer),lunch.position,lunch_patrol.direction,lunch_walking)
 else:
  lunch.position=lunch.position.lerp(lunch_remote,minf(1.0,delta*5.0))
 if lunch_walking:
  var facing:=0.0 if lunch_patrol.direction>0 else PI
  lunch.rotation.y=lerp_angle(lunch.rotation.y,facing,minf(1.0,delta*5.0))
 preload("res://scripts/avatar_model.gd").animate(lunch,lunch_walking)

@rpc("authority","call_remote","unreliable_ordered")
func _receive_patrol(position: Vector3,direction: float,walking: bool) -> void:
 if not position.is_finite() or absf(position.x-18.8)>.1 or absf(position.y)>.1 or position.z<18.0 or position.z>48.0 or absf(direction)!=1.0:return
 lunch_remote=position;lunch_patrol.direction=direction;lunch_walking=walking
func _sync_lectures() -> void:
 var active: Dictionary=game.lecture_classes.public_classes
 var formal_room:=str(game.school.activity.get("room",{}).get("id",""))
 if formal_room in LECTURE_ROOMS and not active.has(formal_room):
  var formal:=_formal_activity(formal_room)
  if not formal.is_empty():
   active=active.duplicate()
   active[formal_room]=formal
 for room in lecture_models.keys():
  if not active.has(room) or str(active[room].get("teacher",""))!=str(lecture_models[room].get_meta("faculty_id","")):
   classroom_routes.erase(room);classroom_homes.erase(room);classroom_route_seen.erase(room);classroom_group_visits.erase(room);classroom_remote.erase(room);classroom_motion_seq.erase(room);classroom_remote_seq.erase(room);classroom_last_positions.erase(room)
   _clear_reaction_pose(room)
   if is_instance_valid(speech_player):speech_player.cancel(room)
   if is_instance_valid(speech_synth):speech_synth.cancel(room)
   lecture_models[room].queue_free();lecture_models.erase(room)
 for room in active:
  var phase: String=str(active[room].get("phase",""))
  if str(classroom_phase.get(room,""))=="lesson" and phase!="lesson" and is_instance_valid(speech_player):speech_player.cancel(room)
  if str(classroom_phase.get(room,""))=="lesson" and phase!="lesson" and is_instance_valid(speech_synth):speech_synth.cancel(room)
  if str(classroom_phase.get(room,""))=="lesson" and phase!="lesson":_clear_reaction_pose(room)
  if phase!="lesson":class_overlap.erase(room)
  classroom_phase[room]=phase
  if room not in LECTURE_ROOMS or lecture_models.has(room):continue
  var id:=str(active[room].get("teacher",""))
  if not Roster.has(id):continue
  var model:=_make_model(id);model.name="LectureTeacher";model.set_meta("faculty_id",id)
  var info: Dictionary = game.campus.registry.get_room(room)
  var center: Vector3 = game.campus.registry.vector(info.center)
  var desk: Vector3 = game.lecture_classes.signs[room].desk
  var toward_center := signf(center.x-desk.x)
  var candidates := [desk + Vector3(toward_center*1.45,0,0), desk + Vector3(0,0,-1.05), desk + Vector3(-toward_center*1.45,0,0)]
  model.position = Vector3(candidates[0].x, center.y, candidates[0].z)
  for candidate in candidates:
   var at := Vector3(candidate.x, center.y, candidate.z)
   if game.campus.registry.room_contains(room, at) and ClassroomRoute.clear_step(game, at, at):
    model.position = at
    break
  _ground_standing_model(model)
  add_child(model);_tag_name(model,str(Roster.entry(id).name));lecture_models[room]=model
  classroom_homes[room]=model.global_position
  var target:=StaticBody3D.new();target.collision_layer=4;target.collision_mask=0;target.set_meta("role","faculty_teacher");target.set_meta("room",room);target.set_meta("label",str(Roster.entry(id).name));model.add_child(target)
  var hit:=CollisionShape3D.new();var capsule:=CapsuleShape3D.new();capsule.radius=.3;capsule.height=1.7;hit.shape=capsule;hit.position.y=.85;target.add_child(hit)
 for room in classroom_phase.keys():
  if not active.has(room):_clear_reaction_pose(room);class_overlap.erase(room);classroom_phase.erase(room)

func _ground_standing_model(model: Node3D) -> void:
 var sole_y := INF
 for leg_name in ["LegL", "LegR"]:
  var leg := model.get_node_or_null(leg_name) as Node3D
  if leg == null: continue
  for part in leg.get_children():
   if part is MeshInstance3D and str(part.get_meta("toon_part", part.name)).begins_with("Sole"):
    var bounds: AABB = leg.transform * part.transform * part.get_aabb()
    sole_y = minf(sole_y, bounds.position.y)
 if not is_finite(sole_y): return
 for part in model.get_children():
  if part is Node3D: part.position.y -= sole_y

func _direct_lectures() -> void:
 var active_ids: Array[String]=[str(game.school.assessment_id)]
 for value in game.lecture_classes.classes.values():active_ids.append(str(value.id))
 for key in lesson_feedback.keys():
  if key not in active_ids:lesson_feedback.erase(key)
 for room in lecture_cues.keys():
  if not game.lecture_classes.classes.has(room): lecture_cues.erase(room)
 for room in game.lecture_classes.classes:
  var activity: Dictionary = game.lecture_classes.classes[room]
  var phase := str(activity.get("phase",""))
  var teacher := str(activity.get("teacher",""))
  if not Roster.has(teacher): continue
  var panel: Node = game.lecture_classes.classroom_events
  var current_event: Dictionary = panel.service.rooms.get(room,{}) if is_instance_valid(panel) and is_instance_valid(panel.service) else {}
  var now: float = game.lecture_classes._now()
  var cue: Dictionary
  if phase == "arrival":
   cue = {"key":"arrival", "text":"%s Sign in for %s and take a seat."%[Characters.teacher(teacher).lines.greeting,activity.course]}
  elif phase == "lesson":
   if lesson_question_active(room):continue
   if activity.get("ai_teaching",false) and current_event.is_empty():
    _maybe_ai_lesson(room)
    var board: Dictionary=game.lecture_classes._stage(activity)
    var lesson_time: float=game.lecture_classes.lesson_duration(activity)-maxf(0.,float(activity.deadline)-now)
    if activity.get("ai_waiting",false) or lesson_time-float(board.get("start_seconds",0.))<9.:continue
   if not current_event.is_empty():
    if now >= float(current_event.get("open_at",0)): continue
    cue = {"key":"practice:"+str(current_event.round.event_id), "text":"Try this next question. Show your reasoning, then submit."}
   else:
    cue = _character_lecture_cue(activity,game.lecture_classes._stage(activity),now,teacher)
  if cue.is_empty(): continue
  var key := str(activity.id)+":"+str(cue.key)
  if lecture_cues.get(room,"") == key: continue
  var point := _teacher_position(room)
  if not point.is_finite(): continue
  lecture_cues[room] = key
  var serial := _next_speech(room)
  var text := str(cue.text).left(220)
  _show_reaction(room,teacher,text,point,serial,2)
  _broadcast_reaction(room,teacher,text,point,serial,2)
  if phase == "lesson" and cue.has("anchor") and lecture_models.has(room):
   var board: Node3D = game.lecture_classes.signs[room].board
   var goal := Vector3(board.global_position.x + float(cue.anchor), classroom_homes[room].y, board.global_position.z + 1.7)
   _request_classroom_route(room, teacher, "lecture:"+key, goal, 0.0, 0, Time.get_ticks_msec()+24000)

func _maybe_ai_lesson(room: String) -> void:
 var activity: Dictionary=game.lecture_classes.classes.get(room,{})
 if activity.get("phase","")!="lesson" or not activity.get("ai_teaching",false):return
 var board: Dictionary=game.lecture_classes._stage(activity)
 _queue_ai_lesson(room,activity,activity,board,false)

func _character_lecture_cue(activity: Dictionary,board: Dictionary,now: float,id: String) -> Dictionary:
 var person:=Characters.teacher(id)
 var preferences: Dictionary=Dialogue.personalities().get(id,{}).duplicate()
 preferences.talkativeness=clampf(float(person.talk)*.65+float(person.traits.teaching_effort)*.35,0.,1.)
 preferences.opening=person.lines.greeting
 preferences.check_in="Show me your reasoning. " if float(person.strictness)>=.65 else ("Try this one with me. " if float(person.traits.warmth)>.7 else "Check your notes against this. ")
 return LectureDirector.cue(activity,board,now,preferences)

func formal_lesson_ready() -> bool:
 var school: Node=game.school
 var state: Dictionary=school.activity
 if school.phase!="lesson" or not state.get("ai_teaching",false):return true
 var room:=str(state.get("room",{}).get("id",""))
 var now:=Time.get_ticks_msec()
 var previous:=int(state.get("question_pause_sample",now))
 state.question_pause_sample=now
 if int(state.get("question_pause_ms",0))<90000 and lesson_question_active(room):
  state.question_pause_ms=int(state.get("question_pause_ms",0))+clampi(now-previous,0,500)
  return false
 var activity:=_formal_activity(room)
 var board: Dictionary=school.teaching_stage()
 _queue_ai_lesson(room,activity,state,board,true)
 return not state.get("ai_waiting",false)

func _queue_ai_lesson(room: String,activity: Dictionary,state: Dictionary,board: Dictionary,formal: bool) -> void:
 var step: Dictionary=board.get("teaching_step",{})
 var feedback: Dictionary=lesson_feedback.get(str(activity.get("id","")),{})
 var signals: Array=feedback.get("understanding",{}).values()
 board["ready_students"]=signals.count("ready")
 board["clarification_requests"]=signals.count("clarify")
 var key:=str(activity.get("id",""))+":"+str(step.get("index",board.get("index",0)))
 if step.get("key","")=="check" and feedback.get("revisit",false):key+=":clarify"
 if str(ai_stage.get(room,""))==key:return
 state.ai_waiting=true
 var client: Node=game.host_openai
 var waiting_since: int=state.get_or_add("ai_wait_started",Time.get_ticks_msec())
 if not is_instance_valid(client) or not client.ready_for_class() or (client.busy and Time.get_ticks_msec()-waiting_since>7500):
  ai_stage[room]=key
  _finish_lesson_cue(room,activity,state,key,board,formal,"")
  return
 if client.busy:return
 ai_stage[room]=key
 state.ai_status="Waiting for the instructor…"
 _generate_ai_lesson(room,activity,state,key,board,formal)

func _generate_ai_lesson(room: String,activity: Dictionary,state: Dictionary,key: String,board: Dictionary,formal: bool) -> void:
 var id:=str(activity.get("teacher",""))
 var class_id:=str(activity.get("id",""))
 var person:=Characters.teacher(id)
 var mood:=character_mind.emotion(person,Time.get_ticks_msec())
 var instructions:=CharacterMind.instructions(person,mood,"lesson")+" Teach the current point in your own teaching style. Use the supplied board and teaching step. Respond in at most 320 characters."
 var step: Dictionary=board.get("teaching_step",{})
 var focus:=str(step.get("prompt","Explain the current board in one concrete example.")).left(250)
 if step.get("key","")=="check" and int(board.get("clarification_requests",0))>0:
  focus="Explain the same idea another way without introducing a new concept. Ask students to confirm when ready."
 var result: Dictionary=await game.host_openai.respond_character(instructions,{"classroom":TeacherAI.context(activity,id,board),"teaching_step":focus},"")
 var latest:=_ai_activity(room)
 if str(latest.get("id",""))!=class_id or latest.get("phase","")!="lesson" or str(ai_stage.get(room,""))!=key:return
 var text_value:=TeacherAI.safe_reply(str(result.get("text",""))) if result.get("ok",false) else ""
 var checked: Dictionary=await game.host_openai.moderate(text_value) if not text_value.is_empty() else {}
 latest=_ai_activity(room)
 if str(latest.get("id",""))!=class_id or latest.get("phase","")!="lesson" or str(ai_stage.get(room,""))!=key:return
 if not checked.get("ok",false) or checked.get("flagged",false):text_value=""
 _finish_lesson_cue(room,activity,state,key,board,formal,text_value)

func _finish_lesson_cue(room: String,activity: Dictionary,state: Dictionary,key: String,board: Dictionary,formal: bool,text_value: String) -> void:
 var id:=str(activity.get("teacher",""))
 if text_value.is_empty():
  var now: float=game.lecture_classes._now()
  text_value=str(_character_lecture_cue(activity,board,now,id).get("text","")).left(220)
 state.erase("ai_wait_started")
 state.ai_waiting=false
 state.ai_status=""
 if formal:
  var position:=_teacher_position(room)
  var serial:=_next_speech(room)
  _show_reaction(room,id,text_value,position,serial,2)
  _broadcast_reaction(room,id,text_value,position,serial,2)
 else:present_class_reaction(room,id,text_value,2)
 if room in classroom_homes:
  var teacher_board: Node3D=game.lecture_classes.signs[room].board
  _request_classroom_route(room,id,"ai:"+key,teacher_board.global_position+Vector3(1.1,0,1.7),0.0)
 if not formal and activity.get("ai_teaching",false) and not state.get("visual_attempted",false) and int(board.get("index",0))>=1:
  var profile:=Characters.teacher(id)
  var stage_index:=int(board.get("index",0))
  if float(profile.traits.demonstrations)>=.6 or stage_index>=3:
   if not game.host_openai.busy and questions.is_empty():
    state.visual_attempted=true
    _suggest_visual(room,str(activity.id),id,board)

func _suggest_visual(room: String,class_id: String,id: String,board: Dictionary) -> void:
 var activity_context:=_ai_activity(room)
 var person:=Characters.teacher(id)
 var instructions:=Visuals.instructions()+" "+CharacterMind.instructions(person,"steady","lesson")+" Create a short illustration only if it clarifies the current board."
 var result: Dictionary=await game.host_openai.respond_character(instructions,{"classroom":TeacherAI.context(activity_context,id,board).left(1600)},"",true)
 if not result.get("ok",false):return
 var plan:=Visuals.decode(str(result.get("text","")))
 if plan.is_empty() or plan.action==null:return
 var checked: Dictionary=await game.host_openai.moderate(plan.moderation)
 var activity: Dictionary=game.lecture_classes.classes.get(room,{})
 if not checked.get("ok",false) or checked.get("flagged",false) or activity.get("id","")!=class_id or activity.get("teacher","")!=id:return
 if activity.has("visual_playback") or int(game.lecture_classes._stage(activity).get("index",-1))!=int(board.get("index",-1)):return
 if Visuals.apply(activity,plan.action,game.lecture_classes._now()):
  game.lecture_classes._publish()
  present_class_reaction(room,id,plan.speech,2)

func _request_classroom_route(room: String,id: String,key: String,goal: Vector3,stand_off: float,peer: int=0,until: int=0) -> bool:
 if not multiplayer.is_server() or room not in LECTURE_ROOMS or classroom_route_seen.get(room,"")==key:return false
 var activity:=_ai_activity(room)
 var model: Node3D=lecture_models.get(room)
 if not is_instance_valid(model) or activity.get("phase","")!="lesson" or str(activity.get("teacher",""))!=id or not goal.is_finite():return false
 var previous: Dictionary=classroom_routes.get(room,{})
 if str(previous.get("key","")).begins_with("conversation:"):return false
 var floor_target:=Vector3(goal.x,model.global_position.y,goal.z)
 var path: Array[Vector3]=ClassroomRoute.plan(game,room,model.global_position,floor_target,stand_off)
 if path.is_empty() or (key.begins_with("conversation:") and path.back().distance_to(floor_target)>stand_off+.75):return false
 classroom_route_seen[room]=key
 classroom_routes[room]={"key":key,"class_id":str(activity.get("id","")),"teacher":id,"path":path,"index":0,"phase":"out","peer":peer,"until":until}
 return true

func _approach_in_lab(room: String,model: Node3D,goal: Vector3) -> bool:
 if room not in ["ac_lab","dc_lab"] or lab_routes.has(room) or not goal.is_finite() or not game.campus.registry.room_contains(room,goal):return false
 var home:=model.global_position
 var floor_target:=Vector3(goal.x,home.y,goal.z)
 var path:=ClassroomRoute.plan(game,room,home,floor_target,1.6)
 if path.is_empty() or path.back().distance_to(floor_target)>2.35:return false
 var return_path:=path.duplicate()
 return_path.reverse()
 return_path.append(home)
 lab_routes[room]={"path":path,"index":0,"departing":false,"return_path":return_path}
 return true

func _return_classroom_teacher(room: String) -> void:
 var model: Node3D=lecture_models.get(room)
 if not is_instance_valid(model) or not classroom_homes.has(room):classroom_routes.erase(room);return
 var path: Array[Vector3]=ClassroomRoute.plan(game,room,model.global_position,classroom_homes[room],0.0)
 if path.is_empty():classroom_routes.erase(room);return
 if ClassroomRoute.clear_step(game,path.back(),classroom_homes[room]):path.append(classroom_homes[room])
 classroom_routes[room]={"path":path,"index":0,"phase":"return","key":"","class_id":"","teacher":str(model.get_meta("faculty_id","")),"peer":0,"until":0}

func _next_classroom_group(room: String,activity: Dictionary,state: Dictionary,event_key: String) -> bool:
 var visit: Dictionary=classroom_group_visits.get(room,{})
 if str(visit.get("event",""))!=event_key:visit={"event":event_key,"visited":[]}
 var visited: Array=visit.visited
 var round: Variant=state.get("round")
 if round==null or not is_instance_valid(round):return false
 for team in state.shared.group_labels:
  if team in visited:continue
  visited.append(team);visit.visited=visited;classroom_group_visits[room]=visit
  for identity in round.present:
   if str(state.shared.groups.get(identity,""))!=str(team):continue
   var peer:=int(activity.get("students",{}).get(identity,{}).get("peer",0))
   var point: Vector3=game.player.global_position if peer==multiplayer.get_unique_id() else game.session.poses.get(peer,{}).get("position",Vector3.INF)
   if peer<=0 or not game.session.roster.has(peer) or not point.is_finite() or not game.lecture_classes._inside(peer,room):continue
   _request_classroom_route(room,str(activity.teacher),"event:"+event_key+":group:"+str(team),point,1.8,peer)
   if classroom_routes.has(room):return true
 classroom_route_seen[room]="event:"+event_key
 return false

func _step_classroom_routes(delta: float) -> void:
 if not multiplayer.is_server():
  for room in classroom_remote:
   var remote_model:=_moving_teacher(room)
   if is_instance_valid(remote_model) and not lab_routes.get(room,{}).get("departing",false):
    remote_model.global_position=remote_model.global_position.lerp(classroom_remote[room],minf(1.0,delta*8.0))
  return
 var events: Node=game.lecture_classes.classroom_events
 var events_enabled: bool=is_instance_valid(events) and events.enabled
 classroom_motion_clock+=delta
 if classroom_motion_clock>=.2:
  classroom_motion_clock=0.0
  for room in lecture_models.keys()+["ac_lab","dc_lab"]:
   var published:=_moving_teacher(room)
   if not is_instance_valid(published):continue
   classroom_motion_seq[room]=int(classroom_motion_seq.get(room,0))+1
   for recipient in game.session.roster:
    if int(recipient)!=multiplayer.get_unique_id() and game.session.peer_connected_now(int(recipient)):_classroom_teacher_motion.rpc_id(int(recipient),room,str(published.get_meta("faculty_id","")),published.global_position,published.rotation.y,int(classroom_motion_seq[room]))
 for room in lecture_models.keys():
  var model: Node3D=lecture_models[room]
  if not is_instance_valid(model):continue
  var activity:=_ai_activity(room)
  var state: Dictionary=events.service.rooms.get(room,{}) if events_enabled and is_instance_valid(events.service) else {}
  var round: Variant=state.get("round")
  var event_key: String=str(activity.get("id",""))+":"+str(round.event_id) if round!=null and is_instance_valid(round) and not round.closed else ""
  if classroom_group_visits.has(room) and str(classroom_group_visits[room].get("event",""))!=event_key:classroom_group_visits.erase(room)
  var route: Dictionary=classroom_routes.get(room,{})
  var valid: bool=activity.get("phase","")=="lesson" and str(activity.get("teacher",""))==str(model.get_meta("faculty_id",""))
  if not route.is_empty() and str(route.get("phase",""))!="return":
   var peer:=int(route.get("peer",0))
   if not valid or str(route.get("class_id",""))!=str(activity.get("id","")) or (peer>0 and (not game.session.roster.has(peer) or not game.lecture_classes._inside(peer,room))) or (str(route.key).begins_with("event:") and (event_key.is_empty() or not str(route.key).begins_with("event:"+event_key))) or (int(route.get("until",0))>0 and Time.get_ticks_msec()>=int(route.until)):
    _return_classroom_teacher(room);route=classroom_routes.get(room,{})
  if route.is_empty() and valid and not event_key.is_empty() and not classroom_route_seen.get(room,"")=="event:"+event_key:
   var mode:=str(round.mode)
   if mode=="board" and game.lecture_classes.signs.has(room):
    var board: Node3D=game.lecture_classes.signs[room].board
    if is_instance_valid(board):_request_classroom_route(room,str(activity.teacher),"event:"+event_key,board.global_position,1.5)
   elif mode=="group":
    _next_classroom_group(room,activity,state,event_key)
  route=classroom_routes.get(room,{})
  if route.is_empty():continue
  if str(route.phase)=="hold":
   if str(route.key).begins_with("lecture:") and not attention.has(room):
    var classroom_center: Vector3 = game.campus.registry.vector(game.campus.registry.get_room(room).center)
    var toward_students := classroom_center - model.global_position
    model.rotation.y = lerp_angle(model.rotation.y, atan2(toward_students.x,toward_students.z), minf(delta*4.0,1.0))
   if not event_key.is_empty() and str(route.key).begins_with("event:"+event_key) and str(route.key).contains(":group:"):
    if not route.has("group_hold_until"):
     route.group_hold_until=Time.get_ticks_msec()+4500;classroom_routes[room]=route
    if Time.get_ticks_msec()>=int(route.group_hold_until):
     if _next_classroom_group(room,activity,state,event_key):continue
     _return_classroom_teacher(room);continue
    else:continue
   if not event_key.is_empty() and str(route.key).begins_with("event:"+event_key):continue
   if int(route.get("until",0))>Time.get_ticks_msec():continue
   _return_classroom_teacher(room);route=classroom_routes.get(room,{})
   if route.is_empty():continue
  var path: Array[Vector3]=route.path
  var index:=int(route.index)
  if index>=path.size():
   if str(route.phase)=="return":classroom_routes.erase(room)
   else:route.phase="hold";classroom_routes[room]=route
   continue
  var target: Vector3=path[index]
  var offset:=target-model.global_position;offset.y=0
  if offset.length()<.08:route.index=index+1;classroom_routes[room]=route;continue
  var next:=model.global_position+offset.normalized()*minf(offset.length(),delta*.8)
  if not ClassroomRoute.clear_step(game,model.global_position,next):
   if str(route.phase)=="return":classroom_routes.erase(room)
   else:_return_classroom_teacher(room)
   continue
  model.global_position=next;model.rotation.y=lerp_angle(model.rotation.y,atan2(offset.x,offset.z),minf(delta*6.0,1.0))
  classroom_routes[room]=route

func _animate_lecture_movement() -> void:
 for room in lecture_models.keys()+["ac_lab","dc_lab"]:
  if room in ["ac_lab","dc_lab"] and (multiplayer.is_server() or lab_routes.get(room,{}).get("departing",false) or not classroom_remote.has(room)):continue
  var model:=_moving_teacher(room)
  if not is_instance_valid(model):continue
  var previous: Vector3=classroom_last_positions.get(room,model.global_position)
  classroom_last_positions[room]=model.global_position
  if reaction_pose.has(room) and Time.get_ticks_msec()<int(reaction_pose[room].get("until",0)):continue
  preload("res://scripts/avatar_model.gd").animate(model,previous.distance_squared_to(model.global_position)>.000009)

func _moving_teacher(room: String) -> Node3D:
 if room in ["ac_lab","dc_lab"]:
  var mount: Node3D=game.school_world.teacher if room=="ac_lab" else game.school_world.dc_instructor
  return mount.get_node_or_null("InstructorModel") as Node3D
 return lecture_models.get(room) as Node3D

@rpc("authority","call_remote","unreliable_ordered")
func _classroom_teacher_motion(room: String,id: String,position: Vector3,yaw: float,sequence: int) -> void:
 if multiplayer.get_remote_sender_id()!=1 or not position.is_finite() or not is_finite(yaw) or room not in LECTURE_ROOMS+["ac_lab","dc_lab"] or not game.campus.registry.room_contains(room,position):return
 var model:=_moving_teacher(room)
 if not is_instance_valid(model) or str(model.get_meta("faculty_id",""))!=id:return
 if sequence<=int(classroom_remote_seq.get(room,0)):return
 classroom_remote_seq[room]=sequence;classroom_remote[room]=position;model.rotation.y=yaw

func _clear_reaction_pose(room: String) -> void:
 if not reaction_pose.has(room):return
 var model: Node3D=reaction_pose[room].get("model") as Node3D
 if is_instance_valid(model):
  if model.has_meta("conversation_hand_until"):model.remove_meta("conversation_hand_until")
  CharacterMotion.express(model,"steady",1.)
 reaction_pose.erase(room)

func _build_conversation_ui() -> void:
 var layer:=CanvasLayer.new();layer.layer=31;add_child(layer)
 var wrapper := Control.new()
 wrapper.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
 wrapper.mouse_filter = Control.MOUSE_FILTER_IGNORE
 layer.add_child(wrapper)
 conversation=PanelContainer.new()
 conversation.theme=preload("res://scripts/ui/design_system/theme.gd").create()
 var panel_style: StyleBoxFlat=preload("res://scripts/ui/design_system/theme.gd").card_style()
 panel_style.bg_color=Color("102331ec")
 panel_style.set_content_margin_all(8)
 conversation.add_theme_stylebox_override("panel",panel_style)
 wrapper.add_child(conversation)
 conversation.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
 conversation.grow_vertical=Control.GROW_DIRECTION_BEGIN
 conversation.grow_horizontal=Control.GROW_DIRECTION_BOTH
 var fit := func():
  var width:=minf(820.0,get_viewport().get_visible_rect().size.x*.82)
  conversation.offset_left=-width*.5
  conversation.offset_right=width*.5
  conversation.offset_top=-185
  conversation.offset_bottom=-15
 wrapper.resized.connect(fit)
 fit.call()
 conversation.hide()
 voice_hint=Label.new()
 voice_hint.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
 voice_hint.offset_top=-150.
 voice_hint.offset_bottom=-119.
 voice_hint.offset_left=-310.
 voice_hint.offset_right=310.
 voice_hint.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
 voice_hint.add_theme_color_override("font_outline_color",Color("081a25"))
 voice_hint.add_theme_constant_override("outline_size",6)
 voice_hint.mouse_filter=Control.MOUSE_FILTER_IGNORE
 wrapper.add_child(voice_hint)
 voice_hint.hide()
 var body:=VBoxContainer.new();body.add_theme_constant_override("separation",4);conversation.add_child(body)
 conversation_name=Label.new();conversation_name.add_theme_font_size_override("font_size",18);body.add_child(conversation_name)
 conversation_scroll=ScrollContainer.new()
 conversation_scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
 conversation_scroll.custom_minimum_size.y=52
 conversation_scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL
 body.add_child(conversation_scroll)
 conversation_text=Label.new()
 conversation_text.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
 conversation_text.size_flags_horizontal=Control.SIZE_EXPAND_FILL
 conversation_scroll.add_child(conversation_text)
 var input_row:=HBoxContainer.new();body.add_child(input_row)
 conversation_input=LineEdit.new();conversation_input.placeholder_text="Type a question or reply";conversation_input.max_length=500;conversation_input.size_flags_horizontal=Control.SIZE_EXPAND_FILL;conversation_input.text_submitted.connect(func(_value: String):_submit_question());input_row.add_child(conversation_input)
 ask_button=Button.new();ask_button.text="Send";ask_button.pressed.connect(_submit_question);input_row.add_child(ask_button)
 record_button=Button.new();record_button.text="Mic";record_button.tooltip_text="Record a question";record_button.pressed.connect(_toggle_recording);input_row.add_child(record_button)
 var actions:=ScrollContainer.new()
 actions.vertical_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
 actions.follow_focus=true
 body.add_child(actions)
 var row:=HBoxContainer.new();actions.add_child(row)
 for option in [["Talk","chat"],["Ask for help","help"],["I'm ready","ready"],["Explain another way","clarify"],["Inspect circuit","inspect_circuit"],["Evaluate LED","evaluate_led"],["Hand over phone","hand_phone"],["Reclaim phone","reclaim_phone"],["Goodbye","bye"]]:
  var button:=Button.new();button.text=option[0];button.pressed.connect(_conversation_choice.bind(str(option[1])));row.add_child(button);conversation_actions[option[1]]=button
func _unhandled_input(event: InputEvent) -> void:
 if not is_instance_valid(game) or not game.front.in_game or Input.mouse_mode!=Input.MOUSE_MODE_CAPTURED:return
 if not (event is InputEventKey and event.pressed and not event.echo and event.physical_keycode==game.player.keys.call_teacher):return
 var room:=str(game.campus.registry.locate(game.player.global_position))
 if room not in ["ac_lab","dc_lab"]:return
 get_viewport().set_input_as_handled()
 if _freeplay_lab_available(room):
  game.paper_ui.teacher()
  return
 game.ui.log_message("Speak to the instructor in person or raise your hand during a class activity.")
func _prune_dialogue() -> void:
 if not multiplayer.is_server():return
 for peer in last_dialogue.keys():
  if not game.session.roster.has(int(peer)):last_dialogue.erase(peer)
 for peer in classmate_voice_serials.keys():
  if not game.session.roster.has(int(peer)):classmate_voice_serials.erase(peer)
func open_conversation(room: String, student := "", class_id := "") -> void:
 var activity:=_ai_activity(room)
 var id:=str(activity.get("teacher",""))
 var member: Dictionary=game.lecture_classes.classroom_students.visible_member(room,class_id,student) if not student.is_empty() else {}
 if (student.is_empty() and not Roster.has(id)) or (not student.is_empty() and member.is_empty()):return
 conversation_room=room
 conversation_student=student
 conversation_class=class_id
 conversation_name.text=str(Roster.entry(id).name) if student.is_empty() else str(member.name)
 conversation_input.text=""
 record_button.visible=bool(game.host_openai.enabled) if multiplayer.is_server() else game.session.online
 conversation_actions.inspect_circuit.visible=student.is_empty() and room in ["ac_lab","dc_lab"]
 conversation_actions.evaluate_led.visible=student.is_empty() and room=="dc_lab"
 for intent in ["hand_phone","reclaim_phone"]:
  conversation_actions[intent].visible=student.is_empty() and room in ["ac_lab","dc_lab"]
 for intent in ["ready","clarify"]:
  conversation_actions[intent].visible=student.is_empty() and activity.get("ai_teaching",false) and activity.get("phase","")=="lesson"
 conversation_text.text="What would you like to talk about?"
 conversation.show();speech_player.subtitle_layer.hide();game.release_mouse()
func close_conversation() -> bool:
 if not voice_room.is_empty():
  _stop_voice_conversation()
  return true
 if not is_instance_valid(conversation) or not conversation.visible:return false
 _cancel_recording()
 conversation.hide();speech_player.subtitle_layer.show();conversation_room=""
 conversation_student="";conversation_class=""
 if game.front.in_game:game.capture()
 return true
func interact(target: Node) -> bool:
 if not is_instance_valid(target) or target.get_meta("role","") not in ["faculty_teacher","classroom_student"]:return false
 var room:=str(target.get_meta("room",""))
 var student:=str(target.get_meta("student_id",""))
 var class_id:=str(target.get_meta("class_id",""))
 if not _start_voice_conversation(room,false,student,class_id):open_conversation(room,student,class_id)
 return true

func invite_question(room: String,id: String,peer: int,class_id: String) -> void:
 if not multiplayer.is_server() or not game.lecture_classes._inside(peer,room):return
 var target: Vector3=game.lecture_classes._position(peer)
 _publish_attention(room,id,target)
 present_class_reaction(room,id,"Go ahead. What would you like me to explain?",3)
 if peer==multiplayer.get_unique_id():_question_invited(room,class_id)
 elif game.session.online and game.session.peer_connected_now(peer):_question_invited.rpc_id(peer,room,class_id)

@rpc("authority","call_remote","reliable")
func _question_invited(room: String,class_id: String) -> void:
 if str(_ai_activity(room).get("id",""))!=class_id:return
 if not _start_voice_conversation(room,true):open_conversation(room)

func _start_voice_conversation(room: String,invited: bool,student := "",class_id := "") -> bool:
 if not bool(game.client_preferences.values.teacher_automatic_conversation) or recording or game.voice_chat.talking:return false
 if multiplayer.is_server() and not game.host_openai.stt_enabled:return false
 var activity:=_ai_activity(room)
 var member: Dictionary=game.lecture_classes.classroom_students.visible_member(room,class_id,student) if not student.is_empty() else {}
 if not is_instance_valid(game.voice_chat.capture) or (member.is_empty() if not student.is_empty() else not Roster.has(str(activity.get("teacher","")))):return false
 _stop_voice_conversation()
 voice_room=room
 voice_class=class_id if not student.is_empty() else str(activity.get("id",""))
 voice_student=student
 voice_invited=invited
 voice_until=Time.get_ticks_msec()+25000
 voice_recognizer.Reset()
 game.voice_chat.capture.clear_buffer()
 record_player=AudioStreamPlayer.new()
 record_player.bus="VoiceCapture"
 record_player.stream=AudioStreamMicrophone.new()
 add_child(record_player)
 record_player.play()
 var name_to_address: String=member.name if not student.is_empty() else Roster.entry(activity.teacher).name
 voice_hint.text="Listening · Speak to %s · Esc to end"%name_to_address
 voice_hint.show()
 return true

func _stop_voice_conversation() -> void:
 if voice_room.is_empty():return
 voice_room=""
 voice_class=""
 voice_student=""
 voice_recognizer.Reset()
 _cancel_recording()
 if is_instance_valid(voice_hint):voice_hint.hide()

func _voice_conversation_step() -> void:
 if voice_room.is_empty():return
 if not game.front.in_game or not get_window().has_focus() or not game.client_preferences.values.teacher_automatic_conversation or game.voice_chat.talking:
  _stop_voice_conversation()
  return
 var activity:=_ai_activity(voice_room)
 var point:=_teacher_position(voice_room)
 if not voice_student.is_empty():
  var member: Dictionary=game.lecture_classes.classroom_students.visible_member(voice_room,voice_class,voice_student)
  if member.is_empty():_stop_voice_conversation();return
  point=member.position
 if str(activity.get("id",""))!=voice_class or game.campus.registry.locate(game.player.global_position)!=voice_room or (not voice_invited and game.player.global_position.distance_to(point)>5.):
  _stop_voice_conversation()
  return
 if Time.get_ticks_msec()>=voice_until:
  _stop_voice_conversation()
  return
 _consume_voice_capture()

func _consume_voice_capture() -> void:
 var capture: AudioEffectCapture=game.voice_chat.capture
 var count:=mini(capture.get_frames_available(),4096)
 if count<256:return
 var speech_room: String=voice_room if voice_student.is_empty() else "classmate"
 var result: Dictionary=voice_recognizer.Push(capture.get_buffer(count),AudioServer.get_mix_rate(),float(game.client_preferences.values.teacher_mic_sensitivity),speech_player.active.has(speech_room))
 if result.get("onset",false):
  voice_until=Time.get_ticks_msec()+25000
  speech_player.cancel(speech_room)
  voice_hint.text="Listening to your question · Esc to end"
 if result.has("audio"):
  var wav:=TeacherAI.wav_16k(result.audio)
  _send_voice_question(voice_room,wav,voice_student,voice_class)
  voice_hint.text="Question sent · Esc to end"
func _conversation_choice(intent: String) -> void:
 if conversation_room.is_empty():return
 if intent=="chat":conversation_input.grab_focus();return
 if intent=="bye":close_conversation();return
 if intent in ["ready","clarify"]:
  if multiplayer.is_server():_lesson_feedback(multiplayer.get_unique_id(),conversation_room,intent)
  elif game.session.online:_send_lesson_feedback.rpc_id(1,conversation_room,intent)
  return
 if intent=="help":
  conversation_input.text="Can you help me with the current topic?"
  _submit_question()
  return
 var phone_id: String=game.smartphones.selected() if intent=="hand_phone" else ""
 if multiplayer.is_server():_dialogue_request(multiplayer.get_unique_id(),conversation_room,intent,phone_id)
 elif game.session.online:_ask.rpc_id(1,conversation_room,intent,phone_id)
@rpc("any_peer","call_remote","reliable")
func _send_lesson_feedback(room: String,signal_name: String) -> void:
 if multiplayer.is_server():_lesson_feedback(multiplayer.get_remote_sender_id(),room,signal_name)
func _lesson_feedback(peer: int,room: String,signal_name: String) -> void:
 if signal_name not in ["ready","clarify"] or not game.session.roster.has(peer):return
 var activity:=_ai_activity(room)
 if activity.get("phase","")!="lesson" or not activity.get("ai_teaching",false) or not game.lecture_classes._inside(peer,room):return
 var school: Node=game.school
 var token:=str(school.identities.get(peer,""))
 var formal: bool=not game.lecture_classes.classes.has(room)
 var state: Dictionary=school.activity if formal else activity
 var students: Dictionary=school.class_students if formal else state.get("students",{})
 var present: Array[String]=[]
 for participant in game.session.roster:
  var identity:=str(school.identities.get(participant,""))
  if not identity.is_empty() and students.has(identity) and game.lecture_classes._inside(int(participant),room):present.append(identity)
 if token not in present:return
 var duration: float=school.teaching_seconds if formal else game.lecture_classes.lesson_duration(state)
 var elapsed: float=duration-(float(school.remaining) if formal else maxf(0.0,float(state.deadline)-game.lecture_classes._now()))
 var board: Dictionary=school.teaching_stage() if formal else game.lecture_classes._stage(state)
 var step: Dictionary=board.get("teaching_step",{})
 if step.get("key")!="check":return
 var class_id:=str(activity.get("id",""))
 var feedback: Dictionary=lesson_feedback.get_or_add(class_id,{})
 var advance_by:=AdaptiveLesson.pacing_signal(feedback,token,signal_name,elapsed,duration,present,step)
 if signal_name=="clarify":feedback.revisit=true
 if not state.get("ai_waiting",false) and advance_by>0.0:
  if formal:school.remaining-=advance_by
  else:state.deadline-=advance_by
 var response:="I'll try another explanation." if signal_name=="clarify" else "Readiness noted."
 var teacher:=str(activity.get("teacher",""))
 if peer==multiplayer.get_unique_id():_dialogue_reply(room,teacher,response)
 elif game.session.online and game.session.peer_connected_now(peer):_dialogue_reply.rpc_id(peer,room,teacher,response)
func _submit_question() -> void:
 var question:=conversation_input.text.strip_edges()
 if conversation_room.is_empty() or question.is_empty():return
 conversation_input.clear()
 conversation_text.text="You: "+question+"\n\nWaiting for a reply…"
 conversation_scroll.set_deferred("scroll_vertical", 100000)
 if not conversation_student.is_empty():
  _send_classmate_question(conversation_room,conversation_class,conversation_student,question)
  return
 if multiplayer.is_server():_question_request(multiplayer.get_unique_id(),conversation_room,question)
 elif game.session.online:_ask_question.rpc_id(1,conversation_room,question)
func _toggle_recording() -> void:
 if recording:_finish_recording();return
 if conversation_room.is_empty() or record_player!=null:return
 var voice: Node=game.voice_chat
 if not is_instance_valid(voice) or not is_instance_valid(voice.capture):return
 voice.capture.clear_buffer()
 record_samples.clear();record_phase=0.0;recording=true;record_started=Time.get_ticks_msec()
 record_player=AudioStreamPlayer.new();record_player.bus="VoiceCapture";record_player.stream=AudioStreamMicrophone.new();add_child(record_player);record_player.play()
 record_button.text="Stop and send recording"
 conversation_text.text="Recording only for this question. Audio goes to the host and OpenAI when you stop."
func _record_step() -> void:
 if not recording:return
 var capture: AudioEffectCapture=game.voice_chat.capture
 if not is_instance_valid(capture):_cancel_recording();return
 var count:=mini(capture.get_frames_available(),AudioServer.get_mix_rate()/10)
 if count>0:
  var frames:=capture.get_buffer(count)
  var stride:=float(AudioServer.get_mix_rate())/16000.0
  while record_phase<float(frames.size()):
   if record_samples.size()>=192000:break
   var i:=mini(frames.size()-1,int(record_phase))
   var sample:=roundi(clampf((frames[i].x+frames[i].y)*.5,-1.0,1.0)*32767.0)
   record_samples.append(sample&255);record_samples.append((sample>>8)&255)
   record_phase+=stride
  record_phase-=float(frames.size())
 if Time.get_ticks_msec()-record_started>=6000:_finish_recording()
func _cancel_recording() -> void:
 recording=false;record_samples.clear()
 if is_instance_valid(record_player):record_player.stop();record_player.queue_free()
 record_player=null
 if is_instance_valid(record_button):record_button.text="Mic"
func _finish_recording() -> void:
 if not recording:return
 var samples:=record_samples.duplicate()
 _cancel_recording()
 if samples.size()<32000:conversation_text.text="Record at least one second of speech.";return
 conversation_text.text="Transcribing…"
 var wav:=TeacherAI.wav_16k(samples)
 _send_voice_question(conversation_room,wav,conversation_student,conversation_class)

func _send_voice_question(room: String,wav: PackedByteArray,student: String,class_id: String) -> void:
 if not student.is_empty():_send_classmate_question(room,class_id,student,wav)
 elif multiplayer.is_server():_speech_question_request(multiplayer.get_unique_id(),room,wav)
 elif game.session.online:_ask_speech.rpc_id(1,room,wav)
@rpc("any_peer","call_remote","reliable")
func _ask_speech(room: String,wav: PackedByteArray) -> void:
 if multiplayer.is_server():_speech_question_request(multiplayer.get_remote_sender_id(),room,wav)
func _ai_activity(room: String) -> Dictionary:
 if room in ["ac_lab","dc_lab"]:return _lab_visit(room)
 if room not in LECTURE_ROOMS:return {}
 var activities: Dictionary=game.lecture_classes.classes if multiplayer.is_server() else game.lecture_classes.public_classes
 return activities.get(room,_formal_activity(room))
func _speech_question_request(peer: int,room: String,wav: PackedByteArray) -> void:
 if wav.size()<32044 or wav.size()>224044:return
 _queue_question(peer,room,wav)

func _transcribe_question(peer: int,room: String,id: String,class_id: String,wav: PackedByteArray,pos: Vector3) -> void:
 var result: Dictionary=await game.host_openai.transcribe_wav(wav)
 if str(_ai_activity(room).get("id",""))!=class_id:
  ai_busy.erase(peer)
  return
 if not result.get("ok",false):
  ai_busy.erase(peer)
  _question_status(peer,room,id,str(result.get("error","Speech was not recognized.")))
  return
 await _answer_question(peer,room,id,class_id,str(result.get("text","")),pos)

@rpc("any_peer","call_remote","reliable")
func _ask_question(room: String,question: String) -> void:
 if multiplayer.is_server():_question_request(multiplayer.get_remote_sender_id(),room,question)

func _question_request(peer: int,room: String,question: String) -> void:
 if question.is_empty() or question.length()>500:return
 _queue_question(peer,room,question)

func _send_classmate_question(room: String,class_id: String,student: String,content: Variant) -> void:
 if multiplayer.is_server():_classmate_question(multiplayer.get_unique_id(),room,class_id,student,content)
 elif game.session.online:_ask_classmate.rpc_id(1,room,class_id,student,content)

@rpc("any_peer","call_remote","reliable")
func _ask_classmate(room: String,class_id: String,student: String,content: Variant) -> void:
 if multiplayer.is_server():_classmate_question(multiplayer.get_remote_sender_id(),room,class_id,student,content)

func _classmate_question(peer: int,room: String,class_id: String,student: String,content: Variant) -> void:
 if content is String:
  if content.strip_edges().is_empty() or content.length()>500:return
 elif content is PackedByteArray:
  if content.size()<32044 or content.size()>224044:return
 else:return
 if game.lecture_classes.classroom_students.nearby_member(peer,room,class_id,student).is_empty():return
 if questions.size()>=32 or questions.filter(func(entry):return entry.peer==peer).size()>=4:
  _notify_classmate(peer,room,class_id,student,"The conversation queue is full.",false)
  return
 questions.append({"peer":peer,"room":room,"class":class_id,"student":student,"content":content})
 if game.host_openai.busy or not ai_busy.is_empty() or questions.size()>1:
  _notify_classmate(peer,room,class_id,student,"Message queued.",false)
 _next_question()

func _character_turn(person: Dictionary,identity: String,activity: Dictionary,question: String) -> Dictionary:
 var relationship: Dictionary=brain.relationship_at(person.id,identity,int(Time.get_unix_time_from_system()))
 var turn:=character_mind.observe(person,relationship,question,Time.get_ticks_msec(),identity)
 var knowledge:=CharacterMind.assess(person,activity,question)
 if str(turn.line).is_empty() and not knowledge.allowed:
  turn.line=knowledge.line
  var learned: Dictionary=brain.recall_reported_fact(relationship,question)
  if not learned.is_empty():turn.line="You told me %s."%str(learned.statement).left(120).trim_suffix(".")
 turn.relationship=relationship
 turn.domain=knowledge.domain
 return turn

func _character_observations(peer: int,model: Node3D,activity: Dictionary) -> Dictionary:
 var result:={"phase":str(activity.get("phase","")),"player_visible":false}
 var room: Variant=activity.get("room")
 if room is Dictionary:result.room=str(room.get("number","")).left(24)
 elif room is String:result.room=room.left(32)
 if not is_instance_valid(model) or not game.session.roster.has(peer):return result
 result.has_arms=model.has_node("Body/ArmR")
 result.character_outfit=str(model.get_meta("character_outfit",""))
 var point: Vector3=game.lecture_classes._position(peer)
 var origin:=model.global_position
 if not point.is_finite() or origin.distance_to(point)>=10.:return result
 var query:=PhysicsRayQueryParameters3D.create(origin+Vector3.UP*1.4,point+Vector3.UP*1.4,1)
 if is_instance_valid(game.player):query.exclude=[game.player.get_rid()]
 var blocked:=not get_world_3d().direct_space_state.intersect_ray(query).is_empty()
 if brain.visibility(origin,model.global_basis.z,point,blocked)<=0.:return result
 result.player_visible=true
 var appearance: Dictionary=game.cosmetic_appearances.get(peer,{})
 if appearance.is_empty():return result
 if appearance_catalog.is_empty():
  var cosmetics=preload("res://scripts/avatar_cosmetics/core/coordinator.gd").new()
  if cosmetics.load_catalog():appearance_catalog=cosmetics.catalog
 var equipped: Dictionary=appearance.get("equipped",{})
 var outfit:=PackedStringArray()
 for slot in ["top_outer","top_inner","bottom","footwear","head","hair","eyewear","ears","neck","back"]:
  if slot=="top_inner" and equipped.has("top_outer"):continue
  var item: Dictionary=equipped.get(slot,{})
  var definition: Dictionary=appearance_catalog.get(item.get("id",""),{})
  var label:=str(definition.get("name",definition.get("label","")))
  if not label.is_empty():
   var color_value:=str(item.get("parameters",{}).get("primary_color",""))
   if Color.html_is_valid(color_value):label=_outfit_color(Color.html(color_value))+" "+label
   outfit.append(label)
 if outfit.is_empty():
  var legacy: Dictionary=appearance.get("legacy_character",{})
  for key in ["outfit","hair","glasses"]:
   if legacy.has(key) and str(legacy[key]) not in ["","None"]:outfit.append(str(legacy[key]))
 if not outfit.is_empty():result.player_outfit=outfit
 return result

func _outfit_color(color: Color) -> String:
 if color.v<.19:return "black"
 if color.s<.15:return "white" if color.v>.78 else "gray"
 var hue:=color.h*360.
 if hue<19. or hue>=345.:return "red"
 if hue<42.:return "brown" if color.v<.52 else "orange"
 if hue<66.:return "yellow"
 if hue<160.:return "green"
 if hue<205.:return "teal"
 if hue<260.:return "blue"
 return "purple" if hue<310. else "pink"

func _embodied_reply(person: Dictionary,question: String,observations: Dictionary) -> String:
 var lower:=question.strip_edges().to_lower()
 if "do you have arms" in lower:return "Sure. Two of them. Why?" if float(person.traits.humor)>.5 else "Yes. What are you asking me to do?"
 if ("what are you wearing" in lower or "what color is your shirt" in lower) and not str(observations.get("character_outfit","")).is_empty():
  return "I've got my %s on."%str(observations.character_outfit).to_lower()
 if "my outfit" in lower or "what am i wearing" in lower:
  if not observations.player_visible:return "Come where I can see you." if float(person.traits.temper)>.6 else "Turn this way a moment. I can't see what you're wearing from here."
  var outfit: PackedStringArray=observations.get("player_outfit",PackedStringArray())
  if outfit.is_empty():return "I can see you, but I can't pick out the details from here."
  return ("I noticed the %s. Looks good." if float(person.traits.humor)>.5 else "I can see the %s from here.")%outfit[0]
 return ""

func _character_action(question: String) -> String:
 var request:=question.to_lower().strip_edges().rstrip("?!.,").trim_prefix("please ").trim_prefix("could you ").trim_prefix("can you ")
 if request.ends_with(" please"):request=request.trim_suffix(" please")
 if request in ["raise your hand","lift your hand"]:return "raise_hand"
 if request in ["come here","walk over here","come over here"]:return "approach"
 if request in ["point at the board","point to the board","show me the board"]:return "point"
 if request in ["walk to the board","go to the board"]:return "approach_board"
 if request in ["nod","nod your head"]:return "nod"
 if request in ["wave","wave at me","wave to me"]:return "wave"
 if request in ["sit down","take a seat"]:return "sit"
 if request in ["stand","stand up"]:return "stand"
 if request in ["jump","pick that up","pick up my equipment"]:return "unsupported"
 return ""

func _character_action_point(room: String,action: String,requester: Vector3) -> Vector3:
 if action not in ["point","approach_board"]:return requester
 var board: Node3D=game.lecture_classes.signs.get(room,{}).get("board") as Node3D
 return board.global_position if is_instance_valid(board) else Vector3.INF

func _character_action_reply(action: String,accepted: bool) -> String:
 if not accepted:return "I can't do that from here."
 return str({"raise_hand":"Like this?","point":"Over there, on the board.","wave":"Hey!","nod":"Mm-hm.",
  "approach":"Give me a moment to get over there.","approach_board":"I'll go to the board.","stand":"There we go.","sit":"I'll sit here."}.get(action,""))

func answer_observed_lesson_question(person: Dictionary,stage: Dictionary,question: String) -> String:
 var explanation:=LectureDirector.answer(question,stage)
 if stage.is_empty():return explanation
 if float(person.strictness)>=.68:return ("Focus on this step. "+explanation).left(275)
 if float(person.traits.teaching_effort)<.4:return explanation
 if float(person.traits.warmth)>.8:return ("Let's take it one step at a time. "+explanation).left(275)
 if float(person.traits.demonstrations)>.92:return ("Compare that with what you see on the board. "+explanation).left(275)
 return explanation

func classroom_character_exchange(activity: Dictionary,member: Dictionary,stage: Dictionary,question: String) -> String:
 var teacher_id: String=activity.teacher
 var student: Dictionary=member.profile
 var teacher:=Characters.teacher(teacher_id)
 var turn:=_character_turn(teacher,student.id,activity,question)
 var answer:=str(turn.line)
 if answer.is_empty():answer=answer_observed_lesson_question(teacher,stage,question)
 _remember_character_turn(teacher_id,student.id,question,answer,turn)
 brain.remember_conversation(student.id,teacher_id,answer,question,int(Time.get_unix_time_from_system()))
 return answer

func _remember_character_turn(id: String,identity: String,question: String,reply: String,turn: Dictionary) -> void:
 var now:=int(Time.get_unix_time_from_system())
 brain.remember_conversation(id,identity,question,reply,now)
 brain.remember_fact(id,identity,question,now)
 if turn.event in ["insult","apology","compliment"]:brain.remember(id,identity,turn.event,now)

func _answer_classmate(entry: Dictionary) -> void:
 var peer: int=entry.peer
 var room: String=entry.room
 var class_id: String=entry.class
 var actor: String=entry.student
 var students: Node=game.lecture_classes.classroom_students
 var member: Dictionary=students.nearby_member(peer,room,class_id,actor)
 if member.is_empty():return
 var identity:=str(game.school.identities.get(peer,""))
 if identity.is_empty():return
 ai_busy[peer]="classmate"
 var client: Node=game.host_openai
 var question: String
 if entry.content is PackedByteArray:
  var transcript: Dictionary=await client.transcribe_wav(entry.content)
  if not transcript.get("ok",false):
   ai_busy.erase(peer)
   _notify_classmate(peer,room,class_id,actor,str(transcript.get("error","Speech was not recognized.")),false)
   return
  question=str(transcript.get("text","")).strip_edges()
 else:question=entry.content
 var activity: Dictionary=game.lecture_classes.classes.get(room,{})
 if activity.get("id","")!=class_id or question.is_empty() or str(game.school.identities.get(peer,""))!=identity or students.nearby_member(peer,room,class_id,actor).is_empty():
  ai_busy.erase(peer)
  return
 var history:=brain.recall(actor,identity)
 var person: Dictionary=member.profile
 var turn:=_character_turn(person,identity,activity,question)
 var relationship: Dictionary=turn.relationship
 var model: Node3D=students.models.get(class_id+":"+actor) as Node3D
 var observations:=_character_observations(peer,model,activity)
 observations.character_posture="seated" if member.get("seated",false) else "standing"
 var stage: Dictionary=game.lecture_classes._stage(activity) if activity.phase=="lesson" else {}
 var reply: String=students.dialogue(member.profile,activity.course,stage,question,history,activity.phase,relationship)
 var embodied:=_embodied_reply(person,question,observations)
 var action:=_character_action(question)
 var raise_hand:=false
 if not str(turn.line).is_empty() and (turn.event!="greeting" or int(relationship.familiarity)<2 or bool(turn.closed)):reply=turn.line
 elif not embodied.is_empty():reply=embodied
 elif not action.is_empty():
  var target:=_character_action_point(room,action,game.lecture_classes._position(peer))
  var permitted:=bool(observations.player_visible) and bool(observations.get("has_arms",false))
  var accepted: bool=permitted and (action!="point" or target.is_finite()) and students.act(room,activity,member,
   "approach" if action=="approach_board" else action,target,game.lecture_classes._now())
  raise_hand=accepted and action=="raise_hand"
  reply=_character_action_reply(action,accepted)
  if accepted:game.lecture_classes._publish()
 elif client.ready_for_class() and activity.phase!="assignment":
  var moderation: Dictionary=await client.moderate(question.left(500))
  if moderation.get("flagged",false):
   ai_busy.erase(peer)
   _notify_classmate(peer,room,class_id,actor,str(person.lines.boundary),true)
   return
  if moderation.get("ok",false):
   var context:={
    "course":activity.course,"topic":str(stage.get("title","")),"relationship":brain.social_context(relationship),
    "observations":observations,"knowledge":person.knowledge_domains,"prior_turns":TeacherAI.relevant_turns(history,question),"reported_facts":brain.relevant_facts(relationship,turn.domain)}
   var result: Dictionary=await client.respond_character(CharacterMind.instructions(person,turn.emotion),context,question)
   if result.get("ok",false):
    var candidate:=TeacherAI.safe_reply(str(result.get("text","")))
    var checked: Dictionary=await client.moderate(candidate)
    if checked.get("ok",false) and not checked.get("flagged",false) and not candidate.is_empty():reply=candidate
 ai_busy.erase(peer)
 if str(game.school.identities.get(peer,""))!=identity or students.nearby_member(peer,room,class_id,actor).is_empty():return
 _remember_character_turn(actor,identity,question,reply,turn)
 _notify_classmate(peer,room,class_id,actor,reply,true,turn.emotion,raise_hand)

func _notify_classmate(peer: int,room: String,class_id: String,actor: String,line: String,speak: bool,mood := "steady",raised := false) -> void:
 var local:=peer==multiplayer.get_unique_id()
 if not local and (not game.session.online or not game.session.peer_connected_now(peer)):return
 var serial:=_next_speech("classmate") if speak else 0
 var delivery:=Characters.speech(Classmates.profile_for(actor),game.host_openai.tts_model,2,mood) if speak and _uses_class_voice() else {}
 var provider:=not delivery.is_empty()
 if local:_classmate_reply(room,class_id,actor,line,speak,mood,raised,serial,provider)
 else:_classmate_reply.rpc_id(peer,room,class_id,actor,line,speak,mood,raised,serial,provider)
 if provider:
  classmate_voice_serials[peer]=serial
  _request_classmate_audio(peer,serial,actor,SpeechMath.display(line).left(350),delivery)

@rpc("authority","call_remote","reliable")
func _classmate_reply(room: String,class_id: String,actor: String,line: String,speak: bool,mood := "steady",raised := false,serial := 0,provider := false) -> void:
 var students: Node=game.lecture_classes.classroom_students
 var model: Node3D=students.models.get(class_id+":"+actor)
 if not is_instance_valid(model):return
 var profile:=Classmates.profile_for(actor)
 if profile.is_empty():return
 if conversation.visible and conversation_room==room and conversation_class==class_id and conversation_student==actor:
  conversation_text.text=SpeechMath.display(line)
  conversation_scroll.set_deferred("scroll_vertical",0)
 elif voice_room!=room or voice_class!=class_id or voice_student!=actor:return
 elif not speak:voice_hint.text=line
 if not speak:return
 var text:=SpeechMath.display(line).left(350)
 var key:=speech_cache_key(actor,text)
 var stream: AudioStreamWAV=speech_player.stream_for(key)
 speech_player.configure(bool(game.client_preferences.values.teacher_speech),bool(game.client_preferences.values.teacher_subtitles))
 speech_player.accept("classmate",profile.name,serial,text,2,model,null if provider else stream,1. if provider else _character_pitch(mood))
 _character_gesture("classmate",model,mood,raised)
 if provider:pending_voice["classmate"]={"serial":serial,"teacher":actor,"text":text,"priority":2}
 elif stream==null and speech_player.speech_enabled:speech_synth.request("classmate",serial,actor,text,key,2)
 students.focus_on_player(class_id,actor)

func _request_classmate_audio(peer: int,serial: int,actor: String,text: String,delivery: Dictionary) -> void:
 var key:=_provider_speech_key(actor,text,delivery)
 var stream: AudioStreamWAV=speech_player.stream_for(key)
 if stream==null:
  var result: Dictionary=await game.host_openai.speak(text,{},delivery.voice,delivery)
  stream=result.get("stream")
 if int(classmate_voice_serials.get(peer,0))!=serial:return
 if peer==multiplayer.get_unique_id():
  if stream==null:_voice_fallback("classmate",serial)
  elif int(pending_voice.get("classmate",{}).get("serial",0))==serial:
   pending_voice.erase("classmate")
   _speech_completed("classmate",serial,key,stream,"ok")
 elif game.session.online and game.session.peer_connected_now(peer):
  if stream!=null:speech_player.cache_stream(key,stream)
  _send_voice_clip_to(peer,"classmate",serial,stream)

func _queue_question(peer: int,room: String,content: Variant) -> void:
 if not multiplayer.is_server() or not game.session.roster.has(peer):return
 var activity: Dictionary=_ai_activity(room)
 var teacher:=str(activity.get("teacher",""))
 if not Roster.has(teacher):return
 if not game.lecture_classes._inside(peer,room):
  _question_status(peer,room,teacher,"Please stay in the classroom to ask a question.")
  return
 if activity.get("phase","")=="office_hours" and not _near_instructor(peer,room):return
 var count:=0
 for entry in questions:
  if int(entry.peer)==peer:count+=1
 if questions.size()>=32 or count>=4:
  _question_status(peer,room,teacher,"The question queue is full. Let the teacher answer a queued question first.")
  return
 questions.append({"peer":peer,"room":room,"teacher":teacher,"class":str(activity.get("id","")),"content":content})
 if game.host_openai.busy or not ai_busy.is_empty() or questions.size()>1:
  _question_status(peer,room,teacher,"Question queued. Position %d."%questions.size())
 _next_question()

func _question_status(peer: int,room: String,teacher: String,message: String) -> void:
 if peer==multiplayer.get_unique_id():_dialogue_reply(room,teacher,message)
 elif game.session.online and game.session.peer_connected_now(peer):_dialogue_reply.rpc_id(peer,room,teacher,message)

func _next_question() -> void:
 if questions.is_empty() or not ai_busy.is_empty() or game.host_openai.busy:return
 var entry: Dictionary=questions.pop_front()
 if entry.has("student"):_answer_classmate(entry);return
 var peer: int=entry.peer
 var room: String=entry.room
 var teacher: String=entry.teacher
 if not game.session.roster.has(peer):return
 var activity:=_ai_activity(room)
 if str(activity.get("id",""))!=entry.class or str(activity.get("teacher",""))!=teacher or not game.lecture_classes._inside(peer,room):
  _question_status(peer,room,teacher,"The conversation ended before the teacher could answer.")
  return
 if activity.get("phase","")=="office_hours" and not _near_instructor(peer,room):return
 var pos: Vector3=game.player.global_position if peer==multiplayer.get_unique_id() else game.session.poses.get(peer,{}).get("position",Vector3.ZERO)
 ai_busy[peer]=room
 _question_status(peer,room,teacher,"The teacher is answering…")
 if entry.content is PackedByteArray:_transcribe_question(peer,room,teacher,entry.class,entry.content,pos)
 else:_answer_question(peer,room,teacher,entry.class,entry.content,pos)

func lesson_question_active(room: String) -> bool:
 return room in ai_busy.values() or questions.any(func(entry: Dictionary):return entry.get("room")==room and not entry.has("student"))

func _personal_teacher_reply(id: String,identity: String,question: String,in_lesson: bool) -> String:
 var topic:=question.strip_edges().to_lower().rstrip("?!.,")
 var familiarity:=int(brain.relationship(id,identity).familiarity)
 if topic in ["hi","hello","hey","hello again"] and familiarity>0:
  return "Good to see you again. What would you like to go over?" if not in_lesson else "Good to see you again. Is there something in today's lesson you'd like to review?"
 if topic in ["do you remember me","do you remember our last conversation"]:
  return "Yes, we've spoken before. What would you like to follow up on?" if familiarity>0 else "I don't think we've met yet. What are you working on?"
 if not in_lesson and topic in ["what do you do for fun","what are your interests","do you have a hobby"]:
  if id=="jeff":return "I spend time out in the garage making things fit that have no business fitting. What do you get up to?"
  return "I'm into %s outside of class. What about you?"%str(Characters.teacher(id).interest)
 return ""

func _answer_question(peer: int,room: String,id: String,class_id: String,question: String,pos: Vector3) -> void:
 var activity_context := _ai_activity(room)
 if not multiplayer.is_server() or activity_context.get("id","")!=class_id or activity_context.get("teacher","")!=id or not game.lecture_classes._inside(peer,room):
  ai_busy.erase(peer)
  return
 var current_stage: Dictionary = {}
 if activity_context.get("phase","")=="lesson":
  current_stage=game.lecture_classes._stage(activity_context) if activity_context.has("teaching") else game.school.teaching_stage()
 var person:=Characters.teacher(id)
 var lab_evidence:=_ac_measurement_context(peer,activity_context) if room=="ac_lab" else ""
 var inspection:=not lab_evidence.is_empty() and question.to_lower().contains("inspect")
 var fallback:=lab_evidence if inspection else answer_observed_lesson_question(person,current_stage,question)
 if activity_context.get("phase","")=="office_hours" and not inspection:
  fallback="I'm here for lab questions. Tell me what you're building or bring your circuit to a bench so we can look at it."
 var identity:=str(game.school.identities.get(peer,""))
 var history: Array=brain.recall(id,identity)
 var turn:=_character_turn(person,identity,activity_context,question)
 var model:=_model_for_room(room,id)
 var observations:=_character_observations(peer,model,activity_context)
 var in_lesson: bool=activity_context.get("phase","")=="lesson"
 var personal:=_personal_teacher_reply(id,identity,question,in_lesson)
 var reply:=str(turn.line) if not str(turn.line).is_empty() else (personal if not personal.is_empty() else fallback)
 if turn.event=="greeting" and not bool(turn.closed) and not personal.is_empty() and int(turn.relationship.get("resentment",0))<3:reply=personal
 var embodied:=_embodied_reply(person,question,observations)
 var action:=_character_action(question)
 var remember_reply:=true
 var client: Node=game.host_openai
 var presentation:=Visuals.presentation_request(question)
 var visual_file:=Visuals.file_request(question)
 var active_room: Dictionary=game.lecture_classes.classes.get(room,{})
 var present_for_visual: bool=active_room.get("id","")==class_id and game.lecture_classes._inside(peer,room)
 if bool(turn.closed):pass
 elif not embodied.is_empty():reply=embodied
 elif not action.is_empty():
  var target:=_character_action_point(room,action,pos)
  var accepted:=false
  if bool(observations.player_visible):
   if action in CharacterMotion.POSES and target.is_finite() and bool(observations.get("has_arms",false)):
    _clear_reaction_pose(room)
    reaction_pose[room]={"model":model,"until":Time.get_ticks_msec()+2200,"requested_pose":action,"point":target}
    accepted=true
   elif action in ["approach","approach_board"]:
    accepted=_approach_in_lab(room,model,target) if room in ["ac_lab","dc_lab"] else _request_classroom_route(room,id,"conversation:"+str(Time.get_ticks_msec()),target,1.6,peer,Time.get_ticks_msec()+14000)
  reply=_character_action_reply(action,accepted)
  if action=="sit":reply="I'll stay standing up here."
  if action=="stand":reply="I'm already standing."
 elif not visual_file.is_empty() and present_for_visual:
  reply=Visuals.use_local_file(active_room,visual_file,game.lecture_classes._now()) if peer==multiplayer.get_unique_id() else "The session host manages saved animations."
 elif presentation.get("op","")=="pin_slide" and present_for_visual:
  reply=Visuals.pin_slide(active_room,int(current_stage.get("index",-1)),game.lecture_classes._now()) if peer==multiplayer.get_unique_id() else "The session host manages slide attachments."
 elif not presentation.is_empty() and present_for_visual and Visuals.apply(active_room,presentation,game.lecture_classes._now()):
  reply=presentation.reply
 elif str(turn.line).is_empty() and personal.is_empty() and is_instance_valid(client) and client.enabled and client.configured() and not client.busy:
  var checked: Dictionary=await client.moderate(question)
  if checked.get("ok",false) and not checked.get("flagged",false):
   var activity: Dictionary=_ai_activity(room)
   if str(activity.get("id",""))==class_id:
    var can_show: bool=game.lecture_classes.classes.get(room,{}).get("id","")==class_id and activity.get("phase")=="lesson"
    var visual:=Visuals.description(activity) if can_show else {}
    var wants_visual:=can_show and Visuals.requested(question,not visual.is_empty())
    var instructions:=CharacterMind.instructions(person,turn.emotion,str(activity.get("phase","")))
    var context: Dictionary={"classroom":TeacherAI.context(activity,id,current_stage).left(820),"knowledge":person.knowledge_domains,"observations":observations}
    if wants_visual:
     instructions=Visuals.instructions()+" "+instructions
     context.current_display=JSON.stringify(visual).left(1100)
    else:
     context.station_readings=lab_evidence.left(260)
     context.earlier_turns=TeacherAI.relevant_turns(history,question)
     context.reported_facts=brain.relevant_facts(turn.relationship,turn.domain)
     context.recent_experiences=turn.relationship.get("episodes",[]).slice(-3)
     context.relationship=brain.social_context(turn.relationship)
    var result: Dictionary=await client.respond_character(instructions,context,question,wants_visual)
    if result.get("ok",false):
     var plan:=Visuals.decode(str(result.get("text",""))) if wants_visual else {}
     var candidate:=TeacherAI.safe_reply(str(plan.get("speech","")) if wants_visual else str(result.get("text","")))
     var output_check: Dictionary=await client.moderate(str(plan.get("moderation",candidate)))
     if output_check.get("ok",false) and not output_check.get("flagged",false) and not candidate.is_empty():
      reply=candidate
      remember_reply=true
      if plan.get("action")!=null:
       var live: Dictionary=game.lecture_classes.classes.get(room,{})
       if live.get("id","")!=class_id or str(game.school.identities.get(peer,""))!=identity or not game.lecture_classes._inside(peer,room) or not Visuals.apply(live,plan.action,game.lecture_classes._now()):
        reply="I couldn't make that change. I'll keep the board as it is."
     else:reply="I can't answer that classroom question right now."
    else:reply=fallback
  elif checked.get("flagged",false):reply=str(person.lines.boundary);remember_reply=false
  else:reply=fallback
 ai_busy.erase(peer)
 var current_class: Dictionary=_ai_activity(room)
 if str(current_class.get("id",""))!=class_id or str(current_class.get("teacher",""))!=id or not game.lecture_classes._inside(peer,room):return
 if current_class.get("phase","")=="office_hours" and not _near_instructor(peer,room):return
 if remember_reply and not identity.is_empty() and str(game.school.identities.get(peer,""))==identity:
  _remember_character_turn(id,identity,question,reply,turn)
 if current_class.has("visual_playback"):game.lecture_classes._publish()
 _question_status(peer,room,id,reply)
 if reply.length()<=350 and not reply.begins_with("OpenAI"):
  _publish_attention(room,id,pos)
  if current_class.get("phase","")=="lesson":present_class_reaction(room,id,reply,3)
  else:
   var serial:=_next_speech(room)
   _show_reaction(room,id,reply,pos,serial,3)
   _broadcast_reaction(room,id,reply,pos,serial,3)
 if reaction_pose.has(room):reaction_pose[room].erase("requested_pose")
@rpc("any_peer","call_remote","reliable")
func _ask(room: String,intent: String,phone_id: String="") -> void:
 if multiplayer.is_server():_dialogue_request(multiplayer.get_remote_sender_id(),room,intent,phone_id)
func _dialogue_request(peer: int,room: String,intent: String,phone_id: String="") -> void:
 if not game.session.roster.has(peer) or intent not in ["inspect_circuit","evaluate_led","hand_phone","reclaim_phone"]:return
 var activity:=_ai_activity(room)
 var id:=str(activity.get("teacher",""))
 var point:=_teacher_position(room)
 var pos: Vector3=game.player.global_position if peer==multiplayer.get_unique_id() else game.session.poses.get(peer,{}).get("position",Vector3.INF)
 if not Roster.has(id) or not pos.is_finite() or not game.campus.registry.room_contains(room,pos):return
 if not (room=="ac_lab" and intent=="inspect_circuit") and (not point.is_finite() or pos.distance_to(point)>3.6):return
 var now:=Time.get_ticks_msec()
 if now-int(last_dialogue.get(peer,-1000))<350:return
 last_dialogue[peer]=now
 var reply: String
 if intent in ["hand_phone","reclaim_phone"]:
  reply=game.smartphones.teacher_handoff(peer,room,id,intent=="reclaim_phone",phone_id)
 elif room=="ac_lab" and intent=="inspect_circuit":
  reply=_ac_measurement_context(peer,activity)
  if reply.is_empty():reply="Come to your assigned or nearest available AC bench so I can inspect its instruments."
 else:
  reply=_inspect_student_circuit(peer,room,id,activity,intent=="evaluate_led")
 if peer==multiplayer.get_unique_id():_dialogue_reply(room,id,reply)
 elif game.session.online:_dialogue_reply.rpc_id(peer,room,id,reply)

func _ac_measurement_context(peer: int,activity: Dictionary) -> String:
 if not multiplayer.is_server() or not game.lecture_classes._inside(peer,"ac_lab"):return ""
 var position: Vector3=game.lecture_classes._position(peer)
 var identity:=str(game.school.identities.get(peer,""))
 var roster_entry: Dictionary=activity.get("students",{}).get(identity,{})
 var assigned:=int(roster_entry.get("bench",-1))
 var closest:=2.8
 var bench:=-1
 for index in game.session.labs.size():
  if assigned>=0 and index!=assigned:continue
  if assigned<0 and (activity.get("students",{}).values().any(func(member):return member.get("bench",-1)==index)
    or game.lecture_classes.lab_practice.work.get("bench",-1)==index):continue
  var point: Vector3=game.session.labs[index].positions.get("power",Vector3.INF)
  var distance:=position.distance_to(point)
  if distance<closest:closest=distance;bench=index
 if bench<0:return ""
 var lab: RefCounted=game.session.labs[bench]
 var text: String="Station %d · %d connected leads. "%[bench+1,lab.completed().size()]
 var fault: String=lab.readings.get("fault","")
 if not fault.is_empty():return text+"The simulator reports: "+fault.left(145)+". Verify wiring while power is off."
 if not lab.powered:return text+"Supply off. Check the connections and meter ranges before powering on."
 var volts: Array=lab.readings.get("voltmeters",[])
 var amps: Array=lab.readings.get("ammeters",[])
 return text+"Supply on at %.1f Hz. Highest voltmeter %.2f V RMS, highest ammeter %.4f A RMS. Zero can indicate an open path or unconnected meter."%[
  lab.frequency,float(volts.max()) if not volts.is_empty() else 0.,float(amps.max()) if not amps.is_empty() else 0.]

func _inspect_student_circuit(peer: int,room: String,teacher: String,activity: Dictionary,evaluate: bool=false) -> String:
 var office_hours: bool=activity.get("phase","")=="office_hours"
 var circuit_lesson: bool=activity.get("phase","")=="lesson" and activity.get("course","")=="ETY155"
 if not multiplayer.is_server() or room!="dc_lab" or not (office_hours or circuit_lesson) or str(activity.get("teacher",""))!=teacher:return "Circuit inspection is available during the DC circuit lesson or office hours."
 var events: Node=game.lecture_classes.classroom_events
 if not is_instance_valid(events) or not bool(events.enabled):return "Circuit inspection is unavailable right now."
 var identity:=str(game.school.identities.get(peer,""))
 if identity.is_empty() or not game.lecture_classes._inside(peer,room):return "Your student profile is unavailable."
 if not office_hours and int(activity.get("students",{}).get(identity,{}).get("peer",0))!=peer:return "Sign into this lesson before asking me to inspect your circuit."
 if not is_instance_valid(game.dc_lab):return "The DC benches are unavailable."
 var selected: Array=[]
 for index in mini(3,game.dc_lab.benches.size()):
  var station: RefCounted=game.dc_lab.benches[index]
  if int(station.board_owner)!=peer or station.board.is_empty():continue
  if game.campus.registry.locate(game.dc_lab.bench_position(index))!=room:continue
  selected.append(index)
 if selected.is_empty():return "Place your own board on a DC bench before asking me to inspect it."
 if selected.size()>1:return "You have boards at more than one DC bench. Leave one placed board to choose which circuit I should inspect."
 var bench:=int(selected[0])
 var board_station: RefCounted=game.dc_lab.benches[bench]
 if board_station.linked:return "Bench %d is linked to another bench. Separate the circuits before I inspect this board."%(bench+1)
 if board_station.board_held or board_station.board_stowed or not board_station.board_simulating():return "Place and connect your board at bench %d so the simulator can inspect its current circuit."%(bench+1)
 if board_station.solved_board_epoch!=board_station.board_epoch or board_station.solved_revision!=board_station.revision:return "Bench %d changed since the last solver step. Wait for the host simulation to update before I comment on this circuit."%(bench+1)
 var solved: Dictionary=board_station.result
 if solved.is_empty():return "The host has not produced a solver result for bench %d yet. Try again after the circuit updates."%(bench+1)
 if not bool(solved.get("ok",false)):return "Bench %d currently reports a solver fault. Switch off power and check the wiring before changing connections."%(bench+1)
 if evaluate:
  var result: Dictionary=InventionRubric.evaluate_led(board_station)
  return "LED objective · Bench %d: %s"%[bench+1,str(result.message)]
 return "The host solver has a result for your placed board at bench %d. That confirms only the current simulation state; explain the connections and compare an actual meter reading with your prediction."%(bench+1)
@rpc("authority","call_remote","reliable")
func _dialogue_reply(room: String,id: String,response: String) -> void:
 if not conversation.visible or conversation_room!=room or not conversation_student.is_empty() or not Roster.has(id):return
 conversation_name.text=str(Roster.entry(id).name)
 conversation_text.text=SpeechMath.display(response)
 conversation_scroll.set_deferred("scroll_vertical",0)

## A departure is considered only after this host has observed the student in
## an actual classroom chair. Lecture seating is free; no chair is assigned.
func _observe_classroom_seats() -> void:
 if not is_instance_valid(game) or not is_instance_valid(game.lecture_classes):return
 var classroom_events: Node=game.lecture_classes.classroom_events
 if not is_instance_valid(classroom_events) or not bool(classroom_events.enabled):
  seat_watch.clear();return
 var now:=Time.get_ticks_msec()/1000.0
 var active: Dictionary={}
 for room in LECTURE_ROOMS:
  var activity: Dictionary=game.lecture_classes.classes.get(room,{})
  if activity.get("phase","")!="lesson":continue
  var class_id:=str(activity.get("id",""))
  for identity in activity.get("students",{}):
   var peer:=int(activity.students[identity].get("peer",0))
   if not game.session.roster.has(peer) or not game.lecture_classes._inside(peer,room):continue
   var point: Vector3=game.lecture_classes._position(peer)
   if not point.is_finite():continue
   var key:=str(peer)
   active[key]=true
   var seated:=false
   var seat_point:=Vector3.ZERO
   for chair in game.chairs:
    if is_instance_valid(chair) and chair.occupant==peer and game.campus.registry.locate(chair.global_position)==room:
     seated=true;seat_point=chair.global_position;break
   var state: Dictionary=seat_watch.get(key,{})
   if str(state.get("class_id",""))!=class_id or str(state.get("identity",""))!=str(identity):state={"class_id":class_id,"identity":str(identity),"room":room,"saw_seat":false,"left_at":0.0,"seat_point":Vector3.ZERO,"next_notice":0.0}
   if seated:
    state.saw_seat=true;state.left_at=0.0;state.seat_point=seat_point
   elif state.saw_seat:
    if float(state.left_at)<=0.0:state.left_at=now
    var exempt:=false
    var events: Node=game.lecture_classes.classroom_events
    if is_instance_valid(events) and is_instance_valid(events.service):
     var event_state: Dictionary=events.service.rooms.get(room,{})
     var round: Variant=event_state.get("round")
     exempt=round!=null and is_instance_valid(round) and not round.closed and event_state.get("hands")!=null and str(event_state.hands.selected)==str(identity)
    if exempt:state.left_at=now
    elif now-float(state.left_at)>=8.0 and now>=float(state.next_notice) and point.distance_to(state.seat_point)>=2.0:
     state.next_notice=now+60.0
     report_event(peer,room,"seat_departure",point,.35)
   seat_watch[key]=state
 for key in seat_watch.keys():
  if not active.has(key):seat_watch.erase(key)

## Host observation used only to prioritize an optional classroom question.
## It never assigns a seat, starts discipline, or changes a grade.
func classroom_distracted(room: String,class_id: String,identity: String,now: float) -> bool:
 if not multiplayer.is_server() or not is_finite(now):return false
 var activity: Dictionary=game.lecture_classes.classes.get(room,{})
 if activity.get("phase","")!="lesson" or str(activity.get("id",""))!=class_id:return false
 var peer:=int(activity.get("students",{}).get(identity,{}).get("peer",0))
 if peer<=0 or not game.session.roster.has(peer) or not game.lecture_classes._inside(peer,room):return false
 var state: Dictionary=seat_watch.get(str(peer),{})
 if not bool(state.get("saw_seat",false)) or str(state.get("class_id",""))!=class_id or str(state.get("identity",""))!=identity or str(state.get("room",""))!=room:return false
 var left_at:=float(state.get("left_at",0.0))
 var point: Vector3=game.lecture_classes._position(peer)
 var seat_point: Vector3=state.get("seat_point",Vector3.ZERO)
 return left_at>0.0 and now-left_at>=5.0 and point.is_finite() and point.distance_to(seat_point)>=2.0

## Server-only entry point. Message context is used transiently and is not stored.
func report_equipment_fault(peer: int,station: int,action: Dictionary,before: Dictionary) -> void:
 if not multiplayer.is_server() or not game.session.roster.has(peer) or station<0 or station>=game.session.labs.size() or action.is_empty():return
 var lab: RefCounted=game.session.labs[station]
 var previous:=str(before.get("readings",{}).get("fault",""))
 var current:=str(lab.readings.get("fault",""))
 if current.is_empty() or current==previous:return
 var at: Vector3=game.player.global_position if peer==multiplayer.get_unique_id() else game.session.poses.get(peer,{}).get("position",Vector3.INF)
 if not at.is_finite() or game.campus.registry.locate(at)!="ac_lab":return
 verified_incidents.append({"peer":peer,"station":station,"kind":"equipment_fault","fault":current.left(120),"time":Time.get_ticks_msec()})
 if verified_incidents.size()>64:verified_incidents.pop_front()
 report_event(peer,"ac_lab","lab_hazard",at,1.0,{"verified_station":station,"verified_fault":current.left(120)})

func report_projectile_impact(id: int) -> void:
 if not multiplayer.is_server() or not is_instance_valid(game.classroom_projectiles):return
 var incident: Dictionary=game.classroom_projectiles.impacts.get(id,{})
 if incident.is_empty() or Time.get_ticks_msec()-int(incident.get("time",0))>1000:return
 report_event(int(incident.peer),str(incident.room),"thrown_object",incident.position,.8 if incident.kind=="property" else 1.0,{"impact_id":id,"impact_kind":str(incident.kind)})

func report_event(peer: int,room: String,kind: String,position: Vector3,severity: float,context: Dictionary={}) -> bool:
 if not multiplayer.is_server() or not game.session.roster.has(peer) or not position.is_finite():return false
 if kind=="thrown_object":
  var impact_id:=int(context.get("impact_id",-1))
  var impact: Dictionary=game.classroom_projectiles.impacts.get(impact_id,{}) if is_instance_valid(game.classroom_projectiles) else {}
  if impact.is_empty() or int(impact.get("peer",0))!=peer or str(impact.get("room",""))!=room or impact.get("position",Vector3.INF)!=position or Time.get_ticks_msec()-int(impact.get("time",0))>1000:return false
  game.classroom_projectiles.impacts.erase(impact_id)
 if kind=="lab_hazard":
  var station:=int(context.get("verified_station",-1))
  var fault:=str(context.get("verified_fault",""))
  if station<0 or station>=game.session.labs.size() or fault.is_empty() or str(game.session.labs[station].readings.get("fault","")).left(120)!=fault:return false
  if verified_incidents.is_empty() or int(verified_incidents.back().get("peer",0))!=peer or int(verified_incidents.back().get("station",-1))!=station or str(verified_incidents.back().get("fault",""))!=fault or Time.get_ticks_msec()-int(verified_incidents.back().get("time",0))>1000:return false
  verified_incidents.pop_back()
 if kind not in ["lab_hazard","class_message","addressed_speech","voice_noise","ambient_speech","phone_use","seat_departure","thrown_object"] or room not in (["ac_lab","dc_lab"] + LECTURE_ROOMS):return false
 var activity:=_ai_activity(room)
 var identity:=str(game.school.identities.get(peer,""))
 if identity.is_empty():return false
 if kind in ["voice_noise","phone_use","seat_departure"]:
  var actual: Vector3=game.player.global_position if peer==multiplayer.get_unique_id() else game.session.poses.get(peer,{}).get("position",Vector3.INF)
  if not actual.is_finite() or actual.distance_to(position)>.5 or game.campus.registry.locate(actual)!=room:return false
  var classroom: Dictionary={}
  var events: Node=game.lecture_classes.classroom_events
  if is_instance_valid(events) and is_instance_valid(events.service):classroom=events.service.rooms.get(room,{})
  if kind=="voice_noise" and VoicePolicy.permitted(peer,identity,activity,classroom,Time.get_ticks_msec()/1000.0):return false
 if not brain.context_allows(kind,str(activity.get("phase","")),severity):return false
 var id:=str(activity.get("teacher",""))
 if not Roster.has(id):return false
 var origin:=_teacher_position(room)
 if not origin.is_finite():return false
 var distance:=origin.distance_to(position)
 if distance>=10.0:return false
 var query:=PhysicsRayQueryParameters3D.create(origin+Vector3.UP*1.4,position+Vector3.UP*1.4,1)
 if is_instance_valid(game.player):query.exclude=[game.player.get_rid()]
 var blocked:=not get_world_3d().direct_space_state.intersect_ray(query).is_empty()
 var audible: float=brain.audibility(kind,distance,blocked)
 var noticed:=audible
 if kind in ["phone_use","seat_departure"]:
  var phone_model:=_model_for_room(room,id)
  noticed=brain.visibility(origin,phone_model.global_basis.z,position,blocked) if is_instance_valid(phone_model) else 0.0
 if kind=="lab_hazard":
  var model:=_model_for_room(room,id)
  if is_instance_valid(model):noticed=maxf(noticed,brain.visibility(origin,model.global_basis.z,position,blocked))
 if noticed<=0.0:return false
 var personality: Dictionary=Dialogue.personalities().get(id,{})
 var decision:=brain.consider(id,identity,kind,clampf(severity,0.0,1.0),personality,Time.get_ticks_msec(),rng.randf(),noticed)
 if decision.is_empty():return false
 if kind=="addressed_speech":
  decision.intent=Dialogue.message_intent(str(context.get("message","")))
  if decision.intent=="apology":brain.accept_apology(id,identity,Time.get_ticks_msec())
 elif kind=="class_message" and Dialogue.message_intent(str(context.get("message","")))=="rude":
  decision.intent="rude"
 var active_round: Dictionary={}
 var class_events: Node=game.lecture_classes.classroom_events
 if is_instance_valid(class_events) and is_instance_valid(class_events.service):active_round=class_events.service.rooms.get(room,{})
 var round: Variant=active_round.get("round")
 var response_context:={"course":str(activity.get("course","the lab")),"in_class":not activity.is_empty(),"phase":str(activity.get("phase","")),"level":str(decision.get("level","calm")),"message":str(context.get("message","")).left(240),"round_mode":str(round.mode) if round!=null and is_instance_valid(round) else ""}
 if kind=="thrown_object":response_context.impact_kind=str(context.get("impact_kind",""))
 if response_context.round_mode=="group" and is_instance_valid(class_events) and is_instance_valid(class_events.service):
  response_context.team_progress=class_events.service.view(peer,room,Time.get_ticks_msec()/1000.0).get("team_progress",{})
 if response_context.round_mode=="physical" and is_instance_valid(class_events) and is_instance_valid(class_events.service):
  var physical_view: Dictionary=class_events.service.view(peer,room,Time.get_ticks_msec()/1000.0)
  response_context.physical_state={"fault":bool(physical_view.get("equipment_fault",false)),"changed":bool(physical_view.get("measurement_changed",false))}
 if decision.intent=="demonstration_request" and is_instance_valid(class_events) and class_events.has_method("request_demonstration"):
  response_context.scheduled=bool(class_events.call("request_demonstration",peer,room,id,Time.get_ticks_msec()/1000.0))
 var text:=Dialogue.respond(id,str(decision.intent),response_context,rng.randi_range(0,8))
 if kind in ["class_message","voice_noise","phone_use","seat_departure","thrown_object","lab_hazard"]:
  character_mind.react_to_disruption(Characters.teacher(id),severity,Time.get_ticks_msec())
 if kind in ["class_message","voice_noise","phone_use"] and str(decision.get("level",""))=="firm" and activity.get("phase","")=="lesson" and is_instance_valid(class_events) and class_events.has_method("request_board_challenge"):
  class_events.call("request_board_challenge",peer,room,id,Time.get_ticks_msec()/1000.0)
 var speech_id:=_next_speech(room)
 var priority:=4 if kind in ["lab_hazard","thrown_object"] else (3 if kind in ["class_message","voice_noise","phone_use"] else 1)
 _show_reaction(room,id,text,position,speech_id,priority)
 if kind in ["class_message","voice_noise","phone_use"] and activity.get("phase","")=="lesson":classroom_disruption.emit(room,id)
 if priority>=3 and activity.get("phase","")=="lesson" and is_instance_valid(class_events) and class_events.enabled:
  _request_classroom_route(room,id,"reaction:"+str(speech_id),position,1.8,peer,Time.get_ticks_msec()+6500)
 _broadcast_reaction(room,id,text,position,speech_id,priority)
 return true
func _teacher_position(room: String) -> Vector3:
 if room in ["ac_lab","dc_lab"]:
  var mount: Node3D=game.school_world.teacher if room=="ac_lab" else game.school_world.dc_instructor
  var model:=mount.get_node_or_null("InstructorModel") as Node3D
  return model.global_position if is_instance_valid(model) else mount.global_position
 if is_instance_valid(lecture_models.get(room)):return lecture_models[room].global_position
 if game.lecture_classes.signs.has(room):return game.lecture_classes.signs[room].desk
 return Vector3.INF

func _near_instructor(peer: int,room: String) -> bool:
 var position: Vector3=game.lecture_classes._position(peer)
 var instructor:=_teacher_position(room)
 return position.is_finite() and instructor.is_finite() and position.distance_to(instructor)<=4.5
func _on_player_message(peer: int,_sender: String,message: String) -> void:
 if not multiplayer.is_server():return
 var position: Vector3=game.player.global_position if peer==multiplayer.get_unique_id() else game.session.poses.get(peer,{}).get("position",Vector3.INF)
 if not position.is_finite():return
 var room: String=game.campus.registry.locate(position)
 var activity:=_ai_activity(room)
 var id:=str(activity.get("teacher",""))
 if not Roster.has(id):return
 var teacher_name:=str(Roster.entry(id).name).to_lower()
 var words:=message.to_lower()
 var addressed:=not teacher_name.is_empty() and words.contains(teacher_name)
 if activity.get("phase","")=="assignment":report_event(peer,room,"class_message",position,.45,{"message":message})
 elif addressed:
  if Dialogue.message_intent(message)=="rude":report_event(peer,room,"class_message",position,.7,{"message":message})
  else:report_event(peer,room,"addressed_speech",position,.6,{"message":message})
 elif activity.get("phase","")=="lesson":
  report_event(peer,room,"class_message",position,.25,{"message":message})
  _observe_class_overlap(peer,room,activity,position)
 else:report_event(peer,room,"ambient_speech",position,.25,{"message":message})

## Two distinct, signed students posting within a short window can draw one
## shared reminder. Chat content and individual blame are not retained here.
func _observe_class_overlap(peer: int,room: String,activity: Dictionary,point: Vector3) -> void:
 var events: Node=game.lecture_classes.classroom_events
 if not is_instance_valid(events) or not bool(events.enabled) or activity.get("phase","")!="lesson":return
 var identity:=str(game.school.identities.get(peer,""))
 if identity.is_empty() or int(activity.get("students",{}).get(identity,{}).get("peer",0))!=peer or not game.lecture_classes._inside(peer,room):return
 var teacher:=str(activity.get("teacher",""))
 var origin:=_teacher_position(room)
 if not Roster.has(teacher) or not origin.is_finite() or origin.distance_to(point)>7.0:return
 var now:=Time.get_ticks_msec()/1000.0
 var state: Dictionary=class_overlap.get(room,{})
 if str(state.get("class_id",""))!=str(activity.get("id","")):state={"class_id":str(activity.get("id","")),"first_peer":0,"first_at":0.0,"next_notice":0.0}
 if now<float(state.next_notice):class_overlap[room]=state;return
 if int(state.first_peer)>0 and int(state.first_peer)!=peer and game.session.roster.has(int(state.first_peer)) and game.lecture_classes._inside(int(state.first_peer),room) and now-float(state.first_at)<=2.0:
  state.first_peer=0;state.next_notice=now+30.0
  class_overlap[room]=state
  var text: String=Dialogue.overlap_comment(Dialogue.personalities().get(teacher,{}))
  var serial:=_next_speech(room)
  _show_reaction(room,teacher,text,point,serial,2)
  _broadcast_reaction(room,teacher,text,point,serial,2)
  return
 state.first_peer=peer;state.first_at=now;class_overlap[room]=state
func _model_for_room(room: String,id: String) -> Node3D:
 if room in ["ac_lab","dc_lab"]:
  var root: Node3D=game.school_world.teacher if room=="ac_lab" else game.school_world.dc_instructor
  var lab_model:=root.get_node_or_null("InstructorModel") as Node3D
  return lab_model if is_instance_valid(lab_model) and lab_model.get_meta("faculty_id","")==id else null
 var model: Node3D=lecture_models.get(room)
 if is_instance_valid(model) and model.get_meta("faculty_id","")==id:return model
 return null

func _set_attention(room: String,id: String,point: Vector3) -> void:
 var model:=_model_for_room(room,id)
 if not is_instance_valid(model) or not point.is_finite():return
 var local_point:=model.get_parent_node_3d().to_local(point)
 var direction:=local_point-model.position;direction.y=0.0
 if direction.length_squared()<.0001:return
 var previous: Dictionary=attention.get(room,{})
 var rest: float=float(previous.get("rest",model.rotation.y)) if previous.get("model")==model else model.rotation.y
 attention[room]={"model":model,"rest":rest,"target":atan2(direction.x,direction.z),"until":Time.get_ticks_msec()+7000}

func _publish_attention(room: String,id: String,point: Vector3) -> void:
 _set_attention(room,id,point)
 if not game.session.online:return
 for peer in game.session.roster:
  if int(peer)==multiplayer.get_unique_id() or not game.session.peer_connected_now(int(peer)):continue
  var at: Vector3=game.session.poses.get(peer,{}).get("position",Vector3.INF)
  if at.is_finite() and game.campus.registry.locate(at)==room:_attention.rpc_id(int(peer),room,id,point)

func present_class_reaction(room: String,id: String,text: String,priority: int=1) -> void:
 if not multiplayer.is_server() or text.is_empty() or text.length()>350 or priority<1 or priority>3:return
 var activity: Dictionary=game.lecture_classes.classes.get(room,{})
 if str(activity.get("teacher",""))!=id or activity.get("phase","")!="lesson":return
 var point:=_teacher_position(room)
 if not point.is_finite():return
 var speech_id:=_next_speech(room)
 _show_reaction(room,id,text,point,speech_id,priority)
 _broadcast_reaction(room,id,text,point,speech_id,priority)

func acknowledge_attendance(room: String, teacher: String, peer: int) -> void:
 if not Roster.has(teacher): return
 var point := _teacher_position(room)
 if not point.is_finite(): return
 var serial := _next_speech(room)
 var message := "You're marked present. Find a seat and join us when you're ready."
 if peer == multiplayer.get_unique_id():
  _show_reaction(room,teacher,message,point,serial)
 elif game.session.online and game.session.peer_connected_now(peer):
  _reaction.rpc_id(peer,room,teacher,message,point,serial)

func present_assessment_intro(room: String,id: String,course: String) -> void:
 if not multiplayer.is_server() or not Roster.has(id):return
 var activity: Dictionary=game.lecture_classes.classes.get(room,{})
 if activity.get("phase","")!="assignment" or str(activity.get("teacher",""))!=id or str(activity.get("course",""))!=course:return
 var point:=_teacher_position(room)
 if not point.is_finite():return
 if is_instance_valid(speech_player):speech_player.cancel(room)
 if is_instance_valid(speech_synth):speech_synth.cancel(room)
 _clear_reaction_pose(room)
 classroom_phase[room]="assignment"
 var text:=Dialogue.assessment_intro(Dialogue.personalities().get(id,{}),course)
 var serial:=_next_speech(room)
 _show_reaction(room,id,text,point,serial,2)
 _broadcast_reaction(room,id,text,point,serial,2)

func _next_speech(room: String) -> int:
 var serial:=int(speech_serial.get(room,0))+1
 speech_serial[room]=serial
 return serial

static func speech_cache_key(id: String,text: String) -> String:
 return id+":"+text.sha256_text()

func _provider_speech_key(id: String,text: String,delivery: Dictionary) -> String:
 return id+":openai:"+JSON.stringify([text,game.host_openai.tts_model,delivery]).sha256_text()

func _broadcast_reaction(room: String,id: String,text: String,point: Vector3,serial: int,priority: int) -> void:
 if not game.session.online:return
 var provider:=_uses_class_voice()
 var mood:=character_mind.emotion(Characters.teacher(id),Time.get_ticks_msec())
 var pose: Dictionary=reaction_pose.get(room,{})
 var gesture:=str(pose.get("requested_pose",""))
 var gesture_point: Vector3=pose.get("point",Vector3.INF)
 for peer in _voice_recipients(room):
  _reaction.rpc_id(peer,room,id,text,point,serial,priority,provider,mood,false,gesture,gesture_point)

func _voice_recipients(room: String) -> Array[int]:
 var recipients: Array[int]=[]
 if not multiplayer.is_server() or not game.session.online:return recipients
 for peer in game.session.roster:
  if int(peer)!=multiplayer.get_unique_id() and game.session.peer_connected_now(int(peer)) and game.lecture_classes._inside(int(peer),room):
   recipients.append(int(peer))
 return recipients

func _uses_class_voice() -> bool:
 return is_instance_valid(game.host_openai) and game.host_openai.tts_enabled and game.host_openai.enabled and game.host_openai.configured()

func present_class_call(room: String,id: String,peer: int) -> void:
 if not multiplayer.is_server() or not game.session.roster.has(peer):return
 var activity: Dictionary=game.lecture_classes.classes.get(room,{})
 if activity.get("phase","")!="lesson" or str(activity.get("teacher",""))!=id:return
 var identity:=str(game.school.identities.get(peer,""))
 if identity.is_empty() or not activity.get("students",{}).has(identity) or int(activity.students[identity].get("peer",0))!=peer or bool(activity.students[identity].get("done",false)):return
 var events: Node=game.lecture_classes.classroom_events
 if not is_instance_valid(events) or not events.enabled or not is_instance_valid(events.service):return
 var state: Dictionary=events.service.rooms.get(room,{})
 if state.is_empty() or str(state.get("class_id",""))!=str(activity.get("id","")) or state.hands.selected!=identity or state.round.closed or not state.round.present.has(identity) or not game.lecture_classes._inside(peer,room):return
 var point: Vector3=game.player.global_position if peer==multiplayer.get_unique_id() else game.session.poses.get(peer,{}).get("position",Vector3.INF)
 if not point.is_finite() or game.campus.registry.locate(point)!=room:return
 var text:=Dialogue.respond(id,"call_on",{"course":str(activity.get("course","")),"in_class":true,"phase":"lesson"},int(state.round.event_id.hash()))
 var serial:=_next_speech(room)
 class_calls[room]={"class_id":str(activity.id),"event_id":str(state.round.event_id),"identity":identity,"serial":serial}
 _request_classroom_route(room,id,"event:"+str(activity.id)+":"+str(state.round.event_id)+":called:"+str(peer),point,1.8,peer)
 _publish_attention(room,id,point)
 _show_reaction(room,id,text,point,serial,2)
 _broadcast_reaction(room,id,text,point,serial,2)

func _prune_class_calls() -> void:
 if class_calls.is_empty() or not is_instance_valid(game):return
 var events: Node=game.lecture_classes.classroom_events
 for room in class_calls.keys():
  var call: Dictionary=class_calls[room]
  var activity: Dictionary=game.lecture_classes.classes.get(room,{})
  var state: Dictionary=events.service.rooms.get(room,{}) if is_instance_valid(events) and is_instance_valid(events.service) else {}
  if activity.get("phase","")=="lesson" and str(activity.get("id",""))==str(call.class_id) and not state.is_empty() and str(state.round.event_id)==str(call.event_id) and not state.round.closed and str(state.hands.selected)==str(call.identity):continue
  if is_instance_valid(speech_player) and int(speech_player.last_serial.get(room,0))==int(call.serial):
   speech_player.cancel(room)
   if is_instance_valid(speech_synth):speech_synth.cancel(room)
  class_calls.erase(room)

@rpc("authority","call_remote","reliable")
func _attention(room: String,id: String,point: Vector3) -> void:_set_attention(room,id,point)
@rpc("authority","call_remote","reliable")
func _reaction(room: String,id: String,text: String,point: Vector3,serial: int=0,priority: int=1,provider := false,mood := "steady",raised := false,gesture := "",gesture_point := Vector3.INF) -> void:
 if serial>0 and is_instance_valid(speech_player) and serial<=int(speech_player.last_serial.get(room,0)):return
 if room in ["ac_lab","dc_lab"]:
  var activity:=_lab_visit(room)
  var visible_id:=str(activity.get("teacher",""))
  if visible_id!=id:return
 if room in LECTURE_ROOMS and not is_instance_valid(_model_for_room(room,id)):return
 _show_reaction(room,id,text,point,serial,priority,provider,mood,raised,gesture,gesture_point)

func _character_pitch(mood: String) -> float:
 return CharacterMotion.pitch(mood)

func _character_gesture(key: String,model: Node3D,mood: String,raised: bool,gesture := "",point := Vector3.INF) -> void:
 _clear_reaction_pose(key)
 var pose:=gesture if gesture in CharacterMotion.POSES else ("raise_hand" if raised else "")
 reaction_pose[key]={"model":model,"until":Time.get_ticks_msec()+2200,"mood":mood,"gesture":pose,"requested":raised,"requested_pose":gesture,"point":point}
 if key=="classmate" and raised:model.set_meta("conversation_hand_until",reaction_pose[key].until)

func _show_reaction(room: String,id: String,text: String,point: Vector3,serial: int=0,priority: int=1,provider := false,mood := "steady",raised := false,gesture := "",gesture_point := Vector3.INF) -> void:
 if not Roster.has(id):return
 text=SpeechMath.display(text).left(350)
 var root: Node3D
 if room=="ac_lab":root=game.school_world.teacher
 elif room=="dc_lab":root=game.school_world.dc_instructor
 else:root=lecture_models.get(room)
 if not is_instance_valid(root):return
 if not is_instance_valid(_model_for_room(room,id)):return
 _set_attention(room,id,point)
 if multiplayer.is_server():
  mood=character_mind.emotion(Characters.teacher(id),Time.get_ticks_msec())
  var pending: Dictionary=reaction_pose.get(room,{})
  gesture=str(pending.get("requested_pose",""))
  gesture_point=pending.get("point",Vector3.INF)
 if gesture=="point" and gesture_point.is_finite():_set_attention(room,id,gesture_point)
 if priority>=2 or mood!="steady":
  _character_gesture(room,_model_for_room(room,id),mood,raised,gesture,gesture_point)
 if is_instance_valid(reaction_labels.get(room)):reaction_labels[room].queue_free()
 if room not in LECTURE_ROOMS or serial <= 0:
  var label:=Label3D.new();label.text=text.left(220);label.position.y=2.35;label.billboard=BaseMaterial3D.BILLBOARD_ENABLED;label.pixel_size=.003;label.font_size=30;label.outline_size=7;label.modulate=Color("f3faf5");label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;label.width=420;label.visibility_range_end=13;root.add_child(label)
  reaction_labels[room]=label;reaction_until[room]=Time.get_ticks_msec()+7000
 if serial>0 and is_instance_valid(speech_player):
  speech_player.configure(bool(game.client_preferences.values.teacher_speech),bool(game.client_preferences.values.teacher_subtitles))
  var local_room: String=game.campus.registry.locate(game.player.global_position)
  var use_openai: bool=multiplayer.is_server() and _uses_class_voice() and (local_room==room or not _voice_recipients(room).is_empty())
  var delivery:=Characters.speech(Characters.teacher(id),str(game.host_openai.tts_model),priority,mood) if use_openai else {}
  var key:=speech_cache_key(id,text)
  if not delivery.is_empty():key=_provider_speech_key(id,text,delivery)
  var stream: AudioStreamWAV=speech_player.stream_for(key)
  speech_player.accept(room,str(Roster.entry(id).name),serial,text,priority,root,stream,1. if provider or use_openai else _character_pitch(mood))
  if provider:
   pending_voice[room]={"serial":serial,"teacher":id,"text":text,"priority":priority}
   return
  if stream!=null and not delivery.is_empty():
   _send_voice_clip.call_deferred(room,serial,stream)
  elif stream==null and (speech_player.speech_enabled or use_openai) and is_instance_valid(speech_synth):
   _request_reaction_audio(room,serial,id,text,key,priority+(10 if local_room==room else 0),delivery)

func _request_reaction_audio(room: String,serial: int,id: String,text: String,key: String,priority: int,delivery: Dictionary) -> void:
 if not delivery.is_empty():
  var result: Dictionary=await game.host_openai.speak(text.left(350),{},delivery.voice,delivery)
  if not is_instance_valid(speech_player) or serial!=int(speech_player.last_serial.get(room,0)):return
  if result.get("ok",false):
   _speech_completed(room,serial,key,result.stream,"ok")
   _send_voice_clip(room,serial,result.stream)
   return
  for peer in _voice_recipients(room):_voice_fallback.rpc_id(peer,room,serial)
 if is_instance_valid(speech_synth):
  speech_synth.request(room,serial,id,text,speech_cache_key(id,text),priority)

func _speech_completed(room: String,serial: int,key: String,stream: AudioStreamWAV,status: String) -> void:
 if status!="ok" or stream==null or not is_instance_valid(speech_player):return
 if speech_player.cache_stream(key,stream):speech_player.deliver_stream(room,serial,stream)

func _send_voice_clip(room: String,serial: int,stream: AudioStreamWAV) -> void:
 if serial!=int(speech_player.last_serial.get(room,0)):return
 for peer in _voice_recipients(room):_send_voice_clip_to(peer,room,serial,stream)

func _send_voice_clip_to(peer: int,room: String,serial: int,stream: AudioStreamWAV) -> void:
 if stream==null or stream.format!=AudioStreamWAV.FORMAT_16_BITS or stream.data.is_empty() or stream.data.size()>768000:
  _voice_fallback.rpc_id(peer,room,serial)
  return
 var samples:=stream.data
 for offset in range(0,samples.size(),12000):
  _voice_chunk.rpc_id(peer,room,serial,samples.size(),offset,stream.mix_rate,stream.stereo,samples.slice(offset,offset+12000))

@rpc("authority","call_remote","reliable")
func _voice_fallback(room: String,serial: int) -> void:
 var pending: Dictionary=pending_voice.get(room,{})
 if pending.get("serial")!=serial or int(speech_player.last_serial.get(room,0))!=serial:return
 pending_voice.erase(room)
 if speech_player.speech_enabled:speech_synth.request(room,serial,pending.teacher,pending.text,speech_cache_key(pending.teacher,pending.text),pending.priority)

@rpc("authority","call_remote","reliable")
func _voice_chunk(room: String,serial: int,total: int,offset: int,rate: int,stereo: bool,chunk: PackedByteArray) -> void:
 if not speech_player.speech_enabled or pending_voice.get(room,{}).get("serial")!=serial or int(speech_player.last_serial.get(room,0))!=serial:return
 if total<=0 or total>768000 or chunk.is_empty() or chunk.size()>12000 or offset<0 or offset+chunk.size()>total or rate not in range(8000,48001):return
 if offset==0:received_voice[room]={"serial":serial,"total":total,"rate":rate,"stereo":stereo,"bytes":PackedByteArray()}
 var transfer: Dictionary=received_voice.get(room,{})
 if transfer.get("serial")!=serial or transfer.get("total")!=total or transfer.get("rate")!=rate or transfer.get("stereo")!=stereo or transfer.bytes.size()!=offset:return
 var bytes: PackedByteArray=transfer.bytes
 bytes.append_array(chunk)
 transfer.bytes=bytes
 if bytes.size()!=total:return
 pending_voice.erase(room)
 received_voice.erase(room)
 var stream:=AudioStreamWAV.new()
 stream.format=AudioStreamWAV.FORMAT_16_BITS
 stream.mix_rate=rate
 stream.stereo=stereo
 stream.data=bytes
 speech_player.deliver_stream(room,serial,stream)
