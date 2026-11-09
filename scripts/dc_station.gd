extends RefCounted
const Solver = preload("res://scripts/electronics_solver.gd")
const PORTS = ["CH1+","CH1-","CH2+","CH2-","CH3+","CH3-","GEN","REF","VΩ","COM","A","S1","S2","GND","R1a","R1b","R2a","R2b","Ca","Cb","Da","Db","B1","B2","B3","B4","IS+","IS-","IS2+","IS2-","IS3+","IS3-","IS4+","IS4-","X1","X2","X3","X4","X5","X6","X7","X8","X9","X10","X11","X12","X13","X14","X15","X16","X17","X18","X19","X20","X21","X22","X23","X24","X25","X26","X27","X28","X29","X30","X31","X32","X33","X34","X35","X36","X37","X38","X39","X40","X41","X42","X43","X44","X45","X46","X47","X48","X49","X50","X51","X52","X53","X54","X55","X56","X57","X58","X59","X60","X61","X62","X63","X64"]
var solver = Solver.new()
var linked := false
var audio_ids: Array=[]
var audio_samples := {}
var board := {}
var board_owner := 0
var board_epoch := 0
var static_step_key := []
var can_reuse_static_solution := false
var static_batteries := []
var coupled_cache := {}
var meter_analysis_at := -INF
var passive_expansion_epoch := -1
var passive_expansion_revision := -1
var passive_expansion: Dictionary = {}
var expanded_board_wires: Variant = null
var passive_pcb_epoch := -1
var passive_pcb := false
var board_held := false
var board_stowed := false
var board_position := Vector3.ZERO
var board_rotation := 0.0
var button_releases := {}
var firmware := {}
var firmware_time_budget := 0.
var last_sample_time := -1.
var native_controls := {}
var firmware_states := {}
var current_source := {"enabled":false,"current":.01,"compliance":30.0}
var auxiliary_sources: Array=[{"enabled":false,"current":.01,"compliance":30.0},{"enabled":false,"current":.01,"compliance":30.0},{"enabled":false,"current":.01,"compliance":30.0}]
var master := false
var channels: Array = [{"voltage":5.0,"limit":.1,"enabled":false},{"voltage":5.0,"limit":.1,"enabled":false},{"voltage":3.3,"limit":.1,"enabled":false}]
var generator := {"enabled":false,"wave":"Sine","frequency":10.0,"amplitude":2.0,"offset":0.0,"phase":0.0,"duty":.5,"resistance":50.0}
var meter_mode := "DC V"
var fuse := false
var resistance := [1000.0,1000.0]
var capacitance := .000001
var wires: Array = []
var lead_colors: Array[int] = []
var result := {}
var meter := "—"
var samples: Array = []
var meter_samples: Array=[]
var meter_range := 0.0
var passive_cache := {}
const ScopeSettings = preload("res://scripts/dc_scope/settings.gd")
const ScopeAcquisition = preload("res://scripts/dc_scope/acquisition.gd")
var scope := ScopeSettings.defaults()
var scope_capture := ScopeAcquisition.new()
var revision := 0
var previous := 0.0
var capture_remaining := 0

func _init() -> void:
	scope_capture.configure(scope)
func restore_scope(saved: Dictionary) -> void:
	scope=ScopeSettings.normalize(saved)
	scope_capture.configure(scope)
func _capture_scope() -> void:
	scope_capture.push([solver.time,difference("S1","GND"),difference("S2","GND"),difference("VΩ","COM"),float(result.get("i",{}).get("ammeter",0))])
	samples=scope_capture.display
	scope.running=scope_capture.running; scope.single=scope_capture.single; scope.armed=scope_capture.armed

func source_value(t: float) -> float:
	var p := fposmod(t*float(generator.frequency)+float(generator.phase)/360.0,1.0)
	var wave := 0.0
	match str(generator.wave):
		"Sine":wave=sin(TAU*p)
		"Square","Pulse":wave=1 if p<float(generator.duty) else -1
		"Triangle":wave=1-4*absf(p-.5)
		"Sawtooth":wave=2*p-1
		"DC":wave=0
	return float(generator.offset)+float(generator.amplitude)*wave

func board_simulating() -> bool:
	if board.is_empty() or board_held or board_stowed:return false
	if not board.get("standalone",false):return true
	if linked:return true
	for wire in wires:
		if str(wire[0]).begins_with("X") or str(wire[1]).begins_with("X"):return true
	if passive_pcb_epoch!=board_epoch:
		passive_pcb_epoch=board_epoch
		var model := preload("res://scripts/breadboard_model.gd")
		passive_pcb=model.expand(board).parts.all(func(part):return part.kind in ["R","D","LED"])
	return not passive_pcb

func _remove_board_leads() -> void:
	for index in range(wires.size()-1,-1,-1):
		var wire: Array = wires[index]
		if board_port(str(wire[0])) or board_port(str(wire[1])):
			_remove_lead(index)

func _remove_lead(index: int) -> void:
	wires.remove_at(index)
	lead_colors.remove_at(index)

# These models depend on board settings, not on prior voltages or firmware.
static func _fixed_parts(parts: Array, definitions: Dictionary, checked: Dictionary) -> bool:
	var catalog := preload("res://scripts/electronics_catalog.gd")
	for part in parts:
		var id := str(part.type)
		if not checked.has(id):
			var fixed := false
			if definitions.has(id):
				checked[id]=false
				fixed=_fixed_parts(definitions[id].get("parts",[]),definitions,checked)
			else:
				var model: Dictionary=catalog.simulation_entry(id)
				fixed=model.get("source_mode","")=="battery_adjustable" or model.get("kind","") in ["R","C","L","D","LED","V","button","toggle","pot","variable_cap","variable_inductor","photodiode","solar_panel","polar_cap","buzzer","seven_segment"]
			checked[id]=fixed
		if not checked[id]:return false
	return true

func _fixed_board_expansion() -> Dictionary:
	if passive_expansion_epoch == board_epoch and passive_expansion_revision == revision:
		return passive_expansion
	passive_expansion_epoch = board_epoch
	passive_expansion_revision = revision
	passive_expansion = {}
	expanded_board_wires=null
	if _fixed_parts(board.parts,board.get("definitions",{}),{}):
		passive_expansion=preload("res://scripts/breadboard_model.gd").expand(board)
	return passive_expansion

func board_wires() -> Array:
	var fixed := _fixed_board_expansion()
	if not fixed.is_empty():return fixed.wires
	if expanded_board_wires==null:
		expanded_board_wires=preload("res://scripts/breadboard_model.gd").wires_only(board)
	return expanded_board_wires

var portable_slot := false

func netlist() -> Array:
	var parts: Array=[]
	if portable_slot:
		if not board_simulating():return parts
		var fixed := _fixed_board_expansion()
		if not fixed.is_empty():return fixed.parts
		var runtime := firmware_states.duplicate()
		runtime["__simulation_time"]=solver.time
		return preload("res://scripts/breadboard_model.gd").expand(board,"board/",result.get("v",{}),runtime).parts.filter(func(p):return p.kind not in ["controller","native_controller","stateful","io_device"])
	for i in range(3):
		if master and channels[i].enabled:parts.append({"id":"s%d"%i,"kind":"supply","a":"CH%d+"%(i+1),"b":"CH%d-"%(i+1),"value":channels[i].voltage,"limit":channels[i].limit,"resistance":.01})
	var sources: Array=[current_source]+auxiliary_sources
	for index in sources.size():
		var source: Dictionary=sources[index];var suffix := "" if index==0 else str(index+1)
		if master and source.enabled:parts.append({"id":"isource"+suffix,"kind":"current_source","a":"IS"+suffix+"+","b":"IS"+suffix+"-","value":source.current,"compliance":source.compliance,"resistance":.01,"rout":1e9})
	if generator.enabled:parts.append({"id":"gen","kind":"V","a":"GEN","b":"REF","value":source_value(solver.time),"resistance":generator.resistance})
	for i in range(2):parts.append({"id":"r%d"%i,"kind":"R","a":"R%da"%(i+1),"b":"R%db"%(i+1),"value":resistance[i]})
	parts.append({"id":"cap","kind":"C","a":"Ca","b":"Cb","value":capacitance})
	parts.append({"id":"diode","kind":"D","a":"Da","b":"Db","vf":.65,"ron":2})
	# Current input remains a shunt regardless of selector: plugging into A matters.
	if not fuse:parts.append({"id":"ammeter","kind":"R","a":"A","b":"COM","value":.1})
	parts.append({"id":"vmeter","kind":"R","a":"VΩ","b":"COM","value":1e7})
	for pin in ["S1","S2"]:parts.append({"id":pin,"kind":"R","a":pin,"b":"GND","value":1e6})
	if board_simulating():
		var fixed := _fixed_board_expansion()
		if not fixed.is_empty():
			parts.append_array(fixed.parts)
			return parts
		var runtime := firmware_states.duplicate()
		runtime["__simulation_time"]=solver.time
		parts.append_array(preload("res://scripts/breadboard_model.gd").expand(board,"board/",result.get("v",{}),runtime).parts.filter(func(p):return p.kind not in ["controller","native_controller","stateful","io_device"]))
	return parts

func step(dt := .0005) -> void:
	prepare_step(dt)
	var key := [revision,board_epoch,board_simulating(),dt]
	if dt>0 and not linked and can_reuse_static_solution and static_step_key==key and is_same(result,solver.last) and solver.reuse_flat_solution(static_batteries,dt):
		finish_step(true)
		return
	static_step_key=key
	can_reuse_static_solution=false
	var leads: Array=wires.duplicate(true)
	if board_simulating():leads.append_array(board_wires())
	var parts := netlist()
	result=solver.solve(parts,leads,dt,dt==0.)
	if dt>0 and not linked and result.get("ok",false) and not (generator.enabled and generator.wave!="DC"):
		var fixed_board := not board_simulating() or not _fixed_board_expansion().is_empty()
		if fixed_board and not wires.any(func(w):return "Ca" in w or "Cb" in w) and float(solver.memory.get("cap",0.0))==0.0:
			can_reuse_static_solution=parts.all(func(part):return part.id=="cap" or part.kind not in ["C","L"])
			static_batteries=parts.filter(func(part):return part.kind=="V" and float(part.get("capacity_ah",0))>0)
	finish_step()

func release_due_buttons(at_time: float) -> void:
	for id in button_releases.keys():
		if at_time>=float(button_releases[id]):
			if board.get("controls",{}).has(id):board.controls[id].pressed=false
			for part in board.get("parts",[]):
				if "board/"+str(part.id)==id:part.pressed=false
			button_releases.erase(id);revision+=1

func prepare_step(dt: float) -> void:
	firmware_time_budget+=maxf(0.,dt)
	var firmware_dt := firmware_time_budget if firmware_time_budget>=.0005-1e-12 else 0.
	if firmware_dt>0.:firmware_time_budget=0.
	audio_ids=[]
	if not button_releases.is_empty():release_due_buttons(solver.time)
	if board_simulating():
		if not _fixed_board_expansion().is_empty():
			firmware.clear()
			firmware_states.clear()
			return
		var live_ids := {}
		for device in preload("res://scripts/breadboard_model.gd").expand(board,"board/",result.get("v",{}),firmware_states).parts:
			if device.get("audio",false) and audio_ids.size()<8:audio_ids.append(device.id)
			if device.kind=="native_controller":
				live_ids[device.id]=true
				continue
			if device.kind=="io_device":
				live_ids[device.id]=true
				firmware_states[device.id]=preload("res://scripts/io_devices/devices.gd").tick(device,result,firmware_states.get(device.id,{}),dt)
				continue
			if device.kind=="stateful":
				live_ids[device.id]=true
				if str(device.model).begins_with("worker:"):
					firmware_states[device.id]=preload("res://scripts/component_models/library.gd").tick(device.config,device.nodes,result.get("v",{}),firmware_states.get(device.id,{}),dt,result.get("i",{}),device.id)
				else:
					firmware_states[device.id]=preload("res://scripts/stateful_devices.gd").tick(device.model,device.nodes,result.get("v",{}),firmware_states.get(device.id,{}),dt)
				continue
			if device.kind!="controller":continue
			live_ids[device.id]=true
			if firmware_dt<=0.:continue
			if not firmware.has(device.id):firmware[device.id]=preload("res://scripts/firmware_runtime.gd").new()
			firmware_states[device.id]=firmware[device.id].tick(device.source,device.nodes,result.get("v",{}),firmware_dt,device.run)
		for id in firmware_states.keys():
			if not live_ids.has(id):firmware.erase(id);firmware_states.erase(id)

func finish_step(reused := false) -> void:
	var sample_now: bool=solver.time!=last_sample_time
	last_sample_time=solver.time
	if not result.ok:meter="ERROR";return
	if sample_now and not portable_slot:_capture_scope()
	if not reused:
		result["resistor_ratings"]={}
		for id in preload("res://scripts/physical_resistors.gd").parameters(board if board_simulating() else {}):
			var parameters: Dictionary=board.component_runtime[id]
			var power: float=absf(float(result.get("drop",{}).get(id,0))*float(result.get("i",{}).get(id,0)))
			result.resistor_ratings[id]={"nominal_ohms":parameters.nominal,"actual_ohms":parameters.actual,"tolerance":parameters.tolerance,"rating_watts":parameters.watts,"power_watts":power,"overloaded":power>float(parameters.watts)}
	for id in audio_samples.keys():
		if id not in audio_ids:audio_samples.erase(id)
	for id in audio_ids:
		if not audio_samples.has(id):audio_samples[id]=[]
		if sample_now:
			audio_samples[id].append([solver.time,float(result.get("drop",{}).get(id,0))])
			if audio_samples[id].size()>512:audio_samples[id].pop_front()
	result["audio"]=audio_samples
	if portable_slot:return
	if absf(float(result.i.get("ammeter",0)))>1.0:
		fuse=true;revision+=1;meter="FUSE OPEN";return
	var v := difference("VΩ","COM")
	if sample_now:
		meter_samples.append([solver.time,difference("S1","GND"),difference("S2","GND"),v,float(result.i.get("ammeter",0))])
		if meter_samples.size()>512:meter_samples.pop_front()
	match meter_mode:
		"DC V":meter="OL" if meter_range>0 and absf(v)>meter_range else "%.4f V"%v
		"DC A":meter="FUSE OPEN" if fuse else "OL" if meter_range>0 and absf(float(result.i.get("ammeter",0)))>meter_range else "%.6f A"%float(result.i.get("ammeter",0))
		"Resistance","Continuity","Diode","Capacitance":
			var key := [revision, linked, board_simulating(), meter_mode]
			if not passive_cache.has(key):passive_cache={key:test_capacitance() if meter_mode=="Capacitance" else test_measure()}
			meter=passive_cache[key]
		"AC V","AC A","Frequency","Duty":
			if meter_samples.size()<8:meter="Acquiring…"
			elif solver.time<meter_analysis_at or solver.time-meter_analysis_at>=.05:
				meter_analysis_at=solver.time
				var column := 3 if meter_mode!="AC A" else 4
				if meter_mode.begins_with("AC"):
					var ac_rms: float=ac_rms_only(meter_samples,column)
					meter="OL" if meter_range>0 and ac_rms>meter_range else "%.5f %s RMS"%[ac_rms,"V" if column==3 else "A"]
				else:
					var stats := statistics(meter_samples,column)
					if meter_mode=="Frequency":meter="%.3f Hz"%stats.frequency if stats.frequency>0 else "No periodic signal"
					else:meter="%.2f %%"%stats.duty if stats.frequency>0 else "No periodic signal"

func difference(a: String,b: String) -> float:
	return float(result.get("v",{}).get(a,0))-float(result.get("v",{}).get(b,0))

func test_measure() -> String:
	if linked:return "Disconnect inter-bench leads for passive tests"
	if master and (channels.any(func(c):return c.enabled) or current_source.enabled or auxiliary_sources.any(func(source):return source.enabled)) or generator.enabled:return "LIVE — disable sources"
	var circuit := netlist()
	# Remove the meter's own loading when measuring a passive network.
	circuit=circuit.filter(func(p):return p.id!="vmeter")
	circuit.append({"id":"test","kind":"I","a":"COM","b":"VΩ","value":.001})
	var testing = Solver.new()
	var leads: Array=wires.duplicate(true)
	if board_simulating():leads.append_array(preload("res://scripts/breadboard_model.gd").wires_only(board))
	if circuit.any(func(p):return p.kind in ["V","supply","current_source"]):return "LIVE — disconnect board battery"
	var measured: Dictionary=testing.solve(circuit,leads)
	if not measured.ok:return "OL / open"
	var voltage: float=measured.v.get("VΩ",0)-measured.v.get("COM",0)
	if absf(voltage)>2:return "OL / open" if meter_mode=="Diode" else ("%.2f Ω"%(absf(voltage)*1000) if absf(voltage)<1e4 else "OL / open")
	if meter_mode=="Diode":return "%.3f V"%voltage
	if meter_mode=="Continuity":return "CONTINUITY" if absf(voltage)*1000<50 else "OPEN"
	return "%.2f Ω"%(absf(voltage)*1000)

func apply(action: Dictionary, preserve_board_leads := false) -> String:
	var op := str(action.get("op",""))
	match op:
		"current_source":
			var raw_index=action.get("index",0)
			if not raw_index is int:return "Invalid current source index"
			var index: int=raw_index
			if index<0 or index>3:return "Invalid current source index"
			var selected_source: Dictionary=current_source if index==0 else auxiliary_sources[index-1]
			var key := str(action.get("key",""));var value=action.get("value")
			if key=="enabled":
				if not value is bool:return "Invalid current source switch"
				selected_source.enabled=value
			elif key in ["current","compliance"]:
				if not (value is int or value is float) or not is_finite(float(value)):return "Invalid current source setting"
				selected_source[key]=clampf(float(value),-1,1) if key=="current" else clampf(float(value),.1,30.)
			else:return "Unknown current source control"
		"carry_board", "stow_board":
			if board.is_empty():return "No board to carry"
			if linked:return "Disconnect inter-bench leads before moving the board."
			for wire in wires:
				if board_port(str(wire[0])) or board_port(str(wire[1])):return "Disconnect all board leads before moving it."
			board_held=op=="carry_board";board_stowed=op=="stow_board"
		"place_board":
			if not board_held:return "Pick up the board first"
			var pos=action.get("position")
			if not pos is Vector3 or not pos.is_finite():return "Invalid placement"
			board_position=pos;board_held=false
		"rotate_board":
			if not board_held:return "Pick up the board to rotate it"
			board_rotation=fposmod(board_rotation+PI/2,TAU)
		"firmware_reset":
			var id := str(action.get("id",""))
			if firmware.has(id):firmware[id].reset()
			else:return "Device is not running"
		"input":
			var requested := str(action.get("id",""))
			if not requested.begins_with("board/"):requested="board/"+requested
			var found := false
			for entry in preload("res://scripts/breadboard_model.gd").devices(board):
				if entry.id!=requested:continue
				var part: Dictionary=entry.part;found=true
				if not board.has("controls"):board.controls={}
				var control: Dictionary=board.controls.get(requested,{})
				var input_type := preload("res://scripts/breadboard_model.gd").manual_input_type(str(part.type))
				match input_type:
					"button":
						control.pressed=bool(action.get("pressed",true))
						if action.get("hold",false) or not control.pressed:button_releases.erase(requested)
						else:button_releases[requested]=solver.time+.25
					"toggle":control.pressed=not control.get("pressed",part.get("pressed",false))
					"battery_adjustable","battery_generator","battery_generator_adjustable":
						var source := preload("res://scripts/electronics_catalog.gd").simulation_entry(str(part.type))
						preload("res://scripts/electronics/portable_sources.gd").adjust(source,control,action)
					"pot10k","variable_cap","variable_inductor","photodiode","solar_panel":
						var default_setting := .65 if input_type in ["photodiode","solar_panel"] else .5
						control.setting=clampf(float(control.get("setting",part.get("setting",default_setting)))+(-.05 if bool(action.get("reverse",false)) else .05),0,1)
					_:
						var io_defaults := preload("res://scripts/io_devices/controls.gd").defaults(str(part.type))
						if io_defaults.is_empty():return "This component has no manual control"
						var io_change := preload("res://scripts/io_devices/controls.gd").apply(str(part.type),board.get("io_controls",{}).get(requested,io_defaults),action.get("command",{}))
						if not io_change.ok:return str(io_change.error)
						if not board.has("io_controls"):board.io_controls={}
						board.io_controls[requested]=io_change.state
						continue
				board.controls[requested]=control
				if requested.count("/")==1:part.merge(control,true)
			if not found:return "Component no longer exists"
		"board":
			var design=action.get("design",{})
			if not design is Dictionary:return "Invalid board"
			var error: String=preload("res://scripts/breadboard_model.gd").validate(design,{},true)
			if error!="":return error
			if not preserve_board_leads and (bool(board.get("standalone",false))!=bool(design.get("standalone",false)) or (design.get("standalone",false) and board.get("parts",[])!=design.get("parts",[]))):
				_remove_board_leads()
			var old_instances: Dictionary=board.get("instance_ids",{}).duplicate()
			board_epoch+=1
			board=design.duplicate(true)
			var ids: Dictionary=board.get("instance_ids",{})
			for id in firmware_states.keys():
				if firmware_states[id].has("memory"):
					var root := str(id).get_slice("/",1)
					var different: bool=old_instances.get(root,"")!=ids.get(root,"")
					if ids.get(root,"")=="":
						var current: Dictionary=preload("res://scripts/inventory_authority/component_persistence.gd").capture({id:firmware_states[id]})
						different=not preload("res://scripts/electronics_profile.gd").same(current.get(id),board.get("component_runtime",{}).get(id))
					if different:firmware_states.erase(id)
			var restored: Dictionary=preload("res://scripts/inventory_authority/component_persistence.gd").restore(board.get("component_runtime",{}))
			for id in restored:
				if not firmware_states.has(id):firmware_states[id]=restored[id]
		"recall":
			firmware.clear();firmware_states.clear()
			board_epoch+=1
			board={};board_owner=0;board_held=false;board_stowed=false;board_position=Vector3.ZERO;board_rotation=0
			_remove_board_leads()
			solver.reset()
		"master":master=not master
		"channel":
			var i := int(action.get("index",-1));var key := str(action.get("key",""))
			if i<0 or i>2 or key not in ["voltage","limit","enabled"]:return "Invalid channel"
			if key=="enabled":channels[i][key]=bool(action.get("value",false))
			else:
				var value := float(action.get("value",0))
				if not is_finite(value):return "Invalid number"
				channels[i][key]=clampf(value,0 if key=="voltage" else .001,30 if key=="voltage" else 1)
		"generator":
			var key := str(action.get("key",""));var value=action.get("value")
			if key=="enabled":generator.enabled=bool(value)
			elif key=="wave" and str(value) in ["Sine","Square","Triangle","Sawtooth","Pulse","DC"]:generator.wave=str(value)
			elif key in ["frequency","amplitude","offset","phase","duty","resistance"]:
				var number := float(value)
				if not is_finite(number):return "Invalid number"
				var bounds: Dictionary={"frequency":[.1,100.0],"amplitude":[0,10],"offset":[-10,10],"phase":[0,360],"duty":[.05,.95],"resistance":[1,1000]}
				generator[key]=clampf(number,bounds[key][0],bounds[key][1])
			else:return "Invalid generator control"
		"meter_range":
			var value := float(action.get("value",0))
			if not is_finite(value) or value not in [0.0,.0002,.002,.02,.2,2.,20.,200.]:return "Invalid meter range"
			meter_range=value
		"meter":
			if str(action.get("mode")) not in ["DC V","AC V","DC A","AC A","Resistance","Continuity","Diode","Capacitance","Frequency","Duty"]:return "Unsupported meter mode"
			meter_mode=str(action.mode)
		"fuse":
			if master or generator.enabled:return "Disable outputs before replacing fuse"
			fuse=false
		"resistor":
			var index := int(action.get("index",-1));var value := float(action.get("value",0))
			if index not in [0,1] or not is_finite(value):return "Invalid resistor"
			resistance[index]=clampf(value,1,1e6)
		"capacitor":
			var value := float(action.get("value",0))
			if not is_finite(value):return "Invalid capacitance"
			capacitance=clampf(value,1e-9,.01)
		"wire":
			var a := str(action.get("a",""));var b := str(action.get("b",""))
			if a not in PORTS or b not in PORTS or wires.size()>=48:return "Invalid lead"
			for port in [a,b]:
				if port.begins_with("X") and not pcb_pin_available(port):return "This PCB pin is not available"
			if (board_held or board_stowed) and (board_port(a) or board_port(b)):return "Place the board before attaching leads"
			wires.append([a,b])
			lead_colors.append(clampi(int(action.get("lead_color", -1)), -1, 3))
		"unwire":
			var i := int(action.get("index",-1))
			if i<0 or i>=wires.size():return "Lead no longer exists"
			_remove_lead(i)
		"clear":
			master=false;generator.enabled=false;wires.clear();lead_colors.clear();solver.reset();samples.clear();scope_capture.reset();scope_capture.configure(scope)
		"scope":
			var controls: Array=[action]
			if str(action.get("key",""))=="autoset":
				if not action.get("value") is bool or action.get("value")!=true or samples.size()<2:return "Acquire samples before Autoset"
				controls=preload("res://scripts/dc_scope/autoset.gd").actions(samples,scope)
			var next_scope: Dictionary=scope
			for control in controls:
				var changed := ScopeSettings.change(next_scope,control)
				if not changed.ok:return str(changed.error)
				next_scope=changed.settings
			scope=next_scope
			scope_capture.configure(scope,str(action.get("key",""))=="single")
		_:return "Unknown DC action"
	meter_analysis_at=-INF
	revision+=1
	return ""

func public_device_states() -> Dictionary:
	var public := {}
	if not board_simulating():return public
	# Filter before cloning: large nonvolatile byte maps never enter publication.
	for id in firmware_states:
		var visible := {}
		for key in firmware_states[id]:
			if key not in ["memory","pending","bits","word","command","address","base","clock","selected","wel","busy","adc_started","shift"]:visible[key]=firmware_states[id][key]
		public[id]=visible.duplicate(true)
	var catalog: Dictionary=preload("res://scripts/breadboard_model.gd").catalog(board)
	for device in preload("res://scripts/breadboard_model.gd").devices(board):
		if not public.has(device.id):continue
		var kind := str(catalog.get(device.part.type,{}).get("kind",""))
		if preload("res://scripts/io_devices/catalog.gd").supports(kind):public[device.id]=preload("res://scripts/io_devices/replication.gd").public_state(kind,firmware_states[device.id])
		elif public[device.id].has("memory"):public[device.id].erase("memory")
	return public
func snapshot() -> Dictionary:
	var public_board := board.duplicate(true)
	public_board.erase("component_runtime")
	return {"current_sources":([current_source]+auxiliary_sources).duplicate(true),"current_source":current_source.duplicate(true),"board_epoch":board_epoch,"board_stowed":board_stowed,"board_held":board_held,"board_position":board_position,"board_rotation":board_rotation,"firmware":public_device_states(),"board":public_board,"board_owner":board_owner,"master":master,"channels":channels.duplicate(true),"generator":generator.duplicate(true),"meter_mode":meter_mode,"meter_range":meter_range,"fuse":fuse,"resistance":resistance.duplicate(),"capacitance":capacitance,"wires":wires.duplicate(true),"result":result.duplicate(true),"meter":meter,"samples":samples.duplicate(true),"scope":scope.duplicate(true),"scope_acquisition":scope_capture.status(),"scope_probe":preload("res://scripts/dc_scope/probe_connections.gd").describe(wires,linked),"revision":revision}

static func ac_rms_only(data: Array,column: int) -> float:
	var sum := 0.0;var square := 0.0
	for row in data:
		var v := float(row[column]);sum+=v;square+=v*v
	var n := maxi(data.size(),1);var average := sum/n
	return sqrt(maxf(0,square/n-average*average))

static func statistics(data: Array,column: int) -> Dictionary:
	var sum := 0.0;var square := 0.0;var low := INF;var high := -INF
	for row in data:
		var v := float(row[column]);sum+=v;square+=v*v;low=minf(low,v);high=maxf(high,v)
	var n := maxi(data.size(),1);var average := sum/n
	var crossings: Array=[];var above := 0
	for i in range(1,data.size()):
		if float(data[i][column])>average:above+=1
		if float(data[i-1][column])<average and float(data[i][column])>=average:crossings.append(float(data[i][0]))
	var frequency: float = (crossings.size()-1)/(crossings[-1]-crossings[0]) if crossings.size()>1 and high-low>1e-5 else 0.0
	return {"average":average,"rms":sqrt(square/n),"ac_rms":sqrt(maxf(0,square/n-average*average)),"vpp":high-low if data.size()>0 else 0,"frequency":frequency,"duty":100.0*above/maxi(data.size()-1,1)}

func test_capacitance() -> String:
	if linked:return "Disconnect inter-bench leads for passive tests"
	if master and (channels.any(func(c):return c.enabled) or current_source.enabled or auxiliary_sources.any(func(source):return source.enabled)) or generator.enabled:return "LIVE — disable sources"
	var circuit := netlist().filter(func(p):return p.id!="vmeter")
	if circuit.any(func(p):return p.kind in ["V","supply","current_source"]):return "LIVE — disconnect board battery"
	var leads: Array=wires.duplicate(true)
	if board_simulating():leads.append_array(preload("res://scripts/breadboard_model.gd").wires_only(board))
	circuit.append({"id":"cap_test","kind":"I","a":"COM","b":"VΩ","value":.000001})
	var tester=Solver.new();var volts: Array=[]
	for index in 3:
		var solved: Dictionary=tester.solve(circuit,leads,.0001)
		if not solved.ok:return "OL / open"
		volts.append(float(solved.v.get("VΩ",0))-float(solved.v.get("COM",0)))
	var first: float=volts[1]-volts[0];var second: float=volts[2]-volts[1]
	if first<=1e-12 or absf(volts[2])>2:return "OL / no capacitance"
	if absf(second/first-1)>.02:return "Isolate capacitor from parallel loads"
	return "%.4f μF"%(.000001*.0001/first*1e6)

func pcb_pin_available(id: String) -> bool:
	if id not in PORTS or not id.begins_with("X") or not board.get("standalone",false):return false
	var parts: Array=board.get("parts",[])
	if parts.size()!=1 or not parts[0] is Dictionary:return false
	var pins=parts[0].get("pins",[])
	return pins is Array and pins.size()>=1 and pins.size()<=64 and int(id.substr(1))<=pins.size()

static func board_port(id: String) -> bool:return id in PORTS and (id.begins_with("B") or id.begins_with("X"))
