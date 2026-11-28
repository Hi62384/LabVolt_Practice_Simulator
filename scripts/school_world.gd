extends Node3D
const Equipment = preload("res://scripts/campus/items/equipment_configuration.gd")
const Whiteboard = preload("res://scripts/ui/paper_workspace/whiteboard_workspace.gd")
const Toon = preload("res://scripts/toon_character.gd")
var game: Node
var school: Node
var teacher: Node3D
var dc_instructor: Node3D
var whiteboard: Label3D
var whiteboard_panel: MeshInstance3D
var board_workspace: CanvasLayer
var marker_board := -1
var marker_point := Vector2.ZERO
var marker_time := 0
var visuals := {}
var board_text := ""
var teaching_board: Node3D
var old_phase := ""
var timer_label: Label
var classroom_roots: Array=[]
func build(owner_game: Node) -> void:
	process_priority=95
	game=owner_game
	school=game.school
	school.updated.connect(_refresh_board_workspace)
	game.session.leaving.connect(func():close_board_workspace(false))
	teacher=Node3D.new()
	add_child(teacher)
	var dc_room: Dictionary = game.campus.registry.get_room("dc_lab")
	if not dc_room.is_empty():
		dc_instructor = Node3D.new()
		dc_instructor.name = "DCPracticeInstructor"
		dc_instructor.position = game.campus.registry.vector(dc_room.center) + Vector3(4.0, 0.0, -3.8)
		add_child(dc_instructor)
		game.campus.register_content("dc_lab", dc_instructor)
	whiteboard_panel=game._box(self,Vector3(0,2,9.75),Vector3(5.7,2.5,.08),Color("f3f2e6"))
	whiteboard=game._text3(self,"",Vector3(0,2,9.68),.15,Color("162b3c"))
	whiteboard.rotation.y=PI
	teaching_board=preload("res://scripts/campus/academics/teaching_board.gd").new();add_child(teaching_board);teaching_board.hide()
	whiteboard.width=1600
	whiteboard.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	var bin := StaticBody3D.new()
	bin.position=preload("res://scripts/campus/academics/classroom_layout.gd").recycling(game.campus.registry.get_room("ac_lab"))
	bin.set_meta("role","trash");bin.add_to_group("paper_recycling")
	bin.set_meta("label","Paper recycling")
	add_child(bin)
	game._cylinder(bin,Vector3(0,.34,0),.3,.68,Color("3c6670"),.4)
	game._cylinder(bin,Vector3(0,.686,0),.255,.01,Color("111b20"))
	var bin_hit := CollisionShape3D.new()
	var bin_shape := CylinderShape3D.new()
	bin_shape.radius=.32
	bin_shape.height=.7
	bin_hit.shape=bin_shape
	bin_hit.position.y=.35
	bin.add_child(bin_hit)
	timer_label=Label.new()
	timer_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	timer_label.position=Vector2(-310,24)
	timer_label.size=Vector2(280,30)
	timer_label.horizontal_alignment=HORIZONTAL_ALIGNMENT_RIGHT
	timer_label.add_theme_font_size_override("font_size",18)
	game.ui.add_child(timer_label)
	school.updated.connect(refresh)
	build_campus_furniture()
func refresh() -> void:
	_refresh_floor_leads()
	if old_phase!=school.phase and game.front.in_game and school.mode=="Class":game.sfx.play("bell")
	old_phase=school.phase
	timer_label.text="%s  %02d:%02d"%[school.phase.capitalize(),int(school.remaining)/60,int(school.remaining)%60]
	if not str(school.activity.get("ai_status","")).is_empty():
		timer_label.text+="\n"+str(school.activity.ai_status)
	for id in visuals.keys():
		if not school.papers.has(id):
			visuals[id].root.queue_free()
			visuals.erase(id)
	for id in school.papers:
		var paper: Dictionary=school.papers[id]
		if not visuals.has(id):_create(paper)
		var visual: Dictionary=visuals[id]
		if visual.revision!=paper.revision:
			_page(visual,paper)
			visual.revision=paper.revision
	var value: String = "PLAY\n\nOpen the lab guide for practice sheets and equipment tutorials."
	if school.mode=="Class":
		value="CLASS • %s • %02d:%02d\n%s\n\n"%[school.phase.to_upper(),int(school.remaining)/60,int(school.remaining)%60,school.project.get("title","")]
		if school.phase=="lesson":
			var stage: Dictionary=school.teaching_stage()
			value+="%d / %d · %s\n%s"%[int(stage.get("index",0))+1,int(stage.get("count",1)),str(stage.get("title","")),str(stage.get("text",stage.get("caption","")))]
		elif school.phase=="travel":value+="Find your assigned room. Teaching begins automatically when the two-minute countdown ends; arrivals afterward are late."
		elif school.phase=="assignment":value+="Complete your sheet and submit it. At the deadline, completed answers are marked; unanswered parts receive no credit."
		else:value+="Class complete. The host can select the next activity without reconnecting."
	if not school.activity.is_empty():
		var room: Dictionary=school.activity.room
		value+="\nRoom %s · %s"%[str(room.get("number",room.get("room_number",""))),str(room.get("name",""))]
	if not school.activity.is_empty():
		var center: Vector3=school.room_bridge.point(school.activity.room.get("center",school.teacher_position))
		var direction := 1.0 if school.teacher_position.z>=center.z else -1.0
		whiteboard.position=school.teacher_position+Vector3(0,2,1.4*direction)
		whiteboard_panel.position=school.teacher_position+Vector3(0,2,1.47*direction)
		whiteboard.rotation.y=PI if direction>0 else 0
	var computer_lecture: bool=not school.activity.is_empty() and str(school.activity.get("room",{}).get("id",""))=="computer"
	var in_lecture: bool=not school.activity.is_empty() and str(school.activity.get("kind","lecture"))=="lecture" and not computer_lecture
	var board_active: bool=in_lecture and game.front.in_game and school.room_bridge.contains(str(school.activity.room.get("id","")),game.player.global_position)
	whiteboard_panel.visible=not computer_lecture
	whiteboard.visible=not in_lecture and not computer_lecture
	teaching_board.set_room_active(board_active)
	if board_active:
		teaching_board.position=whiteboard.position
		teaching_board.rotation=whiteboard.rotation
		var stage: Dictionary=school.teaching_stage() if school.phase=="lesson" else {"text":value}
		var status: String="%s  %02d:%02d"%[school.phase.to_upper(),int(school.remaining)/60,int(school.remaining)%60]
		teaching_board.show_content(str(school.activity.get("course_id","")),school.phase,str(school.project.get("title","")),stage,status)
	if value!=board_text:
		board_text=value
		whiteboard.text=value
var floor_lead_visuals := {}

func _refresh_floor_leads() -> void:
	for id in floor_lead_visuals.keys():
		if school.floor_leads.has(id):continue
		floor_lead_visuals[id].queue_free()
		floor_lead_visuals.erase(id)
	for id in school.floor_leads:
		if floor_lead_visuals.has(id):continue
		var lead: Dictionary=school.floor_leads[id]
		var root := StaticBody3D.new()
		root.collision_layer=4
		root.collision_mask=0
		root.set_meta("role","floor_lead")
		root.set_meta("lead_id",id)
		root.set_meta("label","Lead")
		add_child(root)
		root.global_position=lead.position
		var jacket: Color=game.JACKET_COLORS[lead.color]
		var start := Vector3(-.15,.035,0)
		var finish := Vector3(.15,.035,0)
		root.add_child(preload("res://scripts/cable_mesh.gd").build(start,finish,jacket))
		game.held_lead_connector(root,jacket,start)
		game.held_lead_connector(root,jacket,finish)
		var hit := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size=Vector3(.4,.10,.24)
		hit.position.y=.05
		hit.shape=shape
		root.add_child(hit)
		floor_lead_visuals[id]=root

func _create(paper: Dictionary) -> void:
	const Supplies = preload("res://scripts/campus/dorms/authority/persistent_dorm.gd")
	var supply := Supplies.paper_supply(paper)
	var root := StaticBody3D.new()
	root.collision_layer=4
	root.set_meta("role","paper")
	root.set_meta("label",str(paper.owner_name)+"’s sheet")
	if not supply.is_empty():root.set_meta("label",str(paper.project.title))
	root.set_meta("paper_id",paper.id)
	add_child(root)
	var hit := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	var board_size: Vector2=paper.get("board_size",Vector2(1.35,.78))
	var backpack := supply.begins_with("bag:")
	var notebook: Dictionary=paper.get("notebook_configuration",{})
	var calculator_options: Dictionary=paper.get("supply_configuration",{}) if paper.get("calculator",false) else {}
	const NotebookModel = preload("res://scripts/campus/items/notebook_model.gd")
	var bag_model := str(paper.get("supply_model","backpack_small"))
	match supply:
		"whiteboard": shape.size=Vector3(board_size.x,.035,board_size.y)
		"calculator_basic": shape.size=Vector3(.16,.053,.225)
		"pencil_case": shape.size=Vector3(.22,.056,.11)
		"flashlight": shape.size=Vector3(.31,.092,.095)
		"lab_goggles", "marker": shape.size=Vector3(.22,.026,.11)
		"notebook": shape.size=Vector3(.23,.034,.31)
		_:
			if backpack:
				shape.size=preload("res://scripts/campus/dorms/authority/backpack_inventory.gd").dimensions(bag_model)
				hit.position.y=shape.size.y*.5
			elif paper.get("calculator",false):shape.size=Vector3(.135,.026,.215)
			else:shape.size=Vector3(.32,.018,.44)
	if not notebook.is_empty():shape.size=NotebookModel.dimensions(notebook)
	if not calculator_options.is_empty():shape.size=Equipment.value(Equipment.CALCULATOR,calculator_options,"hardware","size",shape.size)
	hit.shape=shape
	root.add_child(hit)
	var viewport := SubViewport.new()
	viewport.size=Whiteboard.texture_size(paper) if supply=="whiteboard" else Vector2i(512,720)
	if supply=="whiteboard":viewport.disable_3d=true
	viewport.transparent_bg=false
	root.add_child(viewport)
	var mesh := MeshInstance3D.new()
	mesh.ignore_occlusion_culling=true
	var quad := QuadMesh.new()
	quad.size=Vector2(shape.size.x,shape.size.z)
	mesh.mesh=quad
	var material := StandardMaterial3D.new()
	material.albedo_texture=viewport.get_texture()
	material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode=BaseMaterial3D.CULL_DISABLED
	mesh.material_override=material
	root.add_child(mesh)
	var prop: Node3D
	if not notebook.is_empty():
		mesh.hide()
		viewport.render_target_update_mode=SubViewport.UPDATE_DISABLED
		prop=NotebookModel.build(root,notebook)
	elif paper.get("calculator",false):
		mesh.hide()
		viewport.render_target_update_mode=SubViewport.UPDATE_DISABLED
		prop=Node3D.new()
		root.add_child(prop)
		_build_calculator_prop(prop,shape.size,Equipment.Keypad.model_for(supply),calculator_options)
	elif supply in ["lab_goggles","flashlight","marker"]:
		mesh.hide()
		prop=Node3D.new()
		root.add_child(prop)
		_build_supply_prop(prop,supply)
	elif backpack:
		mesh.hide()
		prop=preload("res://scripts/campus/items/backpack_model.gd").build(root,bag_model,paper.get("supply_configuration",{}))
	if supply=="pencil_case":
		mesh.hide()
		var material_pouch := Toon.material("a45652")
		Toon.ellipsoid(root,Vector3.ZERO,Vector3(.11,.027,.052),material_pouch,"Pouch")
		game._box(root,Vector3(0,.023,.004),Vector3(.17,.006,.011),Color("633736"))
		for tooth in range(16):
			game._box(root,Vector3((tooth-7.5)*.009,.027,.004),Vector3(.003,.002,.007),Color("cfb28a"))
		game._box(root,Vector3(.078,.029,.009),Vector3(.017,.004,.011),Color("e1c391"))
	if paper.has("classroom_board"):
		var tray_marker:=Node3D.new()
		tray_marker.position=Vector3(-board_size.x*.5+.20,-board_size.y*.5+.07,.035)
		root.add_child(tray_marker)
		_build_supply_prop(tray_marker,"marker")
	var backing: MeshInstance3D = game._box(root,Vector3(0,.022,0),shape.size,Color("253947") if paper.get("calculator",false) else Color("315464") if paper.get("notebook",false) else Color("eee8d7"))
	if supply=="pencil_case" or is_instance_valid(prop):backing.hide()
	backing.ignore_occlusion_culling=true
	visuals[paper.id]={"root":root,"hit":hit,"mesh":mesh,"backing":backing,"viewport":viewport,"page_view":null,"revision":-1,"prop":prop}

func _build_calculator_prop(prop: Node3D, dimensions: Vector3, model: String, options: Dictionary = {}) -> void:
	var width := dimensions.x
	var length := dimensions.z
	var face := dimensions.y*.5
	var basic := model=="calculator_basic"
	var shell: Color = {"calculator_basic":Color("171b1f"),"calculator_financial":Color("39473c")}.get(model,Color("293748"))
	shell=Color(Equipment.value(Equipment.CALCULATOR,options,"appearance","shell",shell.to_html(false)))
	var casing: MeshInstance3D=game._box(prop,Vector3.ZERO,Vector3(width,length,dimensions.y),shell)
	var plate: MeshInstance3D=game._box(prop,Vector3(0,0,face),Vector3(width*.95,length*.96,.004),shell.lightened(.10))
	casing.set_meta("material_segment","case")
	plate.set_meta("material_segment","trim")
	var finish: Vector2=Equipment.value(Equipment.CALCULATOR,options,"appearance","finish",Vector2(.60,0))
	for surface in [casing,plate]:
		surface.material_override=surface.get_active_material(0).duplicate()
		surface.material_override.roughness=finish.x
		surface.material_override.metallic=finish.y
	var display_scale: float=Equipment.value(Equipment.CALCULATOR,options,"hardware","screen",1.0)
	var display_color:=Color(Equipment.value(Equipment.CALCULATOR,options,"appearance","screen_color","b0c398"))
	game._box(prop,Vector3(0,length*.30,face+.003),Vector3(width*.88,length*.24*display_scale,.006),Color("141f24"))
	game._box(prop,Vector3(0,length*.30,face+.006),Vector3(width*.81,length*.185*display_scale,.002),display_color).set_meta("material_segment","display")
	_calculator_mark(prop,"0",Vector3(width*.33,length*.29,face+.0075),.00053,Color("233b30"))
	var keys:=Equipment.Keypad.updated_keys(options.get("keypad",Equipment.Keypad.keys(model)))
	var key_colors: Dictionary=options.get("key_colors",{})
	var key_tint:=Color(options.get("materials",{}).get("keys",{}).get("color","ffffff"))
	if options.has("body") and int(options.get("version",1))<Equipment.DESIGN_VERSION:keys=Equipment.Keypad.with_required(keys)
	var columns: int=Equipment.value(Equipment.CALCULATOR,options,"hardware","columns",4 if basic else 5)
	var round_keys: bool=Equipment.value(Equipment.CALCULATOR,options,"appearance","key_style",false)
	var rows := maxi(1,Equipment.Keypad.occupied_rows(keys,columns))
	var step := Vector2(width*.88/columns,length*.60/rows)
	for index in keys.size():
		var key: String=keys[index]
		if key.is_empty():continue
		var at := Vector3((index%columns-(columns-1)*.5)*step.x,length*.13-(floorf(float(index)/columns)+.5)*step.y,face+.005)
		var tint := Color("8297a2") if key.is_valid_int() or key=="." else Color("485968")
		if not options.is_empty():
			tint=Color(Equipment.value(Equipment.CALCULATOR,options,"appearance","keys","60747e"))
			if not key.is_valid_int() and key!=".":tint=tint.darkened(.18)
		if key=="RUN":tint=Color("478f7e")
		if key in ["AC","DEL"]:tint=Color("a76658")
		if key_colors.has(key):tint=Color(key_colors[key])
		var cap: MeshInstance3D
		if round_keys:cap=Toon.ellipsoid(prop,at,Vector3(step.x*.43,step.y*.395,.0035),Toon.material(tint.to_html(false)),key+" key")
		else:cap=game._box(prop,at,Vector3(step.x*.86,step.y*.79,.007 if basic else .004),tint)
		cap.set_meta("material_segment","keys")
		cap.set_meta("material_color_multiplier",tint)
		_calculator_mark(prop,Equipment.Keypad.caption(key),at+Vector3(0,0,.004),.00032 if basic else .00022,Color("1a2631") if (tint*key_tint).get_luminance()>.45 else Color("f2f5ef"))
	Equipment.Materials.apply(prop,options)
	preload("res://scripts/campus/items/decoration_surface.gd").attach(prop,options.get("decoration",[]),Vector3(0,0,-face-.0005),Vector3(0,PI,0),Vector2(width*.83,length*.86))

func _calculator_mark(parent: Node3D, value: String, at: Vector3, pixel: float, tint: Color) -> void:
	var mark := Label3D.new()
	mark.text=value
	mark.font_size=26
	mark.pixel_size=pixel
	mark.modulate=tint
	mark.outline_size=0
	mark.position=at
	parent.add_child(mark)

func _build_supply_prop(prop: Node3D, supply: String) -> void:
	if supply=="lab_goggles":
		for side in [-1.0,1.0]:
			var x: float=side*.047
			Toon.ellipsoid(prop,Vector3(x,0,0),Vector3(.049,.031,.013),Toon.material("254856"),"Lens frame")
			Toon.ellipsoid(prop,Vector3(x,0,.009),Vector3(.041,.024,.008),Toon.material("83bdcc"),"Lens")
			game._box(prop,Vector3(side*.09,0,-.039),Vector3(.012,.013,.077),Color("254856"))
		game._box(prop,Vector3.ZERO,Vector3(.025,.013,.017),Color("254856"))
		game._box(prop,Vector3(0,0,-.077),Vector3(.18,.014,.01),Color("254856"))
		return
	var flashlight := supply=="flashlight"
	var barrel := CylinderMesh.new()
	barrel.height=.222 if flashlight else .113
	barrel.top_radius=.027 if flashlight else .010
	barrel.bottom_radius=barrel.top_radius
	barrel.material=Toon.material("314652" if flashlight else "dedbd1")
	var body := MeshInstance3D.new()
	body.mesh=barrel
	body.rotation.z=PI*.5
	prop.add_child(body)
	var cap := CylinderMesh.new()
	cap.height=.061 if flashlight else .022
	cap.top_radius=.044 if flashlight else .0045
	cap.bottom_radius=.028 if flashlight else .011
	cap.material=Toon.material("546972" if flashlight else "31596b")
	var tip := MeshInstance3D.new()
	tip.mesh=cap
	tip.rotation.z=PI*.5
	tip.position.x=-.129 if flashlight else -.064
	prop.add_child(tip)
	if flashlight:
		var trim := Toon.material("647881")
		Toon.link(prop,Vector3(-.157,0,0),Vector3(-.169,0,0),.046,trim)
		Toon.ellipsoid(prop,Vector3(-.169,0,0),Vector3(.003,.038,.038),Toon.material("ddd9bb",.3),"Lens")
		var grip_material := Toon.material("253641")
		for ring in range(5):
			var x := .008+ring*.018
			Toon.link(prop,Vector3(x,0,0),Vector3(x+.005,0,0),.029,grip_material)
		game._box(prop,Vector3(-.061,.027,0),Vector3(.024,.008,.017),Color("dbb16e"))
	else:
		Toon.ellipsoid(prop,Vector3(-.077,0,0),Vector3(.008,.004,.004),Toon.material("253641"),"Felt nib")
		Toon.link(prop,Vector3(.042,0,0),Vector3(.062,0,0),.0105,Toon.material("31596b"))

func _page(visual: Dictionary,paper: Dictionary) -> void:
	if is_instance_valid(visual.page_view):visual.page_view.free()
	if paper.get("calculator",false):return
	var supply := str(paper.get("supply_id",""))
	if supply=="whiteboard":
		var classroom:=paper.has("classroom_board")
		var canvas_size:=Vector2(visual.viewport.size)
		var frame_width:=12.0 if classroom else 20.0
		var face := ColorRect.new()
		face.color=Color("e9eee8")
		visual.viewport.add_child(face)
		face.size=canvas_size
		for rect in [Rect2(0,0,canvas_size.x,frame_width),Rect2(0,canvas_size.y-frame_width,canvas_size.x,frame_width),Rect2(0,0,frame_width,canvas_size.y),Rect2(canvas_size.x-frame_width,0,frame_width,canvas_size.y)]:
			var frame := ColorRect.new()
			frame.color=Color("6a7980")
			frame.position=rect.position
			frame.size=rect.size
			face.add_child(frame)
		var strokes := Control.new()
		strokes.mouse_filter=Control.MOUSE_FILTER_IGNORE
		strokes.size=canvas_size
		face.add_child(strokes)
		var paths: Array=paper.get("board_lines",[])
		strokes.draw.connect(func():Whiteboard.paint(strokes,paths))
		var notes: Variant=paper.get("board_notes",[])
		if notes is Array and not notes.is_empty():
			var note_panel:=ColorRect.new()
			note_panel.color=Color("d9e5e3")
			var note_height:=70.0 if classroom else 118.0
			note_panel.position=Vector2(24,canvas_size.y-note_height-12)
			note_panel.size=Vector2(canvas_size.x-48,note_height)
			face.add_child(note_panel)
			var note_text:=Label.new()
			note_text.position=Vector2(12,8)
			note_text.size=note_panel.size-Vector2(24,16)
			note_text.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
			note_text.add_theme_color_override("font_color",Color("203b49"))
			note_text.add_theme_font_size_override("font_size",28 if classroom else 21)
			var lines: Array[String]=[]
			for entry in notes.slice(0,2 if classroom else 3):lines.append("• "+str(entry.get("text","")).left(100))
			note_text.text="\n".join(lines)
			note_panel.add_child(note_text)
		visual.page_view=face
		visual.revision=paper.revision
		visual.viewport.render_target_update_mode=SubViewport.UPDATE_ONCE
		return
	if paper.get("notebook",false) and not paper.get("notebook_configuration",{}).is_empty():
		visual.revision=paper.revision
		return
	if paper.get("notebook",false):
		var cover := ColorRect.new()
		cover.color=Color("416b78")
		cover.size=Vector2(512,720)
		visual.viewport.add_child(cover)
		var spine := ColorRect.new()
		spine.color=Color("254854")
		spine.size=Vector2(66,720)
		cover.add_child(spine)
		var nameplate := Label.new()
		nameplate.text="NOTEBOOK"
		nameplate.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
		nameplate.vertical_alignment=VERTICAL_ALIGNMENT_CENTER
		nameplate.add_theme_font_size_override("font_size",42)
		nameplate.add_theme_color_override("font_color",Color("254854"))
		var plate := StyleBoxFlat.new()
		plate.bg_color=Color("ddd2b8")
		nameplate.add_theme_stylebox_override("normal",plate)
		nameplate.position=Vector2(122,182)
		nameplate.size=Vector2(326,108)
		cover.add_child(nameplate)
		visual.page_view=cover
		visual.viewport.render_target_update_mode=SubViewport.UPDATE_ONCE
		return
	if supply in ["pencil_case","lab_goggles","flashlight","marker"] or supply.begins_with("bag:"):
		visual.revision=paper.revision
		return
	var page = preload("res://scripts/math_course_paper.gd").new() if paper.project.get("course_id", "") in ["MTH147", "MTH255"] else preload("res://scripts/worksheet_page.gd").new()
	page.paper=paper.duplicate(true);page.paper.project=school._public_project(paper.project,(paper.lesson or not paper.mark.is_empty()) and paper.owner==multiplayer.get_unique_id());page.page=int(paper.page);page.writable=false
	visual.viewport.add_child(page);page.scale=Vector2(512./780.,720./1100.)
	if page.has_method("fit_preview"):page.fit_preview(visual.viewport)
	var annotations=preload("res://scripts/paper_annotations.gd").new();annotations.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);annotations.writable=false;annotations.items=paper.get("annotations",{}).get(str(paper.page),[]).duplicate(true);page.add_child(annotations)
	visual.page_view=page;visual.revision=paper.revision
	visual.viewport.render_target_update_mode=SubViewport.UPDATE_ONCE

func _process(delta: float) -> void:
	if teacher==null:return
	timer_label.visible=school.mode=="Class" and game.player.enabled
	var moving := teacher.position.distance_to(school.teacher_position)>.01
	teacher.position=teacher.position.lerp(school.teacher_position,1-exp(-10*delta))
	teacher.rotation.y=lerp_angle(teacher.rotation.y,school.teacher_yaw,1-exp(-10*delta))
	var model=teacher.get_node_or_null("InstructorModel")
	if model!=null:preload("res://scripts/avatar_model.gd").animate(model,moving)
	for id in visuals:
		if not school.papers.has(id):continue
		var p: Dictionary=school.papers[id]
		var v: Dictionary=visuals[id]
		if p.get("stowed",false):v.root.visible=false;v.hit.disabled=true;continue
		var supply := str(p.get("supply_id",""))
		var backpack := supply.begins_with("bag:")
		var configured_notebook: bool=not p.get("notebook_configuration",{}).is_empty()
		var shape: Vector3=v.hit.shape.size
		v.hit.disabled=p.held and p.owner==multiplayer.get_unique_id()
		v.hit.rotation.x=PI/2 if p.held and not backpack else 0
		if backpack:v.hit.position.y=0.0 if p.held else shape.y*.5
		if configured_notebook:v.hit.position.y=0.0 if p.held else shape.y*.5
		if p.get("calculator",false):v.hit.position.y=0.0 if p.held else shape.y*.5
		if p.held:
			v.backing.visible=not is_instance_valid(v.prop) and supply!="pencil_case"
			v.backing.rotation.x=PI/2
			v.backing.position=Vector3(0,0,-shape.y*.5-.001)
			v.mesh.position.y=0
			v.mesh.rotation.x=0
			if is_instance_valid(v.prop):
				v.prop.rotation=Vector3.ZERO
				v.prop.position=Vector3.ZERO
			var local := int(p.owner)==multiplayer.get_unique_id()
			var pose: Dictionary=game.session.poses.get(p.owner,{})
			var basis: Basis=game.camera.global_basis if local else Basis(Vector3.UP,float(pose.get("yaw",0.0)))
			var fallback: Vector3=game.camera.to_global(Vector3(.37,-.27,-.59)) if local else pose.get("position",Vector3.ZERO)+Vector3(0,1.2,0)
			var hand: Vector3=game.held_item_position(p.owner,fallback)
			basis*=Basis.from_euler(Vector3(-.12,-.15,0))
			if local:hand-=basis.x*.035
			if backpack:
				var carry_basis := basis*Basis.from_euler(Vector3(.16,-.48,-.15))
				v.root.global_transform=Transform3D(carry_basis,hand-carry_basis*Vector3(0,shape.y*.47,.025))
			elif supply=="whiteboard":
				var carry_basis := basis.rotated(basis.y,-.58)
				v.root.global_transform=Transform3D(carry_basis.scaled(Vector3.ONE*.27),hand-carry_basis*Vector3(shape.x*.10,0,.025))
			elif supply=="flashlight":
				var carry_basis := basis * Basis.from_euler(Vector3(0,-1.05,-.10))
				var grip := hand + basis * Vector3(.005,.018,-.020)
				v.root.global_transform=Transform3D(carry_basis,grip-carry_basis*Vector3(.053,0,0))
			elif supply=="marker":
				var carry_basis := basis * Basis.from_euler(Vector3(0,-.40,-.85))
				var grip := hand + basis * Vector3(.010,.012,-.016)
				v.root.global_transform=Transform3D(carry_basis,grip-carry_basis*Vector3(.022,0,0))
			elif p.get("calculator",false):
				var carry_basis := basis*Basis.from_euler(Vector3(.13,-.43,.09))
				if supply=="calculator_basic":carry_basis=carry_basis.scaled(Vector3.ONE*1.23)
				var grip_offset := Vector3(shape.x*.54,-shape.z*.27,-shape.y*.21)
				v.root.global_transform=Transform3D(carry_basis,hand-carry_basis*grip_offset)
			elif configured_notebook:
				v.prop.rotation.x=PI/2
				v.prop.position.z=-shape.y*.5
				v.root.global_transform=Transform3D(basis,hand-basis*Vector3(shape.x*.43,-shape.z*.32,0))
			elif supply=="pencil_case" or is_instance_valid(v.prop):
				v.root.global_transform=Transform3D(basis,hand-basis*Vector3(.073,0,.012))
			else:
				v.root.global_transform=Transform3D(basis,hand-basis*Vector3(shape.x*.43,-shape.z*.32,0))
			v.root.visible=not local or (game.player.enabled and not game.workout_hides_carried_items())
		elif p.has("wall_normal"):
			v.root.visible=true
			var classroom_room:=str(p.get("classroom_board",""))
			if not classroom_room.is_empty() and is_instance_valid(game.lecture_classes):
				var sign: Dictionary=game.lecture_classes.signs.get(classroom_room,{})
				if is_instance_valid(sign.get("board")) and sign.board.active:v.root.visible=false
			v.hit.disabled=not v.root.visible
			v.backing.hide()
			v.root.global_transform=Transform3D(Basis.looking_at(-p.wall_normal,Vector3.UP),p.position)
			v.hit.rotation.x=PI/2
			v.mesh.rotation=Vector3.ZERO
			v.mesh.position=Vector3.ZERO
		else:
			v.root.visible=true
			v.backing.visible=supply!="pencil_case" and not is_instance_valid(v.prop)
			v.backing.rotation=Vector3.ZERO
			v.backing.position=Vector3(0,.033-shape.y*.5,0)
			v.root.global_transform=Transform3D(Basis.IDENTITY,p.position)
			if is_instance_valid(v.prop):
				v.prop.rotation.x=0.0 if backpack else -PI/2
				v.prop.position.y=shape.y*.5 if backpack else .046 if supply=="flashlight" else .034
			v.mesh.rotation.x=-PI/2
			v.mesh.position.y=.034
			if p.get("calculator",false):v.prop.position.y=shape.y*.5
			if configured_notebook:
				v.prop.rotation=Vector3.ZERO
				v.prop.position=Vector3.ZERO

func use_supply(button: int, continuation := false) -> bool:
	var held_id: int=school.held(multiplayer.get_unique_id())
	var supply := str(school.papers.get(held_id,{}).get("supply_id",""))
	var classroom_marker:=held_id==0
	if supply!="marker" and not classroom_marker:return false
	var camera: Camera3D=game.camera
	var ray := PhysicsRayQueryParameters3D.create(camera.global_position,camera.global_position-camera.global_basis.z*3,5)
	var hit := get_world_3d().direct_space_state.intersect_ray(ray)
	if hit.is_empty():
		marker_board=-1
		return supply=="marker"
	if supply=="marker" or classroom_marker:
		var target: Node3D=hit.collider
		var id := int(target.get_meta("paper_id",-1))
		if not school.papers.get(id,{}).has("wall_normal"):
			marker_board=-1
			return supply=="marker"
		if classroom_marker and not school.papers[id].has("classroom_board"):
			marker_board=-1
			return false
		var now := Time.get_ticks_msec()
		if continuation and now-marker_time<55:return true
		var local := target.to_local(hit.position)
		var board_size: Vector2=school.papers[id].get("board_size",Vector2(1.35,.78))
		var point := Vector2(clampf(local.x/board_size.x+.5,0,1),clampf(.5-local.y/board_size.y,0,1))
		var from := marker_point if continuation and marker_board==id and marker_point.distance_to(point)<.23 else point
		school.request({"op":"board_mark","id":id,"from":from,"point":point,"continue":continuation and from!=point,"erase":button==MOUSE_BUTTON_RIGHT})
		marker_board=id
		marker_point=point
		marker_time=now
	return true
func interact_held() -> bool:
	var id: int=school.held(multiplayer.get_unique_id())
	if id==0:return false
	var item: Dictionary=school.papers.get(id,{})
	var supply := str(item.get("supply_id",""))
	if item.get("calculator",false):
		game.open_carried_calculator(supply,item.get("supply_configuration",{}))
	elif item.get("notebook",false) or supply.is_empty():
		game.paper_ui.open_sheet(id)
	elif supply=="lab_goggles":
		game.hotbar._toggle_goggles(true,false)
	elif supply.begins_with("bag:"):
		game.hotbar._bag_intent({"op":"bag_move","bag":supply.trim_prefix("bag:"),"destination":"back"},false)
	else:
		return false
	return true

func open_board_workspace(target: StaticBody3D) -> bool:
	if not is_instance_valid(target):return false
	var id := int(target.get_meta("paper_id",0))
	var paper: Dictionary=school.papers.get(id,{})
	if not paper.has("wall_normal"):return false
	var peer := multiplayer.get_unique_id()
	var supply := str(school.papers.get(school.held(peer),{}).get("supply_id",""))
	if multiplayer.is_server() and not school._can_mark_whiteboard(peer,paper):
		game.ui.log_message("Hold a marker or wait for permission to write on this board.")
		return true
	if supply!="marker" and (not supply.is_empty() or not paper.has("classroom_board")):
		game.ui.log_message("Hold a marker to edit this whiteboard.")
		return true
	if is_instance_valid(board_workspace):return true
	var workspace := Whiteboard.new()
	workspace.board_id=id
	workspace.board_aspect=Whiteboard.aspect_for(paper)
	board_workspace=workspace
	add_child(workspace)
	workspace.command_requested.connect(func(action: Dictionary):school.request(action))
	workspace.dismissed.connect(close_board_workspace)
	workspace.refresh(paper)
	game.release_mouse()
	return true

func _refresh_board_workspace() -> void:
	if not is_instance_valid(board_workspace):return
	var paper: Dictionary=school.papers.get(board_workspace.board_id,{})
	if not paper.has("wall_normal") or game.player.global_position.distance_to(paper.position)>=3.6:
		close_board_workspace()
	else:
		board_workspace.refresh(paper)

func close_board_workspace(restore_control := true) -> bool:
	if not is_instance_valid(board_workspace):return false
	board_workspace.queue_free()
	board_workspace=null
	if restore_control and game.front.in_game:game.capture()
	return true

func interact(target: StaticBody3D,right_click: bool) -> bool:
	if target==null:return false
	var role: String=target.get_meta("role","")
	var held_id: int=school.held(multiplayer.get_unique_id())
	match role:
		"paper":
			var id: int=target.get_meta("paper_id")
			var item: Dictionary = school.papers.get(id,{})
			if right_click and item.get("calculator",false):
				if item.owner==multiplayer.get_unique_id():game.open_carried_calculator(str(item.get("supply_id","calculator")),item.get("supply_configuration",{}))
			elif right_click:
				if item.get("supply_id","").is_empty() or item.get("notebook",false):game.paper_ui.open_sheet(id)
			else:school.request({"op":"pickup","id":id})
			return true
		"trash":
			if right_click and can_recycle_held_sheet():confirm_trash(held_id)
			return true
		"table":
			if held_id!=0 and not right_click:return true
	return false

func can_recycle_held_sheet() -> bool:
	var item: Dictionary=school.papers.get(school.held(multiplayer.get_unique_id()),{})
	return not item.is_empty() and str(item.get("supply_id","")).is_empty() and not item.get("notebook",false) and not item.get("calculator",false)

func open_placed_document(target: StaticBody3D) -> bool:
	if target==null or target.get_meta("role","")!="paper":return false
	var id := int(target.get_meta("paper_id",0))
	if not school.shareable_document(school.papers.get(id,{})):return false
	game.paper_ui.open_sheet(id)
	return true

func placed_item_hint(id: int) -> String:
	var item: Dictionary=school.papers.get(id,{})
	if item.is_empty():return ""
	var owned := int(item.get("owner",0))==multiplayer.get_unique_id()
	var supply := str(item.get("supply_id",""))
	var supplies = preload("res://scripts/campus/dorms/authority/persistent_dorm.gd")
	var name: String=supplies.supply_title(supply) if supplies.is_supply(supply) else "Backpack" if supply.begins_with("bag:") else "Sheet"
	var pickup := "Click: pick up "+name.to_lower() if owned else ""
	if item.has("wall_normal"):
		return "%s: open whiteboard" % OS.get_keycode_string(game.player.keys.interact)
	if item.get("calculator",false):
		if not owned:return name
		return "Right click: use "+name.to_lower()+" • "+pickup
	if school.shareable_document(item):
		var key := OS.get_keycode_string(game.player.keys.interact)
		return "%s — Owned by %s\n%s — Open%s" % [name,item.get("owner_name","Student"),key," • "+pickup if owned else ""]
	if item.get("notebook",false) or supply.is_empty():
		return "Right click: read "+name.to_lower()+(" • "+pickup if owned else "")
	return pickup if owned else name

func confirm_trash(id: int) -> void:
	if not school.papers.has(id):return
	var paper: Dictionary=school.papers[id]
	if not school._official(paper) or not paper.mark.is_empty():
		school.request({"op":"trash","id":id});return
	var dialog := ConfirmationDialog.new()
	dialog.title="Recycle active assessment"
	dialog.dialog_text="Confirm recycling this active marked sheet. It will receive 0%."
	dialog.confirmed.connect(func():school.request({"op":"trash","id":id,"confirmed":true});dialog.queue_free();game.capture())
	dialog.canceled.connect(func():dialog.queue_free();game.capture())
	game.ui.add_child(dialog);game.release_mouse();dialog.popup_centered(Vector2i(520,160))

func build_campus_furniture() -> void:
	if not classroom_roots.is_empty() or school.room_bridge.registry==null:return
	var layout=preload("res://scripts/campus/academics/classroom_layout.gd")
	for id in school.room_bridge.registry.lecture_rooms():
		var room: Dictionary=school.room_bridge.room("","lecture",id)
		if room.is_empty():continue
		var furniture := Node3D.new();furniture.name=id.to_pascal_case()+"Furniture";add_child(furniture);classroom_roots.append(furniture)
		game.campus.register_content(str(room.id),furniture)
		var slots: Array=room.get("desks",layout.desks(room))
		var seats: Array=room.get("seats",[])
		for index in slots.size():
			var position: Vector3=school.room_bridge.point(slots[index])
			var desk := StaticBody3D.new();desk.position=position-Vector3(0,.035,0);desk.set_meta("role","table");desk.set_meta("label",str(room.number)+" student desk");furniture.add_child(desk)
			var hit := CollisionShape3D.new();var shape := BoxShape3D.new();shape.size=Vector3(1.7,.07,.8);hit.shape=shape;desk.add_child(hit)
			preload("res://scripts/campus/presentation/decor/lecture_rooms/classroom_furniture_skin.gd").dress_desk(desk)
			game._add_chair(school.room_bridge.point(seats[index]) if index<seats.size() else position+Vector3(0,-.895,-.9))
			var chair: Node3D=game.chairs.back()
			chair.seat_id=str(room.id)+":seat:"+str(index)
			chair.set_meta("classroom_room",str(room.id))
			chair.reparent(furniture)
			preload("res://scripts/campus/presentation/decor/lecture_rooms/classroom_chair_skin.gd").dress(chair)
		var bin := StaticBody3D.new();bin.position=layout.recycling(room);bin.set_meta("role","trash");bin.add_to_group("paper_recycling");bin.set_meta("label","Paper recycling");furniture.add_child(bin)
		var bin_hit := CollisionShape3D.new();var bin_shape := CylinderShape3D.new();bin_shape.radius=.32;bin_shape.height=.7;bin_hit.shape=bin_shape;bin_hit.position.y=.35;bin.add_child(bin_hit)
		game._cylinder(bin,Vector3(0,.35,0),.3,.7,Color("3c6670"))
	for course in ["ELM253","ETY155"]:
		var room: Dictionary=school.room_bridge.room(course,"lab")
		if room.is_empty() or str(room.id)=="ac_lab":continue
		var bin := StaticBody3D.new();bin.position=layout.recycling(room);bin.set_meta("role","trash");bin.add_to_group("paper_recycling");bin.set_meta("label","Paper recycling");add_child(bin)
		var hit := CollisionShape3D.new();var shape := CylinderShape3D.new();shape.radius=.32;shape.height=.7;hit.shape=shape;hit.position.y=.35;bin.add_child(hit)
		game._cylinder(bin,Vector3(0,.35,0),.3,.7,Color("3c6670"))
