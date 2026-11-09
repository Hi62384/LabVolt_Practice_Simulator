extends "res://scripts/campus/computers/desktop_ui.gd"
## Adds existing academic answer controls without changing desktop owner's file.
func _build_course_work() -> void:
	super._build_course_work()
	content.add_child(_button("Refresh course work",func():_send({"op":"refresh"})))
	for assignment in snapshot.get("assignments",[]):
		if not assignment is Dictionary:continue
		var paper_id: int=int(assignment.get("id",0))
		var answers: Dictionary=assignment.get("answers",{})
		var questions: Array=assignment.get("questions",[])
		for index in questions.size():
			var question = questions[index]
			var label := Label.new()
			label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
			label.text=str(question.get("prompt",question.get("text","Question %d"%(index+1)))) if question is Dictionary else str(question)
			content.add_child(label)
			var row := HBoxContainer.new()
			content.add_child(row)
			var answer := LineEdit.new()
			answer.max_length=512
			answer.text=str(answers.get(str(index),""))
			answer.size_flags_horizontal=Control.SIZE_EXPAND_FILL
			row.add_child(answer)
			var key := str(index)
			row.add_child(_button("Save answer",func():_send({"op":"answer","paper":paper_id,"question":key,"value":answer.text})))
func _on_desktop_changed(value: Dictionary) -> void:
	super._on_desktop_changed(value)
	if value.is_empty():
		_switch_app("Files")
	elif active_app=="Course work":
		_switch_app("Course work")
