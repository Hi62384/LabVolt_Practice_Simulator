extends SceneTree
func _initialize():call_deferred("run")
func run():
 var capture=AudioEffectCapture.new();capture.buffer_length=1.;AudioServer.add_bus_effect(0,capture)
 var camera=Camera3D.new();root.add_child(camera);camera.position=Vector3(0,0,1);camera.make_current()
 var audio=load("res://scripts/circuit_audio.gd").new();root.add_child(audio)
 var board=load("res://scripts/breadboard_model.gd").empty();board.parts=[{"id":"sound","type":"buzzer","a":"A1","b":"F1"}]
 audio.update_circuit(board,{"i":{"board/sound":.005}})
 await create_timer(.45).timeout
 var frames=capture.get_buffer(capture.get_frames_available());var sum=0.;var crossings=0;var first_cross=-1;var last_cross=-1
 for i in frames.size():
  sum+=frames[i].x*frames[i].x
  if i>0 and frames[i-1].x<0 and frames[i].x>=0:
   crossings+=1;last_cross=i
   if first_cross<0:first_cross=i
 print("CAPTURE ",frames.size()," rms ",sqrt(sum/maxi(1,frames.size()))); if frames.size()<1000 or sqrt(sum/maxi(1,frames.size()))<=.005:quit(1);return
 var hz=float(crossings)*AudioServer.get_mix_rate()/frames.size()
 var periods_hz=float(crossings-1)*AudioServer.get_mix_rate()/maxi(1,last_cross-first_cross)
 print("WHOLE WINDOW ",hz," PERIODS ",periods_hz," crossings ",crossings," first ",first_cross," last ",last_cross," mix ",AudioServer.get_mix_rate()," driver ",AudioServer.get_driver_name())
 if not (crossings>30 and periods_hz>430 and periods_hz<450):quit(1);return
 audio.update_circuit(board,{"i":{"board/sound":0.}})
 await create_timer(.25).timeout;capture.clear_buffer();await create_timer(.2).timeout
 frames=capture.get_buffer(capture.get_frames_available());sum=0.
 for frame in frames:sum+=frame.x*frame.x
 assert(frames.size()>1000 and sqrt(sum/frames.size())<.00001)
 AudioServer.remove_bus_effect(0,AudioServer.get_bus_effect_count(0)-1)
 audio.queue_free();await process_frame
 print("PASS: actual audio bus produces powered buzzer waveform and silence with no drive")
 quit()

