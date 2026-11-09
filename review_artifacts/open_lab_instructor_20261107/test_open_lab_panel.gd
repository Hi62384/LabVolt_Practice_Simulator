extends SceneTree
const Panel = preload("res://review_artifacts/open_lab_instructor_20261107/open_lab_panel.gd")
const FormalPolicy = preload("res://review_artifacts/open_lab_instructor_20261107/tutorials/formal_guide_policy.gd")
var failures := 0
var invoked := []
func check(ok: bool, label: String) -> void:
	if not ok:failures+=1;printerr("FAIL OPEN_LAB_UI "+label)
func _initialize() -> void:call_deferred("run")
func selected(action: String) -> void:invoked.append(action)
func run() -> void:
	var root_panel := VBoxContainer.new()
	root.add_child(root_panel)
	Panel.mount(root_panel,func():selected("practice"),func():selected("tutorial"),func():selected("close"))
	var buttons: Array[Node]=root_panel.find_children("*","Button",true,false)
	check(buttons.size()==3,"two main actions plus close")
	check((buttons[0] as Button).text=="Practice Lesson" and (buttons[1] as Button).text=="Equipment Tutorial" and (buttons[2] as Button).text=="Close","action labels")
	check(root_panel.find_children("*","OptionButton",true,false).is_empty(),"no selectors")
	(buttons[0] as Button).pressed.emit()
	(buttons[1] as Button).pressed.emit()
	check(invoked==["practice","tutorial"],"independent routes")
	for course in ["ELM253","ETY155"]:
		check(not FormalPolicy.allowed("Class",{"mode":"Course","kind":"lecture","course_id":course}),"lecture guide hidden "+course)
		check(FormalPolicy.allowed("Class",{"mode":"Course","kind":"lab","course_id":course}),"lab guide shown "+course)
	check(FormalPolicy.allowed("Freeplay",{"kind":"lab"}),"freeplay is outside formal guide guard")
	root_panel.queue_free()
	await process_frame
	await process_frame
	print("OPEN_LAB_UI_RESULT failures=%d"%failures)
	quit(0 if failures==0 else 1)
