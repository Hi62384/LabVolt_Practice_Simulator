extends SceneTree
const Voices=preload("res://scripts/campus/academics/teacher_voice_profiles.gd")
const People=preload("res://scripts/campus/academics/class_character_profile.gd")
const LINE:="We can try this circuit again."
var failures: Array[String]=[]

func check(condition: bool,message: String) -> void:
	if not condition:failures.append(message);push_error(message)

func _initialize() -> void:
	var origin:="portable-origin".sha256_text()
	var person:=People.legacy_student(3)
	person.id="campus_student_"+"portable-student".sha256_text().left(32)
	person.voice_scope=origin
	var first:="user://voice-origin-%d.json"%Time.get_ticks_usec()
	var second:="user://voice-destination-%d.json"%Time.get_ticks_usec()
	Voices.store_path=first;Voices.reset_cache()
	check(Voices.stage_candidate(person,{"id":"voice_portable_approved","type":"prompt"})==OK,"Origin candidate staged")
	for mood: String in Voices.AUDITION_MOODS:check(Voices.record_audition(person.id,"voice_portable_approved",mood,"gpt-live-1.1",LINE,origin)==OK,"Origin audition recorded")
	check(Voices.approve(person.id,"voice_portable_approved",true,"gpt-live-1.1",LINE,origin)==OK,"Origin approved once")
	var record:=Voices.portable_profile(person)
	check(record.permanent_voice_id=="voice_portable_approved" and record.approval_status=="approved","Portable record carries permanent approved identity")
	check(not record.has("audition_runs") and not record.has("auditions") and not record.has("account_availability"),"Portable record excludes local hearing and account details")
	Voices.store_path=second;Voices.reset_cache()
	var original:=record.duplicate(true)
	record["unexpected_private_field"]="synthetic-do-not-persist"
	check(Voices.accept_portable_profile(person,record)==OK,"First selected student import accepted")
	Voices.reset_cache()
	var restored:=Voices.identity(person)
	check(restored.permanent_voice_id=="voice_portable_approved" and restored.voice_scope==origin and restored.approval_status=="approved","Original voice and origin survive receiving-host restart")
	check(restored.audition_status=="not_auditioned_on_this_device" and Voices.auditions_for(restored,"gpt-live-1.1",LINE).is_empty(),"Remote approval never claims local listening")
	check(not FileAccess.get_file_as_string(second).contains("synthetic-do-not-persist"),"Unknown network fields are never persisted")
	check(Voices.capacity(person).known==0,"Foreign resource does not consume a claimed local allocation")
	check(Voices.accept_portable_profile(person,original)==OK,"Repeated import is idempotent")
	var conflict:=original.duplicate(true);conflict.permanent_voice_id="voice_conflicting_import"
	check(Voices.accept_portable_profile(person,conflict)==ERR_ALREADY_EXISTS and Voices.identity(person).permanent_voice_id=="voice_portable_approved","Import cannot overwrite a saved approved voice")
	var other:=person.duplicate(true);other.id="campus_student_"+"other-student".sha256_text().left(32)
	var impostor:=original.duplicate(true);impostor.character_id=other.id
	check(Voices.accept_portable_profile(other,impostor)==ERR_ALREADY_EXISTS,"One custom voice cannot be assigned to a different character")
	var invalid:=Voices.Design.draft(other);invalid.permanent_voice_id="unknown_preset"
	check(Voices.accept_portable_profile(other,invalid)==ERR_INVALID_DATA,"Unknown preset cannot become a permanent identity")
	check(Voices.accept_portable_profile({"id":"mr_bro"},original)==ERR_INVALID_DATA,"Population imports cannot modify canonical faculty")
	for path: String in [first,second]:
		for suffix: String in ["",".bak",".tmp"]:
			if FileAccess.file_exists(path+suffix):DirAccess.remove_absolute(path+suffix)
	Voices.store_path="user://character_voices.json";Voices.reset_cache()
	print("PORTABLE_CHARACTER_VOICE ","PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)
