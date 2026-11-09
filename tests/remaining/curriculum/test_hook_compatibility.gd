extends SceneTree
## Compile and exercise the exact shared-hook proposals IN MEMORY. No unowned
## source file, snapshot or live project is modified by this compatibility test.
const Base=preload("res://scripts/campus/courses/course_provider.gd")
var checks := 0
var failures := 0
func check(value: bool,label: String) -> void:
	checks+=1
	if not value:failures+=1;push_error(label)
func _initialize() -> void:
	var source := FileAccess.get_file_as_string("res://scripts/campus_course_provider.gd")
	var hook := "\tif int(assignment.get(\"generator_schema\",0))>=3:return assignment"
	if not source.contains(hook):source=source.replace("\tif assignment.has(\"error\"):return assignment","\tif assignment.has(\"error\"):return assignment\n"+hook)
	var script := GDScript.new();script.source_code=source
	check(script.reload()==OK,"Proposed root provider hook compiles")
	if failures:quit(1);return
	var wrapper: Object=script.new()
	for course in ["ELM253","ETY155"]:
		for kind in ["lecture","lab"]:
			for week in Base.weeks(course,kind):
				for d in range(5):
					for seed_value in [1,155]:
						var expected := Base.generate(course,int(week.week),kind,d,seed_value)
						var actual: Dictionary=wrapper.generate(course,int(week.week),kind,d,seed_value)
						check(var_to_bytes(actual)==var_to_bytes(expected),"Root wrapper preserves complete randomized givens/keys/real equipment plan")
	var paper_source := FileAccess.get_file_as_string("res://scripts/worksheet_diagram.gd")
	var old := "text(Vector2(235,y+25),\"%s · %s %s\"%[str(part.get(\"id\",\"\")),str(float(part.get(\"value\",0))),unit],16)"
	var updated := "text(Vector2(235,y+25),str(part.get(\"id\",\"\"))+\" · \"+preload(\"res://scripts/campus/courses/course_diagram.gd\").display_value(part),18)"
	paper_source=paper_source.replace(old,updated)
	var paper_script := GDScript.new();paper_script.source_code=paper_source
	check(paper_script.reload()==OK,"Proposed paper engineering/phase label hook compiles")
	print("SHARED HOOK COMPATIBILITY checks=%d failures=%d (in-memory only)"%[checks,failures])
	quit(1 if failures else 0)
