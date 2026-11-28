extends Node3D

const Profiles=preload("res://scripts/campus/academics/class_character_profile.gd")
const Toon=preload("res://scripts/toon_character.gd")
const Avatar=preload("res://scripts/avatar_model.gd")
const Social=preload("res://scripts/campus/academics/classmate_social.gd")
const Motion=preload("res://scripts/campus/academics/character_motion.gd")
const Behavior=preload("res://scripts/campus/academics/character_behavior.gd")
const Route=preload("res://scripts/campus/academics/classroom_teacher_route.gd")
const Population=preload("res://scripts/campus/academics/student_population.gd")
const Discipline=preload("res://scripts/campus/academics/classroom_discipline.gd")
const Memory=preload("res://scripts/campus/academics/character_memory.gd")
const DossierStore=preload("res://scripts/campus/academics/character_dossier_store.gd")
const MAX_PER_CLASS:=6
const RECORDS:="user://classmate_learning.cfg"
static var known_profiles: Dictionary={}
var game: Node
var models: Dictionary={}
var dialogue_focus: Dictionary={}
var learning: Dictionary={}
var records:=ConfigFile.new()
var population:=Population.new()
var social_next_global:=0.
var records_path:=RECORDS
var learning_save_error:=OK
var host_profile:=""

static func profile_for(id: String) -> Dictionary:
	if known_profiles.has(id):
		var profile: Dictionary=known_profiles[id]
		return DossierStore.project(profile) if not DossierStore.host_identity.is_empty() and profile.has("traits") else profile.duplicate(true)
	# Only a host-selected resident or an authenticated public snapshot exists
	# here. Evidence-based migration belongs to Population, never a UI lookup.
	return {}

func nearby_member(peer: int,room: String,class_id: String,id: String) -> Dictionary:
	var activity: Dictionary=game.lecture_classes.classes.get(room,{})
	if activity.get("id","")!=class_id or not game.lecture_classes._inside(peer,room):return {}
	var member: Dictionary=activity.get("classmates",{}).get(id,{})
	if member.is_empty() or member.get("removed_from_class",false) or member.get("leaving_class",false) or float(member.arrival)>game.lecture_classes._now():return {}
	var point: Vector3=game.lecture_classes._position(peer)
	if point.distance_to(member.position)>3.8:return {}
	return member

func visible_member(room: String,class_id: String,id: String) -> Dictionary:
	var activity: Dictionary=game.lecture_classes.public_classes.get(room,{})
	if activity.get("id","")!=class_id:return {}
	for member in activity.get("classmates",[]):
		if member.id==id:return member
	return {}

func dialogue(profile: Dictionary,course: String,stage: Dictionary,question: String,history: Array,phase: String,relationship: Dictionary={}) -> String:
	# Offline recovery only. The connected path always reasons with the full
	# character context, including during assessments.
	return Social.fallback_reply(profile,question,history,phase,relationship,str(stage.get("title","")))

func configure(owner: Node) -> void:
	game=owner
	known_profiles.clear()
	learning.clear()
	records.clear()
	host_profile=""
	records_path=""
	learning_save_error=OK
	if not multiplayer.is_server():return
	if not is_instance_valid(game):
		population.profile_blocked=true
		learning_save_error=ERR_INVALID_PARAMETER
		return
	var profile_id:=str(game.school.local_identity)
	var selected:=population.set_host_profile(profile_id)
	if selected!=OK:
		learning_save_error=selected
		push_warning("Student population profile could not be opened.")
		return
	population.load_population()
	if population.profile_blocked:
		learning_save_error=population.last_load_error
		return
	# A corrupt save can provide its own explicitly unsaved session population;
	# a failed host selection must never publish the previous owner's people.
	host_profile=profile_id
	records_path=Memory.profile_prefix(profile_id)+".learning.cfg"
	if not FileAccess.file_exists(records_path) and FileAccess.file_exists(RECORDS):
		var legacy:=ConfigFile.new()
		if legacy.load(RECORDS)==OK and Population.claim_legacy(profile_id):DirAccess.copy_absolute(RECORDS,records_path)
	for id in population.people:known_profiles[id]=population.profile_for(id)
	var loaded:=records.load(records_path)
	if loaded!=OK and records.load(records_path+".bak")==OK:
		loaded=OK
		_save_records()
	if loaded==OK:
		for id in records.get_sections():
			if not id.begins_with("campus_student_"):continue
			var scores: Dictionary={}
			for course in ["MTH147","MTH255","ETY155","ELM253","DGS266"]:
				var learned: Variant=records.get_value(id,course,0.)
				if learned is float and is_finite(learned):scores[course]=clampf(learned,0.,.35)
			learning[id]=scores

func start(activity: Dictionary,room: Dictionary,players: Array[Vector3],now: float) -> void:
	if not multiplayer.is_server():return
	if is_instance_valid(game) and host_profile!=str(game.school.local_identity):configure(game)
	var seats: Array=room.get("seats",[])
	var options:=seats.filter(func(seat: Vector3):
		return not players.any(func(player: Vector3):return seat.distance_to(player)<1.1))
	var rng:=RandomNumberGenerator.new()
	rng.seed=hash(activity.id)
	var practical: bool=activity.get("kind","")=="lab"
	if practical:
		for bench: Vector3 in room.get("benches",[]):
			var working_point:=bench+Vector3(0,0,1.45)
			if not players.any(func(point: Vector3):return working_point.distance_to(point)<1.4):options.append(working_point)
	var capacity:=mini(MAX_PER_CLASS,options.size() if practical else maxi(0,mini(options.size(),seats.size()-players.size()-1)))
	var count:=rng.randi_range(1 if practical and capacity>0 else 0,capacity)
	var classmates: Dictionary={}
	var occupied: Dictionary={}
	var active_classes: Dictionary=game.lecture_classes.classes if is_instance_valid(game) else {}
	for other in active_classes.values():
		if str(other.get("id",""))==str(activity.id):continue
		for id in other.get("classmates",{}):
			if not bool(other.classmates[id].get("removed_from_class",false)):occupied[id]=true
	for profile: Dictionary in population.available(occupied,count,hash(activity.id)):
		known_profiles[profile.id]=profile.duplicate(true)
		var slot:=_social_seat(profile,classmates,options,rng)
		var seat: Vector3=options.pop_at(slot)
		var arrival:=now+rng.randf_range(0.,16.)
		classmates[profile.id]={"profile":profile,"seat":seat,"position":seat+Vector3(0,0,1.6),"arrival":arrival,
			"seated":false,"standing":practical,"has_seat":seat in seats,"arrived":false,"walking":false,"action":"arriving","next":arrival+7.,"turns":0,
			"academic_due":0.,"social_source":"","behavior_started":arrival}
	activity.classmates=classmates

func _social_seat(profile: Dictionary,classmates: Dictionary,options: Array,rng: RandomNumberGenerator) -> int:
	var index:=rng.randi_range(0,options.size()-1)
	if not is_instance_valid(game):return index
	var brain: RefCounted=game.faculty.brain
	var affinity:=.2
	for other in classmates.values():
		var bond: Dictionary=brain.social_context(brain.relationship(profile.id,other.profile.id))
		if float(bond.friendship)<=affinity:continue
		affinity=float(bond.friendship)
		var distance:=INF
		for candidate in options.size():
			var gap: float=other.seat.distance_squared_to(options[candidate])
			if gap<distance:
				index=candidate
				distance=gap
	return index

func step(activity: Dictionary,now: float,delta: float,room := "") -> void:
	if not multiplayer.is_server():return
	_show_preclass_reply(activity,now)
	for member in activity.get("classmates",{}).values():
		var profile: Dictionary=member.profile
		if now<float(member.arrival) or member.get("removed_from_class",false):continue
		if member.has("walk") and _step_walk(activity,member,now,delta):continue
		if member.has("gesture") and now>=float(member.gesture_until):member.erase("gesture")
		if not member.get("arrived",member.seated):
			var position: Vector3=member.position
			member.position=position.move_toward(member.seat,delta*lerpf(1.15,2.0,float(profile.traits.energy)))
			member.arrived=member.position.is_equal_approx(member.seat)
			member.seated=member.arrived and not member.get("standing",false)
			member.walking=not member.arrived
			member.action="listening" if member.arrived else "walking"
			continue
		if activity.phase=="assignment" and not member.get("submitted",false) and now>=float(member.get("academic_due",INF)):
			_assessment_step(activity,member,now)
		if now<float(member.next) or member.get("using_bench",false):continue
		member.erase("line")
		member.erase("look_at")
		# Refresh only at the existing local decision cadence. Background expansion
		# does not rebuild a person or perform work every frame.
		var authoritative: Dictionary=population.profile_for(str(profile.id))
		if not authoritative.is_empty():
			profile=authoritative;member.profile=profile;known_profiles[profile.id]=profile
		var mood: String=game.faculty.character_mind.emotion(profile,Time.get_ticks_msec())
		if activity.phase=="lesson" and member.action=="listening" and float(profile.traits.attention_span)<.49:
			mood=game.faculty.character_mind.feel(profile,"idle",.35,Time.get_ticks_msec())
		member.mood=mood
		member.turns+=1
		member.action=Behavior.student_activity(profile,activity,member,mood)
		member.behavior_started=now
		if member.action=="asking for help":member.action="raising hand"
		if member.action=="using phone" and (now<float(member.get("items_away_until",0.)) or member.get("phone_in_custody",false)):member.action="listening"
		if activity.phase=="assignment":
			# These are body/attention choices only. The independent academic_due
			# above is the sole submission clock, even during sleep or a conversation.
			if member.action=="taking notes":member.action="studying" if member.get("submitted",false) else "working"
			elif member.action=="listening":member.action="waiting quietly" if member.get("submitted",false) else "reviewing work"
		if member.action=="distracted":
			var seat: Vector3=member.seat
			member.look_at=seat+Vector3(1.8,1.1,0.9)
		elif member.action in ["taking notes","working","reviewing work"]:
			member.look_at=member.position+Vector3(0,.75,-.55)
		elif member.action in ["using phone","studying"]:
			member.look_at=member.position+Vector3(0,1.0,-.35)
		elif member.action=="avoiding distraction":
			member.look_at=member.position+Vector3(-1.2,1.2,-.6)
		if not room.is_empty():_observe_student_behavior(room,activity,member,now)
		member.next=now+5.+posmod(hash([profile.id,member.turns]),10)
	if activity.phase in ["arrival","lesson","assignment","results"]:
		_before_class(activity,now,room)
		if not room.is_empty():_greet_nearby_player(activity,room,now)

func _greet_nearby_player(activity: Dictionary,room: String,now: float) -> void:
	if activity.phase not in ["arrival","results"] or activity.get("social_pending",false):return
	if now<social_next_global:return
	if now<float(activity.get("player_greeting_next",0.)) or activity.has("classmate_reply") or float(activity.get("deadline",INF))-now<5.:return
	if game.host_openai.busy or not game.faculty.ai_busy.is_empty() or not game.faculty.questions.is_empty():return
	activity.player_greeting_next=now+2.
	var greeted: Dictionary=activity.get_or_add("greeted_players",{})
	var room_classes: Node=game.lecture_classes
	for peer in game.session.roster:
		var identity:=str(game.school.identities.get(peer,""))
		if identity.is_empty() or greeted.has(identity) or not room_classes._inside(int(peer),room):continue
		var position: Vector3=room_classes._position(int(peer))
		var candidate: Dictionary={}
		var best:=0.55
		for member in activity.classmates.values():
			if not member.get("arrived",false) or member.has("line") or member.has("walk") or member.get("using_bench",false):continue
			var distance: float=member.position.distance_to(position)
			if distance>2.6:continue
			var bond: Dictionary=game.faculty.brain.relationship(member.profile.id,identity)
			if int(bond.get("resentment",0))>=2 or str(member.get("mood","steady")) in ["angry","irritated","anxious"]:continue
			var score: float=float(member.profile.traits.initiative)+minf(float(bond.familiarity)*.08,.24)-distance*.1
			if score<=best:continue
			candidate=member
			best=score
		if candidate.is_empty():continue
		var profile: Dictionary=candidate.profile
		var connection: Dictionary=game.faculty.brain.relationship(profile.id,identity)
		greeted[identity]=true
		activity.player_greeting_next=now+20.
		social_next_global=now+18.
		activity.social_pending=true
		_start_player_greeting(activity,candidate,int(peer),identity,position,room)
		return

func _start_player_greeting(activity: Dictionary,member: Dictionary,peer: int,identity: String,point: Vector3,room: String) -> void:
	var phase:=str(activity.phase)
	var response: Dictionary=await game.faculty.generate_character_exchange(member.profile,identity,activity,"",{
		"initiate":true,"intention":"Recognize this nearby person and decide whether to greet, reconnect, tease, or raise an unresolved issue from real memory.",
		"observations":{"interlocutor_visible":true,"phase":phase}})
	activity.social_pending=false
	if not _activity_current(activity,phase) or str(game.school.identities.get(peer,""))!=identity:return
	if not game.lecture_classes._inside(peer,room) or game.lecture_classes._position(peer).distance_to(member.position)>3.8:return
	var line:=str(response.get("line",""))
	if line.is_empty():return
	member.line=line
	member.look_at=point
	member.action="chatting"
	member.mood=str(response.get("emotion",member.get("mood","steady")))
	member.social_source=str(response.get("source","fallback"))
	member.next=game.lecture_classes._now()+_speech_seconds(line)
	member.gesture="wave" if float(member.profile.traits.expressiveness)>.62 else "nod"
	member.gesture_point=point
	member.gesture_until=game.lecture_classes._now()+2.2
	game.lecture_classes._publish()

func act(room: String,activity: Dictionary,member: Dictionary,action: String,point: Vector3,now: float) -> bool:
	if not multiplayer.is_server() or member.get("removed_from_class",false) or member.get("leaving_class",false) or member.get("using_bench",false) or not member.get("arrived",false):return false
	# A nod or glance during an assessment is harmless. Walking, changing seats
	# and demonstrations still require the host's discipline/activity systems.
	if activity.phase=="assignment" and action not in ["nod","wave","shrug","turn_away","defensive"]:return false
	if action in Motion.POSES:
		member.gesture=action
		member.gesture_point=point
		member.gesture_until=now+2.2
		if point.is_finite():member.look_at=point
		member.next=maxf(member.next,now+2.3)
		return true
	if action=="stand":
		member.seated=false
		member.standing=true
		return true
	var home: Vector3=member.seat
	if action=="sit":
		if not bool(member.get("has_seat",false)) or member.walking or member.position.distance_to(home)>.15:return false
		for peer in game.session.roster:
			var position: Vector3=game.lecture_classes._position(int(peer))
			if position.distance_to(home)<.55:return false
		member.seated=true
		member.standing=false
		return true
	if action!="approach" or not point.is_finite() or not game.campus.registry.room_contains(room,point) or member.has("walk"):return false
	var floor_target:=Vector3(point.x,float(member.position.y),point.z)
	var path:=Route.plan(game,room,member.position,floor_target,1.6)
	if path.is_empty() or path.back().distance_to(floor_target)>2.35:return false
	member.walk={"room":room,"path":path,"visited":[member.position],"index":0,"returning":false}
	member.seated=false
	member.walking=true
	member.action="walking"
	return true

func apply_discipline(room: String,activity: Dictionary,id: String,decision: Dictionary,now: float) -> bool:
	if not multiplayer.is_server():return false
	var member: Dictionary=activity.get("classmates",{}).get(id,{})
	if member.is_empty() or member.get("removed_from_class",false):return false
	var action:=str(decision.get("action",""))
	if action in ["ignore","look","remark","warning"]:
		if action!="ignore":
			member.look_at=game.faculty._teacher_position(room)
			member.action="listening"
			member.next=maxf(float(member.next),now+4.)
		return true
	if action in ["put_away","confiscate"]:
		member.action="listening"
		member.items_away_until=maxf(float(member.get("items_away_until",0.)),now+120.)
		if action=="confiscate":
			member.phone_in_custody=true
			member.item_custody={"kind":"phone","held_by":str(activity.get("teacher","")),"class_id":str(activity.id),"return":"class_end"}
		member.next=maxf(float(member.next),now+5.)
		return true
	if action=="stop_activity":
		# Lab equipment safety remains the lab authority's responsibility. This
		# stops only the NPC's independent action, never touches a circuit/grade.
		member.action="listening"
		member.next=maxf(float(member.next),now+10.)
		return true
	if action not in ["move","remove"] or member.get("using_bench",false):return false
	if action=="remove" and activity.phase=="assignment":return false
	var room_data: Dictionary=game.campus.registry.get_room(room)
	var target:=Vector3.INF
	if action=="move":
		var best:=0.5
		for seat: Vector3 in activity.get("room",{}).get("seats",[]):
			if activity.classmates.values().any(func(other):return other!=member and not other.get("removed_from_class",false) and ((other.seat as Vector3).distance_to(seat)<.7 or (other.get("walk",{}).get("target_seat",Vector3.INF) as Vector3).distance_to(seat)<.7)):continue
			if game.session.roster.keys().any(func(peer):return game.lecture_classes._position(int(peer)).distance_to(seat)<.8):continue
			var distance: float=member.position.distance_to(seat)
			if distance>best:
				best=distance
				target=seat
	else:
		var raw: Variant=room_data.get("door")
		if raw is Array and raw.size()==3:
			var door:=Vector3(float(raw[0]),float(raw[1]),float(raw[2]))
			var raw_anchor: Variant=room_data.get("anchor",raw)
			var anchor:=Vector3(float(raw_anchor[0]),float(raw_anchor[1]),float(raw_anchor[2]))
			target=door.move_toward(anchor,.85)
	if not target.is_finite():return false
	target.y=float(member.position.y)
	var seat_points: Array[Vector3]=[member.seat]
	if action=="move":seat_points.append(target)
	var ignored:=_vacant_chair_bodies(seat_points)
	var path:=Route.plan(game,room,member.position,target,.15,Callable(),ignored)
	if path.is_empty() or path.back().distance_to(target)>.9:return false
	if action=="move":
		if not Route.clear_step(game,path.back(),target,Callable(),ignored):return false
		path.append(target)
	member.walk={"room":room,"path":path,"visited":[member.position],"index":0,"returning":false,
		"purpose":action,"target":target,"target_seat":target if action=="move" else member.seat,"seat_points":seat_points}
	member.seated=false
	member.walking=true
	member.leaving_class=action=="remove"
	member.action="changing seats" if action=="move" else "leaving class"
	return true

func _vacant_chair_bodies(points: Array[Vector3]) -> Array[RID]:
	var ignored: Array[RID]=[]
	# A seated person's navigation capsule overlaps their own chair. Permit only
	# the authored start/destination chair while standing or sitting; never ignore
	# a wall, desk, another occupied chair or the room's general collision layer.
	for chair: Node3D in game.chairs:
		if not is_instance_valid(chair) or int(chair.occupant)!=0:continue
		if not points.any(func(point):return point.distance_to(chair.global_position)<.55):continue
		if chair is CollisionObject3D:ignored.append(chair.get_rid())
		for child in chair.get_children():
			if child is CollisionObject3D and str(child.get_meta("role",""))=="chair":ignored.append(child.get_rid())
	return ignored

func _observe_student_behavior(room: String,activity: Dictionary,member: Dictionary,now: float) -> void:
	if activity.phase not in ["lesson","assignment"] or member.get("removed_from_class",false):return
	var kind:="phone_use" if member.action=="using phone" else "voice_noise" if member.action in ["whispering","joking","arguing"] and not str(member.get("line","")).is_empty() else ""
	if kind.is_empty():return
	var teacher_id:=str(activity.get("teacher",""))
	var teacher:=Profiles.teacher(teacher_id)
	var model: Node3D=game.faculty._model_for_room(room,teacher_id)
	var origin: Vector3=game.faculty._teacher_position(room)
	if not origin.is_finite() or origin.distance_to(member.position)>10.:return
	var query:=PhysicsRayQueryParameters3D.create(origin+Vector3.UP*1.4,member.position+Vector3.UP*1.4,1)
	if is_instance_valid(game.player):query.exclude=[game.player.get_rid()]
	var blocked:=not get_world_3d().direct_space_state.intersect_ray(query).is_empty()
	var visibility: float=game.faculty.brain.visibility(origin,model.global_basis.z,member.position,blocked) if is_instance_valid(model) else 0.
	var noticed: float=visibility if kind=="phone_use" else game.faculty.brain.audibility(kind,origin.distance_to(member.position),blocked)
	if noticed<=0.:return
	var event_id:="%s:%s:%d:%s"%[activity.id,member.profile.id,int(member.turns),kind]
	var severity:=.35 if kind=="phone_use" else .55 if member.action=="arguing" else .25
	var records_by_actor: Dictionary=activity.get_or_add("discipline_records",{})
	var decision:=Discipline.consider(teacher,{"verified":true,"perceived":true,"kind":kind,"phase":activity.phase,
		"event_id":event_id,"severity":severity},records_by_actor.get(member.profile.id,{}),Time.get_ticks_msec())
	if decision.is_empty():return
	records_by_actor[member.profile.id]=decision.record
	var phase_label:="assessment" if activity.phase=="assignment" else "lesson"
	var description:="%s was visibly using a phone during the %s."%[member.profile.name,phase_label] if kind=="phone_use" else "%s interrupted the %s by speaking to another student."%[member.profile.name,phase_label]
	var bond: Dictionary=game.faculty.brain.relationship(teacher_id,str(member.profile.id))
	var turn: Dictionary=game.faculty.character_mind.observe(teacher,bond,description,Time.get_ticks_msec(),str(member.profile.id),"disruption",event_id,
		{"phase":str(activity.phase),"summary":description,"strength":severity})
	game.faculty.brain.remember_event(teacher,str(member.profile.id),turn,description,"",int(Time.get_unix_time_from_system()),event_id)
	var applied:=apply_discipline(room,activity,str(member.profile.id),decision,now)
	member.last_discipline={"action":decision.action,"reason":decision.reason,"executed":applied and decision.action not in ["move","remove"],"pending":applied and decision.action in ["move","remove"]}
	if decision.action in ["ignore","look"] or activity.get("discipline_pending",false):return
	if game.host_openai.busy or not game.faculty.ai_busy.is_empty():return
	activity.discipline_pending=true
	_student_discipline_line(room,activity,member,teacher,decision,applied,event_id,turn)

func _student_discipline_line(room: String,activity: Dictionary,member: Dictionary,teacher: Dictionary,decision: Dictionary,applied: bool,event_id: String,turn: Dictionary) -> void:
	var phase:=str(activity.phase)
	var response: Dictionary=await game.faculty.generate_character_exchange(teacher,str(member.profile.id),activity,"",{
		"initiate":true,"existing_event_id":event_id,"existing_turn":turn,"interlocutor":_social_identity(member.profile),"intention":"Address the behavior you actually observed using your own standards and temperament. Describe only a consequence that was executed. For movement in progress, give directions without claiming the student already arrived. If the action failed, give a verbal warning instead.",
		"discipline":{"kind":decision.kind,"action":decision.action,"reason":decision.reason,"executed":applied and decision.action not in ["move","remove"],"pending":applied and decision.action in ["move","remove"],"event_already_recorded":true}})
	activity.discipline_pending=false
	if not _activity_current(activity,phase):return
	var line:=str(response.get("line",""))
	if not line.is_empty():game.faculty.present_class_reaction(room,str(teacher.id),line,3)

func _step_walk(activity: Dictionary,member: Dictionary,now: float,delta: float) -> bool:
	var walk: Dictionary=member.walk
	var path: Array=walk.path
	var position: Vector3=member.position
	if activity.phase=="assignment" and str(walk.get("purpose",""))!="move":
		member.erase("walk")
		member.walking=false
		member.leaving_class=false
		return false
	if int(walk.index)>=path.size():
		member.walking=false
		if str(walk.get("purpose","")) in ["move","remove"]:
			if member.has("last_discipline"):
				member.last_discipline.executed=true
				member.last_discipline.pending=false
			if walk.purpose=="remove":
				member.removed_from_class=true
				member.leaving_class=false
				member.action="left class"
			else:
				member.seat=walk.target_seat
				member.has_seat=true
				member.standing=false
				member.seated=true
				member.action="listening"
			member.erase("walk")
			return true
		if bool(walk.returning):
			member.erase("walk")
			member.seated=bool(member.get("has_seat",false)) and not member.standing and position.distance_to(member.seat)<.15
			return false
		if not walk.has("wait_until"):walk.wait_until=now+2.
		if now<float(walk.wait_until):return true
		path=walk.visited.duplicate()
		path.reverse()
		walk.path=path
		walk.index=0
		walk.returning=true
	var target: Vector3=path[int(walk.index)]
	var next:=position.move_toward(target,delta*lerpf(.92,1.68,float(member.profile.traits.energy)))
	var ignored: Array[RID]=[]
	if walk.has("seat_points"):ignored=_vacant_chair_bodies(walk.seat_points)
	if not game.campus.registry.room_contains(walk.room,next) or not Route.clear_step(game,position,next,Callable(),ignored):
		member.erase("walk")
		member.walking=false
		member.leaving_class=false
		if str(walk.get("purpose","")) in ["move","remove"]:
			member.action="listening"
			if member.has("last_discipline"):
				member.last_discipline.executed=false
				member.last_discipline.pending=false
				member.last_discipline.reason="The path became blocked; the student remains in class."
		return false
	member.position=next
	member.walking=true
	member.look_at=target
	if next.is_equal_approx(target):
		walk.index+=1
		if not walk.returning:walk.visited.append(target)
	return true

func _before_class(activity: Dictionary,now: float,room: String="") -> void:
	if not is_instance_valid(game):return
	if now<social_next_global:return
	if activity.get("social_pending",false) or activity.has("classmate_reply") or now<float(activity.get("social_next",0.)) or float(activity.get("deadline",INF))-now<6.:return
	if game.host_openai.busy or not game.faculty.ai_busy.is_empty() or not game.faculty.questions.is_empty():return
	var lesson:=str(activity.phase)=="lesson"
	var assignment:=str(activity.phase)=="assignment"
	var interval:=60. if assignment else (40. if lesson else 18.)
	# Routine idling is local. Only occasional socially motivated decisions use
	# the provider, and each pair gets at most one exchange in a phase.
	if (lesson or assignment) and now<float(activity.get("last_social_at",-60.))+interval:return
	var actors: Array=activity.get("classmates",{}).values().filter(func(member):
		return (member.get("seated",false) or member.get("arrived",false)) and member.arrival<=now and not member.has("line") and not member.has("walk") and not member.get("using_bench",false) and not member.get("removed_from_class",false))
	if assignment:actors=actors.filter(func(member):return member.action!="sleeping")
	if (lesson or assignment) and not actors.any(func(member):return member.action in ["whispering","joking","arguing","helping classmate"]):return
	var pairs: Dictionary=activity.get_or_add("social_pairs",{})
	var selected:=Social.choose(actors,game.faculty.brain,pairs,str(activity.phase))
	activity.social_next=now+5.
	if selected.is_empty():return
	var speaker: Dictionary=selected[0]
	var listener: Dictionary=selected[1]
	pairs[Social.pair_key(speaker.profile.id,listener.profile.id)+":"+str(activity.phase)]=true
	activity.social_next=now+interval
	activity.last_social_at=now
	social_next_global=now+18.
	activity.social_pending=true
	_start_social_exchange(activity,speaker,listener,selected[2],selected[3],room)

func _start_social_exchange(activity: Dictionary,speaker: Dictionary,listener: Dictionary,history: Dictionary,reverse: Dictionary,room: String) -> void:
	var phase:=str(activity.phase)
	var topic:=str(activity.get("title",""))
	var purpose:=Social.intention(speaker.profile,listener.profile,history,reverse,phase,str(speaker.action))
	var opening: Dictionary=await game.faculty.generate_character_exchange(speaker.profile,str(listener.profile.id),activity,"",{
		"initiate":true,"defer_record":true,"intention":purpose.purpose,"interlocutor":_social_identity(listener.profile),"topic":topic,
		"observations":{"interlocutor_visible":true,"phase":phase}})
	if not _social_delivery_current(opening,activity,phase) or speaker.get("removed_from_class",false) or listener.get("removed_from_class",false):
		activity.social_pending=false
		return
	var line:=str(opening.get("line",""))
	if line.is_empty():
		game.faculty.character_interaction.record(opening,false)
		activity.social_pending=false
		return
	var now: float=game.lecture_classes._now()
	speaker.line=line
	speaker.action="whispering" if phase in ["lesson","assignment"] else "chatting"
	speaker.look_at=listener.position
	speaker.mood=str(opening.get("emotion",speaker.get("mood","steady")))
	speaker.social_source=str(opening.get("source","fallback"))
	speaker.behavior_started=now
	speaker.next=now+_speech_seconds(line)+3.
	listener.action="listening"
	listener.look_at=speaker.position
	listener.next=now+_speech_seconds(line)+3.
	game.lecture_classes._publish()
	game.faculty.character_interaction.record(opening,true)
	if not room.is_empty():_observe_student_behavior(room,activity,speaker,now)
	# The opening was heard now. Record that perception before generating a
	# delayed reply; a cancelled reply cannot erase the real incoming event.
	var response: Dictionary=await game.faculty.generate_character_exchange(listener.profile,str(speaker.profile.id),activity,line,{
		"record_incoming":true,"defer_record":true,
		"interlocutor":_social_identity(speaker.profile),"topic":topic,"observations":{"interlocutor_visible":true,"phase":phase}})
	activity.social_pending=false
	if not _social_delivery_current(response,activity,phase) or speaker.get("removed_from_class",false) or listener.get("removed_from_class",false):return
	activity.classmate_reply={"speaker":speaker.profile.id,"listener":listener.profile.id,"line":str(response.get("line","")),
		"kind":purpose.kind,"phase":phase,"emotion":str(response.get("emotion",listener.get("mood","steady"))),
		"source":str(response.get("source","fallback")),"at":maxf(game.lecture_classes._now(),now+_speech_seconds(line)),"room":room,"result":response}

func _show_preclass_reply(activity: Dictionary,now: float) -> void:
	var reply: Dictionary=activity.get("classmate_reply",{})
	if reply.is_empty() or now<float(reply.at):return
	activity.erase("classmate_reply")
	if activity.phase!=reply.get("phase","arrival"):return
	var response: Dictionary=reply.get("result",{})
	if not response.is_empty() and not _social_delivery_current(response,activity,str(reply.phase)):return
	var actor: Dictionary=activity.classmates.get(reply.listener,{})
	if actor.is_empty() or not activity.classmates.has(reply.speaker):return
	var initiator: Dictionary=activity.classmates[reply.speaker]
	if actor.get("removed_from_class",false) or initiator.get("removed_from_class",false):return
	actor.line=reply.line
	actor.action=("whispering" if activity.phase in ["lesson","assignment"] else "chatting") if not str(reply.line).is_empty() else "returning to work"
	actor.mood=str(reply.get("emotion",actor.get("mood","steady")))
	actor.social_source=str(reply.get("source","fallback"))
	actor.behavior_started=now
	actor.next=now+_speech_seconds(str(reply.line))
	# Complete the already-recorded incoming event only when the reply is shown.
	# This adds the actual speech/biography without reappraising the relationship.
	if not response.is_empty():game.faculty.character_interaction.record(response,not str(reply.line).is_empty())
	var room:=str(reply.get("room",""))
	if not room.is_empty():_observe_student_behavior(room,activity,actor,now)
	if not str(reply.line).is_empty():
		activity.social_pending=true
		_hear_social_reply(activity,initiator,actor,str(reply.line))

func _social_delivery_current(result: Dictionary,activity: Dictionary,phase: String) -> bool:
	if result.is_empty() or result.get("cancelled",false) or not _activity_current(activity,phase):return false
	return game.faculty.character_interaction._current(result.get("prepared",{}))

func _hear_social_reply(activity: Dictionary,listener: Dictionary,speaker: Dictionary,line: String) -> void:
	# The initiator hears the reply too. Appraise it once, without generating a
	# recursive conversation or assigning the listener someone else's emotion.
	await game.faculty.generate_character_exchange(listener.profile,str(speaker.profile.id),activity,line,{
		"listen_only":true,"interlocutor":_social_identity(speaker.profile),"observations":{"interlocutor_visible":true,"phase":str(activity.phase)}})
	activity.social_pending=false

func _activity_current(activity: Dictionary,phase: String) -> bool:
	for current in game.lecture_classes.classes.values():
		if str(current.get("id",""))==str(activity.get("id","")):return str(current.get("phase",""))==phase
	return false

static func _social_identity(person: Dictionary) -> Dictionary:
	return {"id":str(person.id),"name":str(person.name),"interest":str(person.get("interest","")),"program":str(person.get("program",""))}

static func _speech_seconds(line: String) -> float:
	return clampf(float(line.length())/15.,2.5,14.)

func proficiency(id: String,course: String,base: float) -> float:
	var affinity:=float(posmod(hash([id,course]),101))/1000.-.05
	return clampf(base+affinity+float(learning.get(id,{}).get(course,0.)),.1,.93)

func debug_snapshot() -> Dictionary:
	var classes: Dictionary={}
	if is_instance_valid(game):
		for room in game.lecture_classes.classes:
			var members: Array=[]
			for member in game.lecture_classes.classes[room].get("classmates",{}).values():
				members.append({"id":member.profile.id,"name":member.profile.name,"action":member.get("action",""),
					"mood":member.get("mood","steady"),"last_dialogue_source":member.get("social_source",""),
					"discipline":member.get("last_discipline",{}),"removed":member.get("removed_from_class",false),
					"item_custody":member.get("item_custody",{}),
					"academic_due":member.get("academic_due",0.),"submitted":member.get("submitted",false)})
			classes[room]=members
	return {"population":population.people.size(),"population_save_error":population.last_save_error,"population_blocked":population.profile_blocked,"population_persistence":population.diagnostics(),"learning_save_error":learning_save_error,
		"recovered_population_backup":population.recovered_backup,"classes":classes}

func record_quiz_rivals(activity: Dictionary,scores: Dictionary) -> void:
	var classmates: Dictionary=activity.get("classmates",{})
	var contenders: Array=scores.keys()
	contenders.sort()
	var observed: Dictionary={}
	var timestamp:=int(Time.get_unix_time_from_system())
	for actor in classmates:
		var points:=int(scores.get(actor,0))
		if points<=0:continue
		var opponent:=""
		var closest:=maxi(20,roundi(points*.18))
		for candidate in contenders:
			if candidate==actor or int(scores[candidate])<=0:continue
			var gap:=absi(points-int(scores[candidate]))
			if gap>closest or (gap==closest and not opponent.is_empty()):continue
			opponent=candidate
			closest=gap
		if opponent.is_empty():continue
		var pair: Array=[actor,opponent]
		pair.sort()
		var key: String=pair[0]+":"+pair[1]
		if observed.has(key):continue
		observed[key]=true
		game.faculty.brain.remember(actor,opponent,"competition",timestamp)
		classmates[actor].mood=game.faculty.character_mind.feel(classmates[actor].profile,"rivalry",.65,Time.get_ticks_msec())
		if classmates.has(opponent):
			game.faculty.brain.remember(opponent,actor,"competition",timestamp)
			classmates[opponent].mood=game.faculty.character_mind.feel(classmates[opponent].profile,"rivalry",.65,Time.get_ticks_msec())

func record_practice(id: String,course: String,correct: bool,week := 0,activity: Dictionary={},event_id: String="",kind: String="quiz",safe_lab: bool=false) -> void:
	if not multiplayer.is_server() or not id.begins_with("campus_student_"):return
	if host_profile.is_empty() or population.profile_blocked:return
	if is_instance_valid(game) and host_profile!=str(game.school.local_identity):return
	var member: Dictionary=activity.get("classmates",{}).get(id,{})
	var token:=""
	if not activity.is_empty():
		if member.is_empty() or event_id.is_empty() or str(activity.get("course",""))!=course or int(activity.get("week",0))!=week:return
		if not is_instance_valid(game) or game.faculty.brain.host_profile()!=host_profile:return
		token="activity:"+JSON.stringify([activity.get("id",""),event_id,id,kind]).sha256_text()
		# The same authoritative completion can be replayed after a delayed step;
		# neither learning gain nor directional memory should be awarded twice.
		if token in game.faculty.brain.processed_events.get(id+":"+id,[]):return
	var scores: Dictionary=learning.get_or_add(id,{})
	scores[course]=minf(.35,float(scores.get(course,0.))+(.015 if correct else .008))
	records.set_value(id,course,scores[course])
	if week>0:
		var key: String="%s.week.%d"%[course,week]
		var value:=clampf(float(records.get_value(id,key,0.)),0.,.25)
		records.set_value(id,key,minf(.25,value+(.025 if correct else .01)))
	_save_records()
	if not token.is_empty():
		var timestamp:=int(Time.get_unix_time_from_system())
		# A student knows their own actual result. Only the supervising teacher
		# gains an observation about them; unrelated classmates receive no marks.
		game.faculty.brain.remember_activity(member.profile,id,kind,course,correct,timestamp,token,week,safe_lab)
		var teacher_id:=str(activity.get("teacher",""))
		if not teacher_id.is_empty():
			var teacher:=Profiles.teacher(teacher_id)
			if not teacher.is_empty():game.faculty.brain.remember_activity(teacher,id,kind,course,correct,timestamp,token,week,safe_lab)

func _save_records() -> void:
	learning_save_error=records.save(records_path+".tmp")
	if learning_save_error!=OK:return
	var prior:=ConfigFile.new()
	if prior.load(records_path)==OK:
		learning_save_error=DirAccess.copy_absolute(records_path,records_path+".bak")
		if learning_save_error!=OK:return
	learning_save_error=DirAccess.rename_absolute(records_path+".tmp",records_path)

func begin_assessment(activity: Dictionary,now: float) -> void:
	for member in activity.get("classmates",{}).values():
		if member.get("removed_from_class",false):continue
		member.mood=game.faculty.character_mind.feel(member.profile,"workload",.85,Time.get_ticks_msec())
		member.action="working"
		member.academic_due=now+9.+float(posmod(hash([activity.id,member.profile.id]),14))
		member.next=now+3.+float(posmod(hash([activity.id,member.profile.id,"assessment_body"]),4))
		member.behavior_started=now

func _assessment_step(activity: Dictionary,member: Dictionary,now: float) -> void:
	if member.get("submitted",false):return
	var project: Dictionary=activity.get("classmate_assessment",{})
	if project.is_empty():return
	var id: String=member.profile.id
	var course: String=activity.course
	var week: int=activity.week
	var concept_gain:=clampf(float(records.get_value(id,"%s.week.%d"%[course,week],0.)),0.,.25)
	var skill:=clampf(proficiency(id,course,member.profile.knowledge)+concept_gain,.1,.96)
	var rng:=RandomNumberGenerator.new()
	rng.seed=hash([activity.id,id])
	var answers: Dictionary={}
	for index in project.get("questions",[]).size():
		var question: Dictionary=project.questions[index]
		var expected: Variant=question.get("answer","")
		var confident:=rng.randf()<skill
		var key:=str(question.get("id",index)) if course.begins_with("MTH") else str(index)
		var options: Array=question.get("options",[])
		if confident and not str(expected).is_empty():
			answers[key]=expected if course.begins_with("MTH") else str(expected)
		elif options.size()>1:
			answers[key]=str((int(expected)+rng.randi_range(1,options.size()-1))%options.size())
		elif expected is float or expected is int:
			answers[key]=str(float(expected)*[.10,.90,1.25,10.][rng.randi_range(0,3)])
	var result: Dictionary=game.school.course_bridge.grade(project,answers)
	if not result.has("score"):return
	member.submitted=true
	records.set_value(id,"%s.last_score"%course,float(result.score))
	record_practice(id,course,float(result.score)>=60.,week,activity,"assessment_submission","assessment")
	member.mood=game.faculty.character_mind.feel(member.profile,"success" if float(result.score)>=60. else "setback",.9,Time.get_ticks_msec())
	member.action="handed in work"
	member.next=now+60.

func snapshot(activity: Dictionary,now: float) -> Array:
	var result:=[]
	for member in activity.get("classmates",{}).values():
		if now<float(member.arrival) or member.get("removed_from_class",false):continue
		var affect: Dictionary=game.faculty.character_mind.context(member.profile,Time.get_ticks_msec()) if is_instance_valid(game) else {}
		result.append({"id":member.profile.id,"name":member.profile.name,"position":member.position,
			"walking":member.walking,"seated":member.seated,"action":member.action,"line":member.get("line",""),
			"look_at":member.get("look_at",Vector3.INF),"class_id":activity.id,"mood":affect.get("emotion",member.get("mood","steady")),"emotions":affect.get("emotions",{}),
			"public_profile":_public_profile(member.profile),"appearance":member.profile.get("appearance",{}),
			"behavior_elapsed":clampf(now-float(member.get("behavior_started",now)),0.,120.),
			"gesture":member.get("gesture",""),"gesture_point":member.get("gesture_point",Vector3.INF),
			"gesture_elapsed":clampf(2.2-(float(member.get("gesture_until",0.))-now),0.,2.2)})
	return result

static func _public_profile(person: Dictionary) -> Dictionary:
	var traits: Dictionary={}
	for key in ["speaking_pace","expressiveness","energy","shyness","confidence","arrogance"]:
		traits[key]=clampf(float(person.traits.get(key,.5)),0.,1.)
	var voice: Dictionary={}
	for key in ["identifier","profile","characteristics","delivery"]:
		if person.get("voice",{}).has(key):voice[key]=person.voice[key]
	return {"id":str(person.id),"name":str(person.name),"role":"student","identity_scope":"public","style":str(person.get("style","")),
		"talk":float(person.get("talk",.5)),"voice_slot":int(person.get("voice_slot",0)),"voice":voice,"traits":traits}

func focus_on_player(class_id: String,actor: String) -> void:
	var key:=class_id+":"+actor
	if models.has(key):dialogue_focus[key]=Time.get_ticks_msec()+4500

func render(room: String,public: Dictionary,delta: float) -> void:
	var seen: Dictionary={}
	var now:=Time.get_ticks_msec()
	for member in public.get(room,{}).get("classmates",[]):
		if not multiplayer.is_server() and member.get("public_profile") is Dictionary:
			var presented: Dictionary=member.public_profile
			if str(presented.get("id",""))==str(member.id):
				known_profiles[member.id]=presented.duplicate(true)
				# Older hosts may omit the marker. Receiving an authenticated public
				# snapshot still cannot authorize hydration from local private saves.
				known_profiles[member.id].identity_scope="public"
		var key:=str(member.class_id)+":"+str(member.id)
		seen[key]=true
		var model: Node3D=models.get(key)
		if not is_instance_valid(model):
			var config:=Toon.sanitize(member.get("appearance",{}))
			var index:=str(member.id).get_slice("_",2).to_int()
			config.name=member.name
			if member.get("appearance",{}).is_empty():config=Population._appearance(index)
			model=Toon.build(config)
			model.set_meta("character_outfit",game.faculty._outfit_color(Color.html(str(config.top)))+" "+str(config.outfit))
			model.rotation.y=PI
			add_child(model)
			model.global_position=member.position
			models[key]=model
			var target:=StaticBody3D.new()
			target.collision_layer=4
			target.collision_mask=0
			target.set_meta("role","classroom_student")
			target.set_meta("room",room)
			target.set_meta("class_id",member.class_id)
			target.set_meta("student_id",member.id)
			target.set_meta("label",member.name)
			var collider:=CollisionShape3D.new()
			var shape:=CapsuleShape3D.new()
			shape.radius=.26
			shape.height=.9
			collider.shape=shape
			collider.position.y=.95
			target.add_child(collider)
			model.add_child(target)
			var label:=Label3D.new()
			label.name="StudentName"
			label.text=member.name
			label.position.y=1.97
			label.billboard=BaseMaterial3D.BILLBOARD_ENABLED
			label.pixel_size=.0025
			label.visibility_range_end=10.
			label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
			label.width=420.
			model.add_child(label)
		model.global_position=model.global_position.move_toward(member.position,delta*2.2)
		var target: Vector3=member.get("look_at",Vector3.INF)
		if member.action=="returning to work":dialogue_focus.erase(key)
		elif member.get("gesture","")!="point" and now<int(dialogue_focus.get(key,0)):target=game.player.global_position
		var direction:=target-model.global_position
		var facing:=PI
		if direction.is_finite() and Vector2(direction.x,direction.z).length_squared()>.01:
			facing=atan2(direction.x,direction.z)
		model.rotation.y=lerp_angle(model.rotation.y,facing,1.-exp(-delta*9.))
		Avatar.animate(model,member.walking,member.seated)
		if now>=int(model.get_meta("conversation_hand_until",0)):
			var pose:=str(member.get("gesture",""))
			if pose.is_empty():pose=_activity_pose(str(member.action))
			var gesture_phase:=float(member.get("gesture_elapsed",0.))
			if str(member.get("gesture","")).is_empty():gesture_phase=float(member.get("behavior_elapsed",0.))
			Motion.express(model,str(member.get("mood","steady")),delta,pose,gesture_phase,member.get("gesture_point",Vector3.INF),
				member.get("emotions",{}),member.get("public_profile",{}).get("traits",{}))
		_render_activity_items(model,str(member.action))
		var label:=model.get_node_or_null("StudentName") as Label3D
		if label!=null:
			var line: String=member.get("line","")
			if line.is_empty() and member.action in ["wiring circuit","checking instruments","reading meter","reading scope","placing breadboard","powering breadboard","setting logic inputs","checking circuit behavior","recorded measurement","discussing group work"]:
				line=str(member.action).capitalize()
			label.text=member.name+("\n"+line if not line.is_empty() else "")
	for key in models.keys():
		if seen.has(key):continue
		models[key].queue_free()
		models.erase(key)
		dialogue_focus.erase(key)

static func _activity_pose(action: String) -> String:
	return str({"raising hand":"raise_hand","asking for help":"raise_hand","using phone":"phone","taking notes":"write",
		"studying":"think","thinking":"think","working":"write","reviewing work":"think","sleeping":"sleep","whispering":"whisper",
		"joking":"whisper","arguing":"argue","helping classmate":"point","celebrating":"celebrate","avoiding distraction":"turn_away"}.get(action,""))

static func _render_activity_items(model: Node3D,action: String) -> void:
	var arm:=model.get_node_or_null("Body/ArmR") as Node3D
	if not is_instance_valid(arm):return
	var phone:=arm.get_node_or_null("StudentPhone") as MeshInstance3D
	if not is_instance_valid(phone):
		phone=MeshInstance3D.new()
		phone.name="StudentPhone"
		var body:=BoxMesh.new()
		body.size=Vector3(.078,.14,.018)
		phone.mesh=body
		phone.material_override=Toon.material("242834")
		phone.position=Vector3(0,-.49,.058)
		arm.add_child(phone)
		var screen:=MeshInstance3D.new()
		var face:=BoxMesh.new()
		face.size=Vector3(.065,.115,.002)
		screen.mesh=face
		screen.material_override=Toon.material("6e99b0")
		screen.position.z=.011
		phone.add_child(screen)
	phone.visible=action=="using phone"
	var notebook:=model.get_node_or_null("StudentNotebook") as MeshInstance3D
	if not is_instance_valid(notebook):
		notebook=MeshInstance3D.new()
		notebook.name="StudentNotebook"
		var pages:=BoxMesh.new()
		pages.size=Vector3(.24,.018,.3)
		notebook.mesh=pages
		notebook.material_override=Toon.material("e3e1d8")
		notebook.position=Vector3(0,.78,.18)
		model.add_child(notebook)
	notebook.visible=action in ["taking notes","studying","working","reviewing work"]
