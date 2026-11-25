extends SceneTree
## Electronics regressions: input boundaries, routed fabrication, instrument
## readings, live preview continuity and acknowledged deployed edits.
const Board=preload("res://scripts/breadboard_model.gd")
const Custom=preload("res://scripts/custom_circuit.gd")
const Copper=preload("res://scripts/pcb_design/design.gd")
const Studio=preload("res://scripts/campus/facilities/circuit_studio/assembly_model.gd")
const Solver=preload("res://scripts/electronics_solver.gd")
const Debug=preload("res://scripts/electronics/circuit_workspace/debug_instruments.gd")
const Maker=preload("res://scripts/electronics/circuit_workspace/maker_canvas.gd")
const Projects=preload("res://scripts/electronics/circuit_workspace/projects.gd")
const Electronics=preload("res://scripts/electronics_ui.gd")
const Network=preload("res://scripts/inventory_authority/network.gd")
const Profile=preload("res://scripts/electronics_profile.gd")
var failures:=0

class FakeAuthority extends RefCounted:
	var bound:=true
	var allow:=true
	var reply: Callable
	var dispatched: Array=[]
	func request_world(index: int,action: Dictionary) -> bool:
		if not allow:return false
		dispatched.append({"index":index,"action":action.duplicate(true)})
		if reply.is_valid():reply.call(index,action)
		return true

class FakeTrade extends RefCounted:
	var authority=FakeAuthority.new()

class FakeUi extends Node:
	var messages: Array=[]
	func log_message(message: String) -> void:
		messages.append(message)

class FakeGame extends Node:
	var session: Dictionary={"online":true}
	var electronics_trade=FakeTrade.new()
	var ui=FakeUi.new()

func _initialize() -> void:
	call_deferred("_run")

func check(ok: bool, description: String) -> void:
	if not ok:
		failures+=1
		printerr("FAIL ",description)

func _fixture_pcb() -> Dictionary:
	var source:=Board.empty()
	source.parts=[{"id":"r","type":"r1000","a":"A1","b":"F1"}]
	var bp: Dictionary=Board.blueprint(source,"Fixture PCB")
	bp.package="PCB"
	bp.footprint={"width":12,"height":8,"color":"24775b"}
	bp.layout={"rows":source.rows,"parts":source.parts.duplicate(true),"wires":[]}
	return bp

func _validation() -> void:
	var board:=Board.empty()
	check(Board.valid_hole(board,"A1") and Board.valid_hole(board,"W1"),"Canonical board holes remain usable")
	for invalid in ["A01","A+1","A1junk","A1.0","A-1"]:
		check(not Board.valid_hole(board,invalid),"Reject hole alias: "+invalid)
	board.parts=[{"id":"good","type":"r1000","a":"A1","b":"F1"}]
	check(Board.validate(board,{},true)=="","Unmodified resistor board still validates")
	var damaged:=board.duplicate(true)
	damaged.parts[0].erase("a")
	check(not Board.validate(damaged,{},true).is_empty(),"Reject missing component endpoint")
	damaged=board.duplicate(true)
	damaged.parts[0].erase("b")
	check(not Board.validate(damaged,{},true).is_empty(),"Reject missing second endpoint")
	damaged=board.duplicate(true)
	damaged.parts[0].pins=["A1","F1"]
	damaged.parts[0].a="A01"
	check(not Board.validate(damaged,{},true).is_empty(),"Reject endpoint alias even when pins are canonical")
	var bp: Dictionary=_fixture_pcb()
	var defs: Dictionary={"ic:fixture":bp}
	check(Custom.validate("ic:fixture",defs)=="","Ordinary PCB fixture remains valid")
	bp.footprint={}
	check(not Custom.validate("ic:fixture",defs).is_empty(),"Empty PCB footprint rejected before routing")
	bp=_fixture_pcb()
	defs["ic:fixture"]=bp
	bp.layout.parts[0].pins=["A1"]
	check(Custom.validate("ic:fixture",defs).contains("pin count"),"Physical pins cannot silently omit a circuit terminal")
	bp.layout.parts[0].pins=["A1","F2"]
	check(Custom.validate("ic:fixture",defs).contains("do not match"),"Physical pin locations must map to saved electrical nets")
	var safe: Dictionary={"name":"Valid","modified":100,"board":Board.empty()}
	check(Projects.valid_record("valid",safe),"Project browser accepts valid records")
	check(not Projects.valid_record("broken",{"name":"Broken","modified":1,"board":{"rows":30}}),"Project browser skips a malformed saved circuit")
	check(not Projects.valid_record("badtime",{"name":"Broken","modified":"yesterday","board":Board.empty()}),"Project browser skips invalid project timestamps")
	var projects:=Projects.new()
	projects.entries={"saved":safe}
	projects.current_id="saved"
	var restored: Dictionary=projects.discard_board()
	check(restored==safe.board,"Discard uses the saved project board, not the autosaved draft")
	restored.wires.append(["A1","A2"])
	check(safe.board.wires.is_empty(),"Restored discard board is a private copy")
	projects.current_id=""
	check(projects.discard_board()==Board.empty(),"Discarding an unnamed circuit restores a blank board")

func _routing() -> void:
	var bp: Dictionary=Copper.migrate(_fixture_pcb())
	var defs: Dictionary={"ic:fixture":bp}
	var error: String=Custom.validate("ic:fixture",defs)
	check(error=="","Generated routing PCB validates: "+error)
	if error!="":return
	check(Copper.unrouted(bp)>0,"Unfinished PCB actually contains unrouted intended nets")
	check(Custom.manufacturing_error("ic:fixture",defs).contains("unrouted"),"Unrouted PCB cannot be manufactured")
	var design: Dictionary=Studio.empty("PCB build")
	design.parts.append({"type":"pcb","x":1,"y":0,"z":0,"control":"","ref":"ic:fixture"})
	var inventions: Dictionary={"inv:test":design}
	check(Studio.validate("inv:test",inventions,defs)=="","Incomplete PCB may remain an editable invention draft")
	check(Studio.structure_error("inv:test",inventions,defs).contains("unrouted"),"Invention fabrication refuses an unrouted PCB")
	var profile:=Profile.new()
	profile.open("audit_unrouted_"+Crypto.new().generate_random_bytes(6).hex_encode())
	profile.data.blueprints=defs
	check(profile.buy("ic:fixture",1).contains("unrouted"),"Purchasing an unfinished routed PCB is blocked")
	check(profile.obtain_ic("ic:fixture",false).contains("unrouted"),"Crafting an unfinished routed PCB is blocked")

func _meters() -> void:
	var board:=Board.empty()
	var meter: Dictionary={"id":"ohms","type":Debug.METER,"a":"A1","b":"F1","debug":{"mode":"Ohms"}}
	board.parts=[meter]
	var parts: Array=Board.expand(board).parts
	var passive: Dictionary=Solver.new().solve(parts,Board.wires_only(board))
	check(passive.get("ok",false) and not Debug.ohms_on_live_circuit(board,meter,passive),"Passive ohmmeter remains available")
	board.parts.append({"id":"supply","type":Debug.SOURCE,"a":"B1","b":"G1","debug":{"voltage":5.0}})
	parts=Board.expand(board).parts
	var powered: Dictionary=Solver.new().solve(parts,Board.wires_only(board))
	check(powered.get("ok",false) and Debug.ohms_on_live_circuit(board,meter,powered),"Powered ohmmeter is flagged LIVE")
	board.parts[1].a="B2";board.parts[1].b="G2"
	parts=Board.expand(board).parts
	var separate: Dictionary=Solver.new().solve(parts,Board.wires_only(board))
	check(separate.get("ok",false) and not Debug.ohms_on_live_circuit(board,meter,separate),"Isolated source does not block a passive Ohms measurement")

func _profile_reload_and_backup() -> void:
	var identity: String="audit_reload_"+Crypto.new().generate_random_bytes(8).hex_encode()
	var profile:=Profile.new()
	profile.open(identity)
	var board:=Board.empty()
	board.parts=[{"id":"resistor","type":"r1000","a":"A1","b":"F1"}]
	profile.data.kits.starter.board=board
	var pins: Array=[
		{"id":"pin_1","name":"IN","hole":"A1","position":{"x":0,"y":0},"role":"unspecified","connector":"male_header"},
		{"id":"pin_2","name":"OUT","hole":"F1","position":{"x":1,"y":0},"role":"unspecified","connector":"male_header"}
	]
	var saved: String=profile.save_blueprint("Restart resistor",pins,"","IC",2,6)
	check(saved.begins_with("Blueprint saved"),"Named physical package saves: "+saved)
	if not saved.begins_with("Blueprint saved"):return
	var id: String=str(profile.data.blueprints.keys()[0])
	var expected: Array=profile.data.blueprints[id].pins.duplicate(true)
	var obtained: String=profile.obtain_ic(id,true)
	check(obtained=="Custom IC added to inventory","Crafted package saves: "+obtained)
	if obtained!="Custom IC added to inventory":return
	check(profile.save()==OK,"Second save establishes a complete known-good backup")
	var original_path: String=profile.path
	var backup: String=FileAccess.get_file_as_string(original_path+".bak")
	check(Profile.valid(JSON.parse_string(backup)),"Backup contains a complete accepted profile")
	var reloaded:=Profile.new()
	reloaded.open(identity)
	check(Profile.same(expected,reloaded.data.get("blueprints",{}).get(id,{}).get("pins",[]))
		and int(reloaded.data.inventory.get(id,0))==1,"Restart preserves pin IDs, names, coordinates, ordering and crafted stock")
	# An interrupted temporary write must not supersede the last commit.
	var file:=FileAccess.open(original_path+".tmp",FileAccess.WRITE)
	check(file!=null,"Create interrupted-save fixture")
	if file==null:return
	file.store_string("incomplete");file.close()
	# Recover after a corrupt primary; using schema-invalid JSON avoids
	# conflating parse diagnostics with a real backup recovery failure.
	file=FileAccess.open(original_path,FileAccess.WRITE)
	check(file!=null,"Create damaged-primary fixture")
	if file==null:return
	file.store_string('{"schema":0}');file.close()
	var recovered:=Profile.new()
	recovered.open(identity)
	check(Profile.same(expected,recovered.data.get("blueprints",{}).get(id,{}).get("pins",[]))
		and int(recovered.data.inventory.get(id,0))==1,"Corrupt primary recovers the complete crafted package from backup")
	check(recovered.save()==OK,"Recovered profile can be saved again")
	check(FileAccess.get_file_as_string(original_path+".bak")==backup,
		"Recovery save never overwrites the only known-good backup with corrupt primary bytes")
	var restored:=Profile.new()
	restored.open(identity)
	check(Profile.same(expected,restored.data.get("blueprints",{}).get(id,{}).get("pins",[]))
		and int(restored.data.inventory.get(id,0))==1,"Repaired primary remains valid on the next restart")

func _queue_and_receipts() -> void:
	var queue: Array=[]
	var origin: Dictionary={"op":"board","design":{"wires":[]}}
	for index in 16:
		check(Network.enqueue_world_request(queue,index,origin),"Queue accepts capacity item "+str(index))
	check(not Network.enqueue_world_request(queue,16,origin) and queue.size()==16,"Queue explicitly rejects overflow")
	origin.design.wires.append(["A1","A2"])
	check(queue[0].action.design.wires.is_empty(),"Queued actions retain independent data snapshots")
	var game:=FakeGame.new()
	game.add_child(game.ui)
	root.add_child(game)
	var ui:=Electronics.new()
	game.add_child(ui)
	ui.game=game
	ui.profile.open("audit_board_ack_"+Crypto.new().generate_random_bytes(6).hex_encode())
	var before: Dictionary=ui.profile.data.kits.starter.board.duplicate(true)
	var candidate: Dictionary=before.duplicate(true)
	candidate.authority_kit_id="starter"
	candidate.wires=[["A1","A2"]]
	check(ui.request_placed_board_edit(0,"starter",candidate),"Physical edit enters host queue")
	check(ui.pending_board_edits.size()==1 and game.electronics_trade.authority.dispatched.size()==1,"Edit remains pending until authoritative receipt")
	if not ui.pending_board_edits.is_empty():
		var id: String=str(ui.pending_board_edits.keys()[0])
		check(ui.profile.data.kits.starter.board==before,"Unacknowledged edit has not mutated local inventory")
		ui.complete_placed_board_edit(0,id,false,before)
		check(ui.profile.data.kits.starter.board==before and ui.pending_board_edits.is_empty(),"Rejected edit restores local kit")
	check(ui.request_placed_board_edit(0,"starter",candidate),"Retry is permitted after rejection")
	if not ui.pending_board_edits.is_empty():
		var id: String=str(ui.pending_board_edits.keys()[0])
		ui.complete_placed_board_edit(0,id,true,candidate)
		check(ui.profile.data.kits.starter.board.wires.size()==1 and ui.pending_board_edits.is_empty(),"Accepted edit persists only after host receipt")
	game.electronics_trade.authority.allow=false
	check(not ui.request_placed_board_edit(0,"starter",candidate) and ui.pending_board_edits.is_empty(),"Rejected queue admission does not strand the editor")
	game.electronics_trade.authority.allow=true
	var next: Dictionary=candidate.duplicate(true)
	next.wires=[["A1","A3"]]
	game.electronics_trade.authority.reply=func(index: int,action: Dictionary):
		ui.complete_placed_board_edit(index,str(action.edit_request_id),true,next)
	check(ui.request_placed_board_edit(0,"starter",next) and ui.pending_board_edits.is_empty(),"Synchronous host acknowledgements cannot be lost")
	check(ui.profile.data.kits.starter.board.wires==next.wires,"Synchronous receipt commits the accepted circuit")
	game.electronics_trade.authority.reply=Callable()
	game.queue_free()

func _preview() -> void:
	var board:=Board.empty()
	board.parts=[
		{"id":"source","type":Debug.SOURCE,"a":"B1","b":"G1","debug":{"voltage":5.0}},
		{"id":"storage","type":"c10.0","a":"A1","b":"F1"}]
	check(Board.validate(board,{},true)=="","Designer debug-source RC fixture validates")
	var ui:=Electronics.new()
	root.add_child(ui)
	ui.set_process(false)
	var canvas:=Maker.new()
	canvas.board=board
	canvas.inventory_catalog=Board.catalog(board)
	root.add_child(canvas)
	await process_frame
	ui.canvas=canvas
	ui.active=true
	ui.designing=true
	ui._process(.025)
	var solver_before=ui.design_preview
	var time_before: float=solver_before.solver.time
	canvas.board.parts[0].debug.voltage=3.0
	ui._process(.025)
	check(is_same(ui.design_preview,solver_before),"Changing debug source does not replace solver instance")
	check(solver_before.solver.time>time_before,"Source change retains the running electrical clock")
	ui.active=false
	canvas.queue_free()
	ui.queue_free()
	await process_frame

func _run() -> void:
	_validation()
	_routing()
	_meters()
	_profile_reload_and_backup()
	_queue_and_receipts()
	await _preview()
	print("ELECTRONICS_AUDIT_FIXES ", "PASS" if failures==0 else "FAIL ",failures)
	quit(failures)
