extends SceneTree
## Opt-in production-path acceptance. A recorded fixture replaces ONLY the
## microphone's audio source: it still traverses the AudioServer capture bus,
## native resampler, PTT turn, authoritative NPC queue, provider, memory and player.
## Physical capture and human-audible voice quality are reported separately.
const Capture=preload("res://scripts/campus/voice/microphone_capture.gd")
const Processor=preload("res://scripts/campus/computers/MicrophoneCaptureProcessor.cs")
const Client=preload("res://scripts/campus/ai/host_openai_client.gd")
const Player=preload("res://scripts/campus/academics/teacher_speech_player.gd")
const TeacherAI=preload("res://scripts/campus/academics/teacher_ai.gd")
const FIXTURES="res://tests/campus/academics/voice_fixtures/"
var game: Node
var mic: Node
var panel: Label
var samples:=PackedByteArray()
var collecting:=false
var playback: Array[Dictionary]=[]
var endings: Dictionary={}
var report: Dictionary={"kind":"production voice acceptance","status":"unverified","provider_requests":false,"physical_microphone":false,"audible_output_verified":false,"character_quality":"manual review required","limitations":[],"turns":[]}
var source:="fixtures"
var teacher:="mr_bro"
var room:="ac_lab"
var capture_only:=false
var stt_only:=false
var finished:=false
var fixture_provider:=false

func _initialize() -> void:run.call_deferred()
func _process(_delta: float) -> bool:
 if is_instance_valid(game):
  for record: Dictionary in playback:
   var active: Dictionary=game.faculty.speech_player.active.get(record.channel,{})
   if int(active.get("serial",-1))!=int(record.serial):continue
   var output: AudioStreamPlayer3D=active.get("player")
   if is_instance_valid(output):record.max_playback_seconds=maxf(float(record.max_playback_seconds),output.get_playback_position())
 return false

func message(text: String) -> void:
 print("VOICE_ACCEPTANCE ",text)
 if is_instance_valid(panel):panel.text=text

func wait_for(condition: Callable,seconds: float) -> bool:
 var until:=Time.get_ticks_msec()+int(seconds*1000.)
 while Time.get_ticks_msec()<until:
  if condition.call():return true
  await process_frame
 return false

func _packet(pcm: PackedByteArray,_activity: Dictionary) -> void:
 if collecting and samples.size()+pcm.size()<=5760000:samples.append_array(pcm)

func _playback_started(channel: String,serial: int,at_ms: int) -> void:
 if channel!=room:return
 var speech: Node=game.faculty.speech_player
 var active: Dictionary=speech.active.get(channel,{})
 var stream: AudioStreamWAV=active.get("item",{}).get("stream")
 var stats: Dictionary=Processor.new().InspectPcm16(stream.data) if stream!=null else {}
 playback.append({"channel":channel,"serial":serial,"started_ms":at_ms,"valid_audio":Player.valid_stream(stream),"non_silent_audio":stats.get("has_signal",false),"audio_bytes":stream.data.size() if stream!=null else 0,"audio_rate":stream.mix_rate if stream!=null else 0,"subtitles_present":speech.subtitles.has(channel) and speech.subtitle_layer.visible,"max_playback_seconds":0.})

func _utterance_finished(channel: String,serial: int,delivered: bool) -> void:
 if channel==room:endings[channel+":"+str(serial)]={"delivered":delivered,"finished_ms":Time.get_ticks_msec()}

func finish(status: String,code: int,limitation: String="") -> void:
 if finished:return
 finished=true
 report.status=status
 if not limitation.is_empty():report.limitations.append(limitation)
 if is_instance_valid(mic):
  collecting=false;mic.subscribe("acceptance_capture",false)
  report.resources_released=not mic.is_active()
 if is_instance_valid(game):
  game.client_preferences.set_option("microphone_muted",true)
  game.faculty.natural_voice.cancel_current()
  report.resources_released=not mic.is_active()
  report.usage=game.host_openai.session_usage.duplicate(true)
  report.request_count=game.host_openai.session_requests
  game.session.leave();game.queue_free()
 await process_frame
 report.resources_released=(not is_instance_valid(mic) or not mic.is_active()) and not is_instance_valid(game)
 var file:=FileAccess.open("user://voice-acceptance.json",FileAccess.WRITE)
 if file!=null:file.store_string(JSON.stringify(report,"  "));file.close()
 message(status+": "+limitation if not limitation.is_empty() else status)
 quit(code)

func run() -> void:
 source=OS.get_environment("LABVOLT_ACCEPTANCE_SOURCE")
 if source.is_empty():source="fixtures"
 capture_only=OS.get_environment("LABVOLT_ACCEPTANCE_CAPTURE_ONLY")=="1"
 stt_only=OS.get_environment("LABVOLT_ACCEPTANCE_STT_ONLY")=="1"
 report.source=source
 report.capture_only=capture_only;report.stt_only=stt_only
 report.input_devices=Array(AudioServer.get_input_device_list());report.output_devices=Array(AudioServer.get_output_device_list())
 report.display=DisplayServer.get_name()
 var fixture_port:=OS.get_environment("LABVOLT_ACCEPTANCE_FIXTURE_PORT")
 fixture_provider=not fixture_port.is_empty()
 report.provider_kind="loopback_fixture" if fixture_provider else "live_provider"
 var load_only:=OS.get_environment("LABVOLT_ACCEPTANCE_LOAD_ONLY")=="1"
 if source not in ["fixtures","microphone"]:finish("configuration_error",1,"Choose fixtures or microphone input.");return
 if not load_only and not capture_only and not fixture_provider and (OS.get_environment("LABVOLT_ACCEPTANCE_LIVE")!="1" or OS.get_environment("OPENAI_API_KEY").is_empty()):
  finish("unavailable",2,"Live STT/NPC/TTS requires explicit --live and an OPENAI_API_KEY in the local process environment. No API requests made.");return
 if source=="microphone" and DisplayServer.get_name()=="headless" and not load_only:
  finish("unavailable",2,"Physical microphone acceptance needs a native window and an enabled audio driver. Headless execution cannot verify it.");return
 game=load("res://scenes/Main.tscn").instantiate();root.add_child(game)
 for index in 4:await process_frame
 game.client_preferences.set_option("microphone_muted",true)
 game.client_preferences.set_option("teacher_automatic_conversation",false)
 mic=game.faculty.shared_microphone
 if load_only:
  assert(game.faculty.shared_microphone==game.voice_chat.microphone and not game.faculty.shared_microphone.is_active())
  finish("load_only_pass",0,"Only production scripts/Main scene loaded. No microphone, provider or audible playback verified.");return
 game.front.singleplayer_page();game.front._start_play(true)
 for index in 3:await process_frame
 game.player.set_physics_process(false);game.voice_chat.set_process(false)
 var wanted:=OS.get_environment("LABVOLT_ACCEPTANCE_TEACHER")
 if not wanted.is_empty():teacher=wanted
 if teacher=="dr_volts":room="dc_lab"
 elif teacher!="mr_bro":finish("configuration_error",1,"This harness supports Mr Bro and Dr Volts. Other characters need a corresponding world target.");return
 report.character=teacher
 game.faculty.current[room]=teacher;game.faculty._sync_lab_teachers()
 for index in 3:await process_frame
 var model: Node3D=game.faculty._model_for_room(room,teacher)
 if not is_instance_valid(model):finish("failed",1,"The requested NPC was not mounted in the world.");return
 game.faculty.lab_routes.erase(room)
 game.player.global_position=model.global_position+Vector3(0,0,1.7)
 game.player.eyes.look_at(model.global_position+Vector3.UP*1.5)
 await physics_frame
 var layer:=CanvasLayer.new();layer.layer=60;game.add_child(layer)
 panel=Label.new();panel.position=Vector2(20,20);panel.size=Vector2(680,160);panel.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;panel.add_theme_color_override("font_color",Color.WHITE);panel.add_theme_color_override("font_outline_color",Color.BLACK);panel.add_theme_constant_override("outline_size",5);layer.add_child(panel)
 var prefs=game.client_preferences
 prefs.set_option("microphone_mode","push_to_talk");prefs.set_option("microphone_echo_mode","headphones")
 prefs.set_option("teacher_mic_detection",false);prefs.set_option("teacher_speech",true);prefs.set_option("teacher_subtitles",true)
 var device:=OS.get_environment("LABVOLT_ACCEPTANCE_DEVICE")
 if not device.is_empty():prefs.set_option("microphone_device",device)
 for key in ["effects","ambience","human_voice","phone_calls","interface"]:prefs.set_option(key,0.)
 prefs.set_option("microphone_muted",false)
 mic=game.faculty.shared_microphone;mic.packet_ready.connect(_packet)
 if not capture_only:
  var client: Node=game.host_openai
  var text_model:=OS.get_environment("LABVOLT_ACCEPTANCE_TEXT_MODEL")
  if text_model.is_empty():text_model=Client.DEFAULT_MODEL
  if client.configure(text_model,768,"",true)!=OK:finish("configuration_error",1,"Unsupported text model or configuration.");return
  client.stt_enabled=true;client.tts_enabled=true
  var stt_model:=OS.get_environment("LABVOLT_ACCEPTANCE_STT_MODEL")
  var tts_model:=OS.get_environment("LABVOLT_ACCEPTANCE_TTS_MODEL")
  if not stt_model.is_empty():client.stt_model=stt_model
  if not tts_model.is_empty():client.tts_model=tts_model
  if fixture_provider:
   if not fixture_port.is_valid_int() or not client.set_local_test_endpoint("http://127.0.0.1:"+fixture_port+"/v1"):
    finish("configuration_error",1,"The local fixture endpoint was rejected. No fallback to a live provider is allowed.");return
   if not client.set_session_key("sk-test-12345678901234567890"):
    finish("configuration_error",1,"The synthetic fixture credential was rejected.");return
   client.stt_model="gpt-4o-mini-transcribe";client.tts_model="gpt-4o-mini-tts"
  report.models={"text":client.model,"stt":client.stt_model,"tts":client.tts_model}
 var manifest: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(FIXTURES+"manifest.json"))
 var count:=clampi(int(OS.get_environment("LABVOLT_ACCEPTANCE_TURNS")),1,3)
 game.faculty.speech_player.playback_started.connect(_playback_started)
 game.faculty.speech_player.utterance_finished.connect(_utterance_finished)
 var identity:=str(game.school.local_identity)
 if not capture_only and not stt_only:prefs.set_option("teacher_automatic_conversation",true)
 for index in count:
  var fixture: Dictionary=manifest.fixtures[index]
  var before: int=game.faculty.brain.recall(teacher,identity).size()
  var playback_before:=playback.size()
  samples.clear();collecting=true
  var record: Dictionary={"index":index+1,"source":source,"expected_text":fixture.text,"started_ms":Time.get_ticks_msec()}
  message("Turn %d: say “%s” after Recording appears. Use headphones."%[index+1,fixture.text])
  await create_timer(1.).timeout
  if capture_only or stt_only:mic.subscribe("acceptance_capture",true)
  else:
   var press:=InputEventKey.new();press.keycode=game.player.keys.voice;press.physical_keycode=game.player.keys.voice;press.pressed=true;Input.parse_input_event(press)
   await process_frame
   game.faculty.natural_voice._process(.25)
  if not mic.is_active():finish("unavailable",2,str(mic.diagnostic.reason));return
  var original_stream: AudioStream=mic.player.stream
  var duration:=clampf(float(OS.get_environment("LABVOLT_ACCEPTANCE_SECONDS")),3.,30.)
  if source=="fixtures":
   var wav:=FileAccess.get_file_as_bytes(FIXTURES+str(fixture.file))
   if not Client.valid_transcription_wav(wav):finish("failed",1,"A checked-in fixture is not canonical PCM16 mono WAV.");return
   var stream:=AudioStreamWAV.new();stream.format=AudioStreamWAV.FORMAT_16_BITS;stream.mix_rate=16000;stream.stereo=false
   var data:=wav.slice(44);data.resize(data.size()+32000);stream.data=data
   mic.player.stop();mic.player.stream=stream;mic.player.play()
   duration=float(fixture.duration_seconds)+.15
  message("Recording turn %d: %s"%[index+1,fixture.text])
  await create_timer(duration).timeout
  mic.drain_pending();collecting=false
  record.capture=Processor.new().InspectPcm16(samples)
  record.capture_device_epoch=mic.capture_epoch
  record.capture_initialization_ms=mic.diagnostic.get("initialization_ms",-1)
  record.capture_frames=mic.diagnostic.get("frames_received",0)
  record.capture_completed_ms=Time.get_ticks_msec()
  if capture_only or stt_only:mic.subscribe("acceptance_capture",false)
  else:
   var release:=InputEventKey.new();release.keycode=game.player.keys.voice;release.physical_keycode=game.player.keys.voice;release.pressed=false;Input.parse_input_event(release)
   await process_frame
   game.faculty.natural_voice._process(.25)
  mic.player.stream=original_stream
  if not record.capture.get("has_signal",false):
   report.turns.append(record);finish("unavailable",2,"No usable microphone waveform was captured. Check selected device, audio driver, permission and input level.");return
  if source=="microphone":report.physical_microphone=true
  if capture_only:
   record.waveform_verified=true;report.turns.append(record);continue
  report.provider_requests=not fixture_provider
  report.fixture_requests=fixture_provider
  if stt_only:
   var result: Dictionary=await game.host_openai.transcribe_wav(TeacherAI.wav_16k(samples),{"request_id":"voice_acceptance_"+str(index),"purpose":"explicit_voice_acceptance"})
   record.stt_ok=result.get("ok",false);record.transcription_measurement=result.get("measurement",{})
   var text:=str(result.get("text",""));record.transcript_sha256=text.sha256_text();record.transcript_matches=_words(text)==_words(fixture.text)
   report.turns.append(record)
   if not record.stt_ok or not record.transcript_matches:finish("failed",1,"The real transcription did not match the known test phrase. Review the input and provider configuration.");return
   continue
  message("Waiting for %s to respond through the production NPC queue…"%teacher)
  if not await wait_for(func():return game.faculty.brain.recall(teacher,identity).size()>before and playback.size()>playback_before,180.):
   record.router=game.faculty.natural_voice.diagnostic.duplicate();report.turns.append(record);finish("failed",1,"The actual NPC response did not reach both persistent memory and audio playback within 180 seconds.");return
  var exchange: Dictionary=game.faculty.brain.recall(teacher,identity).back()
  var transcript:=str(exchange.get("student",""));var response:=str(exchange.get("teacher",""))
  record.transcript_sha256=transcript.sha256_text();record.transcript_matches=_words(transcript)==_words(fixture.text)
  record.response_sha256=response.sha256_text();record.response_characters=response.length()
  record.playback=playback.back();record.finish_to_audio_ms=int(record.playback.started_ms)-int(record.capture_completed_ms)
  var end_key:=room+":"+str(record.playback.serial)
  if not await wait_for(func():return endings.has(end_key),150.):report.turns.append(record);finish("failed",1,"The NPC playback did not finish or release its utterance.");return
  record.playback_end=endings[end_key]
  if index==1:record.memory_followup_matches="copper comet" in _words(response)
  report.turns.append(record)
  if not record.transcript_matches or not record.playback.valid_audio or not record.playback.non_silent_audio or not record.playback.subtitles_present or not record.playback_end.delivered or float(record.playback.max_playback_seconds)<=0.:
   finish("failed",1,"A transcript, valid non-silent audio, subtitle, or complete playback check failed. Human audible quality remains unverified.");return
  if index==1 and not record.memory_followup_matches:finish("failed",1,"The follow-up reply did not retain Copper Comet. Review character memory and response quality.");return
 report.audio_quality="Human listening and teacher/content quality require manual review. Engine playback evidence is present only for complete pipeline turns."
 var status:="capture_pass" if capture_only else ("stt_pass" if stt_only else "pipeline_pass")
 finish(("fixture_" if fixture_provider else "")+status,0)

func _words(text: String) -> String:
 var clean:=RegEx.create_from_string("[^a-z0-9]+")
 return clean.sub(text.to_lower()," ",true).strip_edges()
