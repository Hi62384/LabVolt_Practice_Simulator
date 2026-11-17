extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var panel = preload("res://scripts/campus/facilities/facility_panel.gd").new()
	root.add_child(panel)
	panel.state={"profile":{"gym":{"muscles":{"biceps":{"size":0.4,"strength":0.3,"fatigue":0.25,"stimulus":0.2,"delay":0.0}},"history":[]}}}
	panel._gym_progress(Color.WHITE)
	var labels:=PackedStringArray()
	_collect_labels(panel,labels)
	var found:=false
	for label in labels:
		if "Biceps" in label and "40.0%" in label:found=true
	var fatigue_found:=false
	for label in labels:
		if "Fatigue 25%" in label and "stimulus 20%" in label:fatigue_found=true
	if not found or not fatigue_found:
		push_error("Gym progress did not display the saved muscle values")
	print("GYM_PROGRESS_PANEL ","PASS" if found and fatigue_found else "FAIL")
	panel.queue_free()
	quit(0 if found and fatigue_found else 1)

func _collect_labels(node: Node, result: PackedStringArray) -> void:
	if node is Label:result.append(node.text)
	for child in node.get_children():_collect_labels(child,result)
