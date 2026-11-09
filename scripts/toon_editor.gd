extends Control
signal finished(saved: bool)
const Character = preload("res://scripts/toon_character.gd")
var config: Dictionary = Character.defaults()
var library: Node
var profile_id := ""
var model: Node3D
var viewport: SubViewport
var camera: Camera3D
var stage: Node3D
var options: VBoxContainer
var name_edit: LineEdit
var message: Label
var title: Label
var tabs: HBoxContainer
var category := "Looks"
var yaw := -.22
var zoom := 3.4
var face_view := false
var dragging := false
var history: Array=[]
var future: Array=[]
var dirty := false
var rebuild_pending := false
var pose := "Idle"
const INK := Color("ecf0f7")
const MUTED := Color("9aaec4")
const ACCENT := Color("80dfc5")
func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var theme_style := Theme.new();theme_style.default_font_size=16;theme=theme_style
	for type in ["Button","LineEdit","OptionButton"]:
		for state in ["normal","hover","pressed","focus"]:
			var s := StyleBoxFlat.new();s.bg_color=Color("26364c") if state=="normal" else Color("37576a");s.set_corner_radius_all(10);s.content_margin_left=14;s.content_margin_right=14;s.content_margin_top=10;s.content_margin_bottom=10
			if state=="focus":s.set_border_width_all(2);s.border_color=ACCENT
			theme.set_stylebox(state,type,s)
		theme.set_color("font_color",type,INK)
	var background := ColorRect.new();background.color=Color("101b2b");background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);add_child(background)
	var margin := MarginContainer.new();margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left","right","top","bottom"]:margin.add_theme_constant_override("margin_"+side,24)
	add_child(margin)
	var layout := VBoxContainer.new();layout.add_theme_constant_override("separation",16);margin.add_child(layout)
	var header := HBoxContainer.new();header.add_theme_constant_override("separation",16);layout.add_child(header)
	var brand := VBoxContainer.new();brand.size_flags_horizontal=Control.SIZE_EXPAND_FILL;header.add_child(brand)
	label(brand,"MAKE YOURSELF",28,INK)
	label(brand,"LAB / VOLT  •  CHARACTER STUDIO",12,ACCENT)
	name_edit=LineEdit.new();name_edit.custom_minimum_size=Vector2(220,46);name_edit.max_length=32;name_edit.placeholder_text="Character name";name_edit.text=config.name;header.add_child(name_edit)
	name_edit.text_changed.connect(func(value):config.name=value;dirty=true)
	button(header,"Cancel",_cancel)
	var save := button(header,"Save character",_save);save.modulate=ACCENT
	var main := HBoxContainer.new();main.add_theme_constant_override("separation",20);main.size_flags_vertical=Control.SIZE_EXPAND_FILL;layout.add_child(main)
	var left := VBoxContainer.new();left.size_flags_horizontal=Control.SIZE_EXPAND_FILL;left.size_flags_stretch_ratio=1.7;main.add_child(left)
	var view := SubViewportContainer.new();view.stretch=true;view.size_flags_vertical=Control.SIZE_EXPAND_FILL;view.size_flags_horizontal=Control.SIZE_EXPAND_FILL;view.custom_minimum_size=Vector2(400,300);left.add_child(view)
	viewport=SubViewport.new();viewport.size=Vector2i(720,640);viewport.own_world_3d=true;viewport.msaa_3d=Viewport.MSAA_4X;view.add_child(viewport)
	view.gui_input.connect(_preview_input)
	stage=Node3D.new();viewport.add_child(stage)
	var env := WorldEnvironment.new();env.environment=Environment.new();env.environment.background_mode=Environment.BG_COLOR;env.environment.background_color=Color("26354b");env.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;env.environment.ambient_light_color=Color("d1dbf2");env.environment.ambient_light_energy=.45;stage.add_child(env)
	for entry in [[Vector3(-35,-35,0),Color("ffe9d3"),.85],[Vector3(-20,140,0),Color("b3e0ef"),.45]]:
		var light := DirectionalLight3D.new();light.rotation_degrees=entry[0];light.light_color=entry[1];light.light_energy=entry[2];light.shadow_enabled=true;stage.add_child(light)
	var podium := MeshInstance3D.new();var cylinder := CylinderMesh.new();cylinder.top_radius=.68;cylinder.bottom_radius=.71;cylinder.height=.10;cylinder.radial_segments=64;podium.mesh=cylinder;podium.position.y=-.04;podium.material_override=Character.material("456076");stage.add_child(podium)
	camera=Camera3D.new();camera.fov=37;stage.add_child(camera)
	var tools := HBoxContainer.new();tools.alignment=BoxContainer.ALIGNMENT_CENTER;tools.add_theme_constant_override("separation",8);left.add_child(tools)
	button(tools,"Full body",func():face_view=false;zoom=3.4;_camera())
	button(tools,"Face",func():face_view=true;zoom=1.3;_camera())
	button(tools,"↶",func():yaw-=PI/4.;_turn())
	button(tools,"↷",func():yaw+=PI/4.;_turn())
	button(tools,"Pose",func():pose="Walk" if pose=="Idle" else "Idle";_animate())
	var hint := label(left,"Drag to rotate  •  Scroll to zoom",13,MUTED);hint.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	var right := VBoxContainer.new();right.custom_minimum_size=Vector2(392,0);right.size_flags_horizontal=Control.SIZE_EXPAND_FILL;main.add_child(right)
	tabs=HBoxContainer.new();tabs.add_theme_constant_override("separation",5);right.add_child(tabs)
	for name in ["Looks","Body","Face","Hair","Outfit"]:button(tabs,name,func():category=name;_options())
	title=label(right,"",22,INK)
	var scroll := ScrollContainer.new();scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL;scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;right.add_child(scroll)
	options=VBoxContainer.new();options.size_flags_horizontal=Control.SIZE_EXPAND_FILL;options.add_theme_constant_override("separation",14);scroll.add_child(options)
	var footer := HBoxContainer.new();footer.add_theme_constant_override("separation",8);right.add_child(footer)
	button(footer,"Undo",_undo);button(footer,"Redo",_redo);button(footer,"Shuffle",_shuffle)
	message=label(layout,"Your character, your style. Changes stay private until you save.",14,MUTED)
	_rebuild();_options()
func label(parent: Node,text: String,size: int,color: Color) -> Label:
	var item := Label.new();item.text=text;item.add_theme_font_size_override("font_size",size);item.modulate=color;parent.add_child(item);return item
func button(parent: Node,text: String,callback: Callable) -> Button:
	var item := Button.new();item.text=text;item.pressed.connect(callback);parent.add_child(item);return item
func _options() -> void:
	for child in options.get_children():options.remove_child(child);child.queue_free()
	title.text={"Looks":"Find your starting look","Body":"Shape your silhouette","Face":"A little personality","Hair":"Make an impression","Outfit":"Ready for the lab"}[category]
	for tab in tabs.get_children():tab.modulate=ACCENT if tab.text==category else Color.WHITE
	match category:
		"Looks":
			label(options,"Six starting points. Every detail is editable.",13,MUTED)
			var grid := GridContainer.new();grid.columns=3;grid.add_theme_constant_override("h_separation",8);grid.add_theme_constant_override("v_separation",8);options.add_child(grid)
			for i in 6:_preset_card(grid,i)
		"Body":
			_slider("Height","height",.8,1.2);_slider("Build","build",.8,1.2);_slider("Head size","head",.8,1.2)
			for spec in [["Shoulder width","shoulders"],["Waist","waist"],["Body depth","body_depth"],["Arm length","arm_length"],["Hand size","hand_size"],["Leg length","leg_length"],["Shoe size","shoe_size"]]:_slider(spec[0],spec[1],.65,1.4)
			_color("Skin tone","skin",Character.SKINS)
		"Face":
			_choices("Expression","expression",Character.EXPRESSIONS)
			_slider("Face width","face_width",.8,1.2);_slider("Eye size","eye_size",.8,1.2);_slider("Eye spacing","eye_spacing",.8,1.2);_slider("Nose","nose",.8,1.2)
			for spec in [["Face height","face_height"],["Jaw width","jaw"],["Ear size","ear_size"],["Nose length","nose_length"],["Mouth width","mouth_width"],["Eye height","eye_height"],["Pupil size","pupil_size"],["Eyebrow thickness","brow_thickness"]]:_slider(spec[0],spec[1],.65,1.4)
			_color("Eyes","eye_color",["397a83","7c5435","537aa1","6b8759","9973ad","363747"])
			_choices("Eyewear","glasses",Character.GLASSES);_toggle("Freckles","freckles");_toggle("Earrings","earrings")
		"Hair":
			_choices("Hairstyle","hair",Character.HAIR)
			_color("Hair color","hair_color",["241d29","5c392c","9d613c","e5bd72","dadbdc","b46188","829eaf","768b6c"])
			_toggle("Short beard","beard");_toggle("Mustache","mustache")
			_slider("Hair volume","hair_volume",.65,1.4);_slider("Hair width","hair_width",.65,1.4);_slider("Fringe length","fringe_length",.65,1.4)
		"Outfit":
			_choices("Outfit","outfit",Character.OUTFITS)
			_choices("Headwear","hat",["None","Beanie","Cap","Hard hat"])
			_color("Headwear color","hat_color",["497d83","d9a747","a45f64","363d50"])
			_toggle("Bow tie","bow_tie");_toggle("Gloves","gloves");_toggle("Wristwatch","watch")
			_color("Glove color","glove_color",["e4e9e8","92b8d1","34394c","c5a476"])
			_color("Main color","top",["398e91","695f94","b36f92","ca7459","d3a354","e7eff0","34465e","65866c"])
			_color("Details & trim","accent",["f5c16c","f3e3c7","b9dcd9","d88b9e","7b8ba4","34364b"])
			_color("Trousers","pants",["293951","4e606f","7a6455","3e4948","b7aca0","574a65"])
			_color("Sneakers","shoes",["f3e9d6","34465e","c17861","7e9d92","a495ba"])
func _preset_card(parent: Node,index: int) -> void:
	var c := Character.preset(index)
	var card := VBoxContainer.new();parent.add_child(card)
	var container := SubViewportContainer.new();container.custom_minimum_size=Vector2(116,140);container.stretch=true;container.mouse_filter=Control.MOUSE_FILTER_IGNORE;card.add_child(container)
	var vp := SubViewport.new();vp.size=Vector2i(150,180);vp.own_world_3d=true;container.add_child(vp)
	var environment := WorldEnvironment.new();environment.environment=Environment.new();environment.environment.background_mode=Environment.BG_COLOR;environment.environment.background_color=Color("31465c");environment.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;environment.environment.ambient_light_energy=.8;vp.add_child(environment)
	var light := DirectionalLight3D.new();light.rotation_degrees=Vector3(-25,-30,0);light.light_energy=1.4;vp.add_child(light)
	var avatar := Character.build(c);vp.add_child(avatar)
	var cam := Camera3D.new();cam.position=Vector3(0,1.18,3.1);cam.fov=35;vp.add_child(cam);cam.look_at(Vector3(0,1.0,0))
	vp.render_target_update_mode=SubViewport.UPDATE_ONCE
	var choose := func():_remember();var old_name: String=config.name;config=c.duplicate(true);config.name=old_name;dirty=true;_rebuild()
	var overlay := Button.new();overlay.flat=true;overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);overlay.pressed.connect(choose);container.add_child(overlay)
	button(card,c.name,choose)
func _choices(text: String,key: String,values: Array) -> void:
	label(options,text,15,MUTED)
	var flow := HFlowContainer.new();flow.add_theme_constant_override("h_separation",6);options.add_child(flow)
	for value in values:
		var item := button(flow,value,func():_set_value(key,value);_options());item.modulate=ACCENT if config[key]==value else Color.WHITE
func _slider(text: String,key: String,minimum: float,maximum: float) -> void:
	var row := HBoxContainer.new();options.add_child(row)
	var title_label := label(row,text,15,MUTED);title_label.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	var value_label := label(row,"%d%%"%roundi(config[key]*100),14,INK)
	var slider := HSlider.new();slider.min_value=minimum;slider.max_value=maximum;slider.step=.01;slider.value=config[key];slider.custom_minimum_size.y=24;options.add_child(slider)
	slider.drag_started.connect(_remember)
	slider.value_changed.connect(func(value):config[key]=value;value_label.text="%d%%"%roundi(value*100);dirty=true;_schedule_rebuild())
func _color(text: String,key: String,values: Array) -> void:
	label(options,text,15,MUTED)
	var row := HFlowContainer.new();row.add_theme_constant_override("h_separation",8);options.add_child(row)
	for value in values:
		var swatch := Button.new();swatch.custom_minimum_size=Vector2(34,34);swatch.tooltip_text="#"+value
		var s := StyleBoxFlat.new();s.bg_color=Color(value);s.set_corner_radius_all(17);s.set_border_width_all(3 if config[key]==value else 1);s.border_color=Color.WHITE if config[key]==value else Color("48576b")
		swatch.add_theme_stylebox_override("normal",s);swatch.add_theme_stylebox_override("hover",s);swatch.pressed.connect(func():_set_value(key,value);_options());row.add_child(swatch)
	var custom := ColorPickerButton.new();custom.color=Color(config[key]);custom.edit_alpha=false;custom.custom_minimum_size=Vector2(40,34);custom.tooltip_text="Choose any color";row.add_child(custom)
	custom.pressed.connect(_remember)
	custom.color_changed.connect(func(value):config[key]=value.to_html(false);dirty=true;_schedule_rebuild())
func _toggle(text: String,key: String) -> void:
	var item := CheckButton.new();item.text=text;item.button_pressed=config[key];options.add_child(item);item.toggled.connect(func(value):_set_value(key,value))
func _remember() -> void:
	history.append(config.duplicate(true));if history.size()>40:history.pop_front()
	future.clear()
func _set_value(key: String,value: Variant) -> void:
	_remember();config[key]=value;dirty=true;_schedule_rebuild()
func _undo() -> void:
	if history.is_empty():return
	future.append(config.duplicate(true));config=history.pop_back();name_edit.text=config.name;dirty=true;_rebuild();_options()
func _redo() -> void:
	if future.is_empty():return
	history.append(config.duplicate(true));config=future.pop_back();name_edit.text=config.name;dirty=true;_rebuild();_options()
func _shuffle() -> void:
	_remember();var saved_name: String=config.name;config=Character.preset(randi()%6);config.name=saved_name
	config.hair=Character.HAIR[randi()%Character.HAIR.size()];config.skin=Character.SKINS[randi()%Character.SKINS.size()];config.expression=Character.EXPRESSIONS[randi()%4];dirty=true;_rebuild();_options()
func _schedule_rebuild() -> void:
	if rebuild_pending:return
	rebuild_pending=true;call_deferred("_rebuild")
func _rebuild() -> void:
	rebuild_pending=false
	if is_instance_valid(model):stage.remove_child(model);model.queue_free()
	model=Character.build(config);stage.add_child(model);_turn();_camera();_animate()
func _turn() -> void:
	if is_instance_valid(model):model.rotation.y=yaw
func _camera() -> void:
	var target := Vector3(0,1.57*float(config.height),0) if face_view else Vector3(0,.96*float(config.height),0)
	camera.position=target+Vector3(0,.08,zoom);camera.look_at(target)
func _animate() -> void:
	var player: AnimationPlayer=model.get_node("AnimationPlayer");player.play(pose)
func _preview_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index==MOUSE_BUTTON_LEFT:dragging=event.pressed
		if event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:zoom=clampf(zoom+(-.15 if event.button_index==MOUSE_BUTTON_WHEEL_UP else .15),.7,5.);_camera()
	if event is InputEventMouseMotion and event.button_mask & MOUSE_BUTTON_MASK_LEFT:yaw+=event.relative.x*.008;_turn()
func _save() -> void:
	config.name=name_edit.text;config=Character.sanitize(config)
	message.text="Saving character…"
	await get_tree().process_frame
	var error: String=library.save_character(profile_id,config)
	if error!="":message.text=error;return
	dirty=false;finished.emit(true)
func _cancel() -> void:
	if not dirty:finished.emit(false);return
	var dialog := ConfirmationDialog.new();dialog.title="Discard changes?";dialog.dialog_text="Your saved character will stay unchanged.";dialog.ok_button_text="Discard changes";dialog.confirmed.connect(func():finished.emit(false));dialog.canceled.connect(dialog.queue_free);add_child(dialog);dialog.popup_centered()

