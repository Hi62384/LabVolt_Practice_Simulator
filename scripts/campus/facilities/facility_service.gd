extends Node3D
var cafeteria_seat_source: Node
signal profile_committed(identity: String)
## Composition adapter: no core writes. Registry is the world's single RoomRegistry.
const Controller=preload("res://scripts/campus/facilities/facility_controller.gd")
const Furniture=preload("res://scripts/campus/facilities/facility_room.gd")
const LedgerAdapter=preload("res://scripts/campus/facilities/ledger_adapter.gd")
const ActivityVisual=preload("res://scripts/campus/facilities/avatar_activity.gd")
var controller: Node
var adapter: RefCounted
var rooms:={}
var visuals:={}
var registry: RefCounted
var movement_ready:=false
var local_locked:=false
var table_food: Dictionary={}

func configure(room_registry: RefCounted, ledger: RefCounted, trusted_context: Callable, interest: Callable) -> void:
	registry=room_registry
	controller=Controller.new();controller.name="FacilityController";add_child(controller)
	adapter=LedgerAdapter.new();adapter.ledger=ledger;adapter.is_authority=func():return multiplayer.is_server()
	adapter.committed.connect(func(identity):profile_committed.emit(identity))
	controller.host.load_profile=adapter.load_facilities
	controller.host.commit_profile=adapter.commit
	controller.host.context=func(peer):
		var value: Dictionary=trusted_context.call(peer)
		if not movement_ready:value=value.duplicate(true);value.allowed=false
		return value
	controller.interested_peers=interest
	controller.room_event.connect(_event)
	controller.owner_result.connect(func(result):
		if result.has("state"):local_locked=not result.state.get("active",{}).is_empty())

func install_movement_hooks(session: Node, player: Node) -> bool:
	# Proposed hooks are deliberately tiny, but required before gameplay enables.
	if not "facility_translation_guard" in session or not "facility_movement_locked" in player:return false
	session.facility_translation_guard=accept_translation
	player.facility_movement_locked=func():return local_locked
	movement_ready=true
	return true

func use_offline_profile(identity: String, profile: RefCounted) -> void:
	adapter=preload("res://scripts/campus/facilities/profile_adapter.gd").new()
	adapter.profiles[identity]=profile;adapter.is_authority=func():return multiplayer.is_server()
	controller.host.load_profile=adapter.load_facilities;controller.host.commit_profile=adapter.commit

func mount_room(id: String, shell: Node3D) -> bool:
	if rooms.has(id):return true
	var definition: Dictionary=registry.get_room(id)
	if definition.is_empty():return false
	var furniture=Furniture.new();furniture.name="FacilityFurniture";shell.add_child(furniture)
	var stations: Dictionary=furniture.build(definition,controller.host.menu)
	if stations.is_empty():furniture.queue_free();return false
	# Room anchors are world coordinates; support a translated shell without double offsets.
	furniture.global_position=Furniture.vector(definition.anchor)
	rooms[id]=furniture
	controller.host.anchors.merge(stations,true)
	return true

func unmount_room(id: String) -> void:
	if not rooms.has(id):return
	# Keep lightweight authoritative anchors when graphics unload; occupied rooms remain active in world.
	if is_instance_valid(rooms[id]):rooms[id].queue_free()
	rooms.erase(id)

func bind_avatar(peer: int, visual: Node3D) -> void:
	if visuals.has(peer) and is_instance_valid(visuals[peer]):visuals[peer].queue_free()
	var activity=ActivityVisual.new();visual.get_parent().add_child(activity);activity.bind_visual(visual)
	visuals[peer]=activity

func _event(peer: int, event: Dictionary) -> void:
	if peer==multiplayer.get_unique_id() and event.get("activity","") in ["idle","seat","exercise","emote"]:local_locked=event.get("activity","")!="idle"
	if visuals.has(peer) and is_instance_valid(visuals[peer]):
		visuals[peer].apply_event(event,peer!=multiplayer.get_unique_id())
	if event.has("held"):
		var order_id := str(event.get("order_id", "0"))
		var key := "%d/%s" % [peer, order_id]
		if order_id == "0":
			for room in rooms.values():
				if is_instance_valid(room):room.sync_food(peer,event.held)
		if is_instance_valid(table_food.get(key)):table_food[key].queue_free()
		table_food.erase(key)
		var held: Dictionary=event.held
		if held.get("station","")=="table":
			var target := preload("res://scripts/campus/facilities/food_visual.gd").placed(str(held.item),int(held.servings),peer,str(controller.host.menu[held.item].name))
			add_child(target)
			target.global_position=Furniture.vector(held.position)
			target.set_meta("order_id", order_id)
			table_food[key]=target

func nearest(position_value: Vector3) -> Dictionary:
	var room_id: String=registry.locate(position_value)
	if room_id=="cafeteria" and is_instance_valid(cafeteria_seat_source):return cafeteria_seat_source.nearest_cafeteria_seat(position_value)
	if not rooms.has(room_id) or not is_instance_valid(rooms[room_id]):return {}
	var id: String=rooms[room_id].nearest(position_value)
	return {"id":id,"kind":controller.host.anchors[id].kind} if id!="" else {}

func accept_translation(peer: int, proposed: Vector3, previous: Vector3) -> Vector3:
	# Apply inside Session.accept_pose before its existing speed/bounds/collision checks.
	return previous if controller.host.movement_locked(peer) else proposed

func unbind_avatar(peer: int) -> void:
	if visuals.has(peer) and is_instance_valid(visuals[peer]):visuals[peer].queue_free()
	visuals.erase(peer)
