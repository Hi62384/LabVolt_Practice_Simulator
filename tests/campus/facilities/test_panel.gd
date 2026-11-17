extends SceneTree
const Controller=preload("res://scripts/campus/facilities/facility_controller.gd")
const FacilityPanel=preload("res://scripts/campus/facilities/facility_panel.gd")
const Rules=preload("res://scripts/campus/facilities/facility_host.gd")
var saved:=Rules.empty_profile()
var dollars:=100
var ticks:=1000
var checks:=0
var failed:=0
func check(v: bool,label: String) -> void:
	checks+=1
	if not v:failed+=1;printerr("FAIL "+label)
func _initialize() -> void:call_deferred("run")
func run() -> void:
	var controller=Controller.new();root.add_child(controller)
	controller.host.clock=func():return ticks
	controller.host.context=func(_peer):return {"identity":"local","position":Vector3.ZERO,"room_id":"test-room","allowed":true,"grounded":true}
	controller.host.load_profile=func(_id):return saved.duplicate(true)
	controller.host.commit_profile=func(_id,delta,p):dollars+=delta;saved=p.duplicate(true);return true
	controller.host.anchors={"counter":{"room_id":"test-room","kind":"counter:tim_hortons","position":Vector3.ZERO}}
	var panel=FacilityPanel.new();root.add_child(panel);panel.bind(controller)
	panel.has_order_space=func():return true
	panel.open_for("counter","counter:tim_hortons")
	check(panel.state.profile.last_sequence==0,"UI refresh from host")
	var purchase: Button=find_accessible_button(panel,"Order Coffee for $3")
	check(purchase!=null,"restaurant menu shows host menu")
	if purchase!=null:purchase.pressed.emit()
	check(dollars==97 and saved.orders.get("1",{}).get("item","")=="coffee","button performs real purchase")
	check(not panel.pending and panel.state.profile.last_sequence==1,"owner response advances UI sequence")
	for sip in 3:
		ticks+=800
		panel.request_direct({"op":"consume","order_id":"1"})
		check(int(saved.orders.get("1",{}).get("servings",0))==2-sip,"hotbar consumption updates the host order")
	check(saved.orders.is_empty(),"last serving removes the host order")
	ticks+=100
	panel.open_for("","emotes")
	var wave:=find_button(panel,"Wave")
	check(wave!=null,"unlocked emote is available")
	if wave!=null:wave.pressed.emit()
	check(controller.host.movement_locked(1),"emote button locks host movement")
	ticks+=100
	panel.request_direct({"op":"stop"})
	check(not controller.host.movement_locked(1),"stop button releases host movement")
	panel.queue_free();controller.queue_free()
	await process_frame;await process_frame
	print("PANEL checks=",checks," failures=",failed)
	quit(1 if failed else 0)
func find_button(node: Node,prefix: String) -> Button:
	if node is Button and node.text.begins_with(prefix):return node
	for child in node.get_children():
		var found:=find_button(child,prefix)
		if found!=null:return found
	return null
func find_accessible_button(node: Node,name_value: String) -> Button:
	if node is Button and node.accessibility_name==name_value:return node
	for child in node.get_children():
		var found:=find_accessible_button(child,name_value)
		if found!=null:return found
	return null
