extends SceneTree
## Synthetic audio exercises the real AudioServer bus/capture/C# processing
## path. This is deliberately NOT a physical microphone or permission test.
const Capture=preload("res://scripts/campus/voice/microphone_capture.gd")
const Activity=preload("res://scripts/campus/computers/TeacherVoiceActivity.cs")
var packets:=0
var pcm_bytes:=0
var peak_rms:=0.0
func _initialize() -> void:run.call_deferred()
func run() -> void:
 var mic: Node=Capture.shared(root)
 mic.configure({"microphone_device":"Default","microphone_mode":"manual","microphone_muted":false,"teacher_mic_sensitivity":1.0})
 assert(mic._device_available("Default"))
 mic.subscribe("manual_test",true)
 mic.subscribe("meter_test",true)
 var device: AudioStreamPlayer=mic.player
 assert(is_instance_valid(device) and mic.is_active())
 assert(not AudioServer.is_bus_mute(AudioServer.get_bus_index(Capture.BUS)))
 assert(is_zero_approx(AudioServer.get_bus_volume_db(AudioServer.get_bus_index(Capture.BUS))))
 assert(AudioServer.is_bus_mute(AudioServer.get_bus_index(Capture.SINK)))
 device.stop()
 var stream:=AudioStreamGenerator.new();stream.mix_rate=48000;stream.buffer_length=.5
 device.stream=stream;device.play()
 mic.packet_ready.connect(func(pcm: PackedByteArray,data: Dictionary):packets+=1;pcm_bytes+=pcm.size();peak_rms=maxf(peak_rms,float(data.get("rms",0.0))))
 var generator: AudioStreamGeneratorPlayback=device.get_stream_playback()
 # Real gameplay settings pause the tree. This synthetic source exercises
 # the same audio effect and drain while paused (not a physical mic test).
 paused=true
 await process_frame
 assert(mic.can_process() and device.can_process(),"The meter source must remain active while singleplayer is paused")
 for block in 25:
  var frames:=PackedVector2Array();frames.resize(1920)
  for i in frames.size():
   var value:=sin(float(block*1920+i)*TAU*220.0/48000.0)*.08
   frames[i]=Vector2(value,value)
  generator.push_buffer(frames)
  await create_timer(.04).timeout
 assert(packets>10 and pcm_bytes>6400 and peak_rms>.01,"Actual capture effects must preserve microphone amplitude while settings pause gameplay")
 paused=false
 await process_frame
 var before:=int(mic.diagnostic.frames_received)
 mic.subscribe("meter_test",false)
 assert(mic.player==device and mic.is_active() and mic.consumers.has("manual_test"))
 assert(int(mic.diagnostic.frames_received)==before,"Closing another consumer must not clear recording state")
 var preferences: Dictionary=mic.preferences.duplicate();preferences.teacher_mic_sensitivity=1.5
 mic.configure(preferences)
 assert(mic.player==device and int(mic.diagnostic.frames_received)==before,"Sensitivity changes must not restart a valid recording")
 mic.drain_pending()
 mic.subscribe("manual_test",false)
 assert(not mic.is_active())
 # One brief onset must emit a final discard; otherwise an NPC stays paused.
 var vad=Activity.new();var packet:=PackedByteArray();packet.resize(640)
 var onset:=false
 for index in 3:onset=bool(vad.PushPcm(packet,true).get("onset",false)) or onset
 assert(onset)
 var discarded: Dictionary=vad.Flush()
 assert(discarded.get("discarded",false) and discarded.has("audio") and discarded.audio.is_empty() and not discarded.continued)
 # A 1.98-second normal pause remains one turn, then ends at two seconds.
 for index in 12:vad.PushPcm(packet,true)
 for index in 99:assert(not vad.PushPcm(packet,false).has("audio"))
 var ended: Dictionary=vad.PushPcm(packet,false)
 assert(ended.has("audio") and not ended.continued and not ended.audio.is_empty())
 mic.queue_free();await process_frame
 print("MICROPHONE_CAPTURE_LIFECYCLE PASS (synthetic audio through real bus, independent consumers, two-second silence and short-onset recovery)")
 quit(0)
