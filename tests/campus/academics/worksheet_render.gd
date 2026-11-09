extends SceneTree
const Page = preload("res://scripts/worksheet_page.gd")
var failed := false
func _initialize() -> void:call_deferred("run")
func run() -> void:
	var assignment := {"course_id":"ETY155","kind":"lab","week":4,"title":"Series circuit worksheet rendering fixture","topic":0,"difficulty":4,"source":"Original explicitly specified test circuit; not a source PDF reproduction","seed":12,"theory":"Series resistors share current. V = IR. The sum of voltage drops equals the source voltage.","data":"Vs=12 V. R1=1 kΩ. R2=2 kΩ. Predict current before wiring.","procedure":"Power off. Build the stated actual node connections. Set the meter mode and range. Record voltage and current with correct lead placement.","questions":[{"prompt":"Total circuit current","unit":"A","options":[]},{"prompt":"Voltage across R2","unit":"V","options":[]}],"diagram":{"kind":"netlist","parts":[{"id":"Vs","kind":"V","a":"p","b":"g","value":12.0},{"id":"R1","kind":"R","a":"p","b":"n","value":1000.0},{"id":"R2","kind":"R","a":"n","b":"g","value":2000.0}]}}
	var viewport := SubViewport.new();viewport.size=Vector2i(820,1500);viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(viewport)
	for index in [0,2]:
		var page := Page.new();page.paper={"project":assignment,"lesson":false,"owner_name":"Student","answers":{},"strokes":{},"mark":{}};page.page=index;viewport.add_child(page)
		await process_frame;await process_frame
		await RenderingServer.frame_post_draw
		var image := viewport.get_texture().get_image()
		if image==null:failed=true;push_error("Worksheet image unavailable")
		else:
			var directory := OS.get_environment("ACADEMICS_CAPTURE_DIR")
			if directory!="":image.save_png(directory.path_join("worksheet-page-%d.png"%index))
		print("WORKSHEET_RENDER page=%d height=%.0f body_min=%.0f"%[index,page.size.y,page.body.get_combined_minimum_size().y])
		page.free()
	viewport.free()
	print("WORKSHEET_RENDER failures=%d"%int(failed))
	quit(1 if failed else 0)
