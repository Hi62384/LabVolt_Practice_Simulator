extends SceneTree
## Native playback/subtitle and WAV integration. Synthesis launch is an adapter;
## no installed voice model or live speech provider is claimed by this test.
const Player=preload("res://scripts/campus/academics/teacher_speech_player.gd")
const Synth=preload("res://scripts/campus/academics/teacher_speech_synth.gd")
const Profiles=preload("res://scripts/campus/academics/class_character_profile.gd")
var events: Array=[]
var killed: Array=[]

func _initialize() -> void:call_deferred("run")

func run() -> void:
	var player:=Player.new();root.add_child(player);player.set_process(false)
	var anchor:=Node3D.new();root.add_child(anchor)
	var head:=Node3D.new();head.name="Head";anchor.add_child(head)
	var text:=""
	for index in 9:
		text+="Part %d: Before deciding whether this course fits your plans, explain what you want to build and what you have already tried. " % index
	text+="That is the complete final thought."
	assert(text.length()>1000 and text.length()<Player.MAX_TEXT)
	var wav:=AudioStreamWAV.new();wav.format=AudioStreamWAV.FORMAT_16_BITS;wav.mix_rate=48000
	var samples:=PackedByteArray();samples.resize(Player.MAX_WAV_BYTES);samples.fill(20);wav.data=samples
	assert(Player.valid_stream(wav) and wav.get_length()>80.)
	assert(player.accept("captions","Chad",1,text,2,anchor))
	assert(player.active.is_empty())
	var caption: Dictionary=player.subtitles.captions
	var shown: Array[String]=[]
	var total:=0
	for page in caption.pages:total+=str(page).length()
	var before:=0
	for page in caption.pages:
		var elapsed:=int((float(before)+str(page).length()*.5)/total*int(caption.duration))
		caption.started=Time.get_ticks_msec()-elapsed
		player._process(0.)
		shown.append(str(caption.label.text).trim_prefix("Chad: "))
		before+=str(page).length()
	assert(shown.size()>3 and " ".join(shown)==text,"A missing voice must still display every sentence in order.")
	assert(player.deliver_stream("captions",1,wav))
	assert(player.active.captions.serial==1 and player.subtitles.captions.page==0,"Late audio restarts captions at the matching first sentence.")
	player.cancel("captions")
	assert(player.accept("slow","Chad",1,text,2,anchor,wav,.5))
	assert(int(player.subtitles.slow.until)-Time.get_ticks_msec()>=int(wav.get_length()*2000.),"Slow emotional playback must retain its subtitles for the full clip.")
	player.cancel("slow")
	assert(player.accept("queue","Chad",1,"First spoken line.",2,anchor,wav))
	assert(player.accept("queue","Chad",2,text,1,anchor))
	assert(player.accept("queue","Chad",3,"Last spoken line.",1,anchor))
	player._finished("queue",1)
	assert(not player.active.has("queue") and player.subtitles.queue.item.serial==2)
	assert(player.deliver_stream("queue",3,wav) and not player.active.has("queue"),"Late audio must retain its place behind the current caption-only reply.")
	player.subtitles.queue.until=Time.get_ticks_msec()-1
	player.presentations.queue.until=Time.get_ticks_msec()-1
	player._process(0.)
	assert(player.active.queue.serial==3,"A caption-only queued line must eventually release the next audio line.")
	player._finished("queue",3)
	assert(not player.active.has("queue") and not player.queued.has("queue"),"A delivered queued clip must play exactly once.")
	player.cancel("queue")
	player.configure(true,false)
	assert(player.accept("hidden","Chad",1,"First.",2,anchor,wav))
	assert(player.accept("hidden","Chad",2,"Unavailable audio.",1,anchor))
	assert(player.accept("hidden","Chad",3,"Last.",1,anchor,wav))
	player._finished("hidden",1);player._process(0.)
	assert(player.active.hidden.serial==3 and player.subtitles.is_empty())
	player.cancel("hidden");player.configure(true,true)
	assert(player.accept("full","Chad",1,"First.",2,anchor,wav))
	for serial in range(2,Player.MAX_QUEUED+2):assert(player.accept("full","Chad",serial,"Queued.",1,anchor,wav))
	var accepted_serial:=int(player.last_serial.full)
	assert(not player.accept("full","Chad",accepted_serial+1,"No space.",1,anchor,wav))
	assert(int(player.last_serial.full)==accepted_serial and int(player.awaiting.full.item.serial)==accepted_serial)
	player.cancel("full")
	var malformed:=wav.duplicate() as AudioStreamWAV
	malformed.data=PackedByteArray([1,2,3])
	assert(not player.cache_stream("malformed",malformed))
	assert(not player.accept("invalid","Chad",1,"Bad audio.",2,anchor,malformed))
	assert(not player.accept("invalid","Chad",1,"Bad pitch.",2,anchor,wav,NAN))
	assert(player.accept("valid-later","Chad",1,"Waiting for the valid clip.",2,anchor))
	assert(not player.deliver_stream("valid-later",1,malformed) and player.awaiting.has("valid-later"))
	assert(player.deliver_stream("valid-later",1,wav));player.cancel("valid-later")
	malformed=wav.duplicate() as AudioStreamWAV
	var oversized:=samples.duplicate();oversized.resize(Player.MAX_WAV_BYTES+2);malformed.data=oversized
	assert(not Player.valid_stream(malformed))
	malformed=wav.duplicate() as AudioStreamWAV;malformed.stereo=true;malformed.data=PackedByteArray([1,2])
	assert(not Player.valid_stream(malformed),"Stereo requires complete two-channel sample frames.")
	malformed=wav.duplicate() as AudioStreamWAV;malformed.mix_rate=7999
	assert(not Player.valid_stream(malformed))
	assert(not player.accept("long","Chad",1,"x".repeat(Player.MAX_TEXT+1),2,anchor))

	# A real maximum-size WAV takes the same path as a completed local process,
	# including native decoding, cache validation and audio-node gain.
	var synth:=Synth.new();root.add_child(synth);synth.set_process(false)
	synth.profile_adapter=func():return {"brian":{"model":"res://assets/campus/faculty/voices/test.onnx","speaker":0,"rate":.9,"gain":1.65,"pause_ms":100}}
	synth.model_adapter=func(_path):return true
	synth.launch_adapter=func(_exe,_args):return 9876
	synth.running_adapter=func(_pid):return false
	synth.kill_adapter=func(pid):killed.append(pid)
	synth.completed.connect(func(room,serial,key,stream,status):
		events.append({"status":status,"stream":stream})
		if status=="ok":
			assert(player.cache_stream(key,stream))
			assert(player.deliver_stream(room,serial,stream)))
	var previous_executable:=OS.get_environment("LABVOLT_PIPER_PATH")
	OS.set_environment("LABVOLT_PIPER_PATH","")
	assert(synth.request("native",1,"brian","x".repeat(Player.MAX_TEXT+1),"oversized")=="invalid")
	assert(player.accept("native","Brian",1,text,2,anchor))
	assert(synth.request("native",1,"brian",text,"long-native")=="queued")
	await process_frame
	assert(FileAccess.get_file_as_string(synth.active.input)==text,"The entire accepted reply reaches the synthesizer input.")
	assert(bool(synth.active.get("standalone",false)))
	assert(wav.save_to_wav(ProjectSettings.globalize_path(synth.active.output))==OK)
	var output_path: String=synth.active.output
	synth._process(0.)
	assert(events.size()==1 and events[0].status=="ok")
	assert(events[0].stream.data==samples,"Voice gain must not rewrite or clip the original PCM samples.")
	assert(is_equal_approx(float(player.active.native.player.volume_db),linear_to_db(1.65)))
	assert(not FileAccess.file_exists(output_path))
	assert(synth.request("cancel-on-exit",2,"brian","Still working.","exit")=="queued")
	await process_frame
	var input_path: String=synth.active.input
	synth.queue_free();await process_frame
	assert(killed==[9876] and not FileAccess.file_exists(input_path),"Leaving a session must terminate its local synthesis process.")
	OS.set_environment("LABVOLT_PIPER_PATH",previous_executable)

	var chad:=Profiles.teacher("chad")
	var tense:=Profiles.speech(chad,"gpt-4o-mini-tts",2,"irritated",{"anger":.8,"embarrassment":.7,"sadness":.2})
	var subdued:=Profiles.speech(chad,"gpt-4o-mini-tts",2,"sad",{"sadness":.8})
	assert(tense.voice==subdued.voice and float(tense.speed)>float(subdued.speed))
	assert("anger 0.8" in tense.instructions and "embarrassment 0.7" in tense.instructions and "dismissive" in tense.instructions)
	assert("sadness 0.8" in subdued.instructions and tense.instructions!=subdued.instructions)
	player.clear_session();anchor.queue_free();player.queue_free()
	await process_frame
	await process_frame
	print("TEACHER_SPEECH_LONG_DELIVERY PASS (native WAV, captions and player; adapter launch, no live voice)")
	quit(0)
