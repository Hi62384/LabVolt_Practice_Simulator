extends SceneTree

var failures: Array[String]=[]

func check(value: bool,message: String) -> void:
	if not value:failures.append(message)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var game: Node=load("res://scenes/Main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	await process_frame
	_check_configured_backpack(game)
	game.queue_free()
	await process_frame
	for failure in failures:push_error(failure)
	print("CONFIGURED_BACKPACK ","PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)

func _check_configured_backpack(game: Node) -> void:
	const Config = preload("res://scripts/campus/items/equipment_configuration.gd")
	const Bags = preload("res://scripts/campus/dorms/authority/backpack_inventory.gd")
	const Mass = preload("res://scripts/campus/facilities/carry_mass.gd")
	var profile = game.electronics.profile
	var options := Config.defaults(Config.BACKPACK)
	options.hardware.merge({"size":1,"pockets":2,"straps":1},true)
	options.appearance.shell=3
	var count: int=profile.data.dorm.get("backpacks",{}).size()
	profile.buy_study_tool(Config.BACKPACK,6,options)
	check(profile.operation_succeeded and profile.data.dorm.get("backpacks",{}).size()==count+1,"configured purchase did not add a backpack")
	if not profile.operation_succeeded:return
	var dorm: Dictionary=profile.data.dorm
	var id: String=dorm.backpacks.keys().back()
	var bag: Dictionary=dorm.backpacks[id]
	check(bag.size=="backpack_medium" and bag.configuration==options,"purchased bag did not retain size and configuration")
	check(Bags.move(dorm,{"op":"bag_move","bag":id,"destination":"back"},[])=="","configured bag could not be equipped")
	for slot in 20:bag.items.append({"kind":"supply","id":"pencil_case"})
	check(not Bags.can_add(bag,"supply") and Bags.can_add(bag,"component"),"backpack did not reserve the last four slots for components")
	check(Mass.profile_mass(profile.data,true)<Mass.profile_mass(profile.data),"padded straps did not reduce movement load")
	for slot in 4:bag.items.append({"kind":"component","type":"led","instance":""})
	check(not Bags.can_add(bag,"component"),"backpack exceeded configured size")
	var model := preload("res://scripts/campus/items/backpack_model.gd").build(game,bag.size,bag.configuration)
	check(model.get_node("Fabric shell").material_override.albedo_color.is_equal_approx(Color("645780")),"backpack fabric does not use its configured color")
	check(model.scale.x>1.0,"backpack dimensions do not reflect purchased size")
	model.queue_free()
	dorm.backpacks.erase(id)
