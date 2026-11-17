extends SceneTree
var samples: Array[float]=[]
func _initialize() -> void: call_deferred("run")
func run() -> void:
 if DisplayServer.get_name()=="headless": printerr("Rendering unavailable");quit(2);return
 DisplayServer.window_set_size(Vector2i(1920,1080))
 DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
 Engine.max_fps=0
 var game=load("res://scenes/Main.tscn").instantiate()
 var trace: Node=null
 if "--trace-spans" in OS.get_cmdline_user_args():
  trace=preload("res://scripts/campus/performance/hitch_trace.gd").new();root.add_child(trace)
  game.set_meta("campus_hitch_trace",trace)
 root.add_child(game)
 game.front.entered()
 # Gameplay initialization can restore saved display settings. Apply the
 # diagnostic override after entering the game so this sample is uncapped.
 DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
 Engine.max_fps=0
 var reactive_circuit: bool="--ac-rlc" in OS.get_cmdline_user_args()
 var two_diodes: bool="--ac-two-diodes" in OS.get_cmdline_user_args()
 var diode_circuit: bool="--ac-diode" in OS.get_cmdline_user_args() or two_diodes
 var daq_circuit: bool="--ac-daq" in OS.get_cmdline_user_args() or reactive_circuit or diode_circuit
 var linked_circuit: bool="--ac-linked" in OS.get_cmdline_user_args() or daq_circuit
 var circuit_start_usec:=0;var circuit_start_sim:=0.0
 if linked_circuit:
  var lab=game.session.labs[0]
  var dc=game.dc_lab
  if "--no-fast-ac" in OS.get_cmdline_user_args():dc.benches[0].fast_linear_ac_enabled=false
  dc.external_links=[
   {"a":{"station":0,"port":"R1a"},"b":{"station":dc.AC_OFFSET,"port":"PV_A"}},
   {"a":{"station":0,"port":"R1b"},"b":{"station":dc.AC_OFFSET,"port":"PV_N"}}
  ]
  if diode_circuit:
   dc.benches[0].wires.append(["R1b","Da"])
   dc.external_links[1].a.port="Db"
  if two_diodes:
   dc.benches[0].board=preload("res://scripts/breadboard_model.gd").empty()
   dc.benches[0].board.ports=["A1","A2","F1","F2"]
   dc.benches[0].board.parts=[{"id":"led","type":"led","a":"A1","b":"A2"}]
   dc.benches[0].wires.append(["Db","B1"])
   dc.external_links[1].a.port="B2"
  if daq_circuit:
   dc.external_links[0].b.port="DAQ_I0_4"
   var pairs=[["DAQ_I0_N","PV_A"],["DAQ_E0_P","PV_A"],["DAQ_E0_N","PV_N"]]
   if reactive_circuit:
    lab.switches.L[0]=true;lab.switches.C[0]=true
    pairs.append_array([["L0_P","PV_A"],["L0_N","PV_N"],["C0_P","PV_A"],["C0_N","PV_N"]])
   for pair in pairs:
    lab.cables.append({"id":lab.next_id,"a":pair[0],"b":pair[1],"owner":0,"creator":1,"color":0})
    lab.next_id+=1
  lab.level=.1
  lab.powered=true
  lab.recalculate()
  dc.refresh_link_flags()
  dc.broadcast()
  circuit_start_usec=Time.get_ticks_usec();circuit_start_sim=dc.ac_bridges[0].solver.time
 var no_lights: bool="--lights-off" in OS.get_cmdline_user_args()
 if no_lights:
  for light in game.find_children("*","Light3D",true,false):
   if light is DirectionalLight3D: light.shadow_enabled=false
   else: light.visible=false
 game.player.enabled=false
 game.player.global_position=Vector3(13,0,25.0)
 var args:=OS.get_cmdline_user_args()
 for arg in args:
  if arg.begins_with("--simulation-budget="):
   game.dc_lab.simulation_budget_usec=clampi(int(arg.trim_prefix("--simulation-budget=")),1000,10000)
  if arg.begins_with("--position="):
   var xyz:=arg.trim_prefix("--position=").split(",")
   if xyz.size()==3:game.player.global_position=Vector3(float(xyz[0]),float(xyz[1]),float(xyz[2]))
  if arg.begins_with("--yaw="):
   game.player.rotation.y=float(arg.trim_prefix("--yaw="));game.player.yaw_target=game.player.rotation.y
  if arg.begins_with("--pitch="):
   game.player.eyes.rotation.x=float(arg.trim_prefix("--pitch="));game.player.pitch_target=game.player.eyes.rotation.x
 if "--chat-sample" in args:game.text_chat._received(1,"Student","Hey! See you in the lab.")
 if "--bubble-sample" in args:
  game.session.roster[2]={"name":"Alex","ready":false}
  var pose:={"position":game.player.global_position+Vector3(0,0,-4),"yaw":0.0,"pitch":0.0,"crouch":false,"seated":false}
  game.session.poses[2]=pose;game._receive_pose(2,pose)
  game.text_chat._received(2,"Alex","Hey! See you in the lab.")
  game.text_chat._received(2,"Alex","Let us get started.")
 game.camera.current=true
 game.campus.set_viewer_position(game.player.global_position)
 Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
 await create_timer(5.0).timeout
 await RenderingServer.frame_post_draw
 var img=root.get_texture().get_image()
 if not no_lights:img.save_png("res://.godot/user_visual_probe.png")
 var begin=Time.get_ticks_usec()
 var sample_start_sim: float=game.dc_lab.ac_bridges[0].solver.time if linked_circuit else 0.0
 if trace!=null:trace.phase="sample"
 var previous=begin
 while Time.get_ticks_usec()-begin<7000000:
  await process_frame
  var now=Time.get_ticks_usec()
  samples.append((now-previous)/1000.0);previous=now
 samples.sort()
 var total:=0.0
 for ms in samples:total+=ms
 var mean:=total/maxi(samples.size(),1)
 print("RENDER_PROBE linked_circuit=%s lights_off=%s process_ms=%.2f physics_ms=%.2f adapter=%s renderer=%s size=%s vsync=%d frames=%d mean_ms=%.2f mean_fps=%.1f p95_ms=%.2f" % [str(linked_circuit),str(no_lights),Performance.get_monitor(Performance.TIME_PROCESS)*1000.0,Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)*1000.0,RenderingServer.get_video_adapter_name(),RenderingServer.get_current_rendering_method(),str(root.size),DisplayServer.window_get_vsync_mode(),samples.size(),mean,1000.0/maxf(mean,.001),samples[mini(samples.size()-1,int(samples.size()*.95))]])
 if linked_circuit:
  var lab=game.session.labs[0]
  var elapsed_wall: float=(Time.get_ticks_usec()-circuit_start_usec)/1000000.0
  var elapsed_sim: float=game.dc_lab.ac_bridges[0].solver.time-circuit_start_sim
  var sample_wall: float=(Time.get_ticks_usec()-begin)/1000000.0
  var sample_sim: float=game.dc_lab.ac_bridges[0].solver.time-sample_start_sim
  print("LINKED_CIRCUIT rlc=%s diode=%s two_diodes=%s daq=%s powered=%s wall_seconds=%.4f simulated_seconds=%.4f overall_rate=%.3f sample_wall=%.4f sample_sim=%.4f sample_rate=%.3f supply_rms=%s daq_v=%s daq_i=%s" % [str(reactive_circuit),str(diode_circuit),str(two_diodes),str(daq_circuit),str(lab.powered),elapsed_wall,elapsed_sim,elapsed_sim/maxf(elapsed_wall,.001),sample_wall,sample_sim,sample_sim/maxf(sample_wall,.001),str(lab.readings.get("external_supply_rms",{})),str(lab.readings.daq_v[0]),str(lab.readings.daq_i[0])])
 if trace!=null:
  trace.stop()
  var sums:={};var counts:={}
  for span in trace.report().spans:
   if span.phase!="sample":continue
   sums[span.label]=int(sums.get(span.label,0))+int(span.duration_usec)
   counts[span.label]=int(counts.get(span.label,0))+1
  for label in sums:print("RENDER_SPAN %s mean_ms=%.3f samples=%d"%[label,float(sums[label])/float(counts[label])/1000.0,counts[label]])
 quit()
