extends Control
const UI = preload("res://scripts/ui/design_system/widgets.gd")
signal closed
signal activity_started
var adapter: Object
var content: VBoxContainer
var tabs: TabContainer
var notice: Label
var course_id := ""
var kind := "lecture"
var week := 1
var difficulty := 2
var mode := "Course"
var math_calculator_allowed := false
var math_formula_allowed := false
var week_status: Label
func build(source: Object) -> void:
	adapter=source
	theme=preload("res://scripts/ui/design_system/theme.gd").create()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var background := ColorRect.new(); background.color=Color("0b1624f5"); background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); add_child(background)
	var margin := MarginContainer.new(); margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for edge in ["left","right","top","bottom"]: margin.add_theme_constant_override("margin_"+edge,32)
	add_child(margin)
	var column := VBoxContainer.new(); column.add_theme_constant_override("separation",14); margin.add_child(column)
	var heading := HBoxContainer.new(); column.add_child(heading)
	var title := Label.new(); title.text="LAB / VOLT   ·   CAMPUS"; title.add_theme_font_size_override("font_size",28); title.size_flags_horizontal=Control.SIZE_EXPAND_FILL; heading.add_child(title)
	var back := UI.action("Back","back",func():closed.emit(); queue_free());heading.add_child(back)
	tabs=TabContainer.new(); tabs.size_flags_vertical=Control.SIZE_EXPAND_FILL; column.add_child(tabs)
	var scroll := ScrollContainer.new(); scroll.name="Courses & activities"; tabs.add_child(scroll)
	content=VBoxContainer.new(); content.size_flags_horizontal=Control.SIZE_EXPAND_FILL; content.add_theme_constant_override("separation",12); scroll.add_child(content)
	notice=Label.new(); notice.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; column.add_child(notice)
	_build_courses(); _build_directory()
func _label(value: String, parent: Node) -> Label:
	var label := Label.new(); label.text=value; label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; parent.add_child(label); return label
func _select(parent: Node, values: Array, chosen: int, callback: Callable) -> OptionButton:
	var select := OptionButton.new(); select.custom_minimum_size.y=40
	for value in values: select.add_item(str(value))
	select.select(chosen); parent.add_child(select); select.item_selected.connect(callback); return select
func _build_courses() -> void:
	var catalog: Array=adapter.call("courses")
	_label("Choose an activity, then walk from the entrance to your assigned room.",content)
	if catalog.is_empty(): _label("Course provider unavailable. Existing laboratory menus remain available.",content); return
	var details := VBoxContainer.new()
	_select(content,["Course","Open Lab","Freeplay"],0,func(i):mode=["Course","Open Lab","Freeplay"][i];_course_details(details))
	var cards := preload("res://scripts/ui/design_system/responsive_grid.gd").new();cards.minimum_card_width=300;cards.maximum_columns=2;content.add_child(cards)
	for entry in catalog:
		var id := str(entry.get("id",entry.get("course_id","")))
		cards.add_child(UI.card(id+" · "+str(entry.get("title",entry.get("name",""))),str(entry.get("description","Select a week to review its topics and practical activity.")),"course"))
	var course_names: Array=[]
	for entry in catalog: course_names.append(str(entry.get("id",entry.get("course_id","")))+" · "+str(entry.get("title",entry.get("name",""))))
	course_id=str(catalog[0].get("id",catalog[0].get("course_id","")))
	
	_select(content,course_names,0,func(i):course_id=str(catalog[i].get("id",catalog[i].get("course_id",""))); _course_details(details))
	content.add_child(details); _course_details(details)
func _course_details(details: VBoxContainer) -> void:
	for child in details.get_children(): details.remove_child(child); child.queue_free()
	var summary: Dictionary=adapter.call("progress",course_id)
	var current: Dictionary=summary.get("current_attempt",{})
	var final_mark: Variant=summary.get("final_mark")
	var marks: Array=["Running: "+("—" if current.get("running_mark")==null else "%.1f%%"%float(current.running_mark)),"Earned to date: %.1f%%"%float(current.get("earned_to_date",0.0)),"Final/best: "+("—" if final_mark==null else "%.1f%% · %s"%[float(final_mark),"PASS" if bool(summary.get("passed",false)) else "FAIL"])]
	details.add_child(UI.card("Your course record","   ·   ".join(marks),"course"))
	if not summary.get("completed_attempts",[]).is_empty():details.add_child(UI.badge("%d completed course attempts · highest final retained"%summary.completed_attempts.size(),"check"))
	_label("A final mark is awarded only after every lecture and laboratory assignment is complete. 50% passes. Retakes keep the highest completed final mark. Open Lab and Freeplay are practice only.",details)
	if not bool(summary.get("weight_policy_valid",true)):_label("Grade-weight policy needs correction: "+"; ".join(summary.get("weight_errors",[])),details)
	var has_lab: bool=not adapter.call("weeks",course_id,"lab").is_empty()
	if adapter.has_method("course_record"):
		var record: Dictionary=adapter.call("course_record",course_id)
		var track_cards := HFlowContainer.new();details.add_child(track_cards)
		for track in ["lecture","lab"]:
			var entries: Array=record.get("tracks",{}).get(track,[])
			if entries.is_empty():continue
			var lines: Array[String]=[]
			for entry in entries:
				lines.append("Week %d%s · %s · attendance: %s"%[int(entry.week)," EXAM" if bool(entry.is_exam) else "","marked %.1f%%"%float(entry.best_score) if entry.best_score!=null else "ungraded",str(entry.attendance).replace("_"," ")])
			track_cards.add_child(UI.card(track.capitalize()+" weeks","\n".join(lines),"course"))
	if has_lab:
		_select(details,["Lecture","Laboratory"],0 if kind=="lecture" else 1,func(i):kind="lecture" if i==0 else "lab"; _course_details(details))
	else:
		kind="lecture"
		_label("Lecture and study only. This course has no laboratory activity.",details)
	var weeks: Array=adapter.call("weeks",course_id,kind)
	var names: Array=[]
	for entry in weeks: names.append("Week %d · %s · %.2f%%"%[int(entry.get("week",names.size()+1)),str(entry.get("title","")),float(entry.get("grade_weight",0.0))])
	week=1
	if not names.is_empty(): _select(details,names,0,func(i):week=int(weeks[i].get("week",i+1)); _week_details(weeks[i]))
	_select(details,["Beginner","Easy","Normal","Hard","Expert"],difficulty,func(i):difficulty=i)
	if course_id.begins_with("MTH"):
		var calculator_toggle := CheckButton.new();calculator_toggle.text="Allow calculator in this assessment";calculator_toggle.button_pressed=math_calculator_allowed;details.add_child(calculator_toggle);calculator_toggle.toggled.connect(func(value):math_calculator_allowed=value)
		var formula_toggle := CheckButton.new();formula_toggle.text="Allow formula reference in this assessment";formula_toggle.button_pressed=math_formula_allowed;details.add_child(formula_toggle);formula_toggle.toggled.connect(func(value):math_formula_allowed=value)
	var room: Dictionary=adapter.call("assigned_room",course_id,kind)
	_label("Assigned room: "+str(room.get("number","Unavailable"))+" · "+str(room.get("title","")),details)
	if not weeks.is_empty(): _week_details(weeks[0])
	week_status=_label("",details)
	_update_progress()
	var start := UI.action("Start selected activity","play",Callable(),true);details.add_child(start)
	start.disabled=(mode=="Open Lab" and not has_lab) or weeks.is_empty() or room.is_empty() or (adapter.has_method("can_start") and not adapter.call("can_start"))
	start.tooltip_text="The host starts activities. Active marked assessments must finish first."
	start.pressed.connect(func():
		var result: Dictionary=adapter.call("request_activity",{"mode":mode,"course_id":course_id,"kind":kind,"week":week,"difficulty":difficulty,"calculator_allowed":math_calculator_allowed,"formula_allowed":math_formula_allowed})
		notice.text="Activity started · follow your room slip." if result.get("ok",false) else str(result.get("error","Unable to start."))
		if result.get("ok",false): activity_started.emit()
	)
func _week_details(entry: Dictionary) -> void:
	notice.text=" · ".join(entry.get("topics",[]))
	_update_progress()
func _update_progress() -> void:
	if not is_instance_valid(week_status) or not adapter.has_method("week_progress"): return
	var progress: Dictionary=adapter.call("week_progress",course_id,week)
	var lines: Array[String]=[]
	for category in ["lecture","lab"]:
		if category=="lab" and adapter.call("weeks",course_id,"lab").is_empty():continue
		var result: Dictionary=progress.get(category,{})
		lines.append(category.capitalize()+": "+("Not completed" if int(result.get("count",0))==0 else "%d attempts · recent %.1f%% · best %.1f%%"%[int(result.count),float(result.recent),float(result.best)]))
	week_status.text="Week %d progress\n"%week+"\n".join(lines)
func _build_directory() -> void:
	var box := VBoxContainer.new(); box.name="Map & directory"; tabs.add_child(box)
	var off := UI.action("Turn guidance off","close",func():adapter.call("navigate",""); notice.text="Navigation assistance off.");box.add_child(off)
	var search := LineEdit.new(); search.placeholder_text="Search room number, subject or facility"; box.add_child(search)
	var map := preload("res://scripts/campus/ui/campus_map.gd").new(); map.rooms=adapter.call("rooms",""); box.add_child(map)
	_select(box,["Ground floor","Upper floor"],0,func(i):map.floor_index=i; map.queue_redraw())
	var scroll := ScrollContainer.new(); scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL; box.add_child(scroll)
	var list := VBoxContainer.new(); list.size_flags_horizontal=Control.SIZE_EXPAND_FILL; scroll.add_child(list)
	var fill := func(query: String):
		for child in list.get_children(): list.remove_child(child); child.queue_free()
		for room in adapter.call("rooms",query):
			var button := Button.new(); button.text=str(room.get("number",""))+" · "+str(room.get("title",""))+" · Floor "+str(int(room.get("floor",0))+1); button.custom_minimum_size.y=38; list.add_child(button)
			button.pressed.connect(func():adapter.call("navigate",str(room.id)); notice.text="Guidance selected: "+str(room.get("number","")))
	search.text_changed.connect(fill); fill.call("")
	map.room_selected.connect(func(id):adapter.call("navigate",id); notice.text="Guidance selected for "+id)
