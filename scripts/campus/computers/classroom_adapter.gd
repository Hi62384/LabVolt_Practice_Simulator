extends Node
## Composition layer: static room anchors + existing chair authority + one local UI.
const Desktop = preload("res://scripts/campus/computers/course_desktop.gd")
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
	_build_idle_display()
	_build_boot_display()
	game.computers.boot_changed.connect(_boot_changed)
	_update_indicators()
	game.computers.desktop_changed.connect(_desktop_changed)
	game.computers.power_changed.connect(_power)
	game.computers.occupancy_changed.connect(_screen_occupancy)
	game.computers.monitor_frame.connect(_receive_monitor_frame)
	var mirror_timer := Timer.new()
	mirror_timer.wait_time = .34
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
	var logical:=Vector2i(bounds.size.round())
	if logical.x<2 or logical.y<2:return
	var display_scale:=get_viewport().get_stretch_transform().get_scale()
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
	return true
func interact(target: Object) -> bool:
	if not is_instance_valid(target):return false
	var role: String=str(target.get_meta("role",""))
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
	if not is_instance_valid(desktop) or not desktop.visible:return false
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
	desktop_overlay.visible=not snapshot.is_empty()
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
	idle_render=SubViewport.new()
	idle_render.size=Vector2i(384,216)
	idle_render.disable_3d=true
	idle_render.gui_disable_input=true
	idle_render.size_2d_override=Vector2i(960,540)
	idle_render.size_2d_override_stretch=true
	idle_render.render_target_update_mode=SubViewport.UPDATE_ONCE
	add_child(idle_render)
	var preview: Control=Desktop.new()
	idle_render.add_child(preview)
	preview.set_process_input(false)
	preview.build_monitor_preview()
	idle_clock=preview.clock_label

func _update_idle_clock() -> void:
	var time := Time.get_time_string_from_system().left(5)
	if idle_clock.text==time:return
	idle_clock.text=time
	idle_render.render_target_update_mode=SubViewport.UPDATE_ONCE

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
		if boot_seen.get(id,-1)==state[id]:continue
		boot_seen[id]=state[id]
		boot_until[id]=Time.get_ticks_msec()+1600
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
	var image := desktop_render.get_texture().get_image()
	if image == null or image.is_empty(): return
	image.resize(game.computers.SCREEN_SIZE.x, game.computers.SCREEN_SIZE.y, Image.INTERPOLATE_BILINEAR)
	image.convert(Image.FORMAT_RGB8)
	game.computers.submit_monitor_frame(lease, image.get_data().compress(FileAccess.COMPRESSION_FASTLZ))
	sharing_last_tick = true

func _receive_monitor_frame(id: String, sender: int, pixels: PackedByteArray) -> void:
	if not indicators.has(id) or id == local_screen_station or int(screen_occupants.get(id, 0)) != sender:
		return
	if not bool(power_states.get(id, false)) or game.player.global_position.distance_squared_to(indicators[id].global_position) > 81.0: return
	if pixels.is_empty():
		remote_frames.erase(id)
	else:
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
	var ambient: Texture2D=idle_render.get_texture()
	var private_screen: Texture2D=desktop_render.get_texture()
	for id in indicators:
		var powered := bool(power_states.get(id,false))
		if multiplayer.is_server():
			var device: Variant=game.computers.stations.get(id,{}).get("power")
			powered=is_instance_valid(device) and device.powered
		var texture: Texture2D=private_screen if id==local_screen_station else remote_frames.get(id, {}).get("texture", station_frames.get(id, ambient))
		var power_target: Node = indicators[id].get_meta("power_target")
		power_target.set_meta("label", "Turn off computer" if powered else "Turn on computer")
		if powered and boot_until.has(id):texture=boot_render.get_texture()
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
