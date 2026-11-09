extends RefCounted
## Data-driven text and mount contract for fixed physical entrance signs.
const Signage = preload("res://scripts/campus/presentation/signage/campus_signage.gd")

static func display_title(room: Dictionary) -> String:
	if str(room.get("id", "")) == "shop":
		return "Shop & Trading"
	return str(room.get("title", "")).replace("Â·", "·")

static func directory_lines(registry: RefCounted, floor: int) -> PackedStringArray:
	var lines := PackedStringArray(["FLOOR %d" % (floor + 1)])
	for room in registry.directory():
		if int(room.floor) == floor:
			lines.append("%s  %s" % [str(room.number), display_title(room)])
	return lines

static func direction_lines(registry: RefCounted, floor: int, max_z: float) -> PackedStringArray:
	var west := PackedStringArray()
	var east := PackedStringArray()
	for room in registry.directory():
		if int(room.floor) != floor or float(room.door[2]) > max_z:
			continue
		var line := "%s %s" % [str(room.number), display_title(room)]
		if float(room.door[0]) < 13.0:
			west.append(line)
		else:
			east.append(line)
	return PackedStringArray(["← " + ", ".join(west), ", ".join(east) + " →"])

static func mount(parent: Node3D, text: String, center: Vector3, yaw: float, size: Vector2, font_size: int) -> Label3D:
	var backing := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(size.x, size.y, 0.08)
	backing.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("183b42")
	backing.material_override = material
	backing.position = center
	backing.rotation.y = yaw
	parent.add_child(backing)
	var label := Signage.create_label(text, center + Basis(Vector3.UP, yaw) * Vector3(0, 0, 0.055), yaw, font_size)
	label.double_sided = false
	label.set_meta("physical_mount", true)
	parent.add_child(label)
	return label

static func mount_portal(parent: Node3D) -> Label3D:
	# The exterior packet supplies the x13/y4.54/z-11.32 frame.
	# Sign bottom is 4.12 m: well above the walkable six-metre opening.
	return mount(parent, "LABVOLT CAMPUS\nENTRANCE · MAIN BUILDING", Vector3(13, 4.54, -11.57), PI, Vector2(6.4, 0.84), 43)
