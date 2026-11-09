extends RefCounted
const TOPICS := ["Equipment and measurement", "Sinusoids and phasors", "Series AC circuits", "Parallel AC power", "Series-parallel networks", "Three-phase power", "Power factor correction", "Induction motors", "Transformers", "Inverters", "Magnetism"]
const SOURCES := ["ELM253 Lab 1", "Sinusoidal Alternating Waveforms; Basic AC Circuits and Phasors", "ELM253 Lab 2", "ELM253 Lab 3", "ELM253 Lab 4 and Lab 6", "ELM253 Lab 5; Three-phase Power Measurement", "ELM253 Lab 7", "Three-Phase AC Induction Motors; Electrical Machines", "Lecture 8: Transformers", "Inverters", "Magnetism and Electromagnetism"]
static func question(prompt: String,answer: float,unit: String,explanation: String) -> Dictionary:
	return {"prompt":prompt,"answer":answer,"unit":unit,"explanation":explanation,"options":[]}
static func choice(prompt: String,options: Array,correct: int,explanation: String) -> Dictionary:
	return {"prompt":prompt,"answer":correct,"unit":"","explanation":explanation,"options":options}
static func generate(topic: int,difficulty: int,seed_value: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed=seed_value
	topic=clampi(topic,0,TOPICS.size()-1)
	difficulty=clampi(difficulty,0,2)
	var voltage := float([96,108,114][rng.randi_range(0,2)]) if difficulty==0 else snappedf(rng.randf_range(85,119),.1)
	var resistance := float([300,600,1200][rng.randi_range(0,2)])
	var inductance := float([0.8,1.6,3.2][rng.randi_range(0,2)])
	var frequency := float(rng.randi_range(45,65))
	var reactance := TAU*frequency*inductance
	var capacitance := float([2.2e-6,4.4e-6,8.8e-6][rng.randi_range(0,2)])
	# Keep even the near-resonant RLC calculation cases realizable below the
	# installed135V bank limit: |I|<=30/300A, |XL|<=2π·65·3.2Ω.
	if topic in [2,3,4,5,6]:voltage=float(rng.randi_range(240,300))/10.0
	var scenario := {"generator":"elm.v3","seed":seed_value,"topic":topic,"frequency_hz":frequency,"voltage_rms":voltage,"resistance_ohms":resistance,"inductance_henry":inductance,"capacitance_farad":capacitance}
	var q: Array=[]
	var data := "All voltages and currents are RMS unless stated. Use the explicitly stated model and round only final answers. Compatible engineering units are accepted; numeric tolerance is relative 2% with a small SI floor. Physical measurements include actual instrument loading."
	var theory := ""
	var procedure := ""
	match topic:
		0:
			theory="A voltmeter connects across two nodes. An ammeter goes in series. Choose a range above the expected reading. Parallel load switches add branch admittances; the equivalent resistance falls as more branches close."
			procedure="Turn supply OFF. Set variable output to zero. Identify the source, return, and meter ranges. Build a resistor branch with an ammeter in series and a voltmeter across the resistor. Check the wiring before powering it. Turn OFF before moving leads."
			var other := float([300,600,1200][rng.randi_range(0,2)])
			var expected := voltage/resistance
			scenario.other_resistance_ohms=other
			data+="\nR1=%.1f Ω; R2=%.1f Ω; source=%.1f V."%[resistance,other,voltage]
			q=[choice("How is an ammeter connected?",["Across the source","In series with the branch","Across an open switch"],1,"The measured branch current must pass through the ammeter."),choice("Before changing the wiring:",["Increase voltage","Turn the supply off","Short the terminals"],1,"Isolate the supply before changing leads."),question("Equivalent resistance of the given R1 and R2 in parallel",1.0/(1.0/resistance+1.0/other),"Ω","Add reciprocal resistances, then invert."),question("Current through R1 alone",expected,"A","I=V/R using the given source and resistance.")]
		1:
			var second_voltage := float(rng.randi_range(100,600))/10.0
			scenario.second_phasor_imag=second_voltage
			theory="A sinusoid has Vrms = Vpeak/√2 and period T = 1/f. Phasors describe magnitude and phase at one frequency. Add rectangular components, not magnitudes."
			data+="\nVrms = %.1f V; f = %.1f Hz; second phasor = j%.1f V."%[voltage,frequency,second_voltage]
			q=[question("Peak voltage",voltage*sqrt(2),"V","Vpeak = √2 Vrms."),question("Period",1000/frequency,"ms","T = 1/f."),question("Magnitude of V + jX",Vector2(voltage,second_voltage).length(),"V","Magnitude = √(V² + X²)."),question("Phase angle of V + jX",rad_to_deg(atan2(second_voltage,voltage)),"degrees","Angle = atan2(X,V).")]
		2:
			var xc := 0.0 if difficulty==0 else 1.0/(TAU*frequency*capacitance)
			var extra_r := 0.0 if difficulty<2 else 1200.0/7.0
			var z := Vector2(resistance+extra_r,reactance-xc)
			scenario.extra_resistance_ohms=extra_r;scenario.xc_ohms=xc
			var current := voltage/z.length()
			data+="\nSeries circuit: %.1f V, R1 = %.1f Ω, R2 = %.2f Ω, XL = %.1f Ω, XC = %.1f Ω. XC = 0 means omit the capacitor."%[voltage,resistance,extra_r,reactance,xc]
			procedure="Bench task: use variable source terminal 4 and N. Wire source → series ammeter → one resistor bank → one inductor bank → return. When specified add the selected capacitor bank in series. For Advanced add a second resistor bank with all three switches on (1200/7 Ω). Set the stated supply voltage and frequency. Choose the actual catalog R/L/C settings stated in the scenario, and verify current and component voltages. Keep unused switches OFF."
			theory="Series elements share current. Z = R + j(XL − XC); I = V/Z. Individual RMS voltage magnitudes do not add arithmetically. Real power is I²R; reactive power is I²(XL − XC)."
			q=[question("Magnitude of impedance",z.length(),"Ω","|Z| = √((R1+R2)²+(XL−XC)²)."),question("Circuit current",current,"A","I = V/|Z|."),question("Real power",current*current*z.x,"W","P = I²(R1+R2)."),question("Power factor",z.x/z.length(),"","PF = R/|Z|."),question("Inductor voltage",current*reactance,"V","VL = I XL.")]
		3:
			var xc := 1.0/(TAU*frequency*capacitance) if difficulty>0 else 0.0
			scenario.xc_ohms=xc
			var ir := voltage/resistance
			var iq: float = -voltage/reactance+(voltage/xc if xc>0 else 0)
			data+="\nParallel branches: %.1f V across R = %.1f Ω, XL = %.9f Ω, XC = %.9f Ω. XC = 0 means omit that branch."%[voltage,resistance,reactance,xc]
			procedure="Sketch R, L, and (when specified) C branches between common source and return nodes. Use stacked banana plugs to form the junctions. Measure source current in series before the split; measure branch current in each branch separately. For a physical comparison, choose available bank values and recalculate using their actual R, L and C; the randomized values here define the calculation exercise."
			theory="Parallel branches share voltage. Take voltage as the reference: IR = V/R, IL = −jV/XL, IC = +jV/XC. Total current is the vector sum. Ideal inductors consume reactive power; real coils also have loss."
			q=[question("Resistor branch current",ir,"A","IR = V/R."),question("Inductor branch current magnitude",voltage/reactance,"A","IL = V/XL."),question("Supply current magnitude",Vector2(ir,iq).length(),"A","Add real and imaginary current components."),question("Real power",voltage*ir,"W","Only the ideal resistor consumes average power."),question("Net reactive power",-voltage*iq,"var","Q = V²/XL − V²/XC when the capacitor is present.")]
		4:
			var r2 := float([300,600,1200][rng.randi_range(0,2)])
			var xc := 1.0/(TAU*frequency*capacitance)
			scenario.second_resistance_ohms=r2;scenario.xc_ohms=xc
			# R || (-j XC), followed by R2 and j XL.
			var parallel := Vector2(resistance*xc*xc,-resistance*resistance*xc)/(resistance*resistance+xc*xc)
			var z := parallel+Vector2(r2,reactance)
			var current := voltage/z.length()
			data+="\nSource %.1f V → R2 %.2f Ω → XL %.9f Ω → (R1 %.1f Ω in parallel with XC %.9f Ω) → return."%[voltage,r2,reactance,resistance,xc]
			theory="Reduce parallel branches using complex admittance, then add series impedances. Find source current before recovering branch voltages and currents. Verify with KCL and KVL using phasors."
			q=[question("Real part of total impedance",z.x,"Ω","Zparallel = R(−jXC)/(R−jXC); add R2."),question("Imaginary part of total impedance",z.y,"Ω","Add XL to the imaginary part of Zparallel."),question("Source current magnitude",current,"A","I = V/|Ztotal|."),question("Voltage across the parallel section",current*parallel.length(),"V","Vparallel = I |Zparallel|."),question("Total real power",current*current*z.x,"W","P = I² Re(Ztotal).")]
		5,6:
			var ir := voltage/resistance
			var il := voltage/reactance
			var line_current := Vector2(ir,il).length()
			var power := 3*voltage*ir
			var reactive := 3*voltage*il
			data+="\nBalanced wye load: phase voltage %.1f V, each phase has R = %.1f Ω in parallel with XL = %.1f Ω; f = %.1f Hz."%[voltage,resistance,reactance,frequency]
			procedure="Connect three equal R/L parallel phase branches in wye, with a common neutral point. Measure phase and line voltages. For two-wattmeter work use the stated sign convention and preserve each current-coil direction. For correction, connect an equal capacitor branch across each phase and compare source current before and after. Use available capacitance steps and compute their actual var at the measured phase voltage."
			theory="In balanced wye, Vline = √3 Vphase and Iline = Iphase. P = √3 Vline Iline PF. Two-wattmeter total power is W1 + W2. With the stated wiring convention, Q = √3(W2 − W1). A shunt capacitor supplies leading var and reduces lagging supply current; too much capacitance overcorrects."
			q=[question("Line-to-line voltage",voltage*sqrt(3),"V","VL = √3 Vphase."),question("Line current before correction",line_current,"A","Iline = √((V/R)²+(V/XL)²)."),question("Total real power",power,"W","P = 3 Vphase²/R."),question("Total reactive power",reactive,"var","Q = 3 Vphase²/XL.")]
			if topic==6:
				var qc := 3*TAU*frequency*capacitance*voltage*voltage
				var signed_target_q := reactive-qc
				data+="\nBring the total signed reactive power to %.9f var using identical wye capacitors, one per phase. Negative target means net leading behavior. The target is realizable with a catalog capacitor bank setting."%signed_target_q
				scenario.target_q_var=signed_target_q
				q.append(question("Capacitance per phase",qc/(3*TAU*frequency*voltage*voltage)*1e6,"µF","Qc=Qold-Qtarget (signed); Cphase=Qc/(3ωVphase²). Do not discard the leading/lagging sign."))
			else:
				q.append(question("W1 for Q = √3(W2 − W1)",(power-reactive/sqrt(3))/2,"W","Solve W1+W2=P and W2−W1=Q/√3."))
		7:
			var poles: int = [2,4,6][rng.randi_range(0,2)]
			var sync: float = 120*frequency/poles
			var slip := float(rng.randi_range(25,85))/1000.0
			var speed: float = sync*(1-slip)
			scenario.poles=poles;scenario.rotor_rpm=speed;scenario.shaft_watts=voltage
			data+="\nInduction motor: %d poles, %.1f Hz, rotor speed %.3f rpm, shaft output %.1f W."%[poles,frequency,speed,voltage]
			theory="The rotating stator field travels at ns = 120f/p. Rotor slip s = (ns−nr)/ns is needed to induce rotor current and torque. Rotor electrical frequency is sf. Mechanical output P = Tω."
			q=[question("Synchronous speed",sync,"rpm","ns = 120f/p."),question("Slip",slip*100,"%","s = (ns−nr)/ns."),question("Rotor electrical frequency",slip*frequency,"Hz","fr = sf."),question("Shaft torque",voltage/(speed*TAU/60),"N·m","T = P/ω and ω = 2πnr/60.")]
		8:
			var ratio: float = [2.0,0.5,120.0/104.0,120.0/208.0][rng.randi_range(0,3)]
			voltage=float(rng.randi_range(300,600))/10.0
			scenario.primary_voltage=voltage;scenario.turns_ratio=ratio
			var vs: float = voltage/ratio
			data+="\nIdeal transformer: primary %.1f V; Np/Ns = %.9f; resistive secondary load %.1f Ω."%[voltage,ratio,resistance]
			theory="Ideal transformer voltage ratio follows turns: Vp/Vs = Np/Ns = a. Current ratio is inverse. Impedance referred to the primary is a²Zload. Frequency stays unchanged. Real transformers have winding and core losses."
			q=[question("Secondary voltage",vs,"V","Vs = Vp/a."),question("Secondary current",vs/resistance,"A","Is = Vs/Rload."),question("Primary current",vs/resistance/ratio,"A","Ip = Is/a."),question("Load referred to the primary",resistance*ratio*ratio,"Ω","Zin = a²Zload.")]
		9:
			var hz := frequency*100
			scenario.switching_hz=hz
			data+="\nIdeal full bridge: DC bus %.1f V, bipolar square-wave output, 50%% duty cycle, switching frequency %.1f Hz, load %.1f Ω."%[voltage,hz,resistance]
			theory="An inverter converts DC to AC. A full bridge alternates output polarity. Never turn on both switches in one leg together: this shorts the DC link. Inductive current continues through feedback diodes during commutation."
			q=[question("Output period",1e6/hz,"µs","T = 1/f."),question("Positive pulse duration",.5e6/hz,"µs","At 50% duty, ton = T/2."),question("Square-wave RMS output voltage",voltage,"V","An ideal bipolar square wave has constant |V|."),question("Resistive load power",voltage*voltage/resistance,"W","P = Vrms²/R."),choice("Why provide dead time?",["Prevent same-leg shoot-through","Increase DC voltage","Remove all harmonics"],0,"Dead time prevents simultaneous conduction in one leg.")]
		10:
			var turns := rng.randi_range(2,8)*100
			var area := float(rng.randi_range(10,40))*0.0001
			var change := voltage*.00001
			var interval := float(rng.randi_range(10,50))/1000.0
			var coil_current := float(rng.randi_range(10,80))/100.0
			scenario.turns=turns;scenario.area_m2=area;scenario.flux_change_wb=change;scenario.interval_seconds=interval;scenario.coil_current=coil_current
			data+="\nCoil: %d turns, core area %.4f m². Flux increases uniformly by %.9f Wb in %.3f s. Coil current is %.2f A."%[turns,area,change,interval,coil_current]
			theory="Flux density B = Φ/A. Magnetomotive force is NI ampere-turns. Faraday’s law gives emf magnitude N|dΦ/dt|; Lenz’s law determines its opposing polarity."
			q=[question("Induced emf magnitude",turns*change/interval,"V","|e| = N ΔΦ/Δt."),question("Flux-density change",change/area,"T","ΔB = ΔΦ/A."),question("Magnetomotive force",turns*coil_current,"A·turns","MMF = NI.")]
	if procedure=="":
		procedure="1. Draw and label the circuit or machine described on page 1.\n2. Write the governing equations before substituting values.\n3. Calculate phasors in rectangular form; convert to magnitude/angle at the end.\n4. For supported R/L/C circuits, reproduce a realizable equivalent on the bench: supply OFF, set ranges, wire, inspect, then energize.\n5. Record measured values in the working area and compare with your predictions.\n6. Power OFF before rewiring. Transformer, inverter, and machine questions use the stated theoretical model; do not treat this simulator as equipment certification."
	for i in range(q.size()):q[i].template_id="elm.%d.%d"%[topic,i];q[i].inputs=scenario.duplicate(true)
	return {"title":TOPICS[topic],"topic":topic,"difficulty":difficulty,"data":data,"theory":theory,"procedure":procedure,"questions":q,"source":SOURCES[topic],"seed":seed_value,"scenario":scenario}
static func public_copy(project: Dictionary,marked: bool=false) -> Dictionary:
	if project.has("course_id"):
		return load("res://scripts/campus/courses/course_provider.gd").public_copy(project,marked)
	var result := project.duplicate(true)
	if not marked:
		for q in result.questions:
			q.erase("answer")
			q.erase("explanation")
			q.erase("inputs")
	return result
static func grade(project: Dictionary,answers: Dictionary) -> Dictionary:
	if project.has("course_id"):
		return load("res://scripts/campus/courses/course_provider.gd").grade(project,answers)
	var earned := 0
	var feedback: Array=[]
	for i in range(project.questions.size()):
		var q: Dictionary=project.questions[i]
		var raw := str(answers.get(str(i),"")).strip_edges()
		var correct := false
		if not q.options.is_empty():
			correct=raw.is_valid_int() and int(raw)==int(q.answer)
		else:
			correct=preload("res://scripts/campus/courses/quantity.gd").check(q,raw).correct
		if correct:earned+=1
		feedback.append({"correct":correct,"expected":q.options[int(q.answer)] if not q.options.is_empty() else "%.5f %s"%[q.answer,q.unit],"explanation":q.explanation})
	return {"score":100.0*earned/maxi(1,project.questions.size()),"feedback":feedback}

# Campus facade uses a runtime load to avoid a preload cycle with the legacy AC provider.
static func generate_course(course_id: String,kind: String,week: int,difficulty: int,seed_value: int) -> Dictionary:
	return load("res://scripts/campus/courses/course_provider.gd").generate(course_id,week,kind,difficulty,seed_value)
static func course_catalog() -> Array:
	return load("res://scripts/campus/courses/course_provider.gd").catalog()
static func course_weeks(course_id: String,kind: String="lecture") -> Array:
	return load("res://scripts/campus/courses/course_provider.gd").weeks(course_id,kind)
