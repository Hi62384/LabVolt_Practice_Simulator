extends Node
## One owner drains the input device. Subscribers never consume its capture buffer.
signal packet_ready(pcm: PackedByteArray, activity: Dictionary)
signal speech_started(turn_id: int)
signal speech_segment(pcm: PackedByteArray, final: bool, turn_id: int, index: int)
signal state_changed
const RATE := 16000
const PACKET_BYTES := 640
const BUS := "SharedMicrophoneCapture"
const Processor = preload("res://scripts/campus/computers/MicrophoneCaptureProcessor.cs")
const Activity = preload("res://scripts/campus/computers/TeacherVoiceActivity.cs")
var processor = Processor.new()
var activity = Activity.new()
var consumers: Dictionary = {}
var capture: AudioEffectCapture
var player: AudioStreamPlayer
var pending := PackedByteArray()
var preferences: Dictionary = {}
var diagnostic: Dictionary = {"active": false, "rms": 0.0, "speech": false, "noise_floor": 0.0, "echo_cancellation": "unavailable", "reason": "Microphone is off."}
var device_refresh := 0.0
var device_missing := false

static func shared(owner: Node) -> Node:
 var service := owner.get_tree().root.get_node_or_null("MicrophoneCapture")
 if service == null:
  service = load("res://scripts/campus/voice/microphone_capture.gd").new()
  service.name = "MicrophoneCapture"
  owner.get_tree().root.add_child(service)
 return service

func configure(values: Dictionary) -> void:
 preferences = values.duplicate()
 var desired := str(preferences.get("microphone_device", "Default"))
 device_missing = desired not in AudioServer.get_input_device_list()
 if not device_missing and AudioServer.input_device != desired:
  _stop_device(false)
  AudioServer.input_device = desired
  processor.Reset(); activity.Reset()
 _sync_device()

func subscribe(consumer: String, enabled: bool) -> void:
 if enabled: consumers[consumer] = true
 else: consumers.erase(consumer)
 _sync_device()

func is_active() -> bool:
 return is_instance_valid(player) and player.playing

func _sync_device() -> void:
 var allowed: bool = not consumers.is_empty() and not bool(preferences.get("microphone_muted", false)) and preferences.get("microphone_mode","push_to_talk")!="muted" and not device_missing
 if not allowed:
  diagnostic.reason = "Selected microphone is unavailable." if device_missing else ("Microphone is muted." if preferences.get("microphone_muted", false) else "Microphone is off.")
  _stop_device(false)
  return
 if is_active(): return
 var bus := AudioServer.get_bus_index(BUS)
 if bus < 0:
  AudioServer.add_bus(); bus = AudioServer.bus_count - 1
  AudioServer.set_bus_name(bus, BUS); AudioServer.set_bus_send(bus, "Master")
  AudioServer.set_bus_volume_db(bus, -80.0)
  capture = AudioEffectCapture.new(); capture.buffer_length = .6; AudioServer.add_bus_effect(bus, capture)
 elif capture == null:
  for index in AudioServer.get_bus_effect_count(bus):
   if AudioServer.get_bus_effect(bus,index) is AudioEffectCapture: capture = AudioServer.get_bus_effect(bus,index)
 if capture == null:
  capture = AudioEffectCapture.new(); AudioServer.add_bus_effect(bus,capture)
 if player == null:
  player = AudioStreamPlayer.new(); player.bus = BUS; player.stream = AudioStreamMicrophone.new(); add_child(player)
 capture.clear_buffer(); pending.clear(); processor.Reset(); activity.Reset()
 player.play(); diagnostic.active = true; diagnostic.reason = "Listening locally"; state_changed.emit()

func _stop_device(flush: bool) -> void:
 if not is_active(): return
 if flush: _emit_activity(activity.Flush())
 player.stop(); capture.clear_buffer(); pending.clear(); processor.Reset(); activity.Reset()
 diagnostic.active = false; diagnostic.rms = 0.0; diagnostic.speech = false
 state_changed.emit()

func finish_turn() -> void:
 _emit_activity(activity.Flush())

func reset_turn() -> void:
 activity.Reset()

func _process(delta: float) -> void:
 device_refresh += delta
 if device_refresh >= 1.0:
  device_refresh = 0.0
  var missing := str(preferences.get("microphone_device", "Default")) not in AudioServer.get_input_device_list()
  if missing != device_missing:
   device_missing = missing
   _sync_device()
 if not is_active() or capture == null: return
 var count := mini(capture.get_frames_available(), int(AudioServer.get_mix_rate() * .12))
 if count <= 0: return
 var processed: Dictionary = processor.Process(capture.get_buffer(count), AudioServer.get_mix_rate(), float(preferences.get("teacher_mic_sensitivity",1.0)), bool(preferences.get("microphone_noise_gate",true)))
 if not processed.has("pcm"): return
 diagnostic.merge(processed,true); diagnostic.erase("pcm")
 pending.append_array(processed.pcm)
 while pending.size() >= PACKET_BYTES:
  var pcm := pending.slice(0,PACKET_BYTES); pending = pending.slice(PACKET_BYTES)
  packet_ready.emit(pcm,diagnostic.duplicate())
  _emit_activity(activity.PushPcm(pcm,bool(processed.speech)))

func _emit_activity(result: Dictionary) -> void:
 if result.get("onset",false): speech_started.emit(int(result.turn_id))
 if result.has("audio"):
  speech_segment.emit(result.audio,not bool(result.get("continued",false)),int(result.turn_id),int(result.get("segment",0)))

func _exit_tree() -> void:
 _stop_device(false)
 var index := AudioServer.get_bus_index(BUS)
 if index > 0: AudioServer.remove_bus(index)
