extends SceneTree
const View=preload("res://scripts/campus/academics/classroom_events/view.gd")
func _initialize() -> void:call_deferred("run")
func click_control(control: Control) -> void:
	var point: Vector2=control.get_global_rect().get_center()
	var motion:=InputEventMouseMotion.new();motion.position=point;Input.parse_input_event(motion)
	for down in [true,false]:
		var button:=InputEventMouseButton.new();button.position=point;button.button_index=MOUSE_BUTTON_LEFT;button.pressed=down;Input.parse_input_event(button)
		await process_frame
func run() -> void:
	var game=load("res://scenes/Main.tscn").instantiate();root.add_child(game)
	for i in 4:await process_frame
	game.front.entered()
	var room="ety155_lecture"
	game.player.global_position=game.lecture_classes.signs[room].desk+Vector3(0,0,2)
	game.campus.set_viewer_position(game.player.global_position)
	game.campus.request_room(room)
	var view:=View.new();game.add_child(view)
	var pointer_actions: Array=[]
	view.action_requested.connect(func(_class_id: String,_event_id: String,op: String,_payload: Variant):pointer_actions.append(op))
	view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	view.apply({"class_id":"visual-class","event_id":"visual-event","course":"ETY155","question":{"prompt":"A 12 V supply feeds two equal resistors in series. What voltage is across one resistor?","options":["3 V","6 V","12 V","24 V"]},"mode":"quiz","round_number":1,"rounds_total":3,"seconds_left":24.0,"can_submit":true,"hands":{"count":0,"raised":false,"selected":false,"called":false}})
	for i in 90:await process_frame
	await RenderingServer.frame_post_draw
	var path=ProjectSettings.globalize_path("res://.godot/classroom-candidate.png")
	var error:=root.get_texture().get_image().save_png(path)
	if error!=OK:push_error("Classroom capture failed: "+str(error));quit(1);return
	print("CLASSROOM_VISUAL_CAPTURE PASS ",path)
	Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
	await click_control(view.panel.hand_button)
	assert("hand" in pointer_actions)
	var close_button: Button=null
	for button in view.panel.find_children("*","Button",true,false):
		if button.text=="Close":close_button=button;break
	assert(close_button!=null)
	await click_control(close_button)
	assert(view.panel!=null and not view.panel.visible and view.reopen_hint.visible)
	assert(view.reopen() and view.panel.visible)
	view.panel.options.select(1)
	await click_control(view.panel.submit_button)
	assert("submit" in pointer_actions)
	view.action_status("visual-class","visual-event","submit","accepted")
	var repeated: Dictionary={"class_id":"visual-class","event_id":"visual-event-2","course":"ETY155","question":{"prompt":"Choose the next circuit value","options":["1 V","2 V"]},"mode":"quiz","round_number":2,"rounds_total":3,"seconds_left":20.0,"can_submit":true}
	view.apply(repeated)
	assert(view.active_id=="visual-event-2" and view.panel.visible and not view.panel.submit_button.disabled)
	print("CLASSROOM_POINTER_FLOW PASS")
	var group_view: Dictionary={"class_id":"visual-class","event_id":"visual-group","course":"ETY155","question":{"prompt":"A 12 V source feeds a 2 kΩ resistor. Explain how to calculate current.","options":["6 mA","12 mA","24 mA"]},"mode":"group","seconds_left":45.0,"can_submit":true,"shared":{"group":"A","task":"Solve the circuit, then review a teammate's method.","count":1,"contributed":false,"entries":[{"text":"Convert 2 kΩ to 2000 Ω first."}],"proposal":"Convert 2 kΩ to 2000 Ω first.","agree":0,"disagree":0,"vote":null}}
	view.apply(group_view)
	for i in 10:await process_frame
	await RenderingServer.frame_post_draw
	var group_path=ProjectSettings.globalize_path("res://.godot/classroom-group-vote.png")
	assert(root.get_texture().get_image().save_png(group_path)==OK)
	print("CLASSROOM_GROUP_VOTE_CAPTURE PASS ",group_path)
	await click_control(view.panel.agree_button)
	assert("vote" in pointer_actions)
	view.queue_free()
	var classes=game.lecture_classes
	var school=game.school
	game.session.roster[1]={"name":"Student"}
	if not school.identities.has(1):school._identify(1,school.local_identity)
	game.player.global_position=classes.signs[room].desk
	assert(classes._start(room,{"kind":"lecture","course_id":"ETY155","week":1,"difficulty":0})=="")
	assert(classes._sign(1,room)=="")
	var activity: Dictionary=classes.classes[room]
	activity.phase="lesson";activity.deadline=classes._now()+180.0
	var owner=preload("res://scripts/campus/academics/classroom_events/controller.gd").new()
	classes.add_child(owner);owner.configure(game);owner.enabled=true
	assert(owner.service.start(room,classes._now(),[],"quiz"))
	var camera:=Camera3D.new();game.add_child(camera);camera.current=true
	camera.global_position=classes.signs[room].board.global_position+Vector3(0,0,4.5)
	camera.look_at(owner.projector.board.global_position)
	for i in 20:await process_frame
	await RenderingServer.frame_post_draw
	var projector_path=ProjectSettings.globalize_path("res://.godot/classroom-projector.png")
	var projector_error:=root.get_texture().get_image().save_png(projector_path)
	if projector_error!=OK:push_error("Projector capture failed: "+str(projector_error));quit(1);return
	print("CLASSROOM_PROJECTOR_CAPTURE PASS ",projector_path)
	var math_now: float=classes._now()
	activity.phase="assignment"
	owner.service.tick(math_now)
	assert(owner.service.rooms.is_empty())
	activity.phase="lesson";activity.course="MTH147";activity.week=2;activity.deadline=math_now+100.0
	assert(owner.service.start(room,math_now,[],"demonstration"))
	owner.service.publish(room,math_now+1.0)
	var math_round=owner.service.rooms[room].round
	assert(not owner.projector.board.signature.contains("diagram") and math_round.reveal().is_empty())
	assert(owner.presentation.panel.options!=null)
	owner.presentation.panel.options.select(math_round.correct_option)
	var math_before=ProjectSettings.globalize_path("res://.godot/classroom-math-prediction.png")
	for i in 20:await process_frame
	await RenderingServer.frame_post_draw
	assert(root.get_texture().get_image().save_png(math_before)==OK)
	print("CLASSROOM_MATH_PREDICTION_CAPTURE PASS ",math_before)
	await click_control(owner.presentation.panel.submit_button)
	assert(math_round.submissions.has(str(school.identities[1])))
	assert(not owner.service.view(1,room,math_now+2.0).has("reveal"))
	var math_close: Button=null
	for button in owner.presentation.panel.find_children("*","Button",true,false):
		if button.text=="Close":math_close=button;break
	assert(math_close!=null)
	await click_control(math_close)
	assert(not owner.presentation.panel.visible and owner.presentation.reopen_hint.visible)
	owner.service.tick(math_now+30.0)
	owner.service.publish(room,math_now+30.0)
	assert(owner.projector.board.signature.contains("diagram") and owner.projector.board.signature.contains("y = "))
	var math_after=ProjectSettings.globalize_path("res://.godot/classroom-math-result.png")
	for i in 20:await process_frame
	await RenderingServer.frame_post_draw
	assert(root.get_texture().get_image().save_png(math_after)==OK)
	print("CLASSROOM_MATH_RESULT_CAPTURE PASS ",math_after)
	assert(owner.presentation.reopen() and owner.presentation.panel.visible)
	game.queue_free();await process_frame;quit(0)
