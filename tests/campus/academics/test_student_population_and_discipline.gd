extends SceneTree
const Population=preload("res://scripts/campus/academics/student_population.gd")
const Profiles=preload("res://scripts/campus/academics/class_character_profile.gd")
const Discipline=preload("res://scripts/campus/academics/classroom_discipline.gd")
const Social=preload("res://scripts/campus/academics/classmate_social.gd")
var failures: Array[String]=[]

func check(ok: bool,message: String) -> void:
	if not ok:failures.append(message)

func _initialize() -> void:
	var roster:=Population.new()
	roster.path="user://student-population-test.json"
	for suffix in ["",".bak",".tmp"]:
		if FileAccess.file_exists(roster.path+suffix):DirAccess.remove_absolute(roster.path+suffix)
	roster.load_population()
	check(roster.people.size()==Population.INITIAL_COUNT,"initial population expands beyond 12")
	for index in 12:
		var id:="campus_student_%02d"%index
		check(roster.profile_for(id).name==Profiles.student(index).name,"legacy student identity preserved")
	var excluded: Dictionary={}
	for person in roster.available({},6,13):excluded[person.id]=true
	var second:=roster.available(excluded,6,14)
	check(second.size()==6 and second.all(func(person):return not excluded.has(person.id)),"overlapping rooms cannot select the same student")
	for person in second:excluded[person.id]=true
	for id in roster.people:excluded[id]=true
	var expanded:=roster.available(excluded,6,15)
	check(expanded.size()==6 and roster.people.size()==Population.INITIAL_COUNT+6,"exhausted campus pool grows without classroom crowding")
	var person: Dictionary=roster.people[expanded[0].id]
	person.biography.saved_detail="I repaired my grandfather's radio last winter."
	person.traits.confidence=.91
	person.traits.shyness=.87
	roster.dirty=true
	check(roster.save_population()==OK,"population atomic save")
	check(roster.save_population()==OK,"population backup refresh")
	var loaded:=Population.new()
	loaded.path=roster.path
	check(loaded.load_population(),"population reload")
	var copy:=loaded.profile_for(person.id)
	check(copy.biography.saved_detail==person.biography.saved_detail and is_equal_approx(copy.traits.shyness,.87) and is_equal_approx(copy.traits.confidence,.91),"saved biography and unusual trait combination do not reroll")
	check(JSON.stringify(copy.appearance)==JSON.stringify(person.appearance),"saved appearance survives restart")
	copy.traits.confidence=.1
	check(is_equal_approx(loaded.profile_for(person.id).traits.confidence,.91),"callers cannot mutate the persistent roster accidentally")
	var broken:=FileAccess.open(roster.path,FileAccess.WRITE)
	broken.store_string("{truncated")
	broken.close()
	var recovered:=Population.new()
	recovered.path=roster.path
	check(recovered.load_population() and recovered.recovered_backup,"corruption recovers verified backup")
	check(recovered.profile_for(person.id).biography.saved_detail==person.biography.saved_detail,"backup restores individual history")
	var isolated:=Population.new()
	check(isolated.set_host_profile("population-host-alpha")==OK,"host namespace selection")
	isolated.load_population()
	isolated.people.campus_student_00.biography.host_private_fact="Only the first host learned this story."
	isolated.dirty=true
	check(isolated.save_population()==OK,"first host population saves")
	check(isolated.set_host_profile("population-host-beta")==OK,"second host namespace selection")
	isolated.load_population()
	check(not isolated.people.campus_student_00.biography.has("host_private_fact"),"host profiles cannot see another host's invented biography")
	check(isolated.set_host_profile("population-host-alpha")==OK,"return to first host")
	isolated.load_population()
	check(isolated.people.campus_student_00.biography.get("host_private_fact","")=="Only the first host learned this story.","switching hosts retains the correct campus population")
	var strict:=Profiles.teacher("mr_stone")
	var tired:=Profiles.teacher("stanley")
	var evidence:={"verified":true,"perceived":true,"kind":"voice_noise","phase":"lesson","severity":.7,"event_id":"incident-0"}
	check(Discipline.consider(strict,{"verified":false,"perceived":true}).is_empty(),"no discipline from unverified claims")
	var strict_record: Dictionary={}
	var tired_record: Dictionary={}
	var strict_actions: Array=[]
	var tired_actions: Array=[]
	for index in 10:
		evidence.event_id="incident-%d"%index
		var a:=Discipline.consider(strict,evidence,strict_record,index*10000)
		var b:=Discipline.consider(tired,evidence,tired_record,index*10000)
		strict_record=a.record
		tired_record=b.record
		strict_actions.append(a.action)
		tired_actions.append(b.action)
		check(Discipline.consider(strict,evidence,strict_record,index*10000).is_empty(),"same incident cannot apply twice")
	check(strict_actions!=tired_actions,"disciplinary escalation depends on the teacher")
	check("warning" in strict_actions and "remove" in strict_actions,"repeated evidenced disruption can lead to removal after warnings")
	evidence.phase="assignment"
	evidence.event_id="assessment-incident"
	check(Discipline.consider(strict,evidence,strict_record,120000).action=="move","assessment discipline preserves access to unfinished work")
	evidence.kind="lab_hazard"
	evidence.event_id="safety-incident"
	check(Discipline.consider(tired,evidence,{},0).action=="stop_activity","safety intervention does not depend on caring personality")
	var phone_record: Dictionary={}
	var phone_actions: Array=[]
	for index in 5:
		var phone:=Discipline.consider(strict,{"verified":true,"perceived":true,"kind":"phone_use","phase":"lesson","severity":.4,"event_id":"phone-%d"%index},phone_record,index*10000)
		phone_record=phone.record
		phone_actions.append(phone.action)
	check("put_away" in phone_actions and "confiscate" in phone_actions and phone_actions.find("confiscate")>phone_actions.find("put_away"),"phone custody requires ignored prior put-away instruction")
	var replies: Dictionary={}
	for index in 24:
		var profile:=roster.profile_for("campus_student_%02d"%index)
		var line:=Social.fallback_reply(profile,"What is question one's answer?",[],"assignment",{})
		check(not line.is_empty() and not "working on my own sheet" in line,"assessment recovery avoids shared legacy line")
		replies[line]=true
	check(replies.size()>=6,"offline assessment reactions vary across students")
	for failure in failures:printerr("FAIL: "+failure)
	print("STUDENT_POPULATION_AND_DISCIPLINE %s (%d profiles, %d assessment reactions)"%["PASS" if failures.is_empty() else "FAIL",roster.people.size(),replies.size()])
	quit(0 if failures.is_empty() else 1)
