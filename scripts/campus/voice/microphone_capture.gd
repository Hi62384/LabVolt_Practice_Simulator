extends Node
## The only device/buffer owner. Every consumer receives its own packet signal;
## closing a meter or releasing PTT cannot clear another consumer's recording.
signal packet_ready(pcm: PackedByteArray, activity: Dictionary)
signal speech_started(turn_id: int)
signal speech_segment(pcm: PackedByteArray, final: bool, turn_id: int, index: int)
signal state_changed
const RATE := 16000
const PACKET_BYTES := 640
const BUS := "SharedMicrophoneCapture"
const SINK := "MicrophoneMonitorSilent"
const Processor = preload("res://scripts/campus/computers/MicrophoneCaptureProcessor.cs")
const Activity = preload("res://scripts/campus/computers/TeacherVoiceActivity.cs")
var processor = Processor.new()
var activity = Activity.new()
var consumers: Dictionary = {}
var capture: AudioEffectCapture
var player: AudioStreamPlayer
var pending := PackedByteArray()
var preferences: Dictionary = {}
var diagnostic: Dictionary = {"active": false, "rms": 0.0, "speech": false, "noise_floor": 0.0, "frames_received": 0, "pcm_bytes": 0, "discarded_frames": 0, "stage": "off", "echo_cancellation": "unavailable", "reason": "Microphone is off."}
var device_refresh := 0.0
var device_missing := false
var started_at := 0
var last_frame_at := 0
var owned_buses: Array[String] = []
var draining := false
var capture_epoch := 0

static func shared(owner: Node) -> Node:
 var service := owner.get_tree().root.get_node_or_null("MicrophoneCapture")
 if service == null:
  service = load("res://scripts/campus/voice/microphone_capture.gd").new()
  service.name = "MicrophoneCapture"
  owner.get_tree().root.add_child(service)
 return service

func configure(values: Dictionary) -> void:
 preferences = values.duplicate()
 var desired := str(preferences.get("microphone_device", "Default")).strip_edges()
 if desired.is_empty():desired = "Default"
 preferences.microphone_device = desired
 # Default is the platform's alias, not necessarily an enumerated device name.
 device_missing = not _device_available(desired)
 if not device_missing and AudioServer.input_device != desired:
  _stop_device(false)
  AudioServer.input_device = desired
 _sync_device()

func _device_available(device: String) -> bool:
 return device == "Default" or device in AudioServer.get_input_device_list()

func subscribe(consumer: String, enabled: bool) -> void:
 if consumer.is_empty():return
 if enabled: consumers[consumer] = true
 else: consumers.erase(consumer)
 diagnostic.consumers = consumers.keys()
 _sync_device()

func is_active() -> bool:
 return is_instance_valid(player) and player.playing

func _ensure_bus(name: String) -> int:
 var index := AudioServer.get_bus_index(name)
 if index < 0:
  AudioServer.add_bus()
  index = AudioServer.bus_count - 1
  AudioServer.set_bus_name(index,name)
  owned_buses.append(name)
 return index

func _sync_device() -> void:
 var muted: bool = bool(preferences.get("microphone_muted",false)) or preferences.get("microphone_mode","push_to_talk") == "muted"
 var input_enabled: bool = bool(ProjectSettings.get_setting("audio/driver/enable_input",false))
 if consumers.is_empty() or muted or device_missing or not input_enabled:
  _stop_device(false)
  diagnostic.stage = "unavailable" if device_missing or not input_enabled else "off"
  diagnostic.reason = "Godot microphone input is disabled. Enable audio input and restart the game." if not input_enabled else ("Selected microphone is unavailable. Choose an available input device." if device_missing else ("Microphone is muted." if muted else "Microphone is off."))
  state_changed.emit()
  return
 if is_active(): return
 # Capture stays at unity gain and enabled. A separate downstream muted bus
 # prevents local monitoring without suppressing input before the capture effect.
 var sink := _ensure_bus(SINK)
 var bus := _ensure_bus(BUS)
 if sink > bus:
  AudioServer.move_bus(sink,bus)
  sink=AudioServer.get_bus_index(SINK);bus=AudioServer.get_bus_index(BUS)
 AudioServer.set_bus_send(sink,"Master")
 AudioServer.set_bus_mute(sink,true)
 AudioServer.set_bus_volume_db(bus,0.0)
 AudioServer.set_bus_mute(bus,false)
 AudioServer.set_bus_bypass_effects(bus,false)
 AudioServer.set_bus_send(bus,SINK)
 capture=null
 for index in AudioServer.get_bus_effect_count(bus):
  if AudioServer.get_bus_effect(bus,index) is AudioEffectCapture:
   capture=AudioServer.get_bus_effect(bus,index)
   AudioServer.set_bus_effect_enabled(bus,index,true)
   break
 if capture == null:
  capture=AudioEffectCapture.new();capture.buffer_length=1.0
  AudioServer.add_bus_effect(bus,capture)
 if not is_instance_valid(player):
  player=AudioStreamPlayer.new();player.name="SharedInputDevice";player.stream=AudioStreamMicrophone.new();add_child(player)
 player.bus=BUS;player.volume_db=0.0
 capture.clear_buffer();pending.clear();processor.Reset();activity.Reset();capture_epoch+=1
 started_at=Time.get_ticks_msec();last_frame_at=0
 diagnostic.merge({"frames_received":0,"pcm_bytes":0,"discarded_frames":0,"speech":false,"rms":0.0,"peak":0.0,"stage":"starting","reason":"Starting microphone capture…","input_device":AudioServer.input_device,"capture_epoch":capture_epoch,"initialization_ms":0,"first_frame_ms":-1},true)
 player.play()
 diagnostic.active=is_active()
 if not diagnostic.active:diagnostic.stage="failed";diagnostic.reason="The microphone stream could not start. Check the input device and Windows microphone permissions."
 state_changed.emit()

func _stop_device(flush: bool) -> void:
 if flush and is_active():finish_turn()
 if is_instance_valid(player):player.stop()
 if capture != null:capture.clear_buffer()
 pending.clear();processor.Reset();activity.Reset()
 diagnostic.active=false;diagnostic.rms=0.0;diagnostic.speech=false
 state_changed.emit()

func drain_pending() -> void:
 # Used before a manual stop/PTT release: consume the final queued device frames
 # and partial PCM packet while the recording consumer is still subscribed.
 _drain_capture()
 if not pending.is_empty():
  var tail:=pending;pending=PackedByteArray()
  packet_ready.emit(tail,diagnostic.duplicate())
  _emit_activity(activity.PushPcm(tail,bool(diagnostic.get("speech",false))))

func finish_turn() -> void:
 drain_pending()
 _emit_activity(activity.Flush())

func reset_turn() -> void:
 # Reset segmentation only; packet recording and other subscribers continue.
 activity.Reset()

func begin_explicit_turn() -> void:
 # A deliberate PTT press defines an utterance, even when quiet speech does
 # not cross the automatic VAD threshold. Release ends it, not a quiet pause.
 _drain_capture()
 _emit_activity(activity.BeginExplicitTurn())

func _process(delta: float) -> void:
 device_refresh += delta
 if device_refresh >= 1.0:
  device_refresh=0.0
  var missing:=not _device_available(str(preferences.get("microphone_device","Default")))
  if missing != device_missing:
   device_missing=missing;_sync_device()
  elif not consumers.is_empty() and not is_active():_sync_device()
 if not is_active() or capture == null:return
 _drain_capture()
 var now:=Time.get_ticks_msec()
 if now-maxi(started_at,last_frame_at)>2000:
  diagnostic.stage="no_frames"
  diagnostic.reason="The microphone stream started but no audio frames arrived. Check Windows microphone permission, input device, and the Mono game build."
 elif diagnostic.get("frames_received",0)>0 and diagnostic.get("peak",0.0)<.00001:
  diagnostic.reason="Audio frames are arriving, but the input is silent. Check the microphone's hardware mute and input level."

func _drain_capture() -> void:
 if draining or not is_active() or capture == null:return
 draining=true
 var rate:=AudioServer.get_mix_rate()
 # Work in 20 ms blocks so VAD is not one average for a long render frame.
 # The one-second capture ring bounds work while allowing slow frames to catch up.
 var block:=maxi(1,int(rate*.02))
 var available:=capture.get_frames_available()
 diagnostic.discarded_frames=capture.get_discarded_frames()
 while available>0:
  var count:=mini(available,block)
  var frames:=capture.get_buffer(count)
  if frames.is_empty():break
  last_frame_at=Time.get_ticks_msec()
  if int(diagnostic.get("first_frame_ms",-1))<0:
   diagnostic.first_frame_ms=last_frame_at
   diagnostic.initialization_ms=last_frame_at-started_at
  diagnostic.frames_received=int(diagnostic.frames_received)+frames.size()
  diagnostic.last_frame_ms=last_frame_at
  var processed: Dictionary=processor.Process(frames,rate,float(preferences.get("teacher_mic_sensitivity",1.0)),bool(preferences.get("microphone_noise_gate",true)))
  if processed.has("pcm"):
   diagnostic.merge(processed,true);diagnostic.erase("pcm")
   diagnostic.stage="speech_detected" if processed.get("speech",false) else "frames_received"
   diagnostic.reason="Speech detected locally." if processed.get("speech",false) else "Receiving microphone audio locally."
   diagnostic.pcm_bytes=int(diagnostic.pcm_bytes)+processed.pcm.size()
   pending.append_array(processed.pcm)
   while pending.size()>=PACKET_BYTES:
    var pcm:=pending.slice(0,PACKET_BYTES);pending=pending.slice(PACKET_BYTES)
    packet_ready.emit(pcm,diagnostic.duplicate())
    _emit_activity(activity.PushPcm(pcm,bool(processed.speech)))
  # Signals may close a consumer or stop the last active device.
  if not is_active():break
  available-=count
 draining=false

func _emit_activity(result: Dictionary) -> void:
 if result.get("onset",false):speech_started.emit(int(result.turn_id))
 if result.has("audio"):
  speech_segment.emit(result.audio,not bool(result.get("continued",false)),int(result.turn_id),int(result.get("segment",0)))

func _exit_tree() -> void:
 _stop_device(false)
 for bus in [BUS,SINK]:
  if bus not in owned_buses:continue
  var index:=AudioServer.get_bus_index(bus)
  if index>0:AudioServer.remove_bus(index)
