extends RefCounted
## Read-only equipment teaching data drawn from dc_station, equipment_builder and lab_state.
const COURSES := {"ac_lab":"ELM253","dc_lab":"ETY155"}

static func devices(lab_id: String) -> Array:
	if lab_id=="dc_lab":return _dc()
	if lab_id=="ac_lab":return _ac()
	return []

static func find(lab_id: String,id: String) -> Dictionary:
	for device in devices(lab_id):
		if device.id==id:return device
	return {}

static func _device(id: String,title: String,purpose: String,output: String,controls: String,ports: String,mistakes: String,detail: String,steps: Array) -> Dictionary:
	return {"id":id,"title":title,"purpose":purpose,"output":output,"controls":controls,"ports":ports,"mistakes":mistakes,"detail":detail,"steps":steps}

static func _step(instruction: String,cue: String,check: Dictionary={}) -> Dictionary:
	return {"instruction":instruction,"cue":cue,"check":check}

static func _dc() -> Array:
	return [
		_device("supply","Three-channel DC supply","Produces three independently adjustable DC outputs.","Voltage, current, power and CV/CC state for each channel.","Each channel has voltage, current limit and enable; master enables the selected channels.","CH1+/CH1-, CH2+/CH2-, CH3+/CH3- are isolated pairs.","A high current limit does not force current into a load. Do not short outputs to test voltage.","Start with one channel and a modest current limit. CV holds set voltage; CC reduces voltage to cap current.",[
			_step("Find the power supply and its three channel displays.","psu"),
			_step("Adjust channel 1 voltage; watch its setpoint change.","psu_ch1_voltage",{"op":"channel","key":"voltage","index":0}),
			_step("Set channel 1's current limit before enabling output.","psu_ch1_limit",{"op":"channel","key":"limit","index":0}),
			_step("Enable channel 1, then turn on master output.","psu_ch1_enable",{"op":"channel","key":"enabled","index":0,"value":true}),
			_step("Turn on master. A connected load will now receive power.","psu_master",{"op":"master","state":["master"],"equals":true}),
			_step("Connect a lead from CH1+ to a load input.","CH1+",{"op":"wire","port":"CH1+"})]),
		_device("meter","Digital multimeter","Measures voltage across points, current through a path and passive components.","Live solver reading with V, A, Ω or status such as OL/FUSE OPEN.","Mode selector, full-scale range and fuse replacement with outputs off.","VΩ and COM for voltage/passive tests; A and COM form the 0.1 Ω, 1 A fused series input.","Never put A and COM directly across a live supply. Resistance, continuity and diode tests require sources off.","Select DC V to compare two points. For current, break the path and insert A/COM in series. Use the correct mode and range.",[
			_step("Find the meter and identify VΩ, COM and A.","meter"),
			_step("Select DC V mode on the meter.","meter_mode",{"op":"meter","mode":"DC V"}),
			_step("Connect VΩ to the point being measured and COM to its reference.","VΩ",{"op":"wire","port":"VΩ"}),
			_step("Read the displayed voltage. It comes from the actual circuit.","meter",{"state":["meter"],"contains":"V"})]),
		_device("generator","Function generator","Produces a selected periodic or DC test signal.","Waveform, frequency, peak amplitude and offset; output depends on connected load.","Wave selection; frequency, amplitude and offset knobs; independent output enable. Phase, duty and impedance remain in the instrument panel.","GEN is the output and REF is its return.","Output enable is separate from the DC supply master. Do not mistake peak amplitude for RMS.","Choose sine, square, triangle, sawtooth, pulse or DC; wire GEN and REF across the desired load and inspect the waveform.",[
			_step("Find the generator and its GEN and REF terminals.","generator"),
			_step("Change the waveform or frequency.","generator_wave",{"op":"generator","key":"wave"}),
			_step("Enable the output when the circuit is ready.","generator_output",{"op":"generator","key":"enabled","value":true}),
			_step("Connect GEN to the test load.","GEN",{"op":"wire","port":"GEN"})]),
		_device("scope","Digital oscilloscope","Shows voltage against time from the real electrical record.","CH1/CH2 traces, peak-to-peak, RMS and frequency when enough samples exist.","Run/stop, timebase, trigger level and each channel's volts/div; further settings in its panel.","S1 and S2 are channel inputs; both use GND as the common reference.","A disconnected input yields no valid circuit signal. Probe factor calibrates displayed tip voltage; it is not a physical divider.","Connect S1 and GND across a signal, run acquisition, then adjust time/div and volts/div to fit the trace.",[
			_step("Find the scope screen and S1/S2/GND connectors.","scope_trace"),
			_step("Connect S1 to a signal and GND to its reference.","S1",{"op":"wire","port":"S1"}),
			_step("Adjust the shared timebase.","scope_timebase",{"op":"scope","key":"timebase"}),
			_step("Adjust CH1 volts per division.","scope_ch1_scale",{"op":"scope","key":"scale","channel":0}),
			_step("Observe an acquired sample record.","scope_trace",{"state":["samples"],"min_size":2})]),
		_device("current_sources","Current sources","Drive a chosen current until compliance voltage is reached.","Mode, output current and compliance voltage for four separate sources.","Set output enable, current and compliance in Current source. Turn on master output.","IS+/IS-, IS2+/IS2-, IS3+/IS3-, IS4+/IS4-.","At compliance the current falls with the load; a displayed setpoint is not proof of delivered current.","Connect one source pair across a suitable load, enable it and compare actual current with setpoint.",[
			_step("Open the instrument panel from the scope screen and find Current source.","scope_trace"),
			_step("Enable source 1 in Current source after setting its current and compliance.","scope_trace",{"op":"current_source","key":"enabled","index":0,"value":true}),
			_step("Connect IS+ to a suitable load in Leads & components.","scope_trace",{"op":"wire","port":"IS+"})]),
		_device("loads","Resistor, capacitor and diode modules","Provide real passive components for bench circuits.","Resistance is adjustable; capacitor value is adjustable; diode has defined anode/cathode.","R1/R2 and capacitor values are in Leads & components.","R1a/R1b, R2a/R2b, Ca/Cb and Da/Db are actual electrical nodes.","Observe diode polarity and capacitor charging. Disable sources before resistance testing.","Build a single resistor loop first; calculate I=V/R and compare the meter current.",[
			_step("Find R1a and R1b in Leads & components.","scope_trace"),
			_step("Attach a lead to R1a in Leads & components.","scope_trace",{"op":"wire","port":"R1a"}),
			_step("Change the resistor value in Leads & components.","scope_trace",{"op":"resistor","index":0})]),
		_device("breadboard","Breadboard and test leads","Build and reconnect small circuits without soldering.","Bench B1–B4 posts route into the deployed board; X pins appear for standalone packages.","Click one DC socket, then another to add a lead; right click removes it.","B1–B4 are available in Leads & components. Breadboard A–E and F–J rows are separate strips; P/N rails split halfway.","A drawn crossing is not automatically a connection. Move or stow boards only after checking attached leads.","Connect one lead at a time and inspect the actual displayed connection before applying power.",[
			_step("Find B1–B4 in Leads & components.","scope_trace"),
			_step("Attach one end of a lead to B1 in Leads & components.","scope_trace",{"op":"wire","port":"B1"}),
			_step("Confirm the new lead appears in the connected-leads list.","scope_trace",{"state":["wires"],"min_size":1})])]

static func _ac() -> Array:
	return [
		_device("ac_supply","AC training supply","Provides fixed and adjustable AC and DC, plus a 24 V AC outlet.","Its selector displays the chosen output voltage.","I/O power, variable level dial, built-in display selector.","P_A/P_B/P_C/P_N fixed; PV_A/PV_B/PV_C/PV_N variable; DC_7/DC_N7 variable; DC_8/DC_N8 fixed; LOW_0/LOW_1 24 V AC.","The display selector does not set voltage. De-energize before changing a training circuit.","Begin with power off, choose the intended fixed or variable pair, then check before energizing.",[
			_step("Find the AC supply and identify fixed and variable terminal columns.","P_A"),
			_step("Adjust the variable output dial.","variable",{"op":"voltage"}),
			_step("Perform the existing preflight check before power.","power",{"op":"check"})]),
		_device("ac_voltmeters","AC voltmeters","Measure potential difference between two points.","Three independent V meters and their selected ranges.","Each meter has a common ± input and 100/250 labeled range inputs.","V0_COM/V0_150/V0_300 through V2_COM/V2_150/V2_300.","A voltmeter connects in parallel. Keep both leads on the same meter and begin on the larger range.","Wire one common and one range socket across the component being compared.",[
			_step("Find the three voltmeters and their common/range sockets.","V0_COM"),
			_step("Connect a lead to V0_COM.","V0_COM",{"op":"plug","port":"V0_COM"})]),
		_device("ac_ammeters","AC ammeters","Measure current flowing through a path.","Three independent A meters with selectable input ranges.","Each meter has ±/OUT and marked current inputs, including 0.5, 2.5 and 8 A choices.","AM0_OUT/AM0_IN/AM0_2_5/AM0_8; the second meter also has AM1_25.","Insert an ammeter in series; direct supply-to-return connection can overload it.","Break one branch and place the meter between its two ends, starting on a safe range.",[
			_step("Find an ammeter's ± socket and range sockets.","AM0_OUT"),
			_step("Connect a lead to AM0_OUT while power is off.","AM0_OUT",{"op":"plug","port":"AM0_OUT"})]),
		_device("ac_wattmeters","Three-phase wattmeter","Measures real electrical power.","Signed watts for the existing meter wiring.","Two meter sections with current and voltage connections.","W0_IN/W0_OUT/W0_VN and W1_IN/W1_OUT/W1_VN; W0_VP/W1_VP are registered auxiliary nodes.","Current coil belongs in the path; voltage coil compares points. Preserve negative signs.","Follow a provided assignment diagram rather than guessing a three-phase hookup.",[
			_step("Locate wattmeter current and voltage posts.","W0_IN"),
			_step("Connect the current path through W0_IN.","W0_IN",{"op":"plug","port":"W0_IN"})]),
		_device("rlc","R/L/C load banks","Resistance consumes power; inductance and capacitance store energy.","Nine switches per R, L and C group combine the printed values.","Three banks per module; each bank has top/bottom ports and three switches.","R0_P/R0_N, L0_P/L0_N, C0_P/C0_N and corresponding bank 1/2 ports.","Several ON switches within a bank place values in parallel; do not assume series addition.","De-energize, switch one branch, then compare voltage and current.",[
			_step("Find R, L and C panels and their three banks.","R0_P"),
			_step("Toggle one R-bank switch with power off.","R_0",{"op":"switch","kind":"R","index":0})]),
		_device("ac_motor","Three-phase induction motor","Turns electrical three-phase input into mechanical rotation.","Motor response depends on real supply/wiring/load state.","Six winding posts; supplied assignments show the proper connection diagram.","M1/M4, M2/M5, M3/M6 are the three winding pairs.","Wye and Delta require different physical links; do not rearrange while energized.","For Wye, join one end of each winding. For Delta, connect the end of each winding to the start of the next; follow the assignment's diagram.",[
			_step("Find the three motor winding pairs.","M1"),
			_step("Connect a lead to M1 while power is off.","M1",{"op":"plug","port":"M1"})]),
		_device("dynamometer","Electrodynamometer","Applies a mechanical load to the motor.","Brake torque depends on coil excitation and the load setting.","Load knob and held measuring control.","DYN_0 and DYN_1 take 120 V AC coil excitation.","Do not confuse mechanical load setting with electrical output voltage.","Power the coil, adjust the load in small steps, then hold the measuring control.",[
			_step("Locate the dynamometer load control.","dyn_load"),
			_step("Adjust its load slightly.","dyn_load",{"op":"dyn_load"}),
			_step("Use the held measurement control.","dyn_measure",{"op":"dyn_measure","pressed":true})]),
		_device("daq","Data acquisition panel","Reads voltage/current channels and supports the implemented I/O view.","E1–E4 voltage, I1–I4 current, eight analog and three digital inputs.","Computer I/O opens the readout and sets two analog and two digital outputs.","DAQ_E0_N/DAQ_E0_P and DAQ_I0_N/DAQ_I0_4/DAQ_I0_40 begin the channel sets.","Put current inputs in series. AI and DO reference DAQ signal common.","Wire a voltage pair or current path and inspect the measured channel.",[
			_step("Find DAQ voltage and current channel inputs.","DAQ_E1_P"),
			_step("Connect an E1 voltage lead.","DAQ_E1_P",{"op":"plug","port":"DAQ_E1_P"})]),
		_device("transformer","Training transformer","Changes AC voltage using coupled winding sections.","Voltage ratio depends on which existing winding posts are used.","Winding posts are labeled by section; no adjustable knob is modeled.","TX_1/TX_2 are the 120 V winding; other TX posts have their printed ratios.","Numbers identify terminals, not live voltage. De-energize before reconnecting windings.","Choose a documented primary and secondary section, then compare their AC voltages.",[
			_step("Find TX_1 and TX_2 on the transformer.","TX_1"),
			_step("Connect a lead to TX_1 with power off.","TX_1",{"op":"plug","port":"TX_1"})]),
		_device("inverter","IGBT training panel","Switches a DC bus through three independently gated output legs.","A gate above 2.5 V selects its bus rail. Coupled circuits can drive the gates with pulses.","Damping adds a load across the bus. DISABLE high opens all three output legs.","IGBT_GATE1..6, IGBT_DISABLE, IGBT_SYNC, IGBT_COMMON and labeled output posts.","Each leg opens if both of its gates are high.","Use posts 1 and 2 for the DC bus. Observe the switched voltage at posts 3 through 5.",[
			_step("Find the IGBT training panel.","IGBT_COMMON"),
			_step("Use the damping control.","igbt_damping",{"op":"igbt_damping"})]),
		_device("leads","AC connection leads","Connect physical rack sockets to build an experiment.","Installed leads appear in the real cable state.","Open the drawer, take a colored lead, then click two reachable sockets.","Only actual printed rack sockets are valid endpoints.","A lead can reach 5 m; do not alter an energized circuit outside free-lab rules.","Pick up one cable, connect both ends, and inspect the powered-off circuit first.",[
			_step("Open a bench cable drawer.","storage",{"op":"drawer"}),
			_step("Pick up a lead.","storage",{"op":"pickup"}),
			_step("Connect one end to a valid socket.","P_A",{"op":"plug"})])]
