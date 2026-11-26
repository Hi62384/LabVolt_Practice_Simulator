extends VBoxContainer

signal extract_requested(path: String)
signal install_requested(path: String)

const Browser = preload("res://scripts/campus/computers/browser_surface_native.gd")
const Types = preload("res://scripts/campus/computers/browser_download.gd")
const Zip = preload("res://scripts/campus/computers/VirtualZip.cs")
const MeshImporter = preload("res://scripts/campus/computers/WorkspaceMesh.cs")
const ExeInspector = preload("res://scripts/campus/computers/WindowsExecutableInspector.cs")
const Packages = preload("res://scripts/campus/computers/application_package.gd")
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
var model_fit_distance := 3.0
var details: Label
var toolbar: HBoxContainer

static func app_for(path: String) -> String:
	var extension:=path.get_extension().to_lower()
	if extension in Types.MODEL_EXTENSIONS:return "3D Viewer"
	if extension in Types.IMAGE_EXTENSIONS:return "Photos"
	if extension in Types.VIDEO_EXTENSIONS:return "Video Player"
	if extension in Types.AUDIO_EXTENSIONS:return "Audio Player"
	if extension=="pdf":return "PDF Reader"
	if extension=="campusapp":return "Application Package"
	if extension in ["exe","msi","msix","msixbundle"]:return "Windows Application"
	if extension in ["zip","7z","rar","tar","gz","tgz","bz2","xz"]:return "Archive Manager"
	return "File Viewer"

func show_file(path: String, bytes: PackedByteArray) -> void:
	add_theme_constant_override("separation",8)
	toolbar=HBoxContainer.new()
	add_child(toolbar)
	var location:=Label.new()
	location.text="Workspace / "+path.replace("/"," / ")
	location.tooltip_text=location.text
	location.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
	location.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	toolbar.add_child(location)
	var badge:=Label.new()
	badge.text="%s  ·  %s"%[path.get_extension().to_upper(),String.humanize_size(bytes.size())]
	badge.modulate=Color("a7ccd8")
	toolbar.add_child(badge)
	var canvas:=PanelContainer.new()
	canvas.size_flags_vertical=Control.SIZE_EXPAND_FILL
	canvas.add_theme_stylebox_override("panel",preload("res://scripts/ui/design_system/tokens.gd").surface(Color("081b2a"),Color("26566a"),8))
	add_child(canvas)
	body=VBoxContainer.new()
	body.add_theme_constant_override("separation",8)
	canvas.add_child(body)
	details=Label.new()
	details.modulate=Color("abd0dc")
	details.add_theme_font_size_override("font_size",13)
	details.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
	details.hide()
	add_child(details)
	var extension:=path.get_extension().to_lower()
	match extension:
		"pdf":
			if Types.valid(bytes,extension):_browser_preview(extension,bytes)
			else:_note("This PDF is damaged or incomplete.")
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
		"zip":_archive(path,bytes)
		"campusapp":_application_package(Packages.inspect(bytes))
		"exe": _windows_executable(bytes)
		"msi","msix","msixbundle":
			if Types.valid(bytes,extension):
				_note("Windows packages can be stored and transferred. Installing Windows apps is unavailable in this build.")
			else:_note("The package header is damaged or incomplete.")
		_:
			if MediaMime.has(extension):_browser_preview(extension,bytes)
			elif Types.is_text(extension) and Types.valid(bytes,extension):_text(bytes.get_string_from_utf8(),"UTF-8 preview")
			else:_note("%s file · %s\nA preview is unavailable for this format."%[extension.to_upper(),String.humanize_size(bytes.size())])
	if extension=="campusapp" and not Packages.inspect(bytes).has("error"):
		_action(toolbar,"Install…",func():install_requested.emit(path)).theme_type_variation="PrimaryButton"

func _note(message: String) -> void:
	var label:=Label.new()
	label.text=message
	label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	body.add_child(label)

func _windows_executable(bytes: PackedByteArray) -> void:
	var executable:=ExeInspector.new()
	var details: Dictionary=executable.Inspect(bytes)
	if details.has("error"):
		_note(details.error)
		return
	var fields:=GridContainer.new()
	fields.columns=2
	fields.add_theme_constant_override("h_separation",24)
	fields.add_theme_constant_override("v_separation",8)
	body.add_child(fields)
	for row in [["Application type",details.kind],["Architecture",details.architecture],["Runtime",details.runtime]]:
		var caption:=Label.new()
		caption.text=row[0]
		caption.modulate=Color("abd0dc")
		fields.add_child(caption)
		var value:=Label.new()
		value.text=row[1]
		fields.add_child(value)
	_note("Campus OS can inspect and store this file. Running Windows apps is unavailable in this build.")

func _text(value: String, heading: String) -> void:
	_note(heading)
	var field:=TextEdit.new()
	field.editable=false
	field.text=value
	field.size_flags_vertical=Control.SIZE_EXPAND_FILL
	body.add_child(field)

func _action(parent: Control, label: String, callback: Callable) -> Button:
	var button:=Button.new()
	button.text=label
	button.pressed.connect(callback)
	parent.add_child(button)
	return button

func _archive(path: String, bytes: PackedByteArray) -> void:
	var result: Dictionary=Zip.new().Unpack(bytes,32*1024*1024)
	if result.has("error"):_note(result.error);return
	var names: Array=result.files.keys()
	names.sort()
	_action(toolbar,"Extract…",func():extract_requested.emit(path)).theme_type_variation="PrimaryButton"
	if result.files.has("manifest.json"):
		var package:=Packages.validate(result.files)
		if not package.has("error"):
			_application_package(package)
			_action(toolbar,"Install…",func():install_requested.emit(path)).theme_type_variation="PrimaryButton"
	var entries:=Tree.new()
	entries.columns=2
	entries.column_titles_visible=true
	entries.set_column_title(0,"Name")
	entries.set_column_title(1,"Unpacked size")
	entries.set_column_expand_ratio(0,4)
	entries.hide_root=true
	entries.size_flags_vertical=Control.SIZE_EXPAND_FILL
	body.add_child(entries)
	var root:=entries.create_item()
	for name in names:
		var row:=entries.create_item(root)
		row.set_text(0,name)
		row.set_text(1,String.humanize_size(result.files[name].size()))
	details.text="%d files"%names.size()
	details.show()

func _application_package(package: Dictionary) -> void:
	if package.has("error"):_note(str(package.error));return
	var manifest: Dictionary=package.manifest
	var heading:=Label.new()
	heading.text=manifest.name+"  "+manifest.version
	heading.add_theme_font_size_override("font_size",23)
	body.add_child(heading)
	_note("%s · %d files · %s unpacked"%[manifest.publisher,package.files,String.humanize_size(package.bytes)])
	_note(manifest.description)

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
	var scroll:=ScrollContainer.new()
	scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL
	body.add_child(scroll)
	view.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	scroll.add_child(view)
	_action(toolbar,"Fit",func():
		view.custom_minimum_size=Vector2.ZERO
		view.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED)
	_action(toolbar,"100%",func():
		view.custom_minimum_size=Vector2(picture.get_size())
		view.stretch_mode=TextureRect.STRETCH_KEEP_CENTERED)
	details.text="%d × %d pixels"%[picture.get_width(),picture.get_height()]
	details.show()

func _audio(extension: String, bytes: PackedByteArray) -> void:
	var stream: AudioStream
	match extension:
		"wav":stream=AudioStreamWAV.load_from_buffer(bytes)
		"mp3":stream=AudioStreamMP3.load_from_buffer(bytes)
		_:stream=AudioStreamOggVorbis.load_from_buffer(bytes)
	if stream==null:_note("The audio could not be decoded.");return
	audio=AudioStreamPlayer.new()
	audio.stream=stream
	add_child(audio)
	var track:=Label.new()
	track.text="♫"
	track.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	track.vertical_alignment=VERTICAL_ALIGNMENT_CENTER
	track.add_theme_font_size_override("font_size",42)
	track.modulate=Color("83dce5")
	track.size_flags_vertical=Control.SIZE_EXPAND_FILL
	body.add_child(track)
	var transport:=HBoxContainer.new()
	body.add_child(transport)
	timeline=HSlider.new()
	timeline.max_value=stream.get_length()
	timeline.step=.01
	timeline.accessibility_name="Playback position"
	timeline.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	play=Button.new()
	play.text="Play"
	play.pressed.connect(func():
		if not audio.playing:audio.play(timeline.value)
		else:audio.stream_paused=not audio.stream_paused
		play.text="Pause" if audio.playing and not audio.stream_paused else "Play")
	play.custom_minimum_size.x=65
	transport.add_child(play)
	transport.add_child(timeline)
	var position:=Label.new()
	transport.add_child(position)
	timeline.value_changed.connect(func(value):if audio.playing:audio.seek(value))
	audio.finished.connect(func():play.text="Play";timeline.set_value_no_signal(0))
	var clock:=Timer.new()
	clock.wait_time=.1
	var update_transport:=func():
		if audio.playing and not audio.stream_paused:timeline.set_value_no_signal(audio.get_playback_position())
		position.text="%s / %s"%[_playback_time(timeline.value),_playback_time(timeline.max_value)]
	clock.timeout.connect(update_transport)
	update_transport.call()
	add_child(clock)
	clock.start()

static func _playback_time(seconds: float) -> String:
	return "%d:%02d"%[floori(seconds/60.0),int(seconds)%60]

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
	view.focus_mode=Control.FOCUS_CLICK
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
			else:browser.set_mouse_left_up()
		if event is InputEventMouseButton and event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:
			var delta:=120 if event.button_index==MOUSE_BUTTON_WHEEL_UP else -120
			browser.set_mouse_wheel_vertical(delta,event.shift_pressed,event.ctrl_pressed,event.alt_pressed)
			view.accept_event())
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
	var has_normals := false
	for mesh: Dictionary in descriptor.get("meshes",[]):
		for primitive: Dictionary in mesh.get("primitives",[]):
			has_normals = has_normals or primitive.get("attributes",{}).has("NORMAL")
	_model_scene(model, not has_normals)

func _model_scene(model: Node3D, generate_flat_normals := false) -> void:
	var display:=SubViewportContainer.new()
	display.stretch=true
	display.size_flags_vertical=Control.SIZE_EXPAND_FILL
	body.add_child(display)
	var viewport:=SubViewport.new()
	viewport.own_world_3d=true
	viewport.msaa_3d=Viewport.MSAA_2X
	viewport.render_target_update_mode=SubViewport.UPDATE_WHEN_VISIBLE
	display.add_child(viewport)
	viewport.add_child(model)
	var bounds:=AABB()
	var found:=false
	var meshes:=model.find_children("*","MeshInstance3D",true,false)
	if model is MeshInstance3D:meshes.push_front(model)
	for node in meshes:
		if node.mesh==null:continue
		if generate_flat_normals and node.mesh is ArrayMesh and node.mesh.get_blend_shape_count()==0:
			node.mesh=_flat_preview_mesh(node.mesh)
		var world_bounds: AABB=node.global_transform*node.get_aabb()
		bounds=bounds.merge(world_bounds) if found else world_bounds
		found=true
	if not found or not bounds.size.is_finite() or not bounds.position.is_finite():_note("This model has no visible mesh.");return
	model.position-=bounds.get_center()
	model_fit_distance=maxf(bounds.size.length()*1.15,.001)
	model_distance=model_fit_distance
	model_camera=Camera3D.new()
	model_camera.fov=49.0
	model_camera.near=maxf(model_distance*.001,.0001)
	model_camera.far=maxf(model_distance*100.0,1.0)
	viewport.add_child(model_camera)
	var world:=WorldEnvironment.new()
	world.environment=Environment.new()
	world.environment.background_mode=Environment.BG_COLOR
	world.environment.background_color=Color("142c3c")
	world.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	world.environment.ambient_light_color=Color("cfdeff")
	world.environment.ambient_light_energy=.24
	viewport.add_child(world)
	for light in [[Vector3(-41,-37,0),Color("fff2e5"),1.45],[Vector3(-16,52,0),Color("b9d9ff"),.30],[Vector3(-30,143,0),Color("90bcff"),.68]]:
		var lamp:=DirectionalLight3D.new()
		lamp.rotation_degrees=light[0]
		lamp.light_color=light[1]
		lamp.light_energy=light[2]
		viewport.add_child(lamp)
	_action(toolbar,"Front",func():
		model_orbit=Vector2.ZERO
		_orbit())
	_action(toolbar,"−",_zoom_model.bind(1.18)).tooltip_text="Zoom out"
	_action(toolbar,"+",_zoom_model.bind(.85)).tooltip_text="Zoom in"
	_action(toolbar,"Reset view",func():
		model_orbit=Vector2(-.55,.3)
		model_distance=model_fit_distance
		_orbit())
	_orbit()
	display.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseMotion and event.button_mask&MOUSE_BUTTON_MASK_LEFT:
			model_orbit+=event.relative*Vector2(-.009,.009)
			_orbit()
		elif event is InputEventMouseButton and event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:
			_zoom_model(.88 if event.button_index==MOUSE_BUTTON_WHEEL_UP else 1.14)
			display.accept_event())
	details.text="%d meshes   ·   Drag to orbit   ·   Scroll to zoom"%meshes.size()
	details.show()

func _flat_preview_mesh(mesh: ArrayMesh) -> ArrayMesh:
	# For small models without authored normals, shade each face independently.
	var corner_count := 0
	for index in mesh.get_surface_count():
		if mesh.surface_get_primitive_type(index)!=Mesh.PRIMITIVE_TRIANGLES:return mesh
		var corners := maxi(mesh.surface_get_array_len(index),mesh.surface_get_array_index_len(index))
		if corners%3!=0:return mesh
		corner_count+=corners
		if corner_count>6000:return mesh
	var preview := ArrayMesh.new()
	for index in mesh.get_surface_count():
		var surface := SurfaceTool.new()
		surface.create_from(mesh,index)
		surface.deindex()
		var arrays := surface.commit_to_arrays()
		var vertices: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
		var normals := PackedVector3Array()
		normals.resize(vertices.size())
		for i in range(0,vertices.size(),3):
			var normal := (vertices[i+2]-vertices[i]).cross(vertices[i+1]-vertices[i]).normalized()
			normals[i]=normal
			normals[i+1]=normal
			normals[i+2]=normal
		arrays[Mesh.ARRAY_NORMAL]=normals
		preview.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
		preview.surface_set_material(index,mesh.surface_get_material(index))
	return preview

func _zoom_model(scale: float) -> void:
	model_distance=clampf(model_distance*scale,model_fit_distance*.15,model_fit_distance*10.0)
	_orbit()

func _orbit() -> void:
	model_orbit.y=clampf(model_orbit.y,-1.5,1.5)
	model_camera.position=Vector3(sin(model_orbit.x)*cos(model_orbit.y),sin(model_orbit.y),cos(model_orbit.x)*cos(model_orbit.y))*model_distance
	model_camera.look_at(Vector3.ZERO)

func _exit_tree() -> void:
	if is_instance_valid(browser):browser.close()
	if not browser_key.is_empty() and is_instance_valid(Browser.runtime):Browser.runtime.release_context(browser_key)
	if not temporary_video.is_empty() and FileAccess.file_exists(temporary_video):DirAccess.remove_absolute(temporary_video)
