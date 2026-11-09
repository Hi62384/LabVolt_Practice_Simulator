extends Node3D
## Attach to an exposed device's physical transform. The host owns visibility/hit permissions.
const Surface=preload("res://scripts/io_devices/surface.gd")
signal command_requested(command: Dictionary)
var viewport: SubViewport
var surface: Control
var plate: MeshInstance3D
var physical_size:=Vector2(.08,.08)

func _ready() -> void:
	viewport=SubViewport.new();viewport.size=Vector2i(256,256);viewport.transparent_bg=true;viewport.render_target_update_mode=SubViewport.UPDATE_ONCE
	add_child(viewport)
	surface=Surface.new();surface.size=Vector2(256,256);viewport.add_child(surface)
	surface.command_requested.connect(func(command):command_requested.emit(command))
	plate=MeshInstance3D.new();var mesh := QuadMesh.new();mesh.size=physical_size;plate.mesh=mesh;plate.rotation.x=-PI/2
	var material := StandardMaterial3D.new();material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED;material.albedo_texture=viewport.get_texture();material.texture_filter=BaseMaterial3D.TEXTURE_FILTER_NEAREST
	plate.material_override=material;add_child(plate)

func present(kind: String,state: Dictionary,control: Dictionary={}) -> void:
	var dimensions:=Vector2(.22,.12) if kind in ["hd44780","hd44780_20x4"] else Vector2(.18,.1) if kind=="ssd1306" else Vector2(.12,.16) if kind=="ili9341" else Vector2(.08,.08)
	if kind=="spi_display":dimensions=Vector2(.22,.09)
	if dimensions!=physical_size:physical_size=dimensions;plate.mesh.size=physical_size
	var changed: bool=surface.kind!=kind or surface.live!=state or (not control.is_empty() and surface.control!=control)
	surface.present(kind,state,control)
	if changed:viewport.render_target_update_mode=SubViewport.UPDATE_ONCE

func set_interact(enabled: bool) -> void:
	if not enabled:surface.release_capture()
	surface.interact=enabled

## World interaction owner maps hit to local [-.04,.04] x/z and forwards
## through the SAME surface event handler, preserving keypad capture/release.
func pointer_event(local_hit: Vector3,pressed: bool) -> void:
	var event := InputEventMouseButton.new();event.button_index=MOUSE_BUTTON_LEFT;event.pressed=pressed
	var uv := Vector2(local_hit.x/physical_size.x+.5,.5-local_hit.z/physical_size.y)
	event.position=uv*Vector2(256,256)
	viewport.push_input(event,true)

func pointer_motion(local_hit: Vector3,relative_pixels: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position=Vector2(local_hit.x/physical_size.x+.5,.5-local_hit.z/physical_size.y)*256.
	event.relative=relative_pixels;viewport.push_input(event,true)

func acknowledge(control: Dictionary) -> void:
	surface.acknowledge(control);viewport.render_target_update_mode=SubViewport.UPDATE_ONCE

func turn(steps: int) -> void:
	surface.submit({"op":"turn","steps":steps,"revision":int(surface.control.get("revision",0))})

func press_switch(pressed: bool) -> void:
	if surface.kind=="io_joystick":surface.submit({"op":"press","pressed":pressed,"revision":int(surface.control.get("revision",0))})

func release_capture() -> void:surface.release_capture()
