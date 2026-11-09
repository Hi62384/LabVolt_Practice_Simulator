extends SceneTree
## Source-asset authoring tool; run only when changing original student geometry.
const Factory = preload("res://scripts/campus/npcs/crowd_mesh.gd")
func _initialize() -> void:
	for simple in [false, true]:
		var start := Time.get_ticks_usec()
		var mesh := Factory.build(simple)
		var path := "res://assets/campus/npcs/student_reduced.tres" if simple else "res://assets/campus/npcs/student_full.tres"
		var error := ResourceSaver.save(mesh, path)
		if error != OK:
			printerr("Cannot save crowd mesh " + path)
			quit(1)
			return
		print("CROWD ASSET %s: vertices=%d, build+save=%d usec" % [path, mesh.surface_get_array_len(0), Time.get_ticks_usec() - start])
	quit()
