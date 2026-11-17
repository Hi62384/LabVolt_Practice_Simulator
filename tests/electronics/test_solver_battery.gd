extends SceneTree
const Solver=preload("res://scripts/electronics_solver.gd")
func _initialize() -> void:
 var solver=Solver.new()
 var parts=[{"id":"cell","kind":"V","a":"p","b":"n","value":5.0,"resistance":.01,"capacity_ah":.01},{"id":"load","kind":"R","a":"p","b":"n","value":1000.0},{"id":"ideal","kind":"V","a":"x","b":"y","value":2.0,"resistance":.01}]
 var result=solver.solve(parts,[],3600.0)
 if not result.ok or result.mode.get("cell")!="BATTERY" or result.charge.has("ideal") or absf(float(result.charge.cell)-.5)>.001:
  push_error("Battery discharge or ideal source state is incorrect: %s"%result);quit(1);return
 result=solver.solve(parts,[],3600.0)
 if not result.ok or result.mode.get("cell")!="DEPLETED" or float(result.charge.cell)!=0.0:
  push_error("Battery did not deplete: %s"%result);quit(1);return
 print("PASS: battery drain and depletion preserve source states");quit()
