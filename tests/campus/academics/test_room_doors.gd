extends SceneTree
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var campus = preload("res://scripts/campus/world/campus_world.gd").new()
	root.add_child(campus)
	await process_frame
	var door = campus.room_roots["study"].get_node("Door_study")
	assert(door.hinges.size()==2)
	assert(not door.opened)
	door.request_toggle()
	assert(door.opened)
	assert(absf(door.hinges[0].rotation.y)<.1)
	await create_timer(.75).timeout
	assert(absf(door.hinges[0].rotation.y)>1.5)
	door.request_toggle()
	assert(not door.opened)
	assert(campus.room_roots["tim_hortons"].get_node_or_null("Door_tim_hortons")==null)
	assert(campus.room_roots["subway"].get_node_or_null("Door_subway")==null)
	print("PASS room doors and open restaurant entrances")
	quit()
