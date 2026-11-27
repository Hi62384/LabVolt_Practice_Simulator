extends RefCounted
## A host-only classmate uses the same station commands and solver as a player.
const Instructions=preload("res://scripts/beginner_bench_instructions.gd")
const Digital=preload("res://scripts/campus/academics/classmate_digital_practice.gd")
const ACTOR_ID:=-100
var game: Node
var work: Dictionary={}

func step(activity: Dictionary,now: float) -> void:
	if not work.is_empty() and (activity.get("id","")!=work.class_id or activity.get("phase")!="lesson"):
		finish()
	if activity.get("phase")!="lesson" or activity.get("course") not in ["ELM253","ETY155","DGS266"]:return
	if work.is_empty() and (activity.get("lab_practice_done",false) or not _begin(activity,now)):return
	if now<float(work.next):return
	work.next=now+.55
	var dc: bool=work.domain=="dc"
	var lab: RefCounted=game.dc_lab.benches[work.bench] if dc else game.session.labs[work.bench]
	var member: Dictionary=work.member
	if work.commands.is_empty():
		if work.digital=="digital_scope" and not work.observations.is_empty():
			if not work.has("demonstration_until"):work.demonstration_until=now+18.
			if now<float(work.demonstration_until):return
		var measured: Dictionary={"v":absf(lab.difference("VΩ","COM")),"meter":lab.meter} if dc and lab.result.get("ok",false) else ({} if dc else lab.records)
		var ok:=not measured.is_empty() and float(measured.get("v",0.))>0.
		if not str(work.digital).is_empty():
			var evidence: Array=work.observations.values()
			measured={"samples":evidence,"kind":work.digital}
			var required:=Digital.rows_required(work.digital)
			ok=evidence.size()==required and evidence.all(func(sample):return sample.correct)
		var students: Node=game.lecture_classes.classroom_students
		students.record_practice(member.profile.id,activity.course,ok,activity.week)
		member.action="recorded measurement" if ok else "checking instruments"
		member.next=now+9.
		activity.lab_practice_result=measured.duplicate()
		finish()
		return
	var action: Dictionary=work.commands.pop_front()
	if action.op=="observe":
		var row:=int(action.get("row",0))
		var sample:=Digital.observation(work.digital,lab,row)
		if sample.is_empty():
			var remaining:=int(action.get("attempts",8))-1
			if remaining>0:
				action.attempts=remaining
				work.commands.push_front(action)
		else:work.observations[row]=sample
		member.action=str(action.label)
		return
	var foot: Vector3=work.foot
	var control:=str(action.get("port",action.get("control","")))
	if not dc and not control.is_empty() and lab.positions.has(control):
		var target: Vector3=lab.positions[control]
		foot=Vector3(target.x,foot.y,target.z+.95)
		member.position=foot
	var error: String=lab.apply(action) if dc else lab.act(ACTOR_ID,action,foot)
	if not error.is_empty():
		activity.lab_practice_error="%s (%s)"%[error,action.get("port",action.get("control",action.op))]
		member.action="checking instruments"
		finish()
		return
	if action.op=="board":
		lab.board_owner=ACTOR_ID
		lab.board_position=game.dc_lab.board_home(work.bench)
	member.action=str(action.get("label","wiring circuit"))
	if dc:game.dc_lab.broadcast()
	else:game.session.broadcast()

func _begin(activity: Dictionary,now: float) -> bool:
	var exercise: Dictionary=activity.get("lab_practice",{})
	var dc: bool=activity.course!="ELM253"
	var digital: String=exercise.get("digital","")
	var stations: Array=game.dc_lab.benches if dc else game.session.labs
	var count:=mini(activity.room.benches.size(),stations.size())
	if exercise.is_empty() or count==0:return false
	for bench in range(count-1,-1,-1):
		if activity.students.values().any(func(student):return int(student.get("bench",-1))==bench):continue
		var lab: RefCounted=stations[bench]
		if dc:
			if lab.master or lab.generator.enabled or lab.linked or lab.fuse or not lab.wires.is_empty() or not lab.board.is_empty():continue
			if ([lab.current_source]+lab.auxiliary_sources).any(func(source):return source.enabled):continue
		elif lab.powered or not lab.cables.is_empty() or not lab.records.is_empty() or not lab.stored_cables.is_empty() or lab.external_connections>0 or not lab.protective_earth_profile.is_empty() or lab.mode!="Free Laboratory":continue
		var workbench: Vector3=game.dc_lab.bench_position(bench) if dc else lab.positions.get("power",Vector3.INF)
		if not workbench.is_finite():continue
		var chosen: Dictionary={}
		for member in activity.get("classmates",{}).values():
			if not member.get("arrived",false):continue
			if chosen.is_empty() or (member.position as Vector3).distance_to(workbench)<(chosen.position as Vector3).distance_to(workbench):chosen=member
		if chosen.is_empty():return false
		if game.session.roster.keys().any(func(peer):
			var point: Vector3=game.lecture_classes._position(int(peer))
			return point.is_finite() and point.distance_to(workbench)<2.1):continue
		var commands:=Digital.commands(digital) if not digital.is_empty() else (_dc_commands(exercise) if dc else _commands(lab,exercise))
		if commands.is_empty():continue
		var foot:=Vector3(workbench.x+(0. if dc else 2.006),chosen.seat.y,workbench.z+1.43)
		work={"class_id":activity.id,"domain":"dc" if dc else "ac","bench":bench,"next":now+.6,"commands":commands,"baseline":lab.snapshot(),"member":chosen,"foot":foot,"digital":digital,"observations":{}}
		chosen.using_bench=true
		chosen.position=foot
		activity.lab_practice_done=true
		return true
	return false

func _commands(lab: RefCounted,exercise: Dictionary) -> Array:
	var plan: Dictionary=exercise.get("plan",{})
	var leads: Array=exercise.get("leads",[])
	if plan.is_empty() or leads.is_empty():return []
	var desired: Dictionary={}
	for bank in plan.banks:
		var switches:=Instructions.switch_indices(bank)
		if switches.is_empty():return []
		for index in switches:desired["%s_%d"%[bank.kind,int(bank.index)*3+index]]=true
	var actions: Array=[]
	if not lab.drawer_open:actions.append({"op":"drawer","control":"storage"})
	for kind in lab.switches:
		for index in lab.switches[kind].size():
			var key: String="%s_%d"%[kind,index]
			var enabled: bool=lab.switches[kind][index]
			if desired.has(key)!=enabled:
				actions.append({"op":"switch","kind":kind,"index":index,"expected":enabled,"control":key,"label":"checking instruments"})
	var level: float=lab.level
	while absf(level-float(plan.variable_level))>.00001:
		var change:=clampf(float(plan.variable_level)-level,-.05,.05)
		actions.append({"op":"voltage","delta":change,"control":"variable","label":"checking instruments"})
		level+=change
	var frequency: float=lab.frequency
	while absf(frequency-float(plan.frequency_hz))>.00001:
		var change:=clampf(float(plan.frequency_hz)-frequency,-5.,5.)
		actions.append({"op":"frequency","delta":change,"control":"frequency","label":"checking instruments"})
		frequency+=change
	for wire in leads:
		actions.append({"op":"pickup","color":actions.size()%4,"control":"storage"})
		for port in wire:
			actions.append({"op":"plug","port":port})
	actions.append_array([{"op":"check","label":"checking instruments"},{"op":"power","control":"power","label":"reading meter"},{"op":"record","label":"reading meter"}])
	return actions

func _dc_commands(exercise: Dictionary) -> Array:
	var resistance:=clampf(float(exercise.get("resistance",1000.)),100.,100000.)
	return [
		{"op":"channel","index":0,"key":"voltage","value":5.,"label":"checking instruments"},
		{"op":"channel","index":0,"key":"limit","value":.10,"label":"checking instruments"},
		{"op":"resistor","index":0,"value":resistance},
		{"op":"wire","a":"CH1+","b":"R1a","lead_color":0},
		{"op":"wire","a":"CH1-","b":"R1b","lead_color":1},
		{"op":"wire","a":"R1a","b":"VΩ","lead_color":0},
		{"op":"wire","a":"R1b","b":"COM","lead_color":1},
		{"op":"meter","mode":"DC V","label":"checking instruments"},
		{"op":"channel","index":0,"key":"enabled","value":true,"label":"reading meter"},
		{"op":"master","label":"reading meter"},
	]

func yield_bench(index: int,domain := "ac") -> void:
	if work.get("domain","")==domain and int(work.bench)==index:finish()

func live_readings(class_id: String,include_trace := false) -> Dictionary:
	# Only the station reserved for this class's demonstration is public.
	if work.get("class_id","")!=class_id:return {}
	var station_number:=int(work.bench)+1
	if work.domain=="ac":
		var station: RefCounted=game.session.labs[work.bench]
		if not station.powered or not str(station.readings.get("fault","")).is_empty():return {}
		return {"station":station_number,"values":{
			"bench_hz":station.frequency,"bench_voltage_v":station.readings.voltmeters.max(),
			"bench_current_a":station.readings.ammeters.max(),
			"bench_power_w":station.readings.wattmeters[0]+station.readings.wattmeters[1]}}
	var station: RefCounted=game.dc_lab.benches[work.bench]
	var values: Dictionary={}
	var series: Dictionary={}
	if station.generator.enabled:
		var measured:=Digital.Evidence.scope_sample(station)
		if not measured.is_empty():
			values.bench_hz=measured.frequency
			values.bench_scope_vpp=measured.vpp
			if include_trace:series.bench_scope_trace=_scope_trace(station.scope_capture.display,measured.frequency)
	if station.master and station.solved_revision==station.revision and station.result.get("ok",false):
		var volts: Dictionary=station.result.get("v",{})
		var islands: Dictionary=station.result.get("islands",{})
		if volts.has("VΩ") and volts.has("COM") and islands.has("VΩ") and islands.get("VΩ")==islands.get("COM"):
			values.bench_voltage_v=absf(station.difference("VΩ","COM"))
	if values.is_empty():return {}
	return {"station":station_number,"values":values,"series":series}

static func _scope_trace(rows: Array,frequency: float) -> PackedVector2Array:
	var trace:=PackedVector2Array()
	if rows.size()<2:return trace
	var end:=float(rows.back()[0])
	var start:=maxf(float(rows[0][0]),end-3./frequency)
	var first:=rows.bsearch_custom([start],func(a: Array,b: Array):return float(a[0])<float(b[0]))
	var count:=mini(rows.size()-first,128)
	if count<2:return trace
	for index in count:
		var row: Array=rows[first+roundi(float(index)*float(rows.size()-1-first)/float(count-1))]
		trace.append(Vector2((float(row[0])-start)*1000.,float(row[1])))
	return trace

func finish() -> void:
	if work.is_empty():return
	if work.domain=="dc":
		var station: RefCounted=game.dc_lab.benches[work.bench]
		var original: Dictionary=work.baseline
		if station.master:station.apply({"op":"master"})
		if station.generator.enabled:station.apply({"op":"generator","key":"enabled","value":false})
		while not station.wires.is_empty():
			station.apply({"op":"unwire","index":station.wires.size()-1})
		if station.board_owner==ACTOR_ID:station.apply({"op":"recall"})
		for index in original.channels.size():
			for key in ["voltage","limit","enabled"]:
				station.apply({"op":"channel","index":index,"key":key,"value":original.channels[index][key]})
		if work.digital=="digital_scope":
			for key in ["wave","frequency","amplitude","offset","duty"]:
				station.apply({"op":"generator","key":key,"value":original.generator[key]})
		station.apply({"op":"resistor","index":0,"value":original.resistance[0]})
		station.apply({"op":"meter","mode":original.meter_mode})
		work.member.using_bench=false
		work.clear()
		game.dc_lab.broadcast()
		return
	var lab: RefCounted=game.session.labs[work.bench]
	var baseline: Dictionary=work.baseline
	# Every NPC change is scoped to a previously empty bench. A human command
	# releases the reservation before the usual access checks and simulation.
	lab.cables.clear()
	lab.powered=false
	lab.records.clear()
	lab.level=baseline.level
	lab.frequency=baseline.frequency
	lab.checked=baseline.checked
	lab.drawer_open=baseline.drawer_open
	lab.last_action=baseline.last_action
	lab.result=baseline.result
	lab.switches=baseline.switches
	lab.revision+=1
	lab.recalculate()
	work.member.using_bench=false
	work.clear()
	game.session.broadcast()
