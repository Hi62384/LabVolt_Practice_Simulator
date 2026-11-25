extends SceneTree

const DisplaySettings=preload("res://scripts/campus/ui/graphics_settings.gd")
const Sessions=preload("res://scripts/campus/computers/computer_sessions.gd")

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var game: Node=load("res://scenes/Main.tscn").instantiate()
	root.add_child(game)
	for frame in 6:await process_frame
	game.session.roster[1]={}
	var charging: Node=game.device_charging
	var room: Dictionary=game.campus.registry.get_room("charging_room")
	assert(room.number=="M110")
	assert(game.campus.room_roots["charging_room"].get_node("ChargingStations").is_inside_tree())
	assert(charging.sockets.size()==4)
	var point: Vector3=charging.sockets[0]-Vector3(0,.12,.40)
	game.player.global_position=point
	var ray:=PhysicsRayQueryParameters3D.create(point+Vector3.UP*.3,point-Vector3.UP*.2,1)
	await physics_frame
	assert(absf(game.get_world_3d().direct_space_state.intersect_ray(ray).position.y-.81)<.03)
	var basic_id:="a".repeat(32)
	var premium_id:="b".repeat(32)
	changing_device(game,charging,basic_id,"basic",point)
	var basic: Dictionary=charging.devices["laptop:"+basic_id]
	charging._toggle(1,0)
	assert(basic.socket==0)
	charging._tick()
	assert(float(basic.charge)>.5 and charging.own_connected["laptop:"+basic_id])
	charging._toggle(1,0)
	assert(not charging.own_connected["laptop:"+basic_id])
	game.portable_laptops.placed.erase(basic_id)
	changing_device(game,charging,premium_id,"premium",point)
	var premium: Dictionary=charging.devices["laptop:"+premium_id]
	charging._toggle(1,0)
	charging._tick()
	assert(float(premium.charge)>float(basic.charge))
	game.portable_laptops.placed.erase(premium_id)
	charging._tick()
	assert(not charging.own_connected["laptop:"+premium_id])
	premium.charge=0.0
	assert(not charging.can_power_laptop(1,premium_id,"premium"))
	assert(charging.PHONE_RUNTIME.premium>charging.PHONE_RUNTIME.basic and charging.LAPTOP_RUNTIME.premium>charging.LAPTOP_RUNTIME.basic)
	var settings:=DisplaySettings.new()
	assert(Sessions.local_screen_interval(.3,settings.screen_previews)==100)
	assert(Sessions.local_screen_interval(2.01,settings.screen_previews)==0)
	settings.set_screen_preview_option("near_fps",20)
	settings.set_screen_preview_option("distance",4)
	settings.set_screen_preview_option("phone_scale",2)
	settings.set_option("view_distance",1000)
	var reloaded:=DisplaySettings.new()
	reloaded.load_settings()
	assert(reloaded.screen_previews==settings.screen_previews and reloaded.options.view_distance==1000)
	assert(Sessions.local_screen_interval(.3,reloaded.screen_previews)==50)
	assert(Sessions.local_screen_interval(3.0,reloaded.screen_previews)>50)
	assert(Sessions.local_screen_interval(4.01,reloaded.screen_previews)==0)
	settings.free()
	reloaded.free()
	game.queue_free()
	for frame in 3:await process_frame
	print("DEVICE_CHARGING PASS")
	quit()

func changing_device(game: Node,charging: Node,id: String,tier: String,point: Vector3) -> void:
	game.portable_laptops.placed[id]={"peer":1,"tier":tier,"station":id,"position":point}
	charging._device(1,"laptop",id,tier).charge=.5
