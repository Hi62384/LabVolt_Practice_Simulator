extends SceneTree
var failed := false
func _initialize():call_deferred("run")
func check(ok: bool,message: String):
 if not ok:push_error(message);failed=true
func rms(frames: PackedVector2Array) -> float:
 var sum=0.
 for frame in frames:sum+=frame.x*frame.x
 return sqrt(sum/maxi(1,frames.size()))
func run():
 var audio=load("res://scripts/circuit_audio.gd").new();root.add_child(audio)
 var B=load("res://scripts/breadboard_model.gd");var board=B.empty()
 board.parts=[{"id":"same","type":"buzzer","a":"A1","b":"F1"}]
 audio.update_circuit(board,{"i":{"board/same":.005}})
 var first=audio.voices["board/same"]
 check(first.stream is AudioStreamWAV,"Buzzer must use a mixer-owned tone")
 board.parts[0].type="speaker"
 audio.update_circuit(board,{"audio":{"board/same":[[10.,0.],[10.0005,0.]]}})
 var second=audio.voices["board/same"]
 check(second!=first and first.get_parent()==null,"Replacement must detach old active player immediately")
 check(second.stream is AudioStreamGenerator and audio.queues.has("board/same"),"Same ID speaker must become waveform playback")
 audio.update_circuit(board,{"audio":{"board/same":[[0.,1.],[.0005,-1.]]}})
 check(audio.last_times["board/same"]==.0005,"Speaker reset must accept a new simulation epoch")
 board.parts[0].type="buzzer"
 audio.update_circuit(board,{"i":{"board/same":.005}})
 check(audio.voices["board/same"].stream is AudioStreamWAV,"Same ID must switch back to active oscillator")
 for state in [audio.queues,audio.cursors,audio.last_times,audio.filters,audio.rates]:check(not state.has("board/same"),"Old speaker state must not survive kind change")
 audio.update_circuit(board,{"i":{"board/same":0.}})
 check(audio.voices["board/same"].volume_linear==0.,"Undriven replacement buzzer must be muted")
 audio.update_circuit({},{});check(audio.voices.is_empty() and audio.voice_kinds.is_empty(),"Removal must clear players and kind tracking")
 await process_frame
 check(audio.get_child_count()==0,"No retired audio players may remain parented")
 # Exercise the real bus too when a display/audio device is available.
 if DisplayServer.get_name()!="headless":
  var capture=AudioEffectCapture.new();capture.buffer_length=1.;AudioServer.add_bus_effect(0,capture)
  var camera=Camera3D.new();root.add_child(camera);camera.position=Vector3(0,0,1);camera.make_current()
  board.parts[0].type="buzzer";audio.update_circuit(board,{"i":{"board/same":.005}})
  await create_timer(.35).timeout
  var frames=capture.get_buffer(capture.get_frames_available());print("BUZZER rms ",rms(frames))
  check(frames.size()>1000 and rms(frames)>.005,"Actual replacement buzzer must be audible on bus")
  board.parts[0].type="speaker";audio.update_circuit(board,{"audio":{"board/same":[[0.,0.],[.0005,0.]]}})
  await create_timer(.2).timeout;capture.clear_buffer();await create_timer(.15).timeout
  frames=capture.get_buffer(capture.get_frames_available());print("REPLACED SPEAKER SILENCE rms ",rms(frames))
  check(frames.size()>1000 and rms(frames)<.00001,"Buzzer tone must stop after replacement with undriven speaker")
  board.parts[0].type="buzzer";audio.update_circuit(board,{"i":{"board/same":.005}})
  await create_timer(.2).timeout;capture.clear_buffer();await create_timer(.15).timeout
  frames=capture.get_buffer(capture.get_frames_available())
  check(frames.size()>1000 and rms(frames)>.005,"Speaker-to-buzzer replacement must restore actual output")
  AudioServer.remove_bus_effect(0,AudioServer.get_bus_effect_count(0)-1)
 audio.update_circuit({},{});audio.queue_free();await process_frame
 if not failed:print("PASS: same-ID buzzer/speaker replacement both directions, stream/state cleanup, reset, removal and real-bus tone removal")
 quit(1 if failed else 0)
