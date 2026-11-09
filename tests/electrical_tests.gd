extends SceneTree
const Network = preload("res://scripts/ac_network.gd")
const Solver = preload("res://scripts/circuit_solver.gd")
const State = preload("res://scripts/lab_state.gd")
const Motor = preload("res://scripts/induction_motor.gd")
var failures := 0
var assertions := 0
var engine = Network.new()

func check(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures += 1
		printerr("FAIL: "+message)

func near(actual: float,expected: float,message: String,tolerance := 0.002) -> void:
	check(absf(actual-expected)<=maxf(tolerance,absf(expected)*0.0002),"%s: %.8f expected %.8f"%[message,actual,expected])

func impedance(id: String,a: String,b: String,z: Vector2) -> Dictionary:
	return {"id":id,"a":a,"b":b,"type":"impedance","value":z}

func source(id: String,a: String,b: String,v: Vector2) -> Dictionary:
	return {"id":id,"a":a,"b":b,"type":"voltage","value":v}

func supplies() -> Array:
	return [source("VA","A","0",Vector2(120,0)),source("VB","B","0",Vector2(-60,-103.923048454)),source("VC","C","0",Vector2(-60,103.923048454))]

func power(v: Vector2,i: Vector2) -> Vector2:
	return Vector2(v.dot(i),v.y*i.x-v.x*i.y)

func total(result: Dictionary,branches: Array) -> Vector2:
	var value := Vector2.ZERO
	for b in branches:
		if b.type=="impedance":
			value += power(result.voltages[b.a]-result.voltages[b.b],result.currents[b.id])
	return value

func _initialize() -> void:
	# Independent balanced references: P_wye=3 Vph²/R; P_delta=3 Vll²/R.
	var b := supplies()
	for phase in ["A","B","C"]:
		b.append(impedance(phase,phase,"0",Vector2(1200,0)))
	var r: Dictionary = engine.solve(["0","A","B","C"],b)
	check(r.fault=="","balanced Wye solves")
	near(total(r,b).x,36,"Wye P")
	for phase in ["A","B","C"]:
		near(r.currents[phase].length(),.1,"Wye phase current")
	b = supplies()
	for pair in [["A","B"],["B","C"],["C","A"]]:
		b.append(impedance(pair[0],pair[0],pair[1],Vector2(1200,0)))
	r = engine.solve(["0","A","B","C"],b)
	near(total(r,b).x,108,"Delta P")
	near(r.currents.VA.length(),.3,"Delta line current")
	near(r.currents.A.length(),sqrt(3)*.1,"Delta branch current")
	# Unequal branches with and without a solid neutral.
	b = supplies()
	for i in range(3):
		b.append(impedance(["A","B","C"][i],["A","B","C"][i],"0",Vector2([1200,600,300][i],0)))
	r = engine.solve(["0","A","B","C"],b)
	near(total(r,b).x,84,"unbalanced solid neutral P")
	near(r.currents.A.length(),.1,"unbalanced A")
	near(r.currents.B.length(),.2,"unbalanced B")
	near(r.currents.C.length(),.4,"unbalanced C")
	for branch in b:
		if branch.type=="impedance":
			branch.b = "N"
	r = engine.solve(["0","A","B","C","N"],b)
	near(r.voltages.N.x,-34.2857142857,"open neutral real")
	near(r.voltages.N.y,29.6922995583,"open neutral imaginary")
	check((r.currents.A+r.currents.B+r.currents.C).length()<1e-6,"open neutral KCL")
	near(total(r,b).x,72,"open-neutral unbalanced total P")
	var w1 := power(r.voltages.A-r.voltages.B,r.currents.A).x
	var w2 := power(r.voltages.C-r.voltages.B,r.currents.C).x
	near(w1+w2,72,"two wattmeters unbalanced three-wire total")
	# Pure L, pure C, then series RLC, f=60 Hz.
	var omega := TAU*60
	b = [source("V","A","0",Vector2(120,0)),impedance("L","A","0",Vector2(0,omega*3.2))]
	r = engine.solve(["0","A"],b)
	near(total(r,b).y,14400/(omega*3.2),"inductive Q positive")
	near(r.currents.L.angle(),-PI/2,"inductive phase")
	b[1] = impedance("C","A","0",Vector2(0,-1/(omega*2.2e-6)))
	r = engine.solve(["0","A"],b)
	near(total(r,b).y,-14400*omega*2.2e-6,"capacitive Q negative")
	b = [source("V","A","0",Vector2(120,0)),impedance("R","A","B",Vector2(300,0)),impedance("L","B","C",Vector2(0,omega*.8)),impedance("C","C","0",Vector2(0,-1/(omega*8.8e-6)))]
	r = engine.solve(["0","A","B","C"],b)
	var reactance := omega*.8-1/(omega*8.8e-6)
	var current := 120/sqrt(300*300+reactance*reactance)
	near(r.currents.R.length(),current,"series RLC I")
	near(total(r,b).x,current*current*300,"series RLC P")
	near(total(r,b).y,current*current*reactance,"series RLC Q")
	check((r.currents.R-r.currents.L).length()<1e-6,"series RLC KCL")
	b = [source("V","A","0",Vector2(120,0)),impedance("R","A","0",Vector2(1200,0)),impedance("L","A","0",Vector2(0,omega*3.2)),impedance("C","A","0",Vector2(0,-1/(omega*2.2e-6)))]
	r = engine.solve(["0","A"],b)
	var pq := total(r,b)
	near(pq.x,12,"PF correction P")
	near(pq.y,14400/(omega*3.2)-14400*omega*2.2e-6,"PF correction Q")
	check(pq.x/pq.length()>.999,"corrected PF")
	# General MNA supports a floating voltage source, unlike fixed-node stamping.
	r = engine.solve(["0","A","B"],[source("V","A","B",Vector2(10,0)),impedance("R1","A","0",Vector2(100,0)),impedance("R2","B","0",Vector2(100,0))])
	near(r.voltages.A.x,5,"floating source A")
	near(r.voltages.B.x,-5,"floating source B")
	r = engine.solve(["0","A","B"],[impedance("R","A","B",Vector2(100,0))])
	check(r.fault=="" and r.floating_references.size()==1,"isolated open circuit explicitly reported")
	near(r.currents.R.length(),0,"isolated open circuit I")
	r = engine.solve(["0","A"],[source("V1","A","0",Vector2(120,0)),source("V2","A","0",Vector2.ZERO)])
	check(r.fault!="","conflicting voltage sources / short rejected")
	test_equipment()
	test_motor()
	test_exam()
	print("ELECTRICAL / DOMAIN: %d assertions, %d failures"%[assertions,failures])
	quit(1 if failures else 0)

func fixture() -> Array:
	var ids: Array = []
	for prefix in ["P_","PV_"]:
		for phase in ["A","B","C","N"]:
			ids.append(prefix+phase)
	for kind in ["R","L","C"]:
		for i in range(3):
			ids.append("%s%d_P"%[kind,i])
			ids.append("%s%d_N"%[kind,i])
	for i in range(3):
		for suffix in ["IN","OUT"]:
			ids.append("AM%d_%s"%[i,suffix])
		for suffix in ["COM","150","300"]:
			ids.append("V%d_%s"%[i,suffix])
	for i in range(2):
		for suffix in ["IN","OUT","VP","VN"]:
			ids.append("W%d_%s"%[i,suffix])
	for i in range(1,7):
		ids.append("M%d"%i)
	return ids

func test_equipment() -> void:
	var ids := fixture()
	var solver := Solver.new()
	var sw := {"R":[true,false,false,true,false,false,true,false,false],"L":[],"C":[]}
	sw.L.resize(9)
	sw.L.fill(false)
	sw.C.resize(9)
	sw.C.fill(false)
	var wires: Array = []
	wires.append({"a":"P_A","b":"W0_IN"})
	wires.append({"a":"W0_OUT","b":"R0_P"})
	wires.append({"a":"P_C","b":"W1_IN"})
	wires.append({"a":"W1_OUT","b":"R2_P"})
	wires.append({"a":"P_B","b":"R1_P"})
	# Three-wire Wye: neutral star point floats, as required by two-wattmeter method.
	wires.append({"a":"R0_N","b":"R1_N"})
	wires.append({"a":"R1_N","b":"R2_N"})
	for pair in [["P_A","W0_VP"],["P_B","W0_VN"],["P_C","W1_VP"],["P_B","W1_VN"]]:
		wires.append({"a":pair[0],"b":pair[1]})
	var r: Dictionary = solver.solve(ids,wires,sw,true,.58)
	check(r.fault=="","two wattmeter fixture solves")
	near(r.wattmeters[0],18,"two-wattmeter W1",.01)
	near(r.wattmeters[1],18,"two-wattmeter W2",.01)
	near(r.wattmeters[0]+r.wattmeters[1],r.p,"two-wattmeter sum",.01)
	wires = [{"a":"P_A","b":"AM0_IN"},{"a":"AM0_OUT","b":"R0_P"},{"a":"R0_N","b":"P_N"},{"a":"V0_150","b":"R0_P"},{"a":"V0_COM","b":"P_N"}]
	sw.R = [true,false,false,false,false,false,false,false,false]
	r = solver.solve(ids,wires,sw,true,.58)
	# Voltmeter 150 kohm parallel to 1200 ohm, behind .02 ohm ammeter.
	var y := 1/1200.0+1/100000.0
	var expected_voltage := 120/(1+.02*y)
	near(r.voltmeters[0],expected_voltage,"finite voltmeter loading",.0001)
	near(r.ammeters[0],expected_voltage*y,"series ammeter",.0001)
	sw.L[0] = true
	wires.append({"a":"P_A","b":"L0_P"})
	wires.append({"a":"L0_N","b":"P_N"})
	solver.frequency = 50
	r = solver.solve(ids,wires,sw,true,.58)
	near(r.q,14400/(TAU*50*3.2),"frequency changes reactance")
	wires = [{"a":"P_A","b":"P_N"}]
	r = solver.solve(ids,wires,sw,true,.58)
	check(r.fault.contains("SHORT"),"source short protection")
	wires = [{"a":"P_A","b":"AM0_IN"},{"a":"AM0_OUT","b":"P_N"}]
	r = solver.solve(ids,wires,sw,true,.58)
	check(r.fault!="","ammeter across source trips")
	# Cable ownership, reach, race conflict, disconnect, revision and safety tests.
	var state := State.new()
	var pos := Vector3(-4.2,1.5,-1.4)
	var locations := {}
	for id in ids:
		locations[id] = pos
	locations["R_0"] = pos
	locations["power"] = pos
	locations["variable"] = pos
	state.initialize(ids,locations)
	check(state.cables.is_empty() and not state.powered,"unwired startup")
	check(state.act(2,{"op":"pickup"},pos)=="","rack pickup")
	check(state.act(2,{"op":"plug","port":"P_A"},pos)=="","first connector")
	check(state.completed().is_empty(),"one-ended cable is electrically open")
	check(state.act(3,{"op":"unplug","port":"P_A"},pos)!="","carried cable lock")
	check(state.act(2,{"op":"plug","port":"R0_P"},pos)=="","second connector")
	check(state.completed().size()==1,"complete cable conducts")
	check(state.act(3,{"op":"unplug","port":"P_A"},pos)=="","other player can carry free end")
	state.release(3)
	check(state.cables[0].owner==0 and state.cables[0].b=="R0_P","disconnect preserves installed end")
	check(state.act(2,{"op":"grab","id":state.cables[0].id},pos)=="","loose end can be reclaimed without removing installed end")
	check(state.act(3,{"op":"grab","id":state.cables[0].id},pos)!="","loose-end ownership race rejected")
	state.release(2)
	check(state.act(2,{"op":"switch","kind":"R","index":0,"expected":false},pos)=="","switch changes")
	check(state.act(3,{"op":"switch","kind":"R","index":0,"expected":false},pos)!="","stale switch race rejected")
	check(state.act(2,{"op":"reset"},pos)!="","client cannot reset")
	check(state.act(1,{"op":"reset"},pos,true)=="","host reset")
	check(state.cables.is_empty() and not state.switches.R.has(true),"reset clears circuit")
	state.act(1,{"op":"configure","mode":"Practical Exam","task":1,"seed":101},pos,true)
	check(state.act(1,{"op":"power"},pos,true)!="","exam requires preflight")
	check(state.act(1,{"op":"check"},pos,true)=="","preflight")
	check(state.act(1,{"op":"power"},pos,true)=="","exam energization")
	check(state.act(1,{"op":"switch","kind":"R","index":0},pos,true)!="" and state.safety_errors==1,"exam live circuit edit safety strike")
	check(state.grade({}).begins_with("0/100"),"empty exam cannot pass")

func test_motor() -> void:
	# Independently derived Thevenin form of the induction equivalent circuit.
	var xm := Vector2(0,180)
	var stator := Vector2(12,15)
	var divider := engine.divide(xm,stator+xm)
	var vth := 120*divider.length()
	var zth := engine.divide(Vector2(-2700,2160),stator+xm)
	var rotor_r := 9/.05
	var expected_torque := 3*vth*vth*rotor_r/(TAU*1800/60*(pow(zth.x+rotor_r,2)+pow(zth.y+15,2)))
	near(Motor.torque(120,60,.05),expected_torque,"motor Thevenin torque",.00001)
	var point: Dictionary = Motor.operating_point(120,60,.5)
	near(point.torque,.62,"motor mechanical equilibrium",.00001)
	near(point.synchronous_rpm,1800,"4 pole synchronous speed")
	check(point.slip>0 and point.rpm<1800 and point.rpm>0,"positive motor slip")
	var solver := Solver.new()
	var sw := {"R":[],"L":[],"C":[]}
	for k in sw:
		sw[k].resize(9)
		sw[k].fill(false)
	var wires: Array = []
	for i in range(3):
		wires.append({"a":"P_"+["A","B","C"][i],"b":"M%d"%(i+1)})
		wires.append({"a":"P_N","b":"M%d"%(i+4)})
	var unloaded: Dictionary = solver.solve(fixture(),wires,sw,true,.58,0)
	var loaded: Dictionary = solver.solve(fixture(),wires,sw,true,.58,.5)
	check(loaded.fault=="" and loaded.motor_rpm>0,"motor runs from actual connected phases")
	check(loaded.motor_rpm<unloaded.motor_rpm and loaded.p>unloaded.p,"dynamometer changes speed and power")
	check(loaded.motor.efficiency>0 and loaded.motor.efficiency<1,"motor energy balance")
	wires[0].a="P_B"
	wires[2].a="P_A"
	var reverse: Dictionary = solver.solve(fixture(),wires,sw,true,.58,.5)
	check(reverse.motor_rpm<0,"phase reversal reverses motor")
	wires[0].a="P_A"
	wires[2].a="P_A"
	wires[4].a="P_A"
	var invalid: Dictionary = solver.solve(fixture(),wires,sw,true,.58,.5)
	check(invalid.motor_rpm==0,"single phase cannot create rotating three phase field")

func test_exam() -> void:
	var state := State.new()
	var ids := fixture()
	var positions := {}
	var pos := Vector3(-4.2,1.5,-1.4)
	for id in ids:
		positions[id]=pos
	positions.power=pos
	state.initialize(ids,positions)
	state.act(1,{"op":"configure","mode":"Practical Exam","task":0,"seed":101},pos,true)
	for i in range(3):
		state.switches.R[i*3+state.element]=true
	var pairs := [["P_A","AM0_IN"],["AM0_OUT","W0_IN"],["W0_OUT","R0_P"],["P_B","R1_P"],["P_C","W1_IN"],["W1_OUT","R2_P"],["R0_N","P_N"],["R1_N","P_N"],["R2_N","P_N"],["W0_VN","P_B"],["W1_VN","P_B"],["V0_150","R0_P"],["V0_COM","P_N"]]
	for pair in pairs:
		state.cables.append({"id":state.next_id,"a":pair[0],"b":pair[1],"color":0,"owner":0,"creator":1})
		state.next_id+=1
	state.recalculate()
	check(state.act(1,{"op":"check"},pos,true)=="","exam valid preflight")
	check(state.act(1,{"op":"power"},pos,true)=="","exam valid energized circuit")
	check(state.act(1,{"op":"record"},pos,true)=="","exam records actual instruments")
	var answer := {"v":state.records.v,"i":state.records.i,"p":state.records.p}
	check(state.grade(answer).begins_with("100/100"),"correct circuit and recorded answer earns full grade")
	answer.p=999
	check(state.grade(answer).begins_with("70/100"),"incorrect measurement loses measurement credit")
	state.switches.R[0]=not state.switches.R[0]
	state.recalculate()
	check(not state.grade(answer).begins_with("100/100"),"modified loads invalidate grade")
