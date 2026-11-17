extends StaticBody3D
var door: Node
func request_toggle() -> void:
	if is_instance_valid(door): door.request_toggle()
