extends RefCounted
## Register the physical owner's actual opening Marker3D; never copy a world position.
var openings := {}
var station := -1

func configure(index: int) -> void:
	assert(index>=0 and index<3)
	station=index

func register_socket(id: String, opening: Marker3D, pick_body: CollisionObject3D) -> void:
	assert(id in preload("res://scripts/dc_station.gd").PORTS)
	assert(not openings.has(id))
	assert(opening.is_ancestor_of(pick_body))
	assert(pick_body.position.is_equal_approx(Vector3.ZERO))
	openings[id]=opening
	pick_body.set_meta("role","dc_port")
	pick_body.set_meta("dc_station",station)
	pick_body.set_meta("dc_port",id)
	pick_body.set_meta("label",id)
	pick_body.set_meta("dc_opening",opening)

func anchor(id: String) -> Transform3D:
	assert(openings.has(id) and is_instance_valid(openings[id]))
	return openings[id].global_transform

func port_positions() -> Dictionary:
	var result := {}
	for id in openings:
		if is_instance_valid(openings[id]):result[id]=anchor(id).origin
	return result

func highlight(id: String, active: bool) -> void:
	if openings.has(id) and openings[id].has_method("set_highlighted"):
		openings[id].call("set_highlighted",active)
