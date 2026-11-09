extends SceneTree
const P=preload("res://scripts/mth255/provider.gd")
func _initialize() -> void:
	var args=OS.get_cmdline_user_args();var target=args[0] if not args.is_empty() else "user://mth255-samples.jsonl"
	var p=P.new();var file=FileAccess.open(target,FileAccess.WRITE);var generated=0;var blocked=0
	if file==null:printerr("Could not create test sample file.");quit(1);return
	for group in p.TOPICS:
		for topic in group:
			for difficulty in range(5):
				for seed_value in range(100,200):
					var result=p.generate_problem(topic,difficulty,seed_value)
					if result.has("error"):blocked+=1
					else:file.store_line(JSON.stringify(result));generated+=1
	file.close();print("MTH255_SAMPLES generated=%d blocked=%d"%[generated,blocked]);quit(0)
