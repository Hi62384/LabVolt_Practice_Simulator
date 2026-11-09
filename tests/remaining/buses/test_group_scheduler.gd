extends SceneTree
const Scheduler=preload("res://scripts/electronics_buses/group_scheduler.gd")
const Adapter=preload("res://scripts/firmware_backends/board_adapter.gd")
var scheduler := Scheduler.new()
var solver=preload("res://scripts/electronics_solver.gd").new()
var states := {"a":{"outputs":{},"pulls":{},"powered":true},"b":{"outputs":{},"pulls":{},"powered":true}}
var volts := {}
var fails := 0
func _initialize() -> void:call_deferred("run")
func check(ok: bool,label: String) -> void:
 print("PASS " if ok else "FAIL ",label)
 if not ok:fails+=1
func nodes(id: String) -> Array:
 return Adapter.catalog().uno.pins.map(func(p):return "v" if p=="VCC" else "g" if p=="GND" else id+"/"+p)
func settle(current: Dictionary,dt: float) -> void:
 states=current
 var parts: Array=[{"id":"power","kind":"V","a":"v","b":"g","value":5.}]
 for id in ["a","b"]:
  parts.append_array(Adapter.expand(Adapter.catalog().uno,id,nodes(id),{},volts,{id:states[id]}))
  parts.append({"id":id+"pull","kind":"R","a":id+"/D0","b":"v","value":10000.})
 parts.append({"id":"a_tx","kind":"R","a":"a/D1","b":"b/D0","value":100.})
 parts.append({"id":"b_tx","kind":"R","a":"b/D1","b":"a/D0","value":100.})
 var result: Dictionary=solver.solve(parts,[],dt)
 if not result.ok:check(false,"same production solver "+str(result));return
 volts=result.v
func run() -> void:
 settle(states,0.)
 scheduler.configure(settle,func():return {"voltages":volts})
 for id in ["a","b"]:
  var name := "uart-sender" if id=="a" else "uart-receiver"
  var image := FileAccess.get_file_as_string(OS.get_environment("LABVOLT_BUS_FIXTURES").path_join(name+".hex"))
  check(scheduler.add(id,nodes(id),{"board":"uno","image":image},"C:/Program Files/nodejs/node.exe","",9),"group scheduler adds "+id)
 var ready := false
 for i in 5000:
  if scheduler.ready():ready=true;break
  if scheduler.fault!="":break
  await create_timer(.001).timeout
 check(ready,"group scheduler asynchronously loads all genuine CPUs")
 var received := {"a":[],"b":[]}
 if ready:
  for frame in 12:
   check(scheduler.begin(.0005,volts),"begin exact .5ms frame "+str(frame))
   var packet := {}
   for i in 10000:
    packet=scheduler.poll()
    if packet.get("ready",false):break
    await create_timer(.001).timeout
   check(packet.get("ok",false) and packet.get("consumed",false),"core adapter consumed all edge barriers within frame "+str(frame))
   if not packet.get("ok",false):print(packet);break
   for id in received:
    for byte in packet.states[id].get("serial",[]):received[id].append(int(byte.value))
  check(received.a==[0x3c,0xc3] and received.b==[0xc3],"production group scheduler preserves actual bidirectional UART bytes")
  check(absf(solver.time-.006)<1e-12,"production group scheduler advances existing solver by exactly6ms")
 check(scheduler.begin(.0005,volts),"begin simulated backend-fault frame")
 var fault_packet := scheduler.fail("Simulated backend stop")
 check(fault_packet.consumed and absf(solver.time-.0065)<1e-12,"backend-fault fallback releases outputs and consumes remaining frame exactly once")
 scheduler.close();check(scheduler.bridge.process.is_empty(),"only owned group sidecar closed")
 print("GROUP SCHEDULER FAILURES: ",fails);quit(fails)
