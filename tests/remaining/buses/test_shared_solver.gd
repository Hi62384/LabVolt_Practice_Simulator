extends SceneTree
const Bridge=preload("res://scripts/firmware_backends/native_bridge.gd")
const Adapter=preload("res://scripts/firmware_backends/board_adapter.gd")
const Library=preload("res://scripts/component_models/library.gd")
const Catalog=preload("res://scripts/component_models/catalog_data.gd")
var fails := 0
var solver=preload("res://scripts/electronics_solver.gd").new()
var native := {"powered":true,"outputs":{},"pulls":{}}
var slave := {}
var volts := {}
var kind := "eeprom25"
var slave_nodes: Array=[]
var logical: Array=[]
var received: Array=[]
var board := "uno"
var supply := 5.0
var cpu_hz := 16000000.
var loopback := false
var last_state := {}
var scenario := ""
var group_states := {}
var group_kind := ""
func check(ok: bool,message: String) -> void:
 print("PASS " if ok else "FAIL ",message)
 if not ok:fails+=1
func _initialize() -> void:call_deferred("run")
func exchange(bridge: RefCounted,command: Dictionary) -> Dictionary:
 if not bridge.request(command):return {"ok":false,"error":bridge.last_error}
 for i in 10000:
  var reply: Dictionary=bridge.poll()
  if not reply.is_empty():return reply
  await create_timer(.001).timeout
 return {"ok":false,"error":"timeout"}
func primitives() -> Array:
 var parts: Array=[{"id":"supply","kind":"V","a":"VCC","b":"GND","value":supply},{"id":"rxpull","kind":"R","a":"D0" if board=="uno" else "GP1","b":"VCC","value":10000.}]
 if not group_states.is_empty():
  for id in group_states:
   var nodes := group_nodes(id)
   parts.append_array(Adapter.expand(Adapter.catalog().uno,id,nodes,{},volts,{id:group_states[id]}))
   parts.append({"id":id+"rxpull","kind":"R","a":id+"/D0","b":"VCC","value":10000.})
  if group_kind=="uart":
   parts.append({"id":"a_to_b","kind":"R","a":"a/D1","b":"b/D0","value":100.})
   parts.append({"id":"b_to_a","kind":"R","a":"b/D1","b":"a/D0","value":100.})
 else:parts.append_array(Adapter.expand(Adapter.catalog()[board],"cpu",logical,{},volts,{"cpu":native}))
 if loopback:parts.append({"id":"loopback","kind":"R","a":"D1" if board=="uno" else "GP0","b":"D0" if board=="uno" else "GP1","value":100.})
 if kind=="spi_display":
  parts.append_array(preload("res://scripts/stateful_devices.gd").expand(kind,"slave",slave_nodes,slave).filter(func(p):return p.kind!="stateful"));return parts
 parts.append_array(Library.expand(Catalog.ENTRIES[kind],"slave",slave_nodes,{},volts,{"slave":slave}).filter(func(p):return p.kind!="stateful"))
 if kind=="pcf8574":
  parts.append({"id":"sclpull","kind":"R","a":"A5" if board=="uno" else "GP1","b":"VCC","value":4700.})
  parts.append({"id":"sdapull","kind":"R","a":"A4" if board=="uno" else "GP0","b":"VCC","value":4700.})
 return parts
func settle(dt: float) -> void:
 var result: Dictionary=solver.solve(primitives(),[],dt)
 if not result.ok:check(false,"shared solver: "+str(result));return
 volts=result.v
 # Existing slave tick API currently requires a positive dt for edge observation.
 # Tiny settle epsilon does not advance the production solver's electrical clock.
 slave=Library.tick(Catalog.ENTRIES[kind],slave_nodes,volts,slave,maxf(dt,1e-12)) if kind!="spi_display" else preload("res://scripts/stateful_devices.gd").tick(kind,slave_nodes,volts,slave,maxf(dt,1e-12))
 result=solver.solve(primitives(),[],0.);volts=result.v
func apply(state: Dictionary,started: int) -> void:
 var previous := native.duplicate(true);previous.cycles=started
 var replay := preload("res://scripts/electronics_buses/edge_replay.gd").replay(previous,state,cpu_hz,func(dt,current):native=current;settle(dt))
 if not replay.ok:check(false,str(replay))
 for byte in state.get("serial",[]):received.append(int(byte.value))
func fixture(name: String,model: String,platform := "uno",variant := "") -> void:
 scenario=variant;board=platform;supply=5. if board=="uno" else 3.3;cpu_hz=16000000. if board=="uno" else 125000000.;loopback=name in ["uart","pico-uart"]
 kind=model;solver.reset();slave={};native={"powered":true,"outputs":{},"pulls":{}};volts={};received=[]
 logical=Adapter.catalog()[board].pins.duplicate()
 slave_nodes=["D10","D12","VCC","GND","D11","D13","VCC","VCC"] if kind=="eeprom25" else ["GND","GND","GND","P0","P1","P2","P3","GND","P4","P5","P6","P7","INT","A5","A4","VCC"]
 if board=="pico":
  logical[0]="VCC"
  slave_nodes=["VCC","GND","GP3","GP2","GP5"] if kind=="spi_display" else ["GND","GND","GND","P0","P1","P2","P3","GND","P4","P5","P6","P7","INT","GP1","GP0","VCC"]
 if scenario=="address_nack":slave_nodes[0]="VCC"
 if scenario=="unpowered":slave_nodes[15]="GND"
 settle(0.)
 var bridge := Bridge.new();check(bridge.start("C:/Program Files/nodejs/node.exe"),"launch owned backend for "+name)
 var path := OS.get_environment("LABVOLT_BUS_FIXTURES").path_join(name+".hex")
 var program: Dictionary={"op":"load","board":board,"image":FileAccess.get_file_as_string(path)}
 if board=="pico":program=JSON.parse_string(FileAccess.get_file_as_string(path.trim_suffix(".hex")+".json"));program.op="load"
 var reply: Dictionary=await exchange(bridge,program)
 if not reply.get("ok",false):check(false,str(reply));bridge.close();return
 var cycles := 0
 for step in 3000:
  var command := Adapter.tick_request(Adapter.catalog()[board],logical,volts,.0005)
  command.electrical_bus=true
  reply=await exchange(bridge,command)
  if not reply.get("ok",false):check(false,str(reply));break
  apply(reply.state,cycles);cycles=int(reply.state.cycles);last_state=reply.state
  if board=="pico" and int(reply.state.registers[6])==0x77:break
  if scenario!="" and received.size()>=1:break
  if received.size()>=(1 if name=="eeprom" else 2 if name=="uart" else 3):break
 bridge.close()
 if scenario!="":
  check(received==[0x20] and slave.get("latch",255)==255,"actual I2C "+scenario+" yields address NACK without changing slave state")
 elif name=="eeprom":
  check(slave.get("memory",{}).get("16",-1)==0x5a,"native AVR SPI writes actual 25LC256 memory through solved MOSI/SCK/CS nets")
  check(received==[0x5a],"native AVR SPI reads actual EEPROM SO voltage into SPDR then UART monitor")
 elif name=="uart":
  check(received==[0x55,0x55],"native AVR UART TX serializes onto actual RX net and decodes 8N1 loopback")
 elif board=="pico":
  if name=="pico-uart":check(received==[0x55,0x55] and int(last_state.registers[7])==0x55,"native Thumb UART decodes actual GP0 to GP1 wire loopback")
  elif name=="pico-display":check(slave.get("cells",[]).size()==32 and slave.cells[0]==72 and slave.cells[1]==105,"native Thumb SPI code writes Hi through solved GP mux/clock/data/CS to display")
  else:check(slave.get("latch",0)==0xa5,"native Thumb I2C code produces actual expander address/data ACK and write")
 else:
  check(received.size()==3 and received[0]==0x18 and received[1]==0x28,"native AVR I2C address/data ACK derived from actual PCF8574 SDA sink")
  check(slave.get("latch",0)==0xa5 and received.size()==3 and received[2]==0xa5,"native AVR I2C write/read drives and senses physical expander ports")
 print("BUS FIXTURE ",name," cycles=",cycles," bytes=",received," memory=",slave.get("memory",{})," phase=",slave.get("phase",""))
func group_nodes(id: String) -> Array:
 return Adapter.catalog().uno.pins.map(func(pin):return str(pin) if pin in ["VCC","GND"] or (group_kind=="i2c" and pin in ["A4","A5"]) else id+"/"+str(pin))
func group_inputs(bridge: RefCounted,power_a := 5.) -> void:
 for id in ["a","b"]:
  var input: Dictionary=Adapter.tick_request(Adapter.catalog().uno,group_nodes(id),volts,0.)
  for key in ["op","dt"]:input.erase(key)
  if id=="a":input.vcc=power_a
  var reply: Dictionary=await exchange(bridge,{"op":"group_input","id":id,"epoch":3,"input":input})
  if not reply.get("ok",false):check(false,"group input "+str(reply))
func group_fixture(protocol: String) -> void:
 group_kind=protocol;board="uno";supply=5.;cpu_hz=16000000.;kind="pcf8574";scenario="";loopback=false;solver.reset();volts={};slave={}
 slave_nodes=["GND","GND","GND","P0","P1","P2","P3","GND","P4","P5","P6","P7","INT","A5","A4","VCC"]
 group_states={"a":{"powered":true,"outputs":{},"pulls":{}},"b":{"powered":true,"outputs":{},"pulls":{}}};settle(0.)
 var bridge := Bridge.new();check(bridge.start("C:/Program Files/nodejs/node.exe"),"launch grouped host backend "+protocol)
 var reply: Dictionary=await exchange(bridge,{"op":"group_begin"})
 for id in ["a","b"]:
  var file := ("uart-sender" if id=="a" else "uart-receiver") if protocol=="uart" else ("i2c" if id=="a" else "i2c-reader")
  reply=await exchange(bridge,{"op":"load","board":"uno","device_id":id,"board_epoch":3,"image":FileAccess.get_file_as_string(OS.get_environment("LABVOLT_BUS_FIXTURES").path_join(file+".hex"))})
  if not reply.get("ok",false):check(false,str(reply))
 var total := 0.;var outputs := {"a":[],"b":[]};var barriers := 0;var zero := 0
 for i in 10000:
  await group_inputs(bridge)
  reply=await exchange(bridge,{"op":"group_tick","dt":minf(.0005,.006-total)})
  if not reply.get("ok",false):check(false,str(reply));break
  var state: Dictionary=reply.state;var elapsed := float(state.elapsed)
  if elapsed<0 or elapsed>.00050000001:check(false,"group elapsed bound");break
  settle(elapsed);group_states=state.devices;settle(0.);total+=elapsed
  if state.bus_barrier:barriers+=1
  if elapsed==0:zero+=1
  for id in outputs:
   for byte in state.devices[id].serial:outputs[id].append(int(byte.value))
  if total>=.006-1e-13:break
 check(absf(total-.006)<1e-12,"two-CPU "+protocol+" exact 6ms total electrical time with no double consumption")
 if protocol=="uart":check(outputs.a==[0x3c,0xc3] and outputs.b==[0xc3],"two genuine AVR CPUs exchange distinct UART request/reply through actual shared-solver wires")
 else:check(slave.get("latch",0)==0xa5 and outputs.b==[0xa5],"two genuine AVR CPUs share actual I2C slave: delayed second controller reads first controller's write")
 reply=await exchange(bridge,{"op":"group_input","id":"a","epoch":4,"input":{"vcc":5.,"pins":{}}})
 check(not reply.get("ok",true) and "epoch" in str(reply.get("error","")),"group rejects stale board epoch")
 await group_inputs(bridge,0.)
 reply=await exchange(bridge,{"op":"group_tick","dt":.0005})
 check(reply.get("ok",false) and reply.state.elapsed==0 and not reply.state.devices.a.powered and reply.state.devices.a.outputs.is_empty(),"group power loss releases drivers at a zero-time electrical barrier")
 await group_inputs(bridge,0.)
 reply=await exchange(bridge,{"op":"group_tick","dt":.0005})
 check(reply.get("ok",false) and reply.state.elapsed>0,"static powered-off CPU does not prevent remaining CPU/time progress")
 print("GROUP ",protocol," total=",total," barriers=",barriers," zero=",zero," bytes=",outputs)
 bridge.close();group_states={}
func run() -> void:
 await fixture("eeprom","eeprom25")
 await fixture("i2c","pcf8574")
 await fixture("uart","eeprom25")
 await fixture("pico-display","spi_display","pico")
 await fixture("pico-i2c","pcf8574","pico")
 await fixture("pico-uart","pcf8574","pico")
 await fixture("i2c","pcf8574","uno","address_nack")
 await fixture("i2c","pcf8574","uno","unpowered")
 await group_fixture("uart")
 await group_fixture("i2c")
 check(load("res://scripts/electronics_buses/cooperative_link.gd").can_instantiate(),"epoch-safe single-link core adapter parses")
 print("BUS SHARED SOLVER FAILURES: ",fails);quit(fails)
