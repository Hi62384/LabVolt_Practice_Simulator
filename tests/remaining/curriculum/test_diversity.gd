extends SceneTree
const DC=preload("res://scripts/campus/courses/dc_assignments.gd")
const Legacy=preload("res://scripts/course_generator.gd")
const Provider=preload("res://scripts/campus/courses/course_provider.gd")
const Quantity=preload("res://scripts/campus/courses/quantity.gd")
const Drawing=preload("res://scripts/campus/courses/course_diagram.gd")
var failures := 0
var checks := 0
func check(value: bool,label: String) -> void:
	checks+=1
	if not value:failures+=1;push_error(label)
func _initialize() -> void:
	var report: Array=[]
	for week in range(1,13):
		for d in range(5):
			var cases := {};var five_bands := {};var four_bands := {};var topologies := {}
			for seed_value in range(32):
				var a := DC.build(week,d,seed_value)
				check(not a.has("error"),"DC generator non-singular")
				cases[var_to_bytes(a.reference_parts).hex_encode()]=true
				five_bands[str(a.scenario.five_band.bands)]=true
				four_bands[str(a.scenario.four_band.bands)]=true
				topologies[str(a.reference_parts.map(func(p):return [p.kind,p.a,p.b]))]=true
				check(a.reference_parts.size()<30,"Practical component budget")
				check(a.reference_parts.filter(func(p):return p.kind=="I").size()<=4,"Four hardware current-source limit")
				check(a.reference_parts.filter(func(p):return p.kind=="V").size()<=3,"Three hardware voltage-channel limit")
				for p in a.reference_parts:
					check(is_finite(float(p.value)),"Finite device parameter")
					if p.kind=="R":check(float(p.value)>0.01,"Positive nondegenerate resistance")
					check(absf(float(a.reference_result.drop[p.id]))<30,"DC voltage/compliance boundary")
				for part in a.diagram.parts:
					check(a.reference_parts.any(func(p):return p==part),"Diagram matches actual circuit descriptor")
			check(cases.size()>=24,"DC parameter diversity per week/difficulty")
			check(five_bands.size()>=10 and four_bands.size()>=10,"Valid seeded band/tolerance diversity")
			report.append({"course":"ETY155","week":week,"difficulty":d,"unique_circuits":cases.size(),"unique_five_band_cases":five_bands.size(),"unique_topologies":topologies.size()})
	for topic in range(11):
		for d in range(3):
			var givens := {};var keys := {};var item_keys := {}
			for seed_value in range(32):
				var a := Legacy.generate(topic,d,seed_value)
				givens[JSON.stringify(a.scenario)]=true
				keys[JSON.stringify(a.questions.map(func(q):return q.answer))]=true
				for q in a.questions:
					if not q.options.is_empty():continue
					if not item_keys.has(q.template_id):item_keys[q.template_id]={}
					item_keys[q.template_id][str(q.answer)]=true
			check(givens.size()==32 and keys.size()>=16,"ELM scenario/key-vector diversity")
			for template in item_keys:check(item_keys[template].size()>=3,"Every legacy calculation template varies with seed: "+str(template))
			report.append({"course":"ELM253","topic":topic,"difficulty":d,"unique_key_vectors":keys.size(),"numeric_template_diversity":item_keys.keys().map(func(key):return {"id":key,"unique_answers":item_keys[key].size()})})
	for raw in ["1e-3 A","1.000 mA","1000 µA","0.001000 A"]:check(Quantity.check({"answer":.001,"unit":"A","min_significant_figures":3},raw).correct==(raw!="1e-3 A"),"Explicit significant-figure policy")
	check(Quantity.check({"answer":4,"unit":"%"},"0.04 1").correct,"Equivalent explicit dimensionless/percent representations")
	check(Quantity.check({"answer":-5,"unit":"V"},"−5 V").correct,"Unicode minus")
	check(Quantity.check({"answer":0,"unit":"A","min_significant_figures":3},"0 A").correct,"Exact zero uses absolute tolerance")
	for raw in ["1e999 A","0 V","1,000 mA","1 mA/mA","1e-3 m"]:check(not Quantity.check({"answer":.001,"unit":"A"},raw).correct,"Malformed/wrong dimension is rejected")
	check(Drawing.display_value({"kind":"C","value":2.2e-6,"unit":"F"})=="2.2 µF","Small capacitor drawing preserves actual value")
	check(Drawing.display_value({"kind":"V","value":"30∠-120°","unit":"V RMS"}).contains("-120"),"AC source diagram preserves phase")
	var path := OS.get_environment("LABVOLT_CURRICULUM_DIVERSITY")
	if path!="":var file := FileAccess.open(path,FileAccess.WRITE);file.store_string(JSON.stringify(report,"  "));file.close()
	print("DIVERSITY checks=%d failures=%d"%[checks,failures])
	quit(1 if failures else 0)
