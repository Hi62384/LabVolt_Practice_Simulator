extends SceneTree
const Design=preload("res://scripts/pcb_design/design.gd")
const Custom=preload("res://scripts/custom_circuit.gd")
const Document=preload("res://scripts/pcb_design/document.gd")
var checks := 0
var failures := 0
func check(ok: bool,message: String) -> void:
	checks+=1
	if not ok:failures+=1;push_error(message)
static func fixture() -> Dictionary:
	return {"name":"Routed divider","package":"PCB","revision":1,"footprint":{"width":8,"height":6,"color":"24775b","thickness_mm":1.6},"parts":[{"id":"r1","type":"r1000","a":"L1","b":"L2","nodes":["L1","L2"]},{"id":"r2","type":"r1000","a":"L2","b":"L3","nodes":["L2","L3"]}],"wires":[],"pins":[{"id":"in","name":"IN","node":"L1"},{"id":"out","name":"OUT","node":"L3"}],"layout":{"rows":10,"parts":[{"id":"r1","type":"r1000","a":"A1","b":"A2"},{"id":"r2","type":"r1000","a":"B2","b":"B3"}],"wires":[]},"pcb_design":{"version":1,"clearance":.08,"pad_radius":.1,"outline":[[0,0],[7,0],[7,5],[0,5]],"pads":{"p:r1:0":{"position":[1,1],"net":"L1"},"p:r1:1":{"position":[3,1],"net":"L2"},"p:r2:0":{"position":[3,3],"net":"L2"},"p:r2:1":{"position":[5,3],"net":"L3"},"x:in":{"position":[1,3],"net":"L1"},"x:out":{"position":[5,1],"net":"L3"}},"routes":[{"id":"input","a":"x:in","b":"p:r1:0","points":[[1,3],[1,1]],"width":.06},{"id":"middle","a":"p:r1:1","b":"p:r2:0","points":[[3,1],[3,3]],"width":.06},{"id":"output","a":"x:out","b":"p:r2:1","points":[[5,1],[5,3]],"width":.06}]}}
func solved(bp: Dictionary) -> Dictionary:
	var flat: Dictionary=Custom.flatten("ic:test",{"ic:test":bp},"board/unit/",["plus","minus"])
	flat.parts.append({"id":"source","kind":"V","a":"plus","b":"minus","value":10.0})
	return preload("res://scripts/electronics_solver.gd").new().solve(flat.parts,flat.wires)
func _initialize() -> void:call_deferred("run")
func run() -> void:
	var bp:=fixture()
	check(Custom.validate("ic:test",{"ic:test":bp})=="","host validates routed blueprint")
	check(Design.unrouted(bp)==0,"complete routed intent")
	var result:=solved(bp)
	check(result.ok and absf(float(result.i["board/unit/r1"])-.005)<1e-7,"actual shared solver gives 10V/2k=5mA")
	check(absf(float(result.drop["board/unit/r1"])-10000.0/2000.01)<1e-7,"actual divider matches independent 0.01ohm source-resistance reference")
	var opened:=bp.duplicate(true);opened.pcb_design.routes.remove_at(1)
	check(Design.validate(opened)=="","unrouted board allowed with honest open circuit")
	check(Design.unrouted(opened)==1,"one missing copper connection")
	check(absf(float(solved(opened).i["board/unit/r1"]))<1e-7,"deleting trace opens real solver circuit")
	var legacy:=bp.duplicate(true);legacy.erase("pcb_design")
	check(absf(float(solved(legacy).i["board/unit/r1"])-.005)<1e-7,"legacy connectivity unchanged")
	var migrated:=Design.migrate(legacy)
	check(Design.validate(migrated)=="","legacy copy migrates into bounded design")
	check(Design.unrouted(migrated)>0,"migration does not retain hidden breadboard strips")
	check(absf(float(solved(migrated).i["board/unit/r1"]))<1e-7,"migrated copper starts honestly open")
	for kind in ["cross","outside","outline","edge","spoof","nan","missing","short","duplicate","overlap"]:
		var bad:=bp.duplicate(true)
		match kind:
			"cross":bad.pcb_design.routes[0].points=[[1,3],[6,3],[6,1],[1,1]]
			"outside":bad.pcb_design.routes[0].points=[[1,3],[-1,3],[1,1]]
			"outline":bad.pcb_design.outline=[[0,0],[7,5],[0,5],[7,0]]
			"edge":bad.pcb_design.pads["x:in"].position=[0,0]
			"spoof":bad.pcb_design.pads["x:in"].net="L3"
			"nan":bad.pcb_design.routes[0].width=NAN
			"missing":bad.pcb_design.pads.erase("x:in")
			"short":bad.pcb_design.routes[0].b="x:out"
			"duplicate":bad.pcb_design.routes[1].id="input"
			"overlap":bad.pcb_design.pads["p:r2:0"].position=[1,3]
		check(Design.validate(bad)!="","reject "+kind)
	var concave:=bp.duplicate(true);concave.pcb_design.outline=[[0,0],[7,0],[7,5],[4,5],[4,4],[2,4],[2,5],[0,5]]
	check(Design.validate(concave)=="","concave outline accepted")
	var shortcut:=concave.duplicate(true);shortcut.pcb_design.routes[1].points=[[3,1],[1,4.5],[5,4.5],[3,3]]
	check(Design.validate(shortcut)!="","trace across concave cutout rejected")
	var doc:=Document.new();doc.open(bp)
	check(doc.remove_route(1),"editor removes copper")
	check(absf(float(solved(doc.blueprint).i["board/unit/r1"]))<1e-7,"editor removal changes actual netlist")
	check(doc.undo() and Design.unrouted(doc.blueprint)==0,"undo restores connectivity")
	check(doc.redo() and Design.unrouted(doc.blueprint)==1,"redo restores open circuit")
	doc.undo()
	var original:=doc.blueprint.duplicate(true)
	check(not doc.set_outline([[0,0],[1,1],[0,1],[1,0]]),"invalid outline cannot commit")
	check(doc.blueprint==original,"failed edit is atomic")
	check(doc.move_pad("p:r2:0",[3,3.3]),"component can move independent of breadboard strips")
	check(Design.v(doc.blueprint.pcb_design.pads["p:r2:1"].position).is_equal_approx(Vector2(5,3.3)),"component move preserves pin arrangement")
	check(absf(float(solved(doc.blueprint).i["board/unit/r1"])-.005)<1e-7,"moved component retains routed connectivity")
	doc.undo()
	check(doc.rotate_component("r2"),"component rotates independently of circuit connectivity")
	check(absf(float(solved(doc.blueprint).i["board/unit/r1"])-.005)<1e-7,"rotated part keeps real electrical behavior")
	check(doc.blueprint.layout.parts[1].surface_rotation==doc.blueprint.parts[1].surface_rotation,"saved 2D/physical orientation metadata matches")
	doc.undo()
	check(not doc.move_pad("p:r1:0",[NAN,0]),"invalid editor coordinates rejected atomically")
	var small:=legacy.duplicate(true);small.footprint.width=2;small.footprint.height=2;small.pins=[]
	for i in 64:small.pins.append({"id":"p"+str(i),"name":"P"+str(i),"node":"L1"})
	var expanded:=Design.migrate(small)
	check(Design.validate(expanded)=="" and expanded.footprint.width>2,"cramped legacy conversion enlarges only new copy")
	check(small.footprint.width==2 and not small.has("pcb_design"),"migration never changes original package")
	var flat_before:=Custom.flatten("ic:test",{"ic:test":bp},"board/unit/",["plus","minus"])
	var flat_after:=Custom.flatten("ic:test",{"ic:test":bp},"board/unit/",["plus","minus"])
	check(flat_before==flat_after and bp==fixture(),"cached flatten does not mutate blueprint")
	var canvas:=preload("res://scripts/breadboard_canvas.gd").new();root.add_child(canvas);canvas.size=Vector2(1000,440)
	var route_view=preload("res://scripts/pcb_design/route_canvas.gd").new();root.add_child(route_view);route_view.size=Vector2(1000,440)
	var route_doc:=Document.new();route_doc.open(opened);route_view.document=route_doc
	var click:=InputEventMouseButton.new();click.button_index=MOUSE_BUTTON_LEFT;click.pressed=true
	click.position=Design.map_point(opened,[3,1],route_view.rect());route_view._gui_input(click)
	check(route_view.start_pad=="p:r1:1","route editor selects actual source pad")
	click.position=Design.map_point(opened,[3,3],route_view.rect());route_view._gui_input(click)
	check(Design.unrouted(route_doc.blueprint)==0,"route editor input creates real conducting route")
	check(absf(float(solved(route_doc.blueprint).i["board/unit/r1"])-.005)<1e-7,"editor gesture reaches actual solver")
	var wheel:=InputEventMouseButton.new();wheel.button_index=MOUSE_BUTTON_WHEEL_UP;wheel.pressed=true;wheel.position=Vector2(400,200)
	var before_zoom: Array=route_view.grid_point(wheel.position);route_view._gui_input(wheel)
	check(route_view.zoom>1 and Design.v(route_view.grid_point(wheel.position)).is_equal_approx(Design.v(before_zoom)),"zoom retains grid point under cursor")
	check(Design.unrouted(route_doc.blueprint)==0,"zoom changes view only")
	route_view.queue_free()
	var rect:=Rect2(12,12,976,416)
	check(canvas.pcb_child_point(bp,bp.layout.parts[0],0,rect)==Design.map_point(bp,[1,1],rect),"2D/physical devices use routed pad positions")
	var mesh=preload("res://scripts/pcb_design/substrate.gd").mesh(concave,rect,0,.0016)
	check(mesh.get_surface_count()==1,"concave physical substrate triangulates")
	var vertices: PackedVector3Array=mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	check(vertices.size()<800,"outline geometry bounded")
	# Real profile/stock/save/trade APIs, isolated user storage.
	var identity:="pcb_test_"+str(Time.get_ticks_usec())
	var profile=preload("res://scripts/electronics_profile.gd").new();profile.open(identity)
	var inventory: Dictionary=profile.data.inventory.duplicate(true)
	var saved: String=doc.save_copy(profile)
	check(saved.begins_with("Blueprint saved: "),"routed revision saves through validated profile")
	var id:=saved.trim_prefix("Blueprint saved: ")
	check(profile.data.inventory==inventory,"blueprint editor cannot mint owned parts")
	var loaded=preload("res://scripts/electronics_profile.gd").new();loaded.open(identity)
	check(preload("res://scripts/electronics_profile.gd").same(loaded.data.blueprints[id].pcb_design,doc.blueprint.pcb_design),"outline/routes persist through JSON profile save")
	check(loaded.obtain_ic(id,true).contains("added"),"existing craft debits actual materials")
	check(int(loaded.data.inventory.r1000)==6 and int(loaded.data.inventory[id])==1,"craft consumes two resistors and grants one PCB")
	var recipient=preload("res://scripts/electronics_profile.gd").new();recipient.open(identity+"_receiver")
	var payload:={"id":"pcb-trade","give":{},"take":{id:1},"definitions":{id:loaded.data.blueprints[id]},"give_instances":{},"take_instances":{}}
	check(recipient.prepare_trade(payload)=="" and recipient.commit_trade("pcb-trade")=="","existing trade accepts validated routed definition")
	check(preload("res://scripts/electronics_profile.gd").same(recipient.data.blueprints[id].pcb_design,doc.blueprint.pcb_design),"trade preserves outline and copper")
	check(recipient.commit_trade("pcb-trade")=="" and recipient.data.inventory[id]==1,"trade replay cannot duplicate stock")
	check(Custom.materials(id,recipient.data.blueprints)=={"r1000":2},"routing does not change nested material accounting")
	var many:=legacy.duplicate(true);many.footprint.width=80;many.footprint.height=80;many.pins=[]
	for i in 64:many.pins.append({"id":"pin_"+str(i),"name":"P"+str(i),"node":"L1" if i%2==0 else "L3","connector":["male_header","female_header","through_hole","terminal_block","test_point"][i%5]})
	many=Design.migrate(many)
	check(Custom.validate("ic:many",{"ic:many":many})=="","64 external connectors remain supported")
	var standalone: Dictionary=preload("res://scripts/breadboard_model.gd").standalone("ic:many",{"ic:many":many})
	check(standalone.parts[0].pins.size()==64 and preload("res://scripts/breadboard_model.gd").validate(standalone,{},true)=="","64 pin standalone schema preserved")
	var too_many:=many.duplicate(true);too_many.pins.append({"id":"65","name":"P65","node":"L1"})
	check(Custom.validate("ic:65",{"ic:65":too_many})!="","65 pins still rejected")
	var outer:=legacy.duplicate(true)
	outer.parts=[{"id":"child","type":"ic:test","nodes":["L1","L3"]}]
	outer.layout.parts=[{"id":"child","type":"ic:test","a":"A1","b":"F1","pins":["A1","F1"]}]
	check(Custom.validate("ic:outer",{"ic:outer":outer,"ic:test":bp})=="","routed PCB nests in legacy package")
	var nested: Dictionary=Custom.flatten("ic:outer",{"ic:outer":outer,"ic:test":bp},"board/outer/",["plus","minus"])
	check(nested.parts[0].id=="board/outer/child/r1","nested runtime device path remains stable")
	check(nested.parts.size()==2,"nested routed expansion uses same components")
	var native_board: Dictionary=preload("res://scripts/breadboard_model.gd").empty();native_board.rows=40
	var native_pins: Array=[]
	for i in 32:native_pins.append("A"+str(i+1))
	var image:={"schema":1,"board":"uno","format":"intel_hex","image":FileAccess.get_file_as_string("res://assets/workers/firmware/uno-toggle.hex")}
	native_board.parts=[{"id":"uno","type":"native_uno","a":"A1","b":"A32","pins":native_pins,"native_sources":{"sketch.ino":"void loop() {}"},"native_firmware":image}]
	var memory_pins: Array=[]
	for i in 8:memory_pins.append("B"+str(i+1))
	native_board.parts.append({"id":"eeprom","type":"eeprom25","a":"B1","b":"B8","pins":memory_pins})
	native_board.programs={"board/uno":{"run":false,"native_sources":{"sketch.ino":"void loop() {}"},"native_firmware":image}}
	var native: Dictionary=preload("res://scripts/breadboard_model.gd").blueprint(native_board,"Programmed PCB")
	native.package="PCB";native.footprint={"width":40,"height":12,"color":"24775b","thickness_mm":1.6}
	native.layout={"rows":40,"parts":native_board.parts.duplicate(true),"wires":[]};native=Design.migrate(native)
	check(Custom.validate("ic:native",{"ic:native":native})=="","actual native source/image fields accepted in routed blueprint")
	var native_doc:=Document.new();native_doc.open(native)
	var native_saved: String=native_doc.save_copy(profile)
	check(native_saved.begins_with("Blueprint saved: "),"routed programmed board saves")
	var native_id:=native_saved.trim_prefix("Blueprint saved: ")
	loaded.open(identity)
	check(loaded.data.blueprints[native_id].programs.uno.native_firmware.image==image.image,"program image survives routed save/reload")
	check(loaded.data.blueprints[native_id].parts[0].native_sources["sketch.ino"]=="void loop() {}","per-device source survives routed save/reload")
	# Current instance persistence contract is copied by existing trade, not stored in immutable blueprint.
	var runtime:={"board/unit/eeprom":{"schema":1,"model":"eeprom25","memory":{"17":123},"status":0}}
	var instances:={"owned_pcb":{"type":native_id,"root":"board/unit","component_runtime":runtime}}
	var memory_payload:={"id":"memory-trade","give":{},"take":{native_id:1},"definitions":{native_id:loaded.data.blueprints[native_id]},"give_instances":{},"take_instances":instances}
	check(recipient.prepare_trade(memory_payload)=="" and recipient.commit_trade("memory-trade")=="","existing owned-instance trade preserves separate nested state")
	check(recipient.data.component_instances.owned_pcb.component_runtime["board/unit/eeprom"].memory["17"]==123,"nested memory byte survives trade without entering shared definition")
	check(not recipient.data.blueprints[native_id].has("component_runtime"),"immutable blueprint never receives instance memory")
	check(recipient.data.blueprints[native_id].programs.uno.native_firmware.image==image.image,"trade preserves associated native image with outline")
	check(loaded.obtain_ic(native_id,false).contains("added"),"programmed PCB purchased with existing dollars")
	loaded.data.component_instances=instances.duplicate(true)
	check(loaded.save()==OK,"owned PCB memory record saves separately")
	var ledger=preload("res://scripts/inventory_authority/ledger.gd").new()
	check(ledger.open(loaded.path+"_pcb_ledger")==OK,"existing authority ledger opens")
	var ledger_recipient=preload("res://scripts/electronics_profile.gd").new();ledger_recipient.open(identity+"_ledger_receiver")
	check(ledger.bind(1,"a".repeat(48),"1".repeat(64),loaded.data).ok and ledger.bind(2,"b".repeat(48),"2".repeat(64),ledger_recipient.data).ok,"host binds validated routed profiles")
	var exchange: Dictionary=ledger.exchange("owned-routed-trade",[1,2],{1:{native_id:1},2:{}},loaded.data.blueprints)
	check(exchange.ok,"real host ledger exchanges owned routed board")
	check(ledger.account(1).profile.inventory[native_id]==0 and ledger.account(2).profile.inventory[native_id]==1,"host ledger conserves owned PCB stock")
	check(ledger.account(2).profile.component_instances.owned_pcb.component_runtime["board/unit/eeprom"].memory["17"]==123,"host ledger carries nested EEPROM memory")
	check(ledger.account(2).profile.blueprints[native_id].programs.uno.native_firmware.image==image.image,"host ledger carries firmware and routed definition")
	canvas.board=preload("res://scripts/breadboard_model.gd").standalone(native_id,{native_id:native})
	var surface_devices: Array=canvas.surface_devices()
	var uno_device: Dictionary=surface_devices.filter(func(device):return device.type=="native_uno")[0]
	check(uno_device.id=="board/pcb/uno" and uno_device.pins.size()==32,"native physical device retains path and every electrical pin")
	var native_bounds:=Rect2(uno_device.pins[0],Vector2.ZERO)
	for pin in uno_device.pins:native_bounds=native_bounds.expand(pin)
	check(uno_device.center.is_equal_approx(native_bounds.get_center()),"native body centre follows complete routed pin bounds")
	var native_control: Dictionary=canvas.exposed_controls().filter(func(control):return control.type=="native_uno")[0]
	check(native_control.center.is_equal_approx(uno_device.center),"native programming picker follows rendered body centre")
	# Exact standalone polygon picker, no rectangular collision over a concave cutout.
	canvas.board=preload("res://scripts/breadboard_model.gd").standalone("ic:shape",{"ic:shape":concave})
	var physical=preload("res://scripts/physical_breadboard.gd").new();physical.set_process(false);root.add_child(physical)
	physical.drawing=canvas
	physical.board_hit=StaticBody3D.new();physical.board_hit.collision_layer=4;physical.add_child(physical.board_hit)
	var hit:=CollisionShape3D.new();hit.shape=BoxShape3D.new();physical.board_hit.add_child(hit)
	physical.sync_outline_hit()
	check(hit.shape is ConcavePolygonShape3D,"standalone picker follows actual outline triangles")
	await physics_frame;await physics_frame
	var substrate=preload("res://scripts/pcb_design/substrate.gd")
	var physical_rect: Rect2=canvas.pcb_rect(canvas.board.parts[0],concave)
	var inside_pixel: Vector2=Design.map_point(concave,[1,2],physical_rect)
	var cutout_pixel: Vector2=Design.map_point(concave,[3,4.5],physical_rect)
	var inside_world: Vector3=substrate.board_point(inside_pixel,.1)
	var cutout_world: Vector3=substrate.board_point(cutout_pixel,.1)
	var space: PhysicsDirectSpaceState3D=physical.get_world_3d().direct_space_state
	check(not space.intersect_ray(PhysicsRayQueryParameters3D.create(inside_world,inside_world-Vector3(0,.2,0),4)).is_empty(),"physical outline interior ray hits")
	check(space.intersect_ray(PhysicsRayQueryParameters3D.create(cutout_world,cutout_world-Vector3(0,.2,0),4)).is_empty(),"physical outline cutout ray misses")
	physical.queue_free()
	canvas.queue_free();await process_frame
	print("PCB_TESTS checks=",checks," failures=",failures)
	quit(0 if failures==0 else 1)
