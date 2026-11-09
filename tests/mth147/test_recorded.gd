extends SceneTree
const Validator = preload("res://scripts/mth147/validator.gd")
func _initialize() -> void:
	var file := FileAccess.open("res://tests/mth147/generated-fixtures.jsonl",FileAccess.READ)
	if file==null:print("FAIL recorded fixtures missing");quit(1);return
	var cases := 0;var failures := 0
	while not file.eof_reached():
		var line := file.get_line()
		if line.is_empty():continue
		var problem: Dictionary=JSON.parse_string(line);var checked := Validator.verify(problem);cases+=1
		if not checked.ok:failures+=1;print("FAIL recorded ",problem.id," ",checked)
	file.close();print("RECORDED_CASES ",cases," FAILURES ",failures)
	quit(1 if failures else 0)
