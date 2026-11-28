extends SceneTree
## Production state transitions with explicit decision fixtures; no live AI.
const Mind=preload("res://scripts/campus/academics/character_mind.gd")
const Brain=preload("res://scripts/campus/academics/teacher_brain.gd")
const Profiles=preload("res://scripts/campus/academics/class_character_profile.gd")
var checks:=0
var failures: Array[String]=[]
func check(value: bool,label: String) -> void:
	checks+=1
	if not value:failures.append(label);push_error(label)
func _initialize() -> void:
	var mind:=Mind.new();var brain:=Brain.new();brain.bind_mind(mind)
	var person:=Profiles.teacher("ms_bird_heart").duplicate(true)
	# Controlled independent values use the actual dossier trait schema. The
	# separate authored Brian case below must work without any injected trait.
	person.traits.grudges=.8;person.traits.forgiveness=.8
	var brian:=Profiles.teacher("brian")
	for i in 3:mind.observe(brian,{},"You are useless.",Time.get_ticks_msec(),"canonical-listener","insult","canonical-insult-"+str(i),{"event":"insult","severity":.9,"behavior":{"mode":"permanent_silence"}})
	check(mind.disengagement(brian.id,"canonical-listener").disengagement=="permanent","an unchanged authored teacher uses the canonical grudges trait to maintain a serious boundary")
	var listener:="fixture-student"
	for i in 3:
		var turn:=mind.observe(person,brain.relationship(person.id,listener),"You are useless.",Time.get_ticks_msec(),listener,"insult","insult-"+str(i),{"event":"insult","severity":.9,"behavior":{"mode":"permanent_silence"}})
		brain.remember_event(person,listener,turn,"You are useless.","",int(Time.get_unix_time_from_system()),str(turn.event_id))
	check(mind.disengagement(person.id,listener).disengagement=="permanent","grounded permanent disengagement is established")
	var before:=int(Time.get_unix_time_from_system())-100
	mind.disengagements[person.id+":"+listener].since=before
	var apology:=mind.observe(person,brain.relationship(person.id,listener),"I'm sorry.",Time.get_ticks_msec()+86400000,listener,"apology","apology",{"event":"apology","sincere":true,"topic_changed":true,"important":true})
	check(apology.quiet and mind.disengagement(person.id,listener).disengagement=="permanent","time, topic change, claimed importance and apology do not clear the boundary")
	check(mind.reconsideration_evidence(person,listener,brain.relationship(person.id,listener)).is_empty(),"ordinary conversation cannot manufacture eligibility")
	for i in 3:brain.remember_activity(person,listener,"quiz","ELM253",true,before+10+i,"verified-success-"+str(i),1)
	var evidence:=mind.reconsideration_evidence(person,listener,brain.relationship(person.id,listener))
	check(evidence.size()==3,"new distinct verified experiences permit a deliberate review")
	var decline:=mind.observe(person,brain.relationship(person.id,listener),"Hello",Time.get_ticks_msec(),listener,"chat","decline",{"reconsideration_allowed":true,"behavior":{"mode":"engage"}})
	check(decline.quiet and mind.disengagement(person.id,listener).disengagement=="permanent","eligibility itself never forces forgiveness")
	var reopened:=mind.observe(person,brain.relationship(person.id,listener),"Hello",Time.get_ticks_msec(),listener,"chat","reopen",{"reconsideration_allowed":true,"behavior":{"mode":"reengage"}})
	check(reopened.reopen_requested and not reopened.quiet and mind.disengagement(person.id,listener).disengagement=="permanent","a proposed reconsideration remains uncommitted before speech validation")
	mind.commit_delivery(person,listener,reopened,true)
	check(mind.disengagement(person.id,listener).disengagement.is_empty(),"delivered validated decision can reopen this relationship")
	var hostile:=mind.observe(person,brain.relationship(person.id,listener),"Another insult",Time.get_ticks_msec(),listener,"insult","new-conflict",{"severity":1.,"behavior":{"mode":"permanent_silence"}})
	check(hostile.quiet and mind.disengagement(person.id,listener).disengagement=="permanent","later verified conflict can establish a new boundary")
	mind.commit_delivery(person,listener,reopened,true)
	check(mind.disengagement(person.id,listener).disengagement=="permanent","retrying an old delivered decision cannot erase a newer boundary")
	var compulsory:=mind.observe(person,brain.relationship(person.id,listener),"Lab hazard",Time.get_ticks_msec(),listener,"hazard","hazard",{"official_communication":true})
	check(not compulsory.quiet and mind.disengagement(person.id,listener).disengagement=="permanent","required safety communication is independent of optional social willingness")
	print("CHARACTER_RELATIONSHIP_DECISIONS ","PASS" if failures.is_empty() else "FAIL"," checks=",checks," source=host state and decision fixtures, not live AI")
	quit(0 if failures.is_empty() else 1)
