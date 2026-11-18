extends SceneTree
const Host=preload("res://scripts/campus/facilities/facility_host.gd")
const Machine=preload("res://scripts/campus/facilities/gym_cable_machine.gd")
const Furniture=preload("res://scripts/campus/facilities/facility_room.gd")
class FakeController extends Node:
	var last:={}
	func request(value: Dictionary) -> void:last=value.duplicate(true)
var profiles:={"1":Host.empty_profile(),"2":Host.empty_profile()}
var now:=1000
var failures: Array[String]=[]
func check(value: bool,message: String) -> void:
	if not value:failures.append(message)
func _initialize() -> void:call_deferred("run")
func run() -> void:
	var host=Host.new();host.authority=func():return true
	host.clock=func():return now
	host.context=func(peer):return {"identity":str(peer),"position":Vector3.ZERO,"room_id":"gym","allowed":true,"grounded":true}
	host.load_profile=func(id):return profiles[id].duplicate(true)
	host.commit_profile=func(id,_d,p):profiles[id]=p.duplicate(true);return true
	host.anchors["gym/cable_0"]={"kind":"cable","room_id":"gym","position":Vector3.ZERO}
	for exercise in Host.CABLE_EXERCISES:
		now+=100
		var result=host.act(1,{"op":"start","station":"gym/cable_0","exercise":exercise,"weight":10,"sequence":int(profiles["1"].last_sequence)+1})
		check(result.ok,"failed to start "+exercise)
		if result.ok:
			now+=100
			var blocked=host.act(2,{"op":"start","station":"gym/cable_0","exercise":exercise,"weight":10,"sequence":1})
			check(not blocked.ok,"occupied station accepted another player")
			result=host.act(1,{"op":"lower","sequence":int(profiles["1"].last_sequence)+1})
			check(result.ok,"could not lower the cable handle")
			now+=int(host.active[1].half_ms)
			result=host.act(1,{"op":"beat","sequence":int(profiles["1"].last_sequence)+1})
			check(result.ok,"cable movement failed")
			now+=100
			host.act(1,{"op":"cancel","sequence":int(profiles["1"].last_sequence)+1})
	for bad in [0,6,105]:
		now+=100
		var result=host.act(1,{"op":"start","station":"gym/cable_0","exercise":"cable_fly","weight":bad,"sequence":int(profiles["1"].last_sequence)+1})
		check(not result.ok,"invalid cable weight accepted")
	var machine=Machine.new();root.add_child(machine);machine.build("gym/cable_0")
	machine.on_room_event(1,{"activity":"exercise","station":"gym/cable_0","exercise":"lat_pulldown","phase":1,"selector_weight":50})
	for i in 50:machine._process(.02)
	check(machine.selected==5 and machine.phase>.9,"stack failed to select and rise")
	check(is_equal_approx(machine.loading_mount.position.y,1.62+.24*machine.phase),"plate loading post detached from moving stack")
	check(machine.selected_resistance() == 50, "selected resistance disagrees with the pin")
	check(is_equal_approx(machine.selection_pin.position.y, machine.weights[-5].position.y), "pin is detached from the bottom plate of the selected stack")
	check(machine.pin_targets[-5].get_meta("weight") == 50, "pin target disagrees with the selected stack plate")
	var top: Vector3=machine.cable.position-machine.cable.basis.y*.5
	var end: Vector3=machine.cable.position+machine.cable.basis.y*.5
	check(top.distance_to(Vector3(0,2.3,.13))<.001 and end.distance_to(machine.handle.get_meta("connector"))<.001,"cable endpoints detached")
	var stack_start: Vector3=machine.stack_cable.position-machine.stack_cable.basis.y*.5
	var stack_end: Vector3=machine.stack_cable.position+machine.stack_cable.basis.y*.5
	var stack_top: Vector3=machine.weights[-1].position+Vector3(0,.035,0)
	check(stack_start.distance_to(Vector3(0,2.3,.13))<.001 and stack_end.distance_to(stack_top)<.001,"stack cable detached from pulley or selected weights")
	var avatar: Node3D=preload("res://scripts/toon_character.gd").build(preload("res://scripts/toon_character.gd").defaults())
	root.add_child(avatar);avatar.position=Vector3(0,0,1.5)
	machine.on_room_event(1,{"activity":"exercise","station":"gym/cable_0","exercise":"lat_pulldown","phase":1,"selector_weight":50},avatar)
	machine._process(.02)
	var hands: Vector3=(avatar.get_node("Body/ArmL/Hand").global_position+avatar.get_node("Body/ArmR/Hand").global_position)*.5
	check(machine.handle.global_position.distance_to(hands)<.001,"handle did not follow the lifter's hands")
	machine.on_room_event(1,{"activity":"exercise","station":"gym/cable_0","exercise":"cable_fly","phase":1,"selector_weight":50},avatar)
	machine._process(.02)
	check(machine.second_handle.visible and machine.second_cable.visible,"fly did not show both cable grips")
	check(machine.handle.global_position.distance_to(avatar.get_node("Body/ArmL/Hand").global_position)<.001 and machine.second_handle.global_position.distance_to(avatar.get_node("Body/ArmR/Hand").global_position)<.001,"fly grips did not follow both hands")
	var second_end: Vector3=machine.second_routed_cable.position+machine.second_routed_cable.basis.y*.5
	check(second_end.distance_to(machine.second_handle.get_meta("connector"))<.001,"second cable detached from its grip")
	machine.on_room_event(1,{"activity":"exercise","station":"gym/cable_0","exercise":"cable_press","phase":1,"selector_weight":50},avatar)
	machine._process(.02)
	check(machine.routed_cable.visible and machine.second_routed_cable.visible,"chest press did not route both cables around the lifter")
	var routed_end: Vector3=machine.routed_cable.position+machine.routed_cable.basis.y*.5
	var guide_end: Vector3=machine.cable.position+machine.cable.basis.y*.5
	var next_start: Vector3=machine.route_sections[0].position-machine.route_sections[0].basis.y*.5
	check(routed_end.distance_to(machine.handle.get_meta("connector"))<.001 and next_start.distance_to(guide_end)<.001,"routed cable segments detached")
	for i in machine.route_sections.size()-1:
		var section_end: Vector3=machine.route_sections[i].position+machine.route_sections[i].basis.y*.5
		var next_start_point: Vector3=machine.route_sections[i+1].position-machine.route_sections[i+1].basis.y*.5
		check(section_end.distance_to(next_start_point)<.001,"curved cable sections detached")
	# Move the hands over a range of positions and verify both segmented leads
	# remain continuous and attached while the machine is active.
	for step in 12:
		avatar.position.z=1.5+float(step)*.015
		machine._process(.02)
		for pair in [[machine.cable,machine.route_sections,machine.routed_cable,machine.handle],[machine.second_cable,machine.second_route_sections,machine.second_routed_cable,machine.second_handle]]:
			var chain: Array=[pair[0]];chain.append_array(pair[1]);chain.append(pair[2])
			for i in chain.size()-1:
				var joint_end: Vector3=chain[i].position+chain[i].basis.y*.5
				var joint_start: Vector3=chain[i+1].position-chain[i+1].basis.y*.5
				check(joint_end.distance_to(joint_start)<.001,"cable opened a gap during movement")
			var tip: Vector3=chain[-1].position+chain[-1].basis.y*.5
			check(tip.distance_to(pair[3].get_meta("connector"))<.001,"cable tip lost its grip during movement")
	machine.on_room_event(1,{"activity":"exercise","station":"gym/cable_0","exercise":"lateral_raise","phase":1,"selector_weight":50},avatar)
	machine._process(.02)
	var low_start: Vector3=machine.cable.position-machine.cable.basis.y*.5
	check(low_start.distance_to(Vector3(0,.20,.13))<.001,"low-cable exercise did not use the lower pulley")
	var activity=preload("res://scripts/campus/facilities/avatar_activity.gd").new();root.add_child(activity);activity.bind_visual(avatar)
	activity.apply_event({"activity":"exercise","station":"gym/cable_0","exercise":"lat_pulldown","phase":1,"machine_position":Vector3.ZERO},false)
	for i in 120:activity._process(.02)
	check(absf(absf(avatar.global_rotation.y)-PI)<.04,"lifter did not turn toward the cable machine")
	activity.apply_event({"activity":"exercise","station":"gym/cable_0","exercise":"cable_row","phase":1,"machine_position":Vector3.ZERO,"cable_stance":Vector3(0,0,1.25)},false)
	for i in 120:activity._process(.02)
	check(avatar.global_position.distance_to(Vector3(0,0,1.25))<.03,"lifter did not move to the cable station")
	activity.free()
	machine.on_room_event(2,{"activity":"idle"})
	check(machine.occupant==1,"other player stopped machine")
	machine.on_room_event(1,{"activity":"idle"})
	for i in 50:machine._process(.02)
	check(machine.occupant==0 and is_zero_approx(machine.phase) and not machine.second_handle.visible and not machine.second_cable.visible and not machine.routed_cable.visible and not machine.second_routed_cable.visible,"machine did not reset")
	avatar.free()
	machine.free()
	var panel=preload("res://scripts/campus/facilities/facility_panel.gd").new();root.add_child(panel)
	panel.station_kind="cable";panel.station_id="gym/cable_0"
	panel.state={"level":1,"profile":profiles["1"],"active":{}}
	panel.cable_resistance = func(_station: String): return panel.get_meta("pin_kg")
	panel.set_meta("pin_kg", 35)
	panel.redraw()
	var fake:=FakeController.new();root.add_child(fake);panel.controller=fake
	var selector: OptionButton=panel.find_children("*","OptionButton",true,false)[0]
	check(selector.get_selected_metadata() != null, "exercise selector did not select an exercise")
	check(not panel.find_child("ExerciseLoad", true, false).visible, "cable selector offered a second resistance control")
	for i in selector.item_count:
		if selector.get_item_metadata(i) == "lat_pulldown":
			selector.select(i)
			selector.item_selected.emit(i)
			break
	for node in panel.find_children("*","Button",true,false):
		if node.text=="Start set":node.pressed.emit();break
	check(fake.last.get("exercise","")=="lat_pulldown" and fake.last.get("weight",0)==35,"selection was not sent to host")
	panel.free()
	fake.free()
	var room=Furniture.new();root.add_child(room)
	var stations: Dictionary=room.build({"id":"gym","kind":"gym","anchor":[0,0,33]},Host.MENU)
	check(room.gym_cables.size()==2 and stations.has("gym/cable_0") and stations.has("gym/cable_1"),"gym did not mount two cable stations")
	room.free()
	for failure in failures:push_error(failure)
	print("CABLE_MACHINE ","PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)
