extends Control
signal answer_changed(key: String,value: String)
signal stroke_added(stroke: Dictionary)
var paper: Dictionary
var page := 0
var writable := false
var ink: Control
var body: VBoxContainer
const PAPER_SIZE := Vector2(780,1100)
const INK := Color("263743")
func _ready() -> void:
	custom_minimum_size=PAPER_SIZE;size=PAPER_SIZE
	var paper_theme := Theme.new();paper_theme.default_font_size=18
	for type in ["Label","LineEdit","OptionButton","Button"]:paper_theme.set_color("font_color",type,INK)
	for type in ["LineEdit","OptionButton"]:
		for state in ["normal","focus","hover","pressed","disabled"]:
			var box := StyleBoxFlat.new();box.bg_color=Color("eef3f4");box.border_color=Color("899ba5");box.set_border_width_all(1);box.set_content_margin_all(8);paper_theme.set_stylebox(state,type,box)
		paper_theme.set_color("font_disabled_color",type,Color("52636a"));paper_theme.set_color("font_uneditable_color",type,INK)
	for control_type in ["LineEdit","OptionButton","Button"]:
		for state in ["font_color","font_hover_color","font_pressed_color","font_focus_color","font_hover_pressed_color","font_selected_color","font_uneditable_color"]:paper_theme.set_color(state,control_type,INK)
		paper_theme.set_color("font_placeholder_color",control_type,Color("566773"))
		paper_theme.set_color("font_disabled_color",control_type,Color("52636a"))
	theme=paper_theme
	var background := Panel.new();background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);background.mouse_filter=Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new();style.bg_color=Color("fcfaf2");style.shadow_color=Color(0,0,0,.35);style.shadow_size=10;style.shadow_offset=Vector2(3,5);background.add_theme_stylebox_override("panel",style);add_child(background)
	var margin := MarginContainer.new();margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for edge in ["left","right"]:margin.add_theme_constant_override("margin_"+edge,46)
	for edge in ["top","bottom"]:margin.add_theme_constant_override("margin_"+edge,35)
	add_child(margin)
	body=VBoxContainer.new();body.add_theme_constant_override("separation",13);margin.add_child(body)
	var lesson: bool=paper.lesson
	var p: Dictionary=paper.project
	text(str(p.get("course_id","ELM253"))+"     /     "+("BASIC DC ELECTRICITY" if p.get("course_id","")=="ETY155" else "AC ELECTRICAL SYSTEMS"),14)
	text("NOTEBOOK" if paper.get("notebook",false) else "EQUIPMENT GUIDE" if paper.get("guide",false) else "GUIDED LESSON" if lesson else "LABORATORY ASSIGNMENT",13,Color("547c82"))
	text(p.title,28)
	text("Name: "+str(paper.owner_name)+"     •     "+["Beginner","Easy","Normal","Hard","Expert"][clampi(int(p.difficulty),0,4)],15)
	var rule := HSeparator.new();body.add_child(rule)
	var teaching: Dictionary=p.get("teaching",{})
	if teaching.is_empty():
		teaching={"equipment":p.get("equipment_text",p.get("procedure","")),"worked":p.get("worked_example",p.get("theory",""))} if p.has("course_id") else preload("res://scripts/lesson_content.gd").teaching(int(p.topic))
	var instruction_pages: Array = p.get("practice_instruction_pages",[])
	if paper.get("guide",false):
		var entry: Dictionary=p.guide_pages[page]
		text(entry.title,24);text(entry.text,18)
	elif page>0 and page<=instruction_pages.size():
		text("EQUIPMENT & PROCEDURE  ·  %d / %d" % [page,instruction_pages.size()],20)
		text(str(instruction_pages[page-1]),17)
	else:
		var section := page-instruction_pages.size() if page>0 else page
		match section:
			0:
				text("01  /  "+("UNDERSTAND THE CIRCUIT" if lesson else "OBJECTIVE & GIVEN DATA"),20)
				text(p.theory if lesson else "Use the circuit and the given quantities below. Show your method, then record your answers on page 3.")
				var diagram := preload("res://scripts/worksheet_diagram.gd").new();diagram.topic=int(p.topic);diagram.course_id=str(p.get("course_id","ELM253"));diagram.descriptor=p.get("diagram",{});body.add_child(diagram)
				text("Figure 1. Concept diagram — use the specified values and connections.",13,Color("66716f"))
				text("HOW TO USE THE EQUIPMENT" if lesson else "GIVEN QUANTITIES",17)
				text(("Turn to the following pages for the equipment and wiring instructions." if not instruction_pages.is_empty() else teaching.equipment) if lesson else p.data,17)
			1:
				text("02  /  "+("WORKED EXAMPLE" if lesson else "METHOD & OBSERVATIONS"),20)
				if lesson:
					text("Follow each substitution before trying the practice questions. These example values are separate from your practice data.",16)
					text(teaching.worked,20)
					text("TRY IT AT THE BENCH",18)
					text("Follow the equipment and procedure pages, then record the readings on your practice page." if not instruction_pages.is_empty() else p.procedure,17)
					text("CHECK YOUR METHOD",18)
					text("Write the equation first. Convert units before substituting. Keep the sign of reactive quantities. Round only at the end, and compare the result with the meter range or expected physical value.",17)
				else:
					text(teaching.equipment,18)
					text("CALCULATIONS",18)
					text(p.procedure,18)
					text("RELATIONSHIPS",18);text(p.theory,18)
			2:
				text("03  /  "+("YOUR TURN — PRACTICE" if lesson else "RESULTS & CALCULATIONS"),20)
				if lesson:text(p.data,15)
				for i in p.questions.size():
					var q: Dictionary=p.questions[i];var key := str(i)
					text("%d. %s"%[i+1,q.prompt]+("  ["+q.unit+"]" if q.unit!="" else ""),18)
					if q.options.is_empty():
						var input := LineEdit.new();input.text=str(paper.answers.get(key,""));input.placeholder_text="Your answer";input.max_length=160;input.editable=writable;input.text_changed.connect(func(value):answer_changed.emit(key,value));body.add_child(input)
					else:
						var options := OptionButton.new();options.add_item("Select one answer")
						for option in q.options:options.add_item(option)
						var popup := options.get_popup()
						popup.add_theme_color_override("font_color",Color("f5f7fa"));popup.add_theme_color_override("font_hover_color",Color("ffffff"))
						options.select(clampi(int(paper.answers[key])+1,0,q.options.size()) if paper.answers.has(key) else 0);options.disabled=not writable;options.item_selected.connect(func(index):answer_changed.emit(key,str(index-1)));body.add_child(options)
				text("Working space — use the pencil to show equations and calculations.",14,Color("66716f"))
			3:
				text("04  /  "+("PRACTICE FEEDBACK" if lesson else "MARKED WORK"),20)
				if paper.mark.is_empty():
					text("Use Check practice to see corrections. Your result will not affect your profile average." if lesson else "Take your sheet to the teacher and hand it in. Your marked answers will appear on this page.",20)
				else:
					text("%.1f%%"%paper.mark.score,36,Color("28715c"))
					text("Practice only — excluded from your average." if lesson else paper.mark.get("reason","Marked by your instructor."),16)
					for i in paper.mark.feedback.size():
						var feedback: Dictionary=paper.mark.feedback[i]
						text("%d. %s"%[i+1,"Correct" if feedback.correct else "Review this answer"],18,Color("28715c") if feedback.correct else Color("ad4741"))
						text("Your answer: "+str(paper.answers.get(str(i),"—"))+"\nExpected: "+str(feedback.expected)+"\n"+str(feedback.explanation),17)
	var space := Control.new();space.size_flags_vertical=Control.SIZE_EXPAND_FILL;space.custom_minimum_size.y=70;body.add_child(space)
	var source_text := str(p.source)
	if p.source is Dictionary:source_text=str(p.source.get("document","Course reference"))+" · pages "+str(p.source.get("pages",""))
	text("Reference: "+source_text,12,Color("78817e"))
	var total := int(p.get("guide_pages",[]).size()) if paper.get("guide",false) else 4+instruction_pages.size()
	text("LAB / VOLT     •     "+("Practice — does not affect your average" if lesson else "Use each question's stated units and tolerance.")+"     •     %d / %d"%[page+1,total],12,Color("78817e"))
	ink=preload("res://scripts/paper_ink.gd").new();ink.background=false;ink.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);ink.editable=writable;ink.strokes=paper.strokes.get(str(page),[]).duplicate(true);ink.stroke_finished.connect(func(stroke):stroke_added.emit(stroke));add_child(ink);set_drawing(false)
func _process(_delta: float) -> void:
	if not is_instance_valid(body):return
	var height := maxf(PAPER_SIZE.y,body.get_combined_minimum_size().y+70)
	if absf(size.y-height)>1:custom_minimum_size.y=height;size.y=height
func text(value: String,font_size := 18,color := INK) -> Label:
	var label := Label.new();label.text=value;label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;label.add_theme_font_size_override("font_size",font_size);label.add_theme_color_override("font_color",color);body.add_child(label);return label
func set_drawing(enabled: bool) -> void:
	if ink==null:return
	ink.mouse_filter=Control.MOUSE_FILTER_STOP if enabled and ink.editable else Control.MOUSE_FILTER_IGNORE
