extends Node3D

const Recipe = preload("res://scripts/campus/facilities/sandwich_recipe.gd")
const CounterRules = preload("res://scripts/campus/facilities/sandwich_counter_rules.gd")
const Food = preload("res://scripts/campus/facilities/food_visual.gd")
const PREP := Vector3(.90,1.21,-2.42)
const OVEN := Vector3(2.45,1.37,-2.57)
const INK := Color("284438")
var game: Node
var controller: Node
var cashier: Node3D
var cashier_start := Vector3.ZERO
var cashier_arms: Dictionary = {}
var hood: Node3D
var cards: Dictionary = {}
var groups: Dictionary = {}
var prep: Dictionary = {}
var preview: Node3D
var mover: Tween
var employee_mover: Tween
var oven_eta := 0
var hud: PanelContainer
var stage: Label
var detail: Label
var focused: StaticBody3D
var instructions: Label
var materials: Dictionary = {}
var counter_id := ""
var _sauce: Node3D

func bind(owner: Node, host_controller: Node, employee: Node3D) -> void:
	game = owner
	controller = host_controller
	cashier = employee
	if is_instance_valid(cashier):
		cashier_start = cashier.position
		for name in ["ArmL","ArmR"]:
			var arm := cashier.find_child(name,true,false) as Node3D
			if is_instance_valid(arm):cashier_arms[arm]=arm.rotation
	_build_counter()
	_build_hud()
	controller.room_event.connect(_event)
	controller.sandwich_rejected.connect(func(message: String):game.ui.log_message(message))
	game.session.leaving.connect(reset_local)
	set_process(false)

func begin(station: String) -> void:
	counter_id = station
	controller.sandwich_action(counter_id,"begin")

func reset_local() -> void:
	if is_instance_valid(hud): hud.hide()
	prep.clear()
	_show_step(-1)
	_clear_preview()
	if is_instance_valid(hood): hood.rotation.x = 0.0
	set_process(false)

func route_event(event: InputEvent) -> bool:
	if not _local_order() or not game.player.enabled or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED: return false
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			controller.sandwich_action(counter_id,"cancel")
			return true
		if event.physical_keycode == game.player.keys.interact:
			match int(prep.step):
				2,4,5: controller.sandwich_action(counter_id,"advance/next")
				6:
					if game.hotbar.slots.all(func(slot):return not slot.is_empty()):
						game.ui.log_message("Free a hotbar slot before ordering.")
					else: game.campus_services.facility_panel.request_direct({"op":"sandwich_checkout"})
				_: return false
			return true
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var target := _aimed()
		if is_instance_valid(target): controller.sandwich_action(counter_id,str(target.get_meta("ingredient","")))
		return true
	return false

func _local_order() -> bool:
	return not prep.is_empty() and int(prep.owner)==multiplayer.get_unique_id()

func _event(_peer: int, event: Dictionary) -> void:
	if event.get("activity","") != "sandwich_counter": return
	var old := prep.duplicate(true)
	prep = event.prep.duplicate(true)
	if prep.is_empty():
		reset_local()
		_move_employee(cashier_start.x,false)
		return
	oven_eta = Time.get_ticks_msec() + int(prep.oven_ms) if int(prep.oven_ms)>0 else 0
	var step_value := int(prep.step)
	_show_step(-1 if oven_eta>0 else step_value)
	_rebuild_preview(old)
	hud.visible = _local_order()
	if hud.visible:
		stage.text = "%d / 7   %s" % [step_value+1,prep.label]
		match step_value:
			2,4,5: instructions.text = "Click ingredients   •   %s Continue   •   Esc Cancel" % OS.get_keycode_string(game.player.keys.interact)
			6: instructions.text = "%s Confirm order   •   Esc Cancel" % OS.get_keycode_string(game.player.keys.interact)
			_: instructions.text = "Aim at an option and click   •   Esc Cancel"
		detail.text = _order_summary(prep.recipe,int(prep.price)) if step_value==6 else ""
	if step_value==3 and oven_eta>0: _move_employee(OVEN.x,true)
	elif step_value>0: _move_employee(PREP.x,step_value>0 and step_value<6)
	if step_value==5 and not old.is_empty() and prep.recipe.sauces.size()>old.recipe.sauces.size(): _dispense()
	set_process(true)

func _order_summary(recipe: Dictionary, price: int) -> String:
	var details := "%s · $%d\n%s · %s · %s" % [
		Recipe.title(recipe), price, Recipe.BREAD[recipe.bread], Recipe.CHEESE[recipe.cheese],
		"Toasted" if recipe.heated else "Untoasted"]
	var additions := Recipe.names(recipe.vegetables,Recipe.VEGETABLES)
	var sauces := Recipe.names(recipe.sauces,Recipe.SAUCES)
	if not additions.is_empty(): details += "\n"+additions
	if not sauces.is_empty(): details += "\n"+sauces
	return details

func _process(_delta: float) -> void:
	if not _local_order(): return
	if oven_eta>0:
		var remaining := oven_eta-Time.get_ticks_msec()
		detail.text = "Loading the toaster" if remaining>CounterRules.OVEN_MS else "In the oven · %d s" % maxi(1,ceili(remaining/1000.0))
		instructions.text = "Esc Cancel"
		focused = null
		return
	var target := _aimed()
	if focused != target:
		if is_instance_valid(focused): focused.get_node("SelectionRim").hide()
		focused = target
		if is_instance_valid(focused): focused.get_node("SelectionRim").show()
	if prep.step!=6: detail.text = str(target.get_meta("ingredient_label","")) if is_instance_valid(target) else ""

func _aimed() -> StaticBody3D:
	if prep.is_empty() or oven_eta>0:return null
	var view: Camera3D = game.camera
	if not is_instance_valid(view): return null
	var ray := PhysicsRayQueryParameters3D.create(view.global_position,view.global_position-view.global_basis.z*3.5,4)
	var result := view.get_world_3d().direct_space_state.intersect_ray(ray)
	var found: Variant = result.get("collider")
	if found is StaticBody3D and found.has_meta("ingredient") and is_ancestor_of(found): return found
	return null

func _build_hud() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 27
	add_child(layer)
	var overlay := Control.new()
	layer.add_child(overlay)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter=Control.MOUSE_FILTER_IGNORE
	hud = PanelContainer.new()
	overlay.add_child(hud)
	hud.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	hud.offset_left=-228
	hud.offset_right=228
	hud.offset_top=-136
	hud.offset_bottom=-136
	hud.grow_vertical=Control.GROW_DIRECTION_BEGIN
	hud.mouse_filter=Control.MOUSE_FILTER_IGNORE
	hud.add_theme_stylebox_override("panel",preload("res://scripts/ui/design_system/tokens.gd").surface(Color("f8f0d9"),Color("227444"),9))
	var column := VBoxContainer.new()
	hud.add_child(column)
	column.mouse_filter=Control.MOUSE_FILTER_IGNORE
	stage = _hud_label(column,19)
	detail = _hud_label(column,16)
	detail.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	instructions = _hud_label(column,13)
	hud.hide()

func _hud_label(column: VBoxContainer, size: int) -> Label:
	var line := Label.new()
	line.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	line.add_theme_font_size_override("font_size",size)
	line.add_theme_color_override("font_color",INK)
	column.add_child(line)
	return line

func _build_counter() -> void:
	_box(self,PREP-Vector3(0,.008,0),Vector3(.76,.028,.49),"d9dfd8")
	_box(self,OVEN+Vector3(0,.01,-.19),Vector3(.87,.41,.08),"54646a")
	for side in [-1,1]:
		_box(self,OVEN+Vector3(side*.41,.01,0),Vector3(.05,.41,.42),"607174")
	_box(self,OVEN+Vector3(0,-.175,0),Vector3(.84,.04,.42),"a0adb0")
	_box(self,OVEN+Vector3(0,.21,0),Vector3(.84,.045,.42),"607174")
	hood = Node3D.new()
	hood.position = OVEN+Vector3(0,-.20,.224)
	add_child(hood)
	_box(hood,Vector3(0,.20,0),Vector3(.83,.40,.032),"303d3d")
	_box(hood,Vector3(0,.20,.021),Vector3(.62,.23,.015),"617d76")
	_box(hood,Vector3(0,.34,.049),Vector3(.54,.027,.058),"b2c8c7")
	_option_row(0,"bread",Recipe.BREAD,-1.35,-2.33)
	_option_row(1,"size",Recipe.SIZE,-1.35,-2.28)
	_option_row(2,"protein",Recipe.PROTEIN,-1.35,-2.25)
	_option_row(2,"cheese",Recipe.CHEESE,-1.35,-2.69,1.48)
	_option_row(3,"toast",{"no":"Leave untoasted","yes":"Toast 10 seconds"},-1.35,-2.3)
	_option_row(4,"vegetables",Recipe.VEGETABLES,-1.35,-2.33)
	_option_row(5,"sauces",Recipe.SAUCES,-1.35,-2.33)
	for key in cards: controller.host.sandwich_targets[key] = cards[key].global_position
	_show_step(-1)

func _option_row(step_value: int, field: String, options: Dictionary, center: float, z: float, elevation := 1.27) -> void:
	if not groups.has(step_value):groups[step_value]=[]
	var index := 0
	for value in options:
		var key := field+"/"+str(value)
		var target := StaticBody3D.new()
		target.position = Vector3(center+(index-(options.size()-1)*.5)*.56,elevation,z)
		target.collision_mask=0
		target.set_meta("ingredient",key)
		target.set_meta("ingredient_label",options[value])
		var shape := BoxShape3D.new()
		shape.size = Vector3(.48,.17,.29)
		var hit := CollisionShape3D.new()
		hit.shape = shape
		target.add_child(hit)
		add_child(target)
		cards[key] = target
		groups[step_value].append(target)
		_box(target,Vector3(0,-.06,0),Vector3(.49,.06,.34),"7d908e")
		if elevation>1.3:
			for side in [-.20,.20]:
				_box(target,Vector3(side,-.19,0),Vector3(.04,.23,.08),"617571")
		var rim := _box(target,Vector3(0,-.017,0),Vector3(.47,.009,.32),"e8c33d")
		rim.name = "SelectionRim"
		rim.hide()
		_build_ingredient(target,field,value,index)
		index += 1

func _build_ingredient(parent: Node3D, field: String, value: String, index: int) -> void:
	if field in ["bread","size"]:
		var length := .32 if value=="foot" else .19 if value=="six" else .27
		var tone := "a6744a" if value=="wheat" else "e1b07b" if value=="white" else "c9985d"
		_piece(parent,Vector3(0,.03,0),Vector3(length,.10,.14),tone)
		for mark in [-.3,0.0,.3]:_box(parent,Vector3(mark*length,.076,0),Vector3(.018,.005,.060),"f1cc91").rotation.y=.5
	elif field=="sauces":
		var tone: String = ["f1dfa8","e2af46","f6ebcc","c4513d"][index]
		_piece(parent,Vector3(0,.075,0),Vector3(.11,.19,.105),tone)
		_box(parent,Vector3(0,.18,0),Vector3(.044,.043,.045),"383e37")
	elif field=="toast":
		_box(parent,Vector3(0,.028,0),Vector3(.21,.115,.19),"54646a" if value=="yes" else "d9dfd8")
		_box(parent,Vector3(0,.04,.102),Vector3(.14,.053,.015),"e9b13b" if value=="yes" else "91bfa8")
	else:
		var tones := {"veg":"7fac56","turkey":"bd8277","chicken":"be9574","none":"c7d5ca","cheddar":"efa645","swiss":"ead696","lettuce":"8fb64e","tomato":"c94e3f","cucumber":"88ab65","onion":"b779a0","pepper":"d5a835"}
		for i in 7:
			var at := Vector3((i%4-1.5)*.082,.02+i*.004,(float(i/4)-.5)*.09)
			_piece(parent,at,Vector3(.106,.023,.095),str(tones.get(value,"c7d5ca")))

func _show_step(value: int) -> void:
	if is_instance_valid(focused): focused.get_node("SelectionRim").hide()
	focused = null
	for key in groups:
		for target in groups[key]:
			target.visible=key==value
			target.collision_layer=4 if key==value else 0

func _rebuild_preview(old: Dictionary) -> void:
	var start := PREP
	if is_instance_valid(preview): start = preview.position
	_clear_preview()
	if prep.is_empty() or int(prep.step)==0:return
	preview = Food.build("sandwich",Recipe.servings(prep.recipe),prep.recipe)
	add_child(preview)
	if old.is_empty() and oven_eta>0 and int(prep.oven_ms)<=CounterRules.OVEN_MS:
		preview.position = OVEN
		hood.rotation.x = 0.0
		return
	var previous_oven := int(old.get("oven_ms",0))>0
	var destination := OVEN if oven_eta>0 else PREP
	preview.position = OVEN if previous_oven else start
	if old.is_empty() or int(old.get("step",0))==0:
		preview.position = Vector3(-.20,1.43,-3.33)
	mover = create_tween().set_parallel(true)
	mover.tween_property(preview,"position",destination,.40).set_trans(Tween.TRANS_SINE).set_delay(.30 if previous_oven else 0.0)
	mover.tween_property(hood,"rotation:x",0.0 if oven_eta>0 else PI*.40,.35).set_delay(.40 if oven_eta>0 else 0.0)
	if int(prep.step)==6:
		var band := CylinderMesh.new()
		band.height=.13 if prep.recipe.size=="foot" else .085
		band.top_radius=.053
		band.bottom_radius=.053
		band.cap_top=false
		band.cap_bottom=false
		band.radial_segments=16
		_mesh(preview,Vector3(0,.052,0),band,"e8dfcc").rotation.z=PI/2.0

func _clear_preview() -> void:
	if is_instance_valid(mover): mover.kill()
	if is_instance_valid(preview): preview.queue_free()
	preview = null

func _move_employee(x: float, reaching: bool) -> void:
	if not is_instance_valid(cashier):return
	if is_instance_valid(employee_mover):employee_mover.kill()
	employee_mover=create_tween().set_parallel(true).set_trans(Tween.TRANS_SINE)
	employee_mover.tween_property(cashier,"position:x",x,.40)
	for arm in cashier_arms:
		var rest: Vector3 = cashier_arms[arm]
		var pose := rest + Vector3(-.93,0,0) if reaching else rest
		employee_mover.tween_property(arm,"rotation",pose,.28)

func _dispense() -> void:
	if is_instance_valid(_sauce): _sauce.queue_free()
	var bottle := _piece(self,PREP+Vector3(-.14,.29,-.1),Vector3(.075,.14,.075),"d4ab6a")
	_sauce = bottle
	bottle.rotation.z=2.4
	var tween := create_tween()
	tween.tween_property(bottle,"position:x",PREP.x+.12,.45)
	tween.tween_callback(bottle.queue_free)

func _box(parent: Node3D, at: Vector3, dimensions: Vector3, tint: String) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = dimensions
	return _mesh(parent,at,mesh,tint)

func _piece(parent: Node3D, at: Vector3, dimensions: Vector3, tint: String) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radial_segments=10
	mesh.rings=5
	var node := _mesh(parent,at,mesh,tint)
	node.scale = dimensions
	return node

func _mesh(parent: Node3D, at: Vector3, mesh: Mesh, tint: String) -> MeshInstance3D:
	if not materials.has(tint):
		var material := StandardMaterial3D.new()
		material.albedo_color = Color(tint)
		material.roughness = .62
		materials[tint] = material
	var part := MeshInstance3D.new()
	part.mesh=mesh
	part.material_override=materials[tint]
	part.position=at
	part.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(part)
	return part
