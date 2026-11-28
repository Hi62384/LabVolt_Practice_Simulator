extends SceneTree
## Local fixture only: tests allocation journaling, recovery, host scoping and
## approval rules, never requests an actual provider voice.
const Voices=preload("res://scripts/campus/academics/teacher_voice_profiles.gd")
const Design=preload("res://scripts/campus/academics/character_voice_design.gd")
const Models=preload("res://scripts/campus/ai/openai_models.gd")
const SCRIPT:="I thought we had this figured out. Let us take another look."
var failures: Array[String]=[]

class ProviderFixture:
	extends Node
	var requests:=0
	var journal_observed:=false
	func host_allowed() -> bool:return true
	func create_prompt_voice(name: String,prompt: String,_hint: String,_draft: Dictionary) -> Dictionary:
		requests+=1
		var saved: Variant=JSON.parse_string(FileAccess.get_file_as_string(Voices.store_path))
		if saved is Dictionary:
			var journal: Dictionary=saved.get("pending_creations",{}).get("mr_bro",{})
			journal_observed=journal.get("name")==name and journal.get("prompt")==prompt
		await get_tree().process_frame
		return {"ok":false,"creation_uncertain":true,"error":"Fixture lost the response."}

func _initialize() -> void:_run.call_deferred()

func check(condition: bool,message: String) -> void:
	if not condition:failures.append(message);push_error(message)

func _approve(person: Dictionary,id: String) -> void:
	var scope:=Voices.scope_for(person)
	for mood: String in Voices.AUDITION_MOODS:
		check(Voices.record_audition(str(person.id),id,mood,"gpt-live-1.1",SCRIPT,scope)==OK,"Record exact model and script "+mood)
	check(Voices.approve(str(person.id),id,true,"gpt-live-1.1",SCRIPT,scope)==OK,"Explicit fixture approval")

func _student(id: String,scope: String,kind: String) -> Dictionary:
	return {"id":id,"name":"Fictional adult","role":"student","age":24,"voice_scope":scope,"dossier_status":"complete","traits":{"warmth":.8,"speaking_pace":.4},
		"voice":{"identifier":"sage" if kind=="feminine" else "ash","presentation":kind,"perceived_age":24,"pitch_range":"low register","accent":"Canadian English","timbre":"rounded and warm","profile":"Original adult fictional timbre","characteristics":"Measured phrases and ordinary pauses"}}

func _run() -> void:
	Voices.store_path="user://custom-voice-recovery-%d.json"%Time.get_ticks_usec();Voices.reset_cache()
	var host:=ProviderFixture.new();root.add_child(host)
	var bro:={"id":"mr_bro","role":"teacher","name":"Mr Bro"}
	var original:=Voices.identity(bro)
	check(not original.is_empty(),"Authored preset initialized")
	var lost:=await Voices.generate_candidate(host,bro,str(original.design_description),SCRIPT)
	check(lost.get("creation_uncertain",false) and host.journal_observed,"Journal persisted before provider POST")
	check(Voices.pending_creation("mr_bro").has("name"),"Ambiguous outcome remains recoverable")
	check(int(Voices.capacity(bro).unresolved)==1,"Unresolved creation consumes conservative capacity")
	check(Voices.identity(bro)==original,"Lost response never changes active identity")
	Voices.reset_cache()
	var retry:=await Voices.generate_candidate(host,bro,str(original.design_description),SCRIPT)
	check(not retry.get("ok",false) and host.requests==1,"Restart blocks duplicate creation before provider call")
	check(Voices.clear_unconfirmed_creation("mr_bro","",false)==ERR_UNAUTHORIZED,"Unresolved allocation cannot be dismissed silently")
	check(Voices.recover_candidate(bro,"voice_recovered_original","prompt",str(original.design_description),false)==ERR_UNAUTHORIZED,"Recovery needs explicit host confirmation")
	check(Voices.recover_candidate(bro,"voice_recovered_original","prompt",str(original.design_description),true)==OK,"Import the actual known provider ID as pending candidate")
	check(Voices.pending_creation("mr_bro").is_empty() and int(Voices.capacity(bro).known)==1,"Recovery reconciles the unresolved slot exactly once")
	check(Voices.identity(bro)==original,"Recovery never approves automatically")
	_approve(bro,"voice_recovered_original")
	Voices.reset_cache()
	check(Voices.resolve(bro,"gpt-realtime-2.1-mini").voice=={"id":"voice_recovered_original"},"Approved prompt voice is pinned through restart and incompatible global default")
	var campus_a:="owner A".sha256_text()
	var campus_b:="owner B".sha256_text()
	var student_a:=_student("campus_student_42",campus_a,"feminine")
	var student_b:=_student("campus_student_42",campus_b,"masculine")
	var design_a:=Design.draft(student_a)
	var design_b:=Design.draft(student_b)
	check(design_a.vocal_presentation=="feminine" and design_a.pitch_range=="low register" and design_a.accent=="Canadian English","AI vocal design informs actual generated student matching")
	check(design_a.permanent_voice_id!=design_b.permanent_voice_id,"Explicit vocal presentation changes provisional match, not roster position")
	check(Models.voice_compatible("gpt-realtime-2.1-mini",design_a.permanent_voice_id) and Models.voice_compatible("gpt-live-1.1",design_b.permanent_voice_id),"Provisional matches support current common models")
	check(Voices.identity(student_a).voice_scope==campus_a and Voices.identity(student_b).voice_scope==campus_b,"Separate generated campus identities use separate saved voice keys")
	check(Voices.stage_candidate(student_a,{"id":"voice_student_a","type":"prompt"})==OK,"Scoped student candidate staged")
	check(Voices.stage_candidate(student_b,{"id":"voice_student_a","type":"prompt"})==ERR_ALREADY_EXISTS,"A second campus cannot accidentally claim another character's custom ID")
	_approve(student_a,"voice_student_a")
	Voices.reset_cache()
	check(Voices.identity(student_a).permanent_voice_id=="voice_student_a" and Voices.identity(student_b).voice_type=="preset","One campus cannot inherit another campus's approved custom voice")
	var old:=_student("campus_student_43","","feminine")
	var owner:=_student("campus_student_43",campus_a,"feminine")
	check(not Voices.identity(old).is_empty(),"Legacy unscoped voice exists")
	check(Voices.stage_candidate(old,{"id":"voice_legacy_owned","type":"prompt"})==OK,"Legacy custom candidate staged")
	_approve(old,"voice_legacy_owned")
	check(Voices.legacy_conflict(owner) and Voices.identity(owner).is_empty(),"Ambiguous old identity is blocked, not silently reassigned")
	check(Voices.resolve_legacy(owner,true,false)==ERR_UNAUTHORIZED,"Legacy adoption requires explicit confirmation")
	check(Voices.resolve_legacy(owner,true,true)==OK,"Confirmed owner adopts existing identity without changing resource")
	check(Voices.identity(owner).permanent_voice_id=="voice_legacy_owned","Adoption preserves actual provider voice")
	check(Voices.set_external_voice_count(97)==OK and int(Voices.capacity(bro).remaining)==0,"Known and external allocations count conservatively")
	var path:=Voices.store_path
	var backup_exists:=FileAccess.file_exists(path+".bak")
	var file:=FileAccess.open(path,FileAccess.WRITE);file.store_string("broken");file.close()
	Voices.reset_cache()
	check(backup_exists and Voices.identity(bro).is_empty() and Voices.last_error==ERR_FILE_CORRUPT,"A stale backup never silently rolls back a custom voice")
	for suffix: String in ["",".bak",".tmp"]:
		if FileAccess.file_exists(path+suffix):DirAccess.remove_absolute(path+suffix)
	Voices.store_path="user://character_voices.json";Voices.reset_cache()
	host.queue_free()
	print("CUSTOM_VOICE_RECOVERY ","PASS" if failures.is_empty() else "FAIL"," (fixture provider, allocation journal, scoping, migration, no live speech claim)")
	quit(0 if failures.is_empty() else 1)
