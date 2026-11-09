extends SceneTree
const Adapter=preload("res://scripts/firmware_backends/board_adapter.gd")
class FakeScheduler:
 extends "res://scripts/electronics_buses/group_scheduler.gd"
 var replies: Array=[]
 func pump() -> Dictionary:
  if replies.is_empty():return {}
  for command in queue:
   if command.op=="group_tick":pending_sequence=int(command.tick_sequence);pending_budget=float(command.dt)
  queue.clear()
  return replies.pop_front()
var fails := 0
var checks := 0
func check(ok: bool,label: String) -> void:
 checks+=1;print("PASS " if ok else "FAIL ",label)
 if not ok:fails+=1
func state(epoch := 7) -> Dictionary:
 return {"group_epoch":epoch,"cycles":100,"powered":true,"outputs":{"D0":1},"pulls":{},"events":[],"serial":[]}
func good(elapsed := .0002,time := .0002,sequence := 1) -> Dictionary:
 return {"ok":true,"state":{"schema":1,"elapsed":elapsed,"time":time,"tick_sequence":sequence,"bus_barrier":true,"devices":{"cpu":state()}}}
func setup(record: Dictionary) -> FakeScheduler:
 var s := FakeScheduler.new();s.loaded=true
 s.devices={"cpu":{"model":Adapter.catalog().uno,"nodes":Adapter.catalog().uno.pins.duplicate(),"epoch":7,"running":true}}
 s.states={"cpu":state()};s.states.cpu.outputs={"D0":0}
 record.total=0.;record.calls=[]
 s.configure(func(states,dt):
  record.total+=dt;record.calls.append({"dt":dt,"states":states.duplicate(true)})
 ,func():return {"voltages":{}})
 check(s.begin(.0005,{}),"start isolated validation frame")
 return s
func invalid_case(label: String,reply: Dictionary) -> void:
 var record := {};var s := setup(record);s.replies=[reply]
 var result := s.poll()
 check(result.get("ready",false) and not result.get("ok",true) and result.get("consumed",false),label+" rejected with one consumed terminal receipt")
 check(absf(record.total-.0005)<1e-15 and s.remaining==0.,label+" settles only the outstanding frame budget")
 var leaked := false
 for call in record.calls:
  if call.states.cpu.get("outputs",{}).get("D0",0)==1 or call.states.cpu.get("powered",false):leaked=true
 check(not leaked,label+" never commits stale or malformed pin state")
 var before: int=record.calls.size()
 for i in 3:s.poll()
 var repeated := s.fail("duplicate failure")
 check(record.calls.size()==before and not repeated.consumed,label+" repeated poll/failure cannot consume time again")
 s.close()
func _initialize() -> void:call_deferred("run")
func run() -> void:
 for label in ["stale epoch","fractional epoch","unknown device","missing device","malformed state","missing payload","missing sequence","replayed sequence","negative elapsed","nonfinite elapsed","excess elapsed","clock mismatch","unexpected edge replay","malformed drive","malformed serial"]:
  var reply := good()
  match label:
   "stale epoch":reply.state.devices.cpu.group_epoch=8
   "fractional epoch":reply.state.devices.cpu.group_epoch=7.5
   "unknown device":reply.state.devices={"other":state()}
   "missing device":reply.state.devices={}
   "malformed state":reply.state.devices.cpu="bad"
   "missing payload":reply.erase("state")
   "missing sequence":reply.state.erase("tick_sequence")
   "replayed sequence":reply.state.tick_sequence=0
   "negative elapsed":reply.state.elapsed=-.0001
   "nonfinite elapsed":reply.state.elapsed=NAN
   "excess elapsed":reply.state.elapsed=.0006;reply.state.time=.0006
   "clock mismatch":reply.state.time=.0004
   "unexpected edge replay":reply.state.devices.cpu.events=[{"type":"gpio"}]
   "malformed drive":reply.state.devices.cpu.outputs={"D99":1}
   "malformed serial":reply.state.devices.cpu.serial=[{"port":0,"value":256}]
  invalid_case(label,reply)
 for failure in ["stale","duplicate","transport"]:
  var record := {};var s := setup(record)
  var bad := good(.0001,.0003,2)
  if failure=="stale":bad.state.devices.cpu.group_epoch=9
  elif failure=="duplicate":bad=good(.0002,.0002,1)
  else:bad={"ok":false,"error":"worker stopped after a committed partial interval"}
  s.replies=[good(),bad]
  check(not s.poll().get("ready",false) and absf(record.total-.0002)<1e-15,"valid prefix commits before "+failure+" failure")
  var result := s.poll();var positive: Array=[]
  for call in record.calls:
   if call.dt>0:positive.append(call.dt)
  check(not result.ok and result.consumed and positive.size()==2 and absf(positive[0]-.0002)<1e-15 and absf(positive[1]-.0003)<1e-15 and absf(record.total-.0005)<1e-15,"partial "+failure+" failure advances .2ms + .3ms exactly once")
  var count: int=record.calls.size();s.poll();s.fail("repeat")
  check(record.calls.size()==count,"partial "+failure+" repeated terminal access is inert")
  s.close()
 var record := {};var success := setup(record);success.replies=[good(),good(.0003,.0005,2)]
 success.poll();var result := success.poll();var count: int=record.calls.size()
 check(result.ok and result.consumed and absf(record.total-.0005)<1e-15,"valid partial sequence commits exactly one complete frame")
 success.poll();var after := success.fail("late failure after success")
 check(record.calls.size()==count and not after.consumed,"completed success cannot be settled again by later poll/fail")
 success.close()
 var deadline_record := {};var deadline := setup(deadline_record)
 deadline.queue[-1].dt=.0001;deadline.replies=[good(.0002,.0002,1)]
 result=deadline.poll()
 check(not result.ok and absf(deadline_record.total-.0005)<1e-15,"reply cannot exceed a shortened dispatched deadline even within frame remainder")
 deadline.close()
 var zero_record := {};var zero_deadline := setup(zero_record)
 zero_deadline.queue[-1].dt=0.;var zero_reply := good(0.,0.,1);zero_reply.state.bus_barrier=false;zero_deadline.replies=[zero_reply]
 result=zero_deadline.poll()
 check(not result.get("ready",false) and zero_record.total==0. and zero_deadline.remaining==.0005,"explicit zero-time commercial deadline remains valid without a native GPIO barrier")
 zero_deadline.close()
 var callback_record := {};var reentrant := setup(callback_record);var injected := {"done":false}
 reentrant.configure(func(current,dt):
  callback_record.total+=dt;callback_record.calls.append({"dt":dt,"states":current.duplicate(true)})
  if dt>0 and not injected.done:
   injected.done=true
   check(not reentrant.poll().get("ready",false),"callback cannot reenter reply commit")
   reentrant.fail("fault during positive settlement callback")
 ,func():return {"voltages":{}})
 reentrant.replies=[good()];result=reentrant.poll()
 check(not result.ok and result.consumed and absf(callback_record.total-.0005)<1e-15,"callback fault cannot replay the already debited .2ms interval")
 check(reentrant.states.cpu.outputs.is_empty(),"callback fault leaves failed drivers released")
 reentrant.close()
 print("NEGATIVE REPLY CHECKS: ",checks," FAILURES: ",fails);quit(fails)
