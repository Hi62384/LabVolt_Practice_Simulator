extends RefCounted
## Author-created explicit topologies. The existing physical electronics MNA solver
## supplies every reference operating point; this is not a second course solver.
const Solver = preload("res://scripts/electronics_solver.gd")
static func part(id: String,kind: String,a: String,b: String,value: float) -> Dictionary:
	return {"id":id,"kind":kind,"a":a,"b":b,"value":value,"resistance":0.0}
static func solve(parts: Array) -> Dictionary:
	return Solver.new().solve(parts,[])
static func stocked(index: int) -> float:
	return float([1000,2200,4700,10000,47000,100000][posmod(index,6)])
static func numeric(prompt: String,value: float,unit: String,why: String) -> Dictionary:
	return {"prompt":prompt,"answer":value,"unit":unit,"explanation":why,"options":[],"relative_tolerance":0.015,"absolute_tolerance_si":1e-9}
static func choice(prompt: String,options: Array,answer: int,why: String) -> Dictionary:
	return {"prompt":prompt,"answer":answer,"options":options,"unit":"","explanation":why}
static func build(week: int,difficulty: int,seed_value: int) -> Dictionary:
	var rng := RandomNumberGenerator.new();rng.seed=seed_value
	var d := clampi(difficulty,0,4)
	var v := float(rng.randi_range(30,120))/10.0
	var r := stocked(rng.randi_range(0,5))
	var tolerance := float([0.01,0.05][rng.randi_range(0,1)])
	var rating := float([0.25,0.5,1.0][rng.randi_range(0,2)])
	var five := colour_case(rng)
	var four := colour_case(rng)
	four.bands=bands(float(four.nominal),2,float(four.tolerance))
	var elapsed := rng.randi_range(12,120)
	var parts: Array=[part("Vs","V","p","g",v)]
	var q: Array=[]
	var target := "R1"
	var gates: Array=[]
	var variants: Array=[]
	match week:
		1,2:
			parts.append(part("R1","R","p","g",r))
			if week==1:
				q.append(choice("Where must the ammeter be connected?",["Across the source","In series with R1","Across a wire"],1,"The branch current must pass through the ammeter."))
				q.append(numeric("Convert R1 to kilo-ohms",r/1000.0,"kΩ","Divide ohms by 1000."))
			else:
				q.append(numeric("Four-band separate resistor: %s. Nominal resistance?"%", ".join(four.bands),float(four.nominal),"Ω","Two significant digits, multiplier and tolerance; no early rounding."))
				q.append(numeric("Minimum resistance for R1 at ±%.0f%%"%(tolerance*100),r*(1-tolerance),"Ω","Rmin = nominal × (1-tolerance)."))
				q.append(numeric("Maximum resistance for R1 at ±%.0f%%"%(tolerance*100),r*(1+tolerance),"Ω","Rmax = nominal × (1+tolerance)."))
				if d>=2:q.append(numeric("Five-band %s nominal resistance"%"-".join(five.bands),float(five.nominal),"Ω","Three significant digits × multiplier; final band specifies tolerance."))
			if d>=1:q.append(numeric("Maximum voltage for R1 with %.2f W rating and 30 V equipment ceiling"%rating,minf(30,sqrt(rating*r)),"V","Use the smaller of 30 V and sqrt(Pmax R)."))
			if d>=2:
				parts.append(part("R2","R","p","g",2200))
				q.append(numeric("Current delivered to both parallel branches",v/r+v/2200.0,"A","Add branch currents, after converting resistances to ohms."))
			if d>=3:
				q.append(numeric("Minimum resistance of that five-band resistor (tolerance %.0f%%)"%(float(five.tolerance)*100),float(five.nominal)*(1-float(five.tolerance)),"Ω","Decode the generated bands, then subtract the stated percentage of nominal."))
				q.append(numeric("Energy dissipated by R1 in %d s"%elapsed,v*v/r*elapsed,"J","Energy = power × elapsed seconds."))
		3:
			r=10000.0
			var x := float(rng.randi_range(2,8))/10.0
			parts.append(part("R1","R","p","w",r*x));parts.append(part("R2","R","w","g",r*(1-x)))
			q.append(choice("What happens to end-to-end resistance as the unloaded wiper moves?",["It stays at the track resistance","It always becomes zero","It doubles"],0,"The segment resistances change; their sum remains the fixed track resistance."))
			q.append(numeric("Unloaded wiper-to-return voltage",v*(1-x),"V","Wiper fraction x is measured from p toward g: Vwg = Vs(1-x)."))
			if d>=2:
				parts.append(part("RL","R","w","g",10000))
				q.append(numeric("Loaded wiper-to-return voltage",float(solve(parts).drop.R2),"V","The load is parallel with the lower pot segment; account for loading."))
			q.append(choice("Which connectivity determines a valid breadboard circuit?",["Nearby-looking holes","Actual connected nodes including split rails","Wire colour"],1,"Use actual breadboard continuity, never visual resemblance."))
			var board_model = preload("res://scripts/breadboard_model.gd")
			for i in range(2+d):
				var row := rng.randi_range(1,30)
				var a := "A%d"%row
				var b := ("E" if i%2==0 else "F")+str(row)
				var connected: bool=board_model.node(a,30)==board_model.node(b,30)
				q.append(choice("Actual simulator 30-row breadboard: are %s and %s internally connected?"%[a,b],["Connected","Not connected"],0 if connected else 1,"Use the actual breadboard model: A-E share a row; F-J share a separate row. The center gap separates the strips."))
			if d>=2:q.append(choice("Are rail holes P1 and P30 internally continuous on this simulator's 30-row board?",["Yes","No, the rail is split"],1,"The actual board model separates rows1-15 from16-30; bridge it explicitly if required."))
			if d>=1:q.append(numeric("Resistance from p to w",r*x,"Ω","RAW = x RAB under the declared position convention."))
			if d>=3:q.append(numeric("Wiper current into the external load",float(solve(parts).i.RL),"A","Account for the load that changes the divider voltage."))
		4:
			var count := 2+d
			for i in range(count):parts.append(part("R%d"%(i+1),"R","p" if i==0 else "n%d"%i,"g" if i==count-1 else "n%d"%(i+1),r if i==0 else stocked(i)))
		5:
			for i in range(2+d):parts.append(part("R%d"%(i+1),"R","p","g",r if i==0 else stocked(i)))
		6,7:
			parts.append(part("R1","R","p","n",r))
			for i in range(2+d):parts.append(part("R%d"%(i+2),"R","n","g",stocked(i)))
			if week==7:
				var limit_power := v*v/r
				var ratings: Array=[0.125,0.25,0.5]
				var minimum := 0
				while minimum<2 and float(ratings[minimum])<limit_power:minimum+=1
				var selection := choice("A separate %.1f V source feeds %.0f Ω. Lowest adequate rating from these choices?"%[v,r],["0.125 W","0.25 W","0.5 W"],minimum,"Calculate P=V²/R, then select the first rating at least that large; do not energize an underrated part.")
				selection.calculation_kind="rating_selection"
				q.append(selection)
		8:
			parts[0]=part("Vs","V","p","m",v)
			parts.append(part("V2","V","g","m",v/3.0))
			parts.append(part("R1","R","p","g",r))
			q.append(numeric("Signed V(g)-V(p)",-v*2.0/3.0,"V","The opposed sources leave Vpg = Vs - Vs/3."))
			for i in range(d):parts.append(part("Rextra%d"%i,"R","p","g",stocked(i+1)))
			if d>=2:
				parts.append(part("R2","R","p","n",r));parts.append(part("R3","R","n","g",2200))
		9:
			# Avoid an accidentally balanced zero-current source branch, whose tiny
			# physical meter-loading current otherwise dominates a relative rubric.
			r=stocked(rng.randi_range(0,2))
			parts.append(part("V2","V","p2","g",v/2.0))
			parts.append(part("R1","R","p","n",r));parts.append(part("R2","R","p2","n",2200));parts.append(part("RL","R","n","g",10000))
			for i in range(d):parts.append(part("Rextra%d"%i,"R","n","g",stocked(i+1)))
			if d>=3:
				parts.append(part("V3","V","g","p3",v/3.0));parts.append(part("R3","R","p3","n",4700))
			for p in parts:
				if p.kind!="V":continue
				var only := parts.duplicate(true)
				for source in only:
					if source.kind=="V" and source.id!=p.id:source.value=0.0
				q.append(numeric("Signed load voltage from %s alone"%p.id,float(solve(only).drop.RL),"V","Deactivate other independent voltage sources to zero volts; retain resistors."))
			target="RL"
		10,11:
			parts.append(part("R1","R","p","n",r));parts.append(part("R2","R","n","g",2200))
			for i in range(d):parts.append(part("Rextra%d"%i,"R","n","g",stocked(i+2)))
			var open := solve(parts)
			var dead := parts.duplicate(true);dead[0].value=0.0
			dead.append(part("test","I","g","n",0.001))
			var rth := float(solve(dead).drop.test)*-1000.0
			var vth := float(open.drop.R2)
			q.append(numeric("Open-circuit port voltage V(n)-V(g)",vth,"V","Remove RL and solve the original network."))
			q.append(numeric("Thévenin resistance at port n,g",rth,"Ω","Deactivate Vs; inject a known test current into the load port."))
			if week==11:
				q.append(numeric("Load resistance for maximum power",rth,"Ω","For this positive linear DC port, RL = Rth."))
				q.append(numeric("Maximum load power",vth*vth/(4*rth),"W","Pmax = Vth²/(4Rth)."))
				for ratio in [0.5,1.0,2.0]:
					var sweep := parts.duplicate(true);sweep.append(part("RL","R","n","g",rth*ratio))
					var run := solve(sweep)
					variants.append({"load_ohms":rth*ratio,"voltage":run.drop.RL,"current":run.i.RL,"power":float(run.drop.RL)*float(run.i.RL)})
			parts.append(part("RL","R","n","g",rth if week==11 else r))
			target="RL"
		12:
			parts=[part("In","I","g","p",v/r),part("Rn","R","p","g",r),part("RL","R","p","g",stocked(d))]
			var conductance := 1.0/r
			var total_i := v/r
			for i in range(d):
				parts.append(part("Rn%d"%i,"R","p","g",stocked(i+1)));conductance+=1.0/stocked(i+1)
				if i>=1:parts.append(part("In%d"%i,"I","g","p",v/(r*(i+2))));total_i+=v/(r*(i+2))
			q.append(numeric("Equivalent Thévenin voltage of source network excluding RL",total_i/conductance,"V","Combine signed parallel current sources and conductances, then Vth = In,total Rn,equivalent."))
			q.append(numeric("Equivalent Thévenin series resistance",1.0/conductance,"Ω","Source transformation preserves the port resistance; use reciprocal sum for parallel resistors."))
			gates.append("adjustable_current_source")
			target="RL"
	var result := solve(parts)
	if not result.get("ok",false):return {"error":result.get("error","Reference solver failed")}
	q.append(numeric("Signed current from a to b through %s"%target,float(result.i[target]),"A","Use the named component orientation and solve the actual topology."))
	q.append(numeric("Signed voltage V(a)-V(b) across %s"%target,float(result.drop[target]),"V","Use the marked a,b orientation; Vab = Va - Vb."))
	if week>=4 and week!=12:
		q.append(numeric("Total current delivered by Vs",-float(result.i.Vs),"A","The solver defines source current entering its positive terminal; delivered current has the opposite sign."))
	if week in [4,5,6]:
		q.append(numeric("Equivalent resistance seen by Vs",v/-float(result.i.Vs),"Ω","Req = source voltage / delivered current."))
	if week>=7:
		q.append(numeric("Power dissipated in %s"%target,float(result.drop[target])*float(result.i[target]),"W","Use the combined network operating point: P = VI."))
	if d>=3:
		q.append(choice("An open lead causes a zero-current branch. First diagnostic?",["Raise voltage without limit","Power off and verify node continuity","Replace the answer key"],1,"Check actual connectivity with power isolated before changing the circuit."))
	if d==4:
		for p in parts:
			if p.kind=="R":q.append(numeric("Dissipation in %s; select a suitable configured rating"%p.id,float(result.drop[p.id])*float(result.i[p.id]),"W","Calculate every branch independently, then check each part's rating."))
	# Structured table layouts reuse the same questions and signed shared-solver values.
	var table: Array=[]
	for p in parts:
		if p.kind=="R":table.append({"component":p.id,"voltage_question":"V(a)-V(b)","current_question":"I(a to b)","resistance_ohms":p.value,"power_question":"V × I"})
	var lines: Array[String]=["Original explicit netlist. a,b are oriented terminals, not source PDF drawing coordinates. Values use V, A and Ω. Calculation predictions use the stated nominal model; physical readings use actual owned parts and instrument loading. Numeric answers may include compatible units; do not round intermediate values."]
	for p in parts:lines.append("%s (%s): a=%s, b=%s, value=%.9f"%[p.id,p.kind,p.a,p.b,p.value])
	return {"questions":q,"data":"\n".join(lines),"scenario":{"generator":"dc.v3","seed":seed_value,"week":week,"difficulty":d,"voltage":v,"nominal_resistance":r,"tolerance":tolerance,"rating_watts":rating,"four_band":four,"five_band":five,"elapsed_seconds":elapsed},"reference_parts":parts,"reference_result":result,"practical":{"target":target,"capabilities":gates,"required_observations":["voltage","current"],"rubric":{"connectivity":40,"measurements":30,"procedure":30},"variants":variants},"layouts":[{"type":"VIPR" if week>=7 else "VIR","rows":table},{"type":"power_sweep","loads_ohms":variants.map(func(row):return row.load_ohms)}] if week==11 else [{"type":"VIPR" if week>=7 else "VIR","rows":table}],"diagram":{"kind":"netlist","parts":parts.duplicate(true),"width":900,"min_font_size":18},"difficulty":d}
static func bands(nominal: float,digits: int,tolerance: float) -> Array:
	var colours: Array=["black","brown","red","orange","yellow","green","blue","violet","grey","white"]
	# Decimal scaling avoids log10 rounding at exact powers of ten (1000 must
	# encode brown-black-red, never black-black-brown).
	var exponent := 0
	var scaled := nominal
	while scaled>=pow(10,digits):scaled/=10.0;exponent+=1
	while scaled<pow(10,digits-1):scaled*=10.0;exponent-=1
	var significant := int(round(scaled))
	var output: Array=[]
	for i in range(digits):output.append(colours[int(significant/pow(10,digits-i-1))%10])
	output.append("gold" if exponent==-1 else "silver" if exponent==-2 else colours[exponent])
	output.append("brown" if tolerance==0.01 else "gold")
	return output
static func colour_case(rng: RandomNumberGenerator) -> Dictionary:
	var nominal: float=[100,220,470,1000,2200,4700,10000,47000,100000][rng.randi_range(0,8)]
	var tolerance: float=[0.01,0.05][rng.randi_range(0,1)]
	return {"nominal":nominal,"tolerance":tolerance,"bands":bands(nominal,3,tolerance)}

