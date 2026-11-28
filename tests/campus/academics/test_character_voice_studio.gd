extends SceneTree
const Studio=preload("res://scripts/campus/ui/character_voice_studio.gd")
const Voices=preload("res://scripts/campus/academics/teacher_voice_profiles.gd")
const People=preload("res://scripts/campus/academics/class_character_profile.gd")
var failures: Array[String]=[]

class HostFixture:
	extends Node
	var tts_model:="gpt-realtime-2.1-mini"
	var requests: Array[Dictionary]=[]
	var creations:=0
	func host_allowed() -> bool:return true
	func create_prompt_voice(name: String,prompt: String,_hint: String,_draft: Dictionary) -> Dictionary:
		creations+=1
		await get_tree().process_frame
		return {"ok":true,"id":"voice_studio_test_%d"%creations,"name":name,"type":"prompt","prompt":prompt}
	func speak(text: String,draft: Dictionary,voice: Variant,delivery: Dictionary) -> Dictionary:
		requests.append({"text":text,"draft":draft,"voice":voice,"delivery":delivery})
		await get_tree().process_frame
		var stream:=AudioStreamWAV.new();stream.mix_rate=24000;stream.format=AudioStreamWAV.FORMAT_16_BITS
		var pcm:=PackedByteArray();pcm.resize(9600)
		for index in 4800:pcm.encode_s16(index*2,int(sin(float(index)*.07)*2000.))
		stream.data=pcm
		return {"ok":true,"stream":stream}

func check(condition: bool,message: String) -> void:
	if not condition:failures.append(message);push_error(message)

func _initialize() -> void:_run.call_deferred()

func _run() -> void:
	Voices.store_path="user://voice-studio-test-%d.json"%Time.get_ticks_usec();Voices.reset_cache()
	var host:=HostFixture.new();root.add_child(host)
	var panel:=Studio.new();root.add_child(panel);panel.configure(host,{"modalities":{"tts":"gpt-realtime-2.1-mini"}})
	await process_frame
	check(panel.character_list.item_count==21 and panel.selected_id=="mr_bro","Studio opens the full faculty list with Mr Bro selected")
	panel.search.text="bro";panel._fill_list()
	check(panel.character_list.item_count==1,"Search filters the authored character list")
	panel.search.text="";panel._fill_list()
	check(is_instance_valid(panel.portrait_model),"Selected identity has a real character preview")
	var previous:=Voices.identity(People.teacher("mr_bro"))
	await panel._generate()
	check(host.creations==1 and not Voices.candidate("mr_bro").is_empty(),"Generation action persists a single staged provider response")
	check(Voices.identity(People.teacher("mr_bro"))==previous,"Pending auditions do not affect gameplay identity")
	check(panel._model()=="gpt-live-1.1" and panel.use_candidate.button_pressed,"Prompt candidate selects the compatible audition route")
	check(panel.approve_button.disabled,"Unheard candidate cannot be approved from the UI")
	await panel._preview()
	panel._stop()
	await create_timer(.3).timeout
	check(not Voices.candidate("mr_bro").get("auditions",{}).has("normal"),"Stopped preview does not count as completed listening")
	for mood: String in ["normal","sad","angry"]:
		for index in panel.emotion.item_count:
			if str(panel.emotion.get_item_metadata(index))==mood:panel.emotion.select(index);break
		await panel._preview()
		await create_timer(.35).timeout
		check(Voices.candidate("mr_bro").get("auditions",{}).has(mood),"Playback completion records only the auditioned mood: "+mood)
	check(panel.approve_button.disabled,"Preview output alone does not assert satisfactory character quality")
	panel.fit.button_pressed=true;panel._refresh()
	check(not panel.approve_button.disabled,"Host listening judgment makes voice and model approval available")
	panel._approve()
	var approved:=People.speech(People.teacher("mr_bro"),"gpt-realtime-2.1-mini",2)
	check(approved.model=="gpt-live-1.1" and approved.voice=={"id":"voice_studio_test_1"},"Approval routes gameplay to the exact approved voice and model")
	check(Voices.candidate("mr_bro").is_empty(),"Approved candidate is no longer shown as pending")
	await panel._generate_missing_faculty()
	check(host.creations==21,"One explicit batch creates all twenty other missing faculty")
	check(Voices.missing_faculty(panel.people).is_empty(),"Batch is resumable and skips approved or pending faculty")
	await panel._generate_missing_faculty()
	check(host.creations==21,"Repeated batch never creates duplicate provider allocations")
	panel._next_candidate()
	check(panel.selected_id!="mr_bro" and panel.use_candidate.button_pressed,"Next candidate advances to an unapproved teacher")
	var next_id:=panel.selected_id
	await panel._play_core()
	var until:=Time.get_ticks_msec()+5000
	while (panel.busy or panel.audio.playing or not panel.core_queue.is_empty()) and Time.get_ticks_msec()<until:await process_frame
	var heard:=Voices.auditions_for(Voices.candidate(next_id),panel._model(),panel.sentence.text)
	check(Voices.AUDITION_MOODS.all(func(mood: String):return heard.has(mood)),"Three-core audition sequence records all moods on the same model and script")
	check(panel.approve_button.disabled,"Batch audition never substitutes for human approval")
	check(host.requests[0].text==host.requests[1].text and host.requests[1].voice==host.requests[2].voice,"Emotion comparisons use the same words and stable voice")
	check(host.requests[1].delivery.instructions!=host.requests[2].delivery.instructions,"Emotion comparisons change model performance instructions")
	panel.queue_free();host.queue_free();await process_frame
	var path:=Voices.store_path
	for suffix: String in ["",".bak",".tmp"]:
		if FileAccess.file_exists(path+suffix):DirAccess.remove_absolute(path+suffix)
	Voices.store_path="user://character_voices.json";Voices.reset_cache()
	print("CHARACTER_VOICE_STUDIO ","PASS" if failures.is_empty() else "FAIL"," (native UI and playback events; simulated provider, no live listening claim)")
	quit(0 if failures.is_empty() else 1)
