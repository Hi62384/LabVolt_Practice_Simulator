extends Node3D
const Photos=preload("res://scripts/campus/phones/photo_library.gd")
const Tiers=preload("res://scripts/campus/phones/phone_tiers.gd")
var game: Node
var held: Node3D
var layer: CanvasLayer
var panel: PanelContainer
var content: VBoxContainer
var status: Label
var display_filter: ColorRect
var current_id:=""
var generation:=0
var capturing:=false
var comm: Node
var current_app:="Photos"
var browser_surface: VBoxContainer
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
	_box(held,Vector3.ZERO,Vector3(.105,.195,.012),Color("243943"))
	_box(held,Vector3(0,0,.007),Vector3(.095,.18,.002),Color("477485"))
	_box(held,Vector3(0,.081,.009),Vector3(.025,.004,.002),Color("b2c9c3"))
	_box(held,Vector3(0,-.081,.009),Vector3(.035,.003,.002),Color("c5d9d0"))
	layer=CanvasLayer.new();layer.layer=45;add_child(layer)
	comm=preload("res://scripts/campus/phones/phone_network.gd").new();comm.name="PhoneNetwork";add_child(comm);comm.build(game);comm.changed.connect(_communications_changed)
	call_notice=Label.new();call_notice.position=Vector2(16,280);call_notice.add_theme_font_size_override("font_size",18);call_notice.add_theme_color_override("font_color",Color("a5e9d7"));call_notice.add_theme_constant_override("outline_size",5);layer.add_child(call_notice);call_notice.hide()
	panel=PanelContainer.new();panel.theme=preload("res://scripts/ui/design_system/theme.gd").create();panel.custom_minimum_size=Vector2(350,580)
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_RIGHT);panel.position=Vector2(-382,-290)
	var skin:=StyleBoxFlat.new();skin.bg_color=Color("102b37");skin.border_color=Color("6ab4a7");skin.set_border_width_all(2);skin.set_corner_radius_all(22);skin.set_content_margin_all(14);panel.add_theme_stylebox_override("panel",skin);layer.add_child(panel)
	var shell:=VBoxContainer.new();shell.add_theme_constant_override("separation",10);panel.add_child(shell)
	var top:=HBoxContainer.new();shell.add_child(top)
	var title:=Label.new();title.text="SMARTPHONE";title.size_flags_horizontal=Control.SIZE_EXPAND_FILL;title.add_theme_font_size_override("font_size",19);title.add_theme_color_override("font_color",Color("a5e9d7"));top.add_child(title)
	top.add_child(_button("Close",close))
	var tabs:=HFlowContainer.new();shell.add_child(tabs)
	tabs.add_child(_button("Photos",func():_switch("Photos")))
	tabs.add_child(_button("Calculator",func():_switch("Calculator")))
	tabs.add_child(_button("Messages",func():_switch("Messages")))
	tabs.add_child(_button("Browser",func():_switch("Browser")))
	status=Label.new();status.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;shell.add_child(status)
	var scroll:=ScrollContainer.new();scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL;shell.add_child(scroll)
	content=VBoxContainer.new();content.size_flags_horizontal=Control.SIZE_EXPAND_FILL;scroll.add_child(content)
	display_filter=ColorRect.new();display_filter.mouse_filter=Control.MOUSE_FILTER_IGNORE
	var shader:=Shader.new();shader.code="shader_type canvas_item;\nuniform sampler2D screen_texture : hint_screen_texture, filter_nearest;\nuniform float display_scale = 1.0;\nvoid fragment() { vec2 pixels = max(vec2(1.0), 1.0 / SCREEN_PIXEL_SIZE * display_scale); vec2 uv = (floor(SCREEN_UV * pixels) + vec2(0.5)) / pixels; COLOR = texture(screen_texture, uv); }"
	var filter_material:=ShaderMaterial.new();filter_material.shader=shader;display_filter.material=filter_material;panel.add_child(display_filter)
	panel.hide()
	game.session.leaving.connect(close)
	game.session.roster_changed.connect(_prune_classroom_open)
	game.session.roster_changed.connect(_prune_teacher_handoffs)
	game.session.restarted.connect(_clear_classroom_open)
	game.session.leaving.connect(_clear_handoff_local)
	game.session.restarted.connect(_clear_handoff_local)

func _box(parent: Node3D,at: Vector3,size: Vector3,color: Color) -> void:
	var mesh:=BoxMesh.new();mesh.size=size
	var instance:=MeshInstance3D.new();instance.mesh=mesh;instance.position=at
	var material:=StandardMaterial3D.new();material.albedo_color=color;material.roughness=.45;instance.material_override=material;parent.add_child(instance)

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
	return is_instance_valid(panel) and panel.visible and not current_id.is_empty() and selected()==current_id

func _process(_delta: float) -> void:
	var id:=selected()
	held.visible=not id.is_empty() and game.front.in_game and game.player.enabled and not panel.visible and not capturing
	if panel.visible and (id!=current_id or not game.front.in_game):close()
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
	if event is InputEventKey and event.pressed and not event.echo and event.keycode==KEY_P:
		capture();return true
	if event is InputEventMouseButton and event.pressed and event.button_index==MOUSE_BUTTON_RIGHT:
		open();return true
	return false

func open() -> void:
	if not game.front.in_game or not game.player.enabled:return
	current_id=selected()
	if current_id.is_empty():return
	photo_page=0
	panel.show();game.release_mouse();_switch("Photos")
	phone_report_clock=0.0
	_report_classroom_open(true,current_id)

func close() -> void:
	generation+=1
	if is_instance_valid(browser_surface):browser_surface.close_session();browser_surface=null
	var previously_open: bool=is_instance_valid(panel) and panel.visible and not current_id.is_empty()
	var was_visible:=panel.visible if is_instance_valid(panel) else false
	if is_instance_valid(panel):
		for child in panel.get_children():
			if child is ConfirmationDialog:child.hide();child.queue_free()
		panel.hide()
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
	if phone.is_empty():return
	var owner: String=str(dorm.owner)
	var capture_generation:=generation
	capturing=true
	var was_held:=held.visible;held.hide()
	# Render the shared world through a separate camera so HUD and chat never
	# appear in saved photos and remain visible to the player during capture.
	var screen_size: Vector2=get_viewport().get_visible_rect().size
	var capture_scale:=minf(1.0,minf(1920.0/screen_size.x,1080.0/screen_size.y))
	var view:=SubViewport.new();view.size=Vector2i(maxi(1,roundi(screen_size.x*capture_scale)),maxi(1,roundi(screen_size.y*capture_scale)));view.world_3d=get_viewport().world_3d
	view.render_target_update_mode=SubViewport.UPDATE_ALWAYS;add_child(view)
	var camera:=Camera3D.new();view.add_child(camera);camera.global_transform=game.camera.global_transform
	camera.projection=game.camera.projection;camera.fov=game.camera.fov;camera.near=game.camera.near;camera.far=game.camera.far;camera.current=true
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image: Image=view.get_texture().get_image()
	view.queue_free()
	held.visible=was_held and selected()==id and game.front.in_game;capturing=false
	if capture_generation!=generation or selected()!=id or not game.front.in_game or str(game.electronics.profile.data.get("dorm",{}).get("owner",""))!=owner:return
	var result:=Photos.capture(owner,id,image,int(Tiers.TIERS[phone.tier].storage_bytes))
	game.ui.log_message(str(result.get("error","Photo saved.")))

func _switch(app: String) -> void:
	if not is_instance_valid(panel) or not panel.visible:return
	generation+=1;var request:=generation
	current_app=app
	var phone: Dictionary=_phone_record(current_id)
	if phone.is_empty():close();return
	var scale: float=float(Tiers.TIERS[phone.tier].display_scale)
	display_filter.visible=scale<1.0
	(display_filter.material as ShaderMaterial).set_shader_parameter("display_scale",scale)
	status.text="Opening %s…"%app
	var delay: int=int(Tiers.TIERS[phone.tier].delay_ms)
	if delay>0:await get_tree().create_timer(float(delay)/1000.0).timeout
	if request!=generation or not panel.visible or selected()!=current_id:return
	if is_instance_valid(browser_surface):browser_surface.close_session();browser_surface=null
	for child in content.get_children():content.remove_child(child);child.queue_free()
	if app=="Calculator":
		var calculator:=preload("res://scripts/scientific_calculator.gd").new();content.add_child(calculator);status.text="Calculator"
	elif app=="Messages":_messages()
	elif app=="Browser":
		var owner_id:=str(game.electronics.profile.data.get("dorm",{}).get("owner",""))
		var photos:=Photos.list(owner_id,current_id)
		var choices: Array=[]
		if not photos.has("error"):
			for photo in photos.photos:choices.append({"kind":"photo","name":str(photo.id)+".jpg","id":str(photo.id),"bytes":int(photo.bytes)})
		browser_surface=preload("res://scripts/campus/computers/browser_surface.gd").new();content.add_child(browser_surface)
		browser_surface.game=game
		browser_surface.configure("phone",current_id,current_id,choices)
		browser_surface.attachment_loader=_browser_photo_attachment
		status.text="Browser · embedded Chromium." if browser_surface.call("renderer_available") else "Embedded browser unavailable on this device."
	else:_gallery(phone)

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
	status.text="Messages · connected players"
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
	if result.has("error"):status.text=result.error;return
	var count: int=result.photos.size()
	var pages: int=maxi(1,ceili(float(count)/PHOTOS_PER_PAGE))
	photo_page=clampi(photo_page,0,pages-1)
	status.text="Photos · %d of %d · %.1f / %.0f MB"%[photo_page+1,pages,float(result.bytes)/1048576.0,float(Tiers.TIERS[phone.tier].storage_bytes)/1048576.0]
	if result.photos.is_empty():
		var empty:=Label.new();empty.text="No photos yet. Hold your phone and press P to take one.";empty.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;content.add_child(empty)
	if pages>1:
		var navigation:=HBoxContainer.new();content.add_child(navigation)
		var previous:=_button("Previous",func():photo_page-=1;_switch("Photos"));previous.disabled=photo_page==0;navigation.add_child(previous)
		var next:=_button("Next",func():photo_page+=1;_switch("Photos"));next.disabled=photo_page>=pages-1;navigation.add_child(next)
	for index in range(photo_page*PHOTOS_PER_PAGE,mini(count,(photo_page+1)*PHOTOS_PER_PAGE)):
		var photo: Dictionary=result.photos[index]
		var loaded:=Photos.load_photo(owner,current_id,photo.id)
		if loaded.has("error"):
			var damaged:=Label.new();damaged.text="Photo unavailable · "+str(loaded.error);damaged.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;content.add_child(damaged)
		else:
			var thumbnail: Image=loaded.image
			if thumbnail.get_width()>512 or thumbnail.get_height()>288:
				var factor:=minf(512.0/thumbnail.get_width(),288.0/thumbnail.get_height())
				thumbnail.resize(maxi(1,roundi(thumbnail.get_width()*factor)),maxi(1,roundi(thumbnail.get_height()*factor)),Image.INTERPOLATE_BILINEAR)
			var preview:=TextureRect.new();preview.custom_minimum_size=Vector2(260,150);preview.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;preview.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED;preview.texture=ImageTexture.create_from_image(thumbnail);content.add_child(preview)
		var photo_id: String=photo.id
		content.add_child(_button("Delete photo",func():_confirm_delete(photo_id)))

func _confirm_delete(photo_id: String) -> void:
	var owner: String=game.electronics.profile.data.dorm.owner
	var phone_id:=current_id
	var dialog:=ConfirmationDialog.new();dialog.title="Delete photo?";dialog.dialog_text="This removes the photo from this phone.";dialog.ok_button_text="Delete";panel.add_child(dialog)
	dialog.confirmed.connect(func():
		if panel.visible and current_id==phone_id and selected()==phone_id and str(game.electronics.profile.data.get("dorm",{}).get("owner",""))==owner and Photos.delete_photo(owner,phone_id,photo_id):_switch("Photos")
		dialog.queue_free())
	dialog.canceled.connect(dialog.queue_free)
	dialog.popup_centered()
