extends SceneTree
## Actual Main/Studio/physical-board acceptance, scripted engine input only.
## No native controller, C/C++ toolchain, advanced display or external helper.
const Board=preload("res://scripts/breadboard_model.gd")
const SavedByteContract=preload("res://tests/acceptance/core_practice/test_reload_contract.gd")
const ReloadGuard=preload("res://tests/acceptance/core_practice/reload_guard.gd")
const Supported=preload("res://tests/acceptance/core_practice/supported_models.gd")
var game
var ui
var checks:=0
var failures:=0
var began:=0
var evidence:={"scope":"Scripted production callbacks, canvas hole events and world physics hits; not full manual mouse coverage","candidate":"J","phase":"practice-J3","stages":{}}
func _initialize() -> void:call_deferred("run")
func check(value: bool,label: String) -> void:
	checks+=1;print("PASS " if value else "FAIL ",label)
	if not value:failures+=1
func nodes(parent: Node) -> Array:
	var all: Array=[parent]
	for child in parent.get_children():all.append_array(nodes(child))
	return all
func button(parent: Node,title: String) -> Button:
	for item in nodes(parent):
		if item is Button and item.text==title:return item
	return null
func click(hole: String,pressed:=true,position:=Vector2.INF) -> void:
	var event:=InputEventMouseButton.new();event.button_index=MOUSE_BUTTON_LEFT;event.pressed=pressed
	event.position=ui.canvas.at(hole) if position==Vector2.INF else position
	ui.canvas._gui_input(event)
func pair(kind: String,a: String,b: String) -> void:
	ui.canvas.selected_type=kind;ui.canvas.first="";click(a);click(b)
func remove(hole: String) -> void:
	ui.canvas.selected_type="remove";click(hole)
func port(id: String) -> Node:
	for node in nodes(game.dc_lab):
		if node.get_meta("role","")=="dc_port" and int(node.get_meta("dc_station",-1))==1 and node.get_meta("dc_port","")==id:return node
	return null
func lead(a: String,b: String) -> void:
	var left:=port(a);var right:=port(b)
	check(left!=null and right!=null,"Actual physical lead sockets "+a+" / "+b)
	if left==null or right==null:return
	game.dc_lab.interact(left,false);game.dc_lab.interact(right,false)
func stage(name: String) -> bool:
	var elapsed:=Time.get_ticks_msec()-began
	print("STAGE ",name," wall_ms=",elapsed)
	if elapsed>54000:check(false,"Required stage exceeds bounded practice work: "+name);return false
	return true
func run() -> void:
	if OS.get_environment("LABVOLT_CORE_PRACTICE_LEASE")!="practice-J3":quit(77);return
	began=Time.get_ticks_msec()
	game=load("res://scenes/Main.tscn").instantiate();root.add_child(game)
	for i in 4:await process_frame
	game.front.network_page(false)
	var start:=button(game.front.screen,"Start Laboratory")
	check(start!=null,"Solo start uses existing front-menu button")
	if start==null:finish();return
	start.pressed.emit()
	for i in 3:await process_frame
	check(game.front.in_game and not game.session.online,"Actual Main solo, no multiplayer peer")
	game.player.position=game.dc_lab.campus_offset+Vector3(0,0,7.5)
	ui=game.electronics
	# Deterministic starter-kit fixture only; no shop/economy acceptance claim.
	ui.profile.data.analyzer=true
	ui.profile.data.kits[ui.profile.data.equipped].board=Board.empty()
	check(ui.profile.save()==OK,"Isolated starter kit saved")
	if not stage("studio-holes"):finish();return
	ui.open("board",1)
	for i in 2:await process_frame
	check(Board.node("A1")==Board.node("E1") and Board.node("A1")!=Board.node("F1"),"Terminal groups and center gap remain distinct")
	check(Board.node("P1")==Board.node("P15") and Board.node("P15")!=Board.node("P16"),"Power rail splits halfway on 30-row board")
	check(ui.canvas.hole_at(ui.canvas.at("A1"))=="A1","Studio actual hole roundtrip")
	pair("r1000","A1","F1")
	check(ui.canvas.board.parts.size()==1,"Studio places owned resistor through two real holes")
	var original: String=ui.canvas.board.parts[0].id
	ui.canvas.selected_type="select"
	var middle: Vector2=(ui.canvas.at("A1")+ui.canvas.at("F1"))*.5
	click("A1",true,middle);click("A1",false,middle+Vector2(23*ui.canvas.zoom,0))
	check(ui.canvas.board.parts[0].id==original and ui.canvas.board.parts[0].a=="A2","Studio drag preserves identity and moves resistor one row")
	pair("led","A3","F3");pair("button","A5","F5")
	check(ui.canvas.board.parts.size()==3,"Studio common LED/button placement")
	remove("A3");check(ui.canvas.board.parts.size()==2,"Studio removes component at actual hole")
	pair("led","A3","F3");pair("wire","F2","B3")
	check(ui.canvas.board.wires.has(["F2","B3"]),"Studio jumper joins resistor return to LED anode")
	ui.canvas.selected_type="interact"
	var center: Vector2=(ui.canvas.at("A5")+ui.canvas.at("F5"))*.5
	click("A5",true,center);check(ui.canvas.board.parts.any(func(p):return p.type=="button" and p.get("pressed",false)),"Button press uses Studio input handler")
	click("A5",false,center);check(ui.canvas.board.parts.all(func(p):return p.type!="button" or not p.get("pressed",false)),"Button release is persisted")
	var kit: Dictionary=ui.profile.data.kits[ui.profile.data.equipped]
	kit.board.ports=["A2","F3","A5","F5"]
	check(ui.profile.save()==OK,"Named bench-port mapping saved")
	ui.deploy()
	for i in 4:await process_frame
	var station=game.dc_lab.benches[1];var physical=game.dc_lab.physical_boards[1]
	check(station.board_owner==1 and physical.visible,"Studio deploy reaches owned physical board in Main")
	check(physical.drawing.hole_at(physical.drawing.at("A2"))=="A2","Mounted physical board retains hole mapping")
	await physics_frame
	var hit_center: Vector3=physical.to_global(Vector3(.7,.04,.25))
	var hit: Dictionary=game.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(hit_center+Vector3.UP*.2,hit_center-Vector3.UP*.2,4))
	check(not hit.is_empty() and hit.collider==physical.board_hit,"Real world ray hits mounted board collision surface")
	if not stage("CH1-DMM-scope"):finish();return
	for ends in [["CH1+","B1"],["CH1-","B2"],["VΩ","B1"],["COM","B2"],["S1","B1"],["GND","B2"]]:lead(ends[0],ends[1])
	game.dc_lab.request(1,{"op":"channel","index":0,"key":"voltage","value":5.0})
	game.dc_lab.request(1,{"op":"channel","index":0,"key":"enabled","value":true})
	if not station.master:game.dc_lab.request(1,{"op":"master"})
	game.dc_lab.request(1,{"op":"meter","mode":"DC V"})
	for i in 80:station.step(.0005)
	check(station.result.get("ok",false) and absf(station.difference("VΩ","COM")-5)<.002,"Real CH1 and DMM resolve 5V loaded circuit")
	check(station.result.get("i",{}).values().any(func(v):return float(v)>.002),"Actual resistor/LED load draws current")
	check(station.meter.ends_with(" V") and station.snapshot().scope_probe.reference_connected,"DMM display and scope common-reference lead are real")
	check(station.scope_capture.history.size()>4,"Scope acquisition consumes actual solver samples")
	evidence.stages.instruments={"meter":station.meter,"voltage":station.difference("VΩ","COM"),"solver_time":station.solver.time,"scope_history":station.scope_capture.history.size(),"scope_probe":station.snapshot().scope_probe}
	if not stage("named-package-craft-use-reload"):finish();return
	game.dc_lab.request(1,{"op":"clear"})
	# Build a resistor-only package through the same Studio hole handlers.
	ui.open("board",1);remove("A3");remove("A5");remove("F2")
	# Removal at F2 also removes the original resistor, so place it again.
	pair("r1000","A2","F2")
	kit=ui.profile.data.kits[ui.profile.data.equipped];kit.board.ports=["A2","F2","A5","F5"]
	check(kit.board.parts.size()==1 and kit.board.wires.is_empty(),"Clean resistor package source from Studio edits")
	ui.open("ics",1)
	var form: Node=null
	for n in ui.body.get_children():
		if n.get_script()==load("res://scripts/package_editor/package_form.gd"):form=n
	check(form!=null,"Production IC package form opened")
	if form==null:finish();return
	for n in nodes(form):
		if n is LineEdit and n.placeholder_text=="Circuit name":n.text="Core practice resistor"
	for i in 4:
		form.rows[i].name.text=["IN","OUT","CTRL","RETURN"][i]
		form.rows[i].hole.text=["A2","F2","A5","F5"][i]
	button(form,"Save circuit package").pressed.emit()
	var id:=""
	for key in ui.profile.data.get("blueprints",{}):
		if ui.profile.data.blueprints[key].name=="Core practice resistor":id=key
	check(id!="","Named package saved through actual form button")
	if id=="":finish();return
	var definition: Dictionary=ui.profile.data.blueprints[id]
	check(definition.pins[0].name=="IN" and definition.pins[0].node=="L2" and definition.pins[1].node=="R2","Named pins preserve internal node order")
	var before: int=ui.profile.data.inventory.r1000
	game.dc_lab.request(1,{"op":"recall"})
	check(station.board.is_empty(),"Recall source board before consuming crafting materials")
	button(ui.screen,"Craft from components").pressed.emit()
	for i in 3:await process_frame
	check(int(ui.profile.data.inventory.get(id,0))==1 and int(ui.profile.data.inventory.r1000)==before-1,"Real craft consumes one resistor and yields one package")
	check(ui.profile.operation_succeeded,"J craft explicit success outcome agrees with actual inventory delta")
	kit=ui.profile.data.kits[ui.profile.data.equipped];kit.items={};kit.items[id]=1
	kit.board=Board.empty();check(ui.profile.save()==OK,"Crafted-package kit template saved")
	ui.open("board",1);pair(id,"A10","A11")
	check(ui.canvas.board.parts.size()==1 and ui.canvas.board.parts[0].pins.size()==4,"Crafted package mounts with saved four physical pins")
	kit=ui.profile.data.kits[ui.profile.data.equipped];kit.board.ports=["A10","A11","F10","F11"];ui.profile.save();ui.deploy()
	for i in 3:await process_frame
	lead("CH1+","B1");lead("CH1-","B2")
	game.dc_lab.request(1,{"op":"channel","index":0,"key":"enabled","value":true})
	if not station.master:game.dc_lab.request(1,{"op":"master"})
	for i in 8:station.step(.0005)
	check(station.result.get("i",{}).values().any(func(v):return absf(float(v)-.005)<.00002),"Crafted named IC conducts through actual mounted external pin mapping")
	var reloaded=load("res://scripts/electronics_profile.gd").new();reloaded.open(game.characters.selected)
	var loaded_pins: Variant=reloaded.data.get("blueprints",{}).get(id,{}).get("pins",null)
	var inventory: Variant=reloaded.data.inventory.get(id,null)
	var raw_profile: Variant=JSON.parse_string(FileAccess.get_file_as_string(ui.profile.path))
	var reload_proof: Dictionary=ReloadGuard.inspect(definition.pins,loaded_pins,inventory)
	reload_proof.package_present=reloaded.data.blueprints.has(id)
	reload_proof.live_profile_path=ui.profile.path;reload_proof.reloaded_path=reloaded.path
	reload_proof.identity=game.characters.selected;reload_proof.paths_equal=ui.profile.path==reloaded.path
	reload_proof.live_authority_bound=ui.profile.authority_submit.is_valid()
	reload_proof.reloaded_authority_bound=reloaded.authority_submit.is_valid()
	reload_proof.exact_saved_sha256=FileAccess.get_sha256(ui.profile.path)
	reload_proof.saved_profile_schema_valid=load("res://scripts/electronics_profile.gd").valid(raw_profile)
	reload_proof.reloaded_profile_schema_valid=load("res://scripts/electronics_profile.gd").valid(reloaded.data)
	reload_proof.original_compound_result=reload_proof.package_present and reload_proof.raw_array_equal and int(reloaded.data.inventory.get(id,0))==1
	evidence.stages.reload=reload_proof
	print("RELOAD_TYPED_PREDICATES_JSON="+JSON.stringify(reload_proof))
	check(reload_proof.package_present and reload_proof.paths_equal and reload_proof.saved_profile_schema_valid and reload_proof.reloaded_profile_schema_valid and reload_proof.strict_semantic_match and (reload_proof.raw_array_equal or reload_proof.get("numeric_grid_type_transition_only",false)),"J3 strict schema and complete semantic pin/inventory roundtrip")
	evidence.stages.package={"id":id,"pins":definition.pins,"inventory":reloaded.data.inventory.get(id,0),"meter_current_candidates":station.result.get("i",{})}
	if not stage("actual-HC04-placement-and-meter"):finish();return
	game.dc_lab.request(1,{"op":"clear"});game.dc_lab.request(1,{"op":"recall"})
	# One declared fixture grant of an existing supported IC; no new platform.
	ui.profile.data.inventory.hc04=1
	kit=ui.profile.data.kits[ui.profile.data.equipped];kit.items={"hc04":1};kit.board=Board.empty();ui.profile.save()
	ui.open("board",1);pair("hc04","A8","F8")
	check(ui.canvas.board.parts.size()==1 and ui.canvas.board.parts[0].pins.size()==14,"Actual Studio mounts supported HC04 across center gap")
	kit=ui.profile.data.kits[ui.profile.data.equipped];kit.board.ports=["F14","A14","A8","A9"];ui.profile.save();ui.deploy()
	for i in 3:await process_frame
	for ends in [["CH1+","B1"],["CH1-","B2"],["B3","B2"],["VΩ","B4"],["COM","B2"]]:lead(ends[0],ends[1])
	game.dc_lab.request(1,{"op":"channel","index":0,"key":"enabled","value":true})
	if not station.master:game.dc_lab.request(1,{"op":"master"})
	for i in 4:station.step(.0005)
	var high: float=station.difference("VΩ","COM")
	check(high>4.9,"Real CH1-powered HC04 low input measured high on DMM")
	game.dc_lab.interact(port("B3"),true);lead("B3","B1")
	for i in 4:station.step(.0005)
	var low: float=station.difference("VΩ","COM")
	check(absf(low)<.05,"Real HC04 high input measured low after physical lead change")
	evidence.stages.logic={"low_input_output_V":high,"high_input_output_V":low,"meter":station.meter}
	if stage("supported-behavioral-ICs"):
		Supported.run(check)
	finish()
func finish() -> void:
	evidence.contract_fixture_loaded=SavedByteContract!=null
	evidence.checks=checks;evidence.failures=failures;evidence.wall_ms=Time.get_ticks_msec()-began
	evidence.remaining=["Manual OS mouse/focus/occlusion, visual legibility and full first-person navigation","555/74HC74 actual breadboard RC/timing/mounting matrix; this run includes bounded model-unit checks only","Large/nested package and all64physicalpins covered only by existing separate proofs","Fresh character restart through menu beyond profile reopen"]
	var file:=FileAccess.open(OS.get_environment("LABVOLT_PRACTICE_WORK").path_join("practice-result.json"),FileAccess.WRITE);file.store_string(JSON.stringify(evidence));file.close()
	print("CORE PRACTICE checks=",checks," failures=",failures," wall_ms=",evidence.wall_ms)
	quit(1 if failures else 0)
