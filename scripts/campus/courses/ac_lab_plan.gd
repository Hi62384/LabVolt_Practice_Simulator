extends RefCounted
## Physical experiments use the existing bank catalog and AC MNA. This plan is
## consumed unchanged by the integrated authoritative campus equipment adapter.
const Network=preload("res://scripts/ac_network.gd")
const Catalog=preload("res://scripts/equipment_catalog.gd")
const Questions=preload("res://scripts/campus/courses/dc_assignments.gd")
static func build(week: int,difficulty: int,seed_value: int,existing: Dictionary={}) -> Dictionary:
	var rng := RandomNumberGenerator.new();rng.seed=seed_value+17011
	var d := clampi(difficulty,0,4)
	var voltage := float(rng.randi_range(240,300))/10.0
	var frequency := float(rng.randi_range(45,65))
	var banks: Array=[]
	var sources := {"A":"PV_A","0":"PV_N"}
	if week==5 and existing.has("phase_arms"):
		voltage=float(existing.variable_level)*120.0;frequency=float(existing.frequency_hz)
		sources.merge({"B":"PV_B","C":"PV_C"})
		for i in range(existing.phase_arms.size()):
			var arm: Dictionary=existing.phase_arms[i]
			for spec in [["R","resistance_ohms"],["L","inductance_henry"],["C","capacitance_farad"]]:
				if float(arm.get(spec[1],0))>0:banks.append({"kind":spec[0],"index":i,"value":arm[spec[1]],"a":arm.a,"b":arm.b})
	else:
		var r: float=Catalog.LOADS.R.values[rng.randi_range(0,2)]
		var l: float=Catalog.LOADS.L.values[rng.randi_range(0,2)]
		var c: float=Catalog.LOADS.C.values[rng.randi_range(0,2)]
		banks.append({"kind":"R","index":0,"value":r,"a":"A","b":"0"})
		if week in [2,6]:
			banks[0].b="j";banks.append({"kind":"L","index":0,"value":l,"a":"j","b":"0"})
			if d>=1:
				banks[-1].b="k";banks.append({"kind":"C","index":0,"value":c,"a":"k","b":"0"})
			if d>=3:
				banks[-1].b="m";banks.append({"kind":"R","index":1,"value":r,"a":"m","b":"0"})
		elif week==3:
			banks.append({"kind":"L","index":0,"value":l,"a":"A","b":"0"})
			if d>=1:banks.append({"kind":"C","index":0,"value":c,"a":"A","b":"0"})
			if d>=3:banks.append({"kind":"R","index":1,"value":float(Catalog.LOADS.R.values[rng.randi_range(0,2)]),"a":"A","b":"0"})
		elif week==7:
			sources.merge({"B":"PV_B","C":"PV_C"})
			banks.clear()
			for i in range(3):
				for spec in [["R",r],["L",l],["C",c]]:banks.append({"kind":spec[0],"index":i,"value":spec[1],"a":["A","B","C"][i],"b":"0"})
		elif week in [4,8]:
			banks[0].b="j"
			banks.append({"kind":"L","index":0,"value":l,"a":"j","b":"k"})
			banks.append({"kind":"R","index":1,"value":float(Catalog.LOADS.R.values[rng.randi_range(0,2)]),"a":"k","b":"0"})
			banks.append({"kind":"C","index":0,"value":c,"a":"k","b":"0"})
			if d>=3:banks.append({"kind":"R","index":2,"value":float(Catalog.LOADS.R.values[rng.randi_range(0,2)]),"a":"k","b":"0"})
		elif d>=2:banks.append({"kind":"R","index":1,"value":float(Catalog.LOADS.R.values[rng.randi_range(0,2)]),"a":"A","b":"0"})
	var nodes: Array=["0"];var branches: Array=[];var drawing: Array=[]
	for node in sources:
		if node=="0":continue
		nodes.append(node)
		var angle := 0.0 if node=="A" else -TAU/3 if node=="B" else TAU/3
		branches.append({"id":"source_"+node,"type":"voltage","a":node,"b":"0","value":Vector2(cos(angle),sin(angle))*voltage})
		drawing.append({"id":"V"+node,"kind":"V","a":node,"b":"0","value":"%.1f∠%.0f°"%[voltage,rad_to_deg(angle)],"unit":"V RMS"})
	for bank in banks:
		for node in [bank.a,bank.b]:
			if not nodes.has(node):nodes.append(node)
		var id: String=str(bank.kind)+str(bank.index)
		var z := Vector2(float(bank.value),0) if bank.kind=="R" else Vector2(0,TAU*frequency*float(bank.value)) if bank.kind=="L" else Vector2(0,-1/(TAU*frequency*float(bank.value)))
		branches.append({"id":id,"type":"impedance","a":bank.a,"b":bank.b,"value":z})
		drawing.append({"id":id,"kind":bank.kind,"a":bank.a,"b":bank.b,"value":bank.value,"unit":"Ω" if bank.kind=="R" else "H" if bank.kind=="L" else "F"})
	var result := Network.new().solve(nodes,branches)
	if result.fault!="":return {"error":result.fault}
	for bank in banks:
		if (result.voltages[bank.a]-result.voltages[bank.b]).length()>134.0:return {"error":"Generated bank overvoltage"}
	var first: Dictionary=banks[0]
	var volts: Vector2=result.voltages[first.a]-result.voltages[first.b]
	var q := [Questions.numeric("Physical experiment: RMS voltage across R0",volts.length(),"V","Solve the physical network listed below; compare with the actual parallel voltmeter."),Questions.numeric("Physical experiment: RMS current through R0",result.currents.R0.length(),"A","Use the actual R0 voltage and resistance; place the ammeter in series.")]
	q[0].template_id="ac.physical.voltage";q[1].template_id="ac.physical.current"
	for question in q:question.inputs={"generator":"ac_physical.v3","banks":banks,"source_nodes":sources,"voltage_rms":voltage,"frequency_hz":frequency}
	var text: Array[String]=["PHYSICAL EXPERIMENT — this diagram and bank table apply to the physical questions; calculation cases above are separately labelled.","Power OFF before wiring. Turn unused bank switches OFF. Set the variable supply to %.9f%% and frequency %.1f Hz. Use variable outputs4/5/6 (A/B/C), and variable N for node0."%[voltage/120.0*100,frequency]]
	for bank in banks:text.append("%s%d: %.9f %s; top socket=node %s, bottom socket=node %s. Enable only the matching catalog switch."%[bank.kind,bank.index,bank.value,"Ω" if bank.kind=="R" else "H" if bank.kind=="L" else "F",bank.a,bank.b])
	text.append("Join all sockets with the same node name. Internal nodes j,k,m are junctions, not source sockets. Connect voltmeter COM to R0_N and150V input to R0_P. Insert ammeter in R0's incoming lead; never place it across the supply. Power ON, Record equipment on the sheet, then power OFF. Preserve actual readings and loading.")
	return {"plan":{"banks":banks,"source_nodes":sources,"variable_level":voltage/120.0,"frequency_hz":frequency},"reference":{"nodes":nodes,"branches":branches,"result":result},"questions":q,"instructions":"\n".join(text),"diagram":{"kind":"netlist","parts":drawing,"width":900,"min_font_size":18,"caption":"Physical experiment; separate calculation cases labelled in given data"}}
