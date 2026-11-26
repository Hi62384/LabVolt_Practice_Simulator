extends SceneTree

const Config = preload("res://scripts/campus/items/equipment_configuration.gd")
const Profile = preload("res://scripts/electronics_profile.gd")
const Ledger = preload("res://scripts/inventory_authority/ledger.gd")

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var game: Node = load("res://scenes/Main.tscn").instantiate()
	root.add_child(game)
	for frame in 5:await process_frame
	_press(game.front.body,"Singleplayer")
	await process_frame
	_press(game.front.body,"Play")
	await process_frame
	var profile: RefCounted=game.electronics.profile
	profile.data.dollars=10000
	game.electronics.open("supplies")
	await process_frame
	var card: Node
	for label in game.electronics.body.find_children("*","Label",true,false):
		if label.text=="Smartphone":
			card=label.get_parent()
			break
	assert(card!=null,"Study Supplies smartphone card is missing")
	_press(card,"Details")
	_press(game.electronics.body,"Configure from $250")
	var dialog: ConfirmationDialog=game.electronics.body.find_children("*","ConfirmationDialog",true,false).back()
	var balance: int=int(profile.data.dollars)
	assert(dialog.stage==0 and profile.data.dorm.get("smartphones",{}).is_empty())
	dialog.canceled.emit()
	await process_frame
	assert(profile.data.dorm.get("smartphones",{}).is_empty() and int(profile.data.dollars)==balance)
	_press(game.electronics.body,"Configure from $250")
	dialog=game.electronics.body.find_children("*","ConfirmationDialog",true,false).back()
	dialog._select(4,"hardware","storage")
	dialog._select(2,"hardware","battery")
	dialog._select(2,"hardware","camera_quality")
	dialog._select(1,"hardware","audio_quality")
	dialog._select(3,"hardware","performance")
	dialog.confirmed.emit()
	var shell: OptionButton=dialog.sections[1].get_child(1)
	shell.select(2)
	shell.item_selected.emit(2)
	assert(dialog.phone.get_meta("phone_shell").material_override.albedo_color.is_equal_approx(Color("27745e")))
	dialog.confirmed.emit()
	assert(dialog.stage==2 and profile.data.dorm.get("smartphones",{}).is_empty())
	assert(int(profile.data.dollars)==balance,"Opening the review charged the player")
	var selection: Dictionary=dialog.configuration.duplicate(true)
	var quote:=Config.quote(Config.PHONE,250,selection)
	assert(dialog.price.text=="$%d"%quote.price and quote.hardware_cost==630)
	dialog.confirmed.emit()
	await process_frame
	assert(profile.operation_succeeded and profile.data.dorm.smartphones.size()==1)
	var id: String=profile.data.dorm.smartphones.keys()[0]
	var item: Dictionary=profile.data.dorm.smartphones[id]
	assert(item.configuration==selection)
	assert(game.smartphones._photo_storage(item)==64*1048576)
	assert(game.device_charging._phone_device(1,id,item).runtime_seconds==1950.0)
	game.hotbar._sync_dorm_items()
	for index in game.hotbar.slots.size():
		if game.hotbar.slots[index].get("id")==id:game.hotbar.active=index
	await process_frame
	assert(game.smartphones.held.get_meta("phone_shell").material_override.albedo_color.is_equal_approx(Color("27745e")))
	var json_roundtrip: Dictionary=JSON.parse_string(JSON.stringify(profile.data))
	assert(Profile.valid(json_roundtrip),"Configured phone did not survive JSON persistence")
	assert(game.smartphones._photo_storage(json_roundtrip.dorm.smartphones[id])==64*1048576)
	assert(_check_authority(selection),"Configured purchases failed to reconcile")
	print("CONFIGURED_PHONE PASS")
	game.queue_free()
	await process_frame
	quit()

func _check_authority(selection: Dictionary) -> bool:
	var profile:=Profile.new()
	profile.open("configured-phone-authority")
	profile.data.dollars=10000
	var owner: String=profile.data.dorm.owner
	var secret: String="a".repeat(64)
	var id: String="d".repeat(32)
	var ledger:=Ledger.new()
	assert(ledger.open("user://configured-phone-ledger")==OK)
	assert(ledger.bind(2,owner,secret,profile.data).ok)
	var tampered:=selection.duplicate(true)
	tampered.hardware.storage=-1
	assert(not ledger.transact(2,"invalid-configuration","buy_smartphone",["basic",6,id,tampered]).ok)
	assert(ledger.account(2).profile.dorm.get("smartphones",{}).is_empty())
	var stale: Dictionary=profile.data.duplicate(true)
	stale.phone_purchase_pending={id:{"tier":"basic","host":"test-host","configuration":selection}}
	var purchased: Dictionary=ledger.transact(2,"configured-purchase","buy_smartphone",["basic",6,id,selection])
	assert(purchased.ok,str(purchased.get("error","")))
	assert(purchased.profile.dorm.smartphones[id].configuration==selection)
	ledger.unbind(2)
	var recovered: Dictionary=ledger.bind(2,owner,secret,JSON.parse_string(JSON.stringify(stale)))
	assert(recovered.ok,str(recovered.get("error","")))
	assert(recovered.profile.dollars==purchased.profile.dollars)
	assert(recovered.profile.dorm.smartphones[id].configuration==selection)
	return true

func _press(parent: Node, label: String) -> void:
	for button in parent.find_children("*","Button",true,false):
		if button.text==label and button.is_visible_in_tree():
			button.pressed.emit()
			return
	assert(false,"Missing button "+label)
