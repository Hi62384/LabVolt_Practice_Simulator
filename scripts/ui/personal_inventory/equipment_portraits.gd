extends RefCounted

const Config = preload("res://scripts/campus/items/equipment_configuration.gd")
const CACHE_LIMIT := 96
const PENDING_LIMIT := 24
static var cache := {}
static var pending: Array[Dictionary]=[]
static var rendering := false

static func texture(kind: String, options: Dictionary, build: Callable, fallback: Texture2D) -> Texture2D:
	if DisplayServer.get_name()=="headless" or not build.is_valid():return fallback
	var key:=kind+JSON.stringify(options).sha256_text()
	if cache.has(key):return cache[key]
	if pending.size()>=PENDING_LIMIT:return fallback
	var thumbnail:=ImageTexture.create_from_image(fallback.get_image())
	if cache.size()>=CACHE_LIMIT:cache.erase(cache.keys()[0])
	cache[key]=thumbnail
	pending.append({"kind":kind,"options":options.duplicate(true),"build":build,"texture":thumbnail})
	if not rendering:
		rendering=true
		_render_next.call_deferred()
	return thumbnail

static func _render_next() -> void:
	var tree:=Engine.get_main_loop() as SceneTree
	if tree==null:
		pending.clear()
		rendering=false
		return
	while not pending.is_empty():
		var task: Dictionary=pending.pop_front()
		var build: Callable=task.build
		if not build.is_valid():continue
		await _capture(tree,task,build)
	rendering=false

static func _capture(tree: SceneTree, task: Dictionary, build: Callable) -> void:
	var viewport:=SubViewport.new()
	viewport.size=Vector2i(128,96)
	viewport.own_world_3d=true
	viewport.transparent_bg=true
	viewport.msaa_3d=Viewport.MSAA_2X
	viewport.render_target_update_mode=SubViewport.UPDATE_ONCE
	tree.root.add_child(viewport)
	var model:=Node3D.new()
	viewport.add_child(model)
	var kind: String=task.kind
	var options: Dictionary=task.options
	var camera:=Camera3D.new()
	camera.fov=39
	var views := {
		Config.PHONE:[Vector3(-.11,-.42,-.11),.35],
		Config.LAPTOP:[Vector3(.21,-.46,.06),.91],
		Config.USB:[Vector3(.88,-.24,-.24),.15],
		Config.NOTEBOOK:[Vector3(1.10,-.26,-.23),.58],
		Config.BACKPACK:[Vector3(-.09,-.42,-.06),.90],
		Config.CALCULATOR:[Vector3(-.12,-.40,-.12),.42],
		Config.KIT:[Vector3(.20,-.50,.04),1.54],
		Config.POWER_BANK:[Vector3(1.10,-.31,-.20),.30],
	}
	var view: Array=views[kind]
	model.rotation=view[0]
	var geometry: Node3D=build.call(kind,model,options)
	if is_instance_valid(geometry):
		match kind:
			Config.PHONE,Config.LAPTOP,Config.CALCULATOR:
				if options.has("decoration"):model.rotation.y+=PI
			Config.KIT:
				var lid: Node3D=geometry.get_node("Lid")
				lid.position=geometry.get_meta("lid_closed")
				lid.rotation=Vector3.ZERO
				model.rotation.x=.66
	camera.position.z=view[1]
	viewport.add_child(camera)
	for setup in [[Vector3(-34,-25,0),1.60],[Vector3(17,62,0),1.0]]:
		var light:=DirectionalLight3D.new()
		light.rotation_degrees=setup[0]
		light.light_energy=setup[1]
		viewport.add_child(light)
	await RenderingServer.frame_post_draw
	var frame:=viewport.get_texture().get_image()
	if frame!=null and not frame.is_empty() and not frame.is_invisible():task.texture.set_image(frame)
	viewport.queue_free()
