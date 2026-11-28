extends VBoxContainer
## The level/sample tests stay local. Only the explicitly labelled cloud tests
## submit the selected sample. Captured PCM is held in memory and cleared on exit.
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
var cloud_busy:=false
var request_id:=""
var test_audio:=PackedByteArray()
var last_sample:=PackedByteArray()
var sample_stats: Dictionary={}
var test_started:=0
var sample_epoch:=0
var epoch:=0
var speech_seen:=false
var preview: AudioStreamPlayer
var record_button: Button
var play_button: Button
var test_buttons: Array[Button]=[]

func build(sensitivity_getter: Callable=Callable(),owner_game: Node=null) -> void:
 sensitivity=sensitivity_getter;game=owner_game
 add_theme_constant_override("separation",8)
 var row:=HBoxContainer.new();row.add_theme_constant_override("separation",8);add_child(row)
 toggle=Button.new();toggle.text="Start microphone test";toggle.pressed.connect(_toggle);row.add_child(toggle)
 meter=ProgressBar.new();meter.max_value=.25;meter.show_percentage=false;meter.size_flags_horizontal=Control.SIZE_EXPAND_FILL;meter.size_flags_vertical=Control.SIZE_SHRINK_CENTER;meter.custom_minimum_size=Vector2(160,16);meter.tooltip_text="Live microphone level. The local test sends no audio.";row.add_child(meter)
 var meter_background:=StyleBoxFlat.new();meter_background.bg_color=Color("091a25");meter_background.border_color=Color("315266");meter_background.set_border_width_all(1);meter_background.set_corner_radius_all(4);meter.add_theme_stylebox_override("background",meter_background)
 var meter_fill:=StyleBoxFlat.new();meter_fill.bg_color=Color("58c9ab");meter_fill.set_corner_radius_all(4);meter.add_theme_stylebox_override("fill",meter_fill)
 note=Label.new();note.text="Microphone off. A level test stays on this device and sends no audio.";note.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;add_child(note)
 stages=Label.new();stages.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;add_child(stages)
 var local_row:=HBoxContainer.new();local_row.add_theme_constant_override("separation",8);add_child(local_row)
 record_button=Button.new();record_button.text="Record local sample";record_button.pressed.connect(_start_recording.bind("local"));local_row.add_child(record_button)
 play_button=Button.new();play_button.text="Play recorded sample";play_button.disabled=true;play_button.pressed.connect(_play_sample);local_row.add_child(play_button)
 if is_instance_valid(game):
  var tests:=HBoxContainer.new();tests.add_theme_constant_override("separation",8);add_child(tests)
  for spec in [["Test transcription","transcription"],["Test response and voice","conversation"]]:
   var button:=Button.new();button.text=spec[0];button.pressed.connect(_start_cloud.bind(spec[1]));tests.add_child(button);test_buttons.append(button)
  var disclosure:=Label.new();disclosure.text="Record and replay a sample locally first. Cloud tests send that sample to the host's configured AI service, or record up to six seconds if no sample exists. Response testing uses Mr Bro's voice and consumes API usage.";disclosure.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;add_child(disclosure)
 set_process(false)

func _toggle() -> void:
 if not cloud_kind.is_empty():_finish_cloud();return
 if running or cloud_busy:_stop();return
 _start()

func _start() -> bool:
 microphone=preload("res://scripts/campus/voice/microphone_capture.gd").shared(self)
 if is_instance_valid(game):microphone.configure(game.client_preferences.values)
 if microphone.preferences.get("microphone_muted",false) or microphone.preferences.get("microphone_mode","")=="muted":note.text="Unmute the microphone to test it.";return false
 _stop_preview()
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
 if not cloud_kind.is_empty() and sample_epoch!=int(microphone.capture_epoch):
  _stop();stages.text="The input device changed during recording. Record a new sample; no audio was sent.";return
 if cloud_kind.is_empty():
  note.text=str(data.get("reason","Listening locally."))+" No audio is being sent."
  stages.text="Input frames: %d · PCM bytes: %d · Capture overrun: %d · Stage: %s"%[int(data.get("frames_received",0)),int(data.get("pcm_bytes",0)),int(data.get("discarded_frames",0)),str(data.get("stage","off"))]
 elif Time.get_ticks_msec()-test_started>=6000:_finish_cloud()

func _packet(pcm: PackedByteArray,_data: Dictionary) -> void:
 if cloud_kind.is_empty() or not running:return
 if sample_epoch!=int(microphone.capture_epoch):return
 var remaining:=192000-test_audio.size()
 if remaining>0:test_audio.append_array(pcm.slice(0,remaining))

func _start_recording(kind: String) -> void:
 _stop()
 if not _start():return
 cloud_kind=kind;test_audio.clear();test_started=Time.get_ticks_msec();speech_seen=false;sample_epoch=int(microphone.capture_epoch)
 toggle.text="Stop recording" if kind=="local" else "Stop and run test"
 stages.text="Capture: listening · Speech detection: waiting"
 note.text="Record a short phrase. Up to six seconds stay on this device." if kind=="local" else "Say a short question. This test sends your recording when you stop or after six seconds."
 _disable_buttons()

func _start_cloud(kind: String) -> void:
 if not is_instance_valid(game) or not game.host_openai.host_allowed():note.text="The session host can run cloud voice diagnostics from these settings.";return
 if not game.host_openai.configured() or not game.host_openai.stt_enabled:note.text="Configure the host's AI service and enable speech recognition first.";return
 if not last_sample.is_empty():
  _stop()
  _submit_cloud(kind,last_sample.duplicate(),epoch)
 else:_start_recording(kind)

func _finish_cloud() -> void:
 if cloud_kind.is_empty():return
 if is_instance_valid(microphone):microphone.drain_pending()
 var kind:=cloud_kind;var samples:=test_audio.duplicate()
 var capture_status: Dictionary=microphone.diagnostic.duplicate() if is_instance_valid(microphone) else {}
 var generation:=epoch
 cloud_kind="";test_audio.clear()
 _stop(false)
 if int(capture_status.get("capture_epoch",-1))!=sample_epoch:
  stages.text="The microphone device changed. Record a new sample; no audio was sent.";_enable_buttons();return
 if samples.size()<4800:
  stages.text=str(capture_status.get("reason","No input frames arrived."))+" No audio was sent." if samples.is_empty() else "The recording was too short. Record at least a short sentence. No audio was sent."
  _enable_buttons();return
 sample_stats=microphone.processor.InspectPcm16(samples)
 last_sample=samples
 stages.text="Recorded %.2f seconds · Peak %.1f dB · RMS %.1f dB · %d samples · Local speech detection: %s"%[float(sample_stats.duration_seconds),linear_to_db(maxf(float(sample_stats.peak),.000001)),linear_to_db(maxf(float(sample_stats.rms),.000001)),int(sample_stats.samples),"detected" if speech_seen else "below threshold"]
 if kind=="local":
  note.text="Sample saved in memory. Play it back to check your microphone; nothing was uploaded."
  _enable_buttons();return
 if not sample_stats.get("has_signal",false):
  stages.text+="\nNo usable input signal was recorded. Check hardware mute and input level. No audio was sent."
  _enable_buttons();return
 _submit_cloud(kind,samples,generation)

func _submit_cloud(kind: String,samples: PackedByteArray,generation: int) -> void:
 var stats: Dictionary=preload("res://scripts/campus/computers/MicrophoneCaptureProcessor.cs").new().InspectPcm16(samples)
 if not stats.get("has_signal",false):stages.text="The recorded sample is silent. Record another sample before testing transcription.";return
 cloud_busy=true;_disable_buttons();toggle.text="Cancel cloud test"
 request_id="microphone_test_%d_%d"%[get_instance_id(),generation]
 stages.text="Capture: received · Transcription: checking the selected sample"
 var result: Dictionary=await game.host_openai.transcribe_wav(preload("res://scripts/campus/academics/teacher_ai.gd").wav_16k(samples),{"request_id":request_id,"purpose":"microphone_diagnostic"})
 samples.clear()
 if not is_inside_tree() or generation!=epoch:return
 request_id=""
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
 request_id="microphone_test_speech_%d_%d"%[get_instance_id(),generation]
 delivery.request_id=request_id
 var audio: Dictionary=await game.host_openai.speak(text,{},delivery.voice,delivery)
 if not is_inside_tree() or generation!=epoch:return
 request_id=""
 if not audio.get("ok",false):stages.text+="\nSpeech generation failed: "+str(audio.get("error","No audio."));_enable_buttons();return
 _stop_preview()
 preview=AudioStreamPlayer.new();preview.bus="NPCSpeech" if AudioServer.get_bus_index("NPCSpeech")>=0 else "Master";preview.stream=preload("res://scripts/campus/voice/audio_voice_mixer.gd").normalise(audio.stream,delivery);add_child(preview)
 stages.text+="\nReply: "+text+"\nPlayback started. Confirm that you can hear it clearly."
 preview.finished.connect(func():
  if is_instance_valid(stages):stages.text+="\nPlayback finished. This checks the service path; test proximity and interruptions in gameplay."
  _stop_preview();_enable_buttons())
 preview.play()

func _play_sample() -> void:
 if last_sample.is_empty():return
 _stop()
 var stream:=AudioStreamWAV.new();stream.format=AudioStreamWAV.FORMAT_16_BITS;stream.mix_rate=16000;stream.stereo=false;stream.data=last_sample
 preview=AudioStreamPlayer.new();preview.stream=stream;preview.bus="Master";add_child(preview)
 note.text="Playing the local microphone sample. Confirm you can hear your recorded words. Nothing was uploaded."
 preview.finished.connect(func():
  if is_instance_valid(note):note.text="Local sample playback finished. Record again or test this sample's transcription."
  _stop_preview())
 preview.play()

func _stop_preview() -> void:
 if is_instance_valid(preview):preview.stop();preview.queue_free()
 preview=null

func _disable_buttons() -> void:
 for button in test_buttons:
  if is_instance_valid(button):button.disabled=true
 if is_instance_valid(record_button):record_button.disabled=true
 if is_instance_valid(play_button):play_button.disabled=true

func _enable_buttons() -> void:
 cloud_busy=false
 for button in test_buttons:
  if is_instance_valid(button):button.disabled=false
 if is_instance_valid(record_button):record_button.disabled=false
 if is_instance_valid(play_button):play_button.disabled=last_sample.is_empty()
 if is_instance_valid(toggle):toggle.text="Start microphone test"

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
 if invalidate:
  epoch+=1
  if not request_id.is_empty() and is_instance_valid(game):game.host_openai.cancel_speech_request(request_id)
  request_id=""
  _stop_preview()
 set_process(false);running=false;cloud_kind="";test_audio.clear()
 if is_instance_valid(microphone):
  microphone.subscribe("meter_"+str(get_instance_id()),false)
  if microphone.packet_ready.is_connected(_packet):microphone.packet_ready.disconnect(_packet)
 player=null;capture=null
 if is_instance_valid(toggle):toggle.text="Start microphone test"
 if is_instance_valid(meter):meter.value=0
 if is_instance_valid(note):note.text="Microphone off. The level test sends no audio."
 if invalidate:_enable_buttons()

func _exit_tree() -> void:
 _stop();last_sample.clear();sample_stats.clear()
