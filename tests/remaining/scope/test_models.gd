extends SceneTree
const Settings = preload("res://scripts/dc_scope/settings.gd")
const Measure = preload("res://scripts/dc_scope/measurements.gd")
const Acquisition = preload("res://scripts/dc_scope/acquisition.gd")
var failures := 0
var assertions := 0
func check(ok: bool, message: String) -> void:
	assertions+=1
	if not ok: failures+=1; push_error(message)
func near(actual: float, expected: float, tolerance: float, message: String) -> void:
	check(absf(actual-expected)<=tolerance,message+" actual="+str(actual)+" expected="+str(expected))
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var settings := Settings.normalize({"scale":5.0,"coupling":"AC","attenuation":10.0})
	check(settings.channels[0].scale==5 and settings.channels[1].scale==5,"legacy migration both channels")
	var changed := Settings.change(settings,{"channel":1,"key":"scale","value":0.25})
	check(changed.ok and changed.settings.channels[0].scale==5 and changed.settings.channels[1].scale==0.25,"independent scale")
	check(settings.channels[1].scale==5,"settings action does not alias input")
	check(not Settings.change(settings,{"channel":2,"key":"scale","value":1}).ok,"invalid channel")
	check(not Settings.change(settings,{"key":"scale","value":NAN}).ok,"nonfinite rejected")
	check(not Settings.change(settings,{"key":"running","value":"false"}).ok,"boolean type enforced")
	check(not Settings.change(settings,{"key":"source","value":0.5}).ok,"fractional trigger source rejected")
	var rows: Array=[]
	for i in range(1001):
		var time := i*0.001
		rows.append([time,3.0+2.0*sin(TAU*10*time),-1.0+0.5*cos(TAU*20*time),0.0,0.0])
	settings=Settings.defaults()
	var first := Measure.statistics(rows,0,settings.channels[0])
	near(first.vpp,4,1e-10,"CH1 Vpp")
	near(first.average,3,1e-10,"CH1 average")
	near(first.rms,sqrt(11.0),1e-9,"CH1 RMS")
	near(first.frequency,10,1e-9,"CH1 frequency")
	settings.channels[1].attenuation=10.0
	var second := Measure.statistics(rows,1,settings.channels[1])
	near(second.vpp,10,1e-10,"CH2 independent calibrated Vpp")
	near(second.average,-10,1e-10,"CH2 negative mean")
	near(second.rms,sqrt(112.5),1e-9,"CH2 independent RMS")
	near(second.frequency,20,1e-9,"CH2 independent frequency")
	settings.channels[0].position=1.0; settings.channels[0].scale=1.0
	var point := Measure.point([0.5,2.0,0.5],0,settings.channels[0],0,1,Vector2(500,320))
	near(point.x,250,1e-10,"shared time axis")
	near(point.y,40,1e-10,"channel position and scale")
	near(Measure.statistics(rows,0,settings.channels[0]).average,3,1e-10,"position never changes voltage")
	var capture := Acquisition.new(); settings=Settings.defaults(); settings.source=1; settings.single=true; settings.armed=true; capture.configure(settings,true)
	for i in range(401): capture.push([i*0.001,9.0,-2.0 if i<200 else 2.0,0.0,0.0])
	check(not capture.running and not capture.single,"single stops after posttrigger window")
	near(capture.status().trigger_time,0.1995,1e-9,"CH2 interpolated trigger time")
	near(capture.status().window_start,0.1745,1e-9,"pretrigger alignment")
	check(capture.display.size()>=95 and capture.display.size()<=105,"timebase length not fixed256samples")
	check(capture.display[0][1]==9 and capture.display[0][2]==-2,"independent raw channels preserved")
	var frozen: Array=capture.display.duplicate(true)
	capture.push([0.5,100.0,100.0,0.0,0.0]); check(capture.display==frozen,"stop preserves capture")
	settings.single=false;settings.armed=false;settings.running=true;settings.trigger_mode="Normal";settings.source=0; capture.configure(settings)
	for i in range(501,701): capture.push([i*0.001,9.0,9.0,0.0,0.0])
	check(capture.display==frozen and capture.armed,"normal waits without inventing trigger")
	settings=Settings.defaults();settings.timebase=0.1;settings.channels[0].coupling="AC"
	capture=Acquisition.new(); capture.configure(settings)
	for i in range(7001):
		var time := i*0.001
		capture.push([time,3.0+2.0*sin(TAU*5*time),-4.0,0.0,0.0])
	var ac := Measure.statistics(capture.display,0,settings.channels[0])
	var alpha := (1.0/(TAU*Settings.AC_CUTOFF_HZ))/(1.0/(TAU*Settings.AC_CUTOFF_HZ)+0.001)
	var omega := TAU*5*0.001
	var gain := alpha*sqrt(2.0-2.0*cos(omega))/sqrt(1.0+alpha*alpha-2.0*alpha*cos(omega))
	near(ac.rms,sqrt(2.0)*gain,0.015,"AC RMS independently derived discrete highpass response")
	near(ac.average,0,0.01,"AC removes DC after settling")
	near(ac.dc_offset,3,0.015,"raw DC offset retained separately")
	near(Measure.statistics(capture.display,1,settings.channels[1]).average,-4,1e-9,"other DC channel unaffected by AC coupling")
	check(capture.display.size()<=Acquisition.MAX_RECORD and capture.history.size()<=Acquisition.MAX_HISTORY,"bounded capture history")
	var fall := Acquisition.new(); var fall_settings := Settings.defaults();fall_settings.edge="Falling";fall_settings.source=0;fall_settings.single=true;fall_settings.armed=true;fall.configure(fall_settings,true)
	for i in 400:fall.push([i*.001,2.0 if i<200 else -2.0,8.0,0.0,0.0])
	near(fall.status().trigger_time,.1995,1e-9,"falling edge independent reference")
	var before_zoom: Array=fall.display.duplicate(true);fall_settings.running=false;fall_settings.single=false;fall_settings.timebase=.02;fall.configure(fall_settings)
	near(fall.status().window_start,.1495,1e-9,"stopped timebase zoom retains trigger position")
	check(fall.display==before_zoom,"timebase zoom never rewrites samples")
	var gap := Acquisition.new();var gap_settings := Settings.defaults();gap_settings.single=true;gap_settings.armed=true;gap.configure(gap_settings,true)
	gap.push([0.0,-1.0,2.0,0.0,0.0]);gap.push([1.0,1.0,2.0,0.0,0.0]);gap.push([1.001,1.0,2.0,0.0,0.0])
	check(not gap.pending and gap.single and gap.display.is_empty(),"sampling gap cannot invent a trigger crossing")
	var empty := Measure.statistics([],0,Settings.defaults().channels[0]);check(empty.count==0 and not empty.frequency_valid and is_finite(empty.rms),"empty acquisition has no invalid numeric results")
	var constant := Measure.statistics([[0.0,-3.0,0.0],[1.0,-3.0,0.0]],0,Settings.defaults().channels[0]);near(constant.rms,3,1e-10,"negative DC RMS")
	near(constant.vpp,0,1e-10,"constant DC Vpp")
	var legacy_ac := Measure.statistics([[0.0,0.0,0.0],[1.0,2.0,0.0],[3.0,4.0,0.0]],0,{"coupling":"AC","attenuation":1.0});near(legacy_ac.average,0,1e-9,"legacy irregular AC uses time-weighted DC removal")
	var rejected := capture.rejected_rows;capture.push([NAN,1,2,0,0]);capture.push([0,1,2,0,0]);check(capture.rejected_rows==rejected+2,"invalid/backwards samples rejected")
	settings.channels[1].enabled=false;settings.channels[1].position=-1.5;settings.channels[1].scale=.2;settings.channels[1].attenuation=10
	check(preload("res://scripts/dc_scope/settings_store.gd").persist(1,settings,"user://scope_test.cfg")==OK,"settings saved")
	var restored := preload("res://scripts/dc_scope/settings_store.gd").restore(1,"user://scope_test.cfg")
	check(not restored.channels[1].enabled and restored.channels[1].position==-1.5 and restored.channels[1].scale==.2 and restored.channels[1].attenuation==10,"independent preferences restored")
	check(not restored.single and not restored.armed,"transient arm not replayed from save")
	var probe := preload("res://scripts/dc_scope/probe_connections.gd").describe([["S1","GEN"]])
	check(not probe.reference_connected and not probe.signal_connected[1] and not probe.differential,"probe common-reference/open-lead diagnostics")
	var trace: Control=load("res://scripts/scope_trace.gd").new();root.add_child(trace);trace.size=Vector2(500,320);trace.samples=rows;trace.settings=restored
	check(trace.channel_segments(1).is_empty(),"disabled channel produces no trace segments")
	trace.settings=Settings.defaults();trace.cursor_a=.25;trace.cursor_b=.75;trace.settings.timebase=.1
	near(trace.cursor_readings().dt,.5,1e-10,"waveform time cursors")
	trace.cursor_a=.125;trace.cursor_b=.15;trace.settings.channels[1].attenuation=10.0
	var cursor_values: Dictionary=trace.cursor_readings()
	near(cursor_values.channels[0].dv,-2,1e-9,"CH1 voltage cursor difference")
	near(cursor_values.channels[1].dv,10,1e-8,"CH2 independently calibrated voltage cursors")
	trace.samples=[[0.0,-10.0,0.0],[.25,0.0,0.0],[.5,10.0,0.0],[.75,-10.0,0.0],[1.0,0.0,0.0]];trace.settings=Settings.defaults();trace.settings.timebase=.1;trace.settings.channels[0].scale=1.0
	var clipped: PackedVector2Array=trace.channel_segments(0)
	var bounded := true;var reaches_top := false;var reaches_bottom := false
	for point_in_clip in clipped:
		bounded=bounded and point_in_clip.y>=0 and point_in_clip.y<=trace.size.y
		reaches_top=reaches_top or is_zero_approx(point_in_clip.y);reaches_bottom=reaches_bottom or is_equal_approx(point_in_clip.y,trace.size.y)
	check(bounded and reaches_top and reaches_bottom,"trace crossings clip exactly at plot boundaries")
	trace.samples=[[0.0,20.0,0.0],[1.0,20.0,0.0]]
	check(trace.channel_segments(0).is_empty(),"offscreen waveform is not replaced by a false flat trace")
	near(trace.cursor_readings().channels[0].a,20.0,1e-9,"clipping never clamps cursor voltage readouts")
	trace.queue_free()
	check(load("res://scripts/dc_scope/scope_panel.gd")!=null,"scope panel parses")
	check(load("res://scripts/dc_ui.gd")!=null,"existing DC UI parses")
	print("SCOPE_MODELS_RESULT assertions=",assertions," failures=",failures)
	quit(1 if failures else 0)
