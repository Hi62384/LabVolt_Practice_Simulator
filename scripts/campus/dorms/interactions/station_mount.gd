class_name DormStationMount
extends RefCounted

## Attaches interaction targets to prop anchors furnished by the dorm builder.
## This intentionally creates no blue panel, billboard, or replacement UI.

static func mount_room(router: DormPersonalStationRouter, room_id: String, anchors: Dictionary) -> Dictionary:
	var mounted := {}
	for kind in ["loadout","notes"]:
		var anchor: Node=anchors.get(kind)
		if is_instance_valid(anchor) and router.register_station(anchor,room_id,kind):mounted[kind]=anchor
	return mounted

static func unmount_room(router: DormPersonalStationRouter, mounted: Dictionary) -> void:
	for station in mounted.values():router.unregister_station(station)
	mounted.clear()
