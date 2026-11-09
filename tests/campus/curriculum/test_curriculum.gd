extends SceneTree
const Provider = preload("res://scripts/campus/courses/course_provider.gd")
const DC = preload("res://scripts/campus/courses/dc_assignments.gd")
const Quantity = preload("res://scripts/campus/courses/quantity.gd")
var checks := 0
var failures := 0
func check(value: bool,message: String) -> void:
	checks+=1
	if not value:failures+=1;push_error(message)
func near(a: float,b: float,tolerance: float=1e-7) -> bool:
	return absf(a-b)<=maxf(tolerance,absf(b)*tolerance)
func _initialize() -> void:
	check(Provider.catalog().size()==2,"Two courses")
	check(Provider.weeks("ETY155","lecture").size()==12,"12 DC lecture weeks")
	check(Provider.weeks("ETY155","lab").size()==12,"12 DC lab weeks")
	check(Provider.weeks("ELM253","lecture").size()==11,"11 AC lecture weeks")
	check(Provider.weeks("ELM253","lab").size()==8,"8 AC lab weeks")
	check(Provider.weeks("unknown").is_empty(),"Reject unknown course")
	for course in ["ETY155","ELM253"]:
		for kind in ["lecture","lab"]:
			for meta in Provider.weeks(course,kind):
				var lesson := Provider.lesson(course,int(meta.week),kind,420)
				check(lesson.stages.size()==6,"Six real teaching stages")
				var duration := 0
				for stage in lesson.stages:duration+=int(stage.duration_seconds);check(str(stage.caption).length()>100,"Stage has substantive instruction")
				check(duration==420,"Timeline totals configured duration")
				for difficulty in range(5):
					for seed_value in [1,12345,25777]:
						var assignment := Provider.generate(course,int(meta.week),kind,difficulty,seed_value)
						check(not assignment.has("error"),"Assignment generates "+course+str(meta.week))
						if assignment.has("error"):continue
						var answers := {}
						for i in assignment.questions.size():
							var q: Dictionary=assignment.questions[i]
							answers[str(i)]=str(q.answer)
							check(not q.options.is_empty() or is_finite(float(q.answer)),"Every numeric answer finite")
						check(near(float(Provider.grade(assignment,answers).score),100.0),"Answer keys mark correctly")
						var public := Provider.public_copy(assignment)
						check(not public.has("reference_result") and not public.questions[0].has("answer"),"No answer leak")
	# Independent base-SI arithmetic oracles, not the production reference keys.
	for difficulty in range(5):
		var series := DC.build(4,difficulty,42)
		var sum_r := 0.0
		for p in series.reference_parts:
			if p.kind=="R":sum_r+=float(p.value)
		var voltage: float=series.reference_parts[0].value
		check(near(-float(series.reference_result.i.Vs),voltage/sum_r),"Independent series Ohm law")
		var parallel := DC.build(5,difficulty,42)
		var conductance := 0.0
		for p in parallel.reference_parts:
			if p.kind=="R":conductance+=1.0/float(p.value)
		check(near(-float(parallel.reference_result.i.Vs),float(parallel.reference_parts[0].value)*conductance),"Independent reciprocal sum")
	var superposition := DC.build(9,4,42)
	var contributions := 0.0
	for q in superposition.questions:
		if str(q.prompt).contains("alone"):contributions+=float(q.answer)
	check(near(contributions,float(superposition.reference_result.drop.RL)),"Signed superposition")
	# Independently inspected p185 topology: load bridges LEFT and RIGHT ports,
	# not either port to ground. Vleft=8, Vright=-6; Rth=(3k||6k)+2k=4k.
	var q129 := [DC.part("V","V","s","g",12),DC.part("R1","R","s","left",3000),DC.part("R2","R","left","g",6000),DC.part("R3","R","right","g",2000),DC.part("I","I","right","g",0.003)]
	var open := DC.solve(q129)
	check(near(float(open.v.left)-float(open.v.right),14),"p185 Q129 Vth14V")
	q129.append(DC.part("RL","R","left","right",4000))
	var loaded := DC.solve(q129)
	check(near(float(loaded.drop.RL)*float(loaded.i.RL),0.01225),"p185 Q129 Pmax12.25mW")
	var norton := DC.build(12,2,42)
	var current := 0.0;var conductance := 0.0
	for p in norton.reference_parts:
		if p.kind=="I":current+=float(p.value)
		if p.kind=="R" and p.id!="RL":conductance+=1.0/float(p.value)
	var r := 1.0/conductance
	var load_r: float=norton.reference_parts[2].value
	var thevenin := DC.solve([DC.part("Vs","V","s","g",current*r),DC.part("Rs","R","s","p",r),DC.part("RL","R","p","g",load_r)])
	check(near(float(thevenin.drop.RL),float(norton.reference_result.drop.RL)),"Norton/Thevenin shared solver equivalence")
	for raw in ["0.001 A","1 mA","1000 µA","1e-3 A"]:check(Quantity.check({"answer":0.001,"unit":"A"},raw).correct,"Equivalent current units "+raw)
	for raw in ["1 V","NaN","INF","1 ma","1 mA junk"]:check(not Quantity.check({"answer":0.001,"unit":"A"},raw).correct,"Reject invalid quantity "+raw)
	check(Quantity.check({"answer":20000,"unit":"Ω"},"20 kΩ").correct,"Engineering notation resistor")
	check(not Quantity.check({"answer":0.001,"unit":"A","min_significant_figures":3},"1 mA").correct,"Significant figure policy")
	check(Quantity.check({"answer":0.001,"unit":"A","min_significant_figures":3},"1.00 mA").correct,"Explicit precision accepted")
	check(not Quantity.check({"answer":-5,"unit":"V"},"5 V").correct,"Signed polarity")
	var a := Provider.generate("ETY155",6,"lab",2,42)
	var bindings := {};var nodes := {}
	for p in a.reference_parts:bindings[p.id]=p.id;nodes[p.a]=p.a;nodes[p.b]=p.b
	var target: String=a.practical.target
	var evidence := {"parts":a.reference_parts.duplicate(true),"wires":[],"bindings":bindings,"nodes":nodes,"capabilities":[],"observations":{"voltage":{"component_id":target,"mode":"V","correct_connection":true,"value_si":a.reference_result.drop[target]},"current":{"component_id":target,"mode":"A","correct_connection":true,"value_si":a.reference_result.i[target]}},"verified_procedure":["power_off_before_wiring","range_checked","power_off_after_measurement"]}
	check(near(float(Provider.validate_practical(a,evidence).score),100),"Actual equipment netlist evidence")
	evidence.parts[1].b="wrong"
	check(not Provider.validate_practical(a,evidence).get("connectivity",false),"Wrong physical wiring rejected")
	check(not Provider.validate_practical(Provider.generate("ETY155",12,"lab",2,42),evidence).ok,"Current-source hardware gate")
	check(preload("res://scripts/course_generator.gd").generate(2,2,42).questions.size()==5,"Legacy API remains")
	for seed_value in range(100):
		var colour := DC.build(2,0,seed_value)
		var bands: Dictionary={"black":0,"brown":1,"red":2,"orange":3,"yellow":4,"green":5,"blue":6,"violet":7,"grey":8,"white":9}
		var names: Array=colour.scenario.four_band.bands
		var independently_decoded := (int(bands[names[0]])*10+int(bands[names[1]]))*pow(10,int(bands[names[2]]))
		check(near(independently_decoded,float(colour.questions[0].answer)),"Independent random colour-band decoding")
	for week in range(1,13):
		var last := ""
		for difficulty in range(5):
			var generated := DC.build(week,difficulty,42)
			var signature := JSON.stringify([generated.reference_parts,generated.questions])
			check(signature!=last,"Meaningful difficulty changes week "+str(week))
			last=signature
	var started := Time.get_ticks_usec()
	for i in range(600):Provider.generate("ETY155",i%12+1,"lab",i%5,i)
	print("Generation sample: 600 DC assignments in %d us (local headless CPU sample; no FPS or GPU claim)"%(Time.get_ticks_usec()-started))
	print("CURRICULUM checks=%d failures=%d"%[checks,failures])
	quit(0 if failures==0 else 1)
