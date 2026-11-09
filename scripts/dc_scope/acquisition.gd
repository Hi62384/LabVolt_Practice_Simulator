extends RefCounted
const Settings = preload("res://scripts/dc_scope/settings.gd")
const MAX_RECORD := 2048
const MAX_HISTORY := 4096
var settings := Settings.defaults()
var display: Array=[]
var history: Array=[]
var running := true
var single := false
var armed := false
var pending := false
var trigger_time := NAN
var window_start := 0.0
var capture_end := 0.0
var capture_start := 0.0
var display_trigger := NAN
var truncated := false
var last_time := NAN
var previous_trigger := NAN
var last_crossing := -INF
var next_sample := -INF
var last_publish := -INF
var input_previous: Array=[0.0,0.0]
var ac_previous: Array=[0.0,0.0]
var rejected_rows := 0
var state := "Acquiring"
var input_dt := 0.0
var signature := ""
func configure(raw: Dictionary, rearm := false) -> void:
	var next := Settings.normalize(raw)
	var condition := str([next.timebase,next.source,next.trigger,next.edge,next.trigger_mode,next.pretrigger,next.channels[0].coupling,next.channels[0].attenuation,next.channels[1].coupling,next.channels[1].attenuation])
	if condition!=signature or rearm or (next.running and not running):
		pending=false; previous_trigger=NAN; last_crossing=-INF
		if not is_equal_approx(float(next.timebase),float(settings.timebase)):
			history.clear(); next_sample=-INF
			if not display.is_empty(): window_start=display_trigger-float(next.timebase)*10.0*float(next.pretrigger) if is_finite(display_trigger) else float(display[-1][0])-float(next.timebase)*10.0
	if next.running and not running: history.clear(); next_sample=-INF
	signature=condition; settings=next
	running=settings.running; single=settings.single; armed=(settings.armed or single or settings.trigger_mode=="Normal") and not pending
	if not running: pending=false; state="Stopped"
	elif pending: state="Triggered · acquiring"
	elif armed: state="Waiting for trigger"
	elif not pending: state="Acquiring"
func reset() -> void:
	display.clear(); history.clear(); pending=false; trigger_time=NAN; display_trigger=NAN; truncated=false; last_time=NAN; previous_trigger=NAN; next_sample=-INF; last_publish=-INF; last_crossing=-INF; input_previous=[0.0,0.0]; ac_previous=[0.0,0.0]
func push(raw: Array) -> void:
	if raw.size()<5: rejected_rows+=1; return
	for value in raw.slice(0,5):
		if not Settings.finite_number(value): rejected_rows+=1; return
	var time := float(raw[0])
	if is_finite(last_time) and time<=last_time: rejected_rows+=1; return
	var dt := time-last_time if is_finite(last_time) else 0.0
	var conditioned: Array=[0.0,0.0]
	for channel in 2:
		var input := float(raw[channel+1])
		if dt>0:
			var rc := 1.0/(TAU*Settings.AC_CUTOFF_HZ); var alpha := rc/(rc+dt)
			conditioned[channel]=alpha*(float(ac_previous[channel])+input-float(input_previous[channel]))
		input_previous[channel]=input; ac_previous[channel]=conditioned[channel]
	last_time=time; input_dt=dt
	if not running: return
	var row := raw.slice(0,5); row.append_array(conditioned)
	var span := float(settings.timebase)*10.0
	if dt>span:
		history.clear(); pending=false; previous_trigger=NAN; next_sample=-INF; last_crossing=-INF
	var source: int=settings.source; var channel: Dictionary=settings.channels[source]
	var value := (float(row[source+5]) if channel.coupling=="AC" else float(row[source+1]))*float(channel.attenuation)
	var crossing := false
	if is_finite(previous_trigger) and channel.enabled:
		crossing=(previous_trigger<float(settings.trigger) and value>=float(settings.trigger)) if settings.edge=="Rising" else (previous_trigger>float(settings.trigger) and value<=float(settings.trigger))
	if time>=next_sample or crossing:
		history.append(row.duplicate()); next_sample=time+span/1024.0
		while history.size()>MAX_HISTORY or (history.size()>1 and float(history[0][0])<time-span*2.0): history.pop_front()
	if crossing and not pending:
		var fraction := clampf((float(settings.trigger)-previous_trigger)/(value-previous_trigger),0,1)
		trigger_time=time-dt+dt*fraction; last_crossing=trigger_time
		capture_start=trigger_time-span*float(settings.pretrigger); capture_end=capture_start+span; pending=true; armed=false; state="Triggered · acquiring"
	previous_trigger=value
	if pending and time>=capture_end:
		_publish(capture_start,span,trigger_time); pending=false
		if single: running=false; single=false; armed=false; state="Stopped · single complete"
		else: armed=settings.trigger_mode=="Normal"; state="Triggered"
	elif not pending and not single and settings.trigger_mode=="Auto" and time-last_crossing>span and time-last_publish>=1.0/30.0:
		_publish(time-span,span); state="Auto · untriggered"
	elif not pending and (single or settings.trigger_mode=="Normal"):
		armed=true; state="Waiting for trigger" if channel.enabled else "Trigger source disabled"
func _publish(start: float, span: float, trigger := NAN) -> void:
	var output: Array=[]
	for row in history:
		if float(row[0])>=start and float(row[0])<=start+span: output.append(row.duplicate())
	truncated=output.size()>MAX_RECORD
	if truncated: output=output.slice(output.size()-MAX_RECORD)
	display=output; last_publish=last_time; window_start=start; display_trigger=trigger
func status() -> Dictionary:
	return {"schema":2,"state":state,"running":running,"single":single,"armed":armed,"triggered":is_finite(display_trigger),"trigger_time":display_trigger if is_finite(display_trigger) else null,"window_start":window_start,"span":float(settings.timebase)*10,"input_sample_interval":input_dt,"record_count":display.size(),"ac_cutoff_hz":Settings.AC_CUTOFF_HZ,"rejected_rows":rejected_rows,"truncated":truncated,"warning":"Timebase is finer than actual solver sample spacing" if input_dt>float(settings.timebase) else "Record limit reached; shorten timebase" if truncated else "Partial pretrigger history" if not display.is_empty() and float(display[0][0])-window_start>maxf(input_dt*2,0.000001) else ""}
