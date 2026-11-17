extends SceneTree
const Station=preload("res://scripts/dc_station.gd")
const Coupling=preload("res://scripts/dc_coupling.gd")
func _initialize() -> void:
 for prune in [false,true]:
  var source=Station.new();var load=Station.new()
  source.prune_disconnected_passives=prune;load.prune_disconnected_passives=prune
  source.master=true;source.channels[0].enabled=true;source.channels[0].voltage=5.0
  var links=[{"a":{"station":0,"port":"CH1+"},"b":{"station":1,"port":"R1a"}},{"a":{"station":0,"port":"CH1-"},"b":{"station":1,"port":"R1b"}}]
  for i in 8:Coupling.step([source,load],links,.0005)
  if absf(float(load.result.i.get("r0",0.0))-.005)>1e-6:push_error("Initial load incorrect");quit(1);return
  load.resistance[0]=2000.0
  for i in 3:Coupling.step([source,load],links,.0005)
  if absf(float(load.result.i.get("r0",0.0))-.0025)>1e-6:push_error("Changed load reused stale solution");quit(1);return
 var idle_a=Station.new();var idle_b=Station.new()
 var open_links=[{"a":{"station":0,"port":"GEN"},"b":{"station":1,"port":"GEN"}}]
 Coupling.step([idle_a,idle_b],open_links,.0005)
 if idle_a.solver.time<=0.0 or idle_b.solver.time<=0.0:push_error("Open linked benches failed to advance");quit(1);return
 print("PASS: full and pruned coupled DC load tracks direct resistance changes")
 quit()
