extends SceneTree
const Host=preload("res://scripts/campus/facilities/facility_host.gd")
const Controller=preload("res://scripts/campus/facilities/facility_controller.gd")
const Room=preload("res://scripts/campus/facilities/facility_room.gd")
const FacilityPanel=preload("res://scripts/campus/facilities/facility_panel.gd")
const ActivityVisual=preload("res://scripts/campus/facilities/avatar_activity.gd")
const LedgerAdapter=preload("res://scripts/campus/facilities/ledger_adapter.gd")
const Service=preload("res://scripts/campus/facilities/facility_service.gd")
class HookSession extends Node:
	var facility_translation_guard:=Callable()
class HookPlayer extends Node:
	var facility_movement_locked:=Callable()
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var parent:=Node3D.new();root.add_child(parent)
	var h=Host.new();var stations:={}
	for id in ["tim_hortons","subway","gym"]:
		var room=Room.new();parent.add_child(room)
		var result: Dictionary=room.build({"id":id,"kind":"gym" if id=="gym" else "restaurant","anchor":[26,0,33]},h.menu)
		assert(result.size()==(5 if id=="gym" else 5))
		for key in result:assert(not stations.has(key));stations[key]=result[key]
		assert(room.nearest(Vector3(26,0,31.8))!="" or id=="gym")
	var panel=FacilityPanel.new();root.add_child(panel)
	panel.state={"level":1,"profile":Host.empty_profile(),"menu":h.menu,"active":{}}
	panel.redraw()
	var visual:=Node3D.new();parent.add_child(visual)
	var motion=ActivityVisual.new();parent.add_child(motion);motion.bind_visual(visual)
	motion.apply_event({"activity":"holding","item":"coffee"})
	assert(motion.food!=null)
	motion.apply_event({"activity":"emote","emote":"wave","duration_ms":1800})
	await process_frame
	motion.apply_event({"activity":"idle"})
	assert(visual.position==Vector3.ZERO)
	var service=Service.new();parent.add_child(service)
	service.configure(RefCounted.new(),null,func(_peer):return {"identity":"test","position":Vector3.ZERO,"room_id":"gym","allowed":true,"grounded":true},func(_room):return [1])
	assert(not service.controller.host.trusted(1).allowed)
	var session=HookSession.new();var player=HookPlayer.new();parent.add_child(session);parent.add_child(player)
	assert(service.install_movement_hooks(session,player))
	assert(service.controller.host.trusted(1).allowed)
	service.controller.host.active[1]={"type":"emote"}
	assert(session.facility_translation_guard.call(1,Vector3(100,0,0),Vector3.ZERO)==Vector3.ZERO)
	service.local_locked=true;assert(player.facility_movement_locked.call())
	service.controller.host.active.clear()
	print("SOURCE room/station/panel checks PASS stations=",stations.size())
	parent.queue_free();panel.queue_free()
	await process_frame
	await process_frame
	quit()
