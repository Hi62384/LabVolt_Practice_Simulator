extends Node3D

const Profiles=preload("res://scripts/campus/academics/class_character_profile.gd")
const Toon=preload("res://scripts/toon_character.gd")
const Avatar=preload("res://scripts/avatar_model.gd")
const MAX_PER_CLASS:=6
const POOL_SIZE:=12
const RECORDS:="user://classmate_learning.cfg"
var game: Node
var models: Dictionary={}
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
	if "study" in message:return "I'd be up for that. Let's compare what we wrote down after class."
	if message in ["hi","hello","hey","hello again"] and int(relationship.get("familiarity",0))>=2:
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
		var slot:=rng.randi_range(0,options.size()-1)
		var seat: Vector3=options.pop_at(slot)
		var arrival:=now+rng.randf_range(0.,16.)
		classmates[profile.id]={"profile":profile,"seat":seat,"position":seat+Vector3(0,0,1.6),"arrival":arrival,
			"seated":false,"standing":practical,"arrived":false,"walking":false,"action":"arriving","next":arrival+7.,"turns":0}
	activity.classmates=classmates

func step(activity: Dictionary,now: float,delta: float) -> void:
	_show_preclass_reply(activity,now)
	for member in activity.get("classmates",{}).values():
		var profile: Dictionary=member.profile
		if now<float(member.arrival):continue
		if not member.get("arrived",member.seated):
			var position: Vector3=member.position
			member.position=position.move_toward(member.seat,delta*1.5)
			member.arrived=member.position.is_equal_approx(member.seat)
			member.seated=member.arrived and not member.get("standing",false)
			member.walking=not member.arrived
			member.action="listening" if member.arrived else "walking"
			continue
		if now<float(member.next) or member.get("using_bench",false):continue
		member.erase("line")
		if activity.phase=="assignment":
			_assessment_step(activity,member,now)
			continue
		var choices:=["listening","listening","taking notes","thinking"]
		if float(profile.confidence)*float(profile.curiosity)>.26:choices.append("raising hand")
		if float(profile.focus)<.45:choices.append("distracted")
		member.turns+=1
		var roll:=posmod(hash([profile.id,activity.id,member.turns]),choices.size())
		member.action=choices[roll]
		member.next=now+5.+posmod(hash([profile.id,member.turns]),10)
	if activity.phase=="arrival":_before_class(activity,now)

func _before_class(activity: Dictionary,now: float) -> void:
	if activity.get("classmate_chat",false) or float(activity.deadline)-now<6.:return
	var actors: Array=activity.get("classmates",{}).values().filter(func(member):
		return member.get("seated",false) and member.arrival<=now and not member.has("line"))
	for speaker in actors:
		if float(speaker.profile.talk)<.55:continue
		for listener in actors:
			if listener.profile.id==speaker.profile.id or (speaker.position as Vector3).distance_to(listener.position)>3.5:continue
			var brain: RefCounted=game.faculty.brain
			var met: Dictionary=brain.relationship(speaker.profile.id,listener.profile.id)
			var greeting: String
			var response: String
			if int(met.familiarity)>=2:
				greeting="Hey, %s. Want to compare notes again after class?"%listener.profile.name.get_slice(" ",0)
				response="Sure. I'll make a note of anything I want to go over."
			else:
				greeting="Hi, I'm %s. What made you take this class?"%speaker.profile.name.get_slice(" ",0)
				response="I'm %s. I wanted more practice with the basics."%listener.profile.name.get_slice(" ",0)
			speaker.line=greeting
			speaker.action="chatting"
			speaker.next=now+5.
			listener.action="listening"
			listener.next=now+5.
			activity.classmate_chat=true
			activity.classmate_reply={"speaker":speaker.profile.id,"listener":listener.profile.id,
				"greeting":greeting,"line":response,"at":now+2.3}
			return

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

func proficiency(id: String,course: String,base: float) -> float:
	var affinity:=float(posmod(hash([id,course]),101))/1000.-.05
	return clampf(base+affinity+float(learning.get(id,{}).get(course,0.)),.1,.93)

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
	member.action="handed in work"
	member.next=now+60.

func snapshot(activity: Dictionary,now: float) -> Array:
	var result:=[]
	for member in activity.get("classmates",{}).values():
		if now<float(member.arrival):continue
		result.append({"id":member.profile.id,"name":member.profile.name,"position":member.position,
			"walking":member.walking,"seated":member.seated,"action":member.action,"line":member.get("line",""),"class_id":activity.id})
	return result

func render(room: String,public: Dictionary,delta: float) -> void:
	var seen: Dictionary={}
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
		Avatar.animate(model,member.walking,member.seated)
		Avatar.raise_hand(model,member.action=="raising hand",delta)
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
