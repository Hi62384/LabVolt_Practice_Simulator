extends RefCounted
## Optional waypoint guidance; maps and directory consume the registry directly.
var registry=preload("res://scripts/campus/world/room_registry.gd").new()
var enabled := false
var target_id := ""
var path := PackedVector3Array()
var waypoint := 0
var last_room := ""
var last_viewer := Vector3.ZERO # Last route origin, not last HUD sample.

func select_room(id: String, viewer: Vector3) -> bool:
	if registry.get_room(id).is_empty(): return false
	target_id=id
	enabled=true
	_rebuild(viewer)
	return true

func clear() -> void:
	enabled=false
	target_id=""
	path.clear()
	waypoint=0
	last_room=""

func _rebuild(viewer: Vector3) -> void:
	path=registry.route_from_position(viewer,target_id)
	waypoint=1 if path.size()>1 else 0
	last_room=registry.locate(viewer)
	last_viewer=viewer

func update(viewer: Vector3) -> Dictionary:
	var current: String=registry.locate(viewer)
	if not enabled or path.is_empty(): return {"enabled":false,"location":current}
	# Replan after cumulative travel as well as relocation within one hallway.
	if current!=last_room or viewer.distance_to(last_viewer)>4.0: _rebuild(viewer)
	while waypoint<path.size()-1 and viewer.distance_to(path[waypoint])<1.0: waypoint+=1
	var room: Dictionary=registry.get_room(target_id)
	var offset: Vector3=path[waypoint]-viewer
	var direction := ("East" if offset.x>0 else "West") if absf(offset.x)>absf(offset.z) else ("North" if offset.z>0 else "South")
	if absf(offset.y)>1.0: direction="Stairs up" if offset.y>0 else "Stairs down"
	return {"enabled":true,"location":current,"target_id":target_id,"number":room.number,"title":room.title,"next":path[waypoint],"arrived":current==target_id,"waypoint":waypoint,"count":path.size(),"distance":viewer.distance_to(path[waypoint]),"direction":direction}
