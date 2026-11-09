extends SceneTree
const Provider = preload("res://scripts/mth147/provider.gd")
const Generator = preload("res://scripts/mth147/generator.gd")
const Validator = preload("res://scripts/mth147/validator.gd")
var failures: int=0
func _initialize() -> void:
	var samples := 20
	var args := OS.get_cmdline_user_args()
	if args.size()>0:samples=clampi(int(args[0]),1,100)
	var output := FileAccess.open("res://tests/mth147/generated-fixtures.jsonl",FileAccess.WRITE)
	var total := 0;var retries := 0;var started := Time.get_ticks_msec()
	for id in Generator.ids():
		if args.size()>1 and id!=args[1]:continue
		var signatures := {}
		for d in range(5):
			for s in range(samples):
				var seed_value := 470000+d*10000+s*127+int(id.hash()%1000)
				var problem := Provider.generate_problem(id,d,seed_value);total+=1
				if problem.has("error"):failures+=1;print("FAIL generation ",id," d=",d," seed=",seed_value," ",problem);continue
				var checked := Validator.verify(problem)
				if not checked.ok:failures+=1;print("FAIL verification ",id," ",checked)
				retries+=int(problem.parameters.generation_attempt)
				var encoded := JSON.stringify(problem,"",true,true)
				var restored: Variant=JSON.parse_string(encoded)
				if not restored is Dictionary or not Validator.verify(restored).ok:failures+=1;print("FAIL JSON preservation ",id," seed=",seed_value)
				if s==0:
					var repeat := Provider.generate_problem(id,d,seed_value)
					if JSON.stringify(repeat,"",true,true)!=encoded:failures+=1;print("FAIL determinism ",id)
				var public_problem := Provider.public_problem(problem)
				for secret in ["answer","parameters","steps","rubric","verification","seed"]:
					if public_problem.has(secret):failures+=1;print("FAIL privacy ",id," ",secret)
				signatures[JSON.stringify(problem.ast)]=true
				output.store_line(encoded)
		if signatures.size()<mini(5,samples):failures+=1;print("FAIL diversity ",id," count=",signatures.size())
		print("TYPE ",id," complete ",samples*5)
	output.close()
	print("GENERATION_CASES ",total," DETERMINISTIC_RETRIES ",retries," FAILURES ",failures," ELAPSED_MS ",Time.get_ticks_msec()-started)
	quit(1 if failures else 0)
