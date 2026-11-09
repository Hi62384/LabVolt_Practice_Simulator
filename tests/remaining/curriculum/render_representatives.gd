extends SceneTree
## Run only inside the coordinator's rendered-validation window. No campus scene,
## heavy import, profiling, network clients or Computer Use is involved.
func _initialize() -> void:call_deferred("run")
func run() -> void:
	var folder := OS.get_environment("LABVOLT_CURRICULUM_RENDER_DIR")
	if folder=="":push_error("Set task-local render output directory");quit(2);return
	DirAccess.make_dir_recursive_absolute(folder)
	var cases := [["ETY155",3,3,"pot_loading"],["ETY155",12,4,"four_current_sources"],["ELM253",5,4,"unbalanced_delta"],["ELM253",4,4,"mixed_ac"]]
	for entry in cases:
		var assignment: Dictionary=preload("res://scripts/campus/courses/course_provider.gd").generate(entry[0],entry[1],"lab",entry[2],155)
		var drawing := preload("res://scripts/campus/courses/course_diagram.gd").new()
		drawing.configure(assignment.diagram)
		var viewport := SubViewport.new();viewport.size=Vector2i(960,int(drawing.custom_minimum_size.y)+40)
		viewport.disable_3d=true;viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
		root.add_child(viewport);viewport.add_child(drawing)
		drawing.position=Vector2(20,20);drawing.size=drawing.custom_minimum_size
		for i in range(3):await process_frame
		await RenderingServer.frame_post_draw
		var path := folder+"/"+str(entry[3])+".png"
		var error := viewport.get_texture().get_image().save_png(path)
		if error!=OK:push_error("Could not save representative render");quit(2);return
		print("RENDERED "+path+" "+str(viewport.size))
		viewport.queue_free();await process_frame
	print("REPRESENTATIVE RENDERS=4")
	quit()
