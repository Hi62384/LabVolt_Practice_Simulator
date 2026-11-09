extends SceneTree
const Provider = preload("res://scripts/campus/courses/course_provider.gd")
const Plan = preload("res://scripts/campus/courses/equipment_plan.gd")
const Board = preload("res://scripts/breadboard_model.gd")
const Station = preload("res://scripts/dc_station.gd")
const ACSolver = preload("res://scripts/ac_network.gd")
var failures := 0
var checks := 0
func check(ok: bool,why: String) -> void:
	checks+=1
	if not ok:failures+=1;push_error(why)
func _initialize() -> void:
	# Build every implemented DC week using actual catalog models and the actual
	# station's supply, breadboard expansion and instrument loading. No measurements
	# are copied into the station from the generated reference result.
	for week in range(1,13):
		for difficulty in range(5):
			for seed_value in [1,155,902]:
				var assignment := Provider.generate("ETY155",week,"lab",difficulty,seed_value)
				var plan := Plan.for_assignment(assignment)
				check(plan.ok,"Buildable catalog plan week "+str(week))
				var station := Station.new();station.master=true
				var board := Board.empty();board.ports=["P1","N1","P16","N16"]
				var hole_for_node := {};var row := 1;var channel := 0
				var target_holes := {};var expanded_target := ""
				for item in plan.devices:
					if item.get("equipment","") in ["isolated_adjustable_dc_channel","adjustable_current_source"]:continue
					var holes: Array=[];var names: Array=[]
					if item.catalog_id=="pot10k":
						holes=["A%d"%row,"F%d"%row,"A%d"%(row+1)]
						names=[item.end_a,item.wiper,item.end_b]
						var p := {"id":"pot%d"%row,"type":"pot10k","pins":holes,"setting":item.setting}
						board.parts.append(p)
						if item.get("reference_id","")==assignment.practical.target:expanded_target="board/"+p.id+"/upper";target_holes={"a":holes[0],"b":holes[1]}
						if item.has("reference_ids") and assignment.practical.target=="R1":expanded_target="board/"+p.id+"/upper";target_holes={"a":holes[0],"b":holes[1]}
						row+=2
					else:
						holes=["A%d"%row,"F%d"%row];names=[item.a,item.b]
						var p := {"id":item.reference_id,"type":item.catalog_id,"a":holes[0],"b":holes[1]}
						board.parts.append(p)
						if p.id==assignment.practical.target:expanded_target="board/"+str(p.id);target_holes={"a":holes[0],"b":holes[1]}
						row+=1
					for i in range(holes.size()):
						if hole_for_node.has(names[i]):board.wires.append([holes[i],hole_for_node[names[i]]])
						else:hole_for_node[names[i]]=holes[i]
				for item in plan.devices:
					if item.get("equipment","")!="isolated_adjustable_dc_channel":continue
					check(channel<3,"At most three isolated channels")
					if channel>=3:continue
					station.channels[channel]={"voltage":item.setpoint_volts,"enabled":true,"limit":0.1}
					var plus: String=item.positive_node;var minus: String=item.negative_node
					if item.reverse_leads:var temp := plus;plus=minus;minus=temp
					for pair in [[plus,"CH%d+"%(channel+1)],[minus,"CH%d-"%(channel+1)]]:
						if not hole_for_node.has(pair[0]):hole_for_node[pair[0]]="P%d"%(1+channel*5)
						station.wires.append([pair[1],"board/"+Board.node(str(hole_for_node[pair[0]]),30)])
					channel+=1
				for item in plan.devices:
					if item.get("equipment","")!="adjustable_current_source":continue
					var index: int=item.source_index
					var suffix := "" if index==0 else str(index+1)
					var source: Dictionary=station.current_source if index==0 else station.auxiliary_sources[index-1]
					source.enabled=true;source.current=item.setpoint_amperes;source.compliance=item.compliance_volts
					for pair in [[item.positive_node,"IS"+suffix+"+"],[item.negative_node,"IS"+suffix+"-"]]:
						station.wires.append([pair[1],"board/"+Board.node(str(hole_for_node[pair[0]]),30)])
				check(Board.validate(board,{},true)=="","Actual breadboard placement validates week "+str(week))
				station.board=board
				if week==2:
					var catalog: Dictionary=preload("res://scripts/electronics_catalog.gd").all()
					board.component_runtime={}
					for p in board.parts:
						var model: Dictionary=catalog[p.type]
						if not model.get("physical_resistor",false):continue
						board.component_runtime["board/"+str(p.id)]={"schema":1,"model":"resistor","nominal":model.value,"tolerance":model.resistance_tolerance,"watts":model.power_rating_w,"actual":float(model.value)*(1+float(model.resistance_tolerance)*0.9)}
				station.wires.append(["VΩ","board/"+Board.node(target_holes.a,30)])
				station.wires.append(["COM","board/"+Board.node(target_holes.b,30)])
				station.step(0.0)
				check(station.result.get("ok",false),"Actual station operating point solves")
				if not station.result.get("ok",false):continue
				var voltage := float(station.result.v["VΩ"])-float(station.result.v.COM)
				var physical_reference: Array=assignment.reference_parts.duplicate(true)
				for wanted in physical_reference:
					for actual in station.netlist():
						if actual.id=="board/"+str(wanted.id) and actual.get("physical_resistor",false):wanted.value=actual.value
				var predicted: float=preload("res://scripts/electronics_solver.gd").new().solve(physical_reference).drop[assignment.practical.target]
				check(absf(voltage-predicted)<=maxf(1e-6,absf(predicted)*.02),"Physical station meter agrees within instrument loading tolerance week "+str(week)+" d"+str(difficulty))
				check(station.result.i.has(expanded_target),"Target exists as real expanded component")
				for key in station.result.get("mode",{}):
					if str(key).begins_with("isource"):check(station.result.mode[key]=="CC","Current source stays within compliance")
				var adapter := preload("res://scripts/campus/academics/equipment_evidence.gd").new()
				var capture := adapter.snapshot(station.netlist(),station.wires+Board.expand(board).wires,assignment)
				check(capture.get("topology",false),"Host grader matches actual nominal values and topology week%d d%d"%[week,difficulty])
				check(adapter.grade(assignment,capture).get("operating_point",false),"Host grader accepts actual tolerance/current-source operating point week%d d%d"%[week,difficulty])
				check(Provider.validate_practical(assignment,{"parts":station.netlist(),"wires":station.wires+Board.expand(board).wires}).get("operating_point",false),"Optional provider validator delegates to the same actual host grader")
				if week==12 and difficulty==4:
					station.current_source.compliance=0.1;station.step(0.0)
					check(not Provider.validate_practical(assignment,{"parts":station.netlist(),"wires":station.wires+Board.expand(board).wires}).ok,"Compliance-limited sources cannot receive valid reference marks")
	# AC regression through the SAME AC network solver, not a course-only phasor engine.
	for seed_value in [1,23,42,89]:
		var assignment := preload("res://scripts/course_generator.gd").generate(2,2,seed_value)
		# Explicit givens, not an RNG-sequence replay of the implementation.
		var s: Dictionary=assignment.scenario
		var v: float=s.voltage_rms
		var xl: float=TAU*float(s.frequency_hz)*float(s.inductance_henry)
		var z := Vector2(float(s.resistance_ohms)+float(s.extra_resistance_ohms),xl-float(s.xc_ohms))
		var result := ACSolver.new().solve(["p","n","0"],[{"id":"Vs","type":"voltage","a":"p","b":"0","value":Vector2(v,0)},{"id":"load","type":"impedance","a":"p","b":"0","value":z}])
		check(result.fault=="","AC network solver valid")
		check(absf(float(result.currents.load.length())-float(assignment.questions[1].answer))<1e-6,"AC generated current independently shared-solver validated")
	# Real AC load-bank wiring for new wye/delta and balanced/unbalanced tasks.
	for difficulty in range(5):
		var assignment := Provider.generate("ELM253",5,"lab",difficulty,42)
		var plan: Dictionary=preload("res://scripts/campus/courses/ac_assignments.gd").three_phase(difficulty,42).physical_ac_plan
		var terminals: Array=["PV_A","PV_B","PV_C","PV_N","P_N"]
		var leads: Array=[];var switches := {"R":[],"L":[],"C":[]}
		for kind in ["R","L","C"]:
			switches[kind].resize(9);switches[kind].fill(false)
			for i in range(3):
				terminals.append("%s%d_P"%[kind,i]);terminals.append("%s%d_N"%[kind,i])
		for i in range(3):
			var arm: Dictionary=plan.phase_arms[i]
			for entry in [["R","resistance_ohms",[1200.0,600.0,300.0]],["L","inductance_henry",[3.2,1.6,0.8]],["C","capacitance_farad",[2.2e-6,4.4e-6,8.8e-6]]]:
				var value: float=arm[entry[1]]
				if value==0:continue
				var index: int=entry[2].find(value)
				check(index>=0,"Each AC bank value is physically realizable")
				switches[entry[0]][i*3+index]=true
				leads.append({"a":"%s%d_P"%[entry[0],i],"b":"PV_"+str(arm.a)})
				leads.append({"a":"%s%d_N"%[entry[0],i],"b":"PV_N" if arm.b=="0" else "PV_"+str(arm.b)})
		var solver := preload("res://scripts/circuit_solver.gd").new();solver.frequency=float(plan.frequency_hz)
		var result := solver.solve(terminals,leads,switches,true,float(plan.variable_level))
		check(result.fault=="","Physical AC load-bank wiring solves")
		var reference_p: float=assignment.questions[2].answer
		var reference_q: float=assignment.questions[3].answer
		check(absf(float(result.p)-reference_p)<maxf(.0001,absf(reference_p)*.00001),"Actual AC banks match generated real power")
		check(absf(float(result.q)-reference_q)<maxf(.0001,absf(reference_q)*.00001),"Actual AC banks match generated reactive power")
	print("EQUIPMENT checks=%d failures=%d"%[checks,failures])
	quit(0 if failures==0 else 1)
