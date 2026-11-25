extends Node3D
const GymLayout = preload("res://scripts/campus/facilities/gym_layout.gd")
## Session-owned plates. A plate is either in the rack or on exactly one sleeve.
const LB_TO_KG := .45359237
const BAR_KG := 20.0
const SIZES := [2.5, 5.0, 10.0, 25.0, 35.0, 45.0]
const COUNTS := [8, 8, 8, 8, 8, 8]
const PLATE_RACK := GymLayout.ORIGIN + GymLayout.PLATES
const BELT_RACK := GymLayout.ORIGIN + GymLayout.BELTS
const BELT_SPACING := .55
const BELT_KG := .8
const POSITIONS := GymLayout.BAR_RESTS
var game: Node
var plates: Array = []
var bars := {}
var bar_colliders := {}
var rescue_targets := {}
var belts: Array = []
var selected_station := ""
var panel: PanelContainer
var list: VBoxContainer
var detail: Label
var models := {}
var rack_models := {}
var serial := 0
var broadcast_timer := 0.0
var trapped := {}
var floor_models := {}
var carried_models := {}
var bar_activities := {}
var bench_models := {}
var plate_floor_models := {}
var plate_hand: Node3D
var plate_visual_id := -2
var remote_plates := {}
var belt_models := {}
var remote_belts := {}
var belt_hand: Node3D
var belt_visual_id := -2
var belt_return_target: StaticBody3D
var bar_hand: Node3D
var bar_visual_id := ""
var plate_meshes := {}
var plate_material: StandardMaterial3D
var plate_accent_material: StandardMaterial3D
var plate_engraving_material: StandardMaterial3D

func build(owner: Node) -> void:
	game=owner
	_reset_plates()
	_build_rack()
	_build_barbell_racks()
	_build_belt_rack()
	for station in POSITIONS:
		var bar_target:=StaticBody3D.new();bar_target.position=POSITIONS[station];bar_target.collision_layer=4;bar_target.collision_mask=0
		bar_target.set_meta("role","gym_barbell_rack");bar_target.set_meta("station",station);bar_target.set_meta("label","Pick up barbell")
		var bar_hit:=CollisionShape3D.new();var bar_shape:=BoxShape3D.new();bar_shape.size=Vector3(1.4,.22,.32);bar_hit.shape=bar_shape;add_child(bar_target);bar_target.add_child(bar_hit)
		var solid_bar:=StaticBody3D.new();solid_bar.name="%sBarCollision" % station.get_file();solid_bar.position=POSITIONS[station];solid_bar.collision_layer=0;solid_bar.collision_mask=0;add_child(solid_bar)
		var solid_shape:=BoxShape3D.new();solid_shape.size=Vector3(GymLayout.BAR_LENGTH,.12,.10);var solid_hit:=CollisionShape3D.new();solid_hit.shape=solid_shape;solid_bar.add_child(solid_hit);bar_colliders[station]=solid_bar
		var rescue := StaticBody3D.new()
		rescue.name = "Rescue_" + station.get_file()
		rescue.collision_layer = 0
		rescue.collision_mask = 0
		rescue.set_meta("role","gym_bar_rescue")
		rescue.set_meta("station",station)
		add_child(rescue)
		_add_rack_collision(rescue,Vector3.ZERO,Vector3(1.5,.16,.16))
		rescue_targets[station] = rescue
		# Give both sleeves their own world-space click target. The bar runs along
		# local X, so the opposite ends are equally usable.
		for side in [-1,1]:
			var target:=StaticBody3D.new()
			target.position=POSITIONS[station]+Vector3(float(side)*1.25,0,0)
			target.collision_layer=4
			target.collision_mask=0
			target.set_meta("role","gym_barbell_sleeve")
			target.set_meta("station",station)
			target.set_meta("side",side)
			target.set_meta("label","Left barbell sleeve" if side<0 else "Right barbell sleeve")
			var collision:=CollisionShape3D.new()
			var shape:=SphereShape3D.new();shape.radius=.3
			collision.shape=shape;target.add_child(collision);add_child(target)
	var ui:=CanvasLayer.new();ui.layer=22;add_child(ui)
	panel=PanelContainer.new();panel.theme=preload("res://scripts/ui/design_system/theme.gd").create()
	panel.add_theme_stylebox_override("panel",preload("res://scripts/ui/design_system/theme.gd").card_style())
	ui.add_child(panel);panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.position=Vector2(-230,-280);panel.custom_minimum_size=Vector2(460,560);panel.hide()
	list=VBoxContainer.new();panel.add_child(list)
	game.session.roster_changed.connect(_roster_changed)
	game.session.restarted.connect(_reset)
	game.campus_services.facilities.controller.room_event.connect(_room_event)
	call_deferred("_render")

func _reset_plates() -> void:
	plates.clear()
	bars.clear()
	belts.clear()
	for i in 4:belts.append({"where":"rack","owner":0,"position":BELT_RACK+Vector3(0,0,i*BELT_SPACING)})
	for station in POSITIONS:bars[station]={"where":"rack","owner":0,"position":Vector3.ZERO}
	for index in SIZES.size():
		for _n in COUNTS[index]:plates.append({"lb":SIZES[index],"station":"","side":0,"order":0,"where":"rack","owner":0,"position":Vector3.ZERO})
	serial=0

const PLATE_GAP := .104
const SLEEVE_STEP := .092
const PEG_START := .12

func _peg_base(slot: int) -> Vector3:
	return Vector3(0,.36+float(int(slot/2))*.59,-.42 if slot%2==0 else .42)

func _rack_position(local: Vector3) -> Vector3:
	return PLATE_RACK + local.rotated(Vector3.UP, PI/2)

func _build_rack() -> void:
	var rack := StaticBody3D.new()
	rack.name = "PlateRack"
	rack.position = PLATE_RACK
	rack.rotation.y = PI/2
	rack.collision_layer = 1
	add_child(rack)
	var metal := StandardMaterial3D.new()
	metal.albedo_color = Color("465963")
	metal.metallic = .6
	metal.roughness = .4
	for z in [-.42,.42]:
		_belt_rack_part(rack, Vector3(.40,.045,z), Vector3(.98,.09,.19), metal)
		_belt_rack_part(rack, Vector3(-.02,.84,z), Vector3(.14,1.68,.14), metal)
		_add_rack_collision(rack, Vector3(.40,.045,z), Vector3(.98,.09,.19))
		_add_rack_collision(rack, Vector3(-.02,.84,z), Vector3(.14,1.68,.14))
	for y in [.18,.87,1.55]:
		_belt_rack_part(rack, Vector3(-.025,y,0), Vector3(.12,.075,.86), metal)
	for slot in SIZES.size():
		var origin := _peg_base(slot)
		var length := PEG_START + float(COUNTS[slot])*PLATE_GAP + .06
		_peg_mesh(rack, origin+Vector3(length*.5,0,0), length, .035, metal)
		_peg_mesh(rack, origin+Vector3(.055,0,0), .09, .065, metal)
		_peg_mesh(rack, origin+Vector3(length,0,0), .025, .048, metal)
		var target := StaticBody3D.new()
		target.position = origin + Vector3(length+.035,0,0)
		target.collision_layer = 4
		target.collision_mask = 0
		target.set_meta("role", "gym_plate_rod")
		target.set_meta("slot", slot)
		target.set_meta("label", "Return %.1f lb plate" % SIZES[slot])
		rack.add_child(target)
		_add_rack_collision(target,Vector3.ZERO,Vector3(.10,.14,.14))

func _peg_mesh(parent: Node3D, at: Vector3, length: float, radius: float, material: Material) -> void:
	var peg := MeshInstance3D.new()
	var shaft := CylinderMesh.new()
	shaft.height = length
	shaft.top_radius = radius
	shaft.bottom_radius = radius
	shaft.radial_segments = 12
	peg.mesh = shaft
	peg.rotation.z = PI/2
	peg.position = at
	peg.material_override = material
	parent.add_child(peg)

func _rack_count(slot: int) -> int:
	var count := 0
	for plate in plates:
		if plate.where == "rack" and float(plate.lb) == SIZES[slot]:
			count += 1
	return count

func _build_barbell_racks() -> void:
	var steel:=StandardMaterial3D.new();steel.albedo_color=Color("33404a");steel.metallic=.55;steel.roughness=.48
	for station in ["gym/squat","gym/barbell_rack_2"]:
		var base: Vector3=POSITIONS[station]
		var rack_body:=StaticBody3D.new();rack_body.name="%sCollision" % station.get_file();rack_body.collision_layer=1;rack_body.collision_mask=0;add_child(rack_body)
		for side in [-1.0,1.0]:
			var post:=MeshInstance3D.new();var post_mesh:=BoxMesh.new();post_mesh.size=Vector3(.11,1.3,.14);post.mesh=post_mesh;post.material_override=steel;post.position=base+Vector3(side*.98,-.70,0);add_child(post)
			_add_rack_collision(rack_body,base+Vector3(side*.98,-.70,0),Vector3(.11,1.3,.14))
			var foot:=MeshInstance3D.new();var foot_mesh:=BoxMesh.new();foot_mesh.size=Vector3(.32,.10,.72);foot.mesh=foot_mesh;foot.material_override=steel;foot.position=base+Vector3(side*.98,-1.30,0);add_child(foot)
			_add_rack_collision(rack_body,base+Vector3(side*.98,-1.30,0),Vector3(.32,.10,.72))
			var cradle:=MeshInstance3D.new();var cradle_mesh:=BoxMesh.new();cradle_mesh.size=Vector3(.24,.08,.18);cradle.mesh=cradle_mesh;cradle.material_override=steel;cradle.position=base+Vector3(side*.98,-.05,0);add_child(cradle)
			_add_rack_collision(rack_body,base+Vector3(side*.98,-.05,0),Vector3(.24,.08,.18))

func _add_rack_collision(parent: StaticBody3D,at: Vector3,size: Vector3) -> void:
	var hit:=CollisionShape3D.new();var shape:=BoxShape3D.new();shape.size=size;hit.shape=shape;hit.position=at;parent.add_child(hit)

func _build_belt_rack() -> void:
	var rack:=Node3D.new();rack.name="BeltStorage";rack.position=Vector3(BELT_RACK.x,0,BELT_RACK.z+BELT_SPACING*1.5);add_child(rack)
	var metal:=StandardMaterial3D.new();metal.albedo_color=Color("52636a");metal.metallic=.5;metal.roughness=.5
	for side in [-1.0,1.0]:
		_belt_rack_part(rack,Vector3(0,.83,side*1.02),Vector3(.09,1.66,.09),metal)
		_belt_rack_part(rack,Vector3(0,.04,side*1.02),Vector3(.55,.08,.15),metal)
	_belt_rack_part(rack,Vector3(0,1.65,0),Vector3(.09,.09,2.13),metal)
	for i in 4:
		_belt_rack_part(rack,Vector3(0,1.59,(float(i)-1.5)*BELT_SPACING),Vector3(.12,.10,.07),metal)

	var return_target := StaticBody3D.new()
	belt_return_target=return_target
	return_target.name = "BeltReturn"
	return_target.position = Vector3(0,.88,0)
	return_target.collision_layer = 0
	return_target.collision_mask = 0
	return_target.set_meta("role","gym_belt_return")
	return_target.set_meta("label","Return Weight Belt")
	var return_collision := CollisionShape3D.new()
	var return_shape := BoxShape3D.new()
	return_shape.size = Vector3(.55,1.72,2.20)
	return_collision.shape = return_shape
	rack.add_child(return_target)
	return_target.add_child(return_collision)

func _belt_rack_part(parent: Node3D,position_value: Vector3,size: Vector3,material: Material) -> void:
	var part:=MeshInstance3D.new();var box:=BoxMesh.new();box.size=size;part.mesh=box;part.material_override=material;part.position=position_value;parent.add_child(part)
	var body:=StaticBody3D.new();body.collision_layer=1;body.collision_mask=0;part.add_child(body)
	var collision:=CollisionShape3D.new();var shape:=BoxShape3D.new();shape.size=size;collision.shape=shape;body.add_child(collision)

func mass(station: String) -> float:
	if not POSITIONS.has(station):return 0.0
	if bars.has(station) and bars[station].where!="rack":return 0.0
	return loaded_mass(station)

func loaded_mass(station: String) -> float:
	if not POSITIONS.has(station):return 0.0
	var result:=BAR_KG
	for plate in plates:
		if plate.station==station:result+=float(plate.lb)*LB_TO_KG
	return result

func held_bar(peer: int) -> String:
	for station in bars:
		if int(bars[station].owner)==peer and bars[station].where=="held":return station
	return ""

func held_mass(peer: int) -> float:
	var station:=held_bar(peer)
	return loaded_mass(station) if not station.is_empty() else 0.0

func held_plate(peer: int) -> int:
	for id in plates.size():
		if int(plates[id].owner)==peer and plates[id].where=="held":return id
	return -1

func held_belt(peer: int) -> int:
	for id in belts.size():
		if int(belts[id].owner)==peer and belts[id].where=="held":return id
	return -1

func worn_belt(peer: int) -> int:
	for id in belts.size():
		if int(belts[id].owner)==peer and belts[id].where=="worn":return id
	return -1

func belt_mass(id: int) -> float:
	if id not in range(belts.size()):return 0.0
	var total:=BELT_KG
	for plate in plates:
		if plate.station=="belt/%d" % id:total+=float(plate.lb)*LB_TO_KG
	return total

func worn_belt_mass(peer: int) -> float:
	return belt_mass(worn_belt(peer))

func belt_for_rack_return(target: Node, peer: int) -> int:
	if not is_instance_valid(target):return -1
	var role: String=target.get_meta("role","")
	if role=="gym_weight_belt" or role=="gym_belt_plate":
		var id:=int(target.get_meta("id" if role=="gym_weight_belt" else "belt_id",-1))
		if id not in range(belts.size()) or belts[id].where!="rack":return -1
	elif role!="gym_belt_return":return -1
	var held:=held_belt(peer)
	return held if held>=0 else worn_belt(peer)

func interact(target: Node, allow_assist := true) -> bool:
	if not is_instance_valid(target) or target.get_meta("role","") not in ["gym_barbell_sleeve","gym_barbell_rack","gym_bar_rescue","gym_barbell_floor","gym_plate_rack","gym_plate_rod","gym_plate_rack_item","gym_plate_floor","gym_weight_belt","gym_belt_plate","gym_belt_return"]:return false
	var returning:=belt_for_rack_return(target,multiplayer.get_unique_id())
	if returning>=0:
		if allow_assist:request_belt("return",returning)
		return true
	if target.get_meta("role","")=="gym_belt_return":
		if allow_assist:
			var belt := held_belt(multiplayer.get_unique_id())
			if belt < 0: belt = worn_belt(multiplayer.get_unique_id())
			if belt>=0:request_belt("return",belt)
			else:game.ui.log_message("Hold or wear a weight belt to return it here.")
		return true
	selected_station=str(target.get_meta("station",""))
	if trapped.has(selected_station) and int(trapped[selected_station])!=multiplayer.get_unique_id():
		if not allow_assist: return true
		game.campus_services.facility_panel.request_direct({"op":"assist","target":int(trapped[selected_station])})
		return true
	if target.get_meta("role","")=="gym_barbell_rack":
		var current_bar:=held_bar(multiplayer.get_unique_id())
		if current_bar==selected_station:
			request("return_bar",selected_station,0.0,0);game.ui.log_message("Barbell reracked.")
		elif current_bar.is_empty() and bars.has(selected_station) and bars[selected_station].where in ["rack","floor"]:
			if game.hotbar.slots.any(func(slot):return slot.is_empty()) and game.hotbar.stow():request("pickup_bar",selected_station,0.0,0)
			else:game.ui.log_message("Free a hotbar slot first.")
		return true
	# Bar plates are operated directly in 3D with the mouse. Do not open the old
	# loading menu when the player presses the generic interact key on a sleeve.
	if target.get_meta("role","") in ["gym_barbell_sleeve","gym_barbell_plate"]:return true
	if target.get_meta("role","")=="gym_weight_belt":
		var belt_id:=int(target.get_meta("id",-1));var held:=held_plate(multiplayer.get_unique_id())
		if held>=0:
			request_plate("belt_attach",held,"belt/%d" % belt_id)
		elif belt_id in range(belts.size()):
			if not game.hotbar.slots.any(func(slot):return slot.is_empty()):game.ui.log_message("Free a hotbar slot first.")
			elif game.hotbar.stow():request_belt("pickup",belt_id)
		return true
	if target.get_meta("role","")=="gym_belt_plate":
		var belt_id:=int(target.get_meta("belt_id",-1));var station:="belt/%d" % belt_id
		if not game.hotbar.slots.any(func(slot):return slot.is_empty()):game.ui.log_message("Free a hotbar slot before removing a belt plate.")
		elif game.hotbar.stow():request_plate("belt_detach",-1,station)
		return true
	if target.get_meta("role","")=="gym_plate_rod":
		var held := held_plate(multiplayer.get_unique_id())
		var slot := int(target.get_meta("slot",-1))
		if held >= 0:
			if float(plates[held].lb) != SIZES[slot]:
				game.ui.log_message("Use the rod marked %.1f lb for this plate." % float(plates[held].lb))
			elif _rack_count(slot) >= COUNTS[slot]:
				game.ui.log_message("This plate rod is full.")
			else:
				request_plate("return",held,"rod",slot)
		return true
	if target.get_meta("role","")=="gym_plate_rack_item":
		if not game.hotbar.slots.any(func(slot):return slot.is_empty()):game.ui.log_message("Free a hotbar slot first.");return true
		if game.hotbar.stow():request_plate("pickup",int(target.get_meta("id",-1)))
		return true
	if target.get_meta("role","")=="gym_plate_floor":
		if not game.hotbar.slots.any(func(slot):return slot.is_empty()):game.ui.log_message("Free a hotbar slot first.");return true
		if game.hotbar.stow():request_plate("pickup",int(target.get_meta("id",-1)))
		return true
	if target.get_meta("role","")=="gym_barbell_floor":
		if not game.hotbar.slots.any(func(slot):return slot.is_empty()):game.ui.log_message("Free a hotbar slot first.");return true
		if game.hotbar.stow():request("pickup_bar",selected_station,0.0,0)
		return true
	return false

func click_bar_target(target: Node) -> bool:
	if not is_instance_valid(target):return false
	var role:=str(target.get_meta("role",""))
	if role not in ["gym_barbell_sleeve","gym_barbell_plate"]:return false
	var station:=str(target.get_meta("station",""))
	var side:=int(target.get_meta("side",0))
	if not POSITIONS.has(station) or side not in [-1,1]:return true
	if role=="gym_barbell_plate":
		if not game.hotbar.slots.any(func(slot):return slot.is_empty()):
			game.ui.log_message("Free a hotbar slot before removing a plate.")
			return true
		if game.hotbar.stow():request_plate("detach",-1,station,side)
		return true
	var id:=held_plate(multiplayer.get_unique_id())
	if id>=0:
		request_plate("attach",id,station,side)
	return true

func _room_event(peer: int,event: Dictionary) -> void:
	if event.get("activity","") in ["exercise","trapped"] and event.get("equipment","")=="barbell":bar_activities[peer]=event.duplicate(true)
	elif event.get("activity","") in ["idle","trapped","seat","emote"]:bar_activities.erase(peer)
	for station in trapped.keys():
		if int(trapped[station])==peer:trapped.erase(station)
	if event.get("activity","")=="trapped":
		var bar_id:=held_bar(peer) if event.get("equipment","")=="barbell" else str(event.get("station",""))
		if POSITIONS.has(bar_id):trapped[bar_id]=peer

func _refresh() -> void:
	for child in list.get_children():list.remove_child(child);child.queue_free()
	if selected_station.is_empty():
		_refresh_rack();return
	if selected_station.begins_with("belt/"):
		_refresh_belt();return
	var title:=Label.new();title.text="BARBELL  /  PLATE LOADING";title.add_theme_font_size_override("font_size",22);list.add_child(title)
	detail=Label.new();detail.text="Total %.1f lb  ·  bar %.0f lb" % [loaded_mass(selected_station)*2.20462262,BAR_KG*2.20462262];list.add_child(detail)
	var hint:=Label.new();hint.text="Bring a plate from the rack to attach it to either sleeve.";list.add_child(hint)
	for lb in SIZES:
		var available:=0
		for plate in plates:
			if plate.where=="rack" and float(plate.lb)==float(lb):available+=1
		var row:=HBoxContainer.new();list.add_child(row)
		var text:=Label.new();text.text="%.1f lb  ·  %d available" % [lb,available];text.size_flags_horizontal=Control.SIZE_EXPAND_FILL;row.add_child(text)
	var row:=HBoxContainer.new();list.add_child(row)
	var plate_id:=held_plate(multiplayer.get_unique_id())
	for side in [-1,1]:
		var attach:=Button.new();attach.text="Attach held · left" if side<0 else "Attach held · right";attach.disabled=plate_id<0;row.add_child(attach)
		attach.pressed.connect(func():request_plate("attach",plate_id,selected_station,side))
	row=HBoxContainer.new();list.add_child(row)
	for side in [-1,1]:
		var button:=Button.new();button.text="Remove left" if side<0 else "Remove right";button.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		button.pressed.connect(func():
			if not game.hotbar.slots.any(func(slot):return slot.is_empty()):game.ui.log_message("Free a hotbar slot first.");return
			if game.hotbar.stow():request_plate("detach",-1,selected_station,side);_close());row.add_child(button)
	var take:=Button.new();take.text="Pick up loaded bar";list.add_child(take)
	take.disabled=bars.get(selected_station,{}).get("where","")!="rack"
	take.pressed.connect(func():
		if not game.hotbar.slots.any(func(slot):return slot.is_empty()):game.ui.log_message("Free a hotbar slot first.");return
		if game.hotbar.stow():request("pickup_bar",selected_station,0.0,0);_close())
	var return_button:=Button.new();return_button.text="Return held bar to this rack";list.add_child(return_button)
	return_button.disabled=held_bar(multiplayer.get_unique_id())!=selected_station
	return_button.pressed.connect(func():request("return_bar",selected_station,0.0,0);_close())
	var close:=Button.new();close.text="Close";close.pressed.connect(_close);list.add_child(close)

func _refresh_rack() -> void:
	var title:=Label.new();title.text="WEIGHT PLATES";title.add_theme_font_size_override("font_size",22);list.add_child(title)
	for lb in SIZES:
		var first:=-1;var available:=0
		for id in plates.size():
			if plates[id].where=="rack" and float(plates[id].lb)==float(lb):
				available+=1
				if first<0:first=id
		var button:=Button.new();button.text="Take %.1f lb  ·  %d available" % [lb,available];button.disabled=first<0;list.add_child(button)
		button.pressed.connect(func():
			if not game.hotbar.slots.any(func(slot):return slot.is_empty()):game.ui.log_message("Free a hotbar slot first.");return
			if game.hotbar.stow():request_plate("pickup",first);_close())
	var id:=held_plate(multiplayer.get_unique_id())
	var put:=Button.new();put.text="Return held plate";put.disabled=id<0;list.add_child(put)
	put.pressed.connect(func():request_plate("return",id);_close())
	var held_belt_id:=held_belt(multiplayer.get_unique_id())
	if held_belt_id < 0: held_belt_id = worn_belt(multiplayer.get_unique_id())
	var belt_return:=Button.new();belt_return.text="Return weight belt";belt_return.disabled=held_belt_id<0;list.add_child(belt_return)
	belt_return.pressed.connect(func():request_belt("return",held_belt_id);_close())
	var close:=Button.new();close.text="Close";close.pressed.connect(_close);list.add_child(close)

func _refresh_belt() -> void:
	var id:=int(selected_station.trim_prefix("belt/"))
	if id not in range(belts.size()):return
	var title:=Label.new();title.text="WEIGHT BELT";title.add_theme_font_size_override("font_size",22);list.add_child(title)
	var status:=Label.new();status.text="Total %.1f lb · belt %.1f lb" % [belt_mass(id)*2.20462262,BELT_KG*2.20462262];list.add_child(status)
	for plate in plates:
		if plate.station==selected_station:
			var label:=Label.new();label.text="Attached: %.1f lb" % float(plate.lb);list.add_child(label)
	var plate_id:=held_plate(multiplayer.get_unique_id())
	var attach:=Button.new();attach.text="Attach held plate";attach.disabled=plate_id<0;list.add_child(attach)
	attach.pressed.connect(func():request_plate("belt_attach",plate_id,selected_station))
	var detach:=Button.new();detach.text="Remove outermost plate";list.add_child(detach)
	detach.pressed.connect(func():
		if not game.hotbar.slots.any(func(slot):return slot.is_empty()):game.ui.log_message("Free a hotbar slot first.");return
		if game.hotbar.stow():request_plate("belt_detach",-1,selected_station);_close())
	var take:=Button.new();take.text="Pick up belt";list.add_child(take)
	take.pressed.connect(func():
		if not game.hotbar.slots.any(func(slot):return slot.is_empty()):game.ui.log_message("Free a hotbar slot first.");return
		if game.hotbar.stow():request_belt("pickup",id);_close())
	var close:=Button.new();close.text="Close";close.pressed.connect(_close);list.add_child(close)

func _close() -> void:
	panel.hide()
	if game.front.in_game:game.capture()

func request(op: String, station: String, lb: float, side: int,point: Variant=null) -> void:
	if multiplayer.is_server():_accept(multiplayer.get_unique_id(),op,station,lb,side,point)
	elif game.session.online:_command.rpc_id(1,op,station,lb,side,point)

@rpc("any_peer","call_remote","reliable")
func _command(op: String, station: String, lb: float, side: int,point: Variant) -> void:
	if multiplayer.is_server():_accept(multiplayer.get_remote_sender_id(),op,station,lb,side,point)

func _accept(peer: int,op: String,station: String,_lb: float,_side: int,point: Variant=null) -> void:
	if not game.session.roster.has(peer) or not POSITIONS.has(station):return
	if point!=null and (not point is Vector3 or not point.is_finite()):return
	var position: Vector3=game.player.global_position if peer==multiplayer.get_unique_id() else game.session.poses.get(peer,{}).get("position",Vector3.INF)
	if not position.is_finite():return
	if game.campus_services.facilities.controller.host.movement_locked(peer):return
	if game.campus_services.facilities.controller.host.seats.has(station):return
	var bar: Dictionary=bars[station]
	if op=="pickup_bar":
		if not held_bar(peer).is_empty() or bar.where not in ["rack","floor"]:return
		var pickup: Vector3=POSITIONS[station] if bar.where=="rack" else bar.position
		if position.distance_to(pickup)>3.0:return
		bar.owner=peer;bar.where="held";_publish();return
	if op in ["stow_bar","equip_bar","drop_bar","return_bar"]:
		if int(bar.owner)!=peer:return
		if op=="stow_bar" and bar.where=="held":bar.where="stowed"
		elif op=="equip_bar" and bar.where=="stowed" and held_bar(peer).is_empty():bar.where="held"
		elif op=="return_bar" and bar.where=="held" and position.distance_to(POSITIONS[station])<=3.0:bar.where="rack";bar.owner=0
		elif op=="drop_bar" and bar.where=="held":
			var ground: Variant=preload("res://scripts/campus/items/placement_target.gd").host_position(game.school,point,position,peer)
			if not ground is Vector3:return
			bar.where="floor";bar.owner=0;bar.position=ground
		else:return
		_publish();return
	# Plates must travel through _accept_plate so an actual held item is consumed
	# or returned to the player's hand, including for remote requests.

func request_plate(op: String,id: int,station: String="",side: int=0,point: Variant=null) -> void:
	if multiplayer.is_server():_accept_plate(multiplayer.get_unique_id(),op,id,station,side,point)
	elif game.session.online:_plate_command.rpc_id(1,op,id,station,side,point)

@rpc("any_peer","call_remote","reliable")
func _plate_command(op: String,id: int,station: String,side: int,point: Variant) -> void:
	if multiplayer.is_server():_accept_plate(multiplayer.get_remote_sender_id(),op,id,station,side,point)

func _accept_plate(peer: int,op: String,id: int,station: String,side: int,point: Variant=null) -> void:
	if not game.session.roster.has(peer):return
	if point!=null and (not point is Vector3 or not point.is_finite()):return
	var position: Vector3=game.player.global_position if peer==multiplayer.get_unique_id() else game.session.poses.get(peer,{}).get("position",Vector3.INF)
	if not position.is_finite() or game.campus_services.facilities.controller.host.movement_locked(peer):return
	if op in ["cable_attach","cable_detach"]:
		var machine: Node=game.campus_services._cable_machine(station)
		if not is_instance_valid(machine) or game.campus_services.facilities.controller.host.seats.has(station):return
		if position.distance_to(machine.loading_mount.global_position-Vector3.UP)>3.0:return
		var stack:=cable_plates(station)
		if op=="cable_detach":
			if stack.is_empty() or id!=int(stack.back()) or held_plate(peer)>=0:return
			plates[id].station="";plates[id].side=0;plates[id].order=0;plates[id].where="held";plates[id].owner=peer
		else:
			if id not in range(plates.size()) or int(plates[id].owner)!=peer or plates[id].where!="held" or stack.size()>=machine.PLATE_LIMIT:return
			serial+=1;plates[id].station=station;plates[id].where="attached";plates[id].owner=0;plates[id].side=0;plates[id].order=serial
		_publish();return
	if op in ["belt_attach","belt_detach"]:
		var suffix:=station.trim_prefix("belt/")
		if not station.begins_with("belt/") or not suffix.is_valid_int():return
		var belt_id:=int(suffix)
		if belt_id not in range(belts.size()) or belts[belt_id].where not in ["rack","floor"] or position.distance_to(belts[belt_id].position)>3.0:return
		if op=="belt_detach":
			if held_plate(peer)>=0:return
			var outermost:=-1;var newest:=-1
			for index in plates.size():
				if plates[index].station==station and int(plates[index].order)>newest:outermost=index;newest=int(plates[index].order)
			if outermost<0:return
			var detached: Dictionary=plates[outermost]
			detached.station="";detached.side=0;detached.order=0;detached.where="held";detached.owner=peer;_publish();return
		if id not in range(plates.size()) or int(plates[id].owner)!=peer or plates[id].where!="held":return
		var attached_count:=0
		for candidate in plates:
			if candidate.station==station:attached_count+=1
		if attached_count>=6:return
		serial+=1;plates[id].station=station;plates[id].where="attached";plates[id].owner=0;plates[id].side=0;plates[id].order=serial;_publish();return
	if op=="detach":
		if not POSITIONS.has(station) or side not in [-1,1] or bars[station].where!="rack" or position.distance_to(POSITIONS[station])>3.0 or game.campus_services.facilities.controller.host.seats.has(station) or held_plate(peer)>=0:return
		var outermost:=-1;var newest:=-1
		for index in plates.size():
			var candidate: Dictionary=plates[index]
			if candidate.station==station and candidate.side==side and int(candidate.order)>newest:outermost=index;newest=int(candidate.order)
		if outermost<0:return
		var plate: Dictionary=plates[outermost]
		plate.station="";plate.side=0;plate.order=0;plate.where="held";plate.owner=peer;_publish();return
	if id not in range(plates.size()):return
	var plate: Dictionary=plates[id]
	if op=="pickup":
		if held_plate(peer)>=0 or plate.where not in ["rack","floor"]:return
		var pickup: Vector3=PLATE_RACK if plate.where=="rack" else plate.position
		if position.distance_to(pickup)>3.0:return
		plate.where="held";plate.owner=peer
	elif op=="stow":
		if int(plate.owner)!=peer or plate.where!="held":return
		plate.where="stowed"
	elif op=="equip":
		if int(plate.owner)!=peer or plate.where!="stowed" or held_plate(peer)>=0:return
		plate.where="held"
	elif op=="return":
		var slot := SIZES.find(float(plate.lb))
		if slot < 0 or (station == "rod" and side != slot) or _rack_count(slot) >= COUNTS[slot]:return
		var end := _rack_position(_peg_base(slot) + Vector3(PEG_START + COUNTS[slot]*PLATE_GAP,0,0))
		if int(plate.owner)!=peer or plate.where!="held" or position.distance_to(end)>3.0:return
		plate.where="rack";plate.owner=0
	elif op=="drop":
		if int(plate.owner)!=peer or plate.where!="held":return
		var ground: Variant=preload("res://scripts/campus/items/placement_target.gd").host_position(game.school,point,position,peer)
		if not ground is Vector3:return
		plate.where="floor";plate.owner=0;plate.position=ground
	elif op=="attach":
		if int(plate.owner)!=peer or plate.where!="held" or not POSITIONS.has(station) or side not in [-1,1] or bars[station].where!="rack" or position.distance_to(POSITIONS[station])>3.0 or game.campus_services.facilities.controller.host.seats.has(station):return
		var count:=0
		for candidate in plates:
			if candidate.station==station and candidate.side==side:count+=1
		if count>=8:return
		serial+=1;plate.where="attached";plate.owner=0;plate.station=station;plate.side=side;plate.order=serial
	else:return
	_publish()

func request_belt(op: String,id: int,point: Variant=null) -> void:
	if multiplayer.is_server():_accept_belt(multiplayer.get_unique_id(),op,id,point)
	elif game.session.online:_belt_command.rpc_id(1,op,id,point)

@rpc("any_peer","call_remote","reliable")
func _belt_command(op: String,id: int,point: Variant) -> void:
	if multiplayer.is_server():_accept_belt(multiplayer.get_remote_sender_id(),op,id,point)

func _report_return_error(peer: int, message: String) -> void:
	if peer==multiplayer.get_unique_id():_belt_return_error(message)
	elif game.session.online and game.session.peer_connected_now(peer):_belt_return_error.rpc_id(peer,message)

@rpc("authority","call_remote","reliable")
func _belt_return_error(message: String) -> void:
	game.ui.log_message(message)

func _accept_belt(peer: int,op: String,id: int,point: Variant=null) -> void:
	if not game.session.roster.has(peer) or id not in range(belts.size()):return
	if point!=null and (not point is Vector3 or not point.is_finite()):return
	var position: Vector3=game.player.global_position if peer==multiplayer.get_unique_id() else game.session.poses.get(peer,{}).get("position",Vector3.INF)
	if not position.is_finite() or game.campus_services.facilities.controller.host.movement_locked(peer):
		if op=="return":_report_return_error(peer,"You cannot return a belt while movement is restricted.")
		return
	var belt: Dictionary=belts[id]
	if op=="pickup":
		if held_belt(peer)>=0 or belt.where not in ["rack","floor"] or position.distance_to(belt.position)>3.0:return
		belt.owner=peer;belt.where="held"
	elif op=="stow":
		if int(belt.owner)!=peer or belt.where!="held":return
		belt.where="stowed"
	elif op=="equip":
		if int(belt.owner)!=peer or belt.where!="stowed" or held_belt(peer)>=0:return
		belt.where="held"
	elif op=="wear":
		if int(belt.owner)!=peer or belt.where!="held" or worn_belt(peer)>=0:return
		if "carry_load" in game and is_instance_valid(game.carry_load):
			var profile: Dictionary=game.carry_load.profile_for(peer)
			if preload("res://scripts/campus/facilities/accessory_layout.gd").persistent_count(profile)>=4:return
		belt.where="worn"
	elif op=="unwear":
		if int(belt.owner)!=peer or belt.where!="worn" or held_belt(peer)>=0:return
		belt.where="held"
	elif op=="drop":
		if int(belt.owner)!=peer or belt.where!="held":return
		var ground: Variant=preload("res://scripts/campus/items/placement_target.gd").host_position(game.school,point,position,peer)
		if not ground is Vector3:return
		belt.where="floor";belt.owner=0;belt.position=ground
	elif op=="return":
		if int(belt.owner)!=peer or belt.where not in ["held","worn"]:
			_report_return_error(peer,"Hold or wear your weight belt before returning it.")
			return
		if position.distance_to(BELT_RACK+Vector3(0,0,BELT_SPACING*1.5))>3.0:
			_report_return_error(peer,"Move closer to the weight belt rack.")
			return
		belt.where="rack";belt.owner=0;belt.position=BELT_RACK+Vector3(0,0,id*BELT_SPACING)
	else:return
	_publish()

func _publish() -> void:
	_render()
	_broadcast()

func _broadcast() -> void:
	if game.session.online:
		for peer in game.session.roster:
			if int(peer)!=multiplayer.get_unique_id() and game.session.peer_connected_now(int(peer)):_receive.rpc_id(int(peer),plates,bars,belts)

@rpc("authority","call_remote","reliable")
func _receive(value: Array, bar_state: Dictionary, belt_state: Array) -> void:
	if value.size()!=plates.size() or bar_state.size()!=POSITIONS.size() or belt_state.size()!=belts.size() or (value==plates and bar_state==bars and belt_state==belts):return
	plates=value.duplicate(true);bars=bar_state.duplicate(true);belts=belt_state.duplicate(true);_render()

func cable_plates(station: String) -> Array[int]:
	var stack: Array[int]=[]
	for id in plates.size():
		if plates[id].where=="attached" and plates[id].station==station:stack.append(id)
	stack.sort_custom(func(a,b):return int(plates[a].order)<int(plates[b].order))
	return stack

func cable_extra_mass(station: String) -> float:
	var mass:=0.0
	for id in cable_plates(station):
		mass+=float(plates[id].lb)*LB_TO_KG
	return mass

func _render_cable_plate(plate_id: int, machine: Node, ordinal: int, topmost: bool) -> void:
	var plate: Dictionary=plates[plate_id]
	var target:=StaticBody3D.new()
	target.name="CablePlate_%d" % plate_id
	target.collision_layer=4 if topmost else 0;target.collision_mask=0
	target.set_meta("role","gym_cable_plate");target.set_meta("station",plate.station)
	target.set_meta("id",plate_id)
	machine.loading_mount.add_child(target)
	var level: float=.067+ordinal*machine.PLATE_SPACING
	target.position.y=level
	var visual:=_plate_model(float(plate.lb))
	target.add_child(visual)
	visual.position.y=.10
	visual.create_tween().tween_property(visual,"position:y",0.0,.20).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	var hit:=CollisionShape3D.new()
	var shape:=CylinderShape3D.new()
	shape.radius=lerpf(.10,.30,sqrt(clampf(float(plate.lb),0.0,45.0)/45.0));shape.height=.084
	hit.shape=shape;target.add_child(hit)
	models[plate_id]=target

func _render() -> void:
	if is_instance_valid(belt_return_target):
		var peer:=multiplayer.get_unique_id()
		belt_return_target.collision_layer=4 if held_belt(peer)>=0 or worn_belt(peer)>=0 else 0
	for peer in remote_belts.keys():_clear_remote_belt(int(peer))
	for node in belt_models.values():
		if is_instance_valid(node):node.queue_free()
	belt_models.clear()
	for id in belts.size():
		if belts[id].where not in ["rack","floor"]:continue
		var belt:=StaticBody3D.new();belt.position=belts[id].position;belt.collision_layer=4;belt.collision_mask=0
		belt.set_meta("role","gym_weight_belt");belt.set_meta("id",id);belt.set_meta("label","Weight belt");add_child(belt)
		var on_rack: bool=belts[id].where=="rack"
		var visual:=_belt_model(id, not on_rack, on_rack)
		if not on_rack: visual.position.y=.08
		belt.add_child(visual)
		var hit:=CollisionShape3D.new()
		if on_rack:
			var shape:=BoxShape3D.new();shape.size=Vector3(.54,.54,.18);hit.shape=shape
		else:
			var shape:=CylinderShape3D.new();shape.radius=.3;shape.height=.18;hit.shape=shape;hit.position.y=.09
		belt.add_child(hit);belt_models[id]=belt
	for node in rack_models.values():
		if is_instance_valid(node):node.queue_free()
	rack_models.clear()
	var rack_order:={}
	for id in plates.size():
		if plates[id].where!="rack":continue
		var lb:=float(plates[id].lb);var slot:=SIZES.find(lb)
		var ordinal:=int(rack_order.get(lb,0));rack_order[lb]=ordinal+1
		var target:=StaticBody3D.new();target.position=_rack_position(_peg_base(slot)+Vector3(PEG_START+.05+float(ordinal)*PLATE_GAP,0,0))
		target.rotation.y = PI/2
		target.collision_layer=4;target.collision_mask=0;target.set_meta("role","gym_plate_rack_item");target.set_meta("id",id);target.set_meta("label","Pick up %.1f lb plate" % lb);add_child(target)
		var disk:=_plate_model(lb)
		disk.basis=Basis(Vector3.BACK, PI/2)*Basis(Vector3.UP, PI/2)
		target.add_child(disk)
		var hit:=CollisionShape3D.new();var shape:=CylinderShape3D.new();shape.radius=lerpf(.10,.30,sqrt(clampf(lb,0.0,45.0)/45.0));shape.height=.086;hit.shape=shape;hit.rotation.z=PI/2;target.add_child(hit)
		rack_models[id]=target
	for node in models.values():
		if is_instance_valid(node):node.queue_free()
	models.clear()
	var motion: Node=game.campus_services.gym_motion
	if not is_instance_valid(motion):return
	for node in floor_models.values():
		if is_instance_valid(node):node.queue_free()
	floor_models.clear()
	for node in plate_floor_models.values():
		if is_instance_valid(node):node.queue_free()
	plate_floor_models.clear()
	for id in plates.size():
		if plates[id].where!="floor":continue
		var target:=StaticBody3D.new();target.position=plates[id].position;target.collision_layer=4;target.collision_mask=0
		target.set_meta("role","gym_plate_floor");target.set_meta("id",id);target.set_meta("label","%.1f lb plate" % float(plates[id].lb));add_child(target)
		var visual:=_plate_model(float(plates[id].lb));visual.position.y=.045;target.add_child(visual)
		var hit:=CollisionShape3D.new();var shape:=CylinderShape3D.new();shape.radius=.3;shape.height=.12;hit.shape=shape;hit.position.y=.06;target.add_child(hit);plate_floor_models[id]=target
	for station in bars:
		if bar_colliders.has(station):bar_colliders[station].collision_layer=1 if bars[station].where=="rack" else 0
		if motion.bars.has(station):motion.bars[station].visible=bars[station].where=="rack"
		if bars[station].where=="floor":
			var target:=StaticBody3D.new();target.position=bars[station].position;target.collision_layer=4;target.collision_mask=0
			target.set_meta("role","gym_barbell_floor");target.set_meta("station",station);target.set_meta("label","Barbell")
			add_child(target);var hit:=CollisionShape3D.new();var shape:=BoxShape3D.new();shape.size=Vector3(GymLayout.BAR_LENGTH,.4,.5);hit.shape=shape;hit.position.y=.2;target.add_child(hit)
			var bar_model:=_bar_model(station);bar_model.position.y=.25;target.add_child(bar_model);floor_models[station]=target
	var counts:={}
	var attached: Array=[]
	for id in plates.size():
		if plates[id].station!="":attached.append(id)
	attached.sort_custom(func(a,b):return int(plates[a].order)<int(plates[b].order))
	for id in attached:
		var plate: Dictionary=plates[id]
		if str(plate.station).begins_with("gym/cable_"):
			var machine: Node=game.campus_services._cable_machine(plate.station)
			if is_instance_valid(machine):
				var stack:=cable_plates(plate.station)
				var ordinal:=stack.find(id)
				_render_cable_plate(id,machine,ordinal,ordinal==stack.size()-1)
			continue
		if plate.station=="" or not motion.bars.has(plate.station):continue
		var key: String=plate.station+str(plate.side)
		var ordinal:=int(counts.get(key,0));counts[key]=ordinal+1
		var target:=StaticBody3D.new();target.name="LoadedPlate_%d" % id
		target.position.x=float(plate.side)*(1.0+ordinal*SLEEVE_STEP)
		target.collision_layer=4;target.collision_mask=0
		target.set_meta("role","gym_barbell_plate");target.set_meta("id",id)
		target.set_meta("station",plate.station);target.set_meta("side",plate.side)
		target.set_meta("label","Remove %.1f lb plate" % float(plate.lb))
		var visual:=_plate_model(float(plate.lb));visual.rotation.z=PI/2;target.add_child(visual)
		var collision:=CollisionShape3D.new();var disk_shape:=CylinderShape3D.new()
		disk_shape.radius=lerpf(.10,.30,sqrt(clampf(float(plate.lb),0.0,45.0)/45.0));disk_shape.height=.14
		collision.shape=disk_shape;collision.rotation.z=PI/2;target.add_child(collision)
		motion.bars[plate.station].add_child(target);models[id]=target
	if panel.visible:_refresh()

func _plate_model(lb: float) -> MeshInstance3D:
	if not plate_meshes.has(lb):plate_meshes[lb]=_plate_mesh(lb)
	if plate_material==null:
		plate_material=StandardMaterial3D.new();plate_material.albedo_color=Color("424b50");plate_material.roughness=.86
		plate_material.metallic=.04
	if plate_accent_material==null:
		plate_accent_material=StandardMaterial3D.new();plate_accent_material.albedo_color=Color("75848a");plate_accent_material.metallic=.42;plate_accent_material.roughness=.48
	if plate_engraving_material==null:
		plate_engraving_material=StandardMaterial3D.new();plate_engraving_material.albedo_color=Color("9aa7aa");plate_engraving_material.metallic=.12;plate_engraving_material.roughness=.78
	var visual:=MeshInstance3D.new();visual.mesh=plate_meshes[lb];visual.material_override=plate_material
	# A steel sleeve surrounds the open bore.
	for face in [-1.0,1.0]:
		# The plate's bevel is built into its mesh. Avoid a large raised metal
		# hoop here; it made the stack look like a set of oversized wire loops.
		var hub:=MeshInstance3D.new();var hub_mesh:=TorusMesh.new();hub_mesh.inner_radius=.047;hub_mesh.outer_radius=.061;hub_mesh.rings=24;hub_mesh.ring_segments=8
		hub.mesh=hub_mesh;hub.material_override=plate_accent_material;hub.position.y=face*.040;visual.add_child(hub)
		# TextMesh is deliberately recessed below the face and uses a dark groove
		# material. It is part of the plate model, never a billboard or floating UI.
		var text_mesh:=TextMesh.new();text_mesh.text=_plate_weight_text(lb);text_mesh.font_size=36;text_mesh.pixel_size=.00085;text_mesh.depth=.00012;text_mesh.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;text_mesh.vertical_alignment=VERTICAL_ALIGNMENT_CENTER
		var mark:=MeshInstance3D.new();mark.name="EngravedWeightFront" if face>0 else "EngravedWeightBack";mark.mesh=text_mesh;mark.material_override=plate_engraving_material;mark.rotation.x=-face*PI/2
		mark.position=Vector3(0,face*.040,-.089);visual.add_child(mark)
	return visual

func _plate_weight_text(lb: float) -> String:
	return "%.0f lbs" % lb if is_equal_approx(lb,roundf(lb)) else "%.1f lbs" % lb

func _plate_mesh(lb: float) -> ArrayMesh:
	var radius:=lerpf(.10,.30,sqrt(clampf(lb,0.0,45.0)/45.0))
	var inner:=.061;var half:=.043;var bevel:=minf(.009,radius*.055);var tool:=SurfaceTool.new();tool.begin(Mesh.PRIMITIVE_TRIANGLES);tool.set_smooth_group(-1)
	for i in 64:
		var a:=TAU*float(i)/64.0;var b:=TAU*float(i+1)/64.0
		var ao:=Vector2(cos(a),sin(a));var bo:=Vector2(cos(b),sin(b))
		# Cross-section is a softly bevelled rim, flat face, and recessed center
		# bore. This gives the plate a visible molded profile and real thickness.
		var rings: Array = [
			[ radius-bevel, half-.004 ], [ radius, half-bevel ], [ radius, -half+bevel ], [ radius-bevel, -half+.004 ],
			[ inner+bevel, -half+.004 ], [ inner, -half+bevel ], [ inner, half-bevel ], [ inner+bevel, half-.004 ]
		]
		for section in rings.size():
			var next: int=(section+1)%rings.size()
			var ra:=float(rings[section][0]);var ya:=float(rings[section][1]);var rb:=float(rings[next][0]);var yb:=float(rings[next][1])
			var va:=Vector3(ao.x*ra,ya,ao.y*ra);var vb:=Vector3(bo.x*ra,ya,bo.y*ra)
			var vc:=Vector3(ao.x*rb,yb,ao.y*rb);var vd:=Vector3(bo.x*rb,yb,bo.y*rb)
			tool.add_vertex(va);tool.add_vertex(vc);tool.add_vertex(vb)
			tool.add_vertex(vb);tool.add_vertex(vc);tool.add_vertex(vd)
	tool.generate_normals()
	return tool.commit()

func _belt_model(id: int, flat := false, hanging := false) -> Node3D:
	var root:=Node3D.new();var ring:=MeshInstance3D.new();var mesh:=TorusMesh.new();mesh.inner_radius=.20;mesh.outer_radius=.24;mesh.rings=20;mesh.ring_segments=12;ring.mesh=mesh
	var leather:=StandardMaterial3D.new();leather.albedo_color=Color("6b5140");leather.roughness=.9;ring.material_override=leather;root.add_child(ring)
	if hanging: ring.rotation.x = PI / 2.0
	var attached := plates.filter(func(plate): return plate.station == "belt/%d" % id)
	attached.sort_custom(func(a,b):return int(a.order)<int(b.order))
	if attached.is_empty():
		return root
	var steel := StandardMaterial3D.new()
	steel.albedo_color=Color("7f8b91");steel.metallic=.65;steel.roughness=.49
	var span := maxf(.11, attached.size()*PLATE_GAP)
	var axle := Vector3(0,-.49,-.04) if hanging else Vector3(0,-.40,-.29)
	if flat: axle = Vector3(.39,.055,0)
	if flat:
		_connector(root, Vector3(.19,.035,0), axle, steel)
		_connector(root, axle, axle+Vector3.UP*span, steel)
	else:
		for side in [-1.0,1.0]:
			var attachment := Vector3(side*.13,-.177,0) if hanging else Vector3(side*.13,-.025,-.173)
			_connector(root, attachment, axle+Vector3(side*span*.5,0,0), steel)
		_connector(root, axle-Vector3(span*.54,0,0), axle+Vector3(span*.54,0,0), steel)
	for index in attached.size():
		var plate: Dictionary = attached[index]
		var target := StaticBody3D.new()
		target.set_meta("role","gym_belt_plate")
		target.set_meta("belt_id",id)
		target.set_meta("label","Remove belt plate")
		target.collision_layer=4;target.collision_mask=0
		if flat:
			target.position = axle + Vector3.UP*(.052+index*PLATE_GAP)
		else:
			target.position = axle + Vector3((index-(attached.size()-1)*.5)*PLATE_GAP,0,0)
			target.rotation.z = PI/2
		var disk := _plate_model(float(plate.lb))
		target.add_child(disk)
		var hit := CollisionShape3D.new()
		var shape := CylinderShape3D.new()
		shape.radius = disk.mesh.get_aabb().size.x*.5
		shape.height = .086
		hit.shape=shape
		target.add_child(hit)
		root.add_child(target)
	return root

func _connector(parent: Node3D, start: Vector3, end: Vector3, material: Material) -> void:
	var visual := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = .014
	mesh.bottom_radius = .014
	mesh.height = start.distance_to(end)
	mesh.radial_segments = 8
	visual.mesh = mesh
	visual.material_override = material
	visual.position = (start+end)*.5
	visual.basis = Basis(Quaternion(Vector3.UP,(end-start).normalized()))
	parent.add_child(visual)

func _bar_model(station: String) -> Node3D:
	var root:=Node3D.new()
	var shaft:=MeshInstance3D.new();var mesh:=CylinderMesh.new();mesh.height=GymLayout.BAR_LENGTH;mesh.top_radius=.035;mesh.bottom_radius=.035;mesh.radial_segments=10;shaft.mesh=mesh;shaft.rotation.z=PI/2
	var metal:=StandardMaterial3D.new();metal.albedo_color=Color("aab8ba");metal.metallic=.7;metal.roughness=.4;shaft.material_override=metal;root.add_child(shaft)
	var count:={-1:0,1:0};var attached:=[]
	for plate in plates:
		if plate.station==station:attached.append(plate)
	attached.sort_custom(func(a,b):return int(a.order)<int(b.order))
	for plate in attached:
		var side:=int(plate.side);var disk:=_plate_model(float(plate.lb))
		disk.rotation.z=PI/2;disk.position.x=float(side)*(1.0+int(count[side])*SLEEVE_STEP);count[side]+=1
		root.add_child(disk)
	return root

func _sync_carried_models(delta: float) -> void:
	var wanted:={}
	for station in bars:
		var bar: Dictionary=bars[station];var peer:=int(bar.owner)
		if peer<=0 or peer==multiplayer.get_unique_id() or bar.where not in ["held","stowed"] or not game.avatars.has(peer):continue
		if str(bar_activities.get(peer,{}).get("station",""))=="gym/benchpress":continue
		var body:=game.avatars[peer].get_node_or_null("CharacterModel") as Node3D
		if not is_instance_valid(body):continue
		wanted[peer]=station
		if not carried_models.has(peer) or carried_models[peer].station!=station or carried_models[peer].body!=body:
			_clear_carried(peer)
			var visual:=_bar_model(station);visual.position=Vector3(0,1.15,.25);body.add_child(visual)
			carried_models[peer]={"station":station,"body":body,"visual":visual,"phase":0.0}
		var entry: Dictionary=carried_models[peer]
		var state: Dictionary=bar_activities.get(peer,{})
		entry.phase=move_toward(float(entry.phase),float(state.get("phase",0)),delta*1.2)
		var target:=Vector3(0,1.15,.25)
		if not state.is_empty():
			var kind:=str(state.exercise);var phase:=float(entry.phase)
			if kind=="squat":target=Vector3(0,1.30-phase*.25,.13)
			elif kind=="overhead_extension":target=Vector3(0,1.65+phase*.3,-.08)
			elif kind in ["curl","front_raise","upright_row"]:target=Vector3(0,.65+phase*.55,-.33)
			else:target=Vector3(0,.45+phase*.3,-.30)
			var joints=preload("res://scripts/campus/facilities/arm_bend.gd")
			var left: Node3D=joints.hand_for(body.find_child("ArmL",true,false) as Node3D)
			var right: Node3D=joints.hand_for(body.find_child("ArmR",true,false) as Node3D)
			if is_instance_valid(left) and is_instance_valid(right):target=body.to_local((left.global_position+right.global_position)*.5)
		entry.visual.position=entry.visual.position.lerp(target,minf(delta*5.0,1.0))
	for peer in carried_models.keys():
		if not wanted.has(peer):_clear_carried(int(peer))

func _sync_bench_models() -> void:
	var motion: Node=game.campus_services.gym_motion
	if not is_instance_valid(motion) or not motion.bars.has("gym/benchpress"):return
	var wanted:={}
	for station in bars:
		var bar: Dictionary=bars[station];var peer:=int(bar.owner)
		var activity: Dictionary=bar_activities.get(peer,{})
		if peer<=0 or bar.where!="held" or activity.get("equipment","")!="barbell" or activity.get("station","")!="gym/benchpress":continue
		wanted[peer]=true
		if not bench_models.has(peer) or bench_models[peer].station!=station:
			_clear_bench_model(peer)
			var visual:=_bar_model(station)
			motion.add_child(visual)
			bench_models[peer]={"station":station,"visual":visual}
		var bar_visual: Node3D=bench_models[peer].visual
		bar_visual.global_transform=motion.bars["gym/benchpress"].global_transform
	for peer in bench_models.keys():
		if not wanted.has(peer):_clear_bench_model(int(peer))

func _clear_bench_model(peer: int) -> void:
	if not bench_models.has(peer):return
	if is_instance_valid(bench_models[peer].visual):bench_models[peer].visual.queue_free()
	bench_models.erase(peer)

func _clear_carried(peer: int) -> void:
	if not carried_models.has(peer):return
	if is_instance_valid(carried_models[peer].visual):carried_models[peer].visual.queue_free()
	carried_models.erase(peer)

func _sync_remote_plates() -> void:
	var wanted:={}
	for id in plates.size():
		var plate: Dictionary=plates[id];var peer:=int(plate.owner)
		if peer<=0 or peer==multiplayer.get_unique_id() or plate.where!="held" or not game.avatars.has(peer):continue
		var body:=game.avatars[peer].get_node_or_null("CharacterModel") as Node3D
		if not is_instance_valid(body):continue
		var arm:=body.find_child("ArmR",true,false) as Node3D
		if not is_instance_valid(arm):continue
		wanted[peer]=id
		if remote_plates.has(peer) and int(remote_plates[peer].id)==id and remote_plates[peer].arm==arm:continue
		_clear_remote_plate(peer)
		var visual:=_plate_model(float(plate.lb));visual.position=Vector3(0,-.50,.08);visual.rotation.x=PI/2;arm.add_child(visual)
		remote_plates[peer]={"id":id,"arm":arm,"visual":visual}
	for peer in remote_plates.keys():
		if not wanted.has(peer):_clear_remote_plate(int(peer))

func _clear_remote_plate(peer: int) -> void:
	if not remote_plates.has(peer):return
	if is_instance_valid(remote_plates[peer].visual):remote_plates[peer].visual.queue_free()
	remote_plates.erase(peer)

func _sync_remote_belts() -> void:
	var wanted:={}
	for id in belts.size():
		var belt: Dictionary=belts[id];var peer:=int(belt.owner)
		if peer<=0 or peer==multiplayer.get_unique_id() or belt.where!="worn" or not game.avatars.has(peer):continue
		var body:=game.avatars[peer].get_node_or_null("CharacterModel") as Node3D
		if not is_instance_valid(body):continue
		wanted[peer]=id
		if remote_belts.has(peer) and int(remote_belts[peer].id)==id and remote_belts[peer].body==body:continue
		_clear_remote_belt(peer)
		var visual:=_belt_model(id);visual.position.y=.87;body.add_child(visual);remote_belts[peer]={"id":id,"body":body,"visual":visual}
	for peer in remote_belts.keys():
		if not wanted.has(peer):_clear_remote_belt(int(peer))

func _clear_remote_belt(peer: int) -> void:
	if not remote_belts.has(peer):return
	if is_instance_valid(remote_belts[peer].visual):remote_belts[peer].visual.queue_free()
	remote_belts.erase(peer)

func _roster_changed() -> void:
	if multiplayer.is_server():
		for bar in bars.values():
			if int(bar.owner)!=0 and not game.session.roster.has(int(bar.owner)):bar.owner=0;bar.where="rack"
		for plate in plates:
			if int(plate.owner)!=0 and not game.session.roster.has(int(plate.owner)):plate.owner=0;plate.where="rack"
		for id in belts.size():
			if int(belts[id].owner)!=0 and not game.session.roster.has(int(belts[id].owner)):
				belts[id].owner=0;belts[id].where="rack";belts[id].position=BELT_RACK+Vector3(0,0,id*BELT_SPACING)
		_publish()

func _reset() -> void:
	trapped.clear();bar_activities.clear()
	for peer in bench_models.keys():_clear_bench_model(int(peer))
	_reset_plates();_render()

func _sync_rescue_targets() -> void:
	var motion: Node = game.campus_services.gym_motion
	if not is_instance_valid(motion):
		return
	for station in rescue_targets:
		var target: StaticBody3D = rescue_targets[station]
		var peer:=int(trapped.get(station,0))
		target.collision_layer=0
		if peer<=0:continue
		var activity: Dictionary=bar_activities.get(peer,{})
		var visual: Node3D=motion.bars.get(station)
		if activity.get("equipment","")=="barbell":
			visual=bench_models.get(peer,{}).get("visual")
			if not is_instance_valid(visual):
				visual=bar_hand if peer==multiplayer.get_unique_id() else carried_models.get(peer,{}).get("visual")
		if is_instance_valid(visual):
			target.global_transform=visual.global_transform.orthonormalized()
			target.collision_layer=4
		elif activity.get("workout_position") is Vector3:
			target.global_position=activity.workout_position+Vector3.UP
			target.rotation.y=float(activity.get("workout_facing",0))
			target.collision_layer=4

func _process(delta: float) -> void:
	if not is_instance_valid(game):return
	_sync_carried_models(delta)
	_sync_bench_models()
	_sync_rescue_targets()
	_sync_remote_plates()
	_sync_remote_belts()
	var id:=held_plate(multiplayer.get_unique_id())
	if id!=plate_visual_id:
		plate_visual_id=id
		if is_instance_valid(plate_hand):plate_hand.queue_free();plate_hand=null
		if id>=0:
			plate_hand=_plate_model(float(plates[id].lb));game.camera.add_child(plate_hand);plate_hand.position=Vector3(.30,-.30,-.58);plate_hand.rotation.x=.65
	var hide_idle_gear: bool=game.workout_hides_carried_items()
	if is_instance_valid(plate_hand):plate_hand.visible=game.front.in_game and game.player.enabled and not hide_idle_gear
	var belt_id:=held_belt(multiplayer.get_unique_id())
	if belt_id!=belt_visual_id:
		belt_visual_id=belt_id
		if is_instance_valid(belt_hand):belt_hand.queue_free();belt_hand=null
		if belt_id>=0:
			belt_hand=_belt_model(belt_id);game.camera.add_child(belt_hand);belt_hand.position=Vector3(.30,-.25,-.6);belt_hand.rotation.x=.7
	if is_instance_valid(belt_hand):belt_hand.visible=game.front.in_game and game.player.enabled and not hide_idle_gear
	var bar_station:=held_bar(multiplayer.get_unique_id())
	if bar_station!=bar_visual_id:
		bar_visual_id=bar_station
		if is_instance_valid(bar_hand):bar_hand.queue_free();bar_hand=null
		if not bar_station.is_empty():bar_hand=_bar_model(bar_station);game.camera.add_child(bar_hand);bar_hand.position=Vector3(0,-.34,-.92);bar_hand.scale=Vector3(.55,.55,.55)
	if is_instance_valid(bar_hand):
		var exercise: Dictionary=game.campus_services.facility_panel.state.get("active",{})
		var bench_uses_world_bar: bool=hide_idle_gear and exercise.get("station")=="gym/benchpress"
		bar_hand.visible=game.front.in_game and game.player.enabled and (not hide_idle_gear or (exercise.get("equipment")=="barbell" and not bench_uses_world_bar))
		if not hide_idle_gear:bar_hand.position=Vector3(0,-.34,-.92)
	if is_instance_valid(game.interaction_presentation) and is_instance_valid(game.gym_weights):
		game.interaction_presentation.render_idle_gym_hold(bar_hand,game.gym_weights.held_visual)
	if not multiplayer.is_server() or not game.session.online:return
	broadcast_timer+=delta
	if broadcast_timer>=5.0:
		broadcast_timer=0.0
		_broadcast()
