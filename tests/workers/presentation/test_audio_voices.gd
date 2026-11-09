extends SceneTree
var failed := false
func _initialize():call_deferred("run")
func check(ok: bool,message: String):
 if not ok:push_error(message);failed=true
func amplitude(frames: PackedVector2Array,hz: float) -> float:
 var re=0.;var im=0.;var rate=AudioServer.get_mix_rate()
 for i in frames.size():
  re+=frames[i].x*cos(TAU*hz*i/rate);im+=frames[i].x*sin(TAU*hz*i/rate)
 return 2.*sqrt(re*re+im*im)/maxi(1,frames.size())
func run():
 print("DRIVER ",AudioServer.get_driver_name()," MIX ",AudioServer.get_mix_rate()," DISPLAY ",DisplayServer.get_name())
 var capture=AudioEffectCapture.new();capture.buffer_length=2.;AudioServer.add_bus_effect(0,capture)
 var camera=Camera3D.new();root.add_child(camera);camera.position=Vector3(0,0,1);camera.make_current()
 var audio=load("res://scripts/circuit_audio.gd").new();root.add_child(audio)
 var board=load("res://scripts/breadboard_model.gd").empty()
 board.parts=[{"id":"a","type":"speaker","a":"A1","b":"F1"},{"id":"b","type":"speaker","a":"A2","b":"F2"},{"id":"c","type":"buzzer","a":"A3","b":"F3"}]
 for block in 16:
  var first=[];var second=[]
  for i in 100:
   var t=(block*100+i)*.0005;first.append([t,sin(TAU*100*t)]);second.append([t,sin(TAU*300*t)])
  var result={"i":{"board/c":.005},"audio":{"board/a":first,"board/b":second}}
  audio.update_circuit(board,result)
  var size=audio.queues["board/a"].size()
  audio.update_circuit(board,result)
  check(audio.queues["board/a"].size()<=size,"Repeated snapshots must not replay samples")
  await create_timer(.05).timeout
 var frames=capture.get_buffer(capture.get_frames_available())
 check(frames.size()>1000,"Audio driver must produce captured frames")
 for hz in [100.,300.,440.]:
  var amp=amplitude(frames,hz);print("TONE ",hz," amplitude ",amp)
  check(amp>(.0015 if hz!=440. else .008),"Missing actual simultaneous bus tone "+str(hz))
 var peak=0.
 for frame in frames:peak=maxf(peak,absf(frame.x))
 check(peak<1.,"Mixed voices must retain headroom")
 # Save the actual captured bus for listening; this is a test artifact, not fidelity evidence.
 var bytes=PackedByteArray();bytes.resize(frames.size()*2)
 for i in frames.size():bytes.encode_s16(i*2,int(clampf(frames[i].x,-1,1)*32767))
 var wav=AudioStreamWAV.new();wav.format=AudioStreamWAV.FORMAT_16_BITS;wav.mix_rate=int(AudioServer.get_mix_rate());wav.data=bytes
 wav.save_to_wav("res://../outputs/audio-bus-review.wav")
 capture.clear_buffer()
 # Stall only this test's main thread. Mixer-owned active tone must continue.
 OS.delay_msec(200)
 var stalled=capture.get_buffer(capture.get_frames_available())
 var stable=amplitude(stalled,440.);print("STALLED MAIN THREAD 440 Hz amplitude ",stable)
 check(stalled.size()>1000 and stable>.02,"Buzzer must survive a 200 ms render/main-thread stall")
 audio.update_circuit(board,{"i":{"board/c":0.}})
 await create_timer(.4).timeout;capture.clear_buffer();await create_timer(.2).timeout
 frames=capture.get_buffer(capture.get_frames_available());var sum=0.
 for frame in frames:sum+=frame.x*frame.x
 var rms=sqrt(sum/maxi(1,frames.size()));print("SILENCE rms ",rms)
 check(frames.size()>1000 and rms<.00001,"Undriven outputs must become silent")
 audio.update_circuit(board,{"audio":{"board/a":[[0.,1.],[.0005,-1.]]}})
 check(audio.last_times["board/a"]==.0005,"Circuit time reset must accept new samples")
 board.parts=[]
 for i in 10:board.parts.append({"id":"voice"+str(i),"type":"buzzer","a":"A1","b":"F1"})
 audio.update_circuit(board,{})
 check(audio.voices.size()==8,"Voice budget must remain bounded at eight")
 audio.update_circuit({},{});check(audio.voices.is_empty(),"Removed circuits must release every voice")
 AudioServer.remove_bus_effect(0,AudioServer.get_bus_effect_count(0)-1);audio.queue_free();await process_frame
 if not failed:print("PASS: actual simultaneous 100/300/440 Hz bus output, deduplication, headroom, silence, reset, cleanup")
 quit(1 if failed else 0)
