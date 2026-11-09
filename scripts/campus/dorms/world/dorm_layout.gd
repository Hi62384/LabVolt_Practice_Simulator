class_name DormLayout
extends RefCounted
## Pure geometry/anchor contract. Assignment, ownership and interaction stay in the
## authoritative shared dorm service.

const CONTRACT_PATH := "res://assets/campus/dorms/dorm_layout_contract.json"
const CURRENT_PLAYER_CAPACITY := 8
const CORRIDOR_X_MIN := 10.0
const CORRIDOR_X_MAX := 16.0
const ENTRY_Z := 68.0
const FIRST_CENTER_Z := 73.75
const ROOM_STRIDE := 11.5
const ROOM_WIDTH := 7.0
const ROOM_DEPTH := 11.5
const ROOM_HEIGHT := 4.0
const DOOR_WIDTH := 1.3

static func dorm_id(index: int) -> String:
	return "dorm_%02d" % (index + 1)

static func rooms_per_side(capacity: int) -> int:
	return ceili(float(maxi(capacity, 1)) / 2.0)

static func room_contract(index: int, capacity: int) -> Dictionary:
	assert(capacity > 0 and index >= 0 and index < capacity)
	var side_index := index / 2
	var west := index % 2 == 0
	var center_z := FIRST_CENTER_Z + float(side_index) * ROOM_STRIDE
	var center_x := CORRIDOR_X_MIN - ROOM_WIDTH / 2.0 if west else CORRIDOR_X_MAX + ROOM_WIDTH / 2.0
	var wall_x := CORRIDOR_X_MIN if west else CORRIDOR_X_MAX
	var identifier := dorm_id(index)
	return {
		"dorm_id": identifier,
		"index": index,
		"side": "west" if west else "east",
		"center": Vector3(center_x, 0.0, center_z),
		"size": Vector3(ROOM_WIDTH, ROOM_HEIGHT, ROOM_DEPTH),
		"bounds_min": Vector3(center_x - ROOM_WIDTH / 2.0, -0.25, center_z - ROOM_DEPTH / 2.0),
		"bounds_max": Vector3(center_x + ROOM_WIDTH / 2.0, ROOM_HEIGHT + 0.2, center_z + ROOM_DEPTH / 2.0),
		"door": Vector3(wall_x, 0.0, center_z),
		"door_width": DOOR_WIDTH,
		"entry_anchor": Vector3(wall_x + (-1.15 if west else 1.15), 0.0, center_z),
		"room_anchor": Vector3(center_x, 0.0, center_z),
		"workshop_anchor": Vector3(center_x + (-2.10 if west else 2.10), 0.0, center_z + 1.6),
		"loadout_notes_anchor": Vector3(center_x + (1.55 if west else -1.55), 0.0, center_z + 2.5),
		"node_paths": {
			"door_pivot": "%s/DoorPivot" % identifier,
			"door": "%s/DoorPivot/Door" % identifier,
			"door_collision": "%s/DoorPivot/Door/CollisionShape3D" % identifier,
			"entry": "%s/EntryAnchor" % identifier,
			"room": "%s/RoomAnchor" % identifier,
			"workshop": "%s/WorkshopAnchor" % identifier,
			"loadout_notes": "%s/LoadoutNotesAnchor" % identifier,
		}
	}

static func all_rooms(capacity: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for index in range(maxi(capacity, 1)):
		result.append(room_contract(index, maxi(capacity, 1)))
	return result

static func hall_end_z(capacity: int) -> float:
	return FIRST_CENTER_Z + float(rooms_per_side(capacity) - 1) * ROOM_STRIDE + ROOM_DEPTH / 2.0

static func hall_bounds(capacity: int) -> AABB:
	return AABB(Vector3(CORRIDOR_X_MIN, -0.25, ENTRY_Z), Vector3(CORRIDOR_X_MAX - CORRIDOR_X_MIN, 4.45, hall_end_z(capacity) - ENTRY_Z))
