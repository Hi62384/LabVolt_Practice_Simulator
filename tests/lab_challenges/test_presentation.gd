extends SceneTree
var assertions := 0
var failures := 0
func _initialize() -> void:call_deferred("run")
func check(ok: bool,msg: String) -> void:
	assertions+=1
	if not ok:failures+=1;push_error(msg)
func run() -> void:
	var decor := preload("res://scripts/lab_challenges/decorations.gd")
	check(decor.unlocks({"count":1,"kinds":{}})==["team_plaque"],"first genuine mastery unlock")
	check("phasor_print" in decor.unlocks({"count":3,"kinds":{}}),"distinct completion tier")
	check("pf_badge" not in decor.unlocks({"count":5,"kinds":{}}),"PF honour requires actual PF challenge mastery")
	check("pf_badge" in decor.unlocks({"count":5,"kinds":{"power_factor":1}}),"PF honour earned")
	check("motor_honours" not in decor.unlocks({"count":8,"kinds":{}}),"motor honour requires model diagnostics mastery")
	check("motor_honours" in decor.unlocks({"count":8,"kinds":{"motor_open_phase":1}}),"motor honour earned")
	for definition in decor.DEFINITIONS.values():
		for line in str(definition.text).split("\n"):
			var width: float=ThemeDB.fallback_font.get_string_size(line,HORIZONTAL_ALIGNMENT_LEFT,-1,60).x*.0016
			check(width<1.0,"preauthored honour text fits fixed plaque")
	var parent := Node3D.new();root.add_child(parent)
	var model: Node3D=decor.render(parent,0,{"left_award":{"id":"team_plaque","path":"res://bad.gd"},"door":{"id":"team_plaque"},"right_award":{"id":"arbitrary_node"}})
	check(model.get_child_count()==2,"only preauthored cosmetic mesh and text created")
	for child in model.get_children():
		check(not child is CollisionObject3D and not child is CollisionShape3D,"cosmetic cannot block gameplay")
		check(child.position.y>3.5 and child.position.z < -3.0,"fixed overhead backboard anchor")
	check(decor.render(parent,-1,{"left_award":{"id":"team_plaque"}}).get_child_count()==0,"invalid bench creates no decoration")
	var panel: CanvasLayer=load("res://scripts/lab_challenges/panel.gd").new();root.add_child(panel);panel.build()
	var requests: Array=[]
	panel.request.connect(func(bench,request):requests.append({"bench":bench,"request":request}))
	panel.show_at(1)
	check(requests.size()==1 and requests[0].bench==1 and requests[0].request.command=="view","panel requests authoritative selected bench frame")
	panel.update_frame({"active":{"id":"attempt","objective":"Real circuit objective","participants":[{"name":"Duplicate","role":"repair","evidence":{"repair":true}}]},"history":[],"unlocks":["team_plaque"],"decorations":{}},"saved")
	check(panel.attempt_id=="attempt" and panel.info.text.contains("Real circuit objective") and panel.decoration.item_count==1,"actual role/objective/unlock controls")
	check(load("res://scripts/lab_challenges/bridge.gd")!=null,"production bridge parses")
	panel.queue_free();parent.queue_free();await process_frame
	print("BASE_PRESENTATION_RESULT assertions=",assertions," failures=",failures)
	quit(1 if failures else 0)
