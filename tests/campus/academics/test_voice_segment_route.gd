extends SceneTree
## Production Faculty -> scheduler -> player and Faculty -> packet receiver.
## Synthetic audio only; the transport envelope is exercised without a provider.
const NetworkCase=preload("res://tests/campus/academics/test_speech_audio_network.gd")
const Player=preload("res://scripts/campus/academics/teacher_speech_player.gd")
const Synth=preload("res://scripts/campus/academics/teacher_speech_synth.gd")
const Transfer=preload("res://scripts/campus/voice/speech_audio_transfer.gd")
var segments: Array=[]

func _initialize() -> void:call_deferred("run")

func run() -> void:
	create_timer(15.).timeout.connect(func():push_error("segmented route timeout");quit(1))
	var game:=NetworkCase.Game.new();root.add_child(game)
	game.add_child(game.session);game.add_child(game.host_openai);game.add_child(game.lecture_classes);game.lecture_classes.add_child(game.lecture_classes.classroom_students)
	game.session.online=false;game.session.roster={1:{}}
	var faculty:=NetworkCase.ProbeFaculty.new();game.add_child(faculty);faculty.set_process(false);faculty.game=game;game.faculty=faculty
	faculty.conversation=PanelContainer.new();faculty.add_child(faculty.conversation);faculty.conversation.hide()
	faculty.voice_hint=Label.new();faculty.add_child(faculty.voice_hint)
	faculty.speech_player=Player.new();faculty.add_child(faculty.speech_player);faculty.speech_player.set_process(false)
	faculty.speech_synth=Synth.new();faculty.add_child(faculty.speech_synth);faculty.speech_synth.configure_provider(game.host_openai)
	faculty.speech_synth.completed.connect(faculty._speech_completed)
	faculty.speech_synth.segment_completed.connect(faculty._speech_segment_completed)
	faculty.speech_synth.segment_completed.connect(func(channel,serial,key,stream,status,index,total,text):segments.append({"stream":stream,"index":index,"text":text}))
	var actor:=Node3D.new();game.add_child(actor)
	game.lecture_classes.classroom_students.models[NetworkCase.CLASS_ID+":"+NetworkCase.ACTOR]=actor
	NetworkCase.StudentsScript.known_profiles[NetworkCase.ACTOR]=NetworkCase.People.legacy_student(14)
	var text:="Start with the voltage across the resistor and keep the exact value of 12.5 volts while we work through the next calculation. "+"The current follows Ohm's law; use the same units throughout the calculation and explain the physical meaning. ".repeat(4)
	faculty._notify_classmate(1,NetworkCase.ROOM,NetworkCase.CLASS_ID,NetworkCase.ACTOR,text,true)
	while faculty.speech_player.cached.is_empty():await process_frame
	var channel: String=NetworkCase.CHANNEL
	assert(game.host_openai.starts==2 and segments.size()==2,"Faculty enables exactly two renders for a long completed response.")
	assert(faculty.speech_player.active.has(channel) and faculty.speech_routes.is_empty())
	assert(faculty.speech_player.active[channel].item.segment_index==0 and faculty.speech_player.active[channel].item.segments.size()==2)
	assert(faculty.speech_player.cached.values()[0].data.size()==segments[0].stream.data.size()+segments[1].stream.data.size())
	faculty.speech_player._finished(channel,1)
	assert(faculty.speech_player.active[channel].item.segment_index==1)
	faculty.speech_player._finished(channel,1)
	assert(not faculty.speech_player.has_utterance(channel,1),"The cached combined clip is not replayed after the parts.")

	# Reverse part completion order through the real Faculty receive method.
	var remote_channel:="received-parts"
	assert(faculty.speech_player.accept(remote_channel,"Teacher",1,text,2,actor,null,1.,{"expect_audio":true}))
	faculty.pending_voice[remote_channel+"|1"]={"at":Time.get_ticks_msec()}
	for index in [1,0]:
		var stream: AudioStreamWAV=segments[index].stream
		var metadata:={"segment_total":2,"segment_index":index,"segment_text":segments[index].text,"sha256":Transfer.digest(stream.data)}
		for offset in range(0,stream.data.size(),Transfer.CHUNK_BYTES):faculty._voice_chunk(remote_channel,1,stream.data.size(),offset,stream.mix_rate,stream.stereo,stream.data.slice(offset,offset+Transfer.CHUNK_BYTES),metadata)
		if index==1:assert(faculty.pending_voice.has(remote_channel+"|1") and not faculty.speech_player.active.has(remote_channel),"The second part cannot clear the pending first part or start out of order.")
	assert(not faculty.pending_voice.has(remote_channel+"|1") and faculty.speech_player.active[remote_channel].item.segment_index==0)
	faculty.speech_player._finished(remote_channel,1)
	assert(faculty.speech_player.active[remote_channel].item.segment_index==1)
	faculty._voice_cancel(remote_channel,1)
	assert(not faculty.speech_player.has_utterance(remote_channel,1) and faculty.voice_transfer.transfers.is_empty())
	game.queue_free();await process_frame;await create_timer(.12).timeout
	print("VOICE_SEGMENT_ROUTE PASS (production faculty, cache without replay, out-of-order packets, cancellation)")
	quit()
