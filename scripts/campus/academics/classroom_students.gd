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
	var count:=rng.randi_range(0,mini(MAX_PER_CLASS,maxi(0,mini(options.size(),seats.size()-players.size()-1))))
	var classmates: Dictionary={}
	var rotate:=rng.randi_range(0,POOL_SIZE-1)
	for index in count:
		var profile:=Profiles.student((rotate+index)%POOL_SIZE)
		var slot:=rng.randi_range(0,options.size()-1)
		var seat: Vector3=options.pop_at(slot)
		var arrival:=now+rng.randf_range(0.,16.)
		classmates[profile.id]={"profile":profile,"seat":seat,"position":seat+Vector3(0,0,1.6),"arrival":arrival,
			"seated":false,"walking":false,"action":"arriving","next":arrival+7.,"turns":0}
	activity.classmates=classmates

func step(activity: Dictionary,now: float,delta: float) -> void:
	for member in activity.get("classmates",{}).values():
		var profile: Dictionary=member.profile
		if now<float(member.arrival):continue
		if not member.seated:
			var position: Vector3=member.position
			member.position=position.move_toward(member.seat,delta*1.5)
			member.seated=member.position.is_equal_approx(member.seat)
			member.walking=not member.seated
			member.action="listening" if member.seated else "walking"
			continue
		if now<float(member.next):continue
		var choices:=["listening","listening","taking notes","thinking"]
		if float(profile.confidence)*float(profile.curiosity)>.26:choices.append("raising hand")
		if float(profile.focus)<.45:choices.append("distracted")
		member.turns+=1
		var roll:=posmod(hash([profile.id,activity.id,member.turns]),choices.size())
		member.action="working" if activity.phase=="assignment" else choices[roll]
		member.next=now+5.+posmod(hash([profile.id,member.turns]),10)

func proficiency(id: String,course: String,base: float) -> float:
	return clampf(base+float(learning.get(id,{}).get(course,0.)),.1,.93)

func record_practice(id: String,course: String,correct: bool) -> void:
	if not multiplayer.is_server() or not id.begins_with("campus_student_"):return
	var scores: Dictionary=learning.get_or_add(id,{})
	scores[course]=minf(.35,float(scores.get(course,0.))+(.015 if correct else .008))
	records.set_value(id,course,scores[course])
	if records.save(RECORDS+".tmp")==OK:DirAccess.rename_absolute(RECORDS+".tmp",RECORDS)

func snapshot(activity: Dictionary,now: float) -> Array:
	var result:=[]
	for member in activity.get("classmates",{}).values():
		if now<float(member.arrival):continue
		result.append({"id":member.profile.id,"name":member.profile.name,"position":member.position,
			"walking":member.walking,"seated":member.seated,"action":member.action,"class_id":activity.id})
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
			var label:=Label3D.new()
			label.text=member.name
			label.position.y=1.97
			label.billboard=BaseMaterial3D.BILLBOARD_ENABLED
			label.pixel_size=.0025
			label.visibility_range_end=10.
			model.add_child(label)
		model.global_position=model.global_position.move_toward(member.position,delta*2.2)
		Avatar.animate(model,member.walking,member.seated)
		Avatar.raise_hand(model,member.action=="raising hand",delta)
	for key in models.keys():
		if seen.has(key):continue
		models[key].queue_free()
		models.erase(key)
