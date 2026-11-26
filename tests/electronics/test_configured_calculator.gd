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
	var defaults: Dictionary=dialog._quote()
	assert(defaults.keypad_cost==13)
	dialog.confirmed.emit()
	assert(dialog.stage==1 and dialog.keypad_designer.visible)
	var designer: VBoxContainer=dialog.keypad_designer
	assert(designer.grid.columns==6 and designer.grid.get_child_count()==36)
	if DisplayServer.get_name()!="headless":
		for frame in 4:await process_frame
		var source: Rect2=designer.grid.get_child(13).get_global_rect()
		var free: Rect2=designer.grid.get_child(12).get_global_rect()
		await _drag_key(dialog,source.get_center(),free.get_center())
		assert(designer.slots[12]=="7" and designer.slots[13]=="","Pointer drag did not move the key")
		designer.undo()
		await process_frame
		print("KEYPAD_POINTER_DRAG PASS")
	designer.search.text="square root"
	designer._render_palette()
	assert(designer.palette.get_child_count()==1)
	assert(not designer.add_key("√"))
	var base_total: int=dialog._quote().price
	assert(designer.add_key("."))
	assert(dialog._quote().price==base_total+1)
	designer.remove_key(designer.slots.find("."))
	assert(dialog._quote().price==base_total)
	designer.undo()
	assert("." in designer.slots)
	designer.redo()
	assert("." not in designer.slots)
	designer.clear_keypad()
	assert(dialog._quote().keypad_cost==0)
	designer.restore_default()
	assert(dialog._quote().keypad_cost==13)
	for preset in ["Basic","Scientific","Financial","Algebra","Graphing"]:
		designer.apply_preset(preset)
		assert(not dialog._quote().is_empty(),preset)
	designer.apply_preset("Algebra")
	assert(designer.add_key("sin",32))
	designer.move_key(32,35)
	assert(designer.slots[32]=="" and designer.slots[35]=="sin")
	designer.remove_key(designer.slots.find("AC"))
	assert(designer.feedback.text.contains("AC"))
	var options: Dictionary=dialog._quote().configuration
	dialog.confirmed.emit()
	dialog.confirmed.emit()
	assert(dialog.stage==3 and dialog.review.text.contains("Missing common keys"))
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
	assert(keypad.columns==6 and keypad.get_child(35).text=="sin" and not keypad.get_child(32) is Button)
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
	invalid.keypad[32]="sin"
	assert(not server.transact(2,"duplicate-key","study_tool",["calculator",6,invalid]).ok)
	invalid=options.duplicate(true)
	invalid.hardware.equation=0
	invalid.hardware.complex=0
	assert(not server.transact(2,"locked-key","study_tool",["calculator",6,invalid]).ok)
	var older:=Equipment.defaults(Equipment.CALCULATOR,2)
	older.keypad=["+"]
	assert(Equipment.quote(Equipment.CALCULATOR,10,older).price==12)
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


func _drag_key(window: Window, start: Vector2, destination: Vector2) -> void:
	start+=Vector2(window.position)
	destination+=Vector2(window.position)
	var hover:=InputEventMouseMotion.new()
	hover.position=start
	hover.global_position=start
	root.push_input(hover,true)
	var press:=InputEventMouseButton.new()
	press.position=start
	press.global_position=start
	press.button_index=MOUSE_BUTTON_LEFT
	press.pressed=true
	press.button_mask=MOUSE_BUTTON_MASK_LEFT
	root.push_input(press,true)
	await process_frame
	for step in range(1,6):
		var motion:=InputEventMouseMotion.new()
		motion.position=start.lerp(destination,float(step)/5.)
		motion.global_position=motion.position
		motion.relative=(destination-start)/5.
		motion.button_mask=MOUSE_BUTTON_MASK_LEFT
		root.push_input(motion,true)
		await process_frame
	var release:=InputEventMouseButton.new()
	release.position=destination
	release.global_position=destination
	release.button_index=MOUSE_BUTTON_LEFT
	root.push_input(release,true)
	await process_frame
