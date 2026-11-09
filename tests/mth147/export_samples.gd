extends SceneTree
const Provider = preload("res://scripts/mth147/provider.gd")
func _initialize() -> void:
	var samples: Array=[]
	for id in ["w8.right","w8.ssa","w9.graph","w9.equation"]:
		var p := Provider.generate_problem(id,4,147)
		if id=="w8.ssa":
			for seed_value in range(147,180):
				p=Provider.generate_problem(id,4,seed_value)
				if p.answer.solutions.size()==2:break
		samples.append(p)
	var file := FileAccess.open("res://tests/mth147/sample-fixtures.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(samples,"  ",true,true));file.close()
	print("SAMPLES_EXPORTED ",samples.size())
	quit()
