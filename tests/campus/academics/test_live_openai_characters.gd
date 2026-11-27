extends SceneTree
## Runs from a disposable Godot profile. The optional interactive key is
## confined to the game process and never written to disk or to this report.
const Models=preload("res://scripts/campus/ai/openai_models.gd")
const Profiles=preload("res://scripts/campus/academics/class_character_profile.gd")
const MathSpeech=preload("res://scripts/campus/academics/speech_math.gd")
var game: Node
var panel: Window
var key_entry: LineEdit
var status: Label
var running:=false
var fixture:=false

func _initialize() -> void:
	call_deferred("_ready_test")

func _ready_test() -> void:
	game=load("res://scenes/Main.tscn").instantiate()
	root.add_child(game)
	for arg in OS.get_cmdline_user_args():
		if not arg.begins_with("--fixture-port="):continue
		var port:=arg.trim_prefix("--fixture-port=")
		if not port.is_valid_int() or not game.host_openai.set_local_test_endpoint("http://127.0.0.1:%s/v1"%port):
			_finish("FAIL: Invalid local fixture endpoint.",1)
			return
		fixture=true
		game.host_openai.set_session_key("sk-test-12345678901234567890")
		_run.call_deferred()
		return
	if OS.get_environment("OPENAI_API_KEY").strip_edges().is_empty():
		if DisplayServer.get_name()=="headless":
			_finish("SKIP: No OpenAI API key available.",2)
			return
		panel=Window.new()
		panel.title="LabVolt — Live OpenAI dialogue and voice test"
		panel.size=Vector2i(560,184)
		panel.transient=true
		panel.exclusive=true
		panel.close_requested.connect(func():quit(2))
		root.add_child(panel)
		var margin:=MarginContainer.new()
		margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		for side in ["left","right","top","bottom"]:margin.add_theme_constant_override("margin_"+side,18)
		panel.add_child(margin)
		var fields:=VBoxContainer.new()
		fields.add_theme_constant_override("separation",12)
		margin.add_child(fields)
		status=Label.new()
		status.text="Enter your OpenAI API key to test dialogue and voices in LabVolt. The key clears when this window closes."
		status.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
		fields.add_child(status)
		key_entry=LineEdit.new()
		key_entry.secret=true
		key_entry.placeholder_text="OpenAI API key"
		key_entry.text_submitted.connect(func(_value):_connect_key())
		fields.add_child(key_entry)
		var start:=Button.new()
		start.text="Run live test"
		start.pressed.connect(_connect_key)
		fields.add_child(start)
		panel.popup_centered()
		key_entry.grab_focus()
	else:
		_run.call_deferred()

func _connect_key() -> void:
	if running:return
	var accepted: bool=game.host_openai.set_session_key(key_entry.text)
	key_entry.clear()
	if not accepted:
		status.text="Enter a valid OpenAI API key."
		return
	panel.hide()
	_run.call_deferred()

func _run() -> void:
	if running:return
	running=true
	create_timer(150.).timeout.connect(func():_finish("FAIL: Live character test timed out.",1))
	for frame in 4:await process_frame
	var client: Node=game.host_openai
	var available: Dictionary=await client.list_models()
	if not available.get("ok",false):
		_finish("FAIL: "+str(available.get("error","Could not list accessible models.")),1)
		return
	var model:=""
	for id in [client.DEFAULT_MODEL,"gpt-4.1-mini","gpt-4.1","gpt-5-mini"]:
		if id in available.models:
			model=id
			break
	if model.is_empty() or client.configure(model,384,Models.normalize_effort(model,""),true)!=OK:
		_finish("FAIL: No supported live dialogue model was available.",1)
		return
	client.tts_enabled=true
	client.tts_model=client.SPEECH_MODEL
	game.front.entered()
	var identity: String=game.school.local_identity
	game.school.identities[1]=identity if not identity.is_empty() else "0123456789abcdef0123456789abcdef0123456789abcdef"
	game.player.set_physics_process(false)
	var classes: Node=game.lecture_classes
	var faculty: Node=game.faculty
	var room:="ac_lab"
	game.player.global_position=classes.signs[room].desk
	var error: String=classes._start(room,{"kind":"lab","course_id":"ELM253","week":1,"difficulty":1})
	if not error.is_empty():
		_finish("FAIL: Could not start the in-game lab. "+error,1)
		return
	var activity: Dictionary=classes.classes[room]
	faculty.lecture_cues[room]=activity.id+":arrival"
	var member: Dictionary=activity.classmates.values()[0] if not activity.classmates.is_empty() else {}
	if member.is_empty():
		_finish("FAIL: The lab did not spawn a classmate.",1)
		return
	member.arrival=classes._now()-1.
	member.position=member.seat
	member.arrived=true
	classes._publish()
	faculty._sync_lab_teachers()
	game.player.global_position=faculty._teacher_position(room)+Vector3(.5,0,0)
	var teacher_line:=await _conversation(room,"","In one short sentence, what is one practical reason students measure AC voltage?")
	if teacher_line.is_empty():
		_finish("FAIL: The instructor did not produce a verified OpenAI reply and voice clip.",1)
		return
	print(_prefix()," teacher (",model,"): ",teacher_line)
	game.player.global_position=member.position+Vector3(.5,0,0)
	classes._publish()
	classes.classroom_students.render(room,classes.public_classes,.1)
	var student_line:=await _conversation(room,member.profile.id,"What do you enjoy about being a student here? Answer in one short sentence.",activity.id)
	if student_line.is_empty():
		_finish("FAIL: The classmate did not produce a verified OpenAI reply and voice clip.",1)
		return
	print(_prefix()," classmate (",model,"): ",student_line)
	_finish("PASS: Live OpenAI dialogue and voice for teacher and classmate.",0)

func _conversation(room: String,actor: String,question: String,class_id := "") -> String:
	var faculty: Node=game.faculty
	var client: Node=game.host_openai
	var channel:=room if actor.is_empty() else "classmate"
	var activity: Dictionary=game.lecture_classes.classes[room]
	var person: Dictionary=Profiles.teacher(activity.teacher) if actor.is_empty() else game.lecture_classes.classroom_students.profile_for(actor)
	var text_before: int=_successes(client,client.model,"text")
	var speech_before: int=_successes(client,client.tts_model,"tts")
	faculty.open_conversation(room,actor,class_id)
	faculty.conversation_input.text=question
	faculty._submit_question()
	var expiry:=Time.get_ticks_msec()+50000
	while Time.get_ticks_msec()<expiry:
		var line: String=faculty.conversation_text.text
		if not line.contains("Waiting for a reply") and _successes(client,client.model,"text")>text_before and _successes(client,client.tts_model,"tts")>speech_before:
			var text:=MathSpeech.display(line).left(350)
			for key in faculty.speech_player.cached:
				if not str(key).begins_with(str(person.id)+":openai:"):continue
				var clip: AudioStreamWAV=faculty.speech_player.cached[key]
				var active: Dictionary=faculty.speech_player.active.get(channel,{})
				var spoken: Dictionary=faculty.speech_player.subtitles.get(channel,{}).get("item",{})
				if spoken.get("text","")==text and int(spoken.get("serial",0))==int(active.get("serial",-1)) and is_instance_valid(active.get("player")) and active.player.stream==clip and _audible(clip):
					await create_timer(minf(clip.get_length()+.15,12.)).timeout
					faculty.close_conversation()
					return text
		await create_timer(.08).timeout
	print(_prefix()," state for ",person.id,": ",str(faculty.conversation_text.text).left(110),
		" · text replies ",_successes(client,client.model,"text")-text_before,
		" · speech clips ",_successes(client,client.tts_model,"tts")-speech_before)
	faculty.close_conversation()
	return ""

func _audible(clip: AudioStreamWAV) -> bool:
	if clip.get_length()<=.2 or clip.format!=AudioStreamWAV.FORMAT_16_BITS:return false
	var samples:=clip.data
	for offset in range(0,samples.size()-1,64):
		if absi(samples.decode_s16(offset))>150:return true
	return false

func _successes(client: Node,model: String,purpose: String) -> int:
	var count:=0
	for entry in client.usage_tracker.rows.values():
		if entry.model==model and entry.purpose==purpose:count+=int(entry.get("success",0))
	return count

func _finish(message: String,code: int) -> void:
	print(_prefix()+" "+message)
	quit(code)

func _prefix() -> String:
	return "OPENAI_FIXTURE" if fixture else "LIVE_OPENAI"
