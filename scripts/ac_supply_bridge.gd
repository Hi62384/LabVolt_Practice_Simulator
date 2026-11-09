extends RefCounted
# Shared transient model for supply, RLC banks, ammeters and voltmeters.
const PORTS=["P_A","P_B","P_C","P_N","PV_A","PV_B","PV_C","PV_N"]
const Aux=preload("res://scripts/ac_auxiliary.gd")
var lab
var solver=preload("res://scripts/electronics_solver.gd").new()
var board := {}
var wires: Array=[["P_N","PV_N"]]
var firmware_states := {}
var result := {}
var linked := false
var samples: Array=[]
var sample_time := 0.
var linked_ports := {}
var occupied_ports := {}
var breaker_tripped := false
var external_wiring: Array = []
func _init(state):lab=state
func prepare_step(_dt: float) -> void:
	sample_time=solver.time
	wires=[["P_N","PV_N"]]
	occupied_ports = linked_ports.duplicate()
	for lead in lab.completed():
		wires.append([lead.a,lead.b])
		occupied_ports[lead.a] = true
		occupied_ports[lead.b] = true
	for i in 2:wires.append(["W%d_IN"%i,"W%d_VP"%i])
func available_ports() -> Array:
	var ports: Array=PORTS.duplicate()
	for kind in ["R","L","C"]:
		for bank in 3:ports.append("%s%d_P"%[kind,bank]);ports.append("%s%d_N"%[kind,bank])
	for i in 3:
		for suffix in ["IN","OUT","2_5","8","25"]:ports.append("AM%d_%s"%[i,suffix])
		for suffix in ["COM","150","300"]:ports.append("V%d_%s"%[i,suffix])
	for i in range(1,10):ports.append("TX_%d"%i)
	for i in 2:
		for suffix in ["IN","OUT","VP","VN"]:ports.append("W%d_%s"%[i,suffix])
	for i in 4:
		for suffix in ["P","N"]:ports.append("DAQ_E%d_%s"%[i,suffix])
		for suffix in ["4","40","N"]:ports.append("DAQ_I%d_%s"%[i,suffix])
	for port in lab.terminals:
		if port in Aux.SUPPLY_PORTS or port.begins_with("DAQ_") or port.begins_with("IGBT_") and port!="IGBT_EARTH" or port.begins_with("DYN_"):
			if not ports.has(port):ports.append(port)
	return ports
func netlist() -> Array:
	var parts: Array=[]
	var catalog=preload("res://scripts/equipment_catalog.gd")
	for kind in ["R","L","C"]:
		for bank in 3:
			for element in 3:
				if lab.switches.get(kind,[]).size()==9 and lab.switches[kind][bank*3+element]:parts.append({"id":"%s%d_%d"%[kind,bank,element],"kind":kind,"a":"%s%d_P"%[kind,bank],"b":"%s%d_N"%[kind,bank],"value":catalog.LOADS[kind].values[element]})
	for i in 3:
		for suffix in ["IN","2_5","8","25"]:
			if lab.terminals.has("AM%d_%s"%[i,suffix]):parts.append({"id":"AM%d_%s"%[i,suffix],"kind":"R","a":"AM%d_%s"%[i,suffix],"b":"AM%d_OUT"%i,"value":catalog.CURRENT_COIL_OHMS})
		for suffix in ["150","300"]:
			if lab.terminals.has("V%d_%s"%[i,suffix]):parts.append({"id":"V%d_%s"%[i,suffix],"kind":"R","a":"V%d_%s"%[i,suffix],"b":"V%d_COM"%i,"value":100000. if suffix=="150" else 250000.})
	for i in 2:
		if lab.terminals.has("W%d_IN"%i):
			parts.append({"id":"W%d_I"%i,"kind":"R","a":"W%d_IN"%i,"b":"W%d_OUT"%i,"value":catalog.CURRENT_COIL_OHMS})
			parts.append({"id":"W%d_V"%i,"kind":"R","a":"W%d_VP"%i,"b":"W%d_VN"%i,"value":150000.})
	for i in 4:
		if lab.terminals.has("DAQ_E%d_P"%i):parts.append({"id":"DAQ_E%d"%i,"kind":"R","a":"DAQ_E%d_P"%i,"b":"DAQ_E%d_N"%i,"value":1000000.})
		for tap in ["4","40"]:
			if lab.terminals.has("DAQ_I%d_%s"%[i,tap]):parts.append({"id":"DAQ_I%d_%s"%[i,tap],"kind":"R","a":"DAQ_I%d_%s"%[i,tap],"b":"DAQ_I%d_N"%i,"value":catalog.CURRENT_COIL_OHMS})
	if lab.terminals.has("TX_1"):
		parts.append({"id":"TXMAG","kind":"R","a":"TX_1","b":"TX_2","value":10000.})
		for winding in [[3,7,104.],[7,8,76.],[8,4,28.],[5,9,60.],[9,6,60.]]:
			parts.append({"id":"TX%d"%winding[0],"kind":"T","a":"TX_%d"%winding[0],"b":"TX_%d"%winding[1],"cp":"TX_1","cn":"TX_2","ratio":winding[2]/120.})
	var control_voltages := {}
	for terminal in result.get("v", {}):
		if str(terminal).begins_with("IGBT_"):
			control_voltages[terminal] = Vector2(result.v[terminal], 0.)
	var gate_state: Dictionary = Aux.switch_state(control_voltages) if not control_voltages.is_empty() else lab.readings.get("igbt", {})
	for part in Aux.impedances(lab.igbt_damping) + (Aux.switch_impedances(gate_state) if lab.powered else []):
		if lab.terminals.has(part.a) and lab.terminals.has(part.b) and (occupied_ports.has(part.a) or occupied_ports.has(part.b)):
			parts.append({"id":part.id,"kind":"R","a":part.a,"b":part.b,"value":part.ohms})
	if not lab.powered:return parts
	for source in Aux.supplies(lab.level) + Aux.daq_outputs(lab.daq_settings):
		if lab.terminals.has(source.a) and lab.terminals.has(source.b) and (occupied_ports.has(source.a) or occupied_ports.has(source.b)):
			var voltage: float = source.volts
			if not source.get("dc",true):
				voltage *= sqrt(2.) * cos(TAU * lab.frequency * solver.time)
			parts.append({"id":source.a,"kind":"V","a":source.a,"b":source.b,"value":voltage,"resistance":source.get("ohms",.05)})
	for variable in [false,true]:
		for phase in 3:
			var port: String= ("PV_" if variable else "P_")+["A","B","C"][phase]
			var angle: float= TAU*lab.frequency*solver.time+[0.,-TAU/3.,TAU/3.][phase]
			parts.append({"id":port,"kind":"V","a":port,"b":"P_N","value":sqrt(2.)*120.*(lab.level if variable else 1.)*cos(angle),"resistance":.01})
	return parts
func step(dt: float) -> void:
	if dt>0.:solver.time+=dt;samples.clear()
func finish_step() -> void:
	if not result.get("ok",false):return
	if not samples.is_empty() and float(samples[-1].time)==sample_time:return
	var entry := {"time":sample_time,"currents":{},"v":result.get("v",{}).duplicate()}
	for port in result.get("i",{}):entry.currents[port]=float(result.i[port])
	samples.append(entry)
	var period: float=1./lab.frequency
	while samples.size()>2 and sample_time-float(samples[1].time)>=period:samples.pop_front()
	if samples.size()<3 or sample_time-float(samples[0].time)<period*.95:return
	var rms := {}
	for port in entry.currents:
		var integral := 0.;var duration := 0.
		for i in range(1,samples.size()):
			var dt: float=samples[i].time-samples[i-1].time
			var value: float=samples[i].currents.get(port,0.)
			integral+=value*value*dt;duration+=dt
		rms[port]=sqrt(integral/maxf(duration,.000001))
		var limit := 5. if str(port).begins_with("PV_") else 15.
		for source in Aux.supplies(lab.level):
			if port == source.a:limit=source.amps
		if (port in PORTS or port in Aux.SUPPLY_PORTS) and lab.powered and rms[port]>limit:
			lab.powered=false;lab.recalculate();lab.readings.fault="SUPPLY OVERCURRENT from external circuit. Breaker tripped.";lab.revision+=1
			breaker_tripped = true
			return
	lab.readings["external_supply_rms"]=rms
	for i in 3:
		var energy := 0.
		for sample in samples:
			var current := 0.
			for suffix in ["IN","2_5","8","25"]:current+=float(sample.currents.get("AM%d_%s"%[i,suffix],0.))
			energy+=current*current
		lab.readings.ammeters[i]=sqrt(energy/samples.size())
		var peak := 0.
		for suffix in ["150","300"]:
			var voltage_energy := 0.
			for sample in samples:
				var voltage: float=float(sample.v.get("V%d_%s"%[i,suffix],0.))-float(sample.v.get("V%d_COM"%i,0.))
				voltage_energy+=voltage*voltage
			peak=maxf(peak,sqrt(voltage_energy/samples.size()))
		lab.readings.voltmeters[i]=peak

	for i in 2:
		var power := 0.
		for sample in samples:
			var voltage: float=float(sample.v.get("W%d_VP"%i,0.))-float(sample.v.get("W%d_VN"%i,0.))
			power+=voltage*float(sample.currents.get("W%d_I"%i,0.))
		lab.readings.wattmeters[i]=power/samples.size()

	for i in 4:
		var voltages: Array=[];var currents: Array=[]
		for sample in samples:
			voltages.append(float(sample.v.get("DAQ_E%d_P"%i,0.))-float(sample.v.get("DAQ_E%d_N"%i,0.)))
			currents.append(float(sample.currents.get("DAQ_I%d_4"%i,0.))+float(sample.currents.get("DAQ_I%d_40"%i,0.)))
		var voltage_fit := fit_signal(samples, voltages, lab.frequency)
		var current_fit := fit_signal(samples, currents, lab.frequency)
		if not lab.readings.has("daq_dc_v"):
			lab.readings.daq_dc_v = [Vector2.ZERO,Vector2.ZERO,Vector2.ZERO,Vector2.ZERO]
			lab.readings.daq_dc_i = lab.readings.daq_dc_v.duplicate()
		lab.readings.daq_v[i] = voltage_fit.ac
		lab.readings.daq_i[i] = current_fit.ac
		lab.readings.daq_dc_v[i] = Vector2(voltage_fit.dc, 0.)
		lab.readings.daq_dc_i[i] = Vector2(current_fit.dc, 0.)
	var ac_voltages := {}
	var dc_voltages := {}
	for port in occupied_ports:
		if not (port.begins_with("DAQ_A") or port.begins_with("DAQ_DI") or port.begins_with("DYN_") or port.begins_with("IGBT_")):
			continue
		var values: Array = []
		for sample in samples:
			values.append(float(sample.v.get(port, 0.)))
		var signal_fit := fit_signal(samples, values, lab.frequency)
		dc_voltages[port] = Vector2(signal_fit.dc, 0.)
		ac_voltages[port] = signal_fit.ac
	lab.readings.merge(Aux.readouts(ac_voltages, dc_voltages), true)
	lab.readings.igbt = Aux.switch_state(dc_voltages) if lab.powered else {}

static func fit_phasor(window: Array,values: Array,frequency: float) -> Vector2:
	var signal_fit := fit_signal(window, values, frequency)
	return signal_fit.ac + Vector2(signal_fit.dc, 0.) if signal_fit.ac == Vector2.ZERO else signal_fit.ac

static func fit_signal(window: Array,values: Array,frequency: float) -> Dictionary:
	if window.size()<3 or values.size()!=window.size():return {"ac":Vector2.ZERO,"dc":0.}
	# Fit DC + A cos(wt) + B sin(wt), including incomplete/nonuniform periods.
	var matrix: Array=[];var rhs := PackedFloat64Array([0.,0.,0.])
	for i in 3:matrix.append(PackedFloat64Array([0.,0.,0.]))
	var mean := 0.;var square := 0.
	for i in window.size():
		var angle: float=TAU*frequency*float(window[i].time)
		var basis := [1.,cos(angle),sin(angle)]
		mean+=float(values[i]);square+=float(values[i])*float(values[i])
		for row in 3:
			rhs[row]+=basis[row]*float(values[i])
			for col in 3:matrix[row][col]+=basis[row]*basis[col]
	mean/=window.size()
	if square/window.size()-mean*mean<1e-12:return {"ac":Vector2.ZERO,"dc":mean}
	var fit: Dictionary=preload("res://scripts/electronics_solver.gd").gaussian(matrix,rhs)
	return {"ac":Vector2(fit.x[1],-fit.x[2])/sqrt(2.),"dc":fit.x[0]} if fit.ok else {"ac":Vector2.ZERO,"dc":mean}
