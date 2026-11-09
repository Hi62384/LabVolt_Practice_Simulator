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
	panel.open_for("counter","counter:tim_hortons")
	check(panel.state.profile.last_sequence==0,"UI refresh from host")
	var purchase: Button=find_button(panel,"Coffee")
	check(purchase!=null,"restaurant menu shows host menu")
	purchase.pressed.emit()
	check(dollars==97 and saved.held.item=="coffee","button performs real purchase")
	check(not panel.pending and panel.state.profile.last_sequence==1,"owner response advances UI sequence")
	for sip in 3:
		ticks+=800
		var consume:=find_button(panel,"Drink / eat")
		check(consume!=null,"held food action visible")
		consume.pressed.emit()
	check(saved.held.is_empty(),"UI consumes food through host")
	check(find_button(panel,"Drink / eat")==null,"consumed food disappears from UI")
	ticks+=100
	find_button(panel,"Emote • Wave").pressed.emit()
	check(controller.host.movement_locked(1),"emote button locks host movement")
	ticks+=100
	find_button(panel,"Stand / stop").pressed.emit()
	check(not controller.host.movement_locked(1),"stop button releases host movement")
	panel.queue_free();controller.queue_free()
	await process_frame;await process_frame
	print("PANEL checks=",checks," failures=",failed)
	quit(1 if failed else 0)
func find_button(panel: Control,prefix: String) -> Button:
	for child in panel.body.get_children():
		if child is Button and child.text.begins_with(prefix):return child
	return null
