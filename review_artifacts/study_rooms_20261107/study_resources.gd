extends Node3D
## Read-only public course catalog and owner-held worksheet access.
## No gradebook, paper, profile, or network mutation here.
var game: Node
var course_adapter: Object
var room_id := ""
var target: StaticBody3D
var panel: PanelContainer
func install(owner: Node,adapter: Object,id: String,center: Vector3) -> bool:
	if not id in ["library","study"] or not is_instance_valid(owner):return false
	game=owner;course_adapter=adapter;room_id=id;position=center
	target=StaticBody3D.new();target.collision_layer=4;target.collision_mask=0
	target.set_meta("role","study_reference");target.set_meta("label","Browse course references")
	target.position=Vector3(-6.5,1.45,-5.03)
	var shape:=CollisionShape3D.new();var hit:=BoxShape3D.new();hit.size=Vector3(.8,.9,.12);shape.shape=hit
	target.add_child(shape);add_child(target)
	return true
func interact(node: Node) -> bool:
	if not is_instance_valid(node) or node!=target:return false
	if not is_instance_valid(game.player) or game.player.global_position.distance_to(target.global_position)>2.5:return true
	open_catalog();return true
func open_catalog() -> void:
	if is_instance_valid(panel):panel.queue_free()
	var layer:=CanvasLayer.new();layer.layer=26;add_child(layer)
	panel=PanelContainer.new();panel.position=Vector2(70,60);panel.custom_minimum_size=Vector2(540,440);layer.add_child(panel)
	var column:=VBoxContainer.new();panel.add_child(column)
	var title:=Label.new();title.text="Course references · "+("M204 Library" if room_id=="library" else "M205 Quiet Study");column.add_child(title)
	var catalog: Array=course_adapter.courses()
	for course in catalog:
		var id:=str(course.get("id",course.get("course_id","")))
		var topics: Array=[]
		for kind in ["lecture","lab"]:
			for week in course_adapter.weeks(id,kind):
				var name:=str(week.get("title",""))
				if not name.is_empty():topics.append(name)
		var entry:=Label.new();entry.text=id+" · "+str(course.get("title",course.get("name","")))+"\n"+" · ".join(topics.slice(0,3))
		entry.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;column.add_child(entry)
	var held_id: int=game.school.held(game.multiplayer.get_unique_id())
	if held_id!=0:
		var own: Dictionary=game.school.papers.get(held_id,{})
		if int(own.get("owner",-1))==game.multiplayer.get_unique_id():
			var sheet:=Button.new();sheet.text="Open my held worksheet";column.add_child(sheet)
			sheet.pressed.connect(func():game.paper_ui.open_sheet(held_id))
	var practice:=Label.new();practice.text="Ungraded ELM253 and ETY155 worksheets are available here. Official assignments remain with your class."
	practice.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;column.add_child(practice)
	for id in ["ELM253","ETY155"]:
		if not catalog.any(func(entry):return str(entry.get("id",entry.get("course_id","")))==id):continue
		var action:=Button.new();action.text="Request ungraded "+id+" practice worksheet";column.add_child(action)
		action.pressed.connect((func(course_id: String):game.school.request({"op":"study_practice","course_id":course_id});layer.queue_free()).bind(id))
	var close:=Button.new();close.text="Close";column.add_child(close)
	close.pressed.connect(func():layer.queue_free())
