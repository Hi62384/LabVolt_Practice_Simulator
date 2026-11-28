extends Node3D
const Roster=preload("res://scripts/campus/academics/faculty_roster.gd")
const Toon=preload("res://scripts/toon_character.gd")
const CharacterFace=preload("res://scripts/campus/academics/character_face.gd")
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
var question_channels: Dictionary={}
var voice_invitations: Dictionary={}
var voice_room_contexts: Dictionary={}
var voice_channel_rooms: Dictionary={}
var questions: Array[Dictionary]=[]
var ai_stage:={}
var lesson_feedback:={}
var brain=preload("res://scripts/campus/academics/teacher_brain.gd").new()
const CharacterMind=preload("res://scripts/campus/academics/character_mind.gd")
const CharacterBehavior=preload("res://scripts/campus/academics/character_behavior.gd")
const CharacterMotion=preload("res://scripts/campus/academics/character_motion.gd")
const CharacterAffect=preload("res://scripts/campus/academics/character_affect.gd")
var character_mind:=CharacterMind.new()
const CharacterInteraction=preload("res://scripts/campus/academics/character_interaction.gd")
const CharacterSpeech=preload("res://scripts/campus/academics/character_speech.gd")
const Discipline=preload("res://scripts/campus/academics/classroom_discipline.gd")
const DossierStore=preload("res://scripts/campus/academics/character_dossier_store.gd")
const DossierGeneration=preload("res://scripts/campus/academics/character_dossier_generation.gd")
const Personas=preload("res://scripts/campus/academics/character_personas.gd")
var character_interaction:=CharacterInteraction.new()
var character_generation:=DossierGeneration.new()
var character_generation_clock:=0.0
var character_epoch:=0
var character_jobs:=0
var discipline_records: Dictionary={}
var character_debug: Window
var character_debug_text: TextEdit
var appearance_catalog: Dictionary={}
var reaction_labels:={}
var reaction_until:={}
var speech_player: Node
var speech_synth: Node
var speech_serial:={}
var speech_turn_timings: Dictionary={}
var received_voice:={}
var voice_transfer=preload("res://scripts/campus/voice/speech_audio_transfer.gd").new()
var speech_routes: Dictionary={}
var natural_voice: Node
var shared_microphone: Node
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
 brain.bind_mind(character_mind)
 character_interaction.bind(character_mind,brain)
 var events: Node=game.lecture_classes.classroom_events
 if is_instance_valid(events):classroom_disruption.connect(events.on_teacher_disruption)
 if multiplayer.is_server():_sync_character_profile()
 _build_conversation_ui()
 speech_player=SpeechPlayer.new();speech_player.name="TeacherSpeechPlayer";add_child(speech_player)
 speech_player.playback_started.connect(_character_audio_started)
 speech_synth=SpeechSynth.new();speech_synth.name="TeacherSpeechSynth";add_child(speech_synth)
 speech_synth.completed.connect(_speech_completed)
 speech_synth.configure_provider(game.host_openai)
 shared_microphone=preload("res://scripts/campus/voice/microphone_capture.gd").shared(self)
 shared_microphone.packet_ready.connect(_manual_capture_packet)
 tree_exiting.connect(_cancel_recording)
 natural_voice=preload("res://scripts/campus/voice/npc_voice_router.gd").new();natural_voice.name="NaturalVoice";add_child(natural_voice);natural_voice.build(game,self)
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
func _sync_character_profile() -> bool:
 if not multiplayer.is_server():return false
 var profile:=str(game.school.local_identity)
 if profile.is_empty():memory_error=ERR_INVALID_PARAMETER;return false
 if profile==brain.host_profile() and DossierStore.host_identity==profile:return true
 # Finish an already-perceived exchange in its original host namespace.
 if character_jobs>0 or not ai_busy.is_empty() or game.host_openai.busy:return false
 character_generation.cancel()
 var error: Error=brain.set_host_profile(profile)
 if error!=OK:
  memory_error=error
  return false
 character_epoch+=1
 discipline_records.clear()
 character_interaction.diagnostics.clear()
 if not brain.load_memory():
  memory_error=ERR_FILE_CORRUPT
  push_warning("Character memory could not be loaded; the existing files are preserved for recovery.")
 else:memory_error=OK
 var dossier_error:=DossierStore.set_host_profile(profile)
 if dossier_error!=OK:push_warning("Character dossiers could not be loaded; existing data is preserved.")
 for teacher_id in Roster.all_people():
  var person:=Characters.teacher(str(teacher_id))
  # Only older save formats carried these authored anchors. A new host's first
  # conversation must not introduce legacy personal answers at the next load.
  var existing_history: bool=int(brain.loaded_memory_version)<8
  if existing_history:
   var prior: Dictionary=Personas.legacy_biography(str(teacher_id))
   var saved: Dictionary=brain.biographies.get_or_add(teacher_id,{})
   for topic in prior:
    if not saved.has(topic):saved[topic]=prior[topic];brain.memory_dirty=true
  if DossierStore.get_dossier(str(teacher_id)).get("generation",{}).get("status")!="complete":
   DossierStore.preserve_biography(str(teacher_id),brain.character_biography(person))
 if is_instance_valid(game.lecture_classes.classroom_students):game.lecture_classes.classroom_students.configure(game)
 character_generation.configure(game.host_openai,game.lecture_classes.classroom_students.population,brain)
 return true

## Host-only completion callbacks supply an already checked outcome. Never
## accept an answer, numeric mark, or a conversational claim through this path.
func record_human_academic_outcome(activity: Dictionary,identity: String,kind: String,correct: bool,event_id: String) -> bool:
 if not multiplayer.is_server() or not is_instance_valid(game):return false
 var profile:=str(game.school.local_identity)
 if profile.is_empty() or profile!=brain.host_profile():return false
 if identity.is_empty() or identity.begins_with("campus_student_") or event_id.is_empty():return false
 if str(activity.get("id","")).is_empty() or not activity.get("students",{}).has(identity):return false
 var teacher_id:=str(activity.get("teacher",""))
 if not Roster.has(teacher_id):return false
 var teacher:=Characters.teacher(teacher_id)
 var token:="human_activity:"+JSON.stringify([activity.id,event_id,identity,kind]).sha256_text()
 return brain.remember_activity(teacher,identity,kind,str(activity.get("course","")),correct,
  int(Time.get_unix_time_from_system()),token,int(activity.get("week",0)))

func _clear_speech() -> void:
 character_generation.cancel()
 _cancel_recording()
 _stop_voice_conversation()
 ai_stage.clear()
 character_epoch+=1
 _save_memory()
 discipline_records.clear()
 lesson_feedback.clear()
 for room in ["ac_lab","dc_lab"]:_hide_lab(room)
 lab_routes.clear();lab_entries.clear();lab_handoffs.clear()
 ai_busy.clear();question_channels.clear();voice_invitations.clear();voice_room_contexts.clear();voice_channel_rooms.clear();questions.clear();ai_stage.clear()
 if is_instance_valid(speech_player):speech_player.clear_session()
 if is_instance_valid(speech_synth):speech_synth.clear_session()
 speech_serial.clear()
 speech_turn_timings.clear()
 received_voice.clear()
 pending_voice.clear()
 speech_routes.clear()
 if is_instance_valid(natural_voice):natural_voice.clear_session()
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
 if DossierStore.dirty:DossierStore.save()
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
 if not multiplayer.is_server() or not _sync_character_profile():return {"ok":false,"error":"Only the active host can create an instructor."}
 if not game.host_openai.enabled or not game.host_openai.configured():return {"ok":false,"error":"Enable the host OpenAI connection first."}
 return character_generation.request_teacher(course,style)
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
  lab_handoffs[room]={"outgoing":outgoing,"incoming":id,"due":Time.get_ticks_msec()+4400,"started":Time.get_ticks_msec(),"waiting":true,"handoff":""}
  remaining[room]=ROTATE_SECONDS
  _begin_staff_handoff(room,lab_handoffs[room],visit.duplicate(true))
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
  if exchange.get("waiting",false) and now<int(exchange.get("started",now))+35000:continue
  if now<int(exchange.due) or lesson_question_active(room):continue
  lab_handoffs.erase(room)
  _switch_lab_instructor(room,incoming)
  _sync_lab_teachers()
  _answer_staff_handoff(room,exchange)

func _begin_staff_handoff(room: String,exchange: Dictionary,activity: Dictionary) -> void:
 var outgoing:=str(exchange.outgoing)
 var incoming:=str(exchange.incoming)
 var started:=int(exchange.started)
 var result:=await generate_character_exchange(Characters.teacher(outgoing),incoming,activity,"",{"initiate":true,"defer_record":true,"intention":"Your office-hours shift is ending. Address the incoming colleague and hand over in your own manner. Do not promise effort or warmth that is unlike you.","interlocutor":{"name":Roster.entry(incoming).name,"role":"teacher"},"_valid":func():return lab_handoffs.get(room,{}).get("incoming","")==incoming and int(lab_handoffs.get(room,{}).get("started",-1))==started})
 if not lab_handoffs.has(room) or lab_handoffs[room].get("incoming","")!=incoming or int(lab_handoffs[room].get("started",-1))!=started:return
 exchange.waiting=false
 if result.is_empty() or result.get("cancelled",false):return
 exchange.handoff=str(result.line)
 exchange.due=Time.get_ticks_msec()+clampi(str(result.line).length()*40,4400,12000)
 if not str(result.line).is_empty():_staff_line(room,outgoing,str(result.line))
 character_interaction.record(result,not str(result.line).is_empty())

func _answer_staff_handoff(room: String,exchange: Dictionary) -> void:
 var incoming:=str(exchange.incoming)
 var outgoing:=str(exchange.outgoing)
 var person:=Characters.teacher(incoming)
 var activity:=_lab_visit(room)
 # A timed-out or deliberately silent opening was never heard. The incoming
 # colleague can observe the shift change without remembering an invented quote.
 var opening:=str(exchange.get("handoff",""))
 var intention:="Your colleague handed over the office-hours shift. Reply as yourself; do not imply enthusiasm or unlimited help if it is unlike you."
 if opening.is_empty():intention="Your office-hours shift has started. Your colleague has said nothing to you. If you speak, initiate naturally in your own manner without inventing a prior exchange."
 var result:=await generate_character_exchange(person,outgoing,activity,opening,{"initiate":opening.is_empty(),"defer_record":true,"intention":intention,"observed_event":{"kind":"staff_shift_started","room":room},"interlocutor":{"name":Roster.entry(outgoing).name,"role":"teacher"}})
 if result.is_empty() or result.get("cancelled",false):return
 if str(result.line).is_empty():
  character_interaction.record(result,false)
  return
 _staff_line(room,incoming,str(result.line))
 character_interaction.record(result,true)
 # The outgoing colleague hears the actual reply to their handoff. No third
 # utterance is generated and no second copy of either speaker's event is made.
 await generate_character_exchange(Characters.teacher(outgoing),incoming,{},str(result.line),{"listen_only":true,"observed_event":{"kind":"staff_handoff_reply","room":room}})

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
  "week":school.activity.get("week",0),"title":school.project.get("title",course),
  "deadline":game.lecture_classes._now()+maxf(0.,float(school.remaining)),"teaching_seconds":float(school.activity.get("teaching_seconds",school.teaching_seconds))}
func _sync_lab_teachers() -> void:
 for room in ["ac_lab","dc_lab"]:
  var activity:=_lab_visit(room)
  _sync_voice_room_context(room,activity)
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
 var traits: Dictionary=Characters.teacher(id).traits
 model.set_meta("classroom_walk_speed",lerpf(.53,1.10,float(traits.energy)))
 model.set_meta("classroom_eye_contact",lerpf(2.2,8.,float(traits.confidence)))
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
 voice_transfer.prune()
 for token in pending_voice.keys():
  var waiting: Dictionary=pending_voice[token]
  if Time.get_ticks_msec()-int(waiting.get("at",0))>125000:
   var channel:=str(token).rsplit("|",true,1)[0]
   _voice_fallback(channel,int(waiting.serial))
 _sync_lab_teachers()
 _step_lab_routes(delta)
 if multiplayer.is_server():
  _next_question()
  character_generation_clock+=delta
  if character_generation_clock>=1.0:
   character_generation_clock=0.0
   if game.front.in_game and _sync_character_profile():
    var preferred: Array=current.values()
    for class_state in game.lecture_classes.classes.values():preferred.append(str(class_state.get("teacher","")))
    character_generation.tick(preferred)
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
  var now:=Time.get_ticks_msec()
  var active:=now<int(pose.get("until",0))
  var person_id:=str(pose.get("person_id",model.get_meta("faculty_id","")))
  var person:=Characters.teacher(person_id) if Roster.has(person_id) else Classmates.profile_for(person_id)
  var emotion:=str(pose.get("mood","steady"))
  var affect: Dictionary=pose.get("affect",{})
  if multiplayer.is_server() and not person.is_empty():
   var state:=character_mind.context(person,Time.get_ticks_msec())
   emotion=str(state.emotion);affect=state.emotions
  elif not person.is_empty() and not affect.is_empty():
   CharacterAffect.recover(affect,person.traits,delta)
   emotion=CharacterAffect.dominant(affect,person.traits)
   pose.mood=emotion
  elif now>=int(pose.get("mood_until",0)):emotion="steady"
  var speaking: Dictionary=speech_player.presentations.get(room,{}) if is_instance_valid(speech_player) else {}
  if int(speaking.get("serial",-1))==int(pose.get("speech_serial",-2)) and now<int(speaking.get("until",0)):
   # Natural gesture bursts continue with this utterance instead of cutting
   # every long response off after one fixed three-second animation.
   var elapsed:=float(now-int(pose.get("started",now)))*.001
   active=active or fmod(elapsed,4.5)<1.3+float(person.get("traits",{}).get("expressiveness",.5))*1.4
  CharacterMotion.express(model,emotion,delta,str(pose.get("gesture","")) if active else "",float(Time.get_ticks_msec()-int(pose.get("started",Time.get_ticks_msec())))*.001,pose.get("point",Vector3.INF),affect,person.get("traits",{}))
  # Gestures finish, but expression/posture continue reflecting actual mood.
  if not active and emotion=="steady" and Time.get_ticks_msec()>=int(pose.get("mood_until",0)):_clear_reaction_pose(room)
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
func _sync_voice_room_context(room: String,activity: Dictionary) -> void:
 var context:={"class_id":str(activity.get("id","")),"teacher":str(activity.get("teacher","")),"phase":str(activity.get("phase",""))}
 var previous: Dictionary=voice_room_contexts.get(room,{})
 if previous==context:return
 if not previous.is_empty():_cancel_room_speech(room)
 voice_room_contexts[room]=context

func _cancel_room_speech(room: String) -> void:
 var channels: Array[String]=[room]
 for channel in voice_channel_rooms:
  if str(voice_channel_rooms[channel])==room and channel not in channels:channels.append(str(channel))
 for channel in channels:
  if is_instance_valid(speech_player):speech_player.cancel(channel)
  if is_instance_valid(speech_synth):speech_synth.cancel(channel)
  for token in pending_voice.keys():
   if str(token).begins_with(channel+"|"):pending_voice.erase(token)
  for token in speech_routes.keys():
   if str(token).begins_with(channel+"|"):speech_routes.erase(token)
  _clear_reaction_pose(channel)

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
  var live_context: Dictionary=_lab_visit(room) if room in ["ac_lab","dc_lab"] else game.lecture_classes.classes.get(room,active[room]) if multiplayer.is_server() else active[room]
  _sync_voice_room_context(room,live_context)
  var phase: String=str(live_context.get("phase",""))
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
  if not active.has(room):
   _sync_voice_room_context(str(room),_lab_visit(str(room)) if room in ["ac_lab","dc_lab"] else {})
   _clear_reaction_pose(room);class_overlap.erase(room);classroom_phase.erase(room)

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
 for value in game.lecture_classes.classes.values():
  if not str(value.get("id","")).is_empty():active_ids.append(str(value.id))
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
   cue = {"key":"arrival", "text":""}
  elif phase == "lesson":
   if lesson_question_active(room):continue
   if activity.get("ai_teaching",false) and current_event.is_empty():
    _maybe_ai_lesson(room)
    var board: Dictionary=game.lecture_classes._stage(activity)
    var lesson_time: float=game.lecture_classes.lesson_duration(activity)-maxf(0.,float(activity.deadline)-now)
    if activity.get("ai_waiting",false) or lesson_time-float(board.get("start_seconds",0.))<9.:continue
   if not current_event.is_empty():
    if now >= float(current_event.get("open_at",0)): continue
    cue = {"key":"practice:"+str(current_event.round.event_id), "text":CharacterBehavior.classroom_line(Characters.teacher(teacher),"practice")}
   else:
    cue = _character_lecture_cue(activity,game.lecture_classes._stage(activity),now,teacher)
  if cue.is_empty(): continue
  var key := str(activity.id)+":"+str(cue.key)
  if lecture_cues.get(room,"") == key: continue
  var point := _teacher_position(room)
  if not point.is_finite(): continue
  lecture_cues[room] = key
  var teacher_profile:=Characters.teacher(teacher)
  var pose:=""
  var gesture_point:=Vector3.INF
  if phase=="arrival" and float(teacher_profile.traits.warmth)>.77 and float(teacher_profile.traits.energy)>.55:
   pose="wave"
  elif phase=="lesson" and cue.has("anchor") and float(teacher_profile.traits.demonstrations)>.87 and lecture_models.has(room):
   pose="point"
   gesture_point=game.lecture_classes.signs[room].board.global_position
  var intention:="You have entered the classroom. Greet the students as yourself and remind them to sign attendance for "+str(activity.course)+" and take a seat." if phase=="arrival" else "Address the next classroom objective as this person. Explain the supplied course point accurately or introduce the upcoming independent practice. Your interests, teaching motivation and mood determine the manner."
  var objective: Dictionary=game.lecture_classes._stage(activity) if phase=="lesson" else {"required_information":["Sign attendance for "+str(activity.course),"Take a seat"]}
  _announce_character(room,teacher,activity,"classroom:"+str(activity.get("course","")),intention,"",2,{"teaching_step":objective,"official_communication":true,"_presentation_pose":pose,"_presentation_point":gesture_point,"_valid":func():return str(lecture_cues.get(room,""))==key})
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
 var cue_activity:=activity.duplicate(true)
 if activity.has("teaching_seconds"):
  cue_activity.teaching={"duration_seconds":float(activity.teaching_seconds)}
 var cue:=LectureDirector.cue(cue_activity,board,now,preferences)
 if float(person.traits.teaching_effort)<.35:cue.erase("anchor")
 return cue

func formal_lesson_ready() -> bool:
 var school: Node=game.school
 var state: Dictionary=school.activity
 if school.phase!="lesson" or not state.get("ai_teaching",false):return true
 var room:=str(state.get("room",{}).get("id",""))
 var now:=Time.get_ticks_msec()
 var previous:=int(state.get("question_pause_sample",now))
 state.question_pause_sample=now
 if lesson_question_active(room):
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
 state.ai_wait_key=key
 var client: Node=game.host_openai
 var waiting_since: int=state.get_or_add("ai_wait_started",Time.get_ticks_msec())
 # Offline and busy-provider recovery still pass through the same personality,
 # emotion and memory path. Wait briefly for an already-running host request.
 if is_instance_valid(client) and client.ready_for_class() and client.busy and Time.get_ticks_msec()-waiting_since<=7500:return
 ai_stage[room]=key
 state.ai_status="Waiting for the instructor…"
 _generate_ai_lesson(room,activity,state,key,board,formal)

func _release_lesson_wait(room: String,state: Dictionary,key: String,retry := false) -> void:
 # A stale callback may release its own wait, never a newer stage's request.
 if str(state.get("ai_wait_key",""))!=key:return
 state.erase("ai_wait_started");state.erase("ai_wait_key")
 state.ai_waiting=false;state.ai_status=""
 if retry and str(ai_stage.get(room,""))==key:ai_stage.erase(room)

func _generate_ai_lesson(room: String,activity: Dictionary,state: Dictionary,key: String,board: Dictionary,formal: bool) -> void:
 var id:=str(activity.get("teacher",""))
 var class_id:=str(activity.get("id",""))
 var person:=Characters.teacher(id)
 var step: Dictionary=board.get("teaching_step",{})
 var focus:=str(step.get("prompt","Explain the current board in one concrete example."))
 if step.get("key","")=="check" and int(board.get("clarification_requests",0))>0:
  focus="Explain the same idea another way without introducing a new concept. Ask students to confirm when ready."
 var intention:="Teach the current point in your own teaching style. Official content must come from the supplied board; do not invent measurements, grade changes, or a different curriculum. "+focus
 if float(person.traits.teaching_effort)<.3:intention+=" Give the essential point accurately, then let the class work independently."
 elif float(person.traits.demonstrations)>.85:intention+=" Ask for a concrete prediction if this step supports it."
 var result:=await generate_character_exchange(person,"classroom:"+str(activity.get("course","")),activity,"",{"initiate":true,"official_communication":true,"defer_record":true,"intention":intention,"teaching_step":board,"_valid":func():return str(ai_stage.get(room,""))==key})
 var latest:=_ai_activity(room)
 if str(latest.get("id",""))!=class_id or latest.get("phase","")!="lesson" or str(ai_stage.get(room,""))!=key:
  _release_lesson_wait(room,state,key,true)
  return
 if result.is_empty() or result.get("cancelled",false):
  _release_lesson_wait(room,state,key,true)
  return
 if result.get("silent",false):
  _release_lesson_wait(room,state,key)
  character_interaction.record(result,false)
  return
 if result.get("source","")=="technical_unavailable":
  _release_lesson_wait(room,state,key)
  state.ai_status=str(result.get("technical_status","AI teaching is unavailable; the course material remains on the board."))
  character_interaction.record(result,false)
  return
 _finish_lesson_cue(room,activity,state,key,board,formal,str(result.line))
 character_interaction.record(result,true)

func _finish_lesson_cue(room: String,activity: Dictionary,state: Dictionary,key: String,board: Dictionary,formal: bool,text_value: String) -> void:
 var id:=str(activity.get("teacher",""))
 if text_value.is_empty():
  _release_lesson_wait(room,state,key)
  return
 _release_lesson_wait(room,state,key)
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
  if float(profile.traits.demonstrations)>=.65 and float(profile.traits.teaching_effort)>=.45:
   if not game.host_openai.busy and questions.is_empty():
    state.visual_attempted=true
    _suggest_visual(room,str(activity.id),id,board)

func _suggest_visual(room: String,class_id: String,id: String,board: Dictionary) -> void:
 var activity:=_ai_activity(room)
 if str(activity.get("id",""))!=class_id or activity.get("phase","")!="lesson":return
 var person:=Characters.teacher(id)
 var result:=await generate_character_exchange(person,"classroom:"+str(activity.get("course","")),activity,"",{"initiate":true,"intention":"Create a short illustration only if it clarifies the current board. Preserve the supplied educational facts.","teaching_step":board,"classroom":TeacherAI.context(activity,id,board),"current_display":Visuals.description(activity),"wants_visual":true,"defer_record":true,"_valid":func():return int(game.lecture_classes._stage(activity).get("index",-1))==int(board.get("index",-1))})
 if result.is_empty() or result.get("cancelled",false):return
 var plan: Dictionary=result.get("plan",{})
 var live: Dictionary=game.lecture_classes.classes.get(room,{})
 var applied: bool=not live.is_empty() and not live.has("visual_playback") and live.get("id","")==class_id and live.get("phase","")=="lesson" and plan.get("action")!=null and Visuals.apply(live,plan.action,game.lecture_classes._now())
 result.prepared.extra.executed_action={"action":"visual_plan","succeeded":applied}
 character_interaction.record(result,applied)
 if applied:
  game.lecture_classes._publish()
  present_class_reaction(room,id,str(result.line),2)

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
  var next:=model.global_position+offset.normalized()*minf(offset.length(),delta*float(model.get_meta("classroom_walk_speed",.8)))
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

var character_inspection_exchange=preload("res://scripts/campus/ui/character_inspector_transport.gd").new()

func _build_conversation_ui() -> void:
 var layer:=CanvasLayer.new();layer.layer=31;add_child(layer)
 var wrapper:=Control.new()
 wrapper.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
 wrapper.mouse_filter=Control.MOUSE_FILTER_IGNORE
 layer.add_child(wrapper)
 var inspector=preload("res://scripts/campus/ui/character_inspector.gd").new()
 conversation=inspector
 wrapper.add_child(conversation)
 conversation.set_anchors_preset(Control.PRESET_CENTER)
 conversation.grow_vertical=Control.GROW_DIRECTION_BOTH
 conversation.grow_horizontal=Control.GROW_DIRECTION_BOTH
 var fit:=func():
  var viewport_size:=get_viewport().get_visible_rect().size
  var width:=minf(1100.,maxf(540.,viewport_size.x-36.))
  var height:=minf(850.,maxf(510.,viewport_size.y-36.))
  conversation.offset_left=-width*.5
  conversation.offset_right=width*.5
  conversation.offset_top=-height*.5
  conversation.offset_bottom=height*.5
 wrapper.resized.connect(fit)
 fit.call()
 inspector.configure(_character_inspection_snapshot)
 inspector.close_requested.connect(close_conversation)
 inspector.send_requested.connect(_submit_question)
 inspector.record_requested.connect(_toggle_recording)
 inspector.action_requested.connect(_conversation_choice)
 conversation_name=inspector.heading
 conversation_input=inspector.input
 conversation_text=inspector.dialogue
 conversation_scroll=inspector.conversation_scroll
 ask_button=inspector.send_button
 record_button=inspector.microphone_button
 conversation_actions=inspector.action_buttons
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
func _unhandled_input(event: InputEvent) -> void:
 if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode==KEY_F8 and multiplayer.is_server():
  _toggle_character_debug();get_viewport().set_input_as_handled();return
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
 _cancel_recording()
 conversation_room=room
 conversation_student=student
 conversation_class=class_id if not student.is_empty() else str(activity.get("id",""))
 conversation.set_meta("selected_character_id",id if student.is_empty() else student)
 conversation.set_meta("inspection_nonce",Crypto.new().generate_random_bytes(12).hex_encode())
 conversation.set_meta("inspection_serial",0)
 conversation.set_meta("inspection_revision","")
 conversation.set_meta("inspection_snapshot",{})
 conversation.set_meta("inspection_sent",-10000)
 conversation.set_meta("inspection_received",0)
 conversation.set_meta("inspection_waiting",false)
 conversation_name.text=str(Roster.entry(id).name) if student.is_empty() else str(member.name)
 conversation_input.text=""
 record_button.visible=bool(game.host_openai.enabled) if multiplayer.is_server() else game.session.online
 conversation_actions.inspect_circuit.visible=student.is_empty() and room in ["ac_lab","dc_lab"]
 conversation_actions.evaluate_led.visible=student.is_empty() and room=="dc_lab"
 for intent in ["hand_phone","reclaim_phone"]:
  conversation_actions[intent].visible=student.is_empty() and room in ["ac_lab","dc_lab"]
 for intent in ["ready","clarify"]:
  conversation_actions[intent].visible=student.is_empty() and activity.get("ai_teaching",false) and activity.get("phase","")=="lesson"
 conversation_text.text="Type a message or use the microphone to begin a conversation."
 _stop_voice_conversation()
 conversation.call("open_character");speech_player.subtitle_layer.hide();game.release_mouse()
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
 open_conversation(room,student,class_id)
 return true

func _character_inspection_snapshot() -> Dictionary:
 var reader=preload("res://scripts/campus/ui/character_inspector_snapshot.gd")
 if multiplayer.is_server():return reader.capture(self)
 if not is_instance_valid(conversation) or conversation_room.is_empty():return {}
 var now:=Time.get_ticks_msec()
 var elapsed:=now-int(conversation.get_meta("inspection_sent",-10000))
 if game.session.online and elapsed>=2000 and (not conversation.get_meta("inspection_waiting",false) or elapsed>=5000):
  var serial:=int(conversation.get_meta("inspection_serial",0))+1
  conversation.set_meta("inspection_serial",serial)
  conversation.set_meta("inspection_sent",now)
  conversation.set_meta("inspection_waiting",true)
  _request_character_inspection.rpc_id(1,conversation_room,conversation_student,conversation_class,str(conversation.get_meta("selected_character_id","")),str(conversation.get_meta("inspection_nonce","")),serial,str(conversation.get_meta("inspection_revision","")))
 var received:=int(conversation.get_meta("inspection_received",0))
 if received>0 and now-received<=8000:return conversation.get_meta("inspection_snapshot",{}).duplicate(true)
 return reader.capture(self)

@rpc("any_peer","call_remote","reliable")
func _request_character_inspection(room: String,student: String,class_id: String,selected: String,nonce: String,serial: int,known_revision: String) -> void:
 if not multiplayer.is_server() or not is_instance_valid(game):return
 if room not in ["ac_lab","dc_lab"]+LECTURE_ROOMS or student.length()>64 or class_id.length()>160 or selected.length()>96 or known_revision.length()>64:return
 var peer:=multiplayer.get_remote_sender_id()
 if not character_inspection_exchange.allow_request(peer,Time.get_ticks_msec(),game.session.roster,serial,nonce):return
 var snapshot:=preload("res://scripts/campus/ui/character_inspector_snapshot.gd").for_peer(self,peer,room,student,class_id,selected)
 var packet:=preload("res://scripts/campus/ui/character_inspector_transport.gd").public_packet(snapshot,known_revision,nonce,serial)
 if game.session.online and game.session.peer_connected_now(peer):_receive_character_inspection.rpc_id(peer,packet)

@rpc("authority","call_remote","reliable")
func _receive_character_inspection(packet: Dictionary) -> void:
 if multiplayer.is_server() or multiplayer.get_remote_sender_id()!=1:return
 if not is_instance_valid(conversation) or not conversation.visible or conversation_room.is_empty():return
 var accepted:=preload("res://scripts/campus/ui/character_inspector_transport.gd").accept_packet(packet,str(conversation.get_meta("inspection_nonce","")),int(conversation.get_meta("inspection_serial",0)),str(conversation.get_meta("selected_character_id","")),conversation.get_meta("inspection_snapshot",{}),str(conversation.get_meta("inspection_revision","")))
 if accepted.is_empty():return
 conversation.set_meta("inspection_snapshot",accepted.snapshot)
 conversation.set_meta("inspection_revision",accepted.revision)
 conversation.set_meta("inspection_received",Time.get_ticks_msec())
 conversation.set_meta("inspection_waiting",false)
 conversation.call("apply_snapshot",accepted.snapshot)

func invite_question(room: String,id: String,peer: int,class_id: String) -> void:
 if not multiplayer.is_server() or not game.lecture_classes._inside(peer,room):return
 voice_invitations[peer]={"room":room,"class_id":class_id,"until":Time.get_ticks_msec()+45000}
 var target: Vector3=game.lecture_classes._position(peer)
 _publish_attention(room,id,target)
 var activity:=_ai_activity(room)
 var identity:=str(game.school.identities.get(peer,""))
 if str(activity.get("id",""))!=class_id or str(activity.get("teacher",""))!=id or identity.is_empty():return
 _announce_character(room,id,activity,identity,"You have noticed this student raising their hand. Invite their question in your own manner.","",3,{"official_communication":true})
 if peer==multiplayer.get_unique_id():_question_invited(room,class_id)
 elif game.session.online and game.session.peer_connected_now(peer):_question_invited.rpc_id(peer,room,class_id)

@rpc("authority","call_remote","reliable")
func _question_invited(room: String,class_id: String) -> void:
 if str(_ai_activity(room).get("id",""))!=class_id:return
 voice_invitations[multiplayer.get_unique_id()]={"room":room,"class_id":class_id,"until":Time.get_ticks_msec()+45000}
 if not _start_voice_conversation(room,true):open_conversation(room)

func _start_voice_conversation(room: String,invited: bool,student := "",class_id := "") -> bool:
 if not is_instance_valid(natural_voice) or recording or not game.client_preferences.values.teacher_automatic_conversation:return false
 for target in voice_candidates(multiplayer.get_unique_id()):
  if target.room==room and str(target.get("student",""))==student and (student.is_empty() or target.class_id==class_id):
   target.invited=invited
   voice_invited=invited
   return natural_voice.force_target(target)
 return false

func _stop_voice_conversation() -> void:
 if is_instance_valid(natural_voice):natural_voice.cancel_current()
 voice_room="";voice_class="";voice_student=""
 if is_instance_valid(voice_hint):voice_hint.hide()

func _voice_conversation_step() -> void:
 # Shared capture and NaturalVoice own lifecycle; no duplicate microphone player.
 pass

func _consume_voice_capture() -> void:
 # Compatibility for test harnesses: only the shared service may consume the device.
 if is_instance_valid(shared_microphone):shared_microphone._process(0.0)

func _selected_conversation_current() -> bool:
 if conversation_room.is_empty() or not is_instance_valid(conversation) or not conversation.visible:return false
 var selected:=str(conversation.get_meta("selected_character_id",""))
 var activity:=_ai_activity(conversation_room)
 if conversation_student.is_empty():return not selected.is_empty() and Roster.has(selected) and str(activity.get("teacher",""))==selected and str(activity.get("id",""))==conversation_class
 if selected!=conversation_student or str(activity.get("id",""))!=conversation_class:return false
 return not game.lecture_classes.classroom_students.visible_member(conversation_room,conversation_class,conversation_student).is_empty()

func _require_selected_conversation() -> bool:
 if _selected_conversation_current():return true
 _cancel_recording()
 if is_instance_valid(conversation):
  conversation.call("apply_snapshot",{})
  conversation_text.text="This character is no longer available here. Close the panel and select them again."
 return false

func _conversation_choice(intent: String) -> void:
 if conversation_room.is_empty():return
 if intent=="bye":close_conversation();return
 if not _require_selected_conversation():return
 if intent=="chat":conversation_input.grab_focus();return
 var selected:=str(conversation.get_meta("selected_character_id",""))
 if intent in ["ready","clarify"]:
  if multiplayer.is_server():_lesson_feedback(multiplayer.get_unique_id(),conversation_room,intent,selected,conversation_class)
  elif game.session.online:_send_lesson_feedback.rpc_id(1,conversation_room,intent,selected,conversation_class)
  return
 if intent=="help":
  conversation_input.text="Can you help me with the current topic?"
  _submit_question()
  return
 var phone_id: String=game.smartphones.selected() if intent=="hand_phone" else ""
 if multiplayer.is_server():_dialogue_request(multiplayer.get_unique_id(),conversation_room,intent,phone_id,selected,conversation_class)
 elif game.session.online:_ask.rpc_id(1,conversation_room,intent,phone_id,selected,conversation_class)
@rpc("any_peer","call_remote","reliable")
func _send_lesson_feedback(room: String,signal_name: String,expected_teacher: String,expected_class: String) -> void:
 if multiplayer.is_server() and _valid_selected_target(expected_teacher,expected_class):_lesson_feedback(multiplayer.get_remote_sender_id(),room,signal_name,expected_teacher,expected_class)
func _lesson_feedback(peer: int,room: String,signal_name: String,expected_teacher: String="",expected_class: String="") -> void:
 if signal_name not in ["ready","clarify"] or not game.session.roster.has(peer):return
 var activity:=_ai_activity(room)
 if not _matches_selected_target(activity,expected_teacher,expected_class):return
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
 var result:=await generate_character_exchange(Characters.teacher(teacher),token,activity,"I'm still confused by that step." if signal_name=="clarify" else "I'm ready for the next step.",{"teaching_step":board,"executed_action":{"action":"lesson_feedback","signal":signal_name,"received":true},"intention":"Acknowledge this verified feedback in your own voice. The lesson progression remains host controlled.","_valid":func():return str(game.school.identities.get(peer,""))==token})
 if result.is_empty() or result.get("cancelled",false):return
 response=str(result.line)
 if peer==multiplayer.get_unique_id():_dialogue_reply(room,teacher,response)
 elif game.session.online and game.session.peer_connected_now(peer):_dialogue_reply.rpc_id(peer,room,teacher,response)
func _submit_question() -> void:
 var question:=conversation_input.text.strip_edges()
 if conversation_room.is_empty() or question.is_empty():return
 if not _require_selected_conversation():return
 conversation_input.clear()
 conversation_text.text="You: "+question+"\n\nWaiting for a reply…"
 conversation_scroll.set_deferred("scroll_vertical", 100000)
 if not conversation_student.is_empty():
  _send_classmate_question(conversation_room,conversation_class,conversation_student,question)
  return
 var selected:=str(conversation.get_meta("selected_character_id",""))
 if multiplayer.is_server():_question_request(multiplayer.get_unique_id(),conversation_room,question,selected,conversation_class)
 elif game.session.online:_ask_question.rpc_id(1,conversation_room,question,selected,conversation_class)
func _toggle_recording() -> void:
 if recording:_finish_recording();return
 if conversation_room.is_empty() or not is_instance_valid(shared_microphone):return
 if not _require_selected_conversation():return
 if game.client_preferences.values.get("microphone_muted",false) or game.client_preferences.values.get("microphone_mode","")=="muted":conversation_text.text="Unmute your microphone in Audio settings first.";return
 if is_instance_valid(game.get("smartphones")) and game.smartphones.comm.local_call.get("state","")=="active":conversation_text.text="End your private phone call before recording an NPC question.";return
 shared_microphone.configure(game.client_preferences.values)
 record_samples.clear();recording=true;record_started=Time.get_ticks_msec()
 shared_microphone.subscribe("manual_teacher_question",true)
 if not shared_microphone.is_active():
  var reason:=str(shared_microphone.diagnostic.get("reason","Microphone capture could not start."))
  _cancel_recording();conversation_text.text=reason;return
 record_button.text="Stop and send recording"
 conversation_text.text="Recording this question. Stopping sends it to the host's AI service."

func _manual_capture_packet(pcm: PackedByteArray,_activity: Dictionary) -> void:
 if not recording:return
 if game.client_preferences.values.get("microphone_muted",false):_cancel_recording();return
 if record_samples.size()+pcm.size()>5760000:_finish_recording.call_deferred();return
 record_samples.append_array(pcm)

func _record_step() -> void:
 if recording and (not conversation.visible or game.client_preferences.values.get("microphone_muted",false)):_cancel_recording()
 if recording and (not is_instance_valid(shared_microphone) or not shared_microphone.is_active()):
  var reason: String=str(shared_microphone.diagnostic.get("reason","Microphone capture stopped. Check the selected input device.")) if is_instance_valid(shared_microphone) else "Microphone capture is unavailable."
  _cancel_recording();conversation_text.text=reason
 if recording and is_instance_valid(game.get("smartphones")) and game.smartphones.comm.local_call.get("state","")=="active":
  _cancel_recording();conversation_text.text="NPC recording stopped for your private phone call."
 if recording and is_instance_valid(shared_microphone) and Time.get_ticks_msec()-record_started>2000 and int(shared_microphone.diagnostic.get("frames_received",0))==0:
  conversation_text.text=str(shared_microphone.diagnostic.get("reason","No microphone frames received. Check the selected device and microphone permission."))

func _cancel_recording() -> void:
 recording=false;record_samples.clear()
 if is_instance_valid(shared_microphone):shared_microphone.subscribe("manual_teacher_question",false)
 record_player=null
 if is_instance_valid(record_button):record_button.text="Mic"
func _finish_recording() -> void:
 if not recording:return
 shared_microphone.drain_pending()
 var samples:=record_samples.duplicate()
 var capture_status: Dictionary=shared_microphone.diagnostic.duplicate()
 _cancel_recording()
 if not _require_selected_conversation():return
 if samples.size()<4800:
  conversation_text.text=str(capture_status.get("reason","Microphone capture did not receive audio.")) if int(capture_status.get("frames_received",0))==0 else "The recording was too short. Record at least a short sentence before sending."
  return
 conversation_text.text="Listening to your question…"
 _send_voice_question(conversation_room,TeacherAI.wav_16k(samples),conversation_student,conversation_class,str(conversation.get_meta("selected_character_id","")))

func _send_voice_question(room: String,wav: PackedByteArray,student: String,class_id: String,expected_teacher: String="") -> void:
 if not student.is_empty():_send_classmate_question(room,class_id,student,wav)
 elif multiplayer.is_server():_speech_question_request(multiplayer.get_unique_id(),room,wav,expected_teacher,class_id)
 elif game.session.online and _valid_selected_target(expected_teacher,class_id):_ask_speech.rpc_id(1,room,wav,expected_teacher,class_id)
@rpc("any_peer","call_remote","reliable")
func _ask_speech(room: String,wav: PackedByteArray,expected_teacher: String,expected_class: String) -> void:
 if multiplayer.is_server() and _valid_selected_target(expected_teacher,expected_class):_speech_question_request(multiplayer.get_remote_sender_id(),room,wav,expected_teacher,expected_class)
func _ai_activity(room: String) -> Dictionary:
 if room in ["ac_lab","dc_lab"]:return _lab_visit(room)
 if room not in LECTURE_ROOMS:return {}
 var activities: Dictionary=game.lecture_classes.classes if multiplayer.is_server() else game.lecture_classes.public_classes
 return activities.get(room,_formal_activity(room))
func _speech_question_request(peer: int,room: String,wav: PackedByteArray,expected_teacher: String="",expected_class: String="") -> void:
 if wav.size()<4844 or wav.size()>5760044:return
 _queue_question(peer,room,wav,expected_teacher,expected_class)

func _transcribe_question(peer: int,room: String,id: String,class_id: String,wav: PackedByteArray,pos: Vector3,voice_context: Dictionary={},timing: Dictionary={}) -> void:
 var epoch:=character_epoch
 timing=timing.duplicate(true)
 timing.transcription_started_ms=Time.get_ticks_msec()
 var result: Dictionary=await game.host_openai.transcribe_wav(wav)
 timing.transcription_finished_ms=Time.get_ticks_msec()
 timing.transcription_ms=int(timing.transcription_finished_ms)-int(timing.transcription_started_ms)
 if epoch!=character_epoch or str(_ai_activity(room).get("id",""))!=class_id or str(_ai_activity(room).get("teacher",""))!=id or not _voice_context_valid(peer,voice_context):
  if _release_question(peer,epoch):resume_voice_channel(room,room)
  return
 if not result.get("ok",false):
  _release_question(peer,epoch)
  _report_voice_stage(peer,voice_context,"transcription_failed",str(result.get("error","Speech was not recognized.")))
  _question_status(peer,room,id,str(result.get("error","Speech was not recognized.")))
  resume_voice_channel(room,room)
  return
 _report_voice_stage(peer,voice_context,"transcription_received")
 var text:=str(result.get("text",""))
 if not voice_context.is_empty() and preload("res://scripts/campus/voice/conversation_targeting.gd").acknowledgement(text):
  _report_voice_stage(peer,voice_context,"intentional_silence")
  if _release_question(peer,epoch):resume_voice_channel(room,room)
  return
 await _answer_question(peer,room,id,class_id,text,pos,voice_context,timing)

@rpc("any_peer","call_remote","reliable")
func _ask_question(room: String,question: String,expected_teacher: String,expected_class: String) -> void:
 if multiplayer.is_server() and _valid_selected_target(expected_teacher,expected_class):_question_request(multiplayer.get_remote_sender_id(),room,question,expected_teacher,expected_class)

func _question_request(peer: int,room: String,question: String,expected_teacher: String="",expected_class: String="") -> void:
 if question.is_empty() or question.length()>8000:return
 _queue_question(peer,room,question,expected_teacher,expected_class)

static func _valid_selected_target(teacher: String,class_id: String) -> bool:
 return not teacher.is_empty() and teacher.length()<=64 and not class_id.is_empty() and class_id.length()<=160

static func _matches_selected_target(activity: Dictionary,teacher: String,class_id: String) -> bool:
 # Empty targets are reserved for trusted internal current-target calls. RPC
 # entry points require an explicit teacher and class before reaching here.
 if teacher.is_empty():return class_id.is_empty()
 return _valid_selected_target(teacher,class_id) and str(activity.get("teacher",""))==teacher and str(activity.get("id",""))==class_id

func _send_classmate_question(room: String,class_id: String,student: String,content: Variant) -> void:
 if multiplayer.is_server():_classmate_question(multiplayer.get_unique_id(),room,class_id,student,content)
 elif game.session.online:_ask_classmate.rpc_id(1,room,class_id,student,content)

@rpc("any_peer","call_remote","reliable")
func _ask_classmate(room: String,class_id: String,student: String,content: Variant) -> void:
 if multiplayer.is_server():_classmate_question(multiplayer.get_remote_sender_id(),room,class_id,student,content)

func _classmate_question(peer: int,room: String,class_id: String,student: String,content: Variant,voice_context: Dictionary={}) -> void:
 var received_ms:=Time.get_ticks_msec()
 if content is String:
  if content.strip_edges().is_empty() or content.length()>8000:return
 elif content is PackedByteArray:
  if content.size()<4844 or content.size()>5760044:return
 else:return
 if not _voice_context_valid(peer,voice_context):return
 if game.lecture_classes.classroom_students.nearby_member(peer,room,class_id,student,7.0 if not voice_context.is_empty() else 3.8).is_empty():return
 if questions.size()>=32 or questions.filter(func(entry):return entry.peer==peer).size()>=4:
  _notify_classmate(peer,room,class_id,student,"The conversation queue is full.",false)
  return
 questions.append({"peer":peer,"room":room,"class":class_id,"student":student,"content":content,"voice_context":voice_context,"_timing":{"host_received_ms":received_ms,"input_kind":"microphone" if content is PackedByteArray else "typed"}})
 if game.host_openai.busy or not ai_busy.is_empty() or questions.size()>1:
  _notify_classmate(peer,room,class_id,student,"Message queued.",false)
 _next_question()

func generate_character_exchange(person: Dictionary,identity: String,activity: Dictionary,question: String,extra_context: Dictionary={}) -> Dictionary:
 if not multiplayer.is_server() or person.is_empty() or identity.is_empty() or not _sync_character_profile():return {}
 character_jobs+=1
 var epoch:=character_epoch
 var extra:=extra_context.duplicate(true)
 var captured_activity:=activity.duplicate(true)
 var extra_guard: Variant=extra.get("_valid")
 extra._valid=func():return _character_context_current(epoch,captured_activity) and (not extra_guard is Callable or (extra_guard.is_valid() and bool(extra_guard.call())))
 var prepared:=await character_interaction.prepare(game.host_openai,person,identity,activity,question,extra)
 if extra.get("record_incoming",false) and not prepared.get("cancelled",false) and _character_context_current(epoch,prepared.activity):
  # The incoming words were actually heard. Persist that perception once;
  # complete this event only if its reply is later delivered.
  brain.remember_event(prepared.person,identity,prepared.turn,str(prepared.question),"",int(Time.get_unix_time_from_system()),str(prepared.event_id))
  prepared.extra.existing_event_id=prepared.event_id
 var result:=await character_interaction.generate(game.host_openai,prepared)
 var valid: bool=_character_context_current(epoch,prepared.activity) and not result.get("cancelled",false)
 if not extra.get("defer_record",false):character_interaction.record(result,valid)
 character_jobs=maxi(0,character_jobs-1)
 if not valid:
  result.line=""
  result.silent=true
  result.cancelled=true
 return result

func _character_context_current(epoch: int,activity: Dictionary) -> bool:
 if epoch!=character_epoch or str(game.school.local_identity)!=brain.host_profile():return false
 var class_id:=str(activity.get("id",""))
 if class_id.is_empty():return true
 for room in ["ac_lab","dc_lab"]+LECTURE_ROOMS:
  var current_activity:=_ai_activity(room)
  if str(current_activity.get("id",""))==class_id:
   return current_activity.get("phase","")==activity.get("phase","") and str(current_activity.get("teacher",""))==str(activity.get("teacher",""))
 return false

func _announce_character(room: String,id: String,activity: Dictionary,identity: String,intention: String,_fallback: String,priority: int=2,extensions: Dictionary={}) -> void:
 var extra:=extensions.duplicate(true)
 extra.initiate=true;extra.intention=intention;extra.defer_record=true
 var result:=await generate_character_exchange(Characters.teacher(id),identity,activity,"",extra)
 if result.is_empty() or result.get("cancelled",false):return
 var point:=_teacher_position(room)
 if not point.is_finite() or str(result.get("line","")).is_empty():
  character_interaction.record(result,false)
  return
 var pose:=str(extra.get("_presentation_pose",result.turn.get("pose","")))
 if pose.is_empty():pose=str(result.turn.get("pose",""))
 if pose in CharacterMotion.POSES:_character_gesture(room,_model_for_room(room,id),str(result.emotion),false,pose,extra.get("_presentation_point",Vector3.INF))
 var serial:=_next_speech(room)
 _show_reaction(room,id,str(result.line),point,serial,priority,false,str(result.emotion))
 _broadcast_reaction(room,id,str(result.line),point,serial,priority)
 character_interaction.record(result,true)

func character_debug_snapshot() -> Dictionary:
 # No global conversation dump. This checks host authority at data access and
 # returns only the selected character's history with the local host player.
 return preload("res://scripts/campus/ui/character_inspector_snapshot.gd").capture(self)

func _toggle_character_debug() -> void:
 if not preload("res://scripts/campus/ui/character_inspector_snapshot.gd").can_inspect_private(self):return
 if not is_instance_valid(conversation) or not conversation.visible:return
 conversation.call("refresh")
 conversation.call("show_diagnostics")

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

func _embodied_reply(_person: Dictionary,_question: String,_observations: Dictionary) -> String:
 # Visible facts go to character context; only the model supplies their wording.
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

func _character_action_reply(_action: String,_accepted: bool) -> String:
 # The executed-action record informs generated speech; gestures have no
 # deterministic spoken acknowledgement.
 return ""

func _character_action_status(action: String,accepted: bool) -> Dictionary:
 var walking:=action in ["approach","approach_board"]
 return {"action":action,"accepted":accepted,"pending":accepted and walking,"completed":accepted and not walking,"succeeded":accepted and not walking,
  "status":"started" if accepted and walking else ("completed" if accepted else "rejected")}

func answer_observed_lesson_question(_person: Dictionary,_stage: Dictionary,_question: String) -> String:
 # Compatibility seam: released curriculum is context, not offline persona speech.
 return ""

func classroom_character_exchange(activity: Dictionary,member: Dictionary,stage: Dictionary,question: String) -> String:
 var teacher:=Characters.teacher(str(activity.teacher))
 var student: Dictionary=member.profile
 var result:=await generate_character_exchange(teacher,student.id,activity,question,{"teaching_step":stage,"interlocutor":{"name":student.name,"role":"student"}})
 if result.is_empty() or result.get("cancelled",false):return ""
 var answer:=str(result.line)
 if not answer.is_empty():
  var relationship: Dictionary=brain.relationship_at(student.id,teacher.id,int(Time.get_unix_time_from_system()))
  var heard:=character_mind.observe(student,relationship,answer,Time.get_ticks_msec(),teacher.id,"chat",str(result.event_id)+":heard",{"phase":"lesson","meaning":"The instructor responded to this student's question."})
  brain.remember_event(student,teacher.id,heard,answer,"",int(Time.get_unix_time_from_system()),str(result.event_id)+":heard")
 return answer

func _answer_classmate(entry: Dictionary) -> void:
 var epoch:=character_epoch
 await _answer_classmate_inner(entry)
 if _release_question(int(entry.peer),epoch) and is_instance_valid(speech_player):resume_voice_channel("classmate:"+str(entry.get("student","")),str(entry.get("room","")))

func _answer_classmate_inner(entry: Dictionary) -> void:
 var peer: int=entry.peer
 var room: String=entry.room
 var class_id: String=entry.class
 var actor: String=entry.student
 var students: Node=game.lecture_classes.classroom_students
 var voice_context: Dictionary=entry.get("voice_context",{})
 var hearing_range:=7.0 if not voice_context.is_empty() else 3.8
 var member: Dictionary=students.nearby_member(peer,room,class_id,actor,hearing_range)
 if member.is_empty():return
 var identity:=str(game.school.identities.get(peer,""))
 if identity.is_empty():return
 var epoch:=character_epoch
 if not _voice_context_valid(peer,voice_context):return
 ai_busy[peer]="classmate:"+actor
 var client: Node=game.host_openai
 var timing: Dictionary=entry.get("_timing",{}).duplicate(true)
 var question: String
 if entry.content is PackedByteArray:
  timing.transcription_started_ms=Time.get_ticks_msec()
  var transcript: Dictionary=await client.transcribe_wav(entry.content)
  timing.transcription_finished_ms=Time.get_ticks_msec()
  timing.transcription_ms=int(timing.transcription_finished_ms)-int(timing.transcription_started_ms)
  if epoch!=character_epoch or not _voice_context_valid(peer,voice_context):return
  if not transcript.get("ok",false):
   _report_voice_stage(peer,voice_context,"transcription_failed",str(transcript.get("error","Speech was not recognized.")))
   _notify_classmate(peer,room,class_id,actor,str(transcript.get("error","Speech was not recognized.")),false)
   return
  _report_voice_stage(peer,voice_context,"transcription_received")
  question=str(transcript.get("text","")).strip_edges()
 else:question=entry.content
 var activity: Dictionary=game.lecture_classes.classes.get(room,{})
 if activity.get("id","")!=class_id or question.is_empty() or str(game.school.identities.get(peer,""))!=identity or students.nearby_member(peer,room,class_id,actor,hearing_range).is_empty():
  return
 var person: Dictionary=member.profile
 var model: Node3D=students.models.get(class_id+":"+actor) as Node3D
 var observations:=_character_observations(peer,model,activity)
 observations.character_posture="seated" if member.get("seated",false) else "standing"
 observations.current_activity=str(member.get("action","working"))
 var stage: Dictionary=game.lecture_classes._stage(activity) if activity.phase=="lesson" else {}
 var extra:={"observations":observations,"available_actions":CharacterInteraction.ACTIONS}
 extra._timing=timing
 var captured_activity:=activity.duplicate(true)
 extra._valid=func():return _character_context_current(epoch,captured_activity) and str(game.school.identities.get(peer,""))==identity and not students.nearby_member(peer,room,class_id,actor,hearing_range).is_empty() and _voice_context_valid(peer,voice_context)
 var prepared:=await character_interaction.prepare(client,person,identity,activity,question,extra)
 var still_present: bool=not prepared.get("cancelled",false) and bool(extra._valid.call())
 if not still_present:
  var cancelled:={"prepared":prepared,"turn":prepared.turn,"line":"","source":"cancelled","fallback_reason":"activity_changed","event_id":prepared.event_id}
  character_interaction.record(cancelled,false);return
 var action:=str(prepared.turn.interpretation.get("requested_action",""))
 if action.is_empty():action=_character_action(question)
 var raised:=false
 var willingness:=CharacterBehavior.action_willingness(person,action,prepared.turn.relationship,str(prepared.activity.get("phase","")),prepared.turn.decision,prepared.turn.get("emotions",{}))
 prepared.context.action_willingness=willingness
 var permitted: bool=(action.is_empty() or bool(willingness.accepted)) and not prepared.moderated and not prepared.turn.get("closed",false) and not prepared.turn.get("quiet",false) and prepared.turn.get("strategy","") not in ["refuse","refuse_help","return_to_work","ignore","walk_away"]
 if permitted and not action.is_empty() and epoch==character_epoch and not students.nearby_member(peer,room,class_id,actor,hearing_range).is_empty():
  var target:=_character_action_point(room,action,game.lecture_classes._position(peer))
  var accepted: bool=bool(observations.player_visible) and bool(observations.get("has_arms",false)) and (action!="point" or target.is_finite()) and students.act(room,activity,member,"approach" if action=="approach_board" else action,target,game.lecture_classes._now())
  raised=accepted and action=="raise_hand"
  prepared.context.executed_action=_character_action_status(action,accepted)
  prepared.extra.executed_action=prepared.context.executed_action
  if accepted:game.lecture_classes._publish()
 var result:=await character_interaction.generate(client,prepared)
 var valid: bool=not result.get("cancelled",false) and bool(extra._valid.call())
 if valid:_mark_character_response_ready(result)
 character_interaction.record(result,valid)
 if not valid:return
 if result.silent:
  _report_voice_stage(peer,voice_context,"intentional_silence")
  member.action="returning to work";member.erase("look_at");member.next=maxf(float(member.next),game.lecture_classes._now()+3.)
  # Silence can still include an actual gesture. The host's action gate owns
  # whether it happens; a rejected proposal produces neither speech nor prose.
  # A member has one gesture slot, so dispatch only the first accepted action.
  for gesture in result.get("nonverbal",[]):
   if gesture in CharacterMotion.POSES and students.act(room,activity,member,str(gesture),Vector3.INF,game.lecture_classes._now()):break
  game.lecture_classes._publish()
  _notify_classmate(peer,room,class_id,actor,"",false)
  return
 if result.source=="technical_unavailable":
  _report_voice_stage(peer,voice_context,"response_failed",str(result.get("technical_status","Character response unavailable.")))
  _notify_classmate(peer,room,class_id,actor,str(result.get("technical_status","Character response unavailable.")),false)
  return
 for gesture in result.get("nonverbal",[]):
  if gesture in ["nod","wave"]:students.act(room,activity,member,str(gesture),member.position,game.lecture_classes._now())
 _report_voice_stage(peer,voice_context,"response_generated")
 _notify_classmate(peer,room,class_id,actor,str(result.line),true,str(result.emotion),raised,str(result.turn.get("pose","")),result.turn.get("emotions",{}),str(result.event_id),timing,voice_context)

func _notify_classmate(peer: int,room: String,class_id: String,actor: String,line: String,speak: bool,mood := "steady",raised := false,gesture := "",affect: Dictionary={},event_id: String="",timing: Dictionary={},voice_context: Dictionary={}) -> void:
 var local:=peer==multiplayer.get_unique_id()
 if not local and (not game.session.online or not game.session.peer_connected_now(peer)):return
 var channel:="classmate:"+actor
 var serial:=_next_speech(channel) if speak else 0
 if speak:_track_character_audio(channel,serial,event_id,timing)
 var delivery:=Characters.speech(Classmates.profile_for(actor),game.host_openai.tts_model,3,mood,affect) if speak and _uses_class_voice() else {}
 var provider:=bool(delivery.get("ok",false))
 if local:_classmate_reply(room,class_id,actor,line,speak,mood,raised,serial,provider,gesture,affect)
 else:
  _classmate_reply.rpc_id(peer,room,class_id,actor,line,speak,mood,raised,serial,provider,gesture,affect)
  if speak:_classmate_reply(room,class_id,actor,line,speak,mood,raised,serial,provider,gesture,affect,true)
 if provider:
  speech_routes[_voice_key(channel,serial)]=_new_speech_route(channel,serial,room,actor,[] if local else [peer],game.lecture_classes.classroom_students.models.get(class_id+":"+actor),class_id,peer,7.2 if not voice_context.is_empty() else 4.2)
  _request_classmate_audio(peer,serial,actor,CharacterSpeech.complete(SpeechMath.display(line)),delivery)

@rpc("authority","call_remote","reliable")
func _classmate_reply(room: String,class_id: String,actor: String,line: String,speak: bool,mood := "steady",raised := false,serial := 0,provider := false,gesture := "",affect: Dictionary={},tracking_only: bool=false) -> void:
 var students: Node=game.lecture_classes.classroom_students
 var model: Node3D=students.models.get(class_id+":"+actor)
 var profile:=Classmates.profile_for(actor)
 if not is_instance_valid(model) or profile.is_empty():return
 if not tracking_only and conversation.visible and conversation_room==room and conversation_class==class_id and conversation_student==actor:
  conversation_text.text=SpeechMath.display(line);conversation_scroll.set_deferred("scroll_vertical",0)
 elif not tracking_only and voice_room==room and voice_class==class_id and voice_student==actor and not speak:
  voice_hint.text=line;voice_hint.show()
 if not speak:return
 var channel:="classmate:"+actor
 voice_channel_rooms[channel]=room
 var text:=CharacterSpeech.complete(SpeechMath.display(line))
 speech_player.configure(bool(game.client_preferences.values.teacher_speech),bool(game.client_preferences.values.teacher_subtitles))
 if not speech_player.accept(channel,str(profile.name),serial,text,3,model,null,1.0,{"expect_audio":provider,"character_id":actor,"conversation_id":class_id,"authoritative_audio":multiplayer.is_server(),"muted":tracking_only,"show_subtitles":not tracking_only}):return
 _character_gesture(channel,model,mood,raised,gesture)
 reaction_pose[channel].speech_serial=serial;reaction_pose[channel].erase("requested_pose")
 reaction_pose[channel].affect=affect;reaction_pose[channel].person_id=actor
 if provider:pending_voice[_voice_key(channel,serial)]={"serial":serial,"teacher":actor,"text":text,"priority":3,"at":Time.get_ticks_msec(),"room":room}
 if not tracking_only:students.focus_on_player(class_id,actor)

func _request_classmate_audio(_peer: int,serial: int,actor: String,text: String,delivery: Dictionary) -> void:
 var key:=_provider_speech_key(actor,text,delivery)
 _request_reaction_audio("classmate:"+actor,serial,actor,text,key,13,delivery)

func _queue_question(peer: int,room: String,content: Variant,expected_teacher: String="",expected_class: String="",voice_context: Dictionary={}) -> void:
 var received_ms:=Time.get_ticks_msec()
 if not multiplayer.is_server() or not game.session.roster.has(peer):return
 var activity: Dictionary=_ai_activity(room)
 var teacher:=str(activity.get("teacher",""))
 if not Roster.has(teacher):return
 if not _matches_selected_target(activity,expected_teacher,expected_class):
  if Roster.has(expected_teacher):_question_status(peer,room,expected_teacher,"The selected character or class has changed. Please select them again.")
  return
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
 questions.append({"peer":peer,"room":room,"teacher":teacher,"class":str(activity.get("id","")),"content":content,"voice_context":voice_context,"_timing":{"host_received_ms":received_ms,"input_kind":"microphone" if content is PackedByteArray else "typed"}})
 if game.host_openai.busy or not ai_busy.is_empty() or questions.size()>1:
  _question_status(peer,room,teacher,"Question queued. Position %d."%questions.size())
 _next_question()

func _question_status(peer: int,room: String,teacher: String,message: String) -> void:
 if peer==multiplayer.get_unique_id():_dialogue_reply(room,teacher,message)
 elif game.session.online and game.session.peer_connected_now(peer):_dialogue_reply.rpc_id(peer,room,teacher,message)

func _next_question() -> void:
 if not _sync_character_profile():return
 if questions.is_empty() or ai_busy.size()>=3:return
 var selected:=-1
 for index in questions.size():
  var candidate: Dictionary=questions[index]
  var channel:="classmate:"+str(candidate.student) if candidate.has("student") else str(candidate.get("teacher",""))
  if not ai_busy.has(int(candidate.peer)) and channel not in question_channels.values():selected=index;break
 if selected<0:return
 var entry: Dictionary=questions.pop_at(selected)
 if not _voice_context_valid(int(entry.peer),entry.get("voice_context",{})):return
 var timing: Dictionary=entry.get_or_add("_timing",{})
 timing.queue_started_ms=Time.get_ticks_msec()
 if timing.has("host_received_ms"):timing.queue_wait_ms=int(timing.queue_started_ms)-int(timing.host_received_ms)
 if entry.has("student"):
  question_channels[int(entry.peer)]="classmate:"+str(entry.student)
  _answer_classmate(entry);return
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
 question_channels[peer]=teacher
 _question_status(peer,room,teacher,"The teacher is answering…")
 if entry.content is PackedByteArray:_transcribe_question(peer,room,teacher,entry.class,entry.content,pos,entry.get("voice_context",{}),timing)
 else:_answer_question(peer,room,teacher,entry.class,entry.content,pos,entry.get("voice_context",{}),timing)

func lesson_question_active(room: String) -> bool:
 if bool(_ai_activity(room).get("npc_voice_question",false)):return true
 if is_instance_valid(speech_player) and speech_player.has_suspended(room):return true
 return room in ai_busy.values() or questions.any(func(entry: Dictionary):return entry.get("room")==room and not entry.has("student"))

func _release_question(peer: int,epoch: int) -> bool:
 # Old asynchronous work cannot release a new session's actor reservation.
 if epoch!=character_epoch:return false
 ai_busy.erase(peer);question_channels.erase(peer)
 return true

func _answer_question(peer: int,room: String,id: String,class_id: String,question: String,pos: Vector3,voice_context: Dictionary={},timing: Dictionary={}) -> void:
 var epoch:=character_epoch
 await _answer_question_inner(peer,room,id,class_id,question,pos,voice_context,timing)
 if _release_question(peer,epoch) and is_instance_valid(speech_player):resume_voice_channel(room,room)

func _answer_question_inner(peer: int,room: String,id: String,class_id: String,question: String,pos: Vector3,voice_context: Dictionary={},timing: Dictionary={}) -> void:
 var activity:=_ai_activity(room)
 if not multiplayer.is_server() or activity.get("id","")!=class_id or activity.get("teacher","")!=id or not game.lecture_classes._inside(peer,room):
  return
 var epoch:=character_epoch
 var identity:=str(game.school.identities.get(peer,""))
 if identity.is_empty():return
 var stage: Dictionary={}
 if activity.get("phase","")=="lesson":stage=game.lecture_classes._stage(activity) if activity.has("teaching") else game.school.teaching_stage()
 var person:=Characters.teacher(id)
 var model:=_model_for_room(room,id)
 var observations:=_character_observations(peer,model,activity)
 var lab_evidence:=_ac_measurement_context(peer,activity) if room=="ac_lab" else ""
 var active_room: Dictionary=game.lecture_classes.classes.get(room,{})
 var can_show: bool=active_room.get("id","")==class_id and activity.get("phase","")=="lesson"
 var visual:=Visuals.description(activity) if can_show else {}
 var wants_visual:=can_show and Visuals.requested(question,not visual.is_empty())
 var extra:={"observations":observations,"teaching_step":stage,"station_readings":lab_evidence,"current_display":visual,"wants_visual":wants_visual,"available_actions":CharacterInteraction.ACTIONS}
 extra._timing=timing.duplicate(true)
 var captured_activity:=activity.duplicate(true)
 extra._valid=func():return _character_context_current(epoch,captured_activity) and game.lecture_classes._inside(peer,room) and str(game.school.identities.get(peer,""))==identity and _voice_context_valid(peer,voice_context)
 var client: Node=game.host_openai
 var prepared:=await character_interaction.prepare(client,person,identity,activity,question,extra)
 var current_class:=_ai_activity(room)
 var valid: bool=not prepared.get("cancelled",false) and bool(extra._valid.call())
 if not valid:
  var cancelled:={"prepared":prepared,"turn":prepared.turn,"line":"","source":"cancelled","fallback_reason":"activity_changed","event_id":prepared.event_id}
  character_interaction.record(cancelled,false);return
 var turn: Dictionary=prepared.turn
 var action:=str(turn.interpretation.get("requested_action",""))
 if action.is_empty():action=_character_action(question)
 var willingness:=CharacterBehavior.action_willingness(person,action,turn.relationship,str(prepared.activity.get("phase","")),turn.decision,turn.get("emotions",{}))
 prepared.context.action_willingness=willingness
 var permitted: bool=(action.is_empty() or bool(willingness.accepted)) and not turn.get("closed",false) and not turn.get("quiet",false) and not prepared.moderated and turn.get("strategy","") not in ["refuse","refuse_help","return_to_work","ignore","walk_away","dismiss"]
 if permitted and not action.is_empty():
  var target:=_character_action_point(room,action,pos)
  var accepted:=false
  if bool(observations.player_visible):
   if action in CharacterMotion.POSES and target.is_finite() and bool(observations.get("has_arms",false)):
    _clear_reaction_pose(room)
    reaction_pose[room]={"model":model,"until":Time.get_ticks_msec()+3200,"requested_pose":action,"point":target,"mood":turn.emotion}
    accepted=true
   elif action in ["approach","approach_board"]:
    accepted=_approach_in_lab(room,model,target) if room in ["ac_lab","dc_lab"] else _request_classroom_route(room,id,"conversation:"+str(Time.get_ticks_msec()),target,1.6,peer,Time.get_ticks_msec()+14000)
  prepared.context.executed_action=_character_action_status(action,accepted)
  prepared.context.executed_action.current_posture="standing"
  prepared.extra.executed_action=prepared.context.executed_action
  prepared.extra.wants_visual=false
 elif permitted and can_show:
  var presentation:=Visuals.presentation_request(question)
  var visual_file:=Visuals.file_request(question)
  var outcome:=""
  if not visual_file.is_empty():outcome=Visuals.use_local_file(active_room,visual_file,game.lecture_classes._now()) if peer==multiplayer.get_unique_id() else "The session host manages saved animations."
  elif presentation.get("op","")=="pin_slide":outcome=Visuals.pin_slide(active_room,int(stage.get("index",-1)),game.lecture_classes._now()) if peer==multiplayer.get_unique_id() else "The session host manages slide attachments."
  elif not presentation.is_empty() and Visuals.apply(active_room,presentation,game.lecture_classes._now()):outcome=str(presentation.reply)
  if not outcome.is_empty():
   prepared.context.executed_action={"action":"presentation_control","result":outcome}
   prepared.extra.executed_action=prepared.context.executed_action
   prepared.extra.wants_visual=false
 var result:=await character_interaction.generate(client,prepared)
 current_class=_ai_activity(room)
 valid=not result.get("cancelled",false) and bool(extra._valid.call())
 if current_class.get("phase","")=="office_hours":valid=valid and _near_instructor(peer,room)
 if not valid:character_interaction.record(result,false);return
 var plan: Dictionary=result.get("plan",{})
 if plan.get("action")!=null:
  var live: Dictionary=game.lecture_classes.classes.get(room,{})
  var applied: bool=live.get("id","")==class_id and live.get("phase","")=="lesson" and Visuals.apply(live,plan.action,game.lecture_classes._now())
  prepared.extra.executed_action={"action":"visual_plan","succeeded":applied}
  if not applied:
   result.line="";result.source="technical_unavailable";result.technical_status="The display did not accept that change."
 if current_class.has("visual_playback"):game.lecture_classes._publish()
 _mark_character_response_ready(result)
 character_interaction.record(result,true)
 if not bool(prepared.extra.get("executed_action",{}).get("accepted",prepared.extra.get("executed_action",{}).get("succeeded",false))) and str(turn.get("pose","")) in CharacterMotion.POSES:
  _character_gesture(room,model,str(result.emotion),false,str(turn.pose))
 if result.silent:
  _report_voice_stage(peer,voice_context,"intentional_silence")
  if attention.has(room):attention[room].until=Time.get_ticks_msec()
  _question_status(peer,room,id,"")
  return
 if result.source=="technical_unavailable":
  _report_voice_stage(peer,voice_context,"response_failed",str(result.get("technical_status","Character response unavailable.")))
  _question_status(peer,room,id,str(result.get("technical_status","Character response unavailable.")))
  return
 for gesture in result.get("nonverbal",[]):
  _character_gesture(room,model,str(result.emotion),false,str(gesture))
 var reply:=str(result.line)
 _report_voice_stage(peer,voice_context,"response_generated")
 _question_status(peer,room,id,reply)
 if not reply.is_empty():
  _publish_attention(room,id,pos)
  if current_class.get("phase","")=="lesson":present_class_reaction(room,id,reply,3,str(result.event_id),timing)
  else:
   var serial:=_next_speech(room)
   _track_character_audio(room,serial,str(result.event_id),timing)
   _show_reaction(room,id,reply,pos,serial,3,false,str(result.emotion))
   _broadcast_reaction(room,id,reply,pos,serial,3)
 if reaction_pose.has(room):reaction_pose[room].erase("requested_pose")
@rpc("any_peer","call_remote","reliable")
func _ask(room: String,intent: String,phone_id: String,expected_teacher: String,expected_class: String) -> void:
 if multiplayer.is_server() and _valid_selected_target(expected_teacher,expected_class):_dialogue_request(multiplayer.get_remote_sender_id(),room,intent,phone_id,expected_teacher,expected_class)
func _dialogue_request(peer: int,room: String,intent: String,phone_id: String="",expected_teacher: String="",expected_class: String="") -> void:
 if not game.session.roster.has(peer) or intent not in ["inspect_circuit","evaluate_led","hand_phone","reclaim_phone"]:return
 var activity:=_ai_activity(room)
 if not _matches_selected_target(activity,expected_teacher,expected_class):return
 var id:=str(activity.get("teacher",""))
 var point:=_teacher_position(room)
 var pos: Vector3=game.player.global_position if peer==multiplayer.get_unique_id() else game.session.poses.get(peer,{}).get("position",Vector3.INF)
 if not Roster.has(id) or not pos.is_finite() or not game.campus.registry.room_contains(room,pos):return
 if not (room=="ac_lab" and intent=="inspect_circuit") and (not point.is_finite() or pos.distance_to(point)>3.6):return
 var now:=Time.get_ticks_msec()
 if now-int(last_dialogue.get(peer,-1000))<350:return
 last_dialogue[peer]=now
 var reply: String
 if activity.get("phase","")=="assignment" and intent in ["inspect_circuit","evaluate_led"]:
  reply="Circuit checks and evaluation are your own work during this assessment."
 elif intent in ["hand_phone","reclaim_phone"]:
  reply=game.smartphones.teacher_handoff(peer,room,id,intent=="reclaim_phone",phone_id)
 elif room=="ac_lab" and intent=="inspect_circuit":
  reply=_ac_measurement_context(peer,activity)
  if reply.is_empty():reply="Come to your assigned or nearest available AC bench so I can inspect its instruments."
 else:
  reply=_inspect_student_circuit(peer,room,id,activity,intent=="evaluate_led")
 var identity:=str(game.school.identities.get(peer,""))
 if identity.is_empty():return
 var request:=str({"inspect_circuit":"Please inspect my circuit.","evaluate_led":"Please evaluate my LED circuit.","hand_phone":"Please hold my phone.","reclaim_phone":"May I have my phone back?"}.get(intent,""))
 var extra:={"executed_action":{"action":intent,"result":reply},"station_readings":reply,"intention":"Respond to the confirmed operation in your own voice. The exact instrument or custody result is displayed separately. Do not invent another action, measurement, grade, or safety guarantee.","_valid":func():return str(game.school.identities.get(peer,""))==identity and game.lecture_classes._inside(peer,room)}
 var result:=await generate_character_exchange(Characters.teacher(id),identity,activity,request,extra)
 if result.is_empty() or result.get("cancelled",false):return
 var commentary:=str(result.get("line",""))
 var display:="Result: "+reply+("\n\n"+commentary if not commentary.is_empty() and commentary!=reply else "")
 if peer==multiplayer.get_unique_id():_dialogue_reply(room,id,display)
 elif game.session.online and game.session.peer_connected_now(peer):_dialogue_reply.rpc_id(peer,room,id,display)
 if not commentary.is_empty():
  var serial:=_next_speech(room)
  _show_reaction(room,id,commentary,point,serial,2,false,str(result.emotion))
  _broadcast_reaction(room,id,commentary,point,serial,2)

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
 if not conversation.visible or conversation_room!=room or not conversation_student.is_empty() or not Roster.has(id):
  if voice_room==room and is_instance_valid(voice_hint):
   var lower:=response.to_lower()
   if ["unavailable","failed","error","not recognized","enable ","ended","limit","could not"].any(func(word):return word in lower):voice_hint.text=response;voice_hint.show()
  return
 if str(conversation.get_meta("selected_character_id",""))!=id or not _selected_conversation_current():return
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
 if not multiplayer.is_server() or not game.session.roster.has(peer) or not position.is_finite() or not _sync_character_profile():return false
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
 var decision:=brain.consider(id,identity,kind,clampf(severity,0.0,1.0),personality,Time.get_ticks_msec(),rng.randf(),noticed,false)
 var person:=Characters.teacher(id)
 var event_id:="observed:%s:%s"%[character_interaction.session_id,str(Time.get_ticks_usec())]
 var record_key:=str(activity.get("id",room))+":"+identity
 var discipline:=Discipline.consider(person,{"verified":true,"perceived":true,"kind":kind,"phase":str(activity.get("phase","")),"event_id":event_id,"severity":severity},discipline_records.get(record_key,{}),Time.get_ticks_msec())
 if not discipline.is_empty():
  discipline_records[record_key]=discipline.record
  var decision_view:=discipline.duplicate(true)
  decision_view.erase("record")
  decision_view.event_id=event_id
  discipline_records[record_key].decision=decision_view
 if decision.is_empty() and discipline.is_empty():return false
 if decision.is_empty():decision={"intent":{"phone_use":"phone","voice_noise":"noise","seat_departure":"seat_departure","lab_hazard":"hazard","thrown_object":"throw"}.get(kind,"class_message"),"level":"firm" if discipline.get("interrupt",false) else "calm"}
 var consequence:=_apply_human_discipline(peer,room,activity,id,discipline) if not discipline.is_empty() else {"executed":false}
 if not discipline.is_empty():discipline_records[record_key].decision.execution=consequence
 var description:="The student was perceived %s in %s."%[kind.replace("_"," "),str(activity.get("phase","campus"))]
 var turn: Dictionary={}
 if str(context.get("message","")).is_empty():
  turn=character_mind.observe(person,brain.relationship(id,identity),description,Time.get_ticks_msec(),identity,"hazard" if kind=="lab_hazard" else "disruption",event_id,{"phase":str(activity.get("phase","")),"meaning":description,"severity":severity})
  brain.remember_event(person,identity,turn,description,"",int(Time.get_unix_time_from_system()),event_id,true)
 if discipline.get("action","") in ["ignore","look"]:
  if discipline.action=="look":_publish_attention(room,id,position)
  # Heard words still receive semantic interpretation and memory even when
  # the teacher chooses not to interrupt the room with a spoken response.
  if turn.is_empty():
   _respond_observed_event.call_deferred(peer,room,id,activity.duplicate(true),str(context.get("message","")),{"listen_only":true,"observed_event":{"kind":kind,"description":description},"discipline":{"action":discipline.action,"execution":consequence}},position,1)
  return false
 if kind=="addressed_speech":
  decision.intent=Dialogue.message_intent(str(context.get("message","")))
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
 var text:="Power is off after a circuit fault. Check the connections before trying again." if kind=="lab_hazard" else ""
 if kind in ["class_message","voice_noise","phone_use"] and str(decision.get("level",""))=="firm" and activity.get("phase","")=="lesson" and is_instance_valid(class_events) and class_events.has_method("request_board_challenge"):
  class_events.call("request_board_challenge",peer,room,id,Time.get_ticks_msec()/1000.0)
 var priority:=4 if kind in ["lab_hazard","thrown_object"] else (3 if kind in ["class_message","voice_noise","phone_use"] else 1)
 if kind in ["class_message","voice_noise","phone_use"] and activity.get("phase","")=="lesson":classroom_disruption.emit(room,id)
 if kind=="lab_hazard":
  # Immediate host-verified laboratory intervention never waits for a provider.
  brain.complete_event(person,identity,event_id,text)
  var serial:=_next_speech(room)
  _show_reaction(room,id,text,position,serial,priority)
  _broadcast_reaction(room,id,text,position,serial,priority)
  return true
 var extra:={"initiate":str(context.get("message","")).is_empty(),"observed_event":{"kind":kind,"description":description},"discipline":{"action":discipline.get("action","remark"),"reason":discipline.get("reason",""),"execution":consequence},"intention":"React to the actual perceived behavior as yourself. Refer only to a consequence that was executed; a pending request is not a completed action."}
 if not turn.is_empty():extra.existing_turn=turn;extra.existing_event_id=event_id
 _respond_observed_event.call_deferred(peer,room,id,activity.duplicate(true),str(context.get("message","")),extra,position,priority)
 return true

func discipline_action_for(peer: int,room: String) -> Dictionary:
 var activity:=_ai_activity(room)
 var identity:=str(game.school.identities.get(peer,""))
 return discipline_records.get(str(activity.get("id",room))+":"+identity,{}).get("decision",{}).duplicate(true)

func complete_discipline_action(peer: int,room: String,action: String,executed: bool) -> void:
 if not multiplayer.is_server():return
 var activity:=_ai_activity(room)
 var identity:=str(game.school.identities.get(peer,""))
 var key:=str(activity.get("id",room))+":"+identity
 if not discipline_records.has(key):return
 var decision: Dictionary=discipline_records[key].get("decision",{})
 if decision.get("action","")!=action:return
 decision.execution={"action":action,"executed":executed,"pending":false}

func _apply_human_discipline(peer: int,room: String,activity: Dictionary,id: String,decision: Dictionary) -> Dictionary:
 if decision.is_empty():return {"executed":false}
 var action:=str(decision.action)
 if action in ["ignore","look","remark","warning","stop_activity"]:
  if action!="ignore":_publish_attention(room,id,game.lecture_classes._position(peer))
  return {"executed":action in ["look","stop_activity"],"action":action}
 if action=="confiscate":
  # The phone service owns inventory custody and persistence; it consumes the
  # same validated decision after report_event returns.
  return {"executed":false,"pending":true,"action":action}
 var target:=Vector3.INF
 if action in ["move","remove"]:
  if action=="remove" and activity.get("phase","")=="assignment":return {"executed":false,"reason":"Assessment work must remain accessible."}
  target=_discipline_destination(peer,room,activity,action=="remove")
  if not target.is_finite():return {"executed":false,"reason":"No clear safe destination is available."}
 if action=="put_away":game.smartphones.classroom_open.erase(peer)
 if peer==multiplayer.get_unique_id():
  var executed:=_perform_discipline(room,str(activity.get("id","")),id,action,target)
  return {"executed":executed,"action":action}
 if game.session.online and game.session.peer_connected_now(peer):
  _discipline_instruction.rpc_id(peer,room,str(activity.get("id","")),id,action,target)
  return {"executed":false,"pending":true,"action":action}
 return {"executed":false,"action":action}

func _discipline_destination(peer: int,room: String,activity: Dictionary,remove: bool) -> Vector3:
 var candidates: Array[Vector3]=[]
 var origin: Vector3=game.lecture_classes._position(peer)
 if remove:
  var definition: Dictionary=game.campus.registry.get_room(room)
  var raw: Variant=definition.get("door")
  var anchor_raw: Variant=definition.get("anchor")
  if raw is Array and raw.size()==3 and anchor_raw is Array and anchor_raw.size()==3:
   var door:=Vector3(float(raw[0]),float(raw[1]),float(raw[2]))
   var anchor:=Vector3(float(anchor_raw[0]),float(anchor_raw[1]),float(anchor_raw[2]))
   var outward: Vector3=(door-anchor).normalized();outward.y=0.
   for distance in [1.,1.6,2.2,2.8]:candidates.append(door+outward*distance)
 else:
  for chair in game.chairs:
   if is_instance_valid(chair) and chair.occupant==0 and game.campus.registry.room_contains(room,chair.global_position) and chair.global_position.distance_to(origin)>2.:
    candidates.append(chair.global_position+chair.global_basis.z*.95)
 var shape:=CapsuleShape3D.new();shape.radius=.28;shape.height=1.7
 var query:=PhysicsShapeQueryParameters3D.new();query.shape=shape;query.collision_mask=3
 if peer==multiplayer.get_unique_id():query.exclude=[game.player.get_rid()]
 for candidate in candidates:
  if game.campus.registry.room_contains(room,candidate)==remove:continue
  var occupied:=false
  for other in game.session.roster:
   if int(other)==peer:continue
   var position: Vector3=game.lecture_classes._position(int(other))
   if position.is_finite() and position.distance_to(candidate)<.85:occupied=true;break
  if occupied:continue
  var ground:=get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(candidate+Vector3.UP*1.5,candidate-Vector3.UP*1.5,1))
  if ground.is_empty() or ground.normal.dot(Vector3.UP)<.7:continue
  var target: Vector3=ground.position+Vector3.UP*.04
  query.transform=Transform3D(Basis.IDENTITY,target+Vector3.UP*.85)
  if get_world_3d().direct_space_state.intersect_shape(query,1).is_empty():return target
 return Vector3.INF

@rpc("authority","call_remote","reliable")
func _discipline_instruction(room: String,class_id: String,id: String,action: String,target: Vector3) -> void:
 _perform_discipline(room,class_id,id,action,target)

func _perform_discipline(room: String,class_id: String,id: String,action: String,target: Vector3) -> bool:
 var activity: Dictionary=game.lecture_classes.classes.get(room,{}) if multiplayer.is_server() else game.lecture_classes.public_classes.get(room,{})
 if str(activity.get("id",""))!=class_id or str(activity.get("teacher",""))!=id:return false
 if action=="put_away":
  game.smartphones.show_put_away_warning(id)
  return true
 if action not in ["move","remove"] or not target.is_finite():return false
 if action=="remove" and activity.get("phase","")=="assignment":return false
 if action=="move" and not game.campus.registry.room_contains(room,target):return false
 if target.distance_to(game.player.global_position)>25.:return false
 if game.player.seated!=null:game._stand_from_chair()
 if game.player.seated!=null:return false
 game.player.global_position=target;game.player.velocity=Vector3.ZERO
 return true

func _respond_observed_event(peer: int,room: String,id: String,activity: Dictionary,question: String,extra: Dictionary,position: Vector3,priority: int) -> void:
 var identity:=str(game.school.identities.get(peer,""))
 var latest:=discipline_action_for(peer,room)
 if latest.get("event_id","")==extra.get("existing_event_id","") and extra.has("discipline"):
  extra.discipline.execution=latest.get("execution",extra.discipline.get("execution",{}))
 if extra.has("discipline"):extra.executed_action=extra.discipline.get("execution",{})
 var result:=await generate_character_exchange(Characters.teacher(id),identity,activity,question,extra)
 if result.is_empty() or result.get("cancelled",false) or str(result.get("line","")).is_empty():return
 var pose:=str(result.turn.get("pose",""))
 if pose in CharacterMotion.POSES:_character_gesture(room,_model_for_room(room,id),str(result.emotion),false,pose)
 var serial:=_next_speech(room)
 _show_reaction(room,id,str(result.line),position,serial,priority,false,str(result.emotion))
 _broadcast_reaction(room,id,str(result.line),position,serial,priority)

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
  _announce_character(room,teacher,activity,"classroom:"+str(activity.get("course","")),"Two distinct students are speaking over each other during the lesson. Respond according to your tolerance, authority and current mood without inventing individual blame.","",2,{"observed_event":{"kind":"overlapping_speech","speakers":2}})
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
 attention[room]={"model":model,"rest":rest,"target":atan2(direction.x,direction.z),
  "until":Time.get_ticks_msec()+roundi(float(model.get_meta("classroom_eye_contact",7.))*1000.)}

func _publish_attention(room: String,id: String,point: Vector3) -> void:
 _set_attention(room,id,point)
 if not game.session.online:return
 for peer in game.session.roster:
  if int(peer)==multiplayer.get_unique_id() or not game.session.peer_connected_now(int(peer)):continue
  var at: Vector3=game.session.poses.get(peer,{}).get("position",Vector3.INF)
  if at.is_finite() and game.campus.registry.locate(at)==room:_attention.rpc_id(int(peer),room,id,point)

func present_class_reaction(room: String,id: String,text: String,priority: int=1,event_id: String="",timing: Dictionary={}) -> void:
 if not multiplayer.is_server() or text.is_empty() or text.length()>CharacterSpeech.MAX_TEXT or priority<1 or priority>3:return
 var activity: Dictionary=game.lecture_classes.classes.get(room,{})
 if str(activity.get("teacher",""))!=id or activity.get("phase","")!="lesson":return
 var point:=_teacher_position(room)
 if not point.is_finite():return
 var speech_id:=_next_speech(room)
 _track_character_audio(room,speech_id,event_id,timing)
 _show_reaction(room,id,text,point,speech_id,priority)
 _broadcast_reaction(room,id,text,point,speech_id,priority)

func present_class_intention(room: String,id: String,intention: String,observed: Dictionary={},priority: int=1) -> void:
 if not multiplayer.is_server() or intention.is_empty() or not Roster.has(id):return
 var activity: Dictionary=game.lecture_classes.classes.get(room,{})
 if str(activity.get("teacher",""))!=id or activity.get("phase","")!="lesson":return
 _announce_character(room,id,activity,"classroom:"+str(activity.get("course","")),intention,"",priority,{"observed_event":observed,"official_communication":true})

func acknowledge_attendance(room: String,teacher: String,peer: int) -> void:
 if not multiplayer.is_server() or not Roster.has(teacher):return
 var activity:=_ai_activity(room)
 var identity:=str(game.school.identities.get(peer,""))
 if identity.is_empty() or str(activity.get("teacher",""))!=teacher:return
 _announce_character(room,teacher,activity,identity,"Acknowledge this student's verified arrival in your own manner. Your prior relationship matters; this does not change their official attendance record.",CharacterBehavior.classroom_line(Characters.teacher(teacher),"attendance"),1,{"_valid":func():return str(game.school.identities.get(peer,""))==identity and game.lecture_classes._inside(peer,room)})

func present_assessment_intro(room: String,id: String,course: String) -> void:
 if not multiplayer.is_server() or not Roster.has(id):return
 var activity: Dictionary=game.lecture_classes.classes.get(room,{})
 if activity.get("phase","")!="assignment" or str(activity.get("teacher",""))!=id or str(activity.get("course",""))!=course:return
 var point:=_teacher_position(room)
 if not point.is_finite():return
 _sync_voice_room_context(room,activity)
 _cancel_room_speech(room)
 _clear_reaction_pose(room)
 classroom_phase[room]="assignment"
 _announce_character(room,id,activity,"classroom:"+course,"The assessment has opened. Announce individual work and the classroom rules in your own voice. Never include questions, solutions, numerical hints, or private marks.","",2,{"official_communication":true,"administrative_rules":"Individual assessment; work independently. Clarification of administrative rules is allowed."})

func _next_speech(room: String) -> int:
 var serial:=int(speech_serial.get(room,0))+1
 speech_serial[room]=serial
 return serial

func _mark_character_response_ready(result: Dictionary) -> void:
 var prepared: Dictionary=result.get("prepared",{})
 if prepared.get("extra",{}).get("_timing") is Dictionary:
  prepared.extra._timing.host_text_ready_ms=Time.get_ticks_msec()

func _track_character_audio(room: String,serial: int,event_id: String,timing: Dictionary) -> void:
 if not multiplayer.is_server() or event_id.is_empty() or not timing.has("host_received_ms"):return
 var key:=room+":"+str(serial)
 if not speech_turn_timings.has(key) and speech_turn_timings.size()>=128:speech_turn_timings.erase(speech_turn_timings.keys()[0])
 speech_turn_timings[key]={"event_id":event_id,"host_received_ms":int(timing.host_received_ms)}

func _character_audio_ready(room: String,serial: int) -> void:
 _note_character_audio(room,serial,"audio_ready",Time.get_ticks_msec())

func _character_audio_started(room: String,serial: int,at_ms: int) -> void:
 _note_character_audio(room,serial,"playback_started",at_ms)

func _note_character_audio(room: String,serial: int,phase: String,at_ms: int) -> void:
 if not multiplayer.is_server():return
 var timing: Dictionary=speech_turn_timings.get(room+":"+str(serial),{})
 if timing.is_empty() or at_ms<int(timing.host_received_ms):return
 character_interaction.note_audio_latency(str(timing.event_id),phase,float(at_ms-int(timing.host_received_ms)))

static func speech_cache_key(id: String,text: String) -> String:
 return id+":"+text.sha256_text()

func _provider_speech_key(id: String,text: String,delivery: Dictionary) -> String:
 # Runtime request IDs, retry counters and object references cannot enter a
 # reusable voice key. The approved identity and performance version must.
 delivery=preload("res://scripts/campus/academics/character_voice_delivery.gd").for_text(delivery,text)
 var stable:={"character_id":id,"text":text,"provider":delivery.get("provider","openai"),"model":delivery.get("model",game.host_openai.tts_model),
  "voice":delivery.get("voice",""),"voice_type":delivery.get("voice_type","preset"),"profile_version":delivery.get("profile_version",0),
  "delivery_key":delivery.get("delivery_key",""),"instructions":delivery.get("instructions",""),"speed":delivery.get("speed",1.),
  "projection":delivery.get("projection","normal"),"intensity":delivery.get("intensity",.5)}
 return id+":openai:"+JSON.stringify(stable).sha256_text()

func _broadcast_reaction(room: String,id: String,text: String,point: Vector3,serial: int,priority: int) -> void:
 if not game.session.online:return
 var emotion_state:=character_mind.context(Characters.teacher(id),Time.get_ticks_msec())
 var mood:=str(emotion_state.emotion)
 # _show_reaction creates a route only after compatibility and queue checks.
 # Never promise remote audio when the host has already rejected the voice.
 var route: Dictionary=speech_routes.get(_voice_key(room,serial),{})
 var provider:=not route.is_empty() and _speech_route_current(room,serial,route)
 var audio_delivery: Dictionary=route.get("audio_delivery",{}) if provider else {}
 var pose: Dictionary=reaction_pose.get(room,{})
 var gesture:=str(pose.get("gesture","")) if int(pose.get("speech_serial",-1))==serial else ""
 var gesture_point: Vector3=pose.get("point",Vector3.INF)
 for peer in _voice_recipients(room):
  _reaction.rpc_id(peer,room,id,text,point,serial,priority,provider,mood,false,gesture,gesture_point,emotion_state.emotions,audio_delivery)

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
 var serial:=_next_speech(room)
 class_calls[room]={"class_id":str(activity.id),"event_id":str(state.round.event_id),"identity":identity,"serial":serial}
 _request_classroom_route(room,id,"event:"+str(activity.id)+":"+str(state.round.event_id)+":called:"+str(peer),point,1.8,peer)
 _publish_attention(room,id,point)
 var event_id:=str(state.round.event_id)
 var result:=await generate_character_exchange(Characters.teacher(id),identity,activity,"",{"initiate":true,"official_communication":true,"intention":"Call on the selected student to explain their reasoning. Use your own teaching manner and do not reveal the practice answer.","_valid":func():return class_calls.get(room,{}).get("event_id","")==event_id and str(state.hands.selected)==identity and not state.round.closed})
 if result.is_empty() or result.get("cancelled",false) or str(result.line).is_empty():return
 serial=_next_speech(room)
 class_calls[room].serial=serial
 _show_reaction(room,id,str(result.line),point,serial,2,false,str(result.emotion))
 _broadcast_reaction(room,id,str(result.line),point,serial,2)

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
func _reaction(room: String,id: String,text: String,point: Vector3,serial: int=0,priority: int=1,provider := false,mood := "steady",raised := false,gesture := "",gesture_point := Vector3.INF,affect: Dictionary={},audio_delivery: Dictionary={}) -> void:
 if serial>0 and is_instance_valid(speech_player) and serial<=int(speech_player.last_serial.get(room,0)):return
 if room in ["ac_lab","dc_lab"]:
  var activity:=_lab_visit(room)
  var visible_id:=str(activity.get("teacher",""))
  if visible_id!=id:return
 if room in LECTURE_ROOMS and not is_instance_valid(_model_for_room(room,id)):return
 _show_reaction(room,id,text,point,serial,priority,provider,mood,raised,gesture,gesture_point,affect,audio_delivery)

func _character_pitch(mood: String) -> float:
 return CharacterMotion.pitch(mood)

func _character_gesture(key: String,model: Node3D,mood: String,raised: bool,gesture := "",point := Vector3.INF) -> void:
 _clear_reaction_pose(key)
 var pose:=gesture if gesture in CharacterMotion.POSES else ("raise_hand" if raised else "")
 reaction_pose[key]={"model":model,"until":Time.get_ticks_msec()+3200,"mood_until":Time.get_ticks_msec()+90000,"started":Time.get_ticks_msec(),"person_id":str(model.get_meta("faculty_id",key.trim_prefix("classmate:") if key.begins_with("classmate:") else "")),"mood":mood,"gesture":pose,"requested":raised,"requested_pose":gesture,"point":point}
 if key.begins_with("classmate:") and raised:model.set_meta("conversation_hand_until",reaction_pose[key].until)

func _show_reaction(room: String,id: String,text: String,point: Vector3,serial: int=0,priority: int=1,provider := false,mood := "steady",raised := false,gesture := "",gesture_point := Vector3.INF,affect: Dictionary={},audio_delivery: Dictionary={}) -> void:
 if not Roster.has(id):return
 text=CharacterSpeech.complete(SpeechMath.display(text))
 if text.is_empty():return
 var root: Node3D
 if room=="ac_lab":root=game.school_world.teacher
 elif room=="dc_lab":root=game.school_world.dc_instructor
 else:root=lecture_models.get(room)
 if not is_instance_valid(root):return
 if not is_instance_valid(_model_for_room(room,id)):return
 _set_attention(room,id,point)
 if multiplayer.is_server():
  var emotion_state:=character_mind.context(Characters.teacher(id),Time.get_ticks_msec())
  mood=emotion_state.emotion;affect=emotion_state.emotions
  var pending: Dictionary=reaction_pose.get(room,{})
  if pending.has("requested_pose"):
   gesture=str(pending.requested_pose)
   gesture_point=pending.get("point",Vector3.INF)
   pending.erase("requested_pose")
 if gesture=="point" and gesture_point.is_finite():_set_attention(room,id,gesture_point)
 if priority>=2 or mood!="steady":
  _character_gesture(room,_model_for_room(room,id),mood,raised,gesture,gesture_point)
  reaction_pose[room].affect=affect
  reaction_pose[room].speech_serial=serial
  reaction_pose[room].erase("requested_pose")
 if is_instance_valid(reaction_labels.get(room)):reaction_labels[room].queue_free()
 reaction_labels.erase(room);reaction_until.erase(room)
 if serial<=0:
  # Legacy text-only reactions use the same screen-space caption queue.
  if is_instance_valid(speech_player):
   var caption_channel:="reaction:"+room
   speech_player.accept(caption_channel,str(Roster.entry(id).name),_next_speech(caption_channel),text,priority,root,null,1.,{"expect_audio":false})
  return
 if serial>0 and is_instance_valid(speech_player):
  speech_player.configure(bool(game.client_preferences.values.teacher_speech),bool(game.client_preferences.values.teacher_subtitles))
  var local_room: String=game.campus.registry.locate(game.player.global_position)
  var use_openai: bool=multiplayer.is_server() and _uses_class_voice() and (local_room==room or not _voice_recipients(room).is_empty())
  var delivery:=Characters.speech(Characters.teacher(id),str(game.host_openai.tts_model),priority,mood,affect) if use_openai else {}
  if use_openai and not bool(delivery.get("ok",false)):use_openai=false
  if priority==2 and _ai_activity(room).get("phase","")=="lesson" and bool(delivery.get("ok",false)):delivery.projection="lecture"
  var key:=_provider_speech_key(id,text,delivery) if use_openai else speech_cache_key(id,text)
  var stream: AudioStreamWAV=speech_player.stream_for(key) if use_openai or not provider else null
  if stream!=null:_character_audio_ready(room,serial)
  if provider:delivery=audio_delivery.duplicate(true)
  if not speech_player.accept(room,str(Roster.entry(id).name),serial,text,priority,root,stream,1.0,{"expect_audio":provider or use_openai,"authoritative_audio":multiplayer.is_server(),"character_id":id,"conversation_id":str(_ai_activity(room).get("id","")),"delivery":delivery}):return
  if provider:
   pending_voice[_voice_key(room,serial)]={"serial":serial,"teacher":id,"text":text,"priority":priority,"at":Time.get_ticks_msec(),"room":room}
   return
  if use_openai:
   speech_routes[_voice_key(room,serial)]=_new_speech_route(room,serial,room,id,_voice_recipients(room),_model_for_room(room,id),str(_ai_activity(room).get("id","")))
   speech_routes[_voice_key(room,serial)].audio_delivery={"projection":delivery.get("projection","normal"),"intensity":delivery.get("intensity",.5)}
   _request_reaction_audio(room,serial,id,text,key,priority+(10 if local_room==room else 0),delivery)

static func _voice_key(channel: String,serial: int) -> String:
 return channel+"|"+str(serial)

func _request_reaction_audio(channel: String,serial: int,id: String,text: String,key: String,priority: int,delivery: Dictionary) -> void:
 if not bool(delivery.get("ok",false)):
  _speech_completed(channel,serial,key,null,str(delivery.get("error","incompatible_voice")));return
 var stream: AudioStreamWAV=speech_player.stream_for(key)
 if stream!=null:_speech_completed.call_deferred(channel,serial,key,stream,"ok");return
 var result: String=speech_synth.request(channel,serial,id,text,key,priority,delivery)
 if result not in ["queued","duplicate","cached"]:_speech_completed(channel,serial,key,null,result)

func _new_speech_route(channel: String,serial: int,room: String,actor: String,peers: Array,anchor: Node3D,class_id: String="",private_peer: int=0,max_range: float=0.) -> Dictionary:
 var route:={"peers":peers.duplicate(),"room":room,"actor":actor,"class_id":class_id,"phase":str(_ai_activity(room).get("phase","")) if not class_id.is_empty() else "","epoch":character_epoch,"created":Time.get_ticks_msec(),
  "local_tracking":speech_player.has_utterance(channel,serial),"cancel_revision":speech_player.cancellation_revision(channel),"private_peer":private_peer,"max_range":max_range,"anchor":weakref(anchor) if is_instance_valid(anchor) else null}
 if private_peer>0 and is_instance_valid(natural_voice):
  var turn: Dictionary=natural_voice.remote_turns.get(private_peer,{})
  if str(turn.get("target",{}).get("student",""))==actor:route.voice_token=str(turn.get("token",""))
 return route

func _speech_route_current(channel: String,serial: int,route: Dictionary) -> bool:
 if route.is_empty() or int(route.get("epoch",-1))!=character_epoch or Time.get_ticks_msec()-int(route.get("created",0))>150000:return false
 var reference: WeakRef=route.get("anchor")
 var anchor: Node3D=reference.get_ref() if reference!=null else null
 if not is_instance_valid(anchor) or anchor.is_queued_for_deletion():return false
 var room:=str(route.get("room",""))
 var class_id:=str(route.get("class_id",""))
 if not class_id.is_empty():
  var activity:=_ai_activity(room)
  if str(activity.get("id",""))!=class_id or str(activity.get("phase",""))!=str(route.get("phase","")):return false
 if int(route.get("cancel_revision",-1))!=speech_player.cancellation_revision(channel) or speech_player.was_cancelled(channel,serial):return false
 var private_peer:=int(route.get("private_peer",0))
 if private_peer>0:
  if not game.session.roster.has(private_peer) or not game.lecture_classes._inside(private_peer,room):return false
  if game.lecture_classes._position(private_peer).distance_to(anchor.global_position)>float(route.get("max_range",4.2)):return false
  var token:=str(route.get("voice_token",""))
  if not token.is_empty() and (not is_instance_valid(natural_voice) or not natural_voice.is_current(private_peer,token)):return false
 return true

func _speech_route_recipient(peer: int,route: Dictionary) -> bool:
 if not game.session.online or not game.session.peer_connected_now(peer):return false
 var room:=str(route.get("room",""))
 if not room.is_empty() and not game.lecture_classes._inside(peer,room):return false
 var max_range:=float(route.get("max_range",0.))
 if max_range>0.:
  var reference: WeakRef=route.get("anchor")
  var anchor: Node3D=reference.get_ref() if reference!=null else null
  if not is_instance_valid(anchor) or game.lecture_classes._position(peer).distance_to(anchor.global_position)>max_range:return false
 return true

func _speech_completed(channel: String,serial: int,key: String,stream: AudioStreamWAV,status: String) -> void:
 if not is_instance_valid(speech_player):return
 var token:=_voice_key(channel,serial)
 var route: Dictionary=speech_routes.get(token,{})
 if route.is_empty():return
 pending_voice.erase(token)
 var recipients: Array=route.get("peers",[])
 if status=="cancelled" or not _speech_route_current(channel,serial,route):
  speech_routes.erase(token);speech_player.cancel_utterance(channel,serial)
  for peer in recipients:
   if game.session.online and game.session.peer_connected_now(int(peer)):_voice_cancel.rpc_id(int(peer),channel,serial)
  return
 if status!="ok" or stream==null:
  speech_routes.erase(token);speech_player.fail_stream(channel,serial,status)
  for peer in recipients:
   if _speech_route_recipient(int(peer),route):_voice_fallback.rpc_id(int(peer),channel,serial)
  return
 if not speech_player.cache_stream(key,stream):
  speech_routes.erase(token);speech_player.fail_stream(channel,serial,"invalid audio")
  for peer in recipients:
   if _speech_route_recipient(int(peer),route):_voice_fallback.rpc_id(int(peer),channel,serial)
  return
 _character_audio_ready(channel,serial)
 speech_player.deliver_stream(channel,serial,stream)
 var available: Array=[]
 for peer in recipients:
  if _speech_route_recipient(int(peer),route):available.append(int(peer))
 route.sending=available.size()
 if available.is_empty():speech_routes.erase(token);return
 for peer in available:_send_voice_clip_to(int(peer),channel,serial,stream,route)

func _send_voice_clip(room: String,serial: int,stream: AudioStreamWAV) -> void:
 var route: Dictionary=speech_routes.get(_voice_key(room,serial),{})
 if route.is_empty() or not _speech_route_current(room,serial,route):return
 for peer in route.get("peers",[]):
  if _speech_route_recipient(int(peer),route):_send_voice_clip_to(int(peer),room,serial,stream,route)

func _send_voice_clip_to(peer: int,channel: String,serial: int,stream: AudioStreamWAV,route: Dictionary={}) -> void:
 if not SpeechPlayer.valid_stream(stream):
  if game.session.online and game.session.peer_connected_now(peer):_voice_fallback.rpc_id(peer,channel,serial)
  _voice_send_finished(channel,serial,route);return
 var epoch:=character_epoch
 var samples:=stream.data
 var metadata:={"sha256":preload("res://scripts/campus/voice/speech_audio_transfer.gd").digest(samples),"projection":str(stream.get_meta("voice_projection","normal")),"normalized":bool(stream.get_meta("voice_normalized",false))}
 for offset in range(0,samples.size(),12000):
  if epoch!=character_epoch or not game.session.online or not game.session.peer_connected_now(peer):break
  if not route.is_empty() and (not _speech_route_current(channel,serial,route) or not _speech_route_recipient(peer,route)):
   _voice_cancel.rpc_id(peer,channel,serial);break
  _voice_chunk.rpc_id(peer,channel,serial,samples.size(),offset,stream.mix_rate,stream.stereo,samples.slice(offset,offset+12000),metadata)
  if offset%(12000*8)==0:await get_tree().process_frame
 _voice_send_finished(channel,serial,route)

func _voice_send_finished(channel: String,serial: int,route: Dictionary) -> void:
 if route.is_empty():return
 route.sending=maxi(0,int(route.get("sending",1))-1)
 if int(route.sending)==0 and int(speech_routes.get(_voice_key(channel,serial),{}).get("epoch",-1))==int(route.get("epoch",-2)):speech_routes.erase(_voice_key(channel,serial))

@rpc("authority","call_remote","reliable")
func _voice_cancel(channel: String,serial: int) -> void:
 pending_voice.erase(_voice_key(channel,serial));voice_transfer.cancel(channel,serial)
 if is_instance_valid(speech_player):speech_player.cancel_utterance(channel,serial)

@rpc("authority","call_remote","reliable")
func _voice_fallback(channel: String,serial: int) -> void:
 pending_voice.erase(_voice_key(channel,serial));voice_transfer.cancel(channel,serial)
 if is_instance_valid(speech_player):speech_player.fail_stream(channel,serial,"Speech unavailable; dialogue preserved.")

@rpc("authority","call_remote","reliable")
func _voice_chunk(channel: String,serial: int,total: int,offset: int,rate: int,stereo: bool,chunk: PackedByteArray,metadata: Dictionary={}) -> void:
 if not is_instance_valid(speech_player) or not speech_player.speech_enabled or not pending_voice.has(_voice_key(channel,serial)) or not speech_player.has_pending(channel,serial):return
 var received: Dictionary=voice_transfer.push(channel,serial,total,offset,rate,stereo,chunk,metadata)
 if not received.get("ok",false):
  if str(received.get("error","")) in ["digest mismatch","transfer capacity"]:_voice_fallback(channel,serial)
  return
 if received.get("complete",false):
  pending_voice.erase(_voice_key(channel,serial))
  speech_player.deliver_stream(channel,serial,received.stream)

# Shared natural-voice entry points. The host revalidates identity, class and hearing.
func _report_voice_stage(peer: int,context: Dictionary,stage: String,message: String="") -> void:
 if is_instance_valid(natural_voice):natural_voice.report_stage(peer,context,stage,message)

func _voice_context_valid(peer: int,context: Dictionary) -> bool:
 return context.is_empty() or (is_instance_valid(natural_voice) and natural_voice.is_current(peer,str(context.get("token",""))))

func _voice_model(target: Dictionary) -> Node3D:
 if not str(target.get("student","")).is_empty():return game.lecture_classes.classroom_students.models.get(str(target.get("class_id",""))+":"+str(target.student)) as Node3D
 if str(target.get("id",""))=="ms_lunch":return lunch
 return _model_for_room(str(target.get("room","")),str(target.get("id","")))

func _voice_visible(peer: int,model: Node3D) -> bool:
 if not is_instance_valid(model):return false
 var point: Vector3=game.lecture_classes._position(peer)
 if not point.is_finite():return false
 var query:=PhysicsRayQueryParameters3D.create(_voice_ear(peer),_voice_head(model),1)
 var excluded: Array[RID]=[]
 if is_instance_valid(game.player):excluded.append(game.player.get_rid())
 if model is CollisionObject3D:excluded.append(model.get_rid())
 for collider in model.find_children("*","CollisionObject3D",true,false):excluded.append(collider.get_rid())
 query.exclude=excluded
 return get_world_3d().direct_space_state.intersect_ray(query).is_empty()

func _voice_head(model: Node3D) -> Vector3:
 var head:=CharacterFace.head_for(model)
 return head.global_position if is_instance_valid(head) else model.global_position+Vector3.UP*1.4

func _voice_ear(peer: int) -> Vector3:
 if peer==multiplayer.get_unique_id() and is_instance_valid(game.player.eyes):return game.player.eyes.global_position
 var point: Vector3=game.lecture_classes._position(peer)
 var pose: Dictionary=game.session.poses.get(peer,{})
 return point+Vector3.UP*(1.16 if bool(pose.get("seated",false)) else 1.5)

func voice_candidates(peer: int) -> Array:
 var result: Array=[]
 if not game.session.roster.has(peer):return result
 var point: Vector3=game.lecture_classes._position(peer)
 if not point.is_finite():return result
 var room: String=game.campus.registry.locate(point)
 var activity:=_ai_activity(room)
 var teacher:=str(activity.get("teacher",""))
 var teacher_model:=_model_for_room(room,teacher) if Roster.has(teacher) else null
 if is_instance_valid(teacher_model):
  result.append({"id":teacher,"name":str(Roster.entry(teacher).name),"room":room,"class_id":str(activity.get("id","")),"student":"","position":_voice_head(teacher_model),"visible":_voice_visible(peer,teacher_model),"invited":_voice_invitation_valid(peer,{"room":room,"class_id":str(activity.get("id",""))})})
 if is_instance_valid(lunch) and lunch.visible and game.campus.registry.locate(lunch.global_position)==room:
  result.append({"id":"ms_lunch","name":"Ms Lunch","room":room,"class_id":"","student":"","position":_voice_head(lunch),"visible":_voice_visible(peer,lunch)})
 var students: Node=game.lecture_classes.classroom_students
 var class_id:=str(activity.get("id",""))
 for key in students.models:
  var model: Node3D=students.models[key]
  if not is_instance_valid(model) or not model.visible or not str(key).begins_with(class_id+":") or class_id.is_empty():continue
  var actor:=str(key).trim_prefix(class_id+":")
  var person:=Classmates.profile_for(actor)
  if person.is_empty() or point.distance_to(model.global_position)>7.:continue
  result.append({"id":actor,"name":str(person.name),"room":room,"class_id":class_id,"student":actor,"position":_voice_head(model),"visible":_voice_visible(peer,model)})
 return result

func voice_target_valid(peer: int,target: Dictionary) -> bool:
 if not game.session.roster.has(peer) or target.is_empty():return false
 if is_instance_valid(game.get("smartphones")):
  var phone: Node=game.smartphones.comm
  if multiplayer.is_server() and phone.calls.get(peer,{}).get("state","")=="active":return false
 var point: Vector3=game.lecture_classes._position(peer)
 if not point.is_finite() or game.campus.registry.locate(point)!=str(target.get("room","")):return false
 for candidate in voice_candidates(peer):
  if candidate.id==str(target.get("id","")) and candidate.class_id==str(target.get("class_id","")) and str(candidate.get("student",""))==str(target.get("student","")) and candidate.get("visible",false):
   var range_limit:=16.0 if bool(target.get("invited",false)) and _voice_invitation_valid(peer,target) else 7.0
   return _voice_ear(peer).distance_to(candidate.position)<=range_limit
 return false

func _voice_invitation_valid(peer: int,target: Dictionary) -> bool:
 var invitation: Dictionary=voice_invitations.get(peer,{})
 if int(invitation.get("until",0))>Time.get_ticks_msec() and str(invitation.get("room",""))==str(target.get("room","")) and str(invitation.get("class_id",""))==str(target.get("class_id","")):return true
 var room:=str(target.get("room",""))
 var call: Dictionary=class_calls.get(room,{})
 return not call.is_empty() and str(call.get("identity",""))==str(game.school.identities.get(peer,"")) and str(call.get("class_id",""))==str(target.get("class_id",""))

func _voice_channel(target: Dictionary) -> String:
 if not str(target.get("student","")).is_empty():return "classmate:"+str(target.student)
 return "npc:"+str(target.get("id","")) if str(target.get("class_id","")).is_empty() else str(target.get("room",""))

func attend_voice_target(peer: int,target: Dictionary) -> void:
 var point: Vector3=game.lecture_classes._position(peer)
 if not str(target.get("student","")).is_empty():game.lecture_classes.classroom_students.focus_on_player(str(target.class_id),str(target.student))
 else:_publish_attention(str(target.get("room","")),str(target.id),point)

func pause_voice_target(target: Dictionary) -> void:
 if is_instance_valid(speech_player):speech_player.pause_for_interruption(_voice_channel(target))
 if multiplayer.is_server() and game.session.online:
  for peer in _voice_recipients(str(target.get("room",""))):_voice_pause.rpc_id(peer,_voice_channel(target),true)

func resume_voice_target(target: Dictionary) -> void:
 resume_voice_channel(_voice_channel(target),str(target.get("room","")))

func resume_voice_channel(channel: String,room: String) -> void:
 if is_instance_valid(speech_player):speech_player.resume_suspended(channel)
 if multiplayer.is_server() and game.session.online:
  for peer in _voice_recipients(room):_voice_pause.rpc_id(peer,channel,false)

@rpc("authority","call_remote","reliable")
func _voice_pause(channel: String,pause: bool) -> void:
 if not is_instance_valid(speech_player):return
 if pause:speech_player.pause_for_interruption(channel)
 else:speech_player.resume_suspended(channel)

func any_voice_playing() -> bool:
 return is_instance_valid(speech_player) and not speech_player.active.is_empty()

func accept_voice_turn(peer: int,target: Dictionary,wav: PackedByteArray,context: Dictionary) -> void:
 if not multiplayer.is_server() or not voice_target_valid(peer,target) or not _voice_context_valid(peer,context):return
 if not str(target.get("student","")).is_empty():_classmate_question(peer,str(target.room),str(target.class_id),str(target.student),wav,context)
 elif str(target.get("id",""))=="ms_lunch":_answer_ambient_voice(peer,target,wav,context)
 else:_queue_question(peer,str(target.room),wav,str(target.id),str(target.class_id),context)

func _answer_ambient_voice(peer: int,target: Dictionary,wav: PackedByteArray,context: Dictionary) -> void:
 var epoch:=character_epoch
 var actor:=str(target.id)
 var deadline:=Time.get_ticks_msec()+120000
 while ai_busy.has(peer) or ai_busy.size()>=3 or actor in question_channels.values():
  if epoch!=character_epoch or not _voice_context_valid(peer,context) or Time.get_ticks_msec()>deadline:return
  await get_tree().create_timer(.05).timeout
 if epoch!=character_epoch or not _voice_context_valid(peer,context):return
 ai_busy[peer]="ambient";question_channels[peer]=actor
 var transcript: Dictionary=await game.host_openai.transcribe_wav(wav)
 if not transcript.get("ok",false) or not _voice_context_valid(peer,context) or epoch!=character_epoch:
  if not transcript.get("ok",false):_report_voice_stage(peer,context,"transcription_failed",str(transcript.get("error","Speech was not recognized.")))
  if _release_question(peer,epoch):resume_voice_target(target)
  return
 _report_voice_stage(peer,context,"transcription_received")
 var person:=Characters.teacher(actor)
 var activity:={"id":"","phase":"freeplay","teacher":actor,"room":str(target.room)}
 var identity:=str(game.school.identities.get(peer,""))
 var response:=await generate_character_exchange(person,identity,activity,str(transcript.get("text","")),{"observations":_character_observations(peer,_voice_model(target),activity),"_valid":func():return epoch==character_epoch and _voice_context_valid(peer,context)})
 if not _release_question(peer,epoch):return
 if not response.is_empty() and not response.get("cancelled",false) and _voice_context_valid(peer,context):
  _report_voice_stage(peer,context,"intentional_silence" if response.get("silent",false) else ("response_failed" if response.get("source","")=="technical_unavailable" else "response_generated"),str(response.get("technical_status","")))
  _present_ambient_speech(target,str(response.get("line","")),str(response.get("emotion","steady")),response.get("turn",{}).get("emotions",{}))
 resume_voice_target(target)

func invite_student_voice(peer: int,room: String,class_id: String,actor: String) -> void:
 if peer==multiplayer.get_unique_id():_student_voice_invitation(room,class_id,actor)
 elif game.session.online and game.session.peer_connected_now(peer):_student_voice_invitation.rpc_id(peer,room,class_id,actor)

@rpc("authority","call_remote","reliable")
func _student_voice_invitation(room: String,class_id: String,actor: String) -> void:
 _start_voice_conversation(room,true,actor,class_id)

func student_speech_pending(actor: String) -> bool:
 if not is_instance_valid(speech_player):return false
 var channel:="classmate:"+actor
 if speech_player.active.has(channel) or speech_player.presentations.has(channel) or speech_player.queued.has(channel) or speech_player.awaiting.has(channel) or speech_player.has_suspended(channel):return true
 for route in speech_routes.values():
  if str(route.get("actor",""))==actor:return true
 return false

func present_student_speech(room: String,class_id: String,actor: String,line: String,mood: String="steady",affect: Dictionary={},priority: int=0) -> void:
 if not multiplayer.is_server() or line.strip_edges().is_empty():return
 line=CharacterSpeech.complete(SpeechMath.display(line))
 var model: Node3D=game.lecture_classes.classroom_students.models.get(class_id+":"+actor)
 var person:=Classmates.profile_for(actor)
 if not is_instance_valid(model) or person.is_empty():return
 var channel:="classmate:"+actor
 var serial:=_next_speech(channel)
 var delivery:=Characters.speech(person,game.host_openai.tts_model,priority,mood,affect)
 var activity:=_ai_activity(room)
 if priority==0 and activity.get("phase","") in ["lesson","assignment"]:delivery.projection="whisper"
 var provider:=_uses_class_voice() and bool(delivery.get("ok",false))
 var peers:=_near_voice_recipients(room,model.global_position,5.0 if delivery.get("projection","")=="whisper" else 12.0)
 _student_speech(room,class_id,actor,line,mood,affect,priority,serial,provider,delivery.get("projection","normal"))
 for peer in peers:_student_speech.rpc_id(peer,room,class_id,actor,line,mood,affect,priority,serial,provider,delivery.get("projection","normal"))
 if provider:
  speech_routes[_voice_key(channel,serial)]=_new_speech_route(channel,serial,room,actor,peers,model,class_id,0,5.0 if delivery.get("projection","")=="whisper" else 12.0)
  _request_reaction_audio(channel,serial,actor,line,_provider_speech_key(actor,line,delivery),priority,delivery)

@rpc("authority","call_remote","reliable")
func _student_speech(room: String,class_id: String,actor: String,line: String,mood: String,affect: Dictionary,priority: int,serial: int,provider: bool,projection: String="normal") -> void:
 var model: Node3D=game.lecture_classes.classroom_students.models.get(class_id+":"+actor)
 var person:=Classmates.profile_for(actor)
 if not is_instance_valid(model) or person.is_empty():return
 var channel:="classmate:"+actor
 voice_channel_rooms[channel]=room
 speech_player.configure(bool(game.client_preferences.values.teacher_speech),bool(game.client_preferences.values.teacher_subtitles))
 if not speech_player.accept(channel,str(person.name),serial,line,priority,model,null,1.0,{"expect_audio":provider,"authoritative_audio":multiplayer.is_server(),"character_id":actor,"conversation_id":class_id,"delivery":{"projection":projection}}):return
 if provider:pending_voice[_voice_key(channel,serial)]={"serial":serial,"teacher":actor,"text":line,"priority":priority,"at":Time.get_ticks_msec(),"room":room}
 _character_gesture(channel,model,mood,false)
 reaction_pose[channel].speech_serial=serial;reaction_pose[channel].affect=affect;reaction_pose[channel].person_id=actor

func _near_voice_recipients(room: String,position: Vector3,max_range: float) -> Array[int]:
 var recipients: Array[int]=[]
 for peer in _voice_recipients(room):
  var point: Vector3=game.lecture_classes._position(peer)
  if point.is_finite() and point.distance_to(position)<=max_range:recipients.append(peer)
 return recipients

func _present_ambient_speech(target: Dictionary,line: String,mood: String,affect: Dictionary) -> void:
 line=CharacterSpeech.complete(SpeechMath.display(line))
 if line.is_empty():return
 if not is_instance_valid(_voice_model(target)):return
 var channel:=_voice_channel(target)
 var serial:=_next_speech(channel)
 var delivery:=Characters.speech(Characters.teacher(str(target.id)),game.host_openai.tts_model,3,mood,affect)
 var provider:=_uses_class_voice() and bool(delivery.get("ok",false))
 _ambient_speech(target,line,mood,affect,serial,provider)
 var model:=_voice_model(target)
 var peers:=_near_voice_recipients(str(target.room),model.global_position,12.0)
 for peer in peers:_ambient_speech.rpc_id(peer,target,line,mood,affect,serial,provider)
 if provider:
  speech_routes[_voice_key(channel,serial)]=_new_speech_route(channel,serial,str(target.room),str(target.id),peers,model,str(target.get("class_id","")),0,12.0)
  _request_reaction_audio(channel,serial,str(target.id),line,_provider_speech_key(str(target.id),line,delivery),3,delivery)

@rpc("authority","call_remote","reliable")
func _ambient_speech(target: Dictionary,line: String,mood: String,affect: Dictionary,serial: int,provider: bool) -> void:
 var model:=_voice_model(target)
 if not is_instance_valid(model):return
 var channel:=_voice_channel(target)
 speech_player.configure(bool(game.client_preferences.values.teacher_speech),bool(game.client_preferences.values.teacher_subtitles))
 if not speech_player.accept(channel,str(target.get("name","")),serial,line,3,model,null,1.0,{"expect_audio":provider,"authoritative_audio":multiplayer.is_server(),"character_id":str(target.id)}):return
 if provider:pending_voice[_voice_key(channel,serial)]={"serial":serial,"teacher":str(target.id),"text":line,"priority":3,"at":Time.get_ticks_msec(),"room":str(target.room)}
 _character_gesture(channel,model,mood,false)
 reaction_pose[channel].speech_serial=serial;reaction_pose[channel].affect=affect;reaction_pose[channel].person_id=str(target.id)

# Microphone turns use accept_voice_turn and the same character reasoning queue as typed text.
