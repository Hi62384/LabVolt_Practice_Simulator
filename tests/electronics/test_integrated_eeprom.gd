extends SceneTree
var station
func tick(cs: float,clk: float,data: float):
 station.channels[0].voltage=cs;station.channels[1].voltage=clk;station.channels[2].voltage=data
 for i in 3:station.step(.0005);assert(station.result.ok)
func byte_out(value: int):
 for bit in range(7,-1,-1):
  var v=5. if value&(1<<bit) else 0.
  tick(0.,0.,v);tick(0.,5.,v);tick(0.,0.,v)
func _initialize():call_deferred("run")
func run():
 var game=load("res://scenes/Main.tscn").instantiate();root.add_child(game)
 for i in 4:await process_frame
 station=game.dc_lab.benches[0]
 var profile=game.electronics.profile;profile.data.inventory.eeprom25=1;profile.data.inventory.battery=1
 var design=load("res://scripts/breadboard_model.gd").empty()
 design.parts=[{"id":"cell","type":"battery","a":"A1","b":"F1"},{"id":"nv","type":"eeprom25","a":"A2","b":"F2","pins":["A2","F2","A3","F3","A4","F4","A5","F5"]}]
 design.wires=[["A3","A1"],["A5","A1"],["F5","A1"],["F3","F1"]];design.ports=["A4","F4","A2","F1"]
 profile.data.kits[profile.data.equipped].board=design.duplicate(true);profile.data.kits[profile.data.equipped].items.eeprom25=1;profile.data.kits[profile.data.equipped].items.battery=1
 var material=game.electronics_trade.authority.materialize(1,design)
 assert(not material.is_empty());assert(station.apply({"op":"board","design":material})=="");station.board_owner=1
 station.master=true
 for channel in station.channels:channel.enabled=true;channel.limit=.1
 station.wires=[["CH1+","B3"],["CH2+","B2"],["CH3+","B1"],["CH1-","B4"],["CH2-","B4"],["CH3-","B4"]]
 tick(5.,0.,0.);byte_out(6);tick(5.,0.,0.)
 byte_out(2);byte_out(0);byte_out(16);byte_out(165);tick(5.,0.,0.)
 for i in 20:station.step(.0005)
 assert(station.firmware_states["board/nv"].memory.get("16",-1)==165)
 assert(game.dc_lab.capture_nonvolatile(1,0)=="")
 var saved=profile.data.duplicate(true)
 assert(station.apply({"op":"recall"})=="")
 profile.data=JSON.parse_string(JSON.stringify(saved))
 var restored=game.electronics_trade.authority.materialize(1,design)
 assert(station.apply({"op":"board","design":restored})=="")
 assert(station.firmware_states["board/nv"].memory["16"]==165)
 var ledger=load("res://scripts/inventory_authority/ledger.gd").new()
 assert(ledger.open("user://actual_eeprom_trade")==OK)
 assert(ledger.bind(1,"a".repeat(48),"1".repeat(64),saved).ok)
 var receiver=load("res://scripts/electronics_profile.gd").new();receiver.open("user://recipient")
 assert(ledger.bind(2,"b".repeat(48),"2".repeat(64),receiver.data).ok)
 var identity: String=ledger.account(1).profile.component_instances.keys()[0]
 var selections={1:{identity:ledger.instance_hash(ledger.account(1).profile.component_instances[identity])},2:{}}
 assert(ledger.exchange("electrically-written-memory",[1,2],{1:{"eeprom25":1},2:{}},{},selections).ok)
 var receiver_design=design.duplicate(true)
 receiver_design.parts=receiver_design.parts.filter(func(part):return part.type=="eeprom25")
 var recipient_material: Dictionary=ledger.materialize(2,receiver_design)
 var recipient_station=load("res://scripts/dc_station.gd").new()
 assert(recipient_station.apply({"op":"board","design":recipient_material})=="")
 assert(recipient_station.firmware_states["board/nv"].memory["16"]==165)
 assert(not ledger.account(1).profile.component_instances.has(identity))
 assert(ledger.materialize(1,design).component_runtime.is_empty())
 var restarted=load("res://scripts/inventory_authority/ledger.gd").new()
 assert(restarted.open("user://actual_eeprom_trade")==OK)
 assert(restarted.bind(3,"b".repeat(48),"2".repeat(64),receiver.data).ok)
 assert(restarted.materialize(3,receiver_design).component_runtime["board/nv"].memory["16"]==165)
 print("PASS: solved SPI writes byte, owned capture and JSON restore retain it, reviewed trade transfers one physical unit, recipient deployment and host restart preserve byte, donor cannot clone it")
 quit()
