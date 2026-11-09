extends SceneTree
func _initialize():call_deferred("run")
func run():
 var capture=AudioEffectCapture.new();capture.buffer_length=1.;AudioServer.add_bus_effect(0,capture)
 var camera=Camera3D.new();root.add_child(camera);camera.position=Vector3(0,0,1);camera.make_current()
 var audio=load("res://scripts/circuit_audio.gd").new();root.add_child(audio)
 var board=load("res://scripts/breadboard_model.gd").empty();board.parts=[{"id":"sound","type":"speaker","a":"A1","b":"F1"}]
 for block in 5:
  var samples=[]
  for i in 200:
   var t=(block*200+i)*.0005;samples.append([t,sin(TAU*100*t)])
  audio.update_circuit(board,{"audio":{"board/sound":samples}})
  await create_timer(.1).timeout
 var frames=capture.get_buffer(capture.get_frames_available());var sum=0.;var crossings=0;var crossing_frames: Array=[];var armed := false
 for i in frames.size():
  sum+=frames[i].x*frames[i].x
  if frames[i].x< -.002:armed=true
  if armed and frames[i].x>.002:crossings+=1;crossing_frames.append(i);armed=false
 print("CAPTURE ",frames.size()," rms ",sqrt(sum/maxi(1,frames.size()))); if frames.size()<1000 or sqrt(sum/maxi(1,frames.size()))<=.005:quit(1);return
 # Render/network gaps are silence, not slower waveform periods.
 var periods: Array=[]
 for i in range(1,crossing_frames.size()):periods.append(crossing_frames[i]-crossing_frames[i-1])
 periods.sort()
 var hz=AudioServer.get_mix_rate()/float(periods[periods.size()/2]) if periods.size()>0 else 0.
 var valid_periods=periods.filter(func(p):return absf(AudioServer.get_mix_rate()/float(p)-100.)<5.).size()
 if periods.size()<20 or hz<95. or hz>105. or valid_periods<float(periods.size())*.8:
  push_error("Expected 100 Hz actual waveform periods; measured "+str(hz));quit(1);return
 audio.update_circuit(board,{"i":{"board/sound":0.}})
 await create_timer(.25).timeout;capture.clear_buffer();await create_timer(.2).timeout
 frames=capture.get_buffer(capture.get_frames_available());sum=0.
 for frame in frames:sum+=frame.x*frame.x
 assert(frames.size()>1000 and sqrt(sum/frames.size())<.00001)
 AudioServer.remove_bus_effect(0,AudioServer.get_bus_effect_count(0)-1)
 audio.queue_free();await process_frame
 print("PASS: actual audio bus produces passive speaker waveform and silence with no drive")
 quit()


