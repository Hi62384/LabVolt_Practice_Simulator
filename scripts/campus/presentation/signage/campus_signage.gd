class_name CampusSignage
extends RefCounted
## Campus text convention: +Z is the readable local front of a Label3D.
## Never expose a Label3D back face: it reads as mirrored from the other side.

const DEFAULT_TEXT := Color("e7f5ef")
const DEFAULT_OUTLINE := Color("193e47")

static func room_number(room: Dictionary) -> String:
	return str(room.get("number", room.get("room_number", ""))).strip_edges()

static func room_hud_identity(room: Dictionary) -> String:
	var number := room_number(room)
	var title := str(room.get("title", room.get("name", ""))).strip_edges()
	if number.is_empty():
		return title if not title.is_empty() else "Campus"
	return number if title.is_empty() else number + " · " + title

static func create_label(text: String, point: Vector3, yaw: float = 0.0, font_size: int = 56) -> Label3D:
	var label := Label3D.new()
	label.text = text
	label.font_size = font_size
	label.pixel_size = 0.006
	label.position = point
	label.rotation.y = yaw
	label.modulate = DEFAULT_TEXT
	label.outline_modulate = DEFAULT_OUTLINE
	label.no_depth_test = false
	label.double_sided = false
	label.visibility_range_end = 24.0
	label.set_meta("readable_front_local", Vector3.BACK)
	return label

static func add_room_number_faces(parent: Node3D, room: Dictionary, door: Vector3, west_wall: bool) -> Array[Label3D]:
	var number := room_number(room)
	var faces: Array[Label3D] = []
	# West rooms have their corridor-facing wall normal toward +X; east rooms toward -X.
	var corridor_offset := Vector3(0.12 if west_wall else -0.12, 3.5, 0.0)
	var interior_offset := -Vector3(corridor_offset.x, 0.0, 0.0) + Vector3(0.0, 3.5, 0.0)
	var corridor := create_label(number, door + corridor_offset, PI / 2.0 if west_wall else -PI / 2.0, 42)
	var interior := create_label(number, door + interior_offset, -PI / 2.0 if west_wall else PI / 2.0, 42)
	for face in [corridor, interior]:
		face.set_meta("sign_role", "room_identity")
		face.set_meta("room_number", number)
		parent.add_child(face)
		faces.append(face)
	return faces
