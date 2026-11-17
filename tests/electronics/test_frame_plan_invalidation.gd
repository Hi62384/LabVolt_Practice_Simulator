extends SceneTree
func _initialize() -> void:call_deferred("run")
func run() -> void:
 var game=load("res://scenes/Main.tscn").instantiate();root.add_child(game)
 for i in 4:await process_frame
 var dc=game.dc_lab;dc.set_process(false);dc.simulation_budget_usec=10000
 dc.external_links=[{"a":{"station":0,"port":"R1a"},"b":{"station":dc.AC_OFFSET,"port":"PV_A"}},{"a":{"station":0,"port":"R1b"},"b":{"station":dc.AC_OFFSET,"port":"PV_N"}}]
 dc.refresh_link_flags()
 var bench=dc.benches[0];var bridge=dc.ac_bridges[0]
 bridge.lab.powered=true;bridge.lab.level=.1;bridge.lab.recalculate()
 dc._process(.02);dc._process(.02)
 if bench.linear_ac_cache.is_empty() or not bench.linear_ac_cache.get("eligible",true):push_error("Initial frame cache missing");quit(1);return
 var start: float=bridge.solver.time;dc._process(.02)
 if bridge.solver.time<=start:push_error("Cached frame did not advance");quit(1);return
 bridge.lab.frequency=47.0;dc._process(.02)
 if float(bench.linear_ac_cache.get("frequency",0))!=47.0:push_error("Frequency edit did not rebuild frame cache");quit(1);return
 bench.resistance[0]=500.0;dc._process(.02)
 if float(bench.linear_ac_cache.key[4][0])!=500.0:push_error("Resistance edit did not rebuild frame cache");quit(1);return
 bridge.lab.powered=false;dc._process(.02)
 if bridge.result.get("i",{}).has("PV_A") and absf(float(bridge.result.i.PV_A))>1e-9:push_error("Powered-off circuit kept stale source current");quit(1);return
 print("PASS: frame plan reuses stable topology and invalidates after frequency, load and power edits");quit()
