extends RefCounted
## Read-only adapter to the existing electrical MNA solver. No solver duplication.
const C=preload("res://scripts/mth255/complex_domain.gd")
static func verify(problem: Dictionary) -> bool:
	if problem.generator_id not in ["impedance","impedance_network"]:return true
	if not ResourceLoader.exists("res://scripts/ac_network.gd"):return false
	var q=problem.parameters;var answer=problem.answer;var nodes=["0","source","mid"];var branches=[];var v=Vector2(q.v if problem.generator_id=="impedance" else q.voltage,0)
	branches.append({"id":"V","a":"source","b":"0","type":"voltage","value":v})
	if problem.generator_id=="impedance_network":
		branches.append({"id":"Z1","a":"source","b":"mid","type":"impedance","value":C.decode(q.z1)})
		branches.append({"id":"Z2","a":"mid","b":"0","type":"impedance","value":C.decode(q.z2)})
		branches.append({"id":"Z3","a":"mid","b":"0","type":"impedance","value":C.decode(q.z3)})
	elif q.parallel:
		nodes=["0","source"]
		branches.append({"id":"Z1","a":"source","b":"0","type":"impedance","value":C.decode(q.z)})
		branches.append({"id":"Z2","a":"source","b":"0","type":"impedance","value":C.decode(q.w)})
	else:
		branches.append({"id":"Z1","a":"source","b":"mid","type":"impedance","value":C.decode(q.z)})
		branches.append({"id":"Z2","a":"mid","b":"0","type":"impedance","value":C.decode(q.w)})
	var result=load("res://scripts/ac_network.gd").new().solve(nodes,branches)
	if not result.get("fault","missing").is_empty():return false
	var total=-result.currents.V
	if not C.near(C.divide(v,total),Vector2(answer.z_real,answer.z_imag)):return false
	if problem.generator_id=="impedance":return C.near(total,Vector2(answer.i_real,answer.i_imag))
	return C.near(result.voltages.mid,Vector2(answer.v_real,answer.v_imag)) and C.near(result.currents.Z2,Vector2(answer.i2_real,answer.i2_imag)) and C.near(result.currents.Z3,Vector2(answer.i3_real,answer.i3_imag))
