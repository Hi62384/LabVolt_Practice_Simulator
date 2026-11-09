class_name CircuitStudioContract
extends RefCounted

const ROOM_ID := "circuit_studio"
const LEGACY_PAGE := "ics"
const ROLE := "circuit_studio_station"
const MANIFEST_PATH := "res://assets/campus/circuit_studio/room.json"

const ACTION_PAGES := {
	"ic_builder": "studio_ic",
	"pcb_builder": "studio_pcb",
	"prototype_bench": "design",
	"firmware_console": "code",
	"kit_library": "kits",
}

static func room_record() -> Dictionary:
	var file := FileAccess.open(MANIFEST_PATH,FileAccess.READ)
	if file==null:return {}
	var parsed: Variant=JSON.parse_string(file.get_as_text())
	return parsed.get("room",{}).duplicate(true) if parsed is Dictionary else {}

static func valid_room_record(room: Dictionary) -> bool:
	if str(room.get("id",""))!=ROOM_ID:return false
	for key in ["center","size","door","approach","anchor","bounds_min","bounds_max"]:
		if not room.get(key) is Array or room[key].size()!=3:return false
	var low:=vector(room.bounds_min);var high:=vector(room.bounds_max);var door:=vector(room.door)
	return low.x<high.x and low.z<high.z and door.z>low.z and door.z<high.z

static func vector(values: Array) -> Vector3:
	return Vector3(float(values[0]),float(values[1]),float(values[2]))

