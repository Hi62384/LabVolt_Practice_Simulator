extends SceneTree

const Equipment = preload("res://scripts/campus/items/equipment_configuration.gd")
const Profile = preload("res://scripts/electronics_profile.gd")
const Ledger = preload("res://scripts/inventory_authority/ledger.gd")
const Transfer = preload("res://scripts/ui/personal_inventory/discard_transfer.gd")

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
	game.electronics.open("supplies")
	await process_frame
	var card: Node
	for label in game.electronics.body.find_children("*","Label",true,false):
		if label.text=="Calculator":
			card=label.get_parent()
			break
	assert(card!=null)
	_press(card,"Details")
	_press(game.electronics.body,"Configure from $10")
	var dialog = game.electronics.body.find_children("*","ConfirmationDialog",true,false).back()
	dialog._select(1,"hardware","model")
	dialog._select(2,"hardware","size")
	dialog._select(2,"hardware","columns")
	dialog._drop_key(Vector2.ZERO,{"key_index":0},1)
	dialog._toggle_key(false,"Ans")
	var options: Dictionary=dialog.configuration.duplicate(true)
	assert(options.keypad[0]=="MC" and not "Ans" in options.keypad)
	assert(dialog.keypad_grid.columns==6)
	dialog.confirmed.emit()
	dialog.confirmed.emit()
	assert(dialog.stage==2)
	dialog.confirmed.emit()
	await process_frame
	var profile: RefCounted=game.electronics.profile
	assert(profile.operation_succeeded)
	var id: String=profile.data.dorm.calculator_options.keys().back()
	assert(profile.data.dorm.calculator_options[id]==options)
	assert(Profile.valid(JSON.parse_string(JSON.stringify(profile.data))))
	var working: Dictionary=profile.data.duplicate(true)
	var carried: Array=working.dorm.get_or_add("carry_items",[])
	if id not in carried:
		carried.erase(Transfer.Dorm.carried_calculator(working.dorm))
		carried.append(id)
	var taken:=Transfer.take(working,{"location":"hotbar","item":{"kind":"supply","id":id}},{})
	assert(taken.ok and taken.parcel.calculator_options[id]==options)
	var returned:=Transfer.give(taken.profile,taken.parcel,6)
	assert(returned.ok and returned.profile.dorm.calculator_options[id]==options)
	var calculator=load("res://scripts/scientific_calculator.gd").new()
	calculator.model="calculator"
	calculator.equipment_options=options
	root.add_child(calculator)
	var keypad: GridContainer=calculator.find_children("*","GridContainer",true,false)[0]
	assert(keypad.columns==6 and keypad.get_child(0).text=="MC")
	calculator.press("sin")
	calculator.press("3")
	calculator.press("0")
	calculator.press("=")
	assert(is_equal_approx(calculator.answer,.5))
	var server:=Ledger.new()
	assert(server.open("user://configured-calculator-ledger")==OK)
	var fresh:=Profile.new()
	fresh.open("configured-calculator-player")
	assert(server.bind(2,fresh.data.dorm.owner,"a".repeat(64),fresh.data).ok)
	var invalid:=options.duplicate(true)
	invalid.keypad.erase("0")
	assert(not server.transact(2,"missing-digit","study_tool",["calculator",6,invalid]).ok)
	var owned:=server.transact(2,"valid-calculator","study_tool",["calculator",6,options])
	assert(owned.ok)
	print("CONFIGURED_CALCULATOR PASS")
	calculator.queue_free()
	game.queue_free()
	await process_frame
	quit()

func _press(parent: Node, label: String) -> void:
	for button in parent.find_children("*","Button",true,false):
		if button.text==label and button.is_visible_in_tree():
			button.pressed.emit()
			return
	assert(false,"Missing button "+label)
