extends AcceptDialog

const Browser = preload("res://scripts/campus/computers/browser_surface_native.gd")
const Types = preload("res://scripts/campus/computers/browser_download.gd")
const Zip = preload("res://scripts/campus/computers/VirtualZip.cs")
const MeshImporter = preload("res://scripts/campus/computers/WorkspaceMesh.cs")
const MediaMime := {
	"mp4":"video/mp4","m4v":"video/mp4","webm":"video/webm","mov":"video/quicktime",
	"mkv":"video/x-matroska","avi":"video/x-msvideo","flac":"audio/flac","m4a":"audio/mp4",
	"aac":"audio/aac","gif":"image/gif","avif":"image/avif","ico":"image/x-icon","pdf":"application/pdf"
}
var body: VBoxContainer
var browser: Node
var browser_key := ""
var temporary_video := ""
var audio: AudioStreamPlayer
var timeline: HSlider
var play: Button
var model_camera: Camera3D
var model_orbit := Vector2(-.55,.3)
var model_distance := 3.0

func show_file(path: String, bytes: PackedByteArray) -> void:
	title=path.get_file()
	ok_button_text="Close"
	body=VBoxContainer.new()
	body.custom_minimum_size=Vector2(545,350)
	add_child(body)
	confirmed.connect(queue_free)
	canceled.connect(queue_free)
	close_requested.connect(queue_free)
	var extension:=path.get_extension().to_lower()
	match extension:
		"wav","mp3","ogg","oga":_audio(extension,bytes)
		"ogv":_theora(bytes)
		"png","jpg","jpeg","webp","bmp":_image(extension,bytes)
		"glb","gltf":_model(extension,bytes)
		"obj","stl":
			var mesh: ArrayMesh=MeshImporter.new().LoadMesh(extension,bytes)
			if mesh==null:_note("The model could not be loaded.")
			else:
				var root:=Node3D.new()
				var item:=MeshInstance3D.new()
				item.mesh=mesh
				root.add_child(item)
				_model_scene(root)
		"zip":_archive(bytes)
		_:
			if MediaMime.has(extension):_browser_preview(extension,bytes)
			elif Types.is_text(extension) and Types.valid(bytes,extension):_text(bytes.get_string_from_utf8(),"UTF-8 preview")
			else:_note("%s file · %s\nA preview is unavailable for this format."%[extension.to_upper(),String.humanize_size(bytes.size())])
	popup_centered()

func _note(message: String) -> void:
	var label:=Label.new()
	label.text=message
	label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	body.add_child(label)

func _text(value: String, heading: String) -> void:
	_note(heading)
	var field:=TextEdit.new()
	field.editable=false
	field.text=value
	field.size_flags_vertical=Control.SIZE_EXPAND_FILL
	body.add_child(field)

func _archive(bytes: PackedByteArray) -> void:
	var result: Dictionary=Zip.new().Unpack(bytes,32*1024*1024)
	if result.has("error"):_note(result.error);return
	var names: Array=result.files.keys()
	names.sort()
	_text("\n".join(names),"ZIP contents")

func _image(extension: String, bytes: PackedByteArray) -> void:
	var picture:=Image.new()
	var error:=ERR_FILE_UNRECOGNIZED
	match extension:
		"png":error=picture.load_png_from_buffer(bytes)
		"jpg","jpeg":error=picture.load_jpg_from_buffer(bytes)
		"webp":error=picture.load_webp_from_buffer(bytes)
		"bmp":error=picture.load_bmp_from_buffer(bytes)
	if error!=OK:_note("The image could not be opened.");return
	var view:=TextureRect.new()
	view.texture=ImageTexture.create_from_image(picture)
	view.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
	view.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	view.size_flags_vertical=Control.SIZE_EXPAND_FILL
	body.add_child(view)
	_note("%d × %d pixels"%[picture.get_width(),picture.get_height()])

func _audio(extension: String, bytes: PackedByteArray) -> void:
	var stream: AudioStream
	match extension:
		"wav":stream=AudioStreamWAV.load_from_buffer(bytes)
		"mp3":stream=AudioStreamMP3.load_from_buffer(bytes)
		_:stream=AudioStreamOggVorbis.load_from_buffer(bytes)
	if stream==null:_note("The audio could not be decoded.");return
	body.custom_minimum_size.y=150
	audio=AudioStreamPlayer.new()
	audio.stream=stream
	add_child(audio)
	_note("Audio · %.1f seconds"%stream.get_length())
	timeline=HSlider.new()
	timeline.max_value=stream.get_length()
	timeline.step=.01
	timeline.accessibility_name="Playback position"
	body.add_child(timeline)
	play=Button.new()
	play.text="Play"
	play.pressed.connect(func():
		if not audio.playing:audio.play(timeline.value)
		else:audio.stream_paused=not audio.stream_paused
		play.text="Pause" if audio.playing and not audio.stream_paused else "Play")
	body.add_child(play)
	timeline.value_changed.connect(func(value):if audio.playing:audio.seek(value))
	audio.finished.connect(func():play.text="Play";timeline.set_value_no_signal(0))
	var clock:=Timer.new()
	clock.wait_time=.1
	clock.timeout.connect(func():if audio.playing and not audio.stream_paused:timeline.set_value_no_signal(audio.get_playback_position()))
	add_child(clock)
	clock.start()

func _theora(bytes: PackedByteArray) -> void:
	temporary_video="user://campus-preview-"+Crypto.new().generate_random_bytes(12).hex_encode()+".ogv"
	var output:=FileAccess.open(temporary_video,FileAccess.WRITE)
	if output==null:_note("The video preview could not be prepared.");return
	output.store_buffer(bytes)
	output.close()
	var stream:=VideoStreamTheora.new()
	stream.file=temporary_video
	var view:=VideoStreamPlayer.new()
	view.stream=stream
	view.expand=true
	view.size_flags_vertical=Control.SIZE_EXPAND_FILL
	body.add_child(view)
	var button:=Button.new()
	button.text="Play"
	button.pressed.connect(func():
		if not view.is_playing():view.play()
		else:view.paused=not view.paused
		button.text="Pause" if view.is_playing() and not view.paused else "Play")
	view.finished.connect(func():button.text="Play")
	body.add_child(button)

func _browser_preview(extension: String, bytes: PackedByteArray) -> void:
	if not Browser.ensure_runtime(get_tree()):_note("The media renderer is unavailable.");return
	var view:=TextureRect.new()
	view.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
	view.size_flags_vertical=Control.SIZE_EXPAND_FILL
	body.add_child(view)
	browser_key="file-preview:"+Crypto.new().generate_random_bytes(12).hex_encode()
	browser=Browser.runtime.create_browser("about:blank",view,{"session_key":browser_key,"allow_downloads":false,"javascript":true}) as Node
	if not is_instance_valid(browser):_note("The media renderer could not open a preview.");return
	var resize:=func():browser.resize(view.size.max(Vector2(1,1)))
	view.resized.connect(resize)
	view.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouse:
			browser.set_mouse_moved(roundi(event.position.x),roundi(event.position.y))
		if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT:
			if event.pressed:browser.set_mouse_left_down()
			else:browser.set_mouse_left_up())
	var payload:={"bytes":bytes,"sent":false}
	var opened:=func(_view,_code):
		if payload.sent or not str(browser.get_url()).begins_with("data:"):return
		var media: PackedByteArray=payload.bytes
		payload.bytes=PackedByteArray()
		payload.sent=true
		for offset in range(0,media.size(),48*1024):
			var part:=Marshalls.raw_to_base64(media.slice(offset,offset+48*1024))
			browser.execute_javascript("window.campusParts.push(Uint8Array.from(atob('%s'),c=>c.charCodeAt(0)));"%part)
		browser.execute_javascript("window.campusPreview(%s);"%JSON.stringify(MediaMime[extension]))
	browser.connect("on_page_loaded",opened)
	browser.load_data_uri("""<!doctype html><meta charset=utf-8><meta http-equiv="Content-Security-Policy" content="default-src 'none'; img-src blob:; media-src blob:; frame-src blob:; style-src 'unsafe-inline'; script-src 'unsafe-inline'">
		<style>body{margin:0;background:#102333;color:#fff;font:16px sans-serif;display:grid;place-items:center;height:100vh}video,img,iframe{max-width:100%;max-height:100vh}iframe{width:100vw;height:100vh;border:0}</style><body>Preparing preview…
		<script>window.campusParts=[];window.campusPreview=(mime)=>{const url=URL.createObjectURL(new Blob(campusParts,{type:mime}));campusParts=[];const element=document.createElement(mime==='application/pdf'?'iframe':mime.startsWith('image/')?'img':mime.startsWith('audio/')?'audio':'video');element.controls=true;element.onerror=()=>document.body.textContent='This media codec could not be played.';element.src=url;document.body.replaceChildren(element);};</script>""","text/html")
	resize.call()

func _model(extension: String, bytes: PackedByteArray) -> void:
	var source:=bytes
	if extension=="glb":
		if bytes.size()<20 or bytes.slice(0,4).get_string_from_ascii()!="glTF":_note("Invalid GLB file.");return
		var length:=bytes.decode_u32(12)
		if length>bytes.size()-20:_note("Invalid GLB data.");return
		source=bytes.slice(20,20+length)
	var descriptor: Variant=JSON.parse_string(source.get_string_from_utf8())
	if not descriptor is Dictionary:_note("Invalid glTF data.");return
	for kind in ["images","buffers"]:
		var records: Variant=descriptor.get(kind,[])
		if not records is Array:_note("Invalid glTF resources.");return
		for item in records:
			if not item is Dictionary or (item.has("uri") and not str(item.uri).begins_with("data:")):
				_note("Use a self-contained GLB or glTF with embedded resources.");return
	var importer:=GLTFDocument.new()
	var state:=GLTFState.new()
	if importer.append_from_buffer(bytes,"",state)!=OK:_note("The model could not be loaded.");return
	var model:=importer.generate_scene(state)
	if model==null:_note("This model has no scene.");return
	_model_scene(model)

func _model_scene(model: Node3D) -> void:
	var display:=SubViewportContainer.new()
	display.stretch=true
	display.size_flags_vertical=Control.SIZE_EXPAND_FILL
	body.add_child(display)
	var viewport:=SubViewport.new()
	viewport.own_world_3d=true
	viewport.render_target_update_mode=SubViewport.UPDATE_WHEN_VISIBLE
	display.add_child(viewport)
	viewport.add_child(model)
	var bounds:=AABB()
	var found:=false
	for node in model.find_children("*","MeshInstance3D",true,false):
		if node.mesh==null:continue
		var world_bounds: AABB=node.global_transform*node.get_aabb()
		bounds=bounds.merge(world_bounds) if found else world_bounds
		found=true
	if not found or not bounds.size.is_finite() or not bounds.position.is_finite():_note("This model has no visible mesh.");return
	model.position-=bounds.get_center()
	model_distance=maxf(bounds.size.length()*1.3,.001)
	model_camera=Camera3D.new()
	model_camera.near=maxf(model_distance*.001,.0001)
	model_camera.far=maxf(model_distance*100.0,1.0)
	viewport.add_child(model_camera)
	var lamp:=DirectionalLight3D.new()
	lamp.rotation_degrees=Vector3(-45,-35,0)
	lamp.light_energy=1.5
	viewport.add_child(lamp)
	_orbit()
	display.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseMotion and event.button_mask&MOUSE_BUTTON_MASK_LEFT:
			model_orbit+=event.relative*Vector2(-.009,.009)
			_orbit()
		elif event is InputEventMouseButton and event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:
			model_distance=clampf(model_distance*(.88 if event.button_index==MOUSE_BUTTON_WHEEL_UP else 1.14),model_camera.near*5.0,model_camera.far*.5)
			_orbit())
	_note("Drag to orbit · Scroll to zoom")

func _orbit() -> void:
	model_orbit.y=clampf(model_orbit.y,-1.5,1.5)
	model_camera.position=Vector3(sin(model_orbit.x)*cos(model_orbit.y),sin(model_orbit.y),cos(model_orbit.x)*cos(model_orbit.y))*model_distance
	model_camera.look_at(Vector3.ZERO)

func _exit_tree() -> void:
	if is_instance_valid(browser):browser.close()
	if not browser_key.is_empty() and is_instance_valid(Browser.runtime):Browser.runtime.release_context(browser_key)
	if not temporary_video.is_empty() and FileAccess.file_exists(temporary_video):DirAccess.remove_absolute(temporary_video)
