extends Node
## Composition layer: static room anchors + existing chair authority + one local UI.
const Desktop = preload("res://scripts/campus/computers/course_desktop.gd")
const Preferences = preload("res://scripts/campus/computers/desktop_preferences.gd")
const EquipmentFinish = preload("res://scripts/campus/items/equipment_finish.gd")
const EquipmentConfig = preload("res://scripts/campus/items/equipment_configuration.gd")
const Board = preload("res://scripts/campus/academics/teaching_board.gd")
var game: Node
var room: Node3D
var desktop: Control
var board: Node3D
var chair_stations := {}
var indicators := {}
var desktop_overlay: SubViewportContainer
var desktop_render: SubViewport
var idle_render: SubViewport
var usb_previews := {}
var boot_render: SubViewport
var boot_cover: ColorRect
var boot_spinner: Label
var boot_desktop: TextureRect
var boot_seen := {}
var boot_until := {}
var boot_timer: Timer
var local_screen_station := ""
var idle_clock: Label
var public_id := "m203_r3_c4"
var station_frames := {}
var remote_frames := {}
var screen_occupants := {}
var sharing_last_tick := false
var last_monitor_capture := -1000
var last_preview_capture := -1000
var live_preview_station := ""
var volume_knobs := {}
var usb_visuals := {}
var held_usb: Node3D
var visible_usb_id := ""
var power_states := {}
var active := false
var ui_was_open := false
var visibility_timer: Timer
func build(owner_game: Node, mounted_room: Node3D) -> bool:
	game=owner_game
	room=mounted_room
	if not room.mounted:return false
	var ids: Array=room.stations.keys()
	ids.sort()
	for id in ids:
		if not register_station(str(id),room.stations[id],str(id)==public_id):return false
	var layer := CanvasLayer.new()
	layer.layer=40
	add_child(layer)
	var desktop_bounds:=Control.new()
	layer.add_child(desktop_bounds)
	desktop_bounds.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	desktop_bounds.mouse_filter=Control.MOUSE_FILTER_IGNORE
	desktop_overlay=SubViewportContainer.new()
	desktop_bounds.add_child(desktop_overlay)
	desktop_overlay.hide()
	desktop_render=SubViewport.new()
	desktop_render.disable_3d=true
	desktop_render.size_2d_override_stretch=true
	desktop_overlay.add_child(desktop_render)
	desktop_bounds.resized.connect(_resize_desktop.bind(desktop_bounds))
	get_viewport().size_changed.connect(_resize_desktop.bind(desktop_bounds))
	_resize_desktop(desktop_bounds)
	desktop=Desktop.new()
	desktop_render.add_child(desktop)
	desktop.build(game.computers,game)
	desktop.workstation_volume_changed.connect(_turn_volume_knob)
	_build_idle_display()
	_build_boot_display()
	game.computers.boot_changed.connect(_boot_changed)
	_update_indicators()
	game.computers.desktop_changed.connect(_desktop_changed)
	game.computers.power_changed.connect(_power)
	game.computers.connected_usb_changed.connect(_update_usb_visuals)
	game.computers.owned_usb_preferences_changed.connect(_update_indicators)
	held_usb=_build_usb_visual(game.camera,Vector3(.28,-.21,-.48))
	held_usb.rotation=Vector3(-.10,.37,-.38)
	held_usb.scale=Vector3.ONE*1.35
	held_usb.hide()
	game.computers.occupancy_changed.connect(_screen_occupancy)
	game.computers.monitor_frame.connect(_receive_monitor_frame)
	var mirror_timer := Timer.new()
	mirror_timer.wait_time = .05
	mirror_timer.timeout.connect(_tick_monitor_mirror)
	add_child(mirror_timer)
	mirror_timer.start()
	board=Board.new()
	room.root.get_node("TeachingDisplayMount").add_child(board)
	game.school.updated.connect(_teaching)
	visibility_timer=Timer.new()
	visibility_timer.wait_time=.5
	visibility_timer.timeout.connect(_teaching)
	add_child(visibility_timer)
	visibility_timer.start()
	_teaching()
	return true

func _resize_desktop(bounds: Control) -> void:
	if is_instance_valid(desktop) and not desktop.parked_device.is_empty() and desktop.snapshot.is_empty():return
	var logical:=Vector2i(bounds.size.round())
	if logical.x<2 or logical.y<2:return
	var hardware_scale: float=desktop.snapshot.get("display_scale",1.0) if is_instance_valid(desktop) else 1.0
	var display_scale:=get_viewport().get_stretch_transform().get_scale()*hardware_scale
	var pixels:=Vector2i((Vector2(logical)*display_scale).round()).max(Vector2i(2,2))
	# Keep the desktop layout in logical units and render its text into native
	# pixels. Inverse container scaling keeps pointer coordinates aligned.
	desktop_render.size=pixels
	desktop_render.size_2d_override=logical
	desktop_overlay.size=Vector2(pixels)
	desktop_overlay.scale=Vector2(logical)/Vector2(pixels)
func register_station(id: String,station: Node3D,is_public: bool) -> bool:
	var index: int=game.chairs.size()
	game._add_chair(station.seat_anchor.global_position)
	var chair: CharacterBody3D=game.chairs[index]
	chair.fixed_seat=true
	chair.fixed_yaw=station.seat_anchor.global_rotation.y
	# Keep the classroom's static chair visual. The existing gameplay chair
	# supplies occupant/rider/collider/network semantics at the exact seat anchor.
	for child in chair.get_children():
		if child is VisualInstance3D:child.hide()
		elif child is Node3D:
			for part in child.get_children():
				if part is VisualInstance3D:part.hide()
	chair.set_physics_process(false)
	chair_stations[index]=str(id)
	if not game.computers.register_station(str(id),index,station.interaction_anchor.global_position,is_public,true):return false
	game.computers.stations[id].speaker_position=station.screen_anchor.global_position-Vector3.UP*.14
	game.computers.stations[id].preview_position=station.screen_anchor.global_position
	var target := StaticBody3D.new()
	target.set_meta("role","computer")
	target.set_meta("station",str(id))
	target.set_meta("label","Use public computer" if is_public else "Use classroom computer")
	station.add_child(target)
	var hit := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size=Vector3(.72,.48,.12)
	hit.shape=shape
	hit.position=station.screen_anchor.position
	target.add_child(hit)
	indicators[id]=station
	if is_public:
		var usb_target:=StaticBody3D.new()
		usb_target.collision_layer=4;usb_target.collision_mask=0
		usb_target.set_meta("role","public_computer_usb")
		usb_target.set_meta("station",str(id))
		usb_target.set_meta("label","Connect or remove USB drive")
		station.add_child(usb_target)
		var usb_hit:=CollisionShape3D.new();var usb_shape:=BoxShape3D.new()
		usb_shape.size=Vector3(.085,.055,.06);usb_hit.shape=usb_shape
		usb_hit.position=Vector3(.47,.88,.025);usb_target.add_child(usb_hit)
		mount_usb_visual(usb_target,id,Vector3(.47,.88,.032),0.0)
	var power_target:=StaticBody3D.new()
	power_target.collision_layer=4;power_target.collision_mask=0
	power_target.set_meta("role","public_computer_power")
	power_target.set_meta("station",str(id))
	power_target.set_meta("label","Turn on computer")
	station.set_meta("power_target", power_target)
	station.add_child(power_target)
	var power_hit:=CollisionShape3D.new();var power_shape:=BoxShape3D.new()
	power_shape.size=Vector3(.12,.08,.08);power_hit.shape=power_shape
	power_hit.position=Vector3(.58,.98,.025);power_target.add_child(power_hit)
	var power_mark:=Label3D.new();power_mark.text="⏻";power_mark.font_size=24;power_mark.pixel_size=.001
	power_mark.position=Vector3(.58,.98,.018);station.add_child(power_mark)
	_add_volume_knob(station,id,Vector3(.47,.98,.033))
	return true

func _add_volume_knob(station: Node3D, id: String, at: Vector3) -> void:
	var knob:=StaticBody3D.new()
	knob.position=at
	knob.collision_layer=4
	knob.collision_mask=0
	knob.set_meta("role","computer_volume")
	knob.set_meta("station",id)
	knob.set_meta("label","Computer volume")
	station.add_child(knob)
	var hit:=CollisionShape3D.new()
	var shape:=BoxShape3D.new()
	shape.size=Vector3(.071,.071,.045)
	hit.shape=shape
	knob.add_child(hit)
	var dial:=Node3D.new()
	knob.add_child(dial)
	var cap:=MeshInstance3D.new()
	var cylinder:=CylinderMesh.new()
	cylinder.top_radius=.027
	cylinder.bottom_radius=.029
	cylinder.height=.025
	cylinder.radial_segments=16
	cap.mesh=cylinder
	cap.rotation.x=PI*.5
	dial.add_child(cap)
	var tick:=MeshInstance3D.new()
	var mark:=BoxMesh.new()
	mark.size=Vector3(.004,.014,.002)
	tick.mesh=mark
	tick.position=Vector3(0,.017,.013)
	var mark_material:=StandardMaterial3D.new()
	mark_material.albedo_color=Color("125c65")
	tick.material_override=mark_material
	dial.add_child(tick)
	volume_knobs[id]=dial
	_turn_volume_knob(id,35 if not is_instance_valid(desktop) else desktop.workstation_volume(id))

func _turn_volume_knob(id: String, value: int) -> void:
	if is_instance_valid(volume_knobs.get(id)):
		volume_knobs[id].rotation.z=deg_to_rad(lerpf(135.0,-135.0,value/100.0))

func scroll_volume(target: Object, direction: float) -> bool:
	if not is_instance_valid(target) or target.get_meta("role","")!="computer_volume":return false
	var id:=str(target.get_meta("station",""))
	desktop.set_workstation_volume(id,desktop.workstation_volume(id)+int(direction)*5)
	return true

func volume_hint(target: Object) -> String:
	return "Scroll: computer volume · %d%%" % desktop.workstation_volume(str(target.get_meta("station","")))

func _build_usb_visual(parent: Node3D, at: Vector3) -> Node3D:
	var drive:=Node3D.new()
	drive.name="USBDrive"
	drive.position=at
	parent.add_child(drive)
	for part in [
		[Vector3(0,0,-.008),Vector3(.025,.009,.021),Color("c5d4dd")],
		[Vector3(0,0,.025),Vector3(.036,.015,.049),Color("287e84")],
		[Vector3(0,.008,.035),Vector3(.021,.003,.017),Color("b5eadb")]]:
		var mesh:=BoxMesh.new()
		mesh.size=part[1]
		var material:=StandardMaterial3D.new()
		material.albedo_color=part[2]
		var piece:=MeshInstance3D.new()
		piece.mesh=mesh
		piece.material_override=material
		piece.position=part[0]
		piece.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		drive.add_child(piece)
	drive.set_meta("equipment_shell",[drive.get_child(1)])
	drive.set_meta("equipment_trim",[drive.get_child(2)])
	return drive

func mount_usb_visual(port: Node3D, id: String, at: Vector3, yaw: float) -> void:
	var drive:=_build_usb_visual(port,at)
	drive.rotation.y=yaw
	usb_visuals[id]=drive
	drive.visible=game.computers.connected_usb_ports.has(id)
	drive.tree_exiting.connect(func():if usb_visuals.get(id)==drive:usb_visuals.erase(id),CONNECT_ONE_SHOT)

func _update_usb_visuals(ports: Dictionary) -> void:
	for id in usb_visuals:
		if not is_instance_valid(usb_visuals[id]):continue
		var model: Node3D=usb_visuals[id]
		model.visible=ports.has(id)
		if not model.visible:continue
		var appearance: Variant=ports[id]
		EquipmentFinish.apply_finish(model,EquipmentConfig.USB,appearance if appearance is Dictionary else EquipmentConfig.defaults(EquipmentConfig.USB))

func mount_portable_display(id: String, model: Node3D) -> void:
	indicators[id]=model
	model.tree_exiting.connect(func():
		if indicators.get(id)!=model:return
		indicators.erase(id)
		station_frames.erase(id)
		remote_frames.erase(id)
		_clear_usb_preview(id)
		if live_preview_station==id:live_preview_station=""
	,CONNECT_ONE_SHOT)
	_update_indicators()

func speaker_position(id: String) -> Variant:
	var station: Dictionary=game.computers.stations.get(id,{})
	if station.has("anchor"):return station.get("speaker_position",station.anchor+Vector3.UP*1.15)
	var model: Node3D=indicators.get(id)
	if is_instance_valid(model) and model.has_meta("portable"):return model.to_global(Vector3(0,.064,.07))
	return null

func interact(target: Object) -> bool:
	if not is_instance_valid(target):return false
	var role: String=str(target.get_meta("role",""))
	if role=="computer_volume":return true
	if role=="public_computer_usb":
		game.computers.request({"op":"usb_port","station":str(target.get_meta("station",""))})
		return true
	if role=="public_computer_power":
		game.computers.request({"op":"power","station":str(target.get_meta("station",""))})
		return true
	if role!="computer":return false
	var id: String=str(target.get_meta("station",""))
	if id.is_empty():return false
	game.computers.request({"op":"enter","station":id})
	return true
func route_event(event: InputEvent) -> bool:
	if not is_instance_valid(desktop) or desktop.snapshot.is_empty() or not desktop.visible:return false
	# Return from game._input without marking general pointer events handled:
	# GUI controls must still receive them. Desktop owns Esc/Ctrl+S in its _input.
	return event is InputEventKey or event is InputEventMouse
func _desktop_changed(snapshot: Dictionary) -> void:
	var next_station := str(snapshot.get("station",""))
	if next_station != local_screen_station and indicators.has(local_screen_station) and bool(power_states.get(local_screen_station, false)) and DisplayServer.get_name() != "headless":
		var frame := desktop_render.get_texture().get_image()
		if frame != null and not frame.is_empty():
			var scaled_width := mini(frame.get_width(), 640)
			var scaled_height := maxi(1, roundi(float(frame.get_height()) * scaled_width / frame.get_width()))
			frame.resize(scaled_width, scaled_height, Image.INTERPOLATE_BILINEAR)
			if station_frames.size() >= 12 and not station_frames.has(local_screen_station):
				station_frames.erase(station_frames.keys()[0])
			station_frames[local_screen_station] = ImageTexture.create_from_image(frame)
	local_screen_station = next_station
	live_preview_station=""
	last_preview_capture=-1000
	desktop_overlay.visible=not snapshot.is_empty()
	desktop_render.gui_disable_input=snapshot.is_empty()
	if not snapshot.is_empty():
		desktop_render.set_meta("parked_preview",false)
		_resize_desktop(desktop_overlay.get_parent())
		# The desktop's own signal can apply the new snapshot after this handler.
		_resize_desktop.call_deferred(desktop_overlay.get_parent())
	desktop_render.render_target_update_mode=SubViewport.UPDATE_DISABLED if snapshot.is_empty() else SubViewport.UPDATE_WHEN_VISIBLE
	_update_indicators()
	if snapshot.is_empty():
		if game.computers.get_meta("resetting",false):
			Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
			game.player.enabled=false
		elif ui_was_open and game.front.in_game:game.capture()
		ui_was_open=false
	else:
		ui_was_open=true
		if is_instance_valid(game.front.campus_hud):game.front.campus_hud.hide()
		game.release_mouse()
func _build_idle_display() -> void:
	idle_render=_new_monitor_preview()
	idle_clock=idle_render.get_child(0).clock_label

func _new_monitor_preview() -> SubViewport:
	var viewport := SubViewport.new()
	viewport.size=Vector2i(384,216)
	viewport.disable_3d=true
	viewport.gui_disable_input=true
	viewport.size_2d_override=Vector2i(960,540)
	viewport.size_2d_override_stretch=true
	add_child(viewport)
	var preview: Control=Desktop.new()
	viewport.add_child(preview)
	preview.set_process_input(false)
	preview.build_monitor_preview()
	viewport.render_target_update_mode=SubViewport.UPDATE_ONCE
	return viewport

func _clear_usb_preview(id: String) -> void:
	var viewport: SubViewport=usb_previews.get(id,{}).get("viewport")
	if is_instance_valid(viewport):viewport.queue_free()
	usb_previews.erase(id)

func _usb_monitor_texture(id: String, bytes: PackedByteArray) -> Texture2D:
	if bytes.is_empty():
		_clear_usb_preview(id)
		return null
	var cached: Dictionary=usb_previews.get(id,{})
	if cached.get("bytes")!=bytes:
		var settings := Preferences.decode(bytes)
		var viewport: SubViewport=cached.get("viewport")
		if not settings.is_empty():
			if viewport==null:viewport=_new_monitor_preview()
			viewport.get_child(0).apply_monitor_preferences(settings)
			viewport.render_target_update_mode=SubViewport.UPDATE_ONCE
		elif viewport!=null:
			viewport.queue_free()
			viewport=null
		cached={"bytes":bytes,"viewport":viewport}
		usb_previews[id]=cached
	return cached.viewport.get_texture() if cached.viewport!=null else null

func _update_idle_clock() -> void:
	var time := Time.get_time_string_from_system().left(5)
	if idle_clock.text==time:return
	idle_clock.text=time
	idle_render.render_target_update_mode=SubViewport.UPDATE_ONCE
	for cached in usb_previews.values():
		var viewport: SubViewport=cached.viewport
		if viewport==null:continue
		viewport.get_child(0).clock_label.text=time
		viewport.render_target_update_mode=SubViewport.UPDATE_ONCE

func _build_boot_display() -> void:
	boot_render=SubViewport.new()
	boot_render.size=Vector2i(384,216)
	boot_render.disable_3d=true
	boot_render.render_target_update_mode=SubViewport.UPDATE_DISABLED
	add_child(boot_render)
	var background:=ColorRect.new()
	background.color=Color("11273e")
	background.size=Vector2(boot_render.size)
	boot_render.add_child(background)
	var mark:=Label.new()
	mark.text="◈"
	mark.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	mark.position=Vector2(0,45)
	mark.size=Vector2(384,60)
	mark.add_theme_font_size_override("font_size",44)
	mark.add_theme_color_override("font_color",Color("77e2dc"))
	background.add_child(mark)
	var title:=Label.new()
	title.text="Campus OS"
	title.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	title.position=Vector2(0,106)
	title.size=Vector2(384,30)
	title.add_theme_font_size_override("font_size",22)
	background.add_child(title)
	boot_spinner=Label.new()
	boot_spinner.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	boot_spinner.position=Vector2(0,148)
	boot_spinner.size=Vector2(384,28)
	boot_spinner.add_theme_font_size_override("font_size",20)
	background.add_child(boot_spinner)
	boot_timer=Timer.new()
	boot_timer.wait_time=.08
	boot_timer.timeout.connect(_tick_boot)
	add_child(boot_timer)
	boot_cover=ColorRect.new()
	boot_cover.color=Color("050b12")
	boot_cover.size=Vector2(boot_render.size)
	background.add_child(boot_cover)
	boot_desktop=TextureRect.new()
	boot_desktop.texture=idle_render.get_texture()
	boot_desktop.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
	boot_desktop.size=Vector2(boot_render.size)
	boot_desktop.modulate.a=0.0
	background.add_child(boot_desktop)

func _boot_changed(state: Dictionary) -> void:
	for id in boot_until.keys():
		if not state.has(id):boot_until.erase(id)
	for id in state:
		if boot_seen.get(id,-1)==state[id].cycle:continue
		boot_seen[id]=state[id].cycle
		boot_until[id]=Time.get_ticks_msec()+clampi(int(state[id].remaining),0,1600)
	if not boot_until.is_empty() and boot_timer.is_stopped():boot_timer.start()
	_tick_boot()
	_update_indicators()

func _tick_boot() -> void:
	var now:=Time.get_ticks_msec()
	var changed:=false
	for id in boot_until.keys():
		if now>=int(boot_until[id]):
			boot_until.erase(id)
			changed=true
	if changed:_update_indicators()
	if boot_until.is_empty():
		boot_timer.stop()
		return
	var remaining:=int(boot_until.values().max())-now
	boot_cover.color.a=clampf((remaining-1390)/210.0,0.0,1.0)
	boot_desktop.modulate.a=1.0-smoothstep(0.0,320.0,float(remaining))
	boot_spinner.text=["◐","◓","◑","◒"][posmod(now/120,4)]
	boot_render.render_target_update_mode=SubViewport.UPDATE_ONCE

func _screen_occupancy(occupants: Dictionary) -> void:
	screen_occupants = occupants
	for id in remote_frames.keys():
		if int(occupants.get(id, 0)) != int(remote_frames[id].sender): remote_frames.erase(id)
	for id in station_frames.keys():
		if int(occupants.get(id, 0)) not in [0, multiplayer.get_unique_id()]:
			station_frames.erase(id)
	_update_indicators()

func _tick_monitor_mirror() -> void:
	var now := Time.get_ticks_msec()
	var slot: int=game.hotbar.active
	held_usb.visible=game.front.in_game and game.player.enabled and slot in range(game.hotbar.slots.size()) and game.hotbar.slots[slot].get("kind","")=="usb"
	if held_usb.visible:
		var usb_id: String=game.hotbar.slots[slot].id
		if usb_id!=visible_usb_id:
			visible_usb_id=usb_id
			var item: Dictionary=game.electronics.profile.data.get("dorm",{}).get("usb_drives",{}).get(usb_id,{})
			EquipmentFinish.apply_finish(held_usb,EquipmentConfig.USB,item.get("configuration",EquipmentConfig.defaults(EquipmentConfig.USB)))
	if local_screen_station.is_empty():
		_tick_parked_screen(now)
	var changed := false
	for id in remote_frames.keys():
		if now - int(remote_frames[id].received) > 1400:
			remote_frames.erase(id)
			changed = true
	if changed: _update_indicators()
	if local_screen_station.is_empty() or not game.session.online:
		sharing_last_tick = false
		return
	var lease := int(desktop.snapshot.get("lease", -1))
	if not desktop.share_monitor:
		if sharing_last_tick: game.computers.submit_monitor_frame(lease, PackedByteArray())
		sharing_last_tick = false
		return
	if DisplayServer.get_name() == "headless": return
	var station: Dictionary=game.computers.stations.get(local_screen_station,{})
	if station.is_empty():return
	var interval:=0
	for peer in game.session.poses:
		if peer==multiplayer.get_unique_id():continue
		var pose: Vector3=game.session.poses[peer].get("position",Vector3.INF)
		var rate: int=game.computers.screen_preview_interval(pose+Vector3.UP*1.4,station.get("preview_position",station.anchor))
		if rate>0 and (interval==0 or rate<interval):interval=rate
	if interval==0 or now-last_monitor_capture<interval:return
	last_monitor_capture=now
	var image := desktop_render.get_texture().get_image()
	if image == null or image.is_empty(): return
	image.resize(game.computers.SCREEN_SIZE.x, game.computers.SCREEN_SIZE.y, Image.INTERPOLATE_BILINEAR)
	image.convert(Image.FORMAT_RGB8)
	game.computers.submit_monitor_frame(lease, image.get_data().compress(FileAccess.COMPRESSION_FASTLZ))
	sharing_last_tick = true

func _screen_interval(id: String, shared := false) -> int:
	var station: Node3D=indicators.get(id)
	var camera: Camera3D=game.camera
	if not is_instance_valid(station) or not is_instance_valid(camera):return 0
	var screen: MeshInstance3D=station.screen
	if station.has_meta("portable") and not station.get_meta("power_target").visible:return 0
	var eye:=camera.global_position
	var origin:=screen.global_position
	var interval: int=game.computers.screen_preview_interval(eye,origin) if shared else game.computers.local_screen_interval(eye.distance_to(origin),game.ui.graphics_controller.screen_previews)
	if interval==0 or (eye-origin).dot(screen.global_basis.z)<=0.0:return 0
	var sample_width: float=screen.get_aabb().size.x*.42
	for x in [0.0,-sample_width,sample_width]:
		var point: Vector3=origin+screen.global_basis.x*x
		if not camera.is_position_in_frustum(point):continue
		var ray:=PhysicsRayQueryParameters3D.create(eye,point,1,[game.player.get_rid()])
		var hit:=screen.get_world_3d().direct_space_state.intersect_ray(ray)
		if hit.is_empty() or (hit.collider.get_meta("role","")=="computer" and hit.collider.get_meta("station","")==id):
			return interval
	return 0

func _tick_parked_screen(now: int) -> void:
	if DisplayServer.get_name()=="headless" or not game.front.in_game:return
	var id: String=desktop.parked_device
	if id.is_empty() or not power_states.get(id,false) or int(screen_occupants.get(id,0))!=0:return
	var interval:=_screen_interval(id)
	# Timer ticks can land a few milliseconds ahead of the nominal interval.
	if interval==0 or now-last_preview_capture+5<interval:return
	last_preview_capture=now
	# Preserve the desktop's logical layout while reducing the parked render cost.
	desktop_render.set_meta("parked_preview",true)
	var logical:=Vector2(desktop_render.size_2d_override)
	var scale:=float(game.ui.graphics_controller.screen_previews.computer_scale)
	if indicators.has(id):scale*=float(indicators[id].get_meta("display_scale",1.0))
	desktop_render.size=Vector2i((logical*scale*minf(384.0/logical.x,216.0/logical.y)).round())
	desktop.show()
	desktop_render.render_target_update_mode=SubViewport.UPDATE_ONCE
	RenderingServer.frame_post_draw.connect(_finish_parked_preview.bind(id),CONNECT_ONE_SHOT)

func _finish_parked_preview(id: String) -> void:
	if not desktop.snapshot.is_empty():return
	desktop.hide()
	if id!=desktop.parked_device or id==live_preview_station:return
	live_preview_station=id
	_update_indicators()

func _receive_monitor_frame(id: String, sender: int, pixels: PackedByteArray) -> void:
	if not indicators.has(id) or id == local_screen_station or int(screen_occupants.get(id, 0)) != sender:
		return
	var station: Dictionary=game.computers.stations.get(id,{})
	if not bool(power_states.get(id,false)) or station.is_empty():return
	if pixels.is_empty():
		remote_frames.erase(id)
	else:
		if _screen_interval(id,true)==0:return
		if pixels.size() > game.computers.SCREEN_BYTES: return
		var raw := pixels.decompress(game.computers.SCREEN_BYTES, FileAccess.COMPRESSION_FASTLZ)
		if raw.size() != game.computers.SCREEN_BYTES: return
		var image := Image.create_from_data(game.computers.SCREEN_SIZE.x, game.computers.SCREEN_SIZE.y, false, Image.FORMAT_RGB8, raw)
		var texture: ImageTexture = remote_frames.get(id, {}).get("texture")
		if texture == null: texture = ImageTexture.create_from_image(image)
		else: texture.update(image)
		remote_frames[id] = {"sender":sender, "received":Time.get_ticks_msec(), "texture":texture}
	_update_indicators()

func _power(power: Dictionary) -> void:
	power_states=power
	for id in remote_frames.keys():
		if not bool(power.get(id, false)): remote_frames.erase(id)
	for id in station_frames.keys():
		if not bool(power.get(id, false)): station_frames.erase(id)
	_update_indicators()

func _update_indicators() -> void:
	if not is_instance_valid(idle_render):return
	var private_screen: Texture2D=desktop_render.get_texture()
	for id in indicators:
		var powered := bool(power_states.get(id,false))
		var preference_bytes := PackedByteArray()
		if multiplayer.is_server():
			var device: Variant=game.computers.stations.get(id,{}).get("power")
			powered=is_instance_valid(device) and device.powered
			if powered and device.usb.get("owner","")==game.school.local_identity:
				preference_bytes=device.usb.drive.entries.get(Preferences.PATH,{}).get("data",PackedByteArray())
		elif powered:
			preference_bytes=game.computers.owned_usb_preferences.get(id,PackedByteArray())
		var usb_screen:=_usb_monitor_texture(id,preference_bytes)
		var ambient: Texture2D=usb_screen if usb_screen!=null else idle_render.get_texture()
		var use_local: bool=id==local_screen_station or (id==live_preview_station and id==desktop.parked_device and int(screen_occupants.get(id,0))==0)
		var texture: Texture2D=private_screen if use_local else remote_frames.get(id, {}).get("texture", station_frames.get(id, ambient))
		var power_target: Node = indicators[id].get_meta("power_target")
		var device_name: String="laptop" if indicators[id].has_meta("portable") else "computer"
		power_target.set_meta("label", ("Turn off " if powered else "Turn on ")+device_name)
		if powered and boot_until.has(id):
			var boot_remaining := int(boot_until[id])-Time.get_ticks_msec()
			if usb_screen==null or boot_remaining>320:texture=boot_render.get_texture()
		indicators[id].set_display(powered,texture)

func _teaching() -> void:
	if is_instance_valid(idle_clock):_update_idle_clock()
	if not is_instance_valid(board):return
	var inside: bool=game.campus.registry.locate(game.player.global_position)=="computer"
	board.set_room_active(inside)
	if not inside:return
	var school: Node=game.school
	var assigned: bool=str(school.activity.get("room",{}).get("id",""))=="computer"
	var stage := {"text":"Computer classroom • Freeplay practice"}
	var phase := "freeplay"
	if assigned:
		phase=str(school.phase)
		if phase=="lesson":stage=school.teaching_stage().duplicate(true)
		else:stage={"text":"Class begins in %02d:%02d"%[int(school.remaining)/60,int(school.remaining)%60]} if phase=="travel" else {"text":"Complete your assigned work using the classroom paper and computer interfaces."}
	board.show_public_content({"course_id":str(school.activity.get("course_id","")) if assigned else "","phase":phase,"heading":"M203 Computer Classroom","stage":stage,"status":""})
