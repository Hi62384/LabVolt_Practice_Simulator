extends SceneTree
func _initialize() -> void:
	call_deferred("render_preview")
func render_preview() -> void:
	root.size=Vector2i(1000,850)
	var diagram := preload("res://scripts/campus/courses/course_diagram.gd").new()
	root.add_child(diagram)
	diagram.configure(preload("res://scripts/campus/courses/course_provider.gd").lesson("ETY155",9).diagram)
	diagram.position=Vector2(30,30);diagram.size=diagram.custom_minimum_size
	for i in range(5):await process_frame
	await RenderingServer.frame_post_draw
	var path := OS.get_environment("LABVOLT_CURRICULUM_PREVIEW")
	if path!="":root.get_texture().get_image().save_png(path)
	print("DIAGRAM PREVIEW rendered "+str(root.size))
	quit()
