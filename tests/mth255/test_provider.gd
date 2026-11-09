extends SceneTree
const Provider=preload("res://scripts/mth255/provider.gd")
const CircuitView=preload("res://scripts/mth255/impedance_view.gd")
const Adapter=preload("res://scripts/mth255/campus_adapter.gd")
const Demo=preload("res://scripts/mth255/demonstrations.gd")
const Verify=preload("res://scripts/mth255/verifier.gd")
var failures=0
func expect(condition: bool,message: String) -> void:
	if not condition:failures+=1;print("FAIL "+message)
func _initialize() -> void:
	var p=Provider.new();var count=0;var signatures={}
	for week in range(1,11):
		for topic in p.TOPICS[week-1]:
			for d in range(5):
				for seed_value in range(24):
					var result=p.generate_problem(topic,d,seed_value)
					if result.has("error"):
						if topic in ["angle_conversion","exact_trig","trig_identity","quadratic_formula","half_angle","trig_proof","log_combine","log_changebase"] and p._core()==null:continue
						expect(false,"generation %s d%d seed%d %s"%[topic,d,seed_value,str(result)]);continue
					count+=1;expect(Verify.verify(result),"verify "+topic+" d"+str(d)+" seed"+str(seed_value)+" "+result.id)
					expect(JSON.stringify(result)==JSON.stringify(p.generate_problem(topic,d,seed_value)),"seed replay "+result.id)
					signatures[JSON.stringify(result.parameters)]=true
					var public_assignment=p.public_copy({"questions":[result]})
					for field in ["answer","parameters","steps","rubric"]:expect(not public_assignment.questions[0].has(field),"private field "+field)
					if p._core()!=null and topic!="decibel_inverse" or topic not in ["coins","dice","cards","card_union","dice_event","decibel_inverse","trig_identity","angle_conversion","exact_trig","quadratic_formula","half_angle","trig_proof","log_combine","log_changebase"]:
						var marked=p.check(result,result.answer)
						expect(marked.correct,"self grade "+topic+" d"+str(d)+" seed"+str(seed_value)+" "+result.id+" "+str(marked))
						var wrong=result.answer.duplicate(true)
						for key in wrong:
							if wrong[key] is float or wrong[key] is int:wrong[key]=float(wrong[key])+123.456
						if wrong!=result.answer:expect(not p.check(result,wrong).correct,"wrong accepted "+result.id)
	var circuit=CircuitView.new();circuit.configure(p.generate_problem("impedance",4,12).diagram);expect(circuit.descriptor.components.size()==2,"circuit semantic source");circuit.free()
	var adapter=Adapter.new()
	expect(adapter.catalog()[0].lab_weeks==0,"adapter no lab")
	expect(adapter.generate("MTH255",1,"lab",2,12).has("error"),"no electrical open lab")
	var demo=Demo.wave(4,50,PI/3,0.0)
	expect(Verify.near(demo.function.period,0.02) and Verify.near(demo.lead_seconds,1.0/300),"wave demo units")
	expect(Demo.rc(10,1000,0.001,true).tau==1.0,"RC demo SI")
	expect(Demo.root_vectors(3,4,5).points.size()==5,"root demo")
	expect(Demo.complex_vector(0,0).phase_degrees==null,"zero vector undefined phase")
	var rational=p.generate_problem("rational_quadratic",4,91)
	expect(not p.check(rational,{"values":[rational.parameters.excluded],"excluded":[rational.parameters.excluded]}).correct,"excluded denominator root")
	var roots=p.generate_problem("complex_roots",4,91);var reordered=roots.answer.duplicate(true);reordered.values.reverse()
	expect(p.check(roots,reordered).correct,"unordered complex roots")
	reordered.values.pop_back();expect(not p.check(roots,reordered).correct,"incomplete complex roots")
	var saved=JSON.parse_string(JSON.stringify(roots));expect(p.check(saved,roots.answer).correct,"JSON reconnect")
	expect(p.weeks().size()==10 and p.weeks("lab").is_empty(),"lecture-only weeks")
	expect(p.generate(0,2,1).has("error") and p.generate(1,5,1).has("error"),"bounded configuration")
	print("MTH255_LIGHT generated=%d unique_parameters=%d failures=%d shared_core=%s"%[count,signatures.size(),failures,str(p._core()!=null)])
	quit(0 if failures==0 else 1)

