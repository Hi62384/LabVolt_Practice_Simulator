extends VBoxContainer
## Explicit local test; cloud audio is sent only after a named cloud-test button is pressed.
var toggle: Button
var meter: ProgressBar
var note: Label
var stages: Label
var player: AudioStreamPlayer
var capture: AudioEffectCapture
var bus_name: String=""
var running:=false
var sensitivity: Callable
var microphone: Node
var game: Node
var cloud_kind:=""
var test_audio:=PackedByteArray()
var test_started:=0
var epoch:=0
var speech_seen:=false
var preview: AudioStreamPlayer
var test_buttons: Array[Button]=[]

func build(sensitivity_getter: Callable=Callable(),owner_game: Node=null) -> void:
 sensitivity=sensitivity_getter;game=owner_game
 add_theme_constant_override("separation",8)
 var row:=HBoxContainer.new();row.add_theme_constant_override("separation",8);add_child(row)
 toggle=Button.new();toggle.text="Start microphone test";toggle.pressed.connect(_toggle);row.add_child(toggle)
 meter=ProgressBar.new();meter.max_value=.25;meter.show_percentage=false;meter.size_flags_horizontal=Control.SIZE_EXPAND_FILL;meter.custom_minimum_size.x=160;row.add_child(meter)
 note=Label.new();note.text="Microphone off. A level test stays on this device and sends no audio.";note.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;add_child(note)
 stages=Label.new();stages.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;add_child(stages)
 if is_instance_valid(game):
  var tests:=HBoxContainer.new();tests.add_theme_constant_override("separation",8);add_child(tests)
  for spec in [["Test transcription","transcription"],["Test response and voice","conversation"]]:
   var button:=Button.new();button.text=spec[0];button.pressed.connect(_start_cloud.bind(spec[1]));tests.add_child(button);test_buttons.append(button)
  var disclosure:=Label.new();disclosure.text="Cloud tests record up to six seconds and send the recording to the host's configured AI service. Response testing uses Mr Bro's voice and consumes API usage.";disclosure.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;add_child(disclosure)
 set_process(false)

func _toggle() -> void:
 if not cloud_kind.is_empty():_finish_cloud();return
 if running:_stop();return
 _start()

func _start() -> bool:
 microphone=preload("res://scripts/campus/voice/microphone_capture.gd").shared(self)
 if is_instance_valid(game):microphone.configure(game.client_preferences.values)
 if microphone.preferences.get("microphone_muted",false) or microphone.preferences.get("microphone_mode","")=="muted":note.text="Unmute the microphone to test it.";return false
 if not microphone.packet_ready.is_connected(_packet):microphone.packet_ready.connect(_packet)
 microphone.subscribe("meter_"+str(get_instance_id()),true)
 player=microphone.player;capture=microphone.capture
 running=microphone.is_active()
 if not running:
  var reason:=str(microphone.diagnostic.reason)
  _stop();note.text=reason;return false
 toggle.text="Stop microphone test";note.text="Local level test is on. Speech detection does not yet verify transcription."
 set_process(true);return true

func _process(_delta: float) -> void:
 if not running or not is_instance_valid(microphone):return
 var data: Dictionary=microphone.diagnostic
 meter.value=float(data.get("rms",0.0))
 speech_seen=speech_seen or bool(data.get("speech",false))
 if not microphone.is_active():_stop();note.text=str(data.get("reason","Microphone stopped."));return
 if cloud_kind.is_empty():
  note.text=str(data.get("reason","Listening locally."))+" No audio is being sent."
  stages.text="Input frames: %d · PCM bytes: %d · Capture overrun: %d · Stage: %s"%[int(data.get("frames_received",0)),int(data.get("pcm_bytes",0)),int(data.get("discarded_frames",0)),str(data.get("stage","off"))]
 elif Time.get_ticks_msec()-test_started>=6000:_finish_cloud()

func _packet(pcm: PackedByteArray,_data: Dictionary) -> void:
 if cloud_kind.is_empty() or not running:return
 if test_audio.size()+pcm.size()<=192000:test_audio.append_array(pcm)

func _start_cloud(kind: String) -> void:
 if not is_instance_valid(game) or not game.host_openai.host_allowed():note.text="The session host can run cloud voice diagnostics from these settings.";return
 if not game.host_openai.configured() or not game.host_openai.stt_enabled:note.text="Configure the host's AI service and enable speech recognition first.";return
 if not _start():return
 epoch+=1;cloud_kind=kind;test_audio.clear();test_started=Time.get_ticks_msec();speech_seen=false
 toggle.text="Stop and run test";stages.text="Capture: listening · Speech detection: waiting · Transcription: not started"
 note.text="Say a short question. This test sends your recording when you stop or after six seconds."
 for button in test_buttons:button.disabled=true

func _finish_cloud() -> void:
 if cloud_kind.is_empty():return
 if is_instance_valid(microphone):microphone.drain_pending()
 var kind:=cloud_kind;var samples:=test_audio.duplicate();var detected:=speech_seen
 var capture_status: Dictionary=microphone.diagnostic.duplicate() if is_instance_valid(microphone) else {}
 var generation:=epoch
 cloud_kind="";test_audio.clear()
 _stop(false)
 if not detected or samples.size()<4800:
  stages.text=str(capture_status.get("reason","No input frames arrived."))+" No audio was sent." if int(capture_status.get("frames_received",0))==0 else "Audio frames arrived, but no sufficient speech was detected. Check hardware mute, input level and sensitivity. No audio was sent."
  _enable_buttons();return
 stages.text="Capture: received · Speech detection: detected · Transcription: checking"
 var result: Dictionary=await game.host_openai.transcribe_wav(preload("res://scripts/campus/academics/teacher_ai.gd").wav_16k(samples))
 samples.clear()
 if not is_inside_tree() or generation!=epoch:return
 if not result.get("ok",false):stages.text="Transcription failed: "+str(result.get("error","No transcript was returned."));_enable_buttons();return
 var transcript:=str(result.get("text",""))
 stages.text="Transcription received: “%s”"%transcript
 if kind=="transcription":_enable_buttons();return
 var person: Dictionary=preload("res://scripts/campus/academics/class_character_profile.gd").teacher("mr_bro")
 var response: Dictionary=await game.host_openai.respond_character("This is an explicitly requested voice diagnostic. Reply in one brief, original sentence as the supplied fictional adult teacher. Do not change gameplay, invent grades or claim an action happened.",{"character":person,"diagnostic":true},transcript)
 if not is_inside_tree() or generation!=epoch:return
 if not response.get("ok",false):stages.text+="\nCharacter response failed: "+str(response.get("error","No reply."));_enable_buttons();return
 var text:=preload("res://scripts/campus/academics/character_speech.gd").complete(str(response.get("text","")))
 var delivery: Dictionary=preload("res://scripts/campus/academics/class_character_profile.gd").speech(person,game.host_openai.tts_model,3,"steady",{})
 if not delivery.get("ok",false):stages.text+="\nVoice unavailable: "+str(delivery.get("error","Incompatible voice."));_enable_buttons();return
 var audio: Dictionary=await game.host_openai.speak(text,{},delivery.voice,delivery)
 if not is_inside_tree() or generation!=epoch:return
 if not audio.get("ok",false):stages.text+="\nSpeech generation failed: "+str(audio.get("error","No audio."));_enable_buttons();return
 preview=AudioStreamPlayer.new();preview.bus="NPCSpeech";preview.stream=preload("res://scripts/campus/voice/audio_voice_mixer.gd").normalise(audio.stream,delivery);add_child(preview)
 stages.text+="\nReply: "+text+"\nPlayback started. Confirm that you can hear it clearly."
 preview.finished.connect(func():
  if is_instance_valid(stages):stages.text+="\nPlayback finished. This checks the service path; test proximity and interruptions in gameplay."
  _enable_buttons())
 preview.play()

func _enable_buttons() -> void:
 for button in test_buttons:
  if is_instance_valid(button):button.disabled=false

static func above_threshold(input_level: float,sensitivity_value: float) -> bool:
 return is_finite(input_level) and is_finite(sensitivity_value) and input_level*clampf(sensitivity_value,.5,2.0)>=.004

static func level(frames: PackedVector2Array) -> float:
 if frames.is_empty():return 0.0
 var sum:=0.0
 for frame in frames:
  var sample: float=(frame.x+frame.y)*.5
  if is_finite(sample):sum+=sample*sample
 return sqrt(sum/frames.size())

func _stop(invalidate: bool=true) -> void:
 if invalidate:epoch+=1
 set_process(false);running=false;cloud_kind="";test_audio.clear()
 if is_instance_valid(microphone):
  microphone.subscribe("meter_"+str(get_instance_id()),false)
  if microphone.packet_ready.is_connected(_packet):microphone.packet_ready.disconnect(_packet)
 player=null;capture=null
 if is_instance_valid(toggle):toggle.text="Start microphone test"
 if is_instance_valid(meter):meter.value=0
 if is_instance_valid(note):note.text="Microphone off. The level test sends no audio."
 if invalidate:_enable_buttons()

func _exit_tree() -> void:_stop()
