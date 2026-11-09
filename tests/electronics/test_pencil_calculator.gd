extends SceneTree
func _initialize() -> void:
	var calculator = load("res://scripts/scientific_calculator.gd")
	for entry in [["sqrt(8",sqrt(8.0)],["sqrt(sqrt(16",2.0],["sin(30",0.5],["(2+3",5.0],["atan(5/9",rad_to_deg(atan(5.0/9.0))]]:
		var value: Dictionary = calculator.calculate(entry[0])
		assert(value.ok and abs(value.value-entry[1])<0.000001, str(entry))
	assert(not calculator.calculate("sqrt(8))").ok)
	assert(not calculator.calculate("sqrt(").ok)
	var widget = calculator.new()
	root.add_child(widget)
	await process_frame
	widget.press("√")
	widget.press("8")
	widget.press("=")
	assert(widget.display.text=="sqrt(8)")
	assert(abs(widget.answer-sqrt(8.0))<0.000001)
	assert(widget.display.caret_column==7)
	assert(load("res://scripts/paper_ui.gd") != null)
	print("PASS: automatic parentheses, nested functions, button input, invalid syntax, worksheet script")
	widget.free()
	quit()
