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
	assert(dialog.feature_selectors.algebra.disabled)
	dialog._select(1,"hardware","equation")
	assert(not dialog.feature_selectors.algebra.disabled)
	dialog._select(1,"hardware","algebra")
	dialog._select(2,"hardware","graph")
	dialog._select(0,"hardware","equation")
	assert(dialog.feature_selectors.algebra.disabled and dialog.configuration.hardware.algebra==0 and dialog.configuration.hardware.graph==0)
	dialog.confirmed.emit()
	assert(dialog.stage==1 and dialog.keypad_designer.visible)
	var designer: VBoxContainer=dialog.keypad_designer
	assert(designer.grid.columns==7 and designer.grid.get_child_count()==49)
	assert(Equipment.Keypad.unlocked("y",{"algebra":1,"graph":0}))
	_press(designer,"Key colors")
	await process_frame
	designer.grid.get_child(0).pressed.emit()
	await process_frame
	designer.grid.get_child(1).pressed.emit()
	await process_frame
	designer.color_picker.color=Color("b980e8")
	designer.apply_color.pressed.emit()
	await process_frame
	assert(dialog._quote().configuration.key_colors=={"7":"b980e8","8":"b980e8"})
	designer.move_key(0,4)
	assert(designer.slots[4]=="7" and designer.key_colors["7"]=="b980e8")
	designer.undo()
	designer.undo()
	assert(designer.key_colors.is_empty())
	_press(designer,"Key colors")
	await process_frame
	var full_layout:=Equipment.defaults(Equipment.CALCULATOR)
	full_layout.hardware={"equation":1,"algebra":1,"complex":1,"graph":2}
	var symbols: Array=Equipment.Keypad.REQUIRED.duplicate()
	symbols.append_array(Equipment.Keypad.BUTTONS.keys().filter(func(key):return key not in symbols))
	full_layout.keypad=symbols.slice(0,49)
	assert(full_layout.keypad.size()==49 and not Equipment.quote(Equipment.CALCULATOR,10,full_layout).is_empty())
	var legacy_layout:=full_layout.duplicate(true)
	legacy_layout.keypad=legacy_layout.keypad.slice(0,36)
	assert(not Equipment.quote(Equipment.CALCULATOR,10,legacy_layout).is_empty())
	assert(Equipment.value(Equipment.CALCULATOR,legacy_layout,"hardware","columns",4)==6)
	full_layout.keypad.append("")
	assert(Equipment.quote(Equipment.CALCULATOR,10,full_layout).is_empty())
	if DisplayServer.get_name()!="headless":
		for frame in 4:await process_frame
		var source: Rect2=designer.grid.get_child(0).get_global_rect()
		var free: Rect2=designer.grid.get_child(4).get_global_rect()
		await _drag_key(dialog,source.get_center(),free.get_center())
		assert(designer.slots[4]=="7" and designer.slots[0]=="","Pointer drag did not move the key")
		designer.undo()
		await process_frame
		print("KEYPAD_POINTER_DRAG PASS")
	designer.search.text="square root"
	designer._render_palette()
	assert(designer.palette.get_child_count()==1)
	assert(not designer.add_key("√"))
	assert(not designer.add_key("ⁿ√"))
	assert(not designer.add_key("←"))
	assert(not designer.add_key("↑"))
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
	assert("z" in designer.slots)
	assert(Equipment.body_size(Equipment.defaults(Equipment.CALCULATOR)).z < Equipment.body_size(dialog.configuration).z)
	var parser:=preload("res://scripts/ui/paper_workspace/equations/parser.gd").new()
	var math_engine:=preload("res://scripts/campus/computers/CalculatorMath.cs").new()
	var constants: Dictionary=math_engine.Calculate(parser.parse("ln(e) + τ - 2π + φ^2 - φ").tree,"evaluate",false,"rad")
	assert(is_equal_approx(constants.real,2.0))
	var points: PackedVector3Array=math_engine.Curve(parser.parse("x + 2y = z").tree,2,"rad",3.)
	assert(not points.is_empty() and points[0].is_equal_approx(Vector3(-3,-3,-9)))
	designer.apply_preset("Algebra")
	assert("ⁿ√" in designer.slots)
	assert("←" not in designer.slots and "→" not in designer.slots)
	assert(designer.add_key("←",40))
	assert(designer.add_key("→",41))
	assert(designer.add_key("↑",38) and designer.add_key("↓",39))
	assert(designer.add_key("sin",42))
	designer.move_key(42,48)
	assert(designer.slots[42]=="" and designer.slots[48]=="sin")
	designer.remove_key(designer.slots.find("AC"))
	assert(designer.feedback.text.contains("AC"))
	_press(designer,"Key colors")
	_press(designer,"Clear selection")
	designer._select_slot(designer.slots.find("7"))
	designer._color_keys("ff8040")
	_press(designer,"Clear selection")
	designer._select_slot(designer.slots.find("8"))
	designer._color_keys("40c0ff")
	dialog.confirmed.emit()
	var key_material:=Equipment.Materials.defaults()
	key_material.color="a0b0c0"
	dialog._set_decoration([],{"keys":key_material})
	var options: Dictionary=dialog._quote().configuration
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
	assert(keypad.columns==7 and keypad.get_child(48).text=="sin" and not keypad.get_child(42) is Button)
	for symbol in options.key_colors:
		var cap: Button=keypad.get_child(options.keypad.find(symbol))
		assert(cap.get_theme_stylebox("normal").bg_color.is_equal_approx(Color(options.key_colors[symbol])*Color(key_material.color)))
	calculator.press("sin")
	calculator.press("3")
	calculator.press("0")
	calculator.press("°")
	calculator.press("RUN")
	assert(is_equal_approx(calculator.answer,.5))
	calculator.display.text="9+8(9)"
	var end: int=calculator.display.cursor
	_press(calculator,"←")
	assert(calculator.display.cursor==end-1)
	_press(calculator,"→")
	assert(calculator.display.cursor==end)
	calculator.press("RUN")
	assert(is_equal_approx(calculator.answer,81.0))
	game.open_carried_calculator("calculator_basic",options)
	await process_frame
	var calculator_window:=game.ui.get_child(-1) as Window
	var handheld:=calculator_window.get_child(0) as Control
	assert(handheld!=null and not handheld is ScrollContainer)
	calculator_window.size.y=280
	for frame in 3:await process_frame
	var last: Control=handheld.find_children("*","GridContainer",true,false)[0].get_child(48)
	var bottom_right:=last.get_global_transform()*last.size
	assert(bottom_right.x<=calculator_window.size.x and bottom_right.y<=calculator_window.size.y)
	calculator_window.close_requested.emit()
	_check_number_mode()
	var server:=Ledger.new()
	assert(server.open("user://configured-calculator-ledger")==OK)
	var fresh:=Profile.new()
	fresh.open("configured-calculator-player")
	assert(server.bind(2,fresh.data.dorm.owner,"a".repeat(64),fresh.data).ok)
	var invalid:=options.duplicate(true)
	invalid.keypad[42]="sin"
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

func _check_number_mode() -> void:
	var calculator=preload("res://scripts/scientific_calculator.gd").new()
	calculator.model="calculator_basic"
	calculator.equipment_options=Equipment.defaults(Equipment.CALCULATOR)
	root.add_child(calculator)
	assert(not calculator.equation_enabled)
	for key in ["8","+","4","="]:calculator.press(key)
	assert(float(calculator.display.text)==12.0)
	calculator.press("×")
	assert(float(calculator.display.text)==12.0)
	calculator.press("3")
	assert(calculator.display.text=="3")
	calculator.press("=")
	assert(calculator.answer==36.0)
	for key in ["2","+","3","×","4","="]:calculator.press(key)
	assert(calculator.answer==20.0)
	for key in ["AC","8","+","÷","=","2","="]:calculator.press(key)
	assert(calculator.answer==4.0)
	for key in ["÷","0","="]:calculator.press(key)
	assert(calculator.result.text=="Cannot divide by zero.")
	for key in ["AC","9","M+","AC","9","÷","MR","="]:calculator.press(key)
	assert(is_equal_approx(calculator.answer,1.0))
	calculator.queue_free()

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
