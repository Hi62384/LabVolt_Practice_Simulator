extends SceneTree
const Model = preload("res://scripts/math_ui/plot_model.gd")
func _initialize() -> void:
	var args:=OS.get_cmdline_user_args()
	if args.size()!=2:quit(2);return
	var cases:Variant=JSON.parse_string(FileAccess.get_file_as_string(args[0]))
	if not cases is Array:quit(2);return
	var output:=[]
	for item in cases:
		var y:=Model.evaluate(item.function,float(item.x))
		output.append(y if is_finite(y) else null)
	var file:=FileAccess.open(args[1],FileAccess.WRITE)
	if file==null:quit(2);return
	file.store_string(JSON.stringify(output));file.close()
	print("MATH_UI_SAMPLES count=%d"%output.size())
	quit()
