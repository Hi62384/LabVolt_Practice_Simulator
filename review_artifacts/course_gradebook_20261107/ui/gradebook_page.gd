extends Control
signal closed

const Skin = preload("res://scripts/ui/design_system/theme.gd")
const Widgets = preload("res://scripts/ui/design_system/widgets.gd")
const Tokens = preload("res://scripts/ui/design_system/tokens.gd")
var model: Dictionary = {}
var selected := ""
var expanded := {}
var detail: VBoxContainer
var courses: VBoxContainer
var layout: BoxContainer
var sidebar: PanelContainer
var content: PanelContainer
var footer: Label

func build(source: Dictionary) -> void:
	model=source
	theme=Skin.create()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var shade := ColorRect.new();shade.color=Color(0.02,0.045,0.065,0.78);shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);add_child(shade)
	var frame := MarginContainer.new();frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for edge in ["left","right","top","bottom"]:frame.add_theme_constant_override("margin_"+edge,24)
	add_child(frame)
	var column := VBoxContainer.new();column.add_theme_constant_override("separation",12);frame.add_child(column)
	var header := HBoxContainer.new();column.add_child(header)
	var heading := Widgets.text("View Courses","TitleLabel");heading.size_flags_horizontal=SIZE_EXPAND_FILL;header.add_child(heading)
	layout=BoxContainer.new();layout.size_flags_vertical=SIZE_EXPAND_FILL;layout.add_theme_constant_override("separation",16);column.add_child(layout)
	sidebar=PanelContainer.new();sidebar.theme_type_variation="CardPanel";sidebar.custom_minimum_size.x=260;layout.add_child(sidebar)
	var side_column := VBoxContainer.new();sidebar.add_child(side_column)
	var side_scroll := ScrollContainer.new();side_scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;side_scroll.size_flags_vertical=SIZE_EXPAND_FILL;side_column.add_child(side_scroll)
	courses=VBoxContainer.new();courses.size_flags_horizontal=SIZE_EXPAND_FILL;side_scroll.add_child(courses)
	side_column.add_child(Widgets.action("Back","back",func():closed.emit();queue_free()))
	content=PanelContainer.new();content.theme_type_variation="CardPanel";content.size_flags_horizontal=SIZE_EXPAND_FILL;layout.add_child(content)
	var detail_column := VBoxContainer.new();content.add_child(detail_column)
	var table_scroll := ScrollContainer.new();table_scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;table_scroll.size_flags_vertical=SIZE_EXPAND_FILL;detail_column.add_child(table_scroll)
	detail=VBoxContainer.new();detail.size_flags_horizontal=SIZE_EXPAND_FILL;detail.add_theme_constant_override("separation",12);table_scroll.add_child(detail)
	footer=Widgets.text("","SubtitleLabel");detail_column.add_child(footer)
	resized.connect(_reflow)
	_reflow();_refresh_courses();_refresh_detail()

func _reflow() -> void:
	if not is_instance_valid(layout):return
	layout.vertical=size.x<900
	sidebar.size_flags_vertical=SIZE_EXPAND_FILL if layout.vertical else SIZE_FILL
	content.size_flags_vertical=SIZE_EXPAND_FILL

func _course_id(row: Dictionary) -> String:return str(row.get("course_id",row.get("id","")))
func _label(value: String,parent: Node,variant := "Label") -> Label:
	var item := Widgets.text(value,variant);parent.add_child(item);return item
func _refresh_courses() -> void:
	for child in courses.get_children():child.queue_free()
	var rows: Array=model.get("courses",[])
	var groups: Dictionary=model.get("groups",{})
	for subject in groups:
		if not expanded.has(subject):expanded[subject]=true
		var group := Widgets.action(("▾ " if expanded[subject] else "▸ ")+str(subject),"course",func():expanded[subject]=not expanded[subject];_refresh_courses())
		group.theme_type_variation="QuietButton";courses.add_child(group)
		if not expanded[subject]:continue
		for id in groups[subject]:
			for row in rows:
				if _course_id(row)!=str(id):continue
				var item := Widgets.action(str(id)+" · "+str(row.get("display_name",row.get("title",""))),"circuit" if subject=="Electrical" else "course",func():selected=str(id);_refresh_courses();_refresh_detail())
				item.theme_type_variation="PrimaryButton" if selected==str(id) else "Button"
				item.clip_text=true;item.tooltip_text=item.text;courses.add_child(item)
	var recent: Array=model.get("recent_attendance",[])
	if not recent.is_empty():
		_label("Recent",courses,"SubtitleLabel")
		for entry in recent.slice(0,mini(3,recent.size())):
			var id := str(entry.get("course_id",""))
			var item := Widgets.action(id,"course",func():selected=id;_refresh_courses();_refresh_detail());courses.add_child(item)

func _refresh_detail() -> void:
	for child in detail.get_children():child.queue_free()
	footer.text=""
	var row: Dictionary={}
	for candidate in model.get("courses",[]):
		if _course_id(candidate)==selected:row=candidate;break
	if row.is_empty():_label("Select a course to view your grades.",detail);return
	_label(selected+" · "+str(row.get("display_name",row.get("title",""))),detail,"TitleLabel")
	var description := str(row.get("description",""))
	if not description.is_empty():_label(description,detail,"MutedLabel")
	var grade: Dictionary=row.get("gradebook",{})
	var running: Variant=grade.get("current_average")
	var average_card := PanelContainer.new();average_card.theme_type_variation="CardPanel";detail.add_child(average_card)
	_label("Current Average"+(" · Attempt %d"%int(grade.get("attempt_number",0)) if int(grade.get("attempt_number",0))>0 else "")+"  "+("Not graded yet" if running==null else "%.1f%%"%float(running)),average_card,"SubtitleLabel")
	var best: Variant=grade.get("best_completed_mark")
	if best!=null:_label("Best completed attempt: %.1f%%"%float(best),detail,"MutedLabel")
	if str(grade.get("identity_status",""))=="ambiguous_legacy":_label("Some older records cannot be assigned to this attempt.",detail,"MutedLabel")
	var final_grade: Variant=grade.get("final_mark")
	footer.text="Earned Final-Grade Points  "+_number(grade.get("earned_final_points")," points")+"    Final Grade  "+("Not yet determined" if final_grade==null else "%.1f%%"%float(final_grade))
	var progress: Dictionary=row.get("progress",{})
	if not progress.is_empty():_label("Course Progress  %d / %d"%[int(progress.get("completed",0)),int(progress.get("required",0))],detail)
	var tracks: Dictionary=grade.get("tracks",{})
	var lectures: Array=[];var labs: Array=[]
	for entry in tracks.get("lecture",[]):
		if str(entry.get("id","")).begins_with("lecture:"):lectures.append(entry)
	for entry in tracks.get("lab",[]):
		if str(entry.get("id","")).begins_with("lab:"):labs.append(entry)
	_track("Lecture",lectures)
	if not labs.is_empty():_track("Laboratory",labs)
	var extras: Array=[]
	for entry in grade.get("rows",[]):
		if not str(entry.get("id","")).begins_with("lecture:") and not str(entry.get("id","")).begins_with("lab:"):extras.append(entry)
	if not extras.is_empty():_track("Other assessments",extras)
	if not bool(grade.get("policy_valid",true)):_label("Weight not configured",detail,"MutedLabel")
	var unmapped: Array=grade.get("unmatched_records",[])
	if not unmapped.is_empty():
		_label("Other recorded results",detail,"SubtitleLabel")
		for record in unmapped:
			_label(str(record.get("title",record.get("assessment_id","Assessment")))+" · %.1f%% · Weight not configured"%float(record.get("score",0.0)),detail)
	var ambiguous: Array=grade.get("ambiguous_legacy_records",[])
	if not ambiguous.is_empty():
		_label("Older results needing review",detail,"SubtitleLabel")
		for record in ambiguous:
			_label(str(record.get("title",record.get("assessment_id","Assessment")))+" · "+_number(record.get("score"),"%"),detail)

func _number(value: Variant,suffix: String) -> String:
	return "—" if value==null else "%.2f%s"%[float(value),suffix]

func _track(heading: String,rows: Array) -> void:
	_label(heading,detail,"SubtitleLabel")
	var table := GridContainer.new();table.columns=5;table.add_theme_constant_override("h_separation",14);table.add_theme_constant_override("v_separation",8);detail.add_child(table)
	for head in ["Week","Topic / Assessment","Mark","Final Weight","Contribution"]:_label(head,table,"MutedLabel")
	for row in rows:
		var status := str(row.get("status","not_available")).replace("_"," ").capitalize()
		var mark: Variant=row.get("score")
		_label("Week "+str(row.get("week")) if row.get("week")!=null else "—",table)
		_label(str(row.get("title",""))+" · "+status,table)
		_label("—" if mark==null else "%.1f%%"%float(mark),table)
		_label(_number(row.get("weight"),"%") if row.get("weight")!=null else "Weight not configured",table)
		_label(_number(row.get("weighted_points")," points"),table)
		var assessments: Array=row.get("assessments",[])
		if assessments.size()>1:
			var toggle := Widgets.action("Show %d assessments"%assessments.size(),"plus",Callable());detail.add_child(toggle)
			var parts := VBoxContainer.new();parts.visible=false;detail.add_child(parts)
			for assessment in assessments:
				_label(str(assessment.get("title","Assessment"))+" · "+_number(assessment.get("score"),"%")+" · "+_number(assessment.get("weight"),"%")+" · "+_number(assessment.get("weighted_points")," points"),parts)
			toggle.pressed.connect(func():parts.visible=not parts.visible;toggle.text="Hide assessments" if parts.visible else "Show %d assessments"%assessments.size())
