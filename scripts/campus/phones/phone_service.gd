extends Node3D
const Photos=preload("res://scripts/campus/phones/photo_library.gd")
const Tiers=preload("res://scripts/campus/phones/phone_tiers.gd")
const Icons=preload("res://scripts/ui/design_system/widgets.gd")
const Tokens=preload("res://scripts/ui/design_system/tokens.gd")
const HELD_PHONE_RENDER_LAYER:=19
var game: Node
var held: Node3D
var held_screen: MeshInstance3D
var powered_off := {}
var browser_bookmarks := {}
var remote_phone_models := {}
var phone_frame_at := {}
var last_phone_frame := 0
const PHONE_WIRE_SIZE := Vector2i(48,84)
const PHONE_WIRE_BYTES := PHONE_WIRE_SIZE.x*PHONE_WIRE_SIZE.y*3
var layer: CanvasLayer
var panel: PanelContainer
var content: VBoxContainer
var status: Label
var backdrop: ColorRect
var flash: ColorRect
var flash_tween: Tween
var app_title: Label
var phone_clock: Label
var battery_label: Label
var next_battery_note := 0
var volume_row: HBoxContainer
var volume_slider: HSlider
var volume_value: Label
var app_scroll: ScrollContainer
var browser_host: VBoxContainer
var current_id:=""
var generation:=0
var capturing:=false
var camera_phone_id:=""
var camera_hint: Label
var comm: Node
var current_app:="Home"
var browser_surface: VBoxContainer
var browser_phone_id: String=""
var placed_preview: ImageTexture
var next_preview_ms: int=0
var phone_volumes: Dictionary={}
var last_apps: Dictionary={}
var idle_view: SubViewport
var contact:=0
var message_draft:=""
var call_notice: Label
const PHOTOS_PER_PAGE:=6
var photo_page:=0
var classroom_open:={}
var classroom_report_at:={}
var classroom_phone_strikes:={}
var phone_report_clock:=0.0
var phone_prune_clock:=0.0
var teacher_handoffs:={}
var handed_phone_id:=""

func build(owner: Node) -> void:
	game=owner
	held=Node3D.new();game.camera.add_child(held);held.position=Vector3(.30,-.24,-.57);held.rotation=Vector3(-.12,-.13,-.12)
	held_screen=_build_handset(held,true)
	layer=CanvasLayer.new();layer.layer=45;add_child(layer)
	comm=preload("res://scripts/campus/phones/phone_network.gd").new();comm.name="PhoneNetwork";add_child(comm);comm.build(game);comm.changed.connect(_communications_changed)
	call_notice=Label.new();call_notice.position=Vector2(16,280);call_notice.add_theme_font_size_override("font_size",18);call_notice.add_theme_color_override("font_color",Color("a5e9d7"));call_notice.add_theme_constant_override("outline_size",5);layer.add_child(call_notice);call_notice.hide()
	_build_phone_ui()
	game.session.leaving.connect(close.bind(false))
	game.session.restarted.connect(close.bind(false))
	game.session.roster_changed.connect(_prune_classroom_open)
	game.session.roster_changed.connect(_prune_teacher_handoffs)
	game.session.restarted.connect(_clear_classroom_open)
	game.session.leaving.connect(_clear_handoff_local)
	game.session.restarted.connect(_clear_handoff_local)

func _build_phone_ui() -> void:
	backdrop=ColorRect.new()
	backdrop.color=Color("020c17a8")
	layer.add_child(backdrop)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.hide()
	panel=PanelContainer.new()
	panel.theme=preload("res://scripts/ui/design_system/theme.gd").create()
	var skin:=Tokens.surface(Color("081b2b"),Color("365a70"),13)
	skin.set_corner_radius_all(27)
	skin.set_border_width_all(2)
	skin.shadow_color=Color("020915cf")
	skin.shadow_size=12
	panel.add_theme_stylebox_override("panel",skin)
	layer.add_child(panel)
	panel.hide()
	var shell:=VBoxContainer.new()
	shell.add_theme_constant_override("separation",6)
	panel.add_child(shell)
	var top:=HBoxContainer.new()
	shell.add_child(top)
	phone_clock=Label.new()
	phone_clock.custom_minimum_size.x=50
	phone_clock.add_theme_font_size_override("font_size",13)
	top.add_child(phone_clock)
	app_title=Label.new()
	app_title.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	app_title.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	app_title.add_theme_color_override("font_color",Tokens.MUTED)
	top.add_child(app_title)
	battery_label=Label.new()
	battery_label.add_theme_font_size_override("font_size",13)
	top.add_child(battery_label)
	var audio:=_button("",func():volume_row.visible=not volume_row.visible)
	audio.icon=Icons.icon("volume")
	audio.text="♪" if audio.icon==null else ""
	audio.tooltip_text="Phone volume"
	audio.accessibility_name="Phone volume"
	audio.custom_minimum_size=Vector2(38,30)
	top.add_child(audio)
	var off:=_button("",close)
	off.icon=Icons.icon("close")
	off.icon_alignment=HORIZONTAL_ALIGNMENT_CENTER
	off.custom_minimum_size=Vector2(50,30)
	off.tooltip_text="Close phone"
	off.accessibility_name="Close phone"
	top.add_child(off)
	var power:=_button("⏻",func():_toggle_power(current_id))
	power.tooltip_text="Turn phone off"
	power.accessibility_name="Turn phone off"
	power.custom_minimum_size=Vector2(36,30)
	top.add_child(power)
	volume_row=HBoxContainer.new()
	volume_row.hide()
	shell.add_child(volume_row)
	var volume_label:=Label.new()
	volume_label.text="Volume"
	volume_row.add_child(volume_label)
	volume_slider=HSlider.new()
	volume_slider.max_value=100
	volume_slider.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	volume_slider.accessibility_name="Phone volume"
	volume_row.add_child(volume_slider)
	volume_value=Label.new()
	volume_value.custom_minimum_size.x=44
	volume_value.horizontal_alignment=HORIZONTAL_ALIGNMENT_RIGHT
	volume_row.add_child(volume_value)
	volume_slider.value_changed.connect(func(value: float):
		if current_id.is_empty():return
		phone_volumes[current_id]=int(value)
		volume_value.text="%d%%"%int(value)
		update_placed_speaker())
	status=Label.new()
	status.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	status.add_theme_color_override("font_color",Tokens.MUTED)
	shell.add_child(status)
	app_scroll=ScrollContainer.new()
	app_scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	app_scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL
	shell.add_child(app_scroll)
	content=VBoxContainer.new()
	content.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation",10)
	app_scroll.add_child(content)
	browser_host=VBoxContainer.new()
	browser_host.size_flags_vertical=Control.SIZE_EXPAND_FILL
	shell.add_child(browser_host)
	browser_host.hide()
	var home:=_button("",func():_switch("Home"))
	home.tooltip_text="Home"
	home.accessibility_name="Home"
	home.size_flags_horizontal=Control.SIZE_SHRINK_CENTER
	home.custom_minimum_size=Vector2(39,39)
	for state in ["normal","hover","pressed"]:
		var ring:=Tokens.surface(Color("132b3e") if state=="normal" else Color("28566b"),Color("6d92a4"),0)
		ring.set_border_width_all(2)
		ring.set_corner_radius_all(24)
		home.add_theme_stylebox_override(state,ring)
	shell.add_child(home)
	get_viewport().size_changed.connect(_layout_phone)
	panel.minimum_size_changed.connect(_layout_phone,CONNECT_DEFERRED)
	camera_hint=Label.new()
	camera_hint.theme=panel.theme
	camera_hint.add_theme_stylebox_override("normal",Tokens.surface(Color("081b2b"),Color("365a70"),14))
	camera_hint.text="Left-click to take a photo   ·   Esc or right-click to return"
	camera_hint.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	camera_hint.mouse_filter=Control.MOUSE_FILTER_IGNORE
	layer.add_child(camera_hint)
	camera_hint.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	camera_hint.offset_top=76
	camera_hint.hide()
	flash=ColorRect.new()
	flash.mouse_filter=Control.MOUSE_FILTER_IGNORE
	layer.add_child(flash)
	flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	flash.hide()

func _layout_phone() -> void:
	if not is_instance_valid(panel):return
	var bounds:=get_viewport().get_visible_rect().size
	var target:=Vector2(minf(620 if current_app=="Browser" else 400,bounds.x-28),minf(700,bounds.y-24))
	panel.size=target
	panel.position=(bounds-target)*.5

func _box(parent: Node3D,at: Vector3,size: Vector3,color: Color,first_person := true) -> void:
	var mesh:=BoxMesh.new();mesh.size=size
	var instance:=MeshInstance3D.new();instance.mesh=mesh;instance.position=at
	instance.set_layer_mask_value(1,not first_person)
	instance.set_layer_mask_value(HELD_PHONE_RENDER_LAYER,first_person)
	instance.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material:=StandardMaterial3D.new();material.albedo_color=color;material.roughness=.45;instance.material_override=material;parent.add_child(instance)

func _build_handset(parent: Node3D,first_person: bool) -> MeshInstance3D:
	_box(parent,Vector3.ZERO,Vector3(.105,.195,.012),Color("243943"),first_person)
	_box(parent,Vector3(0,.088,.007),Vector3(.024,.003,.002),Color("95aab3"),first_person)
	_box(parent,Vector3(.053,.046,0),Vector3(.004,.024,.004),Color("638797"),first_person)
	var screen:=MeshInstance3D.new()
	var quad:=QuadMesh.new()
	quad.size=Vector2(.094,.156)
	screen.mesh=quad
	screen.position=Vector3(0,.004,.007)
	screen.set_layer_mask_value(1,not first_person)
	screen.set_layer_mask_value(HELD_PHONE_RENDER_LAYER,first_person)
	screen.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var glass:=StandardMaterial3D.new()
	glass.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	screen.material_override=glass
	parent.add_child(screen)
	var home:=MeshInstance3D.new()
	var button:=CylinderMesh.new()
	button.top_radius=.005
	button.bottom_radius=.005
	button.height=.001
	home.mesh=button
	home.rotation.x=PI/2
	home.position=Vector3(0,-.087,.007)
	home.set_layer_mask_value(1,not first_person)
	home.set_layer_mask_value(HELD_PHONE_RENDER_LAYER,first_person)
	var trim:=StandardMaterial3D.new()
	trim.albedo_color=Color("7597a3")
	home.material_override=trim
	parent.add_child(home)
	return screen

func is_powered(id: String) -> bool:
	return not id.is_empty() and not powered_off.has(id) and (not is_instance_valid(game.device_charging) or game.device_charging.percent("phone",id)>0)

func _toggle_power(id: String) -> void:
	if id.is_empty():return
	if game.device_charging.percent("phone",id)<=0:
		game.ui.log_message("Phone battery is empty. Connect it to a charger in M110.")
		return
	if powered_off.has(id):
		powered_off.erase(id)
		var model:=_placed_model(id)
		if is_instance_valid(model):_paint_screen(model.get_meta("phone_screen"),idle_preview())
		game.ui.log_message("Phone on.")
	else:
		powered_off[id]=true
		if browser_phone_id==id:_close_browser()
		browser_bookmarks.erase(id)
		last_apps.erase(id)
		var model:=_placed_model(id)
		if is_instance_valid(model):_paint_screen(model.get_meta("phone_screen"),null)
		if panel.visible:close()
		game.ui.log_message("Phone off.")

func _paint_screen(screen: MeshInstance3D, texture: Texture2D) -> void:
	var glass: StandardMaterial3D=screen.material_override
	var tint:=Color.WHITE if is_instance_valid(texture) else Color("080f14")
	if glass.albedo_texture==texture and glass.albedo_color==tint:return
	glass.albedo_texture=texture
	glass.albedo_color=tint

func _button(text: String,action: Callable) -> Button:
	var result:=Button.new();result.text=text;result.focus_mode=Control.FOCUS_ALL;result.pressed.connect(action);return result

func selected() -> String:
	var active: int=game.hotbar.active
	if active not in range(game.hotbar.slots.size()):return ""
	var item: Dictionary=game.hotbar.slots[active]
	if item.get("kind","")!="smartphone":return ""
	var id: String=str(item.get("id",""))
	return id if id!=handed_phone_id and not _locally_in_custody(id) and not _phone_record(id).is_empty() else ""

func _locally_in_custody(id: String) -> bool:
	var custody: Variant=game.electronics.profile.data.get("dorm",{}).get("teacher_phone_custody",{})
	return custody is Dictionary and str(custody.get("id",""))==id

func _phone_record(id: String) -> Dictionary:
	if id.is_empty() or not is_instance_valid(game) or not is_instance_valid(game.school):return {}
	var dorm: Dictionary=game.electronics.profile.data.get("dorm",{})
	if str(dorm.get("owner",""))!=str(game.school.local_identity):return {}
	var phone: Dictionary=dorm.get("smartphones",{}).get(id,{})
	if phone.get("location","")!="hotbar" or "phone:"+id not in dorm.get("carry_items",[]) or not Tiers.TIERS.has(phone.get("tier","")):return {}
	return phone

func _current_phone_open() -> bool:
	return is_instance_valid(panel) and panel.visible and _phone_in_reach(current_id)

func _placed_model(id: String) -> Node3D:
	if id.is_empty() or not is_instance_valid(game.personal_placement):return null
	return game.personal_placement.models.get(game.personal_placement.key_for(multiplayer.get_unique_id(),"phone:"+id))

func _phone_in_reach(id: String) -> bool:
	if id.is_empty():return false
	if selected()==id:return true
	var model:=_placed_model(id)
	var feet: Vector3=game.player.global_position
	return is_instance_valid(model) and feet.distance_to(model.global_position)<=3.0 and not _phone_record(id).is_empty()

func _process(_delta: float) -> void:
	var id:=selected()
	held.visible=not id.is_empty() and game.front.in_game and game.player.enabled and not panel.visible
	if camera_phone_id!="" and (camera_phone_id!=id or not game.front.in_game or not game.player.enabled or Input.mouse_mode!=Input.MOUSE_MODE_CAPTURED):
		_leave_camera()
	if panel.visible and (not _phone_in_reach(current_id) or not game.front.in_game):close()
	if is_instance_valid(browser_surface):
		if (id!=browser_phone_id and not is_instance_valid(_placed_model(browser_phone_id))) or not is_powered(browser_phone_id):
			browser_bookmarks[browser_phone_id]=browser_surface.parked_tabs()
			_close_browser()
	if is_instance_valid(browser_surface) and not panel.visible:
		_update_phone_preview()
	if panel.visible:
		if not is_powered(current_id):close()
		else:
			battery_label.text="%d%%"%game.device_charging.percent("phone",current_id)
			battery_label.tooltip_text=game.device_charging.label("phone",current_id)
	var active_id:=id if not id.is_empty() else current_id if panel.visible else browser_phone_id
	var now:=Time.get_ticks_msec()
	if is_powered(active_id) and game.front.in_game and now>=next_battery_note:
		next_battery_note=now+1500
		game.device_charging.use_phone(active_id)
	var display: Texture2D=null
	if is_powered(id):
		display=browser_surface.preview_texture() if is_instance_valid(browser_surface) and browser_phone_id==id else null
		if display==null:display=idle_preview()
	if held.visible:_paint_screen(held_screen,display)
	_publish_handset(id,display)
	for peer in remote_phone_models.keys():
		var record: Dictionary=remote_phone_models[peer]
		if not is_instance_valid(record.model) or Time.get_ticks_msec()-int(record.at)>1000:
			if is_instance_valid(record.model):record.model.queue_free()
			remote_phone_models.erase(peer)
	phone_report_clock+=_delta
	if _current_phone_open() and phone_report_clock>=1.5:
		phone_report_clock=0.0
		_report_classroom_open(true,current_id)
	if multiplayer.is_server():
		phone_prune_clock+=_delta
		if phone_prune_clock>=.5:
			phone_prune_clock=0.0
			_prune_classroom_open()
			_prune_teacher_handoffs()

func route(event: InputEvent) -> bool:
	if panel.visible:
		if event is InputEventKey and event.pressed and not event.echo and event.keycode==KEY_ESCAPE:close();return true
		return event is InputEventKey or event is InputEventMouse
	if selected().is_empty() or not game.front.in_game or Input.mouse_mode!=Input.MOUSE_MODE_CAPTURED:return false
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode==KEY_O:
		_toggle_power(selected())
		return true
	if not is_powered(selected()):return false
	if camera_phone_id.is_empty() and event is InputEventMouseButton and is_instance_valid(game.current_target) and game.current_target.get_meta("role","")=="placed_personal_item":return false
	if camera_phone_id==selected() and event is InputEventKey and event.pressed and not event.echo and event.keycode==KEY_ESCAPE:
		open();return true
	if event is InputEventKey and event.pressed and not event.echo and event.keycode==KEY_P:
		capture();return true
	if event is InputEventMouseButton and event.pressed:
		if event.button_index==MOUSE_BUTTON_LEFT:capture();return true
		if event.button_index==MOUSE_BUTTON_RIGHT:open();return true
	return false

func open() -> void:
	if not game.front.in_game or not game.player.enabled:return
	_open_phone(selected())

func open_placed(id: String) -> void:
	if game.front.in_game and game.player.enabled and _phone_in_reach(id):_open_phone(id)

func _open_phone(id: String) -> void:
	if id.is_empty():return
	if not is_powered(id):_toggle_power(id)
	if not is_powered(id):return
	current_id=id
	_leave_camera()
	photo_page=0
	volume_row.hide()
	volume_slider.set_value_no_signal(_phone_volume(id))
	volume_value.text="%d%%"%_phone_volume(id)
	backdrop.show();panel.show();game.release_mouse()
	_switch(str(last_apps.get(id,"Home")))
	phone_report_clock=0.0
	_report_classroom_open(true,current_id)

func close(keep_browser := true) -> void:
	_leave_camera()
	generation+=1
	if not keep_browser or not game.front.in_game:
		_close_browser()
		last_apps.clear()
	var previously_open: bool=is_instance_valid(panel) and panel.visible and not current_id.is_empty()
	var was_visible:=panel.visible if is_instance_valid(panel) else false
	if is_instance_valid(panel):
		for child in panel.get_children():
			if child is ConfirmationDialog:child.hide();child.queue_free()
		panel.hide()
		backdrop.hide()
	current_id=""
	if previously_open:_report_classroom_open(false,"")
	contact=0;message_draft="";photo_page=0
	if was_visible and is_instance_valid(game.front) and game.front.in_game:game.capture()

## Only the authenticated sender can report their own local UI state. The
## host checks the carried phone and classroom before any teacher observation.
func _report_classroom_open(opened: bool,id: String) -> void:
	if not is_instance_valid(game):return
	if multiplayer.is_server():_apply_classroom_open(multiplayer.get_unique_id(),opened,id)
	elif game.session.online:_phone_open_request.rpc_id(1,opened,id)

@rpc("any_peer","call_remote","reliable",7)
func _phone_open_request(opened: bool,id: String) -> void:
	if multiplayer.is_server():_apply_classroom_open(multiplayer.get_remote_sender_id(),opened,id)

func _classroom_context(peer: int) -> Dictionary:
	if not game.session.roster.has(peer):return {}
	var identity: String=game.dorm_interactions.authenticated_identity(peer)
	if identity.is_empty() or str(game.school.identities.get(peer,""))!=identity:return {}
	var point: Vector3=game.player.global_position if peer==multiplayer.get_unique_id() else game.session.poses.get(peer,{}).get("position",Vector3.INF)
	if not point.is_finite():return {}
	var room: String=str(game.campus.registry.locate(point))
	var activity: Dictionary=game.lecture_classes.classes.get(room,{})
	if activity.get("phase","") not in ["lesson","assignment"] or not game.lecture_classes._inside(peer,room):return {}
	if int(activity.get("students",{}).get(identity,{}).get("peer",0))!=peer:return {}
	var events: Node=game.lecture_classes.classroom_events
	if not is_instance_valid(events) or not bool(events.enabled):return {}
	return {"identity":identity,"room":room,"point":point,"class_id":str(activity.get("id","")),"teacher":str(activity.get("teacher","")),"phase":str(activity.phase)}

func _valid_classroom_phone(peer: int,id: String,identity: String) -> bool:
	if id.length()!=32 or not id.is_valid_hex_number() or id!=id.to_lower():return false
	var dorm: Dictionary=game.dorm_interactions._profile(identity).get("dorm",{})
	var phone: Dictionary=dorm.get("smartphones",{}).get(id,{})
	return phone.get("location","")=="hotbar" and ("phone:"+id) in dorm.get("carry_items",[]) and Tiers.TIERS.has(phone.get("tier",""))

func _saved_custody(identity: String) -> Dictionary:
	var state: Variant=game.dorm_interactions._profile(identity).get("dorm",{}).get("teacher_phone_custody",{})
	return state if state is Dictionary else {}

func _commit_custody(peer: int,identity: String,state: Dictionary) -> bool:
	var current: Dictionary=game.dorm_interactions._profile(identity)
	if current.is_empty():return false
	var next: Dictionary=current.duplicate(true)
	if state.is_empty():next.dorm.erase("teacher_phone_custody")
	else:next.dorm.teacher_phone_custody=state.duplicate(true)
	var result: Dictionary=game.dorm_interactions._commit_world_inventory(peer,identity,next)
	return bool(result.get("ok",false))

func _apply_classroom_open(peer: int,opened: bool,id: String) -> void:
	if not multiplayer.is_server() or not game.session.roster.has(peer):return
	if not opened:
		classroom_open.erase(peer)
		return
	var context: Dictionary=_classroom_context(peer)
	if str(_saved_custody(str(context.get("identity",""))).get("id",""))==id:
		classroom_open.erase(peer)
		return
	if context.is_empty() or not _valid_classroom_phone(peer,id,str(context.identity)):
		classroom_open.erase(peer)
		return
	var now:=Time.get_ticks_msec()/1000.0
	classroom_open[peer]={"id":id,"room":context.room,"class_id":context.class_id,"teacher":context.teacher,"phase":context.phase,"until":now+4.0}
	if now<float(classroom_report_at.get(peer,0.0)):return
	classroom_report_at[peer]=now+15.0
	if not game.faculty.report_event(peer,str(context.room),"phone_use",context.point,.55):return
	var strikes: Dictionary=classroom_phone_strikes.get(peer,{})
	var count: int=int(strikes.get("count",0))+1 if now-float(strikes.get("at",0.0))<120.0 and str(strikes.get("class_id",""))==str(context.class_id) else 1
	classroom_phone_strikes[peer]={"count":count,"at":now,"class_id":str(context.class_id)}
	if count>=2:
		var custody: Dictionary={"id":id,"room":str(context.room),"teacher":str(context.teacher)}
		if _commit_custody(peer,str(context.identity),custody):
			teacher_handoffs[peer]=custody
			classroom_open.erase(peer)
			classroom_phone_strikes.erase(peer)
			_sync_teacher_handoff(peer,id)

func _prune_classroom_open() -> void:
	if not multiplayer.is_server() or not is_instance_valid(game):return
	var now:=Time.get_ticks_msec()/1000.0
	for peer in classroom_open.keys():
		var state: Dictionary=classroom_open[peer]
		var context: Dictionary=_classroom_context(int(peer))
		if now>float(state.until) or context.is_empty() or str(context.room)!=str(state.room) or str(context.class_id)!=str(state.class_id) or str(context.teacher)!=str(state.teacher) or str(context.phase)!=str(state.phase) or not _valid_classroom_phone(int(peer),str(state.id),str(context.get("identity",""))):classroom_open.erase(peer)
	for peer in classroom_report_at.keys():
		if not game.session.roster.has(peer):classroom_report_at.erase(peer)
	for peer in classroom_phone_strikes.keys():
		if not game.session.roster.has(peer) or now-float(classroom_phone_strikes[peer].get("at",0.0))>=120.0:classroom_phone_strikes.erase(peer)

func _clear_classroom_open() -> void:
	classroom_open.clear();classroom_report_at.clear();classroom_phone_strikes.clear();phone_report_clock=0.0;phone_prune_clock=0.0
	teacher_handoffs.clear();handed_phone_id=""

## Custody is saved with the owner's profile. The phone stays in the owner's
## inventory so a failed save never loses it; host phone actions are blocked.
func teacher_handoff(peer: int,room: String,teacher: String,reclaim: bool,phone_id: String="") -> String:
	if not multiplayer.is_server():return "The teacher cannot handle the phone now."
	var identity: String=game.dorm_interactions.authenticated_identity(peer)
	if identity.is_empty():return "Your school profile is unavailable."
	var lease: Dictionary=_saved_custody(identity)
	if reclaim:
		if lease.is_empty():return "There is no phone to return here."
		if not _commit_custody(peer,identity,{}):return "The phone could not be returned. Try again."
		teacher_handoffs.erase(peer)
		_sync_teacher_handoff(peer,"")
		return "Your phone is back. Keep it away during the lesson."
	if not lease.is_empty():return "A teacher is holding your phone. Ask a teacher for it back."
	var context: Dictionary=_classroom_context(peer)
	if context.is_empty() or str(context.room)!=room or str(context.teacher)!=teacher:return "You must be signed into this class to hand over a phone."
	if not _valid_classroom_phone(peer,phone_id,str(context.identity)):return "Select an owned phone in your hotbar first."
	lease={"id":phone_id,"room":room,"teacher":teacher}
	if not _commit_custody(peer,identity,lease):return "The teacher could not save your phone handoff. Try again."
	teacher_handoffs[peer]=lease
	classroom_open.erase(peer)
	_sync_teacher_handoff(peer,phone_id)
	return "You handed your phone to the teacher. Ask a teacher for it back, even after rejoining."

func _sync_teacher_handoff(peer: int,id: String) -> void:
	if peer==multiplayer.get_unique_id():_teacher_handoff_state(id)
	elif game.session.online and game.session.peer_connected_now(peer):_teacher_handoff_state.rpc_id(peer,id)

@rpc("authority","call_remote","reliable",7)
func _teacher_handoff_state(id: String) -> void:
	if id!=handed_phone_id and not id.is_empty() and is_instance_valid(game):game.ui.log_message("A teacher is holding your phone. Ask a teacher for it back.")
	handed_phone_id=id
	if not id.is_empty() and is_instance_valid(panel) and panel.visible and current_id==id:close()

func _release_teacher_handoff(peer: int) -> void:
	if not teacher_handoffs.has(peer):return
	teacher_handoffs.erase(peer)
	_sync_teacher_handoff(peer,"")

func release_class_handoffs(room: String,class_id: String) -> void:
	pass # Saved custody survives class transitions.

func _prune_teacher_handoffs() -> void:
	if not multiplayer.is_server():return
	for peer in game.session.roster:
		var identity: String=game.dorm_interactions.authenticated_identity(int(peer))
		var lease: Dictionary=_saved_custody(identity) if not identity.is_empty() else {}
		var id: String=str(lease.get("id",""))
		var previous: String=str(teacher_handoffs.get(peer,{}).get("id",""))
		if id.is_empty():teacher_handoffs.erase(peer)
		else:teacher_handoffs[peer]=lease
		if previous!=id:_sync_teacher_handoff(int(peer),id)

func _clear_handoff_local() -> void:
	handed_phone_id=""

func capture() -> void:
	if capturing:return
	var id:=selected();var dorm: Dictionary=game.electronics.profile.data.get("dorm",{})
	var phone: Dictionary=_phone_record(id)
	if phone.is_empty() or not is_powered(id):return
	var owner: String=str(dorm.owner)
	var capture_generation:=generation
	capturing=true
	# Render the shared world through a separate camera so HUD and chat never
	# appear in saved photos and remain visible to the player during capture.
	var screen_size: Vector2=get_viewport().get_visible_rect().size
	var capture_scale:=minf(1.0,minf(1920.0/screen_size.x,1080.0/screen_size.y))
	var view:=SubViewport.new();view.size=Vector2i(maxi(1,roundi(screen_size.x*capture_scale)),maxi(1,roundi(screen_size.y*capture_scale)));view.world_3d=get_viewport().world_3d
	view.render_target_update_mode=SubViewport.UPDATE_ALWAYS;add_child(view)
	var camera:=Camera3D.new();view.add_child(camera);camera.global_transform=game.camera.global_transform
	camera.cull_mask=game.camera.cull_mask
	camera.set_cull_mask_value(HELD_PHONE_RENDER_LAYER,false)
	camera.projection=game.camera.projection;camera.fov=game.camera.fov;camera.near=game.camera.near;camera.far=game.camera.far;camera.current=true
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image: Image=view.get_texture().get_image()
	view.queue_free()
	capturing=false
	if capture_generation!=generation or selected()!=id or not game.front.in_game or str(game.electronics.profile.data.get("dorm",{}).get("owner",""))!=owner:return
	var result:=Photos.capture(owner,id,image,int(Tiers.TIERS[phone.tier].storage_bytes))
	game.ui.log_message(str(result.get("error","Photo saved.")))
	if not result.has("error"):
		if is_instance_valid(flash_tween):flash_tween.kill()
		flash.color=Color(1,1,1,.66)
		flash.show()
		flash_tween=create_tween()
		flash_tween.tween_property(flash,"color:a",0.0,.22).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		flash_tween.tween_callback(flash.hide)
		game.sfx.play("shutter")

func _switch(app: String) -> void:
	if not is_instance_valid(panel) or not panel.visible:return
	generation+=1;var request:=generation
	current_app=app
	last_apps[current_id]=app
	var phone: Dictionary=_phone_record(current_id)
	if phone.is_empty():close();return
	var resume_browser:=app=="Browser" and is_instance_valid(browser_surface) and browser_phone_id==current_id
	if not resume_browser:_close_browser()
	_clear_app()
	browser_host.hide()
	app_scroll.show()
	app_title.text="" if app=="Home" else app
	phone_clock.text=Time.get_time_string_from_system().left(5)
	status.text=""
	status.hide()
	_layout_phone()
	if app=="Home":_home_screen();return
	var delay: int=int(Tiers.TIERS[phone.tier].delay_ms)
	if delay>0:
		status.text="Opening %s…"%app
		status.show()
		await get_tree().create_timer(float(delay)/1000.0).timeout
	if request!=generation or not _current_phone_open():return
	status.hide()
	if app=="Calculator":
		var calculator:=preload("res://scripts/scientific_calculator.gd").new()
		calculator.campus_style=true
		content.add_child(calculator)
	elif app=="Messages":_messages()
	elif app=="Browser":
		if resume_browser:
			app_scroll.hide()
			browser_host.show()
			return
		var owner_id:=str(game.electronics.profile.data.get("dorm",{}).get("owner",""))
		var photos:=Photos.list(owner_id,current_id)
		var choices: Array=[]
		if not photos.has("error"):
			for photo in photos.photos:choices.append({"kind":"photo","name":str(photo.id)+".jpg","id":str(photo.id),"bytes":int(photo.bytes)})
		app_scroll.hide()
		browser_host.show()
		browser_surface=preload("res://scripts/campus/computers/browser_surface.gd").new()
		browser_surface.size_flags_vertical=Control.SIZE_EXPAND_FILL
		browser_host.add_child(browser_surface)
		browser_surface.game=game
		browser_phone_id=current_id
		browser_surface.speaker_world=game
		update_placed_speaker()
		browser_surface.configure("phone",current_id,current_id,choices)
		if browser_bookmarks.has(current_id):
			browser_surface.restore_parked_tabs(browser_bookmarks[current_id])
			browser_bookmarks.erase(current_id)
		browser_surface.attachment_loader=_browser_photo_attachment
	else:_gallery(phone)

func _clear_app() -> void:
	for child in content.get_children():
		content.remove_child(child)
		child.queue_free()
	app_scroll.scroll_vertical=0

func _close_browser() -> void:
	if not is_instance_valid(browser_surface):return
	var model:=_placed_model(browser_phone_id)
	if is_instance_valid(model):
		var screen: MeshInstance3D=model.get_meta("phone_screen")
		_paint_screen(screen,idle_preview() if is_powered(browser_phone_id) else null)
	browser_surface.close_session()
	browser_surface.queue_free()
	browser_surface=null
	browser_phone_id=""
	placed_preview=null
	next_preview_ms=0

func update_placed_speaker() -> void:
	if not is_instance_valid(browser_surface):return
	var model:=_placed_model(browser_phone_id)
	var audible:=is_instance_valid(model) or selected()==browser_phone_id or (panel.visible and current_id==browser_phone_id)
	browser_surface.set_speaker_volume(_phone_volume(browser_phone_id) if audible else 0)
	if is_instance_valid(model):
		browser_surface.move_speaker(model.global_position+Vector3.UP*.02)
	else:
		placed_preview=null
		browser_surface.move_speaker(game.camera.global_position)

func _update_phone_preview() -> void:
	var model:=_placed_model(browser_phone_id)
	if not is_instance_valid(model):
		update_placed_speaker()
		return
	var now:=Time.get_ticks_msec()
	if now<next_preview_ms or DisplayServer.get_name()=="headless":return
	var screen: MeshInstance3D=model.get_meta("phone_screen")
	var origin:=screen.global_position
	var camera: Camera3D=game.camera
	var screens: Dictionary=game.ui.graphics_controller.screen_previews
	var interval: int=game.computers.local_screen_interval(camera.global_position.distance_to(origin),screens)
	if interval==0 or camera.global_position.y<=origin.y or not camera.is_position_in_frustum(origin):return
	var ray:=PhysicsRayQueryParameters3D.create(camera.global_position,origin,1)
	var hit:=get_world_3d().direct_space_state.intersect_ray(ray)
	if not hit.is_empty():return
	next_preview_ms=now+interval
	var source: Texture2D=browser_surface.preview_texture()
	if source==null:return
	var frame:=source.get_image()
	if frame==null or frame.is_empty():return
	var pixels:=Vector2i(Vector2(128,224)*float(screens.phone_scale))
	frame.resize(pixels.x,pixels.y,Image.INTERPOLATE_BILINEAR)
	if placed_preview==null or placed_preview.get_size()!=Vector2(pixels):placed_preview=ImageTexture.create_from_image(frame)
	else:placed_preview.update(frame)
	screen.material_override.albedo_texture=placed_preview
	screen.material_override.albedo_color=Color.WHITE

func _phone_volume(id: String) -> int:
	return int(phone_volumes.get(id,35))

func _publish_handset(id: String,display: Texture2D) -> void:
	if not game.session.online or not game.front.in_game or id.is_empty():return
	var now:=Time.get_ticks_msec()
	if now-last_phone_frame<200:return
	var viewers:=false
	for peer in game.session.poses:
		if peer!=multiplayer.get_unique_id() and game.player.global_position.distance_squared_to(game.session.poses[peer].get("position",Vector3.INF))<=25.0:
			viewers=true
			break
	if not viewers:return
	last_phone_frame=now
	var pixels:=PackedByteArray()
	if is_instance_valid(display) and DisplayServer.get_name()!="headless":
		var frame:=display.get_image()
		if frame!=null and not frame.is_empty():
			frame.resize(PHONE_WIRE_SIZE.x,PHONE_WIRE_SIZE.y,Image.INTERPOLATE_BILINEAR)
			frame.convert(Image.FORMAT_RGB8)
			pixels=frame.get_data().compress(FileAccess.COMPRESSION_FASTLZ)
			if pixels.size()>PHONE_WIRE_BYTES:pixels.clear()
	if multiplayer.is_server():_forward_handset(multiplayer.get_unique_id(),id,is_powered(id),pixels)
	else:_send_handset.rpc_id(1,id,is_powered(id),pixels)

@rpc("any_peer","call_remote","unreliable",6)
func _send_handset(id: String,powered: bool,pixels: PackedByteArray) -> void:
	if multiplayer.is_server():_forward_handset(multiplayer.get_remote_sender_id(),id,powered,pixels)

func _forward_handset(peer: int,id: String,powered: bool,pixels: PackedByteArray) -> void:
	var now:=Time.get_ticks_msec()
	if now-int(phone_frame_at.get(peer,-1000))<175 or id.length()!=32 or not id.is_valid_hex_number() or pixels.size()>PHONE_WIRE_BYTES:return
	phone_frame_at[peer]=now
	if not game.session.roster.has(peer) or not _valid_classroom_phone(peer,id,game.dorm_interactions.authenticated_identity(peer)):return
	if game.personal_placement.is_placed(peer,"phone:"+id):return
	var origin: Vector3=game.session.poses.get(peer,{}).get("position",Vector3.INF)
	for target in game.session.roster:
		if target==peer:continue
		var at: Vector3=game.session.poses.get(target,{}).get("position",Vector3.INF)
		if at.distance_squared_to(origin)>25.0:continue
		if target==multiplayer.get_unique_id():_show_remote_handset(peer,powered,pixels)
		elif game.session.peer_connected_now(target):_receive_handset.rpc_id(target,peer,powered,pixels)

@rpc("authority","call_remote","unreliable",6)
func _receive_handset(peer: int,powered: bool,pixels: PackedByteArray) -> void:
	if multiplayer.get_remote_sender_id()==1:_show_remote_handset(peer,powered,pixels)

func _show_remote_handset(peer: int,powered: bool,pixels: PackedByteArray) -> void:
	if not game.avatars.has(peer):return
	var avatar: Node3D=game.avatars[peer]
	var record: Dictionary=remote_phone_models.get(peer,{})
	if record.is_empty() or not is_instance_valid(record.model):
		var model:=Node3D.new()
		avatar.add_child(model)
		model.position=Vector3(.25,1.23,-.29)
		model.rotation=Vector3(-.5,.11,-.18)
		record={"model":model,"screen":_build_handset(model,false)}
		remote_phone_models[peer]=record
	record.at=Time.get_ticks_msec()
	if not powered:
		_paint_screen(record.screen,null)
		return
	var screen: MeshInstance3D=record.screen
	var camera: Camera3D=game.camera
	var distance:=camera.global_position.distance_to(screen.global_position)
	var interval: int=game.computers.local_screen_interval(distance,game.ui.graphics_controller.screen_previews)
	if interval==0 or int(record.at)-int(record.get("last_frame",-1000))<interval or not camera.is_position_in_frustum(screen.global_position):
		return
	if (camera.global_position-screen.global_position).dot(screen.global_basis.z)<=0.0:return
	record.last_frame=record.at
	var texture: Texture2D=record.get("texture",idle_preview())
	if not pixels.is_empty() and pixels.size()<=PHONE_WIRE_BYTES:
		var raw:=pixels.decompress(PHONE_WIRE_BYTES,FileAccess.COMPRESSION_FASTLZ)
		if raw.size()==PHONE_WIRE_BYTES:
			var frame:=Image.create_from_data(PHONE_WIRE_SIZE.x,PHONE_WIRE_SIZE.y,false,Image.FORMAT_RGB8,raw)
			if not record.has("texture"):record.texture=ImageTexture.create_from_image(frame)
			else:record.texture.update(frame)
			texture=record.texture
	_paint_screen(screen,texture)

func idle_preview() -> Texture2D:
	if is_instance_valid(idle_view):return idle_view.get_texture()
	idle_view=SubViewport.new()
	idle_view.disable_3d=true
	idle_view.gui_disable_input=true
	idle_view.size=Vector2i(128,224)
	idle_view.render_target_update_mode=SubViewport.UPDATE_ONCE
	add_child(idle_view)
	var wallpaper:=ColorRect.new()
	wallpaper.color=Color("0c273a")
	wallpaper.size=Vector2(idle_view.size)
	idle_view.add_child(wallpaper)
	var launcher:=VBoxContainer.new()
	launcher.position=Vector2(12,22)
	launcher.size.x=104
	wallpaper.add_child(launcher)
	var clock:=Label.new()
	clock.text=Time.get_time_string_from_system().left(5)
	clock.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	clock.add_theme_font_size_override("font_size",24)
	launcher.add_child(clock)
	var grid:=GridContainer.new()
	grid.columns=3
	grid.add_theme_constant_override("h_separation",6)
	grid.add_theme_constant_override("v_separation",6)
	launcher.add_child(grid)
	for icon in ["scope","folder","network","chat","meter"]:
		var tile:=PanelContainer.new()
		tile.add_theme_stylebox_override("panel",Tokens.surface(Color("1b5568"),Color("5391a2"),4))
		tile.custom_minimum_size=Vector2(29,29)
		grid.add_child(tile)
		var glyph:=TextureRect.new()
		glyph.texture=Icons.icon(icon)
		glyph.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
		glyph.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tile.add_child(glyph)
	return idle_view.get_texture()

func _home_screen() -> void:
	var cover:=PanelContainer.new()
	cover.add_theme_stylebox_override("panel",Tokens.surface(Color("133951"),Color("38728a"),16))
	content.add_child(cover)
	var time:=Label.new()
	time.text=phone_clock.text
	time.add_theme_font_size_override("font_size",34)
	cover.add_child(time)
	var apps:=GridContainer.new()
	apps.columns=3
	apps.add_theme_constant_override("h_separation",8)
	apps.add_theme_constant_override("v_separation",8)
	content.add_child(apps)
	for item in [["Camera","scope","1b6870"],["Photos","folder","385e76"],["Browser","network","226395"],["Messages","chat","28705f"],["Calculator","meter","514b76"]]:
		var app: String=item[0]
		var tile:=_button(app,_open_camera if app=="Camera" else _switch.bind(app))
		tile.icon=Icons.icon(item[1])
		tile.icon_alignment=HORIZONTAL_ALIGNMENT_CENTER
		tile.vertical_icon_alignment=VERTICAL_ALIGNMENT_TOP
		tile.alignment=HORIZONTAL_ALIGNMENT_CENTER
		tile.custom_minimum_size.y=84
		tile.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		tile.add_theme_constant_override("icon_max_width",27)
		tile.add_theme_stylebox_override("normal",Tokens.surface(Color(item[2]),Color("477d92"),9))
		tile.add_theme_stylebox_override("hover",Tokens.surface(Color(item[2]).lightened(.17),Tokens.ACCENT,9))
		apps.add_child(tile)

func _open_camera() -> void:
	if not _current_phone_open() or capturing:return
	if is_instance_valid(_placed_model(current_id)):
		status.text="Pick up the phone to use its camera."
		status.show()
		return
	var id:=current_id
	close()
	camera_phone_id=id
	camera_hint.show()

func _leave_camera() -> void:
	camera_phone_id=""
	if is_instance_valid(camera_hint):camera_hint.hide()

func _browser_photo_attachment(kind: String,id: String,lease: String,item: Dictionary) -> PackedByteArray:
	if not is_instance_valid(browser_surface) or kind!="phone" or id!=current_id or lease!=current_id or not _current_phone_open() or item.get("kind","")!="photo":return PackedByteArray()
	var owner_id:=str(game.electronics.profile.data.get("dorm",{}).get("owner",""))
	var photo_id:=str(item.get("id",""))
	var listed:=Photos.list(owner_id,current_id)
	if listed.has("error") or not listed.photos.any(func(photo):return str(photo.id)==photo_id and int(photo.bytes)==int(item.get("bytes",-1))):return PackedByteArray()
	var loaded:=Photos.load_photo(owner_id,current_id,photo_id)
	if loaded.has("error"):return PackedByteArray()
	var bytes: PackedByteArray=loaded.image.save_jpg_to_buffer(.88)
	return bytes if bytes.size()<=browser_surface.MAX_ATTACHMENT_BYTES else PackedByteArray()

func _communications_changed() -> void:
	var state: Dictionary=comm.local_call
	call_notice.visible=not state.is_empty()
	if not state.is_empty():
		var name: String=str(game.session.roster.get(int(state.peer),{}).get("name","Student"))
		call_notice.text="%s · %s"%[str(state.state).capitalize(),name]
	if panel.visible and current_app=="Messages":_switch("Messages")

func _messages() -> void:
	status.text="Connected players"
	status.show()
	var state: Dictionary=comm.local_call
	if not state.is_empty():
		var name: String=str(game.session.roster.get(int(state.peer),{}).get("name","Student"))
		var label:=Label.new();label.text="%s · %s"%[str(state.state).capitalize(),name];content.add_child(label)
		if state.state=="incoming":content.add_child(_button("Answer",func():if _current_phone_open():comm.request("answer")))
		content.add_child(_button("End call",func():if _current_phone_open():comm.end_local_call()))
	for peer in game.session.roster:
		if int(peer)==multiplayer.get_unique_id():continue
		var target:=int(peer)
		var row:=HBoxContainer.new();content.add_child(row)
		var name: String=str(game.session.roster[peer].get("name","Student"))
		var select:=_button(name,func():if _current_phone_open():contact=target;_switch("Messages"));select.size_flags_horizontal=Control.SIZE_EXPAND_FILL;row.add_child(select)
		row.add_child(_button("Call",func():if _current_phone_open():comm.request("call",target)))
	if contact!=0 and game.session.roster.has(contact):
		for item in comm.messages:
			if contact not in [int(item.from),int(item.to)]:continue
			var line:=Label.new();line.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;line.text=("You: " if int(item.from)==multiplayer.get_unique_id() else str(game.session.roster.get(contact,{}).get("name","Student"))+": ")+str(item.text);content.add_child(line)
		var input:=LineEdit.new();input.max_length=240;input.placeholder_text="Write a message";input.text=message_draft;content.add_child(input)
		input.text_changed.connect(func(value):message_draft=value)
		var send:=func():
			if not _current_phone_open():return
			var value:=input.text.strip_edges()
			if not value.is_empty():message_draft="";comm.request("message",contact,value)
		input.text_submitted.connect(func(_value):send.call())
		content.add_child(_button("Send",send))
	elif game.session.roster.size()<=1:
		var empty:=Label.new();empty.text="Connect with another player to message or call.";empty.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;content.add_child(empty)

func _gallery(phone: Dictionary) -> void:
	var owner: String=game.electronics.profile.data.dorm.owner
	var result:=Photos.list(owner,current_id)
	if result.has("error"):status.text=result.error;status.show();return
	var count: int=result.photos.size()
	var pages: int=maxi(1,ceili(float(count)/PHOTOS_PER_PAGE))
	photo_page=clampi(photo_page,0,pages-1)
	status.text="%d %s  ·  %.1f / %.0f MB"%[count,"photo" if count==1 else "photos",float(result.bytes)/1048576.0,float(Tiers.TIERS[phone.tier].storage_bytes)/1048576.0]
	status.show()
	var take:=_button("Open camera",_open_camera)
	take.icon=Icons.icon("scope")
	content.add_child(take)
	if result.photos.is_empty():
		var empty:=Label.new();empty.text="No photos yet. Aim in the world and left-click with the phone equipped.";empty.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;content.add_child(empty)
		return
	if pages>1:
		var navigation:=HBoxContainer.new();content.add_child(navigation)
		var previous:=_button("Previous",func():photo_page-=1;_switch("Photos"));previous.disabled=photo_page==0;navigation.add_child(previous)
		var next:=_button("Next",func():photo_page+=1;_switch("Photos"));next.disabled=photo_page>=pages-1;navigation.add_child(next)
	var grid:=GridContainer.new()
	grid.columns=2
	grid.add_theme_constant_override("h_separation",8)
	grid.add_theme_constant_override("v_separation",8)
	content.add_child(grid)
	for index in range(photo_page*PHOTOS_PER_PAGE,mini(count,(photo_page+1)*PHOTOS_PER_PAGE)):
		var photo: Dictionary=result.photos[index]
		var loaded:=Photos.load_photo(owner,current_id,photo.id)
		if loaded.has("error"):
			var damaged:=_button("Photo unavailable",_show_photo.bind(str(photo.id)))
			damaged.size_flags_horizontal=Control.SIZE_EXPAND_FILL
			grid.add_child(damaged)
		else:
			var thumbnail: Image=loaded.image
			if thumbnail.get_width()>512 or thumbnail.get_height()>288:
				var factor:=minf(512.0/thumbnail.get_width(),288.0/thumbnail.get_height())
				thumbnail.resize(maxi(1,roundi(thumbnail.get_width()*factor)),maxi(1,roundi(thumbnail.get_height()*factor)),Image.INTERPOLATE_BILINEAR)
			var preview:=TextureButton.new()
			preview.custom_minimum_size.y=103
			preview.size_flags_horizontal=Control.SIZE_EXPAND_FILL
			preview.ignore_texture_size=true
			preview.stretch_mode=TextureButton.STRETCH_KEEP_ASPECT_COVERED
			preview.texture_normal=ImageTexture.create_from_image(thumbnail)
			preview.accessibility_name="Open photo %d"%(index+1)
			preview.tooltip_text=preview.accessibility_name
			preview.pressed.connect(_show_photo.bind(str(photo.id)))
			grid.add_child(preview)

func _show_photo(photo_id: String) -> void:
	if not _current_phone_open():return
	_clear_app()
	status.hide()
	var back:=_button("All photos",func():_switch("Photos"))
	back.icon=Icons.icon("back")
	content.add_child(back)
	var loaded:=Photos.load_photo(str(game.electronics.profile.data.dorm.owner),current_id,photo_id)
	if loaded.has("error"):
		status.text=str(loaded.error)
		status.show()
	else:
		var photo:=TextureRect.new()
		photo.custom_minimum_size.y=245
		photo.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
		photo.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		photo.texture=ImageTexture.create_from_image(loaded.image)
		content.add_child(photo)
	var remove:=_button("Delete photo",_confirm_delete.bind(photo_id))
	remove.icon=Icons.icon("trash")
	content.add_child(remove)

func _confirm_delete(photo_id: String) -> void:
	var owner: String=game.electronics.profile.data.dorm.owner
	var phone_id:=current_id
	var dialog:=ConfirmationDialog.new();dialog.title="Delete photo?";dialog.dialog_text="This removes the photo from this phone.";dialog.ok_button_text="Delete";panel.add_child(dialog)
	dialog.confirmed.connect(func():
		if panel.visible and current_id==phone_id and selected()==phone_id and str(game.electronics.profile.data.get("dorm",{}).get("owner",""))==owner and Photos.delete_photo(owner,phone_id,photo_id):_switch("Photos")
		dialog.queue_free())
	dialog.canceled.connect(dialog.queue_free)
	dialog.popup_centered()
