extends RefCounted
## Original, bank-realizable three-phase extensions. Uses the established AC MNA
## solver, not an independent course solver. The supplied Lab5 wye objectives and
## lecture delta relationships determine the tasks; source drawings are not copied.
const Network = preload("res://scripts/ac_network.gd")
const DC = preload("res://scripts/campus/courses/dc_assignments.gd")
static func three_phase(difficulty: int,seed_value: int) -> Dictionary:
	var rng := RandomNumberGenerator.new();rng.seed=seed_value
	var d := clampi(difficulty,0,4)
	var delta := d in [1,4]
	# Delta uses reduced source voltage so each load stays below the game's135V
	# per-bank protection threshold. Do not put a114V phase supply across delta loads.
	var voltage := float(rng.randi_range(480,600))/10.0 if delta else float(rng.randi_range(900,1140))/10.0
	var frequency := float(rng.randi_range(45,65))
	var rotation := rng.randi_range(0,2)
	var balanced_r := float([300,600,1200][rng.randi_range(0,2)])
	var balanced_l := float([0.8,1.6,3.2][rng.randi_range(0,2)])
	var nodes: Array=["A","B","C","0"]
	var branches: Array=[]
	var diagram_parts: Array=[]
	var phases: Array=[]
	for i in range(3):
		var value := Vector2(cos(-i*TAU/3),sin(-i*TAU/3))*voltage
		branches.append({"id":"Vs%d"%i,"type":"voltage","a":nodes[i],"b":"0","value":value})
		diagram_parts.append({"id":"V%s"%nodes[i],"kind":"V","a":nodes[i],"b":"0","value":"%.1f∠%d°"%[voltage,-i*120 if i<2 else 120],"unit":"V RMS"})
		var r := float([300,600,1200][(i+rotation)%3]) if d>=3 else balanced_r
		var a: String=nodes[i];var b: String=nodes[(i+1)%3] if delta else "0"
		branches.append({"id":"R%d"%i,"type":"impedance","a":a,"b":b,"value":Vector2(r,0)})
		diagram_parts.append({"id":"R%d"%i,"kind":"R","a":a,"b":b,"value":r,"unit":"Ω"})
		var record := {"a":a,"b":b,"resistance_ohms":r,"inductance_henry":0.0,"capacitance_farad":0.0}
		if d in [2,4]:
			var inductance := float([0.8,1.6,3.2][(i+rotation)%3]) if d==4 else balanced_l
			branches.append({"id":"L%d"%i,"type":"impedance","a":a,"b":b,"value":Vector2(0,TAU*frequency*inductance)})
			record.inductance_henry=inductance
			diagram_parts.append({"id":"L%d"%i,"kind":"L","a":a,"b":b,"value":inductance,"unit":"H"})
		if d==4:
			var capacitance: float=[2.2e-6,4.4e-6,8.8e-6][(i+rotation)%3]
			branches.append({"id":"C%d"%i,"type":"impedance","a":a,"b":b,"value":Vector2(0,-1.0/(TAU*frequency*capacitance))})
			record.capacitance_farad=capacitance
			diagram_parts.append({"id":"C%d"%i,"kind":"C","a":a,"b":b,"value":capacitance,"unit":"F"})
		phases.append(record)
	var result := Network.new().solve(nodes,branches)
	if result.fault!="":return {"error":result.fault}
	var line: Array=[Vector2.ZERO,Vector2.ZERO,Vector2.ZERO]
	var p := 0.0;var q := 0.0
	for branch in branches:
		if branch.type!="impedance":continue
		var i: Vector2=result.currents[branch.id]
		var v: Vector2=result.voltages[branch.a]-result.voltages[branch.b]
		p+=v.dot(i);q+=v.y*i.x-v.x*i.y
		var ai := nodes.find(branch.a);var bi := nodes.find(branch.b)
		if ai<3:line[ai]+=i
		if bi<3:line[bi]-=i
	var neutral: Vector2=line[0]+line[1]+line[2]
	var neutral_magnitude := 0.0 if neutral.length()<1e-6 else neutral.length()
	if absf(q)<1e-5:q=0.0
	var questions: Array=[DC.numeric("Line-to-line RMS source voltage",voltage*sqrt(3),"V","The source is balanced: VL = sqrt(3) Vphase."),DC.numeric("Line A RMS current",line[0].length(),"A","Sum signed phasor branch currents at node A; delta line current is not one branch current."),DC.numeric("Total three-phase real power",p,"W","Sum real power over actual R/L/C branches, using RMS phasors."),DC.numeric("Total three-phase reactive power",q,"var","Sum signed branch reactive powers; capacitors contribute negative var.")]
	if d>=2:questions.append(DC.numeric("Line B RMS current",line[1].length(),"A","Do not apply balanced-load shortcuts to unequal loads."))
	if not delta:questions.append(DC.numeric("Neutral current RMS magnitude",neutral_magnitude,"A","Use the vector sum of the three line currents, not the sum of magnitudes."))
	if d>=3:
		questions.append(DC.choice("May sqrt(3) VL IL PF be used with an arbitrary single line current for this unbalanced load?",["Yes","No; sum individual phase powers"],1,"The familiar balanced formula requires balanced conditions."))
	for question in questions:
		question.template_id="threephase."+str(question.prompt)
		question.inputs={"generator":"three_phase.v3","voltage_rms":voltage,"frequency_hz":frequency,"delta":delta,"arms":phases}
	var lines: Array[String]=["Original %s load. Source phase RMS %.2fV,%.1fHz, phase sequence A,B,C. Source phasors 0,-120,+120 degrees. Use variable outputs, not fixed120V. Neutral is connected for wye."%["delta" if delta else "wye",voltage,frequency]]
	for i in range(3):lines.append("Arm%d: %s to %s; R=%.1fΩ; L=%.4fH; C=%.9fF. Zero L/C means omit that branch. Components in each arm are parallel."%[i+1,phases[i].a,phases[i].b,phases[i].resistance_ohms,phases[i].inductance_henry,phases[i].capacitance_farad])
	return {"questions":questions,"data":"\n".join(lines),"scenario":{"generator":"three_phase.v3","seed":seed_value,"difficulty":d,"voltage_rms":voltage,"frequency_hz":frequency,"delta":delta,"arms":phases},"reference_ac":{"nodes":nodes,"branches":branches,"result":result},"physical_ac_plan":{"connection":"delta" if delta else "wye","variable_level":voltage/120.0,"frequency_hz":frequency,"phase_arms":phases,"use_bank_per_phase":true},"practical":{"capabilities":["ac_bench"],"requires_host_adapter":true,"rubric":{"connectivity":40,"measurements":30,"procedure":30}},"diagram":{"kind":"netlist","parts":diagram_parts,"width":900,"min_font_size":18}}
