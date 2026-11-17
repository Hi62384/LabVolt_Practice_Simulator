extends SceneTree

class CountingBench extends "res://scripts/dc_station.gd":
 var step_count := 0
 var last_dt := 0.0
 func step(dt := .0005) -> void:
  step_count += 1
  last_dt = dt
  super.step(dt)

func _initialize() -> void:
 call_deferred("run")

func run() -> void:
 var game=load("res://scenes/Main.tscn").instantiate()
 root.add_child(game)
 for i in 4: await process_frame
 var dc=game.dc_lab
 dc.set_process(false)
 var idle=CountingBench.new()
 dc.benches[1]=idle
 var active=CountingBench.new()
 active.generator.enabled=true
 dc.benches[2]=active
 dc.external_links=[
  {"a":{"station":0,"port":"R1a"},"b":{"station":dc.AC_OFFSET,"port":"PV_A"}},
  {"a":{"station":0,"port":"R1b"},"b":{"station":dc.AC_OFFSET,"port":"PV_N"}}
 ]
 var bridge=dc.ac_bridges[0]
 bridge.lab.powered=true
 bridge.lab.level=.1
 dc.accumulator=0.0
 var start: float=bridge.solver.time
 dc._process(.02)
 if idle.step_count!=1 or absf(idle.last_dt-.02)>.000001:
  push_error("Unrelated idle bench should update once per frame; got %d steps at %s"%[idle.step_count,idle.last_dt]);quit(1);return
 if active.step_count<1:
  push_error("Unrelated active bench was skipped");quit(1);return
 if bridge.solver.time<=start or not bridge.linked:
  push_error("Linked AC circuit did not advance");quit(1);return
 print("PASS: connected AC simulation advances while unrelated idle bench updates once")
 quit()
