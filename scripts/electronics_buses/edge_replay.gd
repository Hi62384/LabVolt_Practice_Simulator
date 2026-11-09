extends RefCounted
## Core adapter only: replays native edges into the caller's EXISTING electrical solver.
## callback(dt,state) must settle protocol outputs at dt=0 without advancing time.
static func replay(previous: Dictionary,current: Dictionary,hz: float,solve: Callable) -> Dictionary:
 if not is_finite(hz) or hz<=0 or not solve.is_valid():return {"ok":false,"error":"Invalid native electrical replay callback/clock"}
 var start := int(previous.get("cycles",0));var end := int(current.get("cycles",start))
 if end<start:start=0 # Reset/power transition; host epoch guard owns identity.
 var cursor := start
 var state := previous.duplicate(true);state.powered=current.get("powered",false)
 if not state.get("outputs") is Dictionary:state.outputs={}
 if not state.get("pulls") is Dictionary:state.pulls={}
 var edges: int=0
 for event in current.get("events",[]):
  if event.get("type")!="gpio":continue
  var at := int(event.get("cycle",start));var pin := str(event.get("pin",""));var level := int(event.get("state",2))
  if at<cursor or at>end or pin.is_empty() or level not in [0,1,2,3,4,5]:return {"ok":false,"error":"Invalid/out-of-order native GPIO edge"}
  if at>cursor:solve.call(float(at-cursor)/hz,state.duplicate(true));cursor=at
  state.outputs.erase(pin);state.pulls.erase(pin)
  if level in [0,1]:state.outputs[pin]=level
  elif level in [3,4]:state.pulls[pin]="up" if level==3 else "down"
  solve.call(0.,state.duplicate(true));edges+=1
 if end>cursor:solve.call(float(end-cursor)/hz,state.duplicate(true))
 # The final state also includes hardware modes that need not generate a GPIO edge.
 solve.call(0.,current.duplicate(true))
 return {"ok":true,"elapsed":float(end-start)/hz,"edges":edges,"barrier":current.get("bus_barrier",false)}
