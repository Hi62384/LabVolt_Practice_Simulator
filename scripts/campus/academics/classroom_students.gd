extends Node3D

const Profiles=preload("res://scripts/campus/academics/class_character_profile.gd")
const Toon=preload("res://scripts/toon_character.gd")
const Avatar=preload("res://scripts/avatar_model.gd")
const Social=preload("res://scripts/campus/academics/classmate_social.gd")
const Motion=preload("res://scripts/campus/academics/character_motion.gd")
const Behavior=preload("res://scripts/campus/academics/character_behavior.gd")
const Route=preload("res://scripts/campus/academics/classroom_teacher_route.gd")
const MAX_PER_CLASS:=6
const POOL_SIZE:=12
const RECORDS:="user://classmate_learning.cfg"
var game: Node
var models: Dictionary={}
var dialogue_focus: Dictionary={}
var learning: Dictionary={}
var records:=ConfigFile.new()

static func profile_for(id: String) -> Dictionary:
	var index:=id.trim_prefix("campus_student_")
	if not index.is_valid_int() or int(index) not in range(POOL_SIZE):return {}
	var profile:=Profiles.student(int(index))
	return profile if profile.id==id else {}

func nearby_member(peer: int,room: String,class_id: String,id: String) -> Dictionary:
	var activity: Dictionary=game.lecture_classes.classes.get(room,{})
	if activity.get("id","")!=class_id or not game.lecture_classes._inside(peer,room):return {}
	var member: Dictionary=activity.get("classmates",{}).get(id,{})
	if member.is_empty() or float(member.arrival)>game.lecture_classes._now():return {}
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
	var message:=question.to_lower()
	if "sorry" in message:return "It's okay. We can start over."
	if "thanks" in message:return "Anytime. Let me know how it goes."
	if "hobby" in message or "free time" in message or "interest" in message:
		return "I'm into %s. What about you?"%profile.interest
	if "remember" in message and not history.is_empty():
		return "Last time you said, “%s.” How did that go?"%str(history[-1].student).left(150)
	if phase=="assignment":return "I'm working on my own sheet right now. Let's compare notes after we hand it in."
	if "rematch" in message and int(relationship.get("competitions",0))>0:
		return "You're on. We were close last time. Let's see how the next quiz goes."
	if "study" in message:return "I'd be up for that. Let's compare what we wrote down after class."
	if message in ["hi","hello","hey","hello again"] and int(relationship.get("familiarity",0))>=2:
		if int(relationship.get("competitions",0))>=2:return "Hey! Our quiz scores keep ending up close. Ready for another round?"
		return "Hey, good to see my study partner again. How's class going?" if int(relationship.get("positive",0))>=2 else "Hey, good to see you again. How's class going?"
	if "help" in message or "formula" in message or "explain" in message:
		if proficiency(profile.id,course,profile.knowledge)<.60:return "I'm still working that out too. Want to ask the instructor together?"
		return "I start by writing the known values and their units. Which part are you stuck on?"
	if not stage.get("title","").is_empty():return "I'm trying to follow the part about %s. How's it going for you?"%str(stage.title).left(120)
	return "Hey! I'm %s. What are you working on today?"%str(profile.name).get_slice(" ",0)

func configure(owner: Node) -> void:
	game=owner
	if records.load(RECORDS)==OK:
		for id in records.get_sections():
			if not id.begins_with("campus_student_"):continue
			var scores: Dictionary={}
			for course in ["MTH147","MTH255","ETY155","ELM253","DGS266"]:
				var learned: Variant=records.get_value(id,course,0.)
				if learned is float and is_finite(learned):scores[course]=clampf(learned,0.,.35)
			learning[id]=scores

func start(activity: Dictionary,room: Dictionary,players: Array[Vector3],now: float) -> void:
	if not multiplayer.is_server():return
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
	var rotate:=rng.randi_range(0,POOL_SIZE-1)
	for index in count:
		var profile:=Profiles.student((rotate+index)%POOL_SIZE)
		var slot:=_social_seat(profile,classmates,options,rng)
		var seat: Vector3=options.pop_at(slot)
		var arrival:=now+rng.randf_range(0.,16.)
		classmates[profile.id]={"profile":profile,"seat":seat,"position":seat+Vector3(0,0,1.6),"arrival":arrival,
			"seated":false,"standing":practical,"has_seat":seat in seats,"arrived":false,"walking":false,"action":"arriving","next":arrival+7.,"turns":0}
	activity.classmates=classmates

func _social_seat(profile: Dictionary,classmates: Dictionary,options: Array,rng: RandomNumberGenerator) -> int:
	var index:=rng.randi_range(0,options.size()-1)
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
	_show_preclass_reply(activity,now)
	for member in activity.get("classmates",{}).values():
		var profile: Dictionary=member.profile
		if now<float(member.arrival):continue
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
		if now<float(member.next) or member.get("using_bench",false):continue
		member.erase("line")
		member.erase("look_at")
		if activity.phase=="assignment":
			_assessment_step(activity,member,now)
			continue
		var mood: String=game.faculty.character_mind.emotion(profile,Time.get_ticks_msec())
		if activity.phase=="lesson" and member.action=="listening" and float(profile.traits.attention_span)<.49:
			mood=game.faculty.character_mind.feel(profile,"idle",.35,Time.get_ticks_msec())
		member.mood=mood
		member.turns+=1
		member.action=Behavior.student_activity(profile,activity,member,mood)
		if member.action=="distracted":
			var seat: Vector3=member.seat
			member.look_at=seat+Vector3(1.8,1.1,0.9)
		elif member.action=="taking notes":
			member.look_at=member.position+Vector3(0,.75,-.55)
		member.next=now+5.+posmod(hash([profile.id,member.turns]),10)
	if activity.phase=="arrival":
		_before_class(activity,now)
		if not room.is_empty():_greet_nearby_player(activity,room,now)

func _greet_nearby_player(activity: Dictionary,room: String,now: float) -> void:
	if now<float(activity.get("player_greeting_next",0.)) or activity.has("classmate_reply") or float(activity.deadline)-now<5.:return
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
		candidate.line=profile.lines.greeting
		if int(connection.get("study_sessions",0))>=2:candidate.line="Hey. Want to compare notes again after class?"
		elif int(connection.positive)>=2:candidate.line="Hey, good to see you again."
		candidate.look_at=position
		candidate.action="chatting"
		candidate.next=now+4.
		candidate.gesture="wave" if float(profile.traits.expressiveness)>.62 else "nod"
		candidate.gesture_point=position
		candidate.gesture_until=now+2.2
		greeted[identity]=true
		activity.player_greeting_next=now+6.
		return

func act(room: String,activity: Dictionary,member: Dictionary,action: String,point: Vector3,now: float) -> bool:
	if not multiplayer.is_server() or activity.phase=="assignment" or member.get("using_bench",false) or not member.get("arrived",false):return false
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

func _step_walk(activity: Dictionary,member: Dictionary,now: float,delta: float) -> bool:
	var walk: Dictionary=member.walk
	var path: Array=walk.path
	var position: Vector3=member.position
	if activity.phase=="assignment":
		member.erase("walk")
		member.walking=false
		return false
	if int(walk.index)>=path.size():
		member.walking=false
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
	if not game.campus.registry.room_contains(walk.room,next) or not Route.clear_step(game,position,next):
		member.erase("walk")
		member.walking=false
		return false
	member.position=next
	member.walking=true
	member.look_at=target
	if next.is_equal_approx(target):
		walk.index+=1
		if not walk.returning:walk.visited.append(target)
	return true

func _before_class(activity: Dictionary,now: float) -> void:
	if activity.has("classmate_reply") or now<float(activity.get("social_next",0.)) or float(activity.deadline)-now<6.:return
	var actors: Array=activity.get("classmates",{}).values().filter(func(member):
		return (member.get("seated",false) or member.get("arrived",false)) and member.arrival<=now and not member.has("line") and not member.get("using_bench",false))
	var pairs: Dictionary=activity.get_or_add("social_pairs",{})
	var selected:=Social.choose(actors,game.faculty.brain,pairs)
	activity.social_next=now+5.
	if selected.is_empty():return
	var speaker: Dictionary=selected[0]
	var listener: Dictionary=selected[1]
	var exchange:=Social.exchange(speaker.profile,listener.profile,selected[2],selected[3],str(activity.get("title","")).left(70))
	speaker.line=exchange.line
	speaker.action="chatting"
	speaker.look_at=listener.position
	speaker.next=now+5.
	listener.action="listening"
	listener.look_at=speaker.position
	listener.next=now+5.
	pairs[Social.pair_key(speaker.profile.id,listener.profile.id)]=true
	activity.social_next=now+8.
	activity.classmate_reply={"speaker":speaker.profile.id,"listener":listener.profile.id,
		"greeting":exchange.line,"line":exchange.reply,"kind":exchange.kind,"at":now+2.3}

func _show_preclass_reply(activity: Dictionary,now: float) -> void:
	var reply: Dictionary=activity.get("classmate_reply",{})
	if reply.is_empty() or now<float(reply.at):return
	activity.erase("classmate_reply")
	if activity.phase!="arrival":return
	var actor: Dictionary=activity.classmates.get(reply.listener,{})
	if actor.is_empty() or not activity.classmates.has(reply.speaker):return
	actor.line=reply.line
	actor.action="chatting"
	actor.next=now+4.
	var brain: RefCounted=game.faculty.brain
	var stamp:=int(Time.get_unix_time_from_system())
	brain.remember_conversation(reply.speaker,reply.listener,reply.line,reply.greeting,stamp)
	brain.remember_conversation(reply.listener,reply.speaker,reply.greeting,reply.line,stamp)
	if reply.kind=="study":
		brain.remember(reply.speaker,reply.listener,"study",stamp)
		brain.remember(reply.listener,reply.speaker,"study",stamp)
	elif reply.kind=="decline" and float(activity.classmates[reply.speaker].profile.traits.criticism_sensitivity)>.5:
		brain.remember(reply.speaker,reply.listener,"disagreement",stamp)
	var affect_event: String={"study":"collaboration","rivalry":"rivalry","decline":"setback"}.get(reply.kind,"")
	if not affect_event.is_empty():
		var initiator: Dictionary=activity.classmates[reply.speaker]
		initiator.mood=game.faculty.character_mind.feel(initiator.profile,affect_event,.75,Time.get_ticks_msec())
		if reply.kind!="decline":actor.mood=game.faculty.character_mind.feel(actor.profile,affect_event,.75,Time.get_ticks_msec())

func proficiency(id: String,course: String,base: float) -> float:
	var affinity:=float(posmod(hash([id,course]),101))/1000.-.05
	return clampf(base+affinity+float(learning.get(id,{}).get(course,0.)),.1,.93)

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

func record_practice(id: String,course: String,correct: bool,week := 0) -> void:
	if not multiplayer.is_server() or not id.begins_with("campus_student_"):return
	var scores: Dictionary=learning.get_or_add(id,{})
	scores[course]=minf(.35,float(scores.get(course,0.))+(.015 if correct else .008))
	records.set_value(id,course,scores[course])
	if week>0:
		var key: String="%s.week.%d"%[course,week]
		var value:=clampf(float(records.get_value(id,key,0.)),0.,.25)
		records.set_value(id,key,minf(.25,value+(.025 if correct else .01)))
	_save_records()

func _save_records() -> void:
	if records.save(RECORDS+".tmp")==OK:DirAccess.rename_absolute(RECORDS+".tmp",RECORDS)

func begin_assessment(activity: Dictionary,now: float) -> void:
	for member in activity.get("classmates",{}).values():
		member.mood=game.faculty.character_mind.feel(member.profile,"workload",.85,Time.get_ticks_msec())
		member.action="working"
		member.next=now+9.+float(posmod(hash([activity.id,member.profile.id]),14))

func _assessment_step(activity: Dictionary,member: Dictionary,now: float) -> void:
	if member.get("submitted",false):return
	member.submitted=true
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
	records.set_value(id,"%s.last_score"%course,float(result.score))
	record_practice(id,course,float(result.score)>=60.,week)
	member.mood=game.faculty.character_mind.feel(member.profile,"success" if float(result.score)>=60. else "setback",.9,Time.get_ticks_msec())
	member.action="handed in work"
	member.next=now+60.

func snapshot(activity: Dictionary,now: float) -> Array:
	var result:=[]
	for member in activity.get("classmates",{}).values():
		if now<float(member.arrival):continue
		result.append({"id":member.profile.id,"name":member.profile.name,"position":member.position,
			"walking":member.walking,"seated":member.seated,"action":member.action,"line":member.get("line",""),
			"look_at":member.get("look_at",Vector3.INF),"class_id":activity.id,"mood":member.get("mood","steady"),
			"gesture":member.get("gesture",""),"gesture_point":member.get("gesture_point",Vector3.INF),
			"gesture_elapsed":clampf(2.2-(float(member.get("gesture_until",0.))-now),0.,2.2)})
	return result

func focus_on_player(class_id: String,actor: String) -> void:
	var key:=class_id+":"+actor
	if models.has(key):dialogue_focus[key]=Time.get_ticks_msec()+4500

func render(room: String,public: Dictionary,delta: float) -> void:
	var seen: Dictionary={}
	var now:=Time.get_ticks_msec()
	for member in public.get(room,{}).get("classmates",[]):
		var key:=str(member.class_id)+":"+str(member.id)
		seen[key]=true
		var model: Node3D=models.get(key)
		if not is_instance_valid(model):
			var config:=Toon.defaults()
			var index:=str(member.id).get_slice("_",2).to_int()
			config.name=member.name
			config.hair=["Sweep","Curls","Crop","Bun"][index%4]
			config.skin=["c78e64","54382e","f3cbb1","a86c49"][index/3%4]
			config.top=["405f64","597d7a","675b77","754d41","789129","385c84"][index%6]
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
			if pose.is_empty() and member.action=="raising hand":pose="raise_hand"
			var gesture_phase:=float(member.get("gesture_elapsed",0.))
			Motion.express(model,str(member.get("mood","steady")),delta,pose,gesture_phase,member.get("gesture_point",Vector3.INF))
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
