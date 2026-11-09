extends SceneTree

const Profile = preload("res://scripts/electronics_profile.gd")
const Board = preload("res://scripts/breadboard_model.gd")
const Converter = preload("res://scripts/electronics/ic_pcb_editor/converter.gd")
const Upgrade = preload("res://scripts/electronics/ic_pcb_editor/upgrade.gd")
const Placement = preload("res://scripts/electronics/circuit_workspace/placement.gd")
const Custom = preload("res://scripts/custom_circuit.gd")
const Ledger = preload("res://scripts/inventory_authority/ledger.gd")

func _initialize() -> void:
	create_timer(20).timeout.connect(func(): quit(1))
	call_deferred("_run")

func _part(id: String, type: String, a: String, b: String) -> Dictionary:
	return {"id":id,"type":type,"a":a,"b":b}

func _run() -> void:
	var profile := Profile.new()
	var identity := Crypto.new().generate_random_bytes(12).hex_encode()
	profile.open(identity)
	profile.data.inventory.r1000 = 10
	profile.data.inventory.led = 10
	var source := Board.empty()
	source.parts.append(_part("resistor","r1000","A1","A2"))
	var model := Converter.new()
	assert(model.select_source("fixture",{"board":source,"name":"Six pin controller"},{}) == "")
	var holes := ["A1","A2","B2","A3","A4","A5"]
	for index in holes.size():
		assert(model.choose_hole(holes[index]) == "")
		model.connections[index].name = ["VCC","GND","INPUT","OUTPUT","RESET","CLOCK"][index]
	model.prepare_package()
	assert(model.width == 1 and model.length == 3 and model.pins.size() == 6)
	assert(model.pins[1].node == model.pins[2].node)
	model.resize_package(10,3)
	assert(model.pins.size() == 6 and model.pins[3].position.x == 10)
	model.remap(3,"A1")
	assert(model.pins[0].source_hole == "A3" and model.pins[3].source_hole == "A1")
	model.remap(0,"A1")
	model.resize_package(2,3)
	var original := model.prepare_blueprint(profile)
	assert(not original.has("error"),str(original))
	var old: String = original.id
	profile.data.blueprints = original.definitions
	profile.data.erase("dorm")
	assert(Profile.valid(profile.data))
	assert(Custom.price(old,original.definitions) == 1)
	var ledger := Ledger.new()
	var path := "user://ic_upgrade_"+identity
	assert(ledger.open(path) == OK)
	assert(ledger.bind(1,"1".repeat(48),"5".repeat(64),profile.data).ok)
	assert(ledger.bind(2,"2".repeat(48),"6".repeat(64),profile.data).ok)
	var bought := ledger.transact(1,"buy","buy",[old,10])
	assert(bought.ok and bought.profile.inventory[old] == 10)
	var other := ledger.transact(2,"other_buy","buy",[old,1])
	assert(other.ok)
	profile.data = bought.profile
	var editing := Converter.new()
	assert(editing.restore(old,profile.data.blueprints[old],profile.data.blueprints) == "")
	editing.board.parts.append(_part("led1","led","B7","B8"))
	editing.board.parts.append(_part("led2","led","B9","B10"))
	editing.resize_package(10,3)
	var invalid := editing.prepare_blueprint(profile)
	assert(not invalid.has("error"))
	assert(not ledger.transact(1,"width_change","ic_upgrade",[old,invalid.id,invalid.definitions[invalid.id],"apply"]).ok)
	editing.resize_package(2,3)
	var revision := editing.prepare_blueprint(profile)
	assert(not revision.has("error"),str(revision))
	var id: String = revision.id
	var bp: Dictionary = revision.definitions[id]
	var check := Upgrade.quote(profile.data,old,id,bp,{})
	assert(check.error == "",check.error)
	assert(check.needed == {"led":20} and check.missing == {"led":10} and check.cost == 30)
	var original_profile: Dictionary = ledger.account(1).profile.duplicate(true)
	assert(not ledger.transact(1,"too_early","ic_upgrade",[old,id,bp,"apply"]).ok)
	assert(Profile.same(original_profile,ledger.account(1).profile))
	var acquisition := ledger.transact(1,"shortage","ic_upgrade",[old,id,bp,"purchase"])
	assert(acquisition.ok and acquisition.profile.inventory.led == 20)
	var mounted := Board.empty()
	mounted.definitions = acquisition.profile.blueprints
	var mounted_part := Placement.maker_candidate(mounted,Board.catalog(mounted),{old:1},false,old,"","E3",1)
	assert(mounted_part.error == "",mounted_part.error)
	mounted = mounted_part.board
	mounted.wires = [["P1","A3"],["N1","A2"]]
	mounted.parts.append(_part("source","battery","P1","N1"))
	var stocked: Dictionary = acquisition.profile.duplicate(true)
	stocked.kits.starter.items[old] = 1
	stocked.kits.starter.board = mounted
	assert(ledger.transact(1,"mount_template","metadata",[stocked]).ok)
	assert(ledger.deploy(1,0,mounted) == "")
	var upgraded := ledger.transact(1,"apply","ic_upgrade",[old,id,bp,"apply"],mounted)
	assert(upgraded.ok,str(upgraded.get("error","")))
	assert(upgraded.profile.inventory[id] == 10 and not upgraded.profile.inventory.has(old))
	assert(upgraded.upgraded_board.parts[0].type == id and upgraded.upgraded_board.wires == mounted.wires)
	assert(ledger.account(1).deployment.counts[id] == 1)
	var actual := Board.expand(upgraded.upgraded_board)
	var solution := preload("res://scripts/electronics_solver.gd").new().solve(actual.parts,actual.wires,.01)
	assert(solution.ok and absf(float(solution.i.get("board/placement_preview/resistor",0))) > .001)
	assert(ledger.recall(1))
	assert(upgraded.profile.inventory.led == 0 and upgraded.profile.inventory.r1000 == 10)
	assert(ledger.account(2).profile.inventory[old] == 1 and not ledger.account(2).profile.inventory.has(id))
	assert(ledger.transact(1,"apply","ic_upgrade",[old,id,bp,"apply"]).ok)
	assert(not ledger.transact(1,"apply_again","ic_upgrade",[old,id,bp,"apply"]).ok)
	assert(Custom.price(id,upgraded.profile.blueprints) == 7)
	var design := Board.empty()
	design.definitions = upgraded.profile.blueprints
	var placement := Placement.maker_candidate(design,Board.catalog(design),{id:1},false,id,"","B3",0)
	assert(placement.error == "",placement.error)
	assert(placement.part.pins == ["B3","C3","D3","D5","C5","B5"])
	var expanded := Board.expand(placement.board)
	assert(expanded.parts.size() == 3)
	assert(expanded.wires.has(["board/L3","board/placement_preview/L1"]))
	var by_owner := Upgrade.resolve_board(upgraded.profile,{"rows":30,"parts":[{"type":old}]})
	assert(by_owner.parts[0].type == id)
	profile.data = upgraded.profile
	var next := Converter.new()
	assert(next.restore(id,bp,profile.data.blueprints) == "")
	next.board.parts.remove_at(0)
	var removed := next.prepare_blueprint(profile)
	assert(not removed.has("error"),str(removed))
	var returned := ledger.transact(1,"remove","ic_upgrade",[id,removed.id,removed.definitions[removed.id],"apply"])
	assert(returned.ok and returned.profile.inventory.r1000 == 20 and returned.profile.inventory[removed.id] == 10)
	assert(ledger.transact(1,"remove","ic_upgrade",[id,removed.id,removed.definitions[removed.id],"apply"]).profile.inventory.r1000 == 20)
	var reloaded := Ledger.new()
	assert(reloaded.open(path) == OK)
	assert(reloaded.bind(3,"1".repeat(48),"5".repeat(64),returned.profile).ok)
	assert(reloaded.account(3).profile.inventory[removed.id] == 10)
	profile.data = returned.profile
	var replaced := Converter.new()
	assert(replaced.restore(removed.id,removed.definitions[removed.id],profile.data.blueprints) == "")
	replaced.board.parts[0].type = "r220"
	var swap := replaced.prepare_blueprint(profile)
	assert(not swap.has("error"),str(swap))
	var exact := Upgrade.quote(profile.data,removed.id,swap.id,swap.definitions[swap.id],{})
	assert(exact.needed == {"r220":10} and exact.returned == {"led":10})
	assert(exact.missing == {"r220":6})
	var preserved: Dictionary = profile.data.inventory.duplicate()
	reloaded.creative = true
	var creative := reloaded.transact(3,"creative","ic_upgrade",[removed.id,swap.id,swap.definitions[swap.id],"apply"])
	assert(creative.ok and Profile.same(creative.profile.inventory,preserved))
	print("IC_UPGRADE_FIXTURE_OK")
	quit()

