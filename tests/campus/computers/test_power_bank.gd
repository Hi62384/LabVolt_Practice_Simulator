extends SceneTree

const Config = preload("res://scripts/campus/items/equipment_configuration.gd")
const Profile = preload("res://scripts/electronics_profile.gd")
const Transfers = preload("res://scripts/ui/personal_inventory/discard_transfer.gd")

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	create_timer(55).timeout.connect(func():quit(1))
	var game: Node=load("res://scenes/Main.tscn").instantiate()
	root.add_child(game)
	for frame in 5:await process_frame
	_press(game.front.body,"Singleplayer")
	await process_frame
	_press(game.front.body,"Play")
	await process_frame
	var profile: RefCounted=game.electronics.profile
	var options:=Config.defaults(Config.POWER_BANK,1)
	options.hardware.merge({"capacity":1,"connector":1,"output":1,"ports":1,"efficiency":1},true)
	profile.data.dollars=10000
	var message: String=profile.buy_study_tool(Config.POWER_BANK,6,options)
	assert(profile.operation_succeeded,message)
	var key: String=profile.data.dorm.power_banks.keys().back()
	assert(profile.data.dorm.power_banks[key].charge_wh==12.0)
	assert(Profile.valid(JSON.parse_string(JSON.stringify(profile.data))))
	assert(key in profile.data.dorm.carry_items)
	var taken:=Transfers.take(profile.data,{"location":"hotbar","item":{"kind":"supply","id":key}},{})
	assert(taken.ok and taken.parcel.power_banks[key].charge_wh==12.0)
	var returned:=Transfers.give(taken.profile,taken.parcel,6)
	assert(returned.ok and returned.profile.dorm.power_banks[key].configuration==options)
	var charging: Node=game.device_charging
	var room: Vector3=charging.sockets[0]-Vector3(0,.12,.40)
	game.player.global_position=room
	var place_id: String=game.personal_placement.key_for(1,key)
	game.personal_placement.placed[place_id]={"key":key,"peer":1,"position":room,"visual":"power_bank","configuration":options,"charge_percent":60,"yaw":0.0,"label":"Power bank"}
	game.personal_placement._sync_models()
	assert(game.personal_placement.models[place_id].has_meta("power_model"))
	charging._grab(1,0)
	charging._plug(1,key)
	assert(charging.banks.connection_on_socket(0)==key)
	_pulse(charging)
	var fuller: float=profile.data.dorm.power_banks[key].charge_wh
	assert(is_equal_approx(fuller,12.45))
	charging._plug(1,key)
	assert(charging.banks.connection_on_socket(0).is_empty())
	var laptop_id: String="b".repeat(32)
	var laptop_model:=Node3D.new()
	game.add_child(laptop_model)
	laptop_model.position=room+Vector3(.45,0,0)
	game.portable_laptops.placed[laptop_id]={"peer":1,"tier":"basic","station":laptop_id,"position":laptop_model.position,"model":laptop_model}
	charging.add_port(laptop_model,"laptop:"+laptop_id,1,Vector3.ZERO,Vector3(.04,.04,.05))
	var laptop: Dictionary=charging._device(1,"laptop",laptop_id,"basic")
	laptop.charge=.5
	charging.toggle_bank(key)
	assert(charging.holding_cable() and not charging.banks.target_connected("laptop:"+laptop_id))
	assert(game.hotbar.slots[game.hotbar.active].get("kind")=="charging_cable")
	charging.release_cable()
	assert(not charging.holding_cable() and not game.hotbar.slots.has({"kind":"charging_cable"}))
	charging.toggle_bank(key)
	charging.interact(laptop_model.get_meta("charging_port"))
	assert(charging.banks.target_connected("laptop:"+laptop_id))
	assert(not charging.holding_cable() and charging.bank_links.size()==1)
	_pulse(charging)
	var used: float=fuller-float(profile.data.dorm.power_banks[key].charge_wh)
	var received: float=(float(laptop.charge)-.5)*38.0
	assert(used>0.0 and received>0.0 and is_equal_approx(received/used,.90))
	var stored: float=profile.data.dorm.power_banks[key].charge_wh
	charging.disconnect_placement(1,"laptop:"+laptop_id)
	game.portable_laptops.placed.erase(laptop_id)
	_pulse(charging)
	assert(is_equal_approx(stored,float(profile.data.dorm.power_banks[key].charge_wh)))
	assert(not charging.banks.target_connected("laptop:"+laptop_id))
	var reloaded:=Profile.new()
	reloaded.open(game.characters.selected)
	assert(is_equal_approx(stored,float(reloaded.data.dorm.power_banks[key].charge_wh)))
	print("POWER_BANK PASS")
	game.queue_free()
	await process_frame
	quit()

func _pulse(charging: Node) -> void:
	for tick in 3:charging.banks.tick()

func _press(parent: Node, label: String) -> void:
	for button in parent.find_children("*","Button",true,false):
		if button.text==label and button.is_visible_in_tree():
			button.pressed.emit()
			return
	assert(false,"Missing button "+label)
