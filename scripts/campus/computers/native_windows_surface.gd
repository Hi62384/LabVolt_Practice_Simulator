extends VBoxContainer

signal output_requested(name: String, data: PackedByteArray)

const Client=preload("res://scripts/campus/computers/CampusNativeClient.cs")
var client
var picture: TextureRect
var caption: Label
var native_texture: ImageTexture
var last_motion:=0
var render_size:=Vector2.ZERO

func start(bytes: PackedByteArray, storage_key: String="", setup := false, bundle := false) -> bool:
	client=Client.new()
	var started: bool=client.StartBundle(bytes,storage_key) if bundle else client.Start(bytes,storage_key,setup)
	if not started:return false
	caption=Label.new()
	caption.text="Starting isolated Windows app…"
	add_child(caption)
	picture=TextureRect.new()
	picture.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	picture.size_flags_vertical=SIZE_EXPAND_FILL
	picture.focus_mode=FOCUS_ALL
	picture.mouse_filter=MOUSE_FILTER_STOP
	picture.gui_input.connect(_guest_input)
	add_child(picture)
	return true

func _process(_delta: float) -> void:
	if client==null:return
	var next: PackedByteArray=client.TakeFrame()
	if not next.is_empty():
		var image:=Image.new()
		if image.load_png_from_buffer(next)==OK and image.get_width()<=1280 and image.get_height()<=900:
			if native_texture==null or native_texture.get_size()!=Vector2(image.get_size()):
				native_texture=ImageTexture.create_from_image(image)
				picture.texture=native_texture
			else:native_texture.update(image)
			render_size=Vector2(image.get_size())
			caption.text="Isolated Windows app · Click the window for keyboard input"
	if not client.Running():
		caption.text=client.Status()
		picture.focus_mode=FOCUS_NONE
		_show_outputs(client.TakeOutputs())
		set_process(false)
	elif native_texture==null:caption.text=client.Status()

func _show_outputs(outputs: Dictionary) -> void:
	var inspector:=preload("res://scripts/campus/computers/WindowsExecutableInspector.cs").new()
	var registry=preload("res://scripts/campus/computers/application_registry.gd")
	for name: String in outputs:
		var bytes: PackedByteArray=outputs[name]
		if not registry._supported_windows(inspector.Inspect(bytes)):continue
		var import:=Button.new()
		import.text="Import "+name+" to Downloads"
		import.pressed.connect(func():output_requested.emit(name,bytes))
		add_child(import)

func _guest_input(event: InputEvent) -> void:
	if not client.Running() or render_size==Vector2.ZERO:return
	if event is InputEventMouse:
		var scale:=minf(picture.size.x/render_size.x,picture.size.y/render_size.y)
		var area:=render_size*scale
		var local: Vector2=(event.position-(picture.size-area)*.5)/area
		if not Rect2(Vector2.ZERO,Vector2.ONE).has_point(local):return
		var action:=-1
		if event is InputEventMouseMotion:
			if Time.get_ticks_msec()-last_motion<33:return
			last_motion=Time.get_ticks_msec()
			action=0
		elif event is InputEventMouseButton:
			if event.pressed:picture.grab_focus()
			if event.button_index==MOUSE_BUTTON_LEFT:action=1 if event.pressed else 2
			if event.button_index==MOUSE_BUTTON_RIGHT:action=3 if event.pressed else 4
		if action>=0:client.Forward(1,roundi(local.x*65535.),roundi(local.y*65535.),action)
	elif event is InputEventKey:
		if event.keycode==KEY_ESCAPE:
			picture.release_focus()
			accept_event()
			return
		if event.ctrl_pressed or event.meta_pressed or event.alt_pressed:return
		var vk:=_virtual_key(event.keycode)
		if vk!=0:client.Forward(2 if event.pressed else 3,vk,0,0)
		if event.pressed and event.unicode>=32:client.Forward(4,event.unicode,0,0)
	else:return
	accept_event()

func _virtual_key(key: int) -> int:
	if key>=KEY_0 and key<=KEY_Z:return key
	if key>=KEY_F1 and key<=KEY_F12:return 0x70+key-KEY_F1
	return int({KEY_BACKSPACE:8,KEY_TAB:9,KEY_ENTER:13,KEY_SPACE:32,KEY_PAGEUP:33,KEY_PAGEDOWN:34,
		KEY_END:35,KEY_HOME:36,KEY_LEFT:37,KEY_UP:38,KEY_RIGHT:39,KEY_DOWN:40,KEY_DELETE:46}.get(key,0))

func _exit_tree() -> void:
	if client!=null:client.Stop()
