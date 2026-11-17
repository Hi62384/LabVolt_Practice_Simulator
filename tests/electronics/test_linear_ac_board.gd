extends SceneTree
const Lab=preload("res://scripts/lab_state.gd")
const Bridge=preload("res://scripts/ac_supply_bridge.gd")
const Station=preload("res://scripts/dc_station.gd")
const Board=preload("res://scripts/breadboard_model.gd")
const Coupling=preload("res://scripts/dc_coupling.gd")
func fixture(fast: bool) -> Dictionary:
 var lab=Lab.new();var ac=Bridge.new(lab);lab.initialize(ac.available_ports(),{})
 lab.powered=true;lab.level=.2;lab.recalculate()
 var dc=Station.new();dc.fast_linear_ac_enabled=fast;dc.portable_slot=true
 dc.board=Board.empty();dc.board.ports=["A1","A2","F1","F2"]
 dc.board.parts=[{"id":"load","type":"r1000","a":"A1","b":"A2"}]
 var links=[{"a":{"station":0,"port":"B1"},"b":{"station":1,"port":"PV_A"}},{"a":{"station":0,"port":"B2"},"b":{"station":1,"port":"PV_N"}}]
 return {"lab":lab,"ac":ac,"dc":dc,"links":links}
func _initialize() -> void:
 var slow=fixture(false);var fast=fixture(true)
 for i in 300:
  for item in [slow,fast]:Coupling.step([item.dc,item.ac],item.links,.0005)
  if not slow.dc.result.ok or not fast.dc.result.ok:push_error("Board solve failed");quit(1);return
  if absf(float(slow.dc.result.i.get("board/load",0))-float(fast.dc.result.i.get("board/load",0)))>1e-7:push_error("Board current mismatch at %d"%i);quit(1);return
 if fast.dc.linear_ac_cache.is_empty() or not fast.dc.linear_ac_cache.get("eligible",true):push_error("Passive board missed fast path");quit(1);return
 var plan=Coupling.linear_frame_plan([fast.dc,fast.ac],fast.links,Coupling.groups_for(2,fast.links),.0005)
 if plan.is_empty():push_error("Board frame plan missing");quit(1);return
 fast.dc.revision+=1
 if Coupling.linear_frame_step(plan,[fast.dc,fast.ac],.0005):push_error("Board edit did not stop frame plan");quit(1);return
 for item in [slow,fast]:
  item.dc.board.parts.append({"id":"led1","type":"led","a":"A1","b":"A2"});item.dc.board_epoch+=1
 for i in 200:
  for item in [slow,fast]:Coupling.step([item.dc,item.ac],item.links,.0005)
  if absf(float(slow.dc.result.i["board/led1"])-float(fast.dc.result.i["board/led1"]))>1e-6:push_error("LED board mismatch");quit(1);return
 if not fast.dc.linear_ac_cache.get("piecewise",false):push_error("Single LED board missed fast path");quit(1);return
 for item in [slow,fast]:
  item.dc.board.parts.append({"id":"led2","type":"led","a":"A2","b":"A1"});item.dc.board_epoch+=1
 for i in 400:
  for item in [slow,fast]:Coupling.step([item.dc,item.ac],item.links,.0005)
  for id in ["board/led1","board/led2"]:
   if absf(float(slow.dc.result.i[id])-float(fast.dc.result.i[id]))>1e-6:push_error("Two-LED board mismatch %s at %d"%[id,i]);quit(1);return
 if not fast.dc.linear_ac_cache.get("piecewise",false) or fast.dc.linear_ac_cache.diodes.size()!=2:push_error("Two-LED board missed fast path");quit(1);return
 fast.dc.board.parts.append({"id":"led3","type":"led","a":"F1","b":"F2"});fast.dc.board_epoch+=1
 Coupling.step([fast.dc,fast.ac],fast.links,.0005)
 if fast.dc.linear_ac_cache.get("eligible",true):push_error("Three-diode board did not fall back");quit(1);return
 print("LINEAR AC BOARD PASS");quit()



