extends CanvasLayer
const UI = preload("res://scripts/ui/design_system/widgets.gd")
const Course = preload("res://scripts/course_generator.gd")
var game: Node
var school: Node
var screen: PanelContainer
var column: VBoxContainer
var surface: Control
var document_id := 0
var page_index := 0
var page_label: Label
var save_status: Label
var zoom_control: MenuButton
var page_body: VBoxContainer
var ink: Control
var rendered_revision := -1
var rendered_mark := {}
var pending := {}
var reader_generation := 0
var flushing := false
var save_timer := 0.0
var calculator: LineEdit
var reading := false
var open_lab_instructor_visible := false
var page_view: Control
var pencil_mode := false
var pencil_color := Color("263743")
var pencil_width := 2.0
var calculator_state := ""
var calc_saved := {}
var drawer_saved := {}
var annotation_layer: Control
var annotation_inspector: VBoxContainer
var paper_tool := "answer"
var view_states := {}
var reader_view_key := ""
var view_scroll: ScrollContainer
var tools_scroll: ScrollContainer
var view_document := -1
var view_page := -1
var view_zoom := 1.0
var panning := false
var pan_origin := Vector2.ZERO
var view_wrapper: Control
var restoring_view := false
var completed_popup_round := -1
var calculator_widget: Control
var calculator_drawer: Control
var tool_case: Control
var workspace_view: Control
var awaiting_annotation_undo := false
var active_cursor_tool := "answer"
func build(owner_game: Node) -> void:
	game=owner_game
	school=game.school
	_load_reader_views()
	layer=30
	screen=PanelContainer.new()
	screen.theme=preload("res://scripts/ui/design_system/theme.gd").create()
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	screen.offset_left=40
	screen.offset_top=20
	screen.offset_right=-40
	screen.offset_bottom=-20
	add_child(screen)
	var style := StyleBoxFlat.new()
	style.bg_color=Color("13232ef4")
	style.set_content_margin_all(20)
	style.set_corner_radius_all(12)
	screen.add_theme_stylebox_override("panel",style)
	surface = Control.new()
	surface.clip_contents = true
	screen.add_child(surface)
	column=VBoxContainer.new()
	column.add_theme_constant_override("separation",10)
	surface.add_child(column)
	column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	screen.hide()
	school.updated.connect(_updated)
func _clear() -> void:
	flush()
	remember_view()
	reader_generation+=1
	panning=false
	if is_instance_valid(calculator_drawer):calculator_drawer.queue_free();calculator_drawer=null
	if is_instance_valid(tool_case):tool_case.get_parent().queue_free();tool_case=null
	Input.set_custom_mouse_cursor(null,Input.CURSOR_ARROW)
	active_cursor_tool="answer"
	if is_instance_valid(page_view):page_view.mouse_default_cursor_shape=Control.CURSOR_ARROW
	restoring_view=false
	ink=null
	page_view=null
	workspace_view=null
	annotation_layer=null
	reader_view_key=""
	for child in column.get_children():
		column.remove_child(child)
		child.queue_free()
func _label(parent: Node,value: String,font_size: int=18) -> Label:
	var label := Label.new()
	label.text=value
	label.add_theme_font_size_override("font_size",font_size)
	label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	parent.add_child(label)
	return label
func _button(parent: Node,value: String,callback: Callable) -> Button:
	var icon_key := "check" if "Submit" in value else "close" if value=="Close" else "back" if value=="‹" else "play" if value=="›" else "course"
	var b := UI.action("Previous page" if value=="‹" else "Next page" if value=="›" else value,icon_key,Callable(),"Submit" in value)
	b.custom_minimum_size=Vector2(55,40)
	b.size_flags_vertical=Control.SIZE_SHRINK_CENTER
	var generation := reader_generation
	b.pressed.connect(func():
		if screen.visible and generation==reader_generation:callback.call()
	)
	parent.add_child(b)
	return b
func close() -> void:
	open_lab_instructor_visible=false
	screen.custom_minimum_size=Vector2.ZERO
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	screen.offset_left=40;screen.offset_top=20;screen.offset_right=-40;screen.offset_bottom=-20
	remember_view()
	flush()
	Input.set_custom_mouse_cursor(null,Input.CURSOR_ARROW)
	active_cursor_tool="answer"
	if is_instance_valid(calculator_drawer):calculator_drawer.close()
	screen.hide()
	reading=false
	reader_generation+=1
	restoring_view=false
	if game.front.in_game:game.capture()
func teacher() -> void:
	open_lab_instructor_visible=school.mode in ["Open Lab","Freeplay","Creative Freeplay"]
	if open_lab_instructor_visible:
		_show_open_lab_instructor()
		return
	flush()
	reading=false
	_clear()
	game.release_mouse()
	screen.show()
	_label(column,"LAB INSTRUCTOR",30)
	_label(column,school.average())
	if school.mode=="Class":
		var assigned: Dictionary=school.activity if school.activity is Dictionary else {}
		_label(column,"%s · Week %d · %s"%[str(assigned.get("course_id","Assigned course")),int(assigned.get("week",0)),str(assigned.get("kind","Class")).capitalize()])
		_label(column,"%s · %02d:%02d"%[school.phase.capitalize(),maxi(0,int(school.remaining))/60,maxi(0,int(school.remaining))%60])
		if school.phase=="travel":_label(column,"Find your assigned room. Teaching begins when the countdown ends.")
		elif school.phase=="lesson":_label(column,str(school.teaching_stage().get("title","Teaching in progress")))
		elif school.phase=="assignment":_label(column,"Complete your assigned work before the deadline.")
		if school.phase=="assignment" and school.held(multiplayer.get_unique_id())==0:_button(column,"Replace missing Class sheet",func():school.request({"op":"replacement"});close())
		if preload("res://scripts/campus/academics/open_lab/tutorials/formal_guide_policy.gd").allowed(school.mode,assigned):_button(column,"Equipment guide",func():school.request({"op":"guide"});close())
	else:
		_build_freeplay_teacher_controls()
	if multiplayer.is_server() and not school.formal_active():_button(column,"Earthing demonstration",safety_demo_menu)
	if school.mode=="Class" and school.phase=="assignment":_button(column,"Abandon my active assessment…",func():confirm_abandon())
	var held_id: int=school.held(multiplayer.get_unique_id())
	if held_id!=0:
		var paper: Dictionary=school.papers[held_id]
		_label(column,"Holding: "+str(paper.project.title))
		if paper.mark.is_empty():_button(column,"Hand in held assignment",func():school.request({"op":"submit","id":held_id});close())
		_button(column,"Read held sheet",func():open_sheet(held_id))
	_button(column,"Back to lab",close)
func _show_open_lab_instructor() -> void:
	flush()
	reading=false
	_clear()
	game.release_mouse()
	screen.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	var viewport_size := get_viewport().get_visible_rect().size
	screen.custom_minimum_size=Vector2.ZERO
	screen.size=Vector2(minf(680,viewport_size.x-48),minf(470,viewport_size.y-48))
	screen.position=(viewport_size-screen.size)*0.5
	screen.show()
	preload("res://scripts/campus/academics/open_lab/open_lab_panel.gd").mount(column,_show_open_lab_practice,_open_lab_tutorial,close)
	var first := column.find_children("*","Button",true,false)[0] as Button
	first.grab_focus()

func _show_open_lab_practice() -> void:
	if school.mode not in ["Open Lab","Freeplay","Creative Freeplay"]:return
	var service = preload("res://scripts/campus/academics/open_lab/practice/practice_service.gd")
	var registry = school.room_bridge.registry
	if registry == null:return
	var course: String = service.course_for_room(registry.locate(game.player.global_position))
	_clear()
	_label(column, "PRACTICE SHEET", 25)
	if course.is_empty():
		_label(column, "Ask the instructor inside the electrical laboratory.")
		_button(column, "Back", _show_open_lab_instructor)
		return
	_label(column, course + " · Ungraded laboratory practice")
	var weeks := OptionButton.new()
	weeks.add_item("Random lab week", 0)
	for lab in school.course_bridge.weeks(course, "lab"):
		var number := int(lab.get("week", 0))
		if number in service.SAFE_WEEKS.get(course, []):
			weeks.add_item("Week %d · %s" % [number, str(lab.get("title", ""))], number)
	column.add_child(weeks)
	var levels := OptionButton.new()
	for level in ["Beginner", "Easy", "Normal", "Hard", "Expert"]:
		levels.add_item(level)
	levels.select(2)
	column.add_child(levels)
	var actions := HBoxContainer.new()
	column.add_child(actions)
	_button(actions, "Back", _show_open_lab_instructor)
	_button(actions, "Get practice sheet", func():
		school.request({"op":"practice_lesson", "week":weeks.get_selected_id(), "difficulty":levels.selected})
		close())
	weeks.grab_focus()

func _open_lab_tutorial() -> void:
	if school.mode not in ["Open Lab","Freeplay","Creative Freeplay"]:return
	if game.has_method("open_lab_equipment_tutorial"):
		close()
		game.call("open_lab_equipment_tutorial")
	else:_label(column,"Equipment tutorial is unavailable in this laboratory.")

func _unhandled_key_input(event: InputEvent) -> void:
	if open_lab_instructor_visible and screen.visible and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close()

func _build_freeplay_teacher_controls() -> void:
	_label(column,"Practice assignments and lessons never change official course marks.")
	var row := HBoxContainer.new()
	column.add_child(row)
	var practice_course := OptionButton.new()
	for value in school.course_ids():practice_course.add_item(value)
	practice_course.select(maxi(school.course_ids().find(str(school.activity.get("course_id","ELM253"))),0))
	row.add_child(practice_course)
	var topics := OptionButton.new();row.add_child(topics)
	var refresh_topics := func():
		topics.clear()
		for week in school.course_bridge.weeks(practice_course.get_item_text(practice_course.selected),school.practice_kind(practice_course.get_item_text(practice_course.selected))):topics.add_item("Week %d · %s"%[int(week.get("week",topics.item_count+1)),str(week.get("title",""))])
	practice_course.item_selected.connect(func(_index):refresh_topics.call())
	refresh_topics.call()
	var level := OptionButton.new()
	for difficulty in ["Beginner","Easy","Normal","Hard","Expert"]:level.add_item(difficulty)
	row.add_child(level)
	var buttons := HBoxContainer.new()
	column.add_child(buttons)
	_button(buttons,"Take assignment",func():school.request({"op":"new","course_id":practice_course.get_item_text(practice_course.selected),"week":topics.selected+1,"difficulty":level.selected});close())
	_button(buttons,"Random assignment",func():school.request({"op":"new","course_id":practice_course.get_item_text(practice_course.selected),"random":true,"difficulty":level.selected});close())
	_button(buttons,"Equipment guide",func():school.request({"op":"guide"});close())
	_button(buttons,"Take lesson",func():school.request({"op":"new","course_id":practice_course.get_item_text(practice_course.selected),"week":topics.selected+1,"difficulty":level.selected,"lesson":true});close())
func open_sheet(id: int) -> void:
	if not school.papers.has(id):return
	var item: Dictionary=school.papers[id]
	if not str(item.get("supply_id","")).is_empty() and not item.get("notebook",false):return
	open_lab_instructor_visible=false
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	screen.offset_left=40;screen.offset_top=20;screen.offset_right=-40;screen.offset_bottom=-20
	flush()
	document_id=id
	page_index=clampi(int(view_states.get(_reader_key(school.papers[id]),{}).get("page",school.papers[id].page)),0,_page_count(school.papers[id])-1)
	reading=true
	rendered_revision=-1
	game.release_mouse()
	screen.show()
	_build_reader()
func _editable(paper: Dictionary) -> bool:
	return paper.owner==multiplayer.get_unique_id() and paper.mark.is_empty()
func _can_mark(paper: Dictionary) -> bool:
	return paper.owner==multiplayer.get_unique_id() and school.can_mark_paper(paper)
func _page_count(paper: Dictionary) -> int:
	if bool(paper.get("guide",false)):
		return maxi(1,paper.get("project",{}).get("guide_pages",[]).size())
	return maxi(1,school.page_count(paper))
func _reader_copy(source: Dictionary) -> Dictionary:
	var copy: Dictionary=source.duplicate(true)
	copy.erase("identity")
	if int(copy.owner)!=multiplayer.get_unique_id():
		copy.answers={};copy.strokes={};copy.annotations={};copy.mark={}
		copy.erase("procedure");copy.erase("math_ui");copy.erase("annotation_history")
	copy.project=school._public_project(source.project,(source.lesson or not source.mark.is_empty()) and int(source.owner)==multiplayer.get_unique_id())
	return copy
func _reader_current(generation: int,id: int) -> bool:
	return reading and screen.visible and generation==reader_generation and id==document_id and school.papers.has(id) and _editable(school.papers[id])
func _queue_answer(generation: int,id: int,key: String,value: String) -> void:
	if not _reader_current(generation,id):return
	pending[key]=value;save_timer=.35
func _reader_request(generation: int,id: int,page: int,action: Dictionary) -> void:
	if not reading or not screen.visible or generation!=reader_generation or id!=document_id or not school.papers.has(id):return
	var paper: Dictionary=school.papers[id]
	if not _editable(paper) and (action.op not in ["stroke","erase_stroke","erase_area","undo_stroke","redo_stroke","annotation","remove_annotation","undo_annotation","redo_annotation"] or not _can_mark(paper)):return
	var request: Dictionary=action.duplicate(true)
	request.id=id;request.page=page
	school.request(request)
func _build_reader() -> void:
	if is_instance_valid(calculator_widget):
		calculator_state=calculator_widget.display.text
		calc_saved={"degrees":calculator_widget.degrees,"answer":calculator_widget.answer,"memory":calculator_widget.memory,"result":calculator_widget.result.text,"caret":calculator_widget.display.caret_column,"selection_begin":calculator_widget.display.get_selection_from_column() if calculator_widget.display.has_selection() else -1,"selection_end":calculator_widget.display.get_selection_to_column() if calculator_widget.display.has_selection() else -1}
	if is_instance_valid(calculator_drawer) and calculator_drawer.has_method("snapshot_state"):drawer_saved=calculator_drawer.snapshot_state()
	_clear()
	if not school.papers.has(document_id):close();return
	var paper: Dictionary=_reader_copy(school.papers[document_id])
	var pencil_case_carried: bool = game.hotbar.has_item("pencil_case")
	var carried_calculator: String = game.hotbar.calculator_type()
	var calculator_carried := not carried_calculator.is_empty()
	if not pencil_case_carried:
		pencil_mode=false
		paper_tool="answer"
	page_index=clampi(page_index,0,_page_count(paper)-1)
	var generation := reader_generation
	var source_id := document_id
	var source_page := page_index
	rendered_revision=paper.revision
	rendered_mark=paper.mark.duplicate(true)
	var toolbar := HFlowContainer.new();toolbar.add_theme_constant_override("h_separation",8);column.add_child(toolbar)
	var document := _label(toolbar, str(paper.project.get("title", "Worksheet")), 18)
	document.autowrap_mode = TextServer.AUTOWRAP_OFF
	document.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	document.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	document.custom_minimum_size.x = 180
	save_status = _label(toolbar, "Autosaved" if _editable(paper) else "Notes only" if _can_mark(paper) else "Read only", 14)
	save_status.modulate = Color("a9c2cf")
	if not paper.get("mark",{}).is_empty():
		var badge := UI.badge("%.1f%%"%float(paper.mark.get("score",0)),"check")
		badge.size_flags_vertical=Control.SIZE_SHRINK_CENTER
		var badge_text := badge.get_child(1) as Label
		badge_text.autowrap_mode=TextServer.AUTOWRAP_OFF
		toolbar.add_child(badge)
	page_index=clampi(page_index,0,_page_count(paper)-1)
	var previous := _button(toolbar,"‹",func():turn_page(-1));previous.disabled=page_index==0
	page_label=_label(toolbar,"%d / %d"%[page_index+1,_page_count(paper)]);page_label.custom_minimum_size.x=65;page_label.size_flags_horizontal=Control.SIZE_SHRINK_CENTER
	var next := _button(toolbar,"›",func():turn_page(1));next.disabled=page_index>=_page_count(paper)-1
	if paper.get("notebook",false) and _editable(paper) and _page_count(paper)<100:
		_button(toolbar,"Add page",func():
			flush()
			school.request({"op":"notebook_page","id":document_id}))
	view_zoom=float(view_states.get(_reader_key(paper),{}).get("zoom",1.0))
	zoom_control = MenuButton.new()
	zoom_control.text = "%d%%" % roundi(view_zoom * 100.0)
	zoom_control.custom_minimum_size = Vector2(76, 40)
	zoom_control.tooltip_text = "Paper zoom · Home fits the page"
	toolbar.add_child(zoom_control)
	var zoom_menu := zoom_control.get_popup()
	zoom_menu.add_item("Fit page", 0)
	for percent in [75, 100, 125, 150, 200]:
		zoom_menu.add_item("%d%%" % percent, percent)
	zoom_menu.id_pressed.connect(func(percent: int):
		if percent == 0:
			workspace_view.fit()
		else:
			workspace_view.zoom_at(workspace_view.size * .5, (percent / 100.0) / maxf(workspace_view.target_zoom, .001))
		remember_view())
	if _can_mark(paper):_button(toolbar,"Undo",_undo_mark)
	if _can_mark(paper):_button(toolbar,"Redo",func():_undo_mark(true))
	_button(toolbar,"Close",close)
	var row := HBoxContainer.new();row.add_theme_constant_override("separation",0);row.size_flags_vertical=Control.SIZE_EXPAND_FILL;column.add_child(row)
	workspace_view=preload("res://scripts/ui/paper_workspace/workspace/viewport.gd").new()
	workspace_view.name="PaperViewport"
	workspace_view.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	workspace_view.size_flags_vertical=Control.SIZE_EXPAND_FILL
	workspace_view.clip_contents=true
	workspace_view.mouse_filter=Control.MOUSE_FILTER_PASS
	row.add_child(workspace_view)
	workspace_view.view_changed.connect(func(value: float,_offset: Vector2):
		view_zoom=value
		if is_instance_valid(zoom_control):zoom_control.text="%d%%" % roundi(value*100.0))
	page_view=(preload("res://scripts/math_course_paper.gd").new() if paper.project.get("course_id", "") in ["MTH147", "MTH255"] else preload("res://scripts/worksheet_page.gd").new());page_view.paper=paper.duplicate(true);page_view.page=page_index;page_view.writable=_editable(paper)
	page_view.answer_changed.connect(func(key,value):_queue_answer(generation,source_id,key,value))
	page_view.stroke_added.connect(func(stroke):_reader_request(generation,source_id,source_page,{"op":"stroke","points":stroke.points,"color":stroke.color,"width":stroke.width,"hardness":stroke.hardness,"opacity":stroke.opacity}))
	workspace_view.mount(page_view);ink=page_view.ink;ink.editable=_can_mark(paper);ink.pencil_color=pencil_color;ink.pencil_width=pencil_width;page_view.set_drawing(pencil_mode)
	annotation_layer=preload("res://scripts/paper_annotations.gd").new();annotation_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);annotation_layer.writable=_can_mark(paper);annotation_layer.items=paper.get("annotations",{}).get(str(page_index),[]).duplicate(true);page_view.add_child(annotation_layer);annotation_layer.ink_color=pencil_color;annotation_layer.set_tool(paper_tool)
	annotation_layer.changed.connect(func(item):_reader_request(generation,source_id,source_page,{"op":"annotation","item":item}))
	annotation_layer.removed.connect(func(id):_reader_request(generation,source_id,source_page,{"op":"remove_annotation","object":id}))
	annotation_layer.selected.connect(edit_annotation)
	annotation_layer.edit_requested.connect(func(_item):_case_text_action("edit"))
	if pencil_case_carried and _can_mark(paper) and ResourceLoader.exists("res://scripts/ui/paper_workspace/tools/case.gd"):
		var tool_anchor := Control.new()
		tool_anchor.mouse_filter = Control.MOUSE_FILTER_IGNORE
		surface.add_child(tool_anchor)
		tool_anchor.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		tool_anchor.offset_left = 0
		tool_anchor.offset_top = 64
		tool_anchor.offset_bottom = 0
		tool_case=load("res://scripts/ui/paper_workspace/tools/case.gd").new();tool_anchor.add_child(tool_case)
		tool_case.configure("text" if paper_tool=="equation" else paper_tool,{"color":pencil_color.to_html(false),"width":pencil_width,"equation":paper_tool=="equation"})
		tool_case.tool_selected.connect(_case_tool_selected)
		tool_case.properties_changed.connect(_case_properties_changed)
		tool_case.text_action.connect(_case_text_action)
		tool_case.set_supported_text_actions(["delete"])
		_case_properties_changed(tool_case.properties)
		if tool_case.tool!="answer":page_view.mouse_default_cursor_shape=Control.CURSOR_CROSS
	ink.eraser=paper_tool=="eraser";page_view.set_drawing(paper_tool in ["pencil","eraser"])
	ink.area_erased.connect(func(point,radius):_reader_request(generation,source_id,source_page,{"op":"erase_area","point":point,"radius":radius}))
	# Eraser targets annotations first; empty clicks reach the ink beneath.
	annotation_layer.erase_ink.connect(func(point):ink.erase_at(point))
	var side_scroll := ScrollContainer.new();side_scroll.custom_minimum_size.x=300;side_scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;row.add_child(side_scroll)
	tools_scroll=side_scroll
	if is_instance_valid(tool_case) or not pencil_case_carried:side_scroll.hide();side_scroll.custom_minimum_size.x=0
	var side := VBoxContainer.new();side.custom_minimum_size.x=280;side.add_theme_constant_override("separation",6);side_scroll.add_child(side)
	_label(side,"PENCIL CASE",15)
	var draw := CheckButton.new();draw.text="✎  Pencil enabled";draw.button_pressed=pencil_mode;draw.disabled=not _editable(paper);side.add_child(draw)
	draw.toggled.connect(func(value):flush();pencil_mode=value;paper_tool="pencil" if value else "answer";_build_reader())
	draw.tooltip_text="Enable to draw on the paper. Disable to type in answer fields."
	var tool_row := HBoxContainer.new();side.add_child(tool_row)
	for entry in [["text","Text"],["eraser","Eraser"]]:
		var tool_button := _button(tool_row,entry[1],func():flush();paper_tool=entry[0] if paper_tool!=entry[0] else "answer";pencil_mode=false;_build_reader());tool_button.disabled=not _editable(paper);tool_button.toggle_mode=true;tool_button.button_pressed=paper_tool==entry[0]
	annotation_inspector=VBoxContainer.new();side.add_child(annotation_inspector)
	if paper_tool in ["text","equation"]:_label(annotation_inspector,"Click the paper to add text. Drag existing text to move it.",13)
	if paper_tool=="eraser":_label(annotation_inspector,"Erase pencil marks. Editable text stays intact.",13)
	var colors := HBoxContainer.new();side.add_child(colors);colors.visible=pencil_mode
	for color in ["263743","235d9b","b24c45","3a7e59","8257a4"]:
		var swatch := Button.new();swatch.custom_minimum_size=Vector2(38,26);var style := StyleBoxFlat.new();style.bg_color=Color(color);style.set_corner_radius_all(7);swatch.add_theme_stylebox_override("normal",style);swatch.pressed.connect(func():pencil_color=Color(color);ink.pencil_color=pencil_color);colors.add_child(swatch)
	var custom := ColorPickerButton.new();custom.color=pencil_color;custom.edit_alpha=false;custom.custom_minimum_size=Vector2(38,26);custom.tooltip_text="Choose any pencil color";colors.add_child(custom)
	custom.color_changed.connect(func(value):pencil_color=value;ink.pencil_color=value)
	var width := HSlider.new();width.min_value=1;width.max_value=32;width.step=1;width.value=pencil_width;width.tooltip_text="Pencil thickness";width.value_changed.connect(func(value):pencil_width=value;ink.pencil_width=value);side.add_child(width);width.visible=pencil_mode
	var actions := HBoxContainer.new();side.add_child(actions)
	var undo := _button(actions,"Undo stroke",func():school.request({"op":"undo_stroke","id":document_id,"page":page_index});if not ink.strokes.is_empty():ink.strokes.pop_back();ink.queue_redraw())
	undo.custom_minimum_size.y=28;undo.disabled=not _editable(paper)
	var erase := _button(actions,"Clear page",func():school.request({"op":"erase","id":document_id,"page":page_index});ink.strokes=[];ink.queue_redraw());erase.custom_minimum_size.y=28;erase.disabled=not _editable(paper)
	if paper.lesson and not paper.get("guide",false) and paper.owner==multiplayer.get_unique_id():
		_button(toolbar,"Check practice" if paper.mark.is_empty() else "Try again",func():
			flush()
			var checking: bool=paper.mark.is_empty()
			school.request({"op":"lesson_check" if checking else "lesson_retry","id":document_id})
			page_index=school.page_count(paper)-1 if checking else int(paper.project.get("lesson_stages",[]).size()) if str(paper.project.get("course_id","")).begins_with("MTH") else school.page_count(paper)-2
			_build_reader())
	calculator_widget=preload("res://scripts/scientific_calculator.gd").new()
	calculator_widget.model=carried_calculator if calculator_carried else "calculator"
	var calculator_allowed := calculator_carried and (not str(paper.project.get("course_id","")).begins_with("MTH") or bool(paper.get("math_policy",{}).get("calculator_allowed",false)))
	if calculator_allowed and ResourceLoader.exists("res://scripts/ui/paper_workspace/calculator/drawer.gd"):
		calculator_drawer=load("res://scripts/ui/paper_workspace/calculator/drawer.gd").new();surface.add_child(calculator_drawer);calculator_drawer.configure(calculator_widget)
		if not drawer_saved.is_empty():calculator_drawer.restore_state(drawer_saved)
	else:side.add_child(calculator_widget)
	calculator=calculator_widget.display;calculator.text=calculator_state
	calculator_widget.visible=calculator_allowed
	if not calculator_widget.visible:_label(side,"Calculator disabled for this assessment." if calculator_carried else "No calculator in your hotbar.",14)
	if not calc_saved.is_empty():
		calculator_widget.degrees=calc_saved.degrees;calculator_widget.answer=calc_saved.answer;calculator_widget.memory=calc_saved.memory;calculator_widget.result.text=calc_saved.result
		if is_instance_valid(calculator_widget.mode):
			calculator_widget.mode.text="DEG" if calc_saved.degrees else "RAD"
			calculator_widget.memory_label.text=calculator_widget.mode.text+("   M" if calc_saved.memory!=0 else "")
		calculator_widget.display.caret_column=clampi(int(calc_saved.get("caret",calculator_state.length())),0,calculator_state.length())
		if int(calc_saved.get("selection_begin",-1))>=0:calculator_widget.display.select(int(calc_saved.selection_begin),int(calc_saved.selection_end))
	if not paper.lesson and _editable(paper):
		_button(toolbar,"Submit test",func():flush();school.request({"op":"submit","id":document_id});close())
		if paper.project.get("kind","")=="lab":
			_button(side,"Record current instrument reading",func():flush();school.request({"op":"measure","id":document_id}))
	view_document=document_id;view_page=page_index;reader_view_key=_reader_key(paper)
	restore_view.call_deferred(view_document,view_page,reader_generation)
func remember_view() -> void:
	if restoring_view or reader_view_key=="" or view_document<0 or not is_instance_valid(workspace_view):return
	var state: Dictionary=view_states.get(reader_view_key,{"pages":{}})
	state.page=view_page;state.zoom=view_zoom
	state.pages[view_page]=workspace_view.offset
	state.tools=tools_scroll.scroll_vertical if is_instance_valid(tools_scroll) else 0
	view_states[reader_view_key]=state
	if view_states.size()>128:view_states.erase(view_states.keys()[0])
	var cfg := ConfigFile.new();cfg.set_value("reader","documents",view_states);cfg.save("user://paper_reader_views.cfg")
func apply_zoom() -> void:
	if is_instance_valid(workspace_view):workspace_view.restore(view_zoom,workspace_view.offset)
func _clamp_pan() -> void:
	if is_instance_valid(workspace_view):workspace_view.move_by(Vector2.ZERO)
func _set_zoom(value: float,anchor: Vector2) -> void:
	if is_instance_valid(workspace_view):workspace_view.zoom_at(anchor,value/maxf(workspace_view.target_zoom,0.001))
func restore_view(id: int,page: int,generation: int) -> void:
	if generation!=reader_generation or not reading or not screen.visible:return
	restoring_view=true
	await get_tree().process_frame
	await get_tree().process_frame
	if generation==reader_generation and reading and screen.visible and id==view_document and page==view_page and is_instance_valid(workspace_view):
		var state: Dictionary=view_states.get(reader_view_key,{})
		var position: Vector2=state.get("pages",{}).get(page,workspace_view.offset)
		if state.has("zoom"):workspace_view.restore(float(state.zoom),position)
		else:workspace_view.fit()
		tools_scroll.scroll_vertical=int(state.get("tools",0))
	if generation==reader_generation:restoring_view=false
func turn_page(direction: int) -> void:
	if not reading or not school.papers.has(document_id):return
	var target := clampi(page_index+direction,0,_page_count(school.papers[document_id])-1)
	if target==page_index:return
	remember_view()
	flush()
	page_index=target
	if school.papers[document_id].owner==multiplayer.get_unique_id():school.request({"op":"page","id":document_id,"page":page_index})
	_build_reader()
func _paper_input(event: InputEvent,generation: int,id: int) -> void:
	_workspace_input(event,generation,id)
func _input(event: InputEvent) -> void:
	if not reading or not screen.visible or not is_instance_valid(workspace_view):return
	if event is InputEventKey and event.pressed and not event.echo:
		var focused := get_viewport().gui_get_focus_owner()
		if focused is LineEdit or focused is TextEdit:return
		if event.keycode == KEY_HOME:
			workspace_view.fit()
			remember_view()
			get_viewport().set_input_as_handled()
		elif event.ctrl_pressed and event.keycode in [KEY_Z, KEY_Y]:
			_undo_mark(event.keycode == KEY_Y or event.shift_pressed)
			get_viewport().set_input_as_handled()
		return
	if not (event is InputEventMouseButton or event is InputEventMouseMotion):return
	var hovered := get_viewport().gui_get_hovered_control()
	if is_instance_valid(annotation_layer) and is_instance_valid(annotation_layer.inline_editor):
		if hovered==annotation_layer.inline_editor:return
		if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT and event.pressed:
			annotation_layer.finish_inline_edit()
	if is_instance_valid(hovered) and (is_instance_valid(calculator_drawer) and calculator_drawer.is_ancestor_of(hovered) or is_instance_valid(tool_case) and tool_case.is_ancestor_of(hovered)):return
	var pointer := workspace_view.get_local_mouse_position()
	if not panning and not Rect2(Vector2.ZERO,workspace_view.size).has_point(pointer):return
	_workspace_input(event,reader_generation,document_id)

func _undo_mark(redo := false) -> void:
	if not game.hotbar.has_item("pencil_case"):return
	var paper: Dictionary = school.papers.get(document_id, {})
	if paper.is_empty() or not _can_mark(paper):return
	var stroke := paper_tool in ["pencil", "eraser"]
	awaiting_annotation_undo = true
	var operation := ("redo_" if redo else "undo_") + ("stroke" if stroke else "annotation")
	_reader_request(reader_generation, document_id, page_index, {"op":operation})
func _workspace_input(event: InputEvent,generation: int,id: int) -> void:
	if generation!=reader_generation or id!=document_id:return
	if not is_instance_valid(workspace_view):return
	var pointer := workspace_view.get_local_mouse_position()
	if event is InputEventMouseButton:
		if event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN] and event.pressed:
			if not Rect2(workspace_view.offset,page_view.size*workspace_view.zoom).has_point(pointer):return
			workspace_view.zoom_at(pointer,1.1 if event.button_index==MOUSE_BUTTON_WHEEL_UP else 1.0/1.1)
			get_viewport().set_input_as_handled()
		elif event.button_index==MOUSE_BUTTON_MIDDLE:
			panning=event.pressed;pan_origin=pointer;get_viewport().set_input_as_handled()
		elif event.button_index==MOUSE_BUTTON_LEFT and event.pressed and (Input.is_key_pressed(KEY_SPACE) or paper_tool=="answer" and not _paper_control_at(pointer)):
			panning=true;pan_origin=pointer;get_viewport().set_input_as_handled()
		elif event.button_index==MOUSE_BUTTON_LEFT and not event.pressed:panning=false
	elif event is InputEventMouseMotion and panning:
		var move: Vector2=pointer-pan_origin;pan_origin=pointer
		workspace_view.move_by(move)
		get_viewport().set_input_as_handled()
func _paper_control_at(position: Vector2) -> bool:
	var control := get_viewport().gui_get_hovered_control()
	if control is LineEdit or control is TextEdit or control is OptionButton or control is Button:return true
	return not Rect2(workspace_view.offset,page_view.size*workspace_view.zoom).has_point(position)
func _case_tool_selected(value: String) -> void:
	flush();paper_tool="equation" if value=="text" and bool(tool_case.properties.get("equation",false)) else value
	pencil_mode=paper_tool=="pencil"
	if is_instance_valid(ink):ink.eraser=paper_tool=="eraser";page_view.set_drawing(pencil_mode or paper_tool=="eraser")
	if is_instance_valid(tool_case):_case_properties_changed(tool_case.properties)
	if is_instance_valid(annotation_layer):annotation_layer.set_tool(paper_tool)
	if is_instance_valid(page_view):page_view.mouse_default_cursor_shape=Control.CURSOR_ARROW
func _case_properties_changed(properties: Dictionary) -> void:
	if str(properties.get("_scope",""))=="selection":
		for key in properties:
			if key=="_scope":continue
			annotation_layer.update_selected("kind" if key=="equation" else key,("equation" if bool(properties[key]) else "text") if key=="equation" else properties[key])
		return
	pencil_color=Color(str(properties.get("color",pencil_color.to_html(false))))
	if paper_tool!="eraser":pencil_width=clampf(float(properties.get("width",pencil_width)),1.0,32.0)
	if is_instance_valid(ink):
		ink.pencil_color=pencil_color;ink.pencil_width=pencil_width
		ink.pencil_hardness=clampf(float(properties.get("hardness",0.8)),0.0,1.0)
		ink.pencil_opacity=clampf(float(properties.get("opacity",1.0)),0.05,1.0)
		ink.eraser_radius=clampf(float(properties.get("width",12.0)),4.0,64.0) if paper_tool=="eraser" else ink.eraser_radius
	if is_instance_valid(annotation_layer):
		annotation_layer.ink_color=pencil_color
		annotation_layer.text_defaults={"font":str(properties.get("font","Sans")),"font_size":int(properties.get("font_size",24)),"angle":float(properties.get("angle",0.0)),"equation":bool(properties.get("equation",false)),"opacity":float(properties.get("opacity",1.0)),"bold":bool(properties.get("bold",false)),"italic":bool(properties.get("italic",false)),"align":str(properties.get("align","left")),"box_width":float(properties.get("box_width",280.0))}
	if paper_tool in ["text","equation"]:
		paper_tool="equation" if bool(properties.get("equation",false)) else "text"
		annotation_layer.set_tool(paper_tool)
func _case_text_action(action: String) -> void:
	if not is_instance_valid(annotation_layer) or annotation_layer.selection.is_empty():return
	if action=="bake":
		annotation_layer.update_selected("baked",true)
		annotation_layer.selection=""
		tool_case.set_selection({})
		annotation_layer.queue_redraw()
	elif action=="duplicate":
		var source: Dictionary=annotation_layer.find_item(annotation_layer.selection)
		if source.is_empty() or bool(source.get("baked",false)):return
		var copy: Dictionary=source.duplicate(true)
		copy.id=str(Time.get_ticks_usec())
		copy.position=(Vector2(copy.position)+Vector2(0.025,0.018)).clamp(Vector2.ZERO,Vector2.ONE)
		annotation_layer.items.append(copy)
		annotation_layer.selection=copy.id
		annotation_layer.changed.emit(copy.duplicate(true))
		annotation_layer.selected.emit(copy)
		annotation_layer.queue_redraw()
	elif action=="delete":
		var selected_id: String=annotation_layer.selection
		annotation_layer.items=annotation_layer.items.filter(func(item):return item.id!=selected_id)
		annotation_layer.selection=""
		tool_case.set_selection({})
		annotation_layer.removed.emit(selected_id)
		annotation_layer.queue_redraw()
	elif action=="edit":
		var item: Dictionary=annotation_layer.find_item(annotation_layer.selection)
		if item.is_empty():return
		if str(item.get("kind","text"))!="equation":
			annotation_layer.edit_inline(item)
			return
		var edit_generation := reader_generation;var edit_document := document_id;var edit_page := page_index;var edit_selection := str(item.id)
		var editor := AcceptDialog.new();editor.title="Edit equation source";editor.ok_button_text="Done";screen.add_child(editor)
		var input := TextEdit.new();input.text=str(item.get("text",""));input.custom_minimum_size=Vector2(420,100);editor.add_child(input)
		var hint := Label.new();hint.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;editor.add_child(hint)
		var annotation_script=preload("res://scripts/paper_annotations.gd")
		var preview: Control=null
		preview=annotation_script.new();preview.custom_minimum_size=Vector2(430,120);preview.size=Vector2(430,120);preview.mouse_filter=Control.MOUSE_FILTER_IGNORE;editor.add_child(preview)
		var preview_item: Dictionary=item.duplicate(true);preview_item.position=Vector2(0.03,0.12);preview_item.angle=0.0;preview.items=[preview_item]
		var refresh_hint := func(value: String):
			var issue: String=annotation_script.equation_error(value)
			hint.text=issue if not issue.is_empty() else "Equation layout: / fractions · ^ superscripts · _ subscripts · ( ) grouping. Preview updates on the paper."
			if is_instance_valid(preview):preview.items[0].text=value;preview.queue_redraw()
		refresh_hint.call(input.text)
		input.text_changed.connect(func():
			var value := input.text.left(256)
			refresh_hint.call(value)
			if edit_generation==reader_generation and edit_document==document_id and edit_page==page_index and is_instance_valid(annotation_layer) and annotation_layer.selection==edit_selection:annotation_layer.update_selected("text",value)
		)
		editor.confirmed.connect(editor.queue_free);editor.canceled.connect(editor.queue_free)
		editor.popup_centered(Vector2i(480,240));input.grab_focus();input.select_all()
func cancel_inline_text() -> bool:
	if not is_instance_valid(annotation_layer) or not is_instance_valid(annotation_layer.inline_editor):return false
	annotation_layer.finish_inline_edit(false)
	return true

func flush(finish_text := true) -> void:
	if flushing:return
	flushing=true
	var source_id := document_id
	if finish_text and reading and is_instance_valid(annotation_layer):annotation_layer.finish_inline_edit()
	if reading and is_instance_valid(ink):ink.finish()
	var answers: Dictionary=pending.duplicate(true)
	pending.clear()
	for key in answers:school.request({"op":"answer","id":source_id,"key":key,"value":answers[key]})
	flushing=false
func _updated() -> void:
	if flushing:
		_updated.call_deferred()
		return
	if not screen.visible or not reading:return
	if not school.papers.has(document_id):close();return
	var paper: Dictionary=school.papers[document_id]
	# Avoid rebuilding focused answer fields on network echoes.
	if paper.get("notebook",false) and is_instance_valid(page_label) and int(page_label.text.get_slice("/",1).strip_edges())!=_page_count(paper):
		page_index=int(paper.page)
		_build_reader()
		return
	if (awaiting_annotation_undo or paper.mark!=rendered_mark or paper.owner!=multiplayer.get_unique_id()) and rendered_revision!=paper.revision:
		awaiting_annotation_undo=false
		_build_reader()
func _process(delta: float) -> void:
	if reading and screen.visible and is_instance_valid(workspace_view):view_zoom=workspace_view.zoom
	if reading and screen.visible and is_instance_valid(save_status) and school.papers.has(document_id):
		save_status.text = ("Autosaved" if pending.is_empty() else "Saving…") if _editable(school.papers[document_id]) else "Notes only" if _can_mark(school.papers[document_id]) else "Read only"
	var cursor_tool := "answer"
	if reading and screen.visible and is_instance_valid(tool_case) and is_instance_valid(page_view) and paper_tool in ["pencil","eraser","text","equation"]:
		var hovered := get_viewport().gui_get_hovered_control()
		if is_instance_valid(hovered) and (hovered==page_view or page_view.is_ancestor_of(hovered)) and not (hovered is LineEdit or hovered is TextEdit or hovered is Button or hovered is OptionButton):
			cursor_tool="text" if paper_tool=="equation" else paper_tool
	if cursor_tool!=active_cursor_tool:
		var hotspot := Vector2(4,28) if cursor_tool=="pencil" else Vector2.ZERO
		Input.set_custom_mouse_cursor(tool_case.cursor_texture(cursor_tool) if cursor_tool!="answer" and is_instance_valid(tool_case) else null,Input.CURSOR_ARROW,hotspot)
		active_cursor_tool=cursor_tool
	if reading and screen.visible and is_instance_valid(calculator_drawer):
		var occupied := Rect2()
		if is_instance_valid(tool_case) and tool_case.revealed:
			var case_body := tool_case.get_child(0) as Control
			if is_instance_valid(case_body):
				var case_transform := calculator_drawer.get_global_transform().affine_inverse() * case_body.get_global_transform()
				occupied = case_transform * Rect2(Vector2.ZERO, Vector2(case_body.size.x, 332))
		calculator_drawer.set_occlusion_rect(occupied)
	if not pending.is_empty():
		save_timer-=delta
		if save_timer<=0:flush(false)
static func calculate_expression(value: String) -> String:
	if value.length()>180:return "Expression too long"
	var safe := value.to_lower().replace("pi","3.141592653589793").replace("^","**")
	var words := RegEx.new()
	words.compile("[a-z_][a-z_0-9]*")
	for word in words.search_all(safe):
		if word.get_string() not in ["sqrt","sin","cos","tan","asin","acos","atan","abs","pow","log","exp"]:return "Use arithmetic and the listed math functions."
	var characters := RegEx.new()
	characters.compile("^[0-9a-z+*/()., _-]+$")
	if not characters.search(safe):return "Invalid expression"
	var expression := Expression.new()
	if expression.parse(safe)!=OK:return "Check the expression"
	var result=expression.execute([],null,false,true)
	if expression.has_execute_failed() or not (result is float or result is int) or not is_finite(float(result)):return "Undefined result"
	return "= "+str(snappedf(float(result),.000000001))

func daq_page() -> void:
	flush()
	var station: int=game._active_station()
	reading=false
	_clear()
	game.release_mouse()
	screen.show()
	_label(column,"DATA ACQUISITION • RMS / PHASORS",28)
	_label(column,"E1–E4 measure across nodes. I1–I4 go in series. AI and DO use the DAQ signal common. DI uses its paired return.")
	var outputs := HBoxContainer.new()
	column.add_child(outputs)
	var settings: Dictionary = game.station_snapshots[station].get("daq_settings", {})
	for i in 2:
		var analog_channel := "AO%d"%i
		var digital_channel := "DO%d"%i
		var voltage := SpinBox.new()
		voltage.min_value = -10.
		voltage.max_value = 10.
		voltage.step = .1
		voltage.suffix = "V"
		voltage.value = settings.get(analog_channel, 0.)
		outputs.add_child(voltage)
		_button(outputs, "Set " + analog_channel, func():
			game.session.request({"op":"daq_output","station":station,"channel":analog_channel,"value":voltage.value}))
		_button(outputs, "Toggle " + digital_channel, func():
			var latest: Dictionary = game.station_snapshots[station].get("daq_settings", {})
			game.session.request({"op":"daq_output","station":station,"channel":digital_channel,"value":not latest.get(digital_channel, false)}))
	var readout := _label(column,"",23)
	var timer := Timer.new()
	timer.wait_time=.25
	column.add_child(timer)
	timer.timeout.connect(func():
		var values: Dictionary=game.station_snapshots[station].get("readings",{})
		var message := ""
		for i in range(4):
			var volts: Vector2=values.get("daq_v",[Vector2.ZERO,Vector2.ZERO,Vector2.ZERO,Vector2.ZERO])[i]
			var amps: Vector2=values.get("daq_i",[Vector2.ZERO,Vector2.ZERO,Vector2.ZERO,Vector2.ZERO])[i]
			message+="E%d   %.3f V  ∠ %.2f°       I%d   %.4f A  ∠ %.2f°\n"%[i+1,volts.length(),rad_to_deg(volts.angle()),i+1,amps.length(),rad_to_deg(amps.angle())]
			var dc_volts: Vector2 = values.daq_dc_v[i] if values.has("daq_dc_v") else Vector2.ZERO
			var dc_amps: Vector2 = values.daq_dc_i[i] if values.has("daq_dc_i") else Vector2.ZERO
			if absf(dc_volts.x) > .001 or absf(dc_amps.x) > .0001:
				message += "       DC  %.3f V / %.4f A\n" % [dc_volts.x, dc_amps.x]
		for i in values.get("daq_analog", []).size():
			var sample: Dictionary = values.daq_analog[i]
			message += "AI%d   %.3f V AC   %+.3f V DC%s" % [i, sample.ac_rms, sample.dc, "\n" if i % 2 else "     "]
		for i in values.get("daq_digital", []).size():
			message += "DI%d %s    " % [i, "HIGH" if values.daq_digital[i] else "LOW"]
		var latest: Dictionary = game.station_snapshots[station].get("daq_settings", {})
		message += "\nAO0 %.1f V  AO1 %.1f V     DO0 %s  DO1 %s" % [latest.get("AO0",0.),latest.get("AO1",0.),"HIGH" if latest.get("DO0",false) else "LOW","HIGH" if latest.get("DO1",false) else "LOW"]
		readout.text=message
	)
	timer.start()
	_button(column,"Return to laboratory",close)

func edit_annotation(item: Dictionary) -> void:
	if is_instance_valid(tool_case):tool_case.set_selection(item);return
	for child in annotation_inspector.get_children():annotation_inspector.remove_child(child);child.queue_free()
	var input := LineEdit.new();input.text=item.text;input.max_length=256;annotation_inspector.add_child(input)
	input.text_changed.connect(func(value):annotation_layer.update_selected("text",value))
	var options := HBoxContainer.new();annotation_inspector.add_child(options)
	var font := OptionButton.new()
	for name in ["Sans","Serif","Mono"]:font.add_item(name)
	font.select(["Sans","Serif","Mono"].find(item.font));options.add_child(font);font.item_selected.connect(func(i):annotation_layer.update_selected("font",font.get_item_text(i)))
	var color := ColorPickerButton.new();color.color=Color(item.color);color.edit_alpha=false;options.add_child(color);color.color_changed.connect(func(value):annotation_layer.update_selected("color",value.to_html(false)))
	for spec in [["Size","font_size",10,72,item.font_size],["Rotation","angle",-180,180,rad_to_deg(float(item.angle))]]:
		_label(annotation_inspector,spec[0],13);var spin := SpinBox.new();spin.min_value=spec[2];spin.max_value=spec[3];spin.value=spec[4];annotation_inspector.add_child(spin);spin.value_changed.connect(func(value):annotation_layer.update_selected(spec[1],deg_to_rad(value) if spec[1]=="angle" else value))
	if item.kind=="equation":
		_label(annotation_inspector,"a/b → fraction · x^2 → exponent. Use ( ) to group terms.",13)
		var symbols := GridContainer.new();symbols.columns=6;annotation_inspector.add_child(symbols)
		for symbol in ["/","^","π","θ","°","∠","Ω","√","±","×","÷","≈","α","β","φ","ω","Δ","Σ","∞","≤","≥","≠","μ","λ"]:
			var b := _button(symbols,symbol,func():input.insert_text_at_caret(symbol);annotation_layer.update_selected("text",input.text));b.custom_minimum_size=Vector2(32,28)
	var actions := HBoxContainer.new();annotation_inspector.add_child(actions)
	_button(actions,"Bake into drawing",func():annotation_layer.update_selected("baked",true);annotation_layer.selection="";annotation_layer.queue_redraw();for child in annotation_inspector.get_children():child.queue_free())
	_button(actions,"Delete",func():annotation_layer.items=annotation_layer.items.filter(func(a):return a.id!=item.id);school.request({"op":"remove_annotation","id":document_id,"page":page_index,"object":item.id});annotation_layer.queue_redraw())
	input.grab_focus();input.select_all()

func confirm_abandon() -> void:
	var dialog := ConfirmationDialog.new()
	dialog.title="Abandon active assessment"
	dialog.dialog_text="Your active marked assessment will receive 0%. Practice sheets never receive an abandonment penalty."
	dialog.confirmed.connect(func():school.request({"op":"abandon","confirmed":true});dialog.queue_free();close())
	dialog.canceled.connect(dialog.queue_free)
	add_child(dialog);dialog.popup_centered(Vector2i(560,180))

func activity_menu(expected_epoch: int) -> void:
	if not multiplayer.is_server() or not school.has_method("can_choose_next_activity") or not school.can_choose_next_activity() or int(school.get("activity_epoch"))!=expected_epoch:return
	flush();reading=false;_clear();game.release_mouse();screen.show()
	_label(column,"CAMPUS ACTIVITY",30)
	_label(column,"Class complete. Choose the next activity; everyone stays connected." if school.phase=="complete" else "The host chooses a shared campus activity.")
	if school.formal_active():
		_label(column,"Finish the current class before changing activities.")
		_button(column,"Return",close)
		return
	var mode_select := OptionButton.new()
	for value in ["Freeplay","Open Lab","Course"]:mode_select.add_item(value)
	column.add_child(mode_select)
	var course_select := OptionButton.new()
	for value in school.course_ids():course_select.add_item(value)
	column.add_child(course_select)
	var kind_select := OptionButton.new()
	for value in ["lecture","lab"]:kind_select.add_item(value)
	column.add_child(kind_select)
	var lecture_room := OptionButton.new()
	lecture_room.add_item("M201 · Lecture Classroom")
	lecture_room.add_item("M202 · Lecture Classroom")
	column.add_child(lecture_room)
	var refresh_room := func():
		lecture_room.visible=mode_select.selected==2 and kind_select.selected==0
	mode_select.item_selected.connect(func(_i):refresh_room.call())
	kind_select.item_selected.connect(func(_i):refresh_room.call())
	refresh_room.call()
	var week_select := OptionButton.new();column.add_child(week_select)
	var refresh_weeks := func():
		week_select.clear()
		for entry in school.course_bridge.weeks(course_select.get_item_text(course_select.selected),kind_select.get_item_text(kind_select.selected)):
			week_select.add_item("Week %d · %s"%[int(entry.get("week",week_select.item_count+1)),str(entry.get("title",""))])
	course_select.item_selected.connect(func(_i):refresh_weeks.call())
	kind_select.item_selected.connect(func(_i):refresh_weeks.call())
	refresh_weeks.call()
	var level := OptionButton.new()
	for value in ["Beginner","Easy","Normal","Hard","Expert"]:level.add_item(value)
	level.select(2);column.add_child(level)
	var deadline := SpinBox.new();deadline.min_value=1;deadline.max_value=120;deadline.value=30;deadline.suffix=" assessment minutes";column.add_child(deadline)
	var result_label := _label(column,"")
	_button(column,"Start activity",func():
		if not school.can_choose_next_activity() or int(school.get("activity_epoch"))!=expected_epoch:
			result_label.text="This activity menu has expired."
			return
		var result: Dictionary=school.start_activity({"mode":mode_select.get_item_text(mode_select.selected),"course_id":course_select.get_item_text(course_select.selected),"kind":kind_select.get_item_text(kind_select.selected),"week":week_select.selected+1,"difficulty":level.selected,"assessment_seconds":deadline.value*60,"lecture_room":["elm253_lecture","ety155_lecture"][lecture_room.selected] if lecture_room.visible else ""})
		if result.ok:close()
		else:result_label.text=str(result.error))
	_button(column,"Recover previous class on this host",func():
		var result: Dictionary=school.recover_activity()
		if result.ok:close()
		else:result_label.text=str(result.error))
	_button(column,"Return",close)

func _reader_key(paper: Dictionary) -> String:
	var profile := str(game.characters.selected) if is_instance_valid(game) and is_instance_valid(game.characters) else "__default__"
	if paper.get("notebook",false):return (profile+":notebook").sha256_text()
	var assignment: Dictionary=paper.get("project",{})
	var questions: Array=[]
	for question in assignment.get("questions",[]):questions.append(str(question.get("id",question.get("text",question.get("prompt","")))))
	return JSON.stringify([profile,paper.get("assessment_id",""),assignment.get("course_id",""),assignment.get("title",""),assignment.get("data",""),questions,paper.get("lesson",false)]).sha256_text()

func _load_reader_views() -> void:
	if not FileAccess.file_exists("user://paper_reader_views.cfg"):return
	var file := FileAccess.open("user://paper_reader_views.cfg",FileAccess.READ)
	if file==null:return
	var length := file.get_length();file.close()
	if length>524288:return
	var cfg := ConfigFile.new()
	if cfg.load("user://paper_reader_views.cfg")!=OK:return
	var stored: Variant=cfg.get_value("reader","documents",{})
	if not stored is Dictionary or stored.size()>128:return
	for key in stored:
		if not key is String or key.length()!=64:continue
		var state: Variant=stored[key]
		if not state is Dictionary or not state.get("pages") is Dictionary or state.pages.size()>64:continue
		var zoom: Variant=state.get("zoom",1.)
		if not zoom is float and not zoom is int:continue
		if not is_finite(float(zoom)):continue
		var pages := {}
		for index in state.pages:
			var point: Variant=state.pages[index]
			if point is Vector2 and point.is_finite() and int(index)>=0 and int(index)<64:pages[int(index)]=point.clamp(Vector2.ZERO,Vector2.ONE*1000000.)
		view_states[key]={"page":clampi(int(state.get("page",0)),0,63),"zoom":clampf(float(zoom),.5,1.5),"pages":pages,"tools":clampi(int(state.get("tools",0)),0,1000000)}

func safety_demo_menu() -> void:
	if not multiplayer.is_server() or school.formal_active():return
	flush();reading=false;_clear();game.release_mouse();screen.show()
	_label(column,"EARTHING DEMONSTRATION",28)
	_label(column,"A simplified teaching circuit. It does not certify equipment or say whether a real circuit is safe.")
	_label(column,"1. Turn the selected bench OFF and disconnect its external bench leads.
2. Connect a cable from the supply's green EARTH socket to the IGBT panel's green earth socket.
3. Apply the model below. With power OFF, inspect the calculated PE resistance. Turn power ON using the normal switch to observe the fault response.")
	var controls:=HBoxContainer.new();column.add_child(controls)
	var station:=OptionButton.new();controls.add_child(station)
	for index in game.session.labs.size():station.add_item("AC bench %d"%(index+1))
	var topology:=OptionButton.new();controls.add_child(topology)
	topology.add_item("Isolated source · no neutral/PE bond")
	topology.add_item("Explicit teaching neutral/PE bond · 0.1 Ω")
	var fault:=CheckButton.new();fault.text="Include line-A insulation fault · 0.5 Ω";column.add_child(fault)
	_label(column,"Model assumptions: patch lead 0.2 Ω; chassis bond 0.05 Ω. These values are assumed for the exercise, not measured trainer specifications.")
	var status:=_label(column,"Model starts only when you apply it. Existing circuits have no automatic earth bond.")
	var refresh:=func():
		var lab=game.session.labs[station.selected]
		lab.recalculate()
		var evidence:Dictionary=lab.readings.get("safety",{})
		if not evidence.get("enabled",false):status.text="Demonstration disabled for this bench.";return
		if evidence.get("snapshot_kind","")=="pre_trip":status.text="Source tripped and power is OFF. The retained fault values describe the moment before the trip.";return
		if lab.powered:status.text="Power is ON. Continuity testing is unavailable. Read the live instruments; no trip does not mean a safe chassis.";return
		var continuity:Dictionary=evidence.get("continuity",{})
		if not continuity.get("ok",false):status.text=str(continuity.get("error","Continuity unavailable."));return
		var rows:Array=continuity.get("chassis",[])
		if rows.is_empty():status.text="No declared chassis in this model.";return
		status.text="PE path is open: check both cable ends." if rows[0].resistance_ohms==null else "Calculated PE path: %.3f Ω. This is a model result, not safety certification."%float(rows[0].resistance_ohms)
	_button(column,"Apply teaching model",func():
		var profile:Dictionary=preload("res://scripts/electrical_safety/profile.gd").example("isolated" if topology.selected==0 else "explicit_bond")
		if fault.button_pressed:profile.faults=[{"id":"line_chassis","a":"P_A","b":"__pe/IGBT","ohms":.5,"enabled":true}]
		var result:Dictionary=game.session.labs[station.selected].configure_protective_earth(profile)
		if not result.ok:status.text=str(result.error)
		else:game.session.broadcast();refresh.call()
	)
	_button(column,"Refresh model status",refresh)
	_button(column,"Disable teaching model",func():
		var result:Dictionary=game.session.labs[station.selected].configure_protective_earth({})
		if not result.ok:status.text=str(result.error)
		else:game.session.broadcast();refresh.call()
	)
	_button(column,"Back to instructor",teacher)
